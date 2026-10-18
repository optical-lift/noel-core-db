-- Build 5: one-time worker-accepted standing assignment authority.
-- Employee-only v1: contractor seat support is NOT present in the live schema.
-- An offer is not consent. Consent authorizes future in-scope assignments,
-- NOT automatic Worker Day scheduling, delivery/read, or completion.
BEGIN;
CREATE TABLE atlas.company_work_standing_assignment_scopes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
  ledger_id uuid NOT NULL REFERENCES atlas.ledgers(id),
  worker_membership_id uuid NOT NULL REFERENCES atlas.organization_memberships(id),
  worker_person_id uuid NOT NULL REFERENCES reality.entities(id),
  employee_seat_id uuid NOT NULL REFERENCES atlas.organization_employee_seats(id),
  position_id uuid NOT NULL REFERENCES atlas.organization_positions(id),
  position_appointment_id uuid NOT NULL REFERENCES atlas.organization_position_appointments(id),
  organization_unit_id uuid NOT NULL,
  proposed_by_person_id uuid NOT NULL REFERENCES reality.entities(id),
  proposed_by_membership_id uuid NOT NULL REFERENCES atlas.organization_memberships(id),
  proposal_terms text NOT NULL CHECK (char_length(btrim(proposal_terms)) BETWEEN 30 AND 3000),
  scope_state text NOT NULL DEFAULT 'proposed'
    CHECK (scope_state IN ('proposed','active','declined','revoked')),
  proposed_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  accepted_by_person_id uuid REFERENCES reality.entities(id),
  declined_at timestamptz,
  revoked_at timestamptz,
  revoked_by_person_id uuid REFERENCES reality.entities(id),
  revocation_reason text,
  valid_until timestamptz,
  CHECK ((scope_state='proposed' AND accepted_at IS NULL AND declined_at IS NULL AND revoked_at IS NULL)
      OR (scope_state='active' AND accepted_at IS NOT NULL AND accepted_by_person_id=worker_person_id AND revoked_at IS NULL)
      OR (scope_state='declined' AND declined_at IS NOT NULL AND accepted_at IS NULL)
      OR (scope_state='revoked' AND revoked_at IS NOT NULL)),
  CHECK(valid_until IS NULL OR valid_until>proposed_at)
);
CREATE UNIQUE INDEX company_work_standing_assignment_current_v1
  ON atlas.company_work_standing_assignment_scopes
  (organization_id,ledger_id,worker_membership_id,position_id)
  WHERE scope_state IN ('proposed','active');
REVOKE ALL ON atlas.company_work_standing_assignment_scopes FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.propose_company_work_standing_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_membership_id uuid,
 p_position_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_owner_person uuid;
 v_manager_membership uuid;
 v_worker atlas.organization_memberships%ROWTYPE;
 v_employee_seat uuid;
 v_appointment uuid;
 v_unit uuid;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
BEGIN
 IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL OR
   p_worker_membership_id IS NULL OR p_position_id IS NULL OR v_terms IS NULL OR
   length(v_terms) NOT BETWEEN 30 AND 3000 OR
   (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'Exact worker, Ledger, Position, reasonable terms and future expiry required'
    USING ERRCODE='22023';
 END IF;
 v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 v_manager_membership:=atlas.current_effective_organization_membership_v1(p_organization_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_memberships m
   WHERE m.id=v_manager_membership AND m.organization_id=p_organization_id
     AND m.person_id=v_owner_person AND m.role='owner' AND m.active) THEN
   RAISE EXCEPTION 'Institutional manager membership not verified' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_worker FROM atlas.organization_memberships m
 WHERE m.id=p_worker_membership_id AND m.organization_id=p_organization_id
   AND m.person_id IS NOT NULL
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now());
 IF v_worker.id IS NULL OR v_worker.person_id=v_owner_person THEN
   RAISE EXCEPTION 'Distinct active canonical employee membership required'
    USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM reality.entities e
    WHERE e.id=v_worker.person_id AND e.entity_kind='person' AND e.identity_state='canonical') THEN
   RAISE EXCEPTION 'Canonical worker Person required' USING ERRCODE='23514';
 END IF;
 SELECT s.id INTO v_employee_seat FROM atlas.organization_employee_seats s
 WHERE s.organization_membership_id=v_worker.id AND s.organization_id=p_organization_id
   AND s.status='active' AND s.seat_class='employee' AND s.ended_at IS NULL;
 IF v_employee_seat IS NULL THEN
   RAISE EXCEPTION 'Active employee seat required; contractor service scope uses separate governed lane'
      USING ERRCODE='23514';
 END IF;
 SELECT p.organization_unit_id,a.id INTO v_unit,v_appointment
 FROM atlas.organization_positions p JOIN atlas.organization_position_appointments a
    ON a.position_id=p.id AND a.organization_membership_id=v_worker.id
 WHERE p.id=p_position_id AND p.organization_id=p_organization_id AND p.status='active'
    AND a.organization_id=p_organization_id AND a.status='active'
    AND a.ends_at IS NULL AND a.begins_at<=now();
 IF v_appointment IS NULL THEN
   RAISE EXCEPTION 'Verified current Position appointment required'
      USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.company_work_standing_assignment_scopes(
   organization_id,ledger_id,worker_membership_id,worker_person_id,employee_seat_id,
   position_id,position_appointment_id,organization_unit_id,
   proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES(p_organization_id,p_ledger_id,v_worker.id,v_worker.person_id,v_employee_seat,
   p_position_id,v_appointment,v_unit,v_owner_person,v_manager_membership,v_terms,p_valid_until)
 RETURNING * INTO v_scope;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
    'state','proposed','scopeId',v_scope.id,'organizationId',p_organization_id,
    'nativeLedgerId',p_ledger_id,'workerPersonId',v_worker.person_id,
    'positionId',p_position_id,'requiresWorkerConsent',true,'assignmentCreated',false);
END
$fn$;

CREATE FUNCTION atlas.respond_company_work_standing_scope_self_api_v1(
 p_scope_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_decision text:=lower(btrim(coalesce(p_decision,'')));
BEGIN
 IF auth.uid() IS NULL OR v_person IS NULL OR p_scope_id IS NULL OR
    v_decision NOT IN('accept','decline') THEN
   RAISE EXCEPTION 'Authenticated worker Person and explicit scope decision required'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
 WHERE id=p_scope_id FOR UPDATE;
 IF v_scope.id IS NULL OR v_scope.worker_person_id IS DISTINCT FROM v_person
    OR v_scope.scope_state<>'proposed' THEN
   RAISE EXCEPTION 'Scope proposal unavailable or already resolved' USING ERRCODE='42501';
 END IF;
 IF v_decision='decline' THEN
   UPDATE atlas.company_work_standing_assignment_scopes
    SET scope_state='declined',declined_at=now() WHERE id=v_scope.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
     'state','declined','scopeId',v_scope.id,'standingAuthorityEstablished',false);
 END IF;
 IF (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
 OR NOT EXISTS(
 SELECT 1 FROM atlas.organization_memberships m
 JOIN atlas.organization_employee_seats s ON s.id=v_scope.employee_seat_id
   AND s.organization_membership_id=m.id AND s.organization_id=m.organization_id
 JOIN atlas.organization_position_appointments a ON a.id=v_scope.position_appointment_id
   AND a.organization_membership_id=m.id AND a.position_id=v_scope.position_id
 JOIN atlas.organization_positions p ON p.id=v_scope.position_id
 WHERE m.id=v_scope.worker_membership_id AND m.person_id=v_person
   AND m.organization_id=v_scope.organization_id
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
   AND s.seat_class='employee' AND s.status='active' AND s.ended_at IS NULL
   AND a.status='active' AND a.ends_at IS NULL
   AND p.status='active' AND p.organization_unit_id=v_scope.organization_unit_id)
 THEN RAISE EXCEPTION 'Original role, position and employee seat no longer support consent'
     USING ERRCODE='23514'; END IF;
 UPDATE atlas.company_work_standing_assignment_scopes SET scope_state='active',
   accepted_at=now(),accepted_by_person_id=v_person WHERE id=v_scope.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
   'state','active','scopeId',v_scope.id,'standingAuthorityEstablished',true,
   'personConsentRecorded',true,'workAssignmentCreated',false);
END
$fn$;

CREATE FUNCTION atlas.revoke_company_work_standing_scope_self_api_v1(
 p_scope_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL OR v_person IS NULL OR p_scope_id IS NULL OR
   v_reason IS NULL OR length(v_reason)>1200 THEN
   RAISE EXCEPTION 'Authenticated Person, scope and revocation reason required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes WHERE id=p_scope_id FOR UPDATE;
 IF v_scope.id IS NULL OR v_scope.scope_state NOT IN ('proposed','active') THEN
   RAISE EXCEPTION 'No active/proposed scope to revoke' USING ERRCODE='23514';
 END IF;
 IF v_person<>v_scope.worker_person_id THEN
   PERFORM atlas.company_work_native_ledger_owner_self_v1(v_scope.organization_id,v_scope.ledger_id);
   IF v_person IS DISTINCT FROM v_scope.proposed_by_person_id THEN
      RAISE EXCEPTION 'Worker or original Ledger owner only' USING ERRCODE='42501';
   END IF;
 END IF;
 UPDATE atlas.company_work_standing_assignment_scopes SET scope_state='revoked',
   revoked_at=now(),revoked_by_person_id=v_person,revocation_reason=v_reason WHERE id=v_scope.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
  'state','revoked','scopeId',v_scope.id,'newAutoAssignmentsPermitted',false);
END
$fn$;

CREATE FUNCTION atlas.company_work_standing_scopes_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_incoming jsonb;
 v_outgoing jsonb;
BEGIN
 IF auth.uid() IS NULL OR v_person IS NULL THEN
   RAISE EXCEPTION 'Canonical signed-in Person required' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,'ledgerId',s.ledger_id,
   'positionId',s.position_id,'positionTitle',p.display_title,
   'organizationUnitId',s.organization_unit_id,'proposalTerms',s.proposal_terms,
   'state',s.scope_state,'validUntil',s.valid_until
 ) ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_incoming
 FROM atlas.company_work_standing_assignment_scopes s
 JOIN atlas.organization_positions p ON p.id=s.position_id
 WHERE s.worker_person_id=v_person AND s.scope_state IN ('proposed','active')
 AND EXISTS(SELECT 1 FROM atlas.organization_memberships m
   JOIN atlas.organization_employee_seats seat
     ON seat.id=s.employee_seat_id AND seat.organization_membership_id=m.id
   WHERE m.id=s.worker_membership_id AND m.person_id=v_person
     AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
     AND seat.status='active' AND seat.ended_at IS NULL);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,'ledgerId',s.ledger_id,
   'workerPersonId',s.worker_person_id,'positionId',s.position_id,
   'state',s.scope_state,'acceptedAt',s.accepted_at,'validUntil',s.valid_until
 ) ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_outgoing
 FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.proposed_by_person_id=v_person AND s.scope_state IN('proposed','active');
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
   'incoming',v_incoming,'outgoing',v_outgoing,
   'workerAcceptedScopeIsNotWorkerDayReceipt',true);
END
$fn$;

CREATE FUNCTION atlas.manager_assign_company_work_under_standing_scope_self_api_v1(
 p_work_item_id uuid,p_scope_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_owner uuid;
 v_actor_membership uuid;
 v_new atlas.work_allocations%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL OR p_work_item_id IS NULL OR p_scope_id IS NULL OR
    v_reason IS NULL OR length(v_reason)>1200 THEN
    RAISE EXCEPTION 'Work, exact scope, signed-in owner and reason required' USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
   WHERE id=p_scope_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' OR v_scope.id IS NULL
   OR v_scope.scope_state<>'active' OR v_scope.accepted_at IS NULL
   OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
   OR v_work.organization_id<>v_scope.organization_id OR
      v_work.organization_unit_id IS DISTINCT FROM v_scope.organization_unit_id THEN
   RAISE EXCEPTION 'Open in-scope Company Work and accepted standing agreement required'
     USING ERRCODE='23514';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(v_work.organization_id,v_scope.ledger_id);
 v_actor_membership:=atlas.current_effective_organization_membership_v1(v_work.organization_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_memberships m
   WHERE m.id=v_actor_membership AND m.organization_id=v_work.organization_id
     AND m.person_id=v_owner AND m.role='owner' AND m.active) THEN
   RAISE EXCEPTION 'Owner manager not established' USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
   WHERE o.work_item_id=v_work.id AND o.offer_state='offered') THEN
   RAISE EXCEPTION 'Withdraw or resolve the original individual offer first'
      USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
    WHERE rel.work_item_id=v_work.id AND rel.organization_id=v_work.organization_id
      AND rel.ledger_id=v_scope.ledger_id AND rel.attribution_state='active'
      AND (rel.evidence_kind='owner_attested' OR
         (rel.evidence_kind='source_verified' AND EXISTS(
           SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(v_work.id,v_scope.ledger_id) proof
           WHERE proof.source_schema=rel.source_schema AND proof.source_table=rel.source_table
             AND proof.source_id=rel.source_id)))) THEN
   RAISE EXCEPTION 'Exact native Ledger work link not proven'
    USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=v_work.id
    AND a.state='active' AND a.allocation_role='responsible') THEN
   RAISE EXCEPTION 'Work already has a responsible worker' USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.work_allocations (
   organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
   allocation_role,state,allocated_at,establishment_basis_kind,establishment_basis,metadata
 ) VALUES(v_work.organization_id,v_work.id,v_scope.worker_membership_id,v_actor_membership,
   'responsible','active',now(),'delegated_under_standing_scope',
   jsonb_build_object(
     'contractVersion','exact_work_responsibility_establishment_v2',
     'basisKind','delegated_under_standing_scope',
     'organizationId',v_work.organization_id,'workItemId',v_work.id,
     'assigneeMembershipId',v_scope.worker_membership_id,
     'actorMembershipId',v_actor_membership,
     'nativeLedgerId',v_scope.ledger_id,'positionId',v_scope.position_id,
     'scopeId',v_scope.id,'scopeAcceptedAt',v_scope.accepted_at,
     'establishedAt',now()
   ),
   jsonb_build_object('source','manager_delegated_under_accepted_standing_scope_v1',
     'managerPersonId',v_owner,'scopeId',v_scope.id,'reason',v_reason,
     'workerDayReceiptProven',false,'workerReadProven',false)
 ) RETURNING * INTO v_new;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','company_work_delegated_assignment_v1',
   'state','assigned','workItemId',v_work.id,'allocationId',v_new.id,
   'ledgerId',v_scope.ledger_id,'scopeId',v_scope.id,
   'responsibleMembershipId',v_scope.worker_membership_id,
   'workerAcceptancePerTaskRequired',false,
   'workerDayPlacementProven',false,'workerReadProven',false);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim an employee consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_employee_seats seat
        on seat.organization_membership_id=worker.id and seat.organization_id=worker.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and seat.id=scope.employee_seat_id and seat.status='active'
        and seat.seat_class='employee' and seat.ended_at is null
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted active exact-Ledger employment scope cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$
;

-- All mutation and reads must go through authenticated self-bound RPCs.
REVOKE ALL ON FUNCTION atlas.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.respond_company_work_standing_scope_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.revoke_company_work_standing_scope_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.company_work_standing_scopes_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.respond_company_work_standing_scope_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.revoke_company_work_standing_scope_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.company_work_standing_scopes_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text) TO authenticated;

CREATE FUNCTION public.propose_company_work_standing_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_membership_id uuid,
 p_position_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.propose_company_work_standing_scope_self_api_v1(
 p_organization_id,p_ledger_id,p_worker_membership_id,p_position_id,p_terms,p_valid_until); $fn$;
CREATE FUNCTION public.respond_company_work_standing_scope_self_api_v1(p_scope_id uuid,p_decision text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.respond_company_work_standing_scope_self_api_v1(p_scope_id,p_decision); $fn$;
CREATE FUNCTION public.revoke_company_work_standing_scope_self_api_v1(p_scope_id uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.revoke_company_work_standing_scope_self_api_v1(p_scope_id,p_reason); $fn$;
CREATE FUNCTION public.company_work_standing_scopes_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.company_work_standing_scopes_self_api_v1(); $fn$;
CREATE FUNCTION public.manager_assign_company_work_under_standing_scope_self_api_v1(
 p_work_item_id uuid,p_scope_id uuid,p_reason text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.manager_assign_company_work_under_standing_scope_self_api_v1(p_work_item_id,p_scope_id,p_reason); $fn$;

REVOKE ALL ON FUNCTION public.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.respond_company_work_standing_scope_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.revoke_company_work_standing_scope_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.company_work_standing_scopes_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.propose_company_work_standing_scope_self_api_v1(uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_company_work_standing_scope_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_company_work_standing_scope_self_api_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.company_work_standing_scopes_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.manager_assign_company_work_under_standing_scope_self_api_v1(uuid,uuid,text) TO authenticated;
COMMIT;

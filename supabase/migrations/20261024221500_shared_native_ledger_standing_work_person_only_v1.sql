-- Candidate: stop needing a fake owner/consultant/employee member row
-- to exercise already-existing root Ledger governance of standing work.
BEGIN;
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ALTER COLUMN proposed_by_membership_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION atlas.propose_native_ledger_standing_scope_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid, p_organization_unit_id uuid, p_coverage_mode text, p_operation_class text, p_terms text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_owner_membership uuid;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
 v_class text:=nullif(btrim(coalesce(p_operation_class,'')),'');
 v_mode text:=lower(btrim(coalesce(p_coverage_mode,'')));
BEGIN
 IF auth.uid() IS NULL OR p_worker_person_id IS NULL OR
    (v_mode IS NULL OR v_mode NOT IN ('operation_class','ledger_all_work')) OR
    (v_mode='operation_class' AND (p_organization_unit_id IS NULL OR
       v_class IS NULL OR length(v_class) NOT BETWEEN 2 AND 120)) OR
    (v_mode='ledger_all_work' AND (p_organization_unit_id IS NOT NULL OR v_class IS NOT NULL)) OR
    v_terms IS NULL OR
    length(v_terms) NOT BETWEEN 30 AND 3000 OR
    (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'A canonical Person, operating unit, bounded terms and valid expiry are required'
      USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner=p_worker_person_id THEN
   RAISE EXCEPTION 'Owner self-work uses a separate authorized path' USING ERRCODE='23514';
 END IF;
 -- company_work_native_ledger_owner_self_v1 already enforces actual
 -- signed Principal and root-governing authority over the exact Ledger.
 -- No Organization Membership or employment category can add authority.
 v_owner_membership:=NULL;
 IF NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,p_worker_person_id) THEN
   RAISE EXCEPTION 'Active exact native Ledger Person connection required' USING ERRCODE='23514';
 END IF;
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.organization_units u
     WHERE u.id=p_organization_unit_id AND u.organization_id=p_organization_id
       AND u.status='active') THEN
   RAISE EXCEPTION 'Active exact organization unit required' USING ERRCODE='23514';
 END IF;
 -- One recorded operation class, not unrelated Work in the same unit.
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.work_items work
   WHERE work.organization_id=p_organization_id
     AND work.organization_unit_id=p_organization_unit_id
     AND work.operation_class=v_class) THEN
   RAISE EXCEPTION 'Standing responsibility class must exist in this operating unit'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_standing_assignment_scopes s
     WHERE s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
       AND s.worker_person_id=p_worker_person_id
       AND s.organization_unit_id IS NOT DISTINCT FROM p_organization_unit_id
       AND s.covered_operation_class IS NOT DISTINCT FROM v_class
       AND s.coverage_mode=v_mode
       AND s.scope_state IN ('proposed','active')
       AND (s.valid_until IS NULL OR s.valid_until>now())) THEN
   RAISE EXCEPTION 'A standing scope already exists for this exact Person and unit'
       USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.company_work_standing_assignment_scopes(
   organization_id,ledger_id,worker_membership_id,worker_person_id,
   position_id,position_appointment_id,organization_unit_id,
   covered_operation_class,coverage_mode,proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES (
   p_organization_id,p_ledger_id,NULL,p_worker_person_id,
   NULL,NULL,p_organization_unit_id,
   v_class,v_mode,v_owner,v_owner_membership,v_terms,p_valid_until
 ) RETURNING * INTO v_scope;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','native_ledger_standing_scope_v1',
   'scopeId',v_scope.id,'state','proposed','organizationId',p_organization_id,
   'ledgerId',p_ledger_id,'workerPersonId',p_worker_person_id,
   'organizationUnitId',p_organization_unit_id,'operationClass',v_class,
   'coverageMode',v_mode,
   'workerConsentRecorded',false,'workAssigned',false,'employeeSeatRequired',false);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(p_work_item_id uuid, p_scope_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_owner uuid;
 v_owner_membership uuid;
 v_new atlas.work_allocations%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL OR p_work_item_id IS NULL OR p_scope_id IS NULL OR
    v_reason IS NULL OR length(v_reason)>1200 THEN
    RAISE EXCEPTION 'Exact Work, established scope, actor and reason required'
      USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
   WHERE id=p_scope_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' OR v_scope.id IS NULL OR
   v_scope.scope_state<>'active' OR v_scope.accepted_at IS NULL OR
   v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id OR
   v_scope.worker_membership_id IS NOT NULL OR
   (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now()) OR
   v_work.organization_id<>v_scope.organization_id OR
   (v_scope.coverage_mode='operation_class' AND
      (v_work.organization_unit_id IS DISTINCT FROM v_scope.organization_unit_id OR
       v_work.operation_class IS DISTINCT FROM v_scope.covered_operation_class)) OR
   v_scope.coverage_mode NOT IN ('operation_class','ledger_all_work') THEN
   RAISE EXCEPTION 'Open Work and currently accepted Person/Ledger standing scope required'
     USING ERRCODE='23514';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
   v_work.organization_id,v_scope.ledger_id);
 -- Signed root Ledger governance was checked by the exact native owner
 -- function. An outdated organization member role is not additional proof.
 v_owner_membership:=NULL;
 IF v_scope.proposed_by_person_id IS DISTINCT FROM v_owner OR
   NOT atlas.person_has_native_ledger_connection_v1(
     v_work.organization_id,v_scope.ledger_id,v_scope.worker_person_id) THEN
   RAISE EXCEPTION 'Issuing authority or receiver Ledger connection changed'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
   WHERE o.work_item_id=v_work.id AND o.offer_state='offered') THEN
   RAISE EXCEPTION 'Resolve or withdraw pending individual offers first' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
   WHERE rel.organization_id=v_work.organization_id AND rel.work_item_id=v_work.id
     AND rel.ledger_id=v_scope.ledger_id AND rel.attribution_state='active'
     AND (rel.evidence_kind='owner_attested' OR
       (rel.evidence_kind='source_verified' AND EXISTS(
         SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
           v_work.id,v_scope.ledger_id) proof
         WHERE proof.source_schema=rel.source_schema AND
           proof.source_table=rel.source_table AND proof.source_id=rel.source_id)))) THEN
   RAISE EXCEPTION 'Work does not have proven exact native Ledger relevance'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=v_work.id
     AND a.state='active' AND a.allocation_role='responsible') THEN
   RAISE EXCEPTION 'An active responsible Person already owns this Work' USING ERRCODE='23514';
 END IF;
 -- Same ordinary worker-attestation reporting contract as accepted Person
 -- offers. Never override an existing source-specific result contract.
 IF v_work.result_contract_key IS NULL AND
   v_work.source_object_type IN ('personal_dated_task','legacy_task') THEN
   IF NOT EXISTS(SELECT 1 FROM atlas.work_result_contract_policies policy
     WHERE policy.contract_key='ordinary_company_work_worker_attestation_v1'
       AND policy.active AND policy.source_domain='organization'
       AND policy.acceptance_mode='worker_attestation') THEN
     RAISE EXCEPTION 'Ordinary worker-attestation result policy is unavailable'
       USING ERRCODE='23514';
   END IF;
   INSERT INTO atlas.company_work_result_contract_bindings_v1(
     organization_id,ledger_id,work_item_id,actor_person_id,
     actor_membership_id,contract_key,reason
   ) VALUES (
     v_work.organization_id,v_scope.ledger_id,v_work.id,v_owner,
     v_owner_membership,'ordinary_company_work_worker_attestation_v1',
     'Direct Person assignment under accepted standing responsibility'
   );
   UPDATE atlas.work_items SET
     result_contract_key='ordinary_company_work_worker_attestation_v1',
     updated_at=now()
   WHERE id=v_work.id AND result_contract_key IS NULL;
 END IF;
 INSERT INTO atlas.work_allocations (
   organization_id,work_item_id,assignee_membership_id,
   assignee_canonical_person_id,assigned_by_membership_id,
   allocation_role,state,allocated_at,establishment_basis_kind,
   establishment_basis,metadata
 ) VALUES (
   v_work.organization_id,v_work.id,NULL,v_scope.worker_person_id,
   v_owner_membership,'responsible','active',now(),
   'delegated_under_standing_scope',
   jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','delegated_under_standing_scope',
      'organizationId',v_work.organization_id,'workItemId',v_work.id,
      'nativeLedgerId',v_scope.ledger_id,'scopeId',v_scope.id,
      'assigneePersonId',v_scope.worker_person_id,
      'scopeAcceptedAt',v_scope.accepted_at,
      'establishedAt',now()),
   jsonb_build_object(
     'source','assign_native_ledger_company_work_under_scope_owner_self_api_v1',
     'managerPersonId',v_owner,'reason',v_reason,'employeeSeatRequired',false,
     'workerDayReceiptProven',false,'workerReadProven',false)
 ) RETURNING * INTO v_new;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','native_ledger_direct_assignment_v1',
   'state','assigned','workItemId',v_work.id,'allocationId',v_new.id,
   'ledgerId',v_scope.ledger_id,'scopeId',v_scope.id,
   'operationClass',v_scope.covered_operation_class,
   'coverageMode',v_scope.coverage_mode,
   'responsiblePersonId',v_scope.worker_person_id,
   'workerAcceptancePerTaskRequired',false,'workerDayPlacementProven',false,
   'workerReadProven',false,'newWorkCreated',false);
END
$function$;

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
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake',
    'ledger_connection_direct_assignment'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.

  if v_kind='ledger_connection_direct_assignment' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>'source','')<>'ledger_connected_direct_assignment_v1'
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'nativeLedgerId','') is null
      or nullif(v_basis->>'senderPersonId','') is null
      or coalesce(v_basis->>'authorizationBasis','')<>'active_mutual_native_ledger_connections'
    then raise exception 'Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         (v_basis->>'senderPersonId')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
          and rel.attribution_state='active' and rel.evidence_kind='participant_attested'
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           and w.metadata->>'createdByPersonId'=v_basis->>'senderPersonId'
           and w.metadata->>'recipientPersonId'=new.assignee_canonical_person_id::text)
    then raise exception 'Connection-direct responsibility has no verified original Person and Ledger' using errcode='23514';end if;
    return new;
  end if;

  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id is not distinct from new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- Native Ledger standing agreement: canonical Person is the assignee,
  -- without invented Organization/employee membership. The original
  -- membership-based delegated branch below remains unchanged.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
      or (tg_op='INSERT' and new.assigned_by_membership_id is not null)
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'scopeId','') is null
      or nullif(v_basis->>'nativeLedgerId','') is null then
       raise exception 'Exact canonical Person standing-scope provenance required'
         using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_standing_assignment_scopes s
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=s.organization_id
      -- Native governing authority belongs to the verified Principal,
      -- not an Organization Membership/role label.
      join atlas.principals issuer
        on issuer.person_id=s.proposed_by_person_id
        and issuer.status='active'
      join atlas.principal_ledger_authorities grantor
        on grantor.principal_id=issuer.id and grantor.ledger_id=s.ledger_id
        and grantor.authority_kind='root_governing'
        and grantor.status='active'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
        and relevance.organization_id=s.organization_id
        and relevance.ledger_id=s.ledger_id
      where s.id::text=v_basis->>'scopeId'
        and s.proposed_by_person_id=atlas.current_person_id_v1()
        and s.organization_id=new.organization_id
        and s.ledger_id::text=v_basis->>'nativeLedgerId'
        and s.worker_person_id=new.assignee_canonical_person_id
        and s.worker_membership_id is null
        and s.scope_state='active' and s.accepted_at is not null
        and s.accepted_by_person_id=new.assignee_canonical_person_id
        and (s.valid_until is null or s.valid_until>now())
        and (s.coverage_mode='ledger_all_work' OR
          (s.coverage_mode='operation_class' AND
           work.organization_unit_id=s.organization_unit_id AND
           work.operation_class=s.covered_operation_class))
        and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              work.id,s.ledger_id) proof
            where proof.source_schema=relevance.source_schema
              and proof.source_table=relevance.source_table
              and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Accepted canonical Person standing scope is not current for exact Work'
         using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
      new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
      new.assignee_canonical_person_id) then
      raise exception 'Canonical responsible Person no longer connected to this Ledger'
        using errcode='23514';
    end if;
    return new;
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
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
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
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
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
$function$;
COMMIT;

-- Build 5: one canonical connection; Work authority comes from exact, accepted
-- institutional agreements, not employee/contractor classification.
-- Historical seat rows remain optional delivery adapters, not worker categories.
BEGIN;
ALTER TABLE atlas.company_work_standing_assignment_scopes
  ALTER COLUMN employee_seat_id DROP NOT NULL;
COMMENT ON COLUMN atlas.company_work_standing_assignment_scopes.employee_seat_id IS
  'Optional legacy delivery-seat provenance, not a condition of institutional connection or standing Work authority.';

CREATE OR REPLACE FUNCTION atlas.propose_company_work_standing_scope_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_membership_id uuid,
 p_position_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_owner_person uuid;
 v_manager_membership uuid;
 v_worker atlas.organization_memberships%ROWTYPE;
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
   RAISE EXCEPTION 'Distinct active canonical institutional connection required'
    USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM reality.entities e
    WHERE e.id=v_worker.person_id AND e.entity_kind='person' AND e.identity_state='canonical') THEN
   RAISE EXCEPTION 'Canonical worker Person required' USING ERRCODE='23514';
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
   organization_id,ledger_id,worker_membership_id,worker_person_id,
   position_id,position_appointment_id,organization_unit_id,
   proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES(p_organization_id,p_ledger_id,v_worker.id,v_worker.person_id,
   p_position_id,v_appointment,v_unit,v_owner_person,v_manager_membership,v_terms,p_valid_until)
 RETURNING * INTO v_scope;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
    'state','proposed','scopeId',v_scope.id,'organizationId',p_organization_id,
    'nativeLedgerId',p_ledger_id,'workerPersonId',v_worker.person_id,
    'positionId',p_position_id,'requiresWorkerConsent',true,'assignmentCreated',false);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.respond_company_work_standing_scope_self_api_v1(
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
 JOIN atlas.organization_position_appointments a ON a.id=v_scope.position_appointment_id
   AND a.organization_membership_id=m.id AND a.position_id=v_scope.position_id
 JOIN atlas.organization_positions p ON p.id=v_scope.position_id
 WHERE m.id=v_scope.worker_membership_id AND m.person_id=v_person
   AND m.organization_id=v_scope.organization_id
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
   AND a.status='active' AND a.ends_at IS NULL
   AND p.status='active' AND p.organization_unit_id=v_scope.organization_unit_id)
 THEN RAISE EXCEPTION 'Original connection and Position no longer support consent'
     USING ERRCODE='23514'; END IF;
 UPDATE atlas.company_work_standing_assignment_scopes SET scope_state='active',
   accepted_at=now(),accepted_by_person_id=v_person WHERE id=v_scope.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_standing_scope_v1',
   'state','active','scopeId',v_scope.id,'standingAuthorityEstablished',true,
   'personConsentRecorded',true,'workAssignmentCreated',false);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.company_work_standing_scopes_self_api_v1()
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
   WHERE m.id=s.worker_membership_id AND m.person_id=v_person
     AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
 AND m.organization_id=s.organization_id);
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

CREATE OR REPLACE FUNCTION atlas.offer_unallocated_company_work_self_api_v1(
  p_work_item_id uuid,p_ledger_id uuid,p_target_person_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_work atlas.work_items%ROWTYPE;
 v_actor_person uuid;
 v_actor_membership uuid;
 v_target_membership uuid;
 v_target_count int;
 v_existing atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_created atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501'; END IF;
 IF p_work_item_id IS NULL OR p_ledger_id IS NULL OR p_target_person_id IS NULL
   OR v_reason IS NULL OR length(v_reason)>1200 THEN
   RAISE EXCEPTION 'Exact Work, Ledger, target Person and reason required'
     USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_item_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' THEN
   RAISE EXCEPTION 'Open Company Work required' USING ERRCODE='22023';
 END IF;
 v_actor_person:=atlas.company_work_native_ledger_owner_self_v1(v_work.organization_id,p_ledger_id);
 SELECT atlas.current_effective_organization_membership_v1(v_work.organization_id) INTO v_actor_membership;
 IF v_actor_membership IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=v_actor_membership AND m.person_id=v_actor_person
      AND m.organization_id=v_work.organization_id) THEN
   RAISE EXCEPTION 'Owner institutional membership not established' USING ERRCODE='42501';
 END IF;
 IF p_target_person_id=v_actor_person THEN
   RAISE EXCEPTION 'Use self-adoption for your own work, not a delegated offer'
    USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance l
    WHERE l.work_item_id=v_work.id AND l.organization_id=v_work.organization_id
      AND l.ledger_id=p_ledger_id AND l.attribution_state='active'
      AND (l.evidence_kind='owner_attested' OR
       (l.evidence_kind='source_verified' AND EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(l.work_item_id,l.ledger_id) proof
        WHERE proof.source_schema=l.source_schema AND proof.source_table=l.source_table
          AND proof.source_id=l.source_id
       )))
 ) THEN
   RAISE EXCEPTION 'Verify exact native Ledger relevance before offering work'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(
    SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=v_work.id
      AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible' AND a.state='active'
 ) THEN RAISE EXCEPTION 'Already assigned; use responsibility transfer'
   USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(
   SELECT 1 FROM reality.entities e WHERE e.id=p_target_person_id
     AND e.entity_kind='person' AND e.identity_state='canonical'
 ) THEN RAISE EXCEPTION 'Target canonical Person required' USING ERRCODE='23514'; END IF;
 SELECT count(*)::int,(array_agg(m.id ORDER BY m.created_at,m.id))[1]
   INTO v_target_count,v_target_membership
 FROM atlas.organization_memberships m
 WHERE m.organization_id=v_work.organization_id AND m.person_id=p_target_person_id
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
;
 IF v_target_count<>1 THEN
   RAISE EXCEPTION 'Exactly one present canonical institutional connection required'
     USING ERRCODE='23514';
 END IF;
 SELECT * INTO v_existing
 FROM atlas.company_work_initial_responsibility_offers
 WHERE work_item_id=v_work.id AND offer_state='offered' FOR UPDATE;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.target_person_id<>p_target_person_id OR v_existing.ledger_id<>p_ledger_id THEN
     RAISE EXCEPTION 'Another offer is already pending for this Work'
       USING ERRCODE='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offer_v1',
    'state','offered','alreadyOffered',true,'offerId',v_existing.id,
    'workItemId',v_work.id,'ledgerId',p_ledger_id,'targetPersonId',p_target_person_id,
    'responsibilityChanged',false);
 END IF;
 INSERT INTO atlas.company_work_initial_responsibility_offers(
   organization_id,work_item_id,ledger_id,offered_by_person_id,
   offered_by_membership_id,target_person_id,target_membership_id,reason
 ) VALUES (v_work.organization_id,v_work.id,p_ledger_id,v_actor_person,
   v_actor_membership,p_target_person_id,v_target_membership,v_reason)
 RETURNING * INTO v_created;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offer_v1',
   'state','offered','alreadyOffered',false,'offerId',v_created.id,
   'workItemId',v_work.id,'ledgerId',p_ledger_id,'targetPersonId',p_target_person_id,
   'responsibilityChanged',false,'workerViewed',false,'scheduled',false);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.respond_unallocated_company_work_self_api_v1(
 p_offer_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_self uuid:=atlas.current_person_id_v1();
 v_offer atlas.company_work_initial_responsibility_offers%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_membership uuid;
 v_decision text:=lower(btrim(coalesce(p_decision,'')));
 v_receipt jsonb;
 v_alloc uuid;
 v_ready boolean;
BEGIN
 IF auth.uid() IS NULL OR v_self IS NULL THEN
   RAISE EXCEPTION 'Signed-in canonical Person required' USING ERRCODE='42501';
 END IF;
 IF v_decision NOT IN ('accepted','declined') OR p_offer_id IS NULL THEN
   RAISE EXCEPTION 'Accept or decline one exact offer' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_offer FROM atlas.company_work_initial_responsibility_offers
   WHERE id=p_offer_id FOR UPDATE;
 IF v_offer.id IS NULL OR v_offer.target_person_id<>v_self THEN
   RAISE EXCEPTION 'Offer unavailable to current Person' USING ERRCODE='42501';
 END IF;
 IF v_offer.offer_state<>'offered' THEN
   IF v_offer.offer_state=v_decision THEN
     RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
       'state',v_offer.offer_state,'offerId',v_offer.id,'workItemId',v_offer.work_item_id,
       'allocationId',v_offer.accepted_allocation_id,'alreadyResolved',true);
   END IF;
   RAISE EXCEPTION 'Offer already resolved' USING ERRCODE='23514';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||v_offer.work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items
   WHERE id=v_offer.work_item_id AND organization_id=v_offer.organization_id FOR UPDATE;
 v_membership:=atlas.current_effective_organization_membership_v1(v_offer.organization_id);
 IF v_membership IS NULL OR v_membership<>v_offer.target_membership_id THEN
   RAISE EXCEPTION 'Original worker membership must remain effective' USING ERRCODE='42501';
 END IF;
 IF v_decision='declined' THEN
   UPDATE atlas.company_work_initial_responsibility_offers
      SET offer_state='declined',resolved_at=now(),resolution_reason='recipient_declined'
       WHERE id=v_offer.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
     'state','declined','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
     'responsibilityChanged',false);
 END IF;
 SELECT (v_work.id IS NOT NULL AND v_work.work_state='open'
    AND NOT EXISTS(SELECT 1 FROM atlas.work_allocations a
      WHERE a.work_item_id=v_offer.work_item_id
       AND a.allocation_role='responsible' AND a.state='active')
    AND EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance l
       WHERE l.organization_id=v_offer.organization_id AND l.work_item_id=v_offer.work_item_id
         AND l.ledger_id=v_offer.ledger_id AND l.attribution_state='active'
         AND (l.evidence_kind='owner_attested' OR
          (l.evidence_kind='source_verified' AND EXISTS(
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(l.work_item_id,l.ledger_id) proof
            WHERE proof.source_schema=l.source_schema
              AND proof.source_table=l.source_table AND proof.source_id=l.source_id))))
)
 INTO v_ready;
 IF NOT coalesce(v_ready,false) THEN
   UPDATE atlas.company_work_initial_responsibility_offers
     SET offer_state='stale',resolved_at=now(),resolution_reason='eligibility_or_work_changed_before_uptake'
       WHERE id=v_offer.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
      'state','stale','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
      'responsibilityChanged',false);
 END IF;
 v_receipt:=atlas.set_company_work_responsibility_with_basis_internal_v2(
   v_offer.work_item_id,v_membership,v_membership,'self_adoption',
   jsonb_build_object('sourceKind','company_work_initial_responsibility_offer',
     'sourceId',v_offer.id,'nativeLedgerId',v_offer.ledger_id,
     'offeredByPersonId',v_offer.offered_by_person_id,
     'receiverPersonId',v_self),
   'receiver_accepted_initial_company_work_offer',
   jsonb_build_object('source','respond_unallocated_company_work_self_api_v1',
     'offerId',v_offer.id,'receiverUptake',true)
 );
 IF v_receipt->>'state' NOT IN ('established','unchanged')
    OR (v_receipt->>'workItemId')::uuid<>v_offer.work_item_id
    OR (v_receipt->>'assigneeMembershipId')::uuid<>v_membership THEN
    RAISE EXCEPTION 'Receiver established Work allocation not proven' USING ERRCODE='23514';
 END IF;
 v_alloc:=(v_receipt->>'allocationId')::uuid;
 UPDATE atlas.company_work_initial_responsibility_offers
   SET offer_state='accepted',resolved_at=now(),accepted_allocation_id=v_alloc,
       resolution_reason='receiver_accepted'
 WHERE id=v_offer.id;
 RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_response_v1',
   'state','accepted','offerId',v_offer.id,'workItemId',v_offer.work_item_id,
   'allocationId',v_alloc,'responsiblePersonId',v_self,'responsibilityChanged',true,
   'scheduled',false,'workerDayDeliveryProven',false);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.company_work_initial_offers_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_person uuid:=atlas.current_person_id_v1();
 v_incoming jsonb;
 v_outgoing jsonb;
BEGIN
 IF auth.uid() IS NULL THEN
   RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';
 END IF;
 IF v_person IS NULL THEN
   RETURN jsonb_build_object('ok',true,'contractVersion','company_work_initial_offers_self_v1',
      'state','person_binding_required','incoming','[]'::jsonb,'outgoing','[]'::jsonb);
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'offerId',o.id,'workItemId',o.work_item_id,'workTitle',w.title,
   'organizationId',o.organization_id,'ledgerId',o.ledger_id,
   'offeredByPersonId',o.offered_by_person_id,'offeredAt',o.offered_at,'reason',o.reason
 ) ORDER BY o.offered_at,o.id),'[]'::jsonb) INTO v_incoming
 FROM atlas.company_work_initial_responsibility_offers o
 JOIN atlas.work_items w ON w.id=o.work_item_id
 WHERE o.target_person_id=v_person AND o.offer_state='offered'
  AND EXISTS(SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=o.target_membership_id AND m.person_id=v_person
      AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now()))
;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'offerId',o.id,'workItemId',o.work_item_id,'workTitle',w.title,
   'organizationId',o.organization_id,'ledgerId',o.ledger_id,
   'targetPersonId',o.target_person_id,'offeredAt',o.offered_at,'reason',o.reason
 ) ORDER BY o.offered_at,o.id),'[]'::jsonb) INTO v_outgoing
 FROM atlas.company_work_initial_responsibility_offers o
 JOIN atlas.work_items w ON w.id=o.work_item_id
 WHERE o.offered_by_person_id=v_person AND o.offer_state='offered'
   AND atlas.is_organization_owner(o.organization_id);
 RETURN jsonb_build_object('ok',true,
   'contractVersion','company_work_initial_offers_self_v1',
   'state','ready','incoming',v_incoming,'outgoing',v_outgoing,
   'offerIsNotAssignment',true,'workerViewedOrDeliveredNotProven',true);
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
$function$
;

COMMIT;

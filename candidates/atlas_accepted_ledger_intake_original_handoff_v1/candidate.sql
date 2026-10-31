-- SOURCE ONLY -- do not run directly on noel-core production.
-- Post-v2 accepted Ledger Work compatibility. One original, unchanged ledger
-- participant-attested provenance; no automatic owner promotion/assignment.
-- DEPENDS ON independently released disposition migration 20261031004257.
BEGIN;

-- Internal evidence predicate, not a grant. This does not itself authorize
-- anyone to view, edit, offer, assign or schedule an original Work item.
CREATE OR REPLACE FUNCTION atlas.accepted_ledger_intake_original_evidence_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM atlas.ledger_work_intakes i
    JOIN atlas.work_items w ON w.id=i.work_item_id
    JOIN atlas.ledger_work_intake_decisions d ON d.intake_id=i.id
      AND d.revision=i.revision
      AND d.decision='accepted_for_ledger'
      AND d.reviewer_principal_id=i.reviewed_by_principal_id
    WHERE i.organization_id=p_organization_id
      AND i.ledger_id=p_ledger_id
      AND i.work_item_id=p_work_item_id
      AND i.review_state='accepted_for_ledger'
      AND i.reviewed_by_principal_id IS NOT NULL
      AND i.reviewed_at IS NOT NULL
      AND w.organization_id=i.organization_id
      AND w.source_object_type='ledger_work_intake'
      AND w.source_object_id=i.id
      AND w.work_state='open'
      AND EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
        WHERE rel.organization_id=i.organization_id
          AND rel.ledger_id=i.ledger_id
          AND rel.work_item_id=w.id
          AND rel.attribution_state='active'
          AND rel.evidence_kind='participant_attested'
          AND rel.established_by_person_id=i.submitted_by_person_id
          AND rel.attestation_source_ref='atlas.work_items:'||w.id::text
      )
  );
$fn$;
REVOKE ALL ON FUNCTION
  atlas.accepted_ledger_intake_original_evidence_v1(uuid,uuid,uuid)
FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION atlas.require_native_original_work_text_owner_v1(p_organization_id uuid, p_ledger_id uuid, p_work_item_id uuid)
 RETURNS atlas.work_items
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_membership uuid;
  v_work atlas.work_items%ROWTYPE;
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Exact Organization, Ledger and original Work required'
      USING ERRCODE='22023';
  END IF;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_membership:=atlas.current_effective_organization_membership_v1(
    p_organization_id);
  IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=v_membership AND m.organization_id=p_organization_id
      AND m.person_id=v_person AND m.user_id=auth.uid()
      AND m.role='owner' AND m.active
  ) THEN
    RAISE EXCEPTION 'Exact signed institutional owner required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.household_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original native Company Work unavailable'
      USING ERRCODE='42501';
  END IF;
  -- Only Work natively authored into Ledger/Event Work by Atlas, not
  -- derived production/medical/legacy sources with their own edit laws.
  IF v_work.source_object_type IS NULL OR
     v_work.source_object_type NOT IN
     ('ledger_occurrence_shared_work','ledger_connected_direct_task',
      'ledger_work_intake') THEN
    RAISE EXCEPTION 'This source-managed Work requires its own edit authority'
      USING ERRCODE='42501';
  END IF;
  -- The original submitter's evidence is not sufficient for ordinary owner
  -- editing. Only a root-reviewed, currently accepted same-original intake
  -- may use this established (still owner-authorized) editor.
  IF v_work.source_object_type='ledger_work_intake' AND
     NOT atlas.accepted_ledger_intake_original_evidence_v1(
       p_organization_id,p_ledger_id,p_work_item_id) THEN
    RAISE EXCEPTION 'Only accepted original Ledger intake Work may be edited'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id
      AND r.work_item_id=p_work_item_id
      AND r.ledger_id=p_ledger_id
      AND r.attribution_state='active'
      AND (
        r.evidence_kind IN ('owner_attested','participant_attested')
        OR (r.evidence_kind='source_verified' AND EXISTS(
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            p_work_item_id,p_ledger_id) proof
          WHERE proof.source_schema=r.source_schema
            AND proof.source_table=r.source_table
            AND proof.source_id=r.source_id))
      )
  ) THEN
    RAISE EXCEPTION 'Exact native Work/Ledger relevance is not established'
      USING ERRCODE='42501';
  END IF;
  RETURN v_work;
END
$function$;


CREATE OR REPLACE FUNCTION atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid, p_work_item_id uuid, p_terms text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;v_work atlas.work_items%rowtype;
 v_scope atlas.company_work_standing_assignment_scopes%rowtype;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
BEGIN
 IF auth.uid() IS NULL OR p_worker_person_id IS NULL OR p_work_item_id IS NULL
   OR v_terms IS NULL OR length(v_terms) NOT BETWEEN 30 AND 3000
   OR (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'Exact Work, Person and bounded terms required' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner=p_worker_person_id OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,p_worker_person_id) THEN
   RAISE EXCEPTION 'Another connected Person and native Ledger owner required'
    USING ERRCODE='42501'; END IF;
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR SHARE;
 IF v_work.id IS NULL OR v_work.work_state<>'open' OR
   (v_work.result_contract_key IS NULL
    AND coalesce(v_work.source_object_type,'') NOT IN ('legacy_task','personal_dated_task')) THEN
   RAISE EXCEPTION 'Open original Work with lawful Result contract required'
    USING ERRCODE='23514'; END IF;
 -- Intake review is a mandatory source condition, not merely one optional
 -- relevance kind. An owner-attested relevance cannot bypass pending review.
 IF v_work.source_object_type='ledger_work_intake'
    AND NOT atlas.accepted_ledger_intake_original_evidence_v1(
      p_organization_id,p_ledger_id,v_work.id) THEN
    RAISE EXCEPTION 'Exact intake must have final root acceptance before consent proposal'
      USING ERRCODE='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_item_context_links l
    WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
    AND l.subject_domain='spatial' AND l.subject_kind='growing_object') THEN
   RAISE EXCEPTION 'Protected spatial Work requires separate original Subject authority'
    USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
   WHERE rel.organization_id=p_organization_id AND rel.ledger_id=p_ledger_id
     AND rel.work_item_id=v_work.id AND rel.attribution_state='active'
     AND (rel.evidence_kind='owner_attested' OR
       (rel.evidence_kind='participant_attested'
         AND atlas.accepted_ledger_intake_original_evidence_v1(
           p_organization_id,p_ledger_id,v_work.id)) OR
       (rel.evidence_kind='source_verified' AND EXISTS(
        SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
          rel.work_item_id,rel.ledger_id) proof
        WHERE proof.source_schema=rel.source_schema
          AND proof.source_table=rel.source_table
          AND proof.source_id=rel.source_id)))) THEN
   RAISE EXCEPTION 'Exact established native Ledger Work relevance required'
    USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_allocations a
   WHERE a.work_item_id=v_work.id AND a.organization_id=p_organization_id
     AND a.state='active' AND a.allocation_role='responsible') THEN
   RAISE EXCEPTION 'Current responsible allocation needs governed transfer'
    USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_standing_assignment_scopes s
   WHERE s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
     AND s.worker_person_id=p_worker_person_id AND s.coverage_mode='exact_work'
     AND s.covered_work_item_id=v_work.id AND s.scope_state IN ('proposed','active')
     AND (s.valid_until IS NULL OR s.valid_until>now())) THEN
   RAISE EXCEPTION 'Exact Work scope already exists' USING ERRCODE='23505'; END IF;
 INSERT INTO atlas.company_work_standing_assignment_scopes(
   organization_id,ledger_id,worker_membership_id,worker_person_id,
   position_id,position_appointment_id,organization_unit_id,
   covered_operation_class,covered_work_item_id,coverage_mode,
   proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES (p_organization_id,p_ledger_id,NULL,p_worker_person_id,
   NULL,NULL,NULL,NULL,v_work.id,'exact_work',v_owner,NULL,v_terms,p_valid_until)
 RETURNING * INTO v_scope;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_ledger_standing_scope_v1',
   'scopeId',v_scope.id,'state','proposed','organizationId',p_organization_id,
   'ledgerId',p_ledger_id,'workerPersonId',p_worker_person_id,
   'coverageMode','exact_work','coveredWorkItemId',v_work.id,
   'workerConsentRecorded',false,'workAssigned',false,
   'newWorkCreated',false,'employeeSeatRequired',false);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.offer_unallocated_company_work_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_target_person_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
       (l.evidence_kind='participant_attested'
         AND atlas.accepted_ledger_intake_original_evidence_v1(
           v_work.organization_id,p_ledger_id,v_work.id)) OR
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
   (v_scope.coverage_mode='exact_work' AND
      (v_scope.covered_work_item_id IS NULL OR
       v_scope.covered_work_item_id IS DISTINCT FROM v_work.id)) OR
   v_scope.coverage_mode NOT IN ('operation_class','ledger_all_work','exact_work') THEN
   RAISE EXCEPTION 'Open Work and currently accepted Person/Ledger standing scope required'
     USING ERRCODE='23514';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
   v_work.organization_id,v_scope.ledger_id);
 -- Signed root Ledger governance was checked by the exact native owner
 -- function. An outdated organization member role is not additional proof.
 v_owner_membership:=NULL;
 -- The accepted source remains required on execution of consent, not only
 -- when a scope was proposed; revocation or replaced relevance must fail shut.
 IF v_work.source_object_type='ledger_work_intake'
    AND NOT atlas.accepted_ledger_intake_original_evidence_v1(
      v_work.organization_id,v_scope.ledger_id,v_work.id) THEN
    RAISE EXCEPTION 'Exact intake root acceptance no longer current'
      USING ERRCODE='42501';
 END IF;
 IF v_scope.proposed_by_person_id IS DISTINCT FROM v_owner OR
   NOT atlas.person_has_native_ledger_connection_v1(
     v_work.organization_id,v_scope.ledger_id,v_scope.worker_person_id) THEN
   RAISE EXCEPTION 'Issuing authority or receiver Ledger connection changed'
     USING ERRCODE='23514';
 END IF;
 IF v_scope.coverage_mode='exact_work' AND EXISTS (
   SELECT 1 FROM atlas.work_item_context_links l
   WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
     AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
 ) THEN RAISE EXCEPTION 'Protected spatial Work requires original Subject disclosure'
   USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
   WHERE o.work_item_id=v_work.id AND o.offer_state='offered') THEN
   RAISE EXCEPTION 'Resolve or withdraw pending individual offers first' USING ERRCODE='23514';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
   WHERE rel.organization_id=v_work.organization_id AND rel.work_item_id=v_work.id
     AND rel.ledger_id=v_scope.ledger_id AND rel.attribution_state='active'
     AND (rel.evidence_kind='owner_attested' OR
       (rel.evidence_kind='participant_attested'
         AND atlas.accepted_ledger_intake_original_evidence_v1(
           v_work.organization_id,v_scope.ledger_id,v_work.id)) OR
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
   'coveredWorkItemId',v_scope.covered_work_item_id,
   'responsiblePersonId',v_scope.worker_person_id,
   'workerAcceptancePerTaskRequired',false,'workerDayPlacementProven',false,
   'workerReadProven',false,'newWorkCreated',false);
END
$function$;


CREATE OR REPLACE FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_work_item_id uuid, p_target_person_id uuid, p_service_date date, p_action_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_work atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_allocation atlas.work_allocations%rowtype;
 v_plan atlas.work_execution_plans%rowtype;
 v_window jsonb;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
 v_created boolean:=false;
 v_basis text;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_work_item_id IS NULL OR p_target_person_id IS NULL
    OR p_action_id IS NULL
    OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
    RAISE EXCEPTION 'Exact existing Work, Person, action and reason required'
      USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Direct allocation requires a genuinely connected Person'
      USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.plan:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open'
   OR v_work.source_object_type NOT IN ('work_decomposition','ledger_work_intake')
   OR v_work.result_contract_key NOT IN(
      'ordinary_company_work_worker_attestation_v1',
      'ordinary_company_work_manager_acceptance_v1'
   ) THEN
   RAISE EXCEPTION 'Only still-open original decomposed Work can be directly assigned.'
     USING ERRCODE='23514';
 END IF;
 IF v_work.source_object_type='ledger_work_intake' THEN
   IF NOT atlas.accepted_ledger_intake_original_evidence_v1(
     p_organization_id,p_ledger_id,p_work_item_id) THEN
     RAISE EXCEPTION 'Only accepted original intake may be directly assigned' USING ERRCODE='42501';
   END IF;
   v_basis:='ledger_connection_direct_assignment';
 ELSE
   v_basis:='original_subject_direct_assignment_v1';
 SELECT g.* INTO v_group FROM atlas.work_decomposition_groups g
 JOIN atlas.work_decomposition_members m ON m.group_id=g.id
 WHERE m.child_work_item_id=v_work.id AND g.authorized_ledger_id=p_ledger_id
   AND g.parent_work_item_id=v_work.source_object_id;
 IF v_group.id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.company_work_native_ledger_relevance r
   WHERE r.organization_id=p_organization_id
     AND r.ledger_id=p_ledger_id AND r.work_item_id=v_work.id
     AND r.attribution_state='active'
 ) THEN RAISE EXCEPTION 'Exact governed Work/Subject Ledger provenance unavailable.'
    USING ERRCODE='42501'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers o
   WHERE o.work_item_id=p_work_item_id AND o.offer_state='offered') THEN
   RAISE EXCEPTION 'Resolve the existing offer first' USING ERRCODE='23514';
 END IF;
 IF EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
     AND a.state='active' AND a.allocation_role='responsible'
     AND (a.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
       OR a.establishment_basis_kind<>v_basis
       OR a.establishment_basis->>'sourceActionId'<>p_action_id::text)
 ) THEN RAISE EXCEPTION 'Another live responsibility or decision exists; use governed transfer.'
    USING ERRCODE='23514'; END IF;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
   AND a.state='active' AND a.allocation_role='responsible'
   AND a.establishment_basis_kind=v_basis;
 IF v_allocation.id IS NOT NULL THEN
   SELECT * INTO v_plan FROM atlas.work_execution_plans p
   WHERE p.organization_id=p_organization_id AND p.work_item_id=v_work.id
     AND p.responsible_allocation_id=v_allocation.id AND p.plan_state='active'
   ORDER BY p.created_at LIMIT 1;
   IF v_allocation.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
       OR v_allocation.establishment_basis->>'sourceActionId' IS DISTINCT FROM p_action_id::text
       OR v_allocation.establishment_basis->>'requestedServiceDate' IS DISTINCT FROM p_service_date::text
       OR (p_service_date IS NOT NULL AND
           (v_plan.id IS NULL OR v_plan.planned_service_date IS DISTINCT FROM p_service_date))
       OR v_allocation.establishment_basis->>'decisionReason' IS DISTINCT FROM v_reason THEN
      RAISE EXCEPTION 'Exact original direct assignment retry differs from stored decision.'
        USING ERRCODE='23505';
   END IF;
 ELSE
   -- Responsibility is established independently of a work-on date. A caller
   -- may supply a date for prior signed-client compatibility; no date means
   -- no execution plan, no implied Today obligation, and no plan event.
   IF p_service_date IS NOT NULL THEN
     v_window:=atlas.company_work_execution_plan_window_check_v1(
       p_work_item_id,p_service_date);
     IF NOT coalesce((v_window->>'allowed')::boolean,false) THEN
       RAISE EXCEPTION 'Original Work may not be scheduled on requested day.'
         USING ERRCODE='23514';
     END IF;
   END IF; -- date/window validation does not guard allocation insertion
   INSERT INTO atlas.work_allocations(
     organization_id,work_item_id,assignee_membership_id,
     assignee_canonical_person_id,assigned_by_membership_id,
     allocation_role,state,allocated_at,establishment_basis_kind,
     establishment_basis,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,NULL,p_target_person_id,NULL,
     'responsible','active',now(),v_basis,
     jsonb_build_object(
       'contractVersion','exact_work_responsibility_establishment_v2',
       'basisKind',v_basis,
       'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
       'workItemId',p_work_item_id,'decompositionId',v_group.id,
       'assigneePersonId',p_target_person_id,'senderPersonId',v_owner,
       'sourceActionId',p_action_id,'decisionReason',v_reason,
       'requestedServiceDate',p_service_date,
       'authorizationBasis','governor_exact_existing_original_work'),
     jsonb_build_object('source',
       CASE WHEN v_work.source_object_type='ledger_work_intake'
         THEN 'accepted_ledger_intake_original_direct_assignment_v1'
         ELSE v_basis END,
       'sameOriginalCanonicalWork',true,'newTaskCreated',false,
       'employeeSeatRequired',false,'workerAttestedAsSelf',false)
   ) RETURNING * INTO v_allocation;
   IF p_service_date IS NOT NULL THEN
   INSERT INTO atlas.work_execution_plans(
     organization_id,work_item_id,responsible_allocation_id,
     assignee_membership_id,planned_by_membership_id,plan_state,
     first_planned_service_date,planned_service_date,exposure_service_date,
     plan_reason,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,v_allocation.id,NULL,NULL,'active',
     p_service_date,p_service_date,p_service_date,v_reason,
     jsonb_build_object('source',v_basis,
       'senderPersonId',v_owner,'originalDecompositionId',v_group.id,
       'workerAttestedAsSelf',false)
   ) RETURNING * INTO v_plan;
   INSERT INTO atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     to_planned_service_date,to_exposure_service_date,reason,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,v_plan.id,'planned',
     p_service_date,p_service_date,v_reason,
     jsonb_build_object('source',v_basis,
       'governorPersonId',v_owner,'sourceActionId',p_action_id)
   );
   END IF; -- optional execution plan (responsibility itself remains active)
   v_created:=true;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion',
   CASE WHEN v_work.source_object_type='ledger_work_intake'
     THEN 'ledger_intake_direct_responsibility_v1'
     ELSE 'original_subject_work_direct_responsibility_v1' END,
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',v_work.id,'subjectDecompositionId',v_group.id,
   'targetPersonId',p_target_person_id,'allocationId',v_allocation.id,
   'planId',v_plan.id,'plannedServiceDate',v_plan.planned_service_date,
   'scheduleState',CASE WHEN v_plan.id IS NULL THEN 'unscheduled' ELSE 'scheduled' END,
   'responsibilityEstablished',true,
   'newWorkCreated',false,'newTaskCreated',false,
   'acceptanceQuestionCreated',false,
   'workerAttestedAsSelf',false,'employeeSeatRequired',false,
   'assignmentNew',v_created,'idempotent',NOT v_created);
END;
$function$;

-- Native Ledger Work projection: pending intake stays in review, not active Work.
CREATE OR REPLACE FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope text DEFAULT 'native_ledger'::text, p_limit integer DEFAULT 200, p_after_work_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_person_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_last_id uuid;
  v_without_proof bigint;
BEGIN
  -- Build-1 root gate proves current auth session, canonical Person/Principal,
  -- current native seat, exact Organization participation and BOTH roots.
  -- No position title, employee seat or generic membership extends this grant.
  v_actor_person_id := atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id, p_ledger_id
  );

  IF p_scope IS NULL OR p_scope NOT IN ('native_ledger','organization') THEN
    RAISE EXCEPTION 'Scope must be native_ledger or organization.' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 500.' USING ERRCODE='22023';
  END IF;

  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.work_item_id),'[]'::jsonb),
         max(x.work_item_id::text)::uuid
    INTO v_items,v_last_id
  FROM (
    SELECT w.id AS work_item_id,
      jsonb_build_object(
        'workItemId',w.id,
        'organizationId',w.organization_id,
        'organizationUnitId',w.organization_unit_id,
        'title',w.title,
        'operationClass',w.operation_class,
        'workState',w.work_state,
        'sourceObjectType',w.source_object_type,
        'resultContractKey',w.result_contract_key,
        'selectedNativeLedgerId',p_ledger_id,
        'nativeLedgerRelevance',CASE WHEN w.has_exact_ledger_evidence
           THEN 'established_for_selected_ledger'
           ELSE 'not_established_for_selected_ledger' END,
        'otherLedgerEvidenceDoesNotProveExclusion',true,
        'responsibility',jsonb_build_object(
           'allocationId',wa.id,
           'state',CASE WHEN wa.id IS NULL THEN 'no_active_responsible_allocation'
                        ELSE 'active_responsible_allocation_observed' END,
           'establishmentBasisKind',wa.establishment_basis_kind,
           'assigneeMembershipId',wa.assignee_membership_id,
           'assigneeInstitutionalPersonRecordId',
              coalesce(wa.assignee_institutional_person_record_id,
                       om_assignee.institutional_person_record_id),
           'assigneePersonId',coalesce(wa.assignee_canonical_person_id,ipr.person_id,om_assignee.person_id),
           'personProvenance',CASE
             WHEN wa.assignee_canonical_person_id IS NOT NULL
               THEN 'person_native_ledger_connection_receiver_uptake'
             WHEN wa.assignee_institutional_person_record_id IS NOT NULL
               THEN 'exact_allocation_institutional_person'
             WHEN om_assignee.institutional_person_record_id IS NOT NULL
               THEN 'active_allocation_to_membership_institutional_person'
             WHEN om_assignee.person_id IS NOT NULL
               THEN 'active_allocation_to_membership_person'
             ELSE 'no_source_person_resolution'
           END,
           'offeredResponsibilityCount',offers.offered_count
        ),
        'lastResponsibleAllocation',CASE WHEN wa_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'allocationId',wa_hist.id,
            'allocationState',wa_hist.state,
            'establishmentBasisKind',wa_hist.establishment_basis_kind,
            'assigneeMembershipId',wa_hist.assignee_membership_id,
            'assigneeInstitutionalPersonRecordId',
               coalesce(wa_hist.assignee_institutional_person_record_id,
                        om_hist.institutional_person_record_id),
            'assigneePersonId',coalesce(wa_hist.assignee_canonical_person_id,ipr_hist.person_id,om_hist.person_id),
            'allocatedAt',wa_hist.allocated_at,
            'completedAt',wa_hist.completed_at,
            'releasedAt',wa_hist.released_at,
            'historicalNotCurrent',true
          ) END,
        'lastExecutionPlan',CASE WHEN ep_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'planId',ep_hist.id,
            'planState',ep_hist.plan_state,
            'firstPlannedServiceDate',ep_hist.first_planned_service_date,
            'plannedServiceDate',ep_hist.planned_service_date,
            'exposureServiceDate',ep_hist.exposure_service_date,
            'rolloverCount',ep_hist.rollover_count,
            'historicalNotCurrent',true
          ) END,
        'planning',jsonb_build_object(
           'planId',ep.id,
           'planState',coalesce(ep.plan_state,'no_current_plan'),
           'plannedServiceDate',ep.planned_service_date,
           'firstPlannedServiceDate',ep.first_planned_service_date,
           'exposureServiceDate',ep.exposure_service_date,
           'rolloverCount',coalesce(ep.rollover_count,0),
           'sourceWindowEarliestAt',tc.earliest_lawful_at,
           'sourceWindowHardFinishAt',tc.hard_finish_at,
           'sourceWindowLatestLawfulAt',tc.latest_lawful_at,
           'planHistoryEventCount',coalesce(events.event_count,0),
           'openConflictCount',coalesce(conflicts.open_count,0)
        ),
        'workerProjection',jsonb_build_object(
           'state',CASE
             WHEN coalesce(wp.canonical_count,0)>0
               THEN 'governed_plan_projection_observed'
             WHEN coalesce(wp.related_count,0)>0
               THEN 'legacy_or_unverified_projection_observed'
             ELSE 'no_matching_worker_projection_observed' END,
           'canonicalProjectionCount',coalesce(wp.canonical_count,0),
           'otherRelatedProjectionCount',
             coalesce(wp.related_count,0)-coalesce(wp.canonical_count,0),
           'workerViewedReceipt','not_proven',
           'currentExecutionWarrant','not_proven_by_projection',
           'employeePrivateContextRead',false
        ),
        'latestWorkerReport',CASE WHEN lr.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',lr.id,'resultKind',lr.result_kind,
            'reportedAt',lr.reported_at,
            'reportedByInstitutionalPersonRecordId',lr.reported_by_institutional_person_record_id,
            'decision',coalesce(ra.decision,'no_acceptance_for_this_result'),
            'decisionAt',ra.accepted_at,
            'reportsSharingLatestTimestamp',lr.timestamp_tie_count,
            'exactOrderWithinTimestampProven',lr.timestamp_tie_count=1
          ) END,
        'latestAcceptedResult',CASE WHEN ar.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',ar.id,'resultKind',ar.result_kind,
            'reportedAt',ar.reported_at,
            'decision',ar.decision,'acceptedAt',ar.accepted_at,
            'acceptanceKind',ar.acceptance_kind
          ) END,
        'reportedResultCount',reports.total_count,
        'acceptedResultIsDistinctFromReport',true
      ) AS item
    FROM (
      SELECT wi.*,
        EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
          WHERE rel.organization_id=wi.organization_id
            AND rel.work_item_id=wi.id
            AND rel.ledger_id=p_ledger_id
            AND rel.attribution_state='active'
            AND (
              rel.evidence_kind in ('owner_attested','participant_attested')
              OR (rel.evidence_kind='source_verified' AND EXISTS (
                SELECT 1
                FROM atlas.company_work_native_ledger_exact_source_v1(
                  rel.work_item_id,rel.ledger_id
                ) proof
                WHERE proof.source_schema=rel.source_schema
                  AND proof.source_table=rel.source_table
                  AND proof.source_id=rel.source_id
              ))
            )
        ) AS has_exact_ledger_evidence
      FROM atlas.work_items wi
      WHERE wi.organization_id=p_organization_id
        AND (p_after_work_item_id IS NULL OR wi.id>p_after_work_item_id)
      ORDER BY wi.id
    ) w
    LEFT JOIN LATERAL (
      SELECT a.id,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state='active'
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa ON true
    LEFT JOIN atlas.organization_memberships om_assignee
      ON om_assignee.id=wa.assignee_membership_id
     AND om_assignee.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr
      ON ipr.id=coalesce(wa.assignee_institutional_person_record_id,
                         om_assignee.institutional_person_record_id)
     AND ipr.organization_id=w.organization_id
    -- Preserve the latest non-active responsible allocation as provenance:
    -- never advertise completed or released responsibility as current.
    LEFT JOIN LATERAL (
      SELECT a.id,a.state,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id,
             a.allocated_at,a.completed_at,a.released_at
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state IN ('completed','released')
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa_hist ON true
    LEFT JOIN atlas.organization_memberships om_hist
      ON om_hist.id=wa_hist.assignee_membership_id
     AND om_hist.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr_hist
      ON ipr_hist.id=coalesce(wa_hist.assignee_institutional_person_record_id,
                            om_hist.institutional_person_record_id)
     AND ipr_hist.organization_id=w.organization_id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS offered_count
      FROM atlas.company_work_responsibility_transfer_offers o
      WHERE o.organization_id=w.organization_id
        AND o.work_item_id=w.id AND o.offer_state='offered'
    ) offers ON true
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.responsible_allocation_id,
             p.assignee_membership_id,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id
        AND p.work_item_id=w.id AND p.plan_state IN ('active','needs_replan')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep ON true
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id AND p.work_item_id=w.id
        AND p.plan_state IN ('completed','withdrawn')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep_hist ON true
    LEFT JOIN LATERAL (
      SELECT t.earliest_lawful_at,t.hard_finish_at,t.latest_lawful_at
      FROM atlas.work_time_contracts t
      WHERE t.organization_id=w.organization_id AND t.work_item_id=w.id
        AND t.contract_state='active'
      ORDER BY t.created_at DESC,t.id DESC LIMIT 1
    ) tc ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS event_count
      FROM atlas.work_execution_plan_events e
      WHERE e.organization_id=w.organization_id AND e.work_item_id=w.id
    ) events ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS open_count
      FROM atlas.work_planning_conflicts c
      WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
        AND c.state='open'
    ) conflicts ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS related_count,
        count(*) FILTER (
          WHERE ep.id IS NOT NULL
            AND ep.plan_state='active'
            AND ep.responsible_allocation_id=wa.id
            AND ep.assignee_membership_id=wa.assignee_membership_id
            AND p.source_kind='work_item'
            AND p.source_id=w.id
            AND p.planned_date=ep.exposure_service_date
            AND p.delivery_payload->>'projectionAuthority'='work_execution_plans'
            AND p.delivery_payload->>'managerPlanId'=ep.id::text
            AND p.delivery_payload->>'source'='company_work_employee_plan_projection_v1'
            AND p.delivery_payload->>'canonicalCompanyWorkProjection'='true'
        )::integer AS canonical_count
      FROM atlas.worker_week_projection_sources s
      JOIN atlas.worker_week_projection p ON p.id=s.projection_id
      WHERE s.work_item_id=w.id AND s.source_role='required'
        AND p.organization_id=w.organization_id
        AND wa.id IS NOT NULL
        AND p.organization_membership_id=wa.assignee_membership_id
    ) wp ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,
             r.reported_by_institutional_person_record_id,
             (SELECT count(*)::integer FROM atlas.work_execution_results tied
              WHERE tied.organization_id=r.organization_id
                AND tied.work_item_id=r.work_item_id
                AND tied.reported_at=r.reported_at) AS timestamp_tie_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
      -- A transaction timestamp may tie across multiple worker reports;
      -- UUID sorting is deterministic, never proof of report chronology.
      ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
    ) lr ON true
    LEFT JOIN atlas.work_result_acceptances ra
      ON ra.execution_result_id=lr.id
     AND ra.organization_id=w.organization_id
     AND ra.work_item_id=w.id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS total_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
    ) reports ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,a.decision,
             a.accepted_at,a.acceptance_kind
      FROM atlas.work_result_acceptances a
      JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
       AND r.organization_id=a.organization_id
       AND r.work_item_id=a.work_item_id
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id AND a.decision='accepted'
      ORDER BY a.accepted_at DESC,a.id DESC LIMIT 1
    ) ar ON true
    WHERE (p_scope='organization' OR w.has_exact_ledger_evidence)
      -- Pending governor intake is not yet accepted operational Ledger Work.
      -- Rejected/cancelled history retains its original Work identity.
      AND (p_scope<>'native_ledger'
        OR w.source_object_type IS DISTINCT FROM 'ledger_work_intake'
        OR w.work_state<>'open'
        OR atlas.accepted_ledger_intake_original_evidence_v1(
          p_organization_id,p_ledger_id,w.id))
    ORDER BY w.id
    LIMIT p_limit
  ) x;

  -- This count is diagnostic for institution-owned work with no CURRENT
  -- native Ledger evidence at all. It does not authorize showing those
  -- Work rows in the selected native Ledger.
  SELECT count(*) INTO v_without_proof
  FROM atlas.work_items wi
  WHERE wi.organization_id=p_organization_id
    AND NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=wi.organization_id
        AND rel.work_item_id=wi.id
        AND rel.attribution_state='active'
        AND (rel.evidence_kind in ('owner_attested','participant_attested')
          OR (rel.evidence_kind='source_verified' AND EXISTS (
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
              rel.work_item_id,rel.ledger_id
            ) proof
            WHERE proof.source_schema=rel.source_schema
              AND proof.source_table=rel.source_table
              AND proof.source_id=rel.source_id
          )))
    );

  RETURN jsonb_build_object(
    'contractVersion','company_work_accountability_native_ledger_v1',
    'organizationId',p_organization_id,
    'selectedNativeLedgerId',p_ledger_id,
    'scopeMode',p_scope,
    'scopeRule',CASE WHEN p_scope='native_ledger'
      THEN 'only_currently_proven_exact_native_ledger_relevance'
      ELSE 'explicit_organization_accountability_not_ledger_attribution' END,
    'items',v_items,
    'pageLimit',p_limit,
    'nextAfterWorkItemId',v_last_id,
    'organizationWorkWithoutAnyCurrentNativeLedgerEvidenceCount',v_without_proof,
    'facts',jsonb_build_object(
      'workOwnedByOrganization',true,
      'reportIsNotAcceptance',true,
      'managerDoesNotImpersonateWorker',true,
      'projectionIsNotProofWorkerViewed',true,
      'projectionIsNotExecutionLease',true,
      'principalClockEscalationNotRequired',true,
      'privatePersonalAtlasNotRead',true,
      'noNewResponsibilityOrPlanCreated',true,
      'sortPriorityNotInvented',true
    )
  );
END
$function$;

-- Exact root-only eligibility read for the existing Work Focus direct action.
-- This checks real source acceptance; mere absence from a pending queue is NOT proof.
CREATE OR REPLACE FUNCTION atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid;
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL
  THEN RAISE EXCEPTION 'Exact existing source required' USING ERRCODE='22023'; END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  IF v_owner IS NULL OR NOT atlas.accepted_ledger_intake_original_evidence_v1(
    p_organization_id,p_ledger_id,p_work_item_id) THEN
    RAISE EXCEPTION 'Original accepted Work unavailable for governor'
      USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','accepted_ledger_intake_owner_assignment_source_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'sourceAccepted',true,
    'sameOriginalWork',true,'authorityNotDelegated',true,
    'personalWorkAssignmentCreated',false,'workPlanCreated',false);
END;
$fn$;
CREATE OR REPLACE FUNCTION public.accepted_ledger_intake_owner_assignment_source_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
  SELECT atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1($1,$2,$3);
$fn$;
REVOKE ALL ON FUNCTION
  atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid),
  public.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
  atlas.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid),
  public.accepted_ledger_intake_owner_assignment_source_self_api_v1(uuid,uuid,uuid)
TO authenticated;

-- Signed submitter *own* status. This is not the root queue, a roster or a
-- notification delivery receipt. All statuses remain private to the author,
-- with current exact Ledger authorization checked afresh at read time.
CREATE OR REPLACE FUNCTION atlas.ledger_work_submission_status_self_api_v1(
  p_ledger_id uuid,p_limit integer DEFAULT 50,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_intake_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
  who uuid; principal uuid; organization uuid; n integer;
  items jsonb; more boolean; last_item jsonb;
BEGIN
  IF auth.uid() IS NULL OR
     (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
  THEN RAISE EXCEPTION 'Signed canonical Person required' USING errcode='42501'; END IF;
  who:=atlas.current_person_id_v1();
  principal:=atlas.current_principal_id_v1();
  IF who IS NULL OR principal IS NULL
  THEN RAISE EXCEPTION 'Canonical Person and Principal required' USING errcode='42501'; END IF;
  IF p_ledger_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_after_created_at IS NULL) IS DISTINCT FROM (p_after_intake_id IS NULL)
  THEN RAISE EXCEPTION 'Exact Ledger, page size and cursor required' USING errcode='22023'; END IF;

  SELECT count(*),(array_agg(lop.organization_id))[1] INTO n,organization
  FROM atlas.ledger_organization_participations lop
  JOIN atlas.ledgers al ON al.id=lop.ledger_id AND al.status='active'
  JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
     AND nl.ledger_state='active' AND nl.retired_at IS NULL
  WHERE lop.ledger_id=p_ledger_id AND lop.status='active'
    AND lop.ended_at IS NULL AND lop.participation_kind IN ('governing','operating');
  IF n<>1 OR NOT(
     atlas.person_has_native_ledger_connection_v1(organization,p_ledger_id,who)
     OR atlas.principal_has_ledger_authority_v1(principal,p_ledger_id))
  THEN RAISE EXCEPTION 'Not admitted to exact Ledger' USING errcode='42501'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'intakeId',x.id,'workItemId',x.work_item_id,
    'title',x.title,'submittedAt',x.created_at,
    'reviewState',x.review_state,'revision',x.revision,
    'reviewedAt',x.reviewed_at,
    'attentionDateProposal',x.attention_date_proposal)
    ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO items
  FROM (
    SELECT i.id,i.work_item_id,w.title,i.created_at,
      i.review_state,i.revision,i.reviewed_at,i.attention_date_proposal
    FROM atlas.ledger_work_intakes i
    JOIN atlas.work_items w ON w.id=i.work_item_id AND w.organization_id=i.organization_id
      AND w.source_object_type='ledger_work_intake' AND w.source_object_id=i.id
    WHERE i.organization_id=organization AND i.ledger_id=p_ledger_id
      AND i.submitted_by_person_id=who
      AND (p_after_created_at IS NULL OR
        (i.created_at,i.id)<(p_after_created_at,p_after_intake_id))
    ORDER BY i.created_at DESC,i.id DESC LIMIT p_limit
  ) x;

  SELECT EXISTS(
    SELECT 1 FROM (
      SELECT i.id FROM atlas.ledger_work_intakes i
      WHERE i.organization_id=organization AND i.ledger_id=p_ledger_id
        AND i.submitted_by_person_id=who
        AND (p_after_created_at IS NULL OR
          (i.created_at,i.id)<(p_after_created_at,p_after_intake_id))
      ORDER BY i.created_at DESC,i.id DESC LIMIT p_limit+1
    ) page OFFSET p_limit
  ) INTO more;
  last_item:=items->(jsonb_array_length(items)-1);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','ledger_work_submitter_status_v1',
    'ledgerId',p_ledger_id,'items',items,'hasMore',more,
    'nextCreatedAt',CASE WHEN more THEN last_item->>'submittedAt' ELSE NULL END,
    'nextIntakeId',CASE WHEN more THEN last_item->>'intakeId' ELSE NULL END,
    'personnelRosterDisclosed',false,'rootInboxDisclosed',false,
    'notificationDeliveryClaimed',false);
END;
$fn$;
CREATE OR REPLACE FUNCTION public.ledger_work_submission_status_self_api_v1(
  p_ledger_id uuid,p_limit integer,p_after_created_at timestamptz,p_after_intake_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='pg_catalog' AS $fn$
  SELECT atlas.ledger_work_submission_status_self_api_v1($1,$2,$3,$4);
$fn$;
REVOKE ALL ON FUNCTION
  atlas.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid),
  public.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
  atlas.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid),
  public.ledger_work_submission_status_self_api_v1(uuid,integer,timestamptz,uuid)
TO authenticated;


-- The existing responsibility provenance guard recognizes earlier original
-- Event/connection sources. Extend ONLY the explicit accepted-intake source,
-- using the canonical checked pg_get_functiondef patch technique already
-- used by Noel's 20261021155715 migration. Preserve all older branches.
DO $accepted_intake_guard$
DECLARE v_source text; v_old text; v_new text;
BEGIN
  v_source:=pg_get_functiondef(
    'atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure);
  v_old:=$old_branch$  if v_kind='ledger_connection_direct_assignment' then$old_branch$;
  v_new:=$accepted_branch$  if v_kind='ledger_connection_direct_assignment'
     and v_source='accepted_ledger_intake_original_direct_assignment_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_exact_existing_original_work'
    then
      raise exception 'Accepted original intake responsibility provenance incomplete'
        using errcode='23514';
    end if;
    if atlas.current_person_id_v1() is distinct from
         (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
         is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
       or not atlas.accepted_ledger_intake_original_evidence_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.work_item_id)
    then
      raise exception 'Accepted original requires current exact root, Person and final review'
        using errcode='42501';
    end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment' then$accepted_branch$;
  IF length(v_source)-length(replace(v_source,v_old,''))<>length(v_old)
     OR position('accepted_ledger_intake_original_direct_assignment_v1' IN v_source)>0
  THEN RAISE EXCEPTION 'Existing guarded Person connection source changed; do not widen or replace' USING errcode='23514';
  END IF;
  v_source:=replace(v_source,v_old,v_new);

  -- The old native Person standing-scope guard recognizes owner-attested
  -- and source-verified relevance. A submitted intake carries a distinct
  -- participant attestation. Recognize it here ONLY after a final exact
  -- root review; all other participant attestations remain inadmissible.
  v_old:=$standing_old$and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists($standing_old$;
  v_new:=$standing_new$and work.work_state='open'
        and (work.source_object_type IS DISTINCT FROM 'ledger_work_intake'
             OR atlas.accepted_ledger_intake_original_evidence_v1(
               new.organization_id,s.ledger_id,new.work_item_id))
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='participant_attested'
           and atlas.accepted_ledger_intake_original_evidence_v1(
             new.organization_id,s.ledger_id,new.work_item_id)) or
          (relevance.evidence_kind='source_verified' and exists($standing_new$;
  IF length(v_source)-length(replace(v_source,v_old,''))<>length(v_old)
  THEN RAISE EXCEPTION 'Native Person standing guard relevance shape changed; refuse to widen'
    USING ERRCODE='23514';
  END IF;
  v_source:=replace(v_source,v_old,v_new);
  EXECUTE v_source;
END;
$accepted_intake_guard$;

NOTIFY pgrst,'reload schema';
COMMIT;

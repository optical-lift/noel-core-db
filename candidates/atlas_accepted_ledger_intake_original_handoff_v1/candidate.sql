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
$function$


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
$function$


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
$function$


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
    'submittedTitle',x.submitted_title,'submittedAt',x.created_at,
    'reviewState',x.review_state,'revision',x.revision,
    'reviewedAt',x.reviewed_at,
    'attentionDateProposal',x.attention_date_proposal)
    ORDER BY x.created_at DESC,x.id DESC),'[]'::jsonb) INTO items
  FROM (
    SELECT i.id,i.work_item_id,i.submitted_title,i.created_at,
      i.review_state,i.revision,i.reviewed_at,i.attention_date_proposal
    FROM atlas.ledger_work_intakes i
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

NOTIFY pgrst,'reload schema';
COMMIT;

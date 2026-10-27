BEGIN;
-- Requires original_work_decomposition + native guarded reader extensions.
-- Assigns ONE EXISTING canonical Work ID; never creates or imports another.
CREATE OR REPLACE FUNCTION atlas.owner_original_split_work_part_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_work atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_subject atlas.work_decomposition_members%rowtype;
BEGIN
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id;
 IF v_work.id IS NULL OR v_work.source_object_type<>'work_decomposition'
    OR v_work.work_state<>'open' THEN
  RAISE EXCEPTION 'Open original split Work unavailable.' USING ERRCODE='42501';
 END IF;
 SELECT m.* INTO v_subject
 FROM atlas.work_decomposition_members m
 JOIN atlas.work_decomposition_groups g ON g.id=m.group_id
 WHERE m.child_work_item_id=v_work.id
   AND g.authorized_ledger_id=p_ledger_id
   AND g.parent_work_item_id=v_work.source_object_id;
 IF v_subject.id IS NULL OR NOT EXISTS (
  SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
  WHERE rel.work_item_id=v_work.id AND rel.organization_id=p_organization_id
   AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
 ) THEN RAISE EXCEPTION 'Exact original Work/Ledger relevance unavailable.'
    USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','original_split_work_part_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',v_work.id,'groupId',v_subject.group_id,
   'subjectDomain',v_subject.subject_domain,
   'subjectKind',v_subject.subject_kind,'subjectId',v_subject.subject_id,
   'isOneOriginalWork',true,'workerCanSelfAttest',
   v_work.result_contract_key='ordinary_company_work_worker_attestation_v1');
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.owner_original_split_work_part_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_original_split_work_part_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_split_work_part_self_api_v1(
 uuid,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_target_person_id uuid,p_service_date date,p_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
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
 IF v_owner=p_target_person_id OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Direct allocation requires another genuinely connected Person'
      USING ERRCODE='42501';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.company_work.plan:'||p_work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items
 WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_work.id IS NULL OR v_work.work_state<>'open'
   OR v_work.source_object_type<>'work_decomposition'
   OR v_work.result_contract_key NOT IN(
      'ordinary_company_work_worker_attestation_v1',
      'ordinary_company_work_manager_acceptance_v1'
   ) THEN
   RAISE EXCEPTION 'Only still-open original decomposed Work can be directly assigned.'
     USING ERRCODE='23514';
 END IF;
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
 IF EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
     AND a.state='active' AND a.allocation_role='responsible'
     AND (a.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
       OR a.establishment_basis_kind<>'original_subject_direct_assignment_v1'
       OR a.establishment_basis->>'sourceActionId'<>p_action_id::text)
 ) THEN RAISE EXCEPTION 'Another live responsibility or decision exists; use governed transfer.'
    USING ERRCODE='23514'; END IF;
 SELECT * INTO v_allocation FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=v_work.id
   AND a.state='active' AND a.allocation_role='responsible'
   AND a.establishment_basis_kind='original_subject_direct_assignment_v1';
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
     'responsible','active',now(),'original_subject_direct_assignment_v1',
     jsonb_build_object(
       'contractVersion','exact_work_responsibility_establishment_v2',
       'basisKind','original_subject_direct_assignment_v1',
       'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
       'workItemId',p_work_item_id,'decompositionId',v_group.id,
       'assigneePersonId',p_target_person_id,'senderPersonId',v_owner,
       'sourceActionId',p_action_id,'decisionReason',v_reason,
       'requestedServiceDate',p_service_date,
       'authorizationBasis','governor_exact_existing_original_work'),
     jsonb_build_object('source','original_subject_direct_assignment_v1',
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
     jsonb_build_object('source','original_subject_direct_assignment_v1',
       'senderPersonId',v_owner,'originalDecompositionId',v_group.id,
       'workerAttestedAsSelf',false)
   ) RETURNING * INTO v_plan;
   INSERT INTO atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     to_planned_service_date,to_exposure_service_date,reason,metadata
   ) VALUES(
     p_organization_id,p_work_item_id,v_plan.id,'planned',
     p_service_date,p_service_date,v_reason,
     jsonb_build_object('source','original_subject_direct_assignment_v1',
       'governorPersonId',v_owner,'sourceActionId',p_action_id)
   );
   END IF; -- optional execution plan (responsibility itself remains active)
   v_created:=true;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','original_subject_work_direct_responsibility_v1',
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
REVOKE ALL ON FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_target_person_id uuid,p_service_date date,p_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_direct_assign_existing_original_work_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_target_person_id,
 p_service_date,p_action_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_direct_assign_existing_original_work_self_api_v1(
 uuid,uuid,uuid,uuid,date,uuid,text) TO authenticated;

-- Exact-Work authorization stays within existing native Ledger/Person standing scopes.
-- A broad operation_class including pruning MUST NOT impersonate "mowing only".
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ADD COLUMN covered_work_item_id uuid REFERENCES atlas.work_items(id);
ALTER TABLE atlas.company_work_standing_assignment_scopes
 DROP CONSTRAINT company_work_native_scope_operation_class_required_v1;
ALTER TABLE atlas.company_work_standing_assignment_scopes
 ADD CONSTRAINT company_work_native_scope_operation_class_required_v1 CHECK (
  worker_membership_id IS NOT NULL OR
  (coverage_mode='ledger_all_work' AND organization_unit_id IS NULL
    AND covered_operation_class IS NULL AND covered_work_item_id IS NULL) OR
  (coverage_mode='operation_class' AND organization_unit_id IS NOT NULL
    AND covered_operation_class IS NOT NULL AND covered_work_item_id IS NULL
    AND length(btrim(covered_operation_class)) BETWEEN 2 AND 120) OR
  (coverage_mode='exact_work' AND organization_unit_id IS NULL
    AND covered_operation_class IS NULL AND covered_work_item_id IS NOT NULL)
 );

CREATE OR REPLACE FUNCTION atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_person_id uuid,
 p_work_item_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
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
 IF EXISTS(SELECT 1 FROM atlas.work_item_context_links l
    WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
    AND l.subject_domain='spatial' AND l.subject_kind='growing_object') THEN
   RAISE EXCEPTION 'Protected spatial Work requires separate original Subject authority'
    USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
   WHERE rel.organization_id=p_organization_id AND rel.ledger_id=p_ledger_id
     AND rel.work_item_id=v_work.id AND rel.attribution_state='active'
     AND (rel.evidence_kind='owner_attested' OR
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
REVOKE ALL ON FUNCTION atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_worker_person_id uuid,
 p_work_item_id uuid,p_terms text,p_valid_until timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.propose_native_ledger_exact_work_scope_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_worker_person_id,
   p_work_item_id,p_terms,p_valid_until);
$function$;
REVOKE ALL ON FUNCTION public.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.propose_native_ledger_exact_work_scope_owner_self_api_v1(
 uuid,uuid,uuid,uuid,text,timestamptz) TO authenticated;

-- Reuse Person acceptance and the original assignment writer; no new Work.
CREATE OR REPLACE FUNCTION atlas.native_ledger_standing_scopes_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_self uuid:=atlas.current_person_id_v1();
 v_incoming jsonb;
 v_outgoing jsonb;
BEGIN
 IF auth.uid() IS NULL OR v_self IS NULL THEN
   RAISE EXCEPTION 'Signed-in canonical Person required' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,
   'ledgerId',s.ledger_id,'workerPersonId',s.worker_person_id,
   'organizationUnitId',s.organization_unit_id,'operationClass',s.covered_operation_class,
   'coveredWorkItemId',s.covered_work_item_id,'coverageMode',s.coverage_mode,
   'proposalTerms',s.proposal_terms,
   'state',s.scope_state,'acceptedAt',s.accepted_at,'validUntil',s.valid_until)
   ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_incoming
 FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.worker_person_id=v_self AND s.worker_membership_id IS NULL
   AND s.scope_state IN ('proposed','active')
   AND atlas.person_has_native_ledger_connection_v1(
     s.organization_id,s.ledger_id,v_self);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'scopeId',s.id,'organizationId',s.organization_id,
   'ledgerId',s.ledger_id,'workerPersonId',s.worker_person_id,
   'organizationUnitId',s.organization_unit_id,'operationClass',s.covered_operation_class,
   'coveredWorkItemId',s.covered_work_item_id,'coverageMode',s.coverage_mode,
   'proposalTerms',s.proposal_terms,
   'state',s.scope_state,'acceptedAt',s.accepted_at,'validUntil',s.valid_until)
   ORDER BY s.proposed_at,s.id),'[]'::jsonb) INTO v_outgoing
 FROM atlas.company_work_standing_assignment_scopes s
 WHERE s.proposed_by_person_id=v_self AND s.worker_membership_id IS NULL
   AND s.scope_state IN ('proposed','active');
 RETURN jsonb_build_object(
  'ok',true,'contractVersion','native_ledger_standing_scope_v1',
  'incoming',v_incoming,'outgoing',v_outgoing,
  'standingAcceptanceIsNotWorkAcceptance',true);
END
$function$;
-- This is an EXISTING signed Person reader. Its public API is SECURITY INVOKER
-- and calls this source; preserve authenticated EXECUTE, never anon access.
REVOKE ALL ON FUNCTION atlas.native_ledger_standing_scopes_self_api_v1()
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.native_ledger_standing_scopes_self_api_v1()
 TO authenticated;
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
-- This existing governor-only writer is reached through a SECURITY INVOKER
-- public wrapper. Signed callers must be able to invoke its SOURCE; internal
-- native Ledger owner and exact Work authorization still enforce the decision.
REVOKE ALL ON FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)
 TO authenticated;
COMMIT;

-- SOURCE-ONLY CANDIDATE: Atlas existing Work self-assignment, October 29, 2026.
-- Preserve native Ledger seat/root authority, original Work, Result, grants and history.
-- Do not deploy without disposable full-schema clone and genuine signed authorization tests.
BEGIN;
DO $source_guard$
DECLARE
  v_choices oid := to_regprocedure('atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)');
  v_assignment oid := to_regprocedure('atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)');
BEGIN
 IF v_choices IS NULL OR v_assignment IS NULL THEN
   RAISE EXCEPTION 'Exact existing Person-choice and Work-assignment source required' USING ERRCODE='42501';
 END IF;
 IF md5(pg_get_functiondef(v_choices)) <> '98d5daf1edf7a62da1e161d5cfa9e61f'
    OR md5(pg_get_functiondef(v_assignment)) <> '22317b744f4c82fcf58562d3fb1934df' THEN
   RAISE EXCEPTION 'Live governing Work functions changed; rebase from current source before release' USING ERRCODE='23514';
 END IF;
END;
$source_guard$;

CREATE OR REPLACE FUNCTION atlas.connected_ledger_person_choices_self_api_v1(p_ledger_id uuid, p_limit integer DEFAULT 100, p_after_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_self uuid;v_items jsonb;v_next uuid;v_more boolean;
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in Person Atlas required' using errcode='42501';end if;
 v_self:=atlas.current_person_id_v1();
 perform atlas.current_active_ledger_seat_v1(p_ledger_id);
 if p_limit not between 1 and 100 then
   raise exception 'Page size out of range' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('personId',x.id,'name',x.display_name)
  order by x.id),'[]'::jsonb) into v_items from (
  select distinct e.id,e.display_name from ledger.seats s
  join reality.entities e on e.id=s.person_entity_id
  where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
   and e.entity_kind='person' and e.identity_state='canonical'
   and (p_after_person_id is null or e.id>p_after_person_id)
  order by e.id limit p_limit) x;
 if jsonb_array_length(v_items)>0 then
   v_next:=(v_items->(jsonb_array_length(v_items)-1)->>'personId')::uuid;
   select exists(select 1 from ledger.seats s
    join reality.entities e on e.id=s.person_entity_id
    where s.ledger_id=p_ledger_id and s.seat_state='active' and s.ended_at is null
     and e.entity_kind='person' and e.identity_state='canonical'
     and e.id>v_next) into v_more;
 else v_more:=false;end if;
 return jsonb_build_object('ok',true,'contractVersion','connected_ledger_person_choices_v1',
 'ledgerId',p_ledger_id,'items',v_items,'hasMore',v_more,
 'nextPersonId',case when v_more then v_next else null end,
 'rootAuthorityNotRequired',true);
end$function$


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
$function$

COMMIT;

-- Held source only; existing Personal original and connection authorities.
BEGIN;
CREATE FUNCTION atlas.personal_connected_task_choices_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_principal uuid:=atlas.require_active_task_principal_v1();
 v_actor uuid:=atlas.personal_task_ready_person_v1(auth.uid());
 v_items jsonb;
BEGIN
 IF v_principal IS NULL OR v_actor IS NULL THEN
  RAISE EXCEPTION 'Signed Person required' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('personId',q.peer_person_id,'name',q.peer_name)
  ORDER BY q.peer_name,q.peer_person_id),'[]'::jsonb) INTO v_items
 FROM (SELECT DISTINCT ON(peer_person_id) peer_person_id,peer_name
   FROM atlas.personal_task_connection_peers_v1(auth.uid())
   ORDER BY peer_person_id,connection_id) q;
 RETURN jsonb_build_object('ok',true,'contractVersion','personal_connected_task_choices_v1',
  'actorPersonId',v_actor,'items',v_items);
END
$fn$;
CREATE FUNCTION atlas.create_connected_personal_task_self_api_v1(
 p_sentence text,p_due_date date,p_recipient_person_id uuid,p_source_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_principal uuid:=atlas.require_active_task_principal_v1();
 v_actor uuid:=atlas.personal_task_ready_person_v1(auth.uid());
 v_created jsonb;v_assignment jsonb;v_id uuid;
BEGIN
 IF v_principal IS NULL OR v_actor IS NULL OR p_recipient_person_id IS NULL
  OR p_recipient_person_id=v_actor OR p_source_action_id IS NULL THEN
  RAISE EXCEPTION 'Exact connected Person and action required' USING ERRCODE='22023'; END IF;
 -- Both existing writers participate in this single SQL transaction. A failed
 -- connection/assignment rolls back creation; exact retries retain both identities.
 v_created:=atlas.create_atlas_task_self_api_v1(p_sentence,p_due_date,
  'daily:connected:'||p_source_action_id::text);
 v_id:=(v_created->'task'->>'id')::uuid;
 IF v_created->>'ok' IS DISTINCT FROM 'true' OR v_id IS NULL THEN
  RAISE EXCEPTION 'Original creation unconfirmed' USING ERRCODE='PT409'; END IF;
 v_assignment:=atlas.change_personal_task_assignment_self_api_v1(v_id,0,
  p_recipient_person_id,'{}'::uuid[],p_source_action_id);
 IF v_assignment->>'ok' IS DISTINCT FROM 'true' OR
  v_assignment->>'taskId' IS DISTINCT FROM v_id::text OR
  v_assignment->>'primaryPersonId' IS DISTINCT FROM p_recipient_person_id::text OR
  v_assignment->>'revision' IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'Original assignment unconfirmed' USING ERRCODE='PT409'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','connected_personal_task_creation_v1',
  'task',v_created->'task','assignment',v_assignment,'oneOriginalTaskId',true,
  'acceptanceRequired',false,'institutionalWorkChanged',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_connected_task_choices_self_api_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.create_connected_personal_task_self_api_v1(text,date,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.personal_connected_task_choices_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.create_connected_personal_task_self_api_v1(text,date,uuid,uuid) TO authenticated;
CREATE FUNCTION public.personal_connected_task_choices_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.personal_connected_task_choices_self_api_v1(); $fn$;
CREATE FUNCTION public.create_connected_personal_task_self_api_v1(
 p_sentence text,p_due_date date,p_recipient_person_id uuid,p_source_action_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.create_connected_personal_task_self_api_v1(
 p_sentence,p_due_date,p_recipient_person_id,p_source_action_id); $fn$;
REVOKE ALL ON FUNCTION public.personal_connected_task_choices_self_api_v1() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_connected_personal_task_self_api_v1(text,date,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.personal_connected_task_choices_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_connected_personal_task_self_api_v1(text,date,uuid,uuid) TO authenticated;
-- Self-responsibility is not a peer dispatch. Reuse the governed native intake,
-- original responsibility and actual placement in one transaction.
CREATE FUNCTION atlas.create_self_ledger_task_self_api_v1(
 p_ledger_id uuid,p_sentence text,p_execution_date date,p_source_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_actor uuid:=atlas.current_person_id_v1();
 v_intake jsonb; v_assignment jsonb; v_place jsonb;
 v_id uuid; v_org uuid; v_allocation uuid; v_plan uuid;
BEGIN
 IF v_actor IS NULL OR p_ledger_id IS NULL OR p_execution_date IS NULL OR p_source_action_id IS NULL
 THEN RAISE EXCEPTION 'Exact Ledger, day and action required' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id) c WHERE c.person_id=v_actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'Exact Ledger authority required' USING ERRCODE='42501'; END IF;
 v_intake:=atlas.record_ledger_work_self_api_v2(p_ledger_id,p_sentence,p_execution_date,
   'daily:self-ledger:'||p_source_action_id::text);
 v_id:=(v_intake->>'workItemId')::uuid;
 SELECT organization_id INTO v_org FROM atlas.ledger_work_intakes
 WHERE id=(v_intake->>'intakeId')::uuid AND work_item_id=v_id AND ledger_id=p_ledger_id
 AND submitted_by_person_id=v_actor AND review_state='accepted_for_ledger';
 IF v_intake->>'ok' IS DISTINCT FROM 'true' OR v_id IS NULL OR v_org IS NULL
 THEN RAISE EXCEPTION 'Accepted original required' USING ERRCODE='PT409'; END IF;
 v_assignment:=atlas.work_focus_owner_reassign_direct_self_api_v1(v_org,p_ledger_id,v_id,NULL,
   v_actor,'Author selected own Ledger responsibility in Today.',p_source_action_id);
 v_allocation:=(v_assignment->>'newAllocationId')::uuid;
 IF v_assignment->>'ok' IS DISTINCT FROM 'true' OR v_allocation IS NULL
 OR v_assignment->>'currentResponsiblePersonId' IS DISTINCT FROM v_actor::text
 OR v_assignment->>'workItemId' IS DISTINCT FROM v_id::text
 THEN RAISE EXCEPTION 'Original responsibility unconfirmed' USING ERRCODE='PT409'; END IF;
 IF v_intake->>'createdNow'='true' THEN
   v_place:=atlas.connected_person_place_work_self_api_v1(v_id,p_execution_date,
     'Author selected work day in Today.');
   IF v_place->>'ok' IS DISTINCT FROM 'true' OR v_place->>'executionDate' IS DISTINCT FROM p_execution_date::text
   OR v_place->>'responsiblePersonId' IS DISTINCT FROM v_actor::text
   OR v_place->>'workItemId' IS DISTINCT FROM v_id::text
   OR v_place->>'ledgerId' IS DISTINCT FROM p_ledger_id::text
   THEN RAISE EXCEPTION 'Original placement unconfirmed' USING ERRCODE='PT409'; END IF;
 END IF;
 -- An exact retry may confirm the still-current original, never reschedule it.
 SELECT id INTO v_plan FROM atlas.work_execution_plans WHERE work_item_id=v_id
  AND organization_id=v_org AND responsible_allocation_id=v_allocation AND plan_state='active'
  AND planned_service_date=p_execution_date AND exposure_service_date=p_execution_date;
 IF v_plan IS NULL THEN RAISE EXCEPTION 'Original plan changed; reopen Work' USING ERRCODE='PT409'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','self_ledger_task_creation_v1',
  'workItemId',v_id,'ledgerId',p_ledger_id,'organizationId',v_org,'allocationId',v_allocation,
  'planId',v_plan,'responsiblePersonId',v_actor,'executionDate',p_execution_date,
  'oneCanonicalWorkIdentity',true,'newPersonalTaskCreated',false,'acceptanceRequired',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.create_self_ledger_task_self_api_v1(uuid,text,date,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.create_self_ledger_task_self_api_v1(uuid,text,date,uuid) TO authenticated;
CREATE FUNCTION public.create_self_ledger_task_self_api_v1(
 p_ledger_id uuid,p_sentence text,p_execution_date date,p_source_action_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.create_self_ledger_task_self_api_v1(p_ledger_id,p_sentence,p_execution_date,p_source_action_id); $fn$;
REVOKE ALL ON FUNCTION public.create_self_ledger_task_self_api_v1(uuid,text,date,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_self_ledger_task_self_api_v1(uuid,text,date,uuid) TO authenticated;
-- Exact contextual authoring: reuse canonical ordinary Work, never Event checklist.
-- A date is optional; NULL Person means signed author unless explicitly unassigned.
CREATE FUNCTION atlas.create_contextual_ledger_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_sentence text,
 p_recipient_person_id uuid,p_execution_date date,p_unassigned boolean,p_source_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE actor uuid:=atlas.current_person_id_v1(); target uuid;
 action text:='composer:'||p_source_action_id::text;
 original uuid; intake_original uuid; direct_original uuid; link_occurrence uuid; link_count integer;
 receipt jsonb; allocation jsonb; placement jsonb; linked jsonb;
 work_id uuid; alloc_id uuid; plan_id uuid; intake_id uuid; review_state text;
 new_now boolean; actual_org uuid; n integer;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
 OR p_unassigned IS NULL OR p_source_action_id IS NULL OR
 (p_unassigned AND (p_recipient_person_id IS NOT NULL OR p_execution_date IS NOT NULL))
 THEN RAISE EXCEPTION 'Exact composer context and action required' USING ERRCODE='22023'; END IF;
 SELECT count(*),(array_agg(x.organization_id))[1] INTO n,actual_org
 FROM atlas.ledger_organization_participations x JOIN atlas.ledgers l ON l.id=x.ledger_id AND l.status='active'
 JOIN ledger.ledgers nl ON nl.id=x.ledger_id AND nl.ledger_state='active' AND nl.retired_at IS NULL
 WHERE x.ledger_id=p_ledger_id AND x.status='active' AND x.ended_at IS NULL AND x.participation_kind IN ('governing','operating');
 IF n<>1 OR actual_org IS DISTINCT FROM p_organization_id THEN
  RAISE EXCEPTION 'Exact operating Ledger required' USING ERRCODE='42501'; END IF;
 IF p_occurrence_id IS NOT NULL THEN
  PERFORM atlas.ledger_occurrence_shared_work_actor_self_v1(p_organization_id,p_ledger_id,p_occurrence_id);
 END IF;
 IF NOT p_unassigned THEN
  PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id) c WHERE c.person_id=actor;
  IF NOT FOUND THEN RAISE EXCEPTION 'Exact Ledger governing authority required' USING ERRCODE='42501'; END IF;
  target:=coalesce(p_recipient_person_id,actor);
  IF NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,target)
  THEN RAISE EXCEPTION 'Current connected Person required' USING ERRCODE='42501'; END IF;
 END IF;
 -- Serialize across both existing source writers for the same logical action.
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.contextual-composer:'||actor::text||':'||action,0));
 SELECT i.work_item_id INTO intake_original FROM atlas.ledger_work_intakes i
 WHERE i.submitted_by_person_id=actor AND i.source_action_id=action;
 SELECT w.id INTO direct_original FROM atlas.work_items w
 WHERE w.organization_id=p_organization_id AND w.stable_key='ledger-direct:'||auth.uid()::text||':'||md5(action);
 -- A different Ledger/organization with the same direct action must not create a second original.
 IF EXISTS(SELECT 1 FROM atlas.work_items w WHERE w.stable_key='ledger-direct:'||auth.uid()::text||':'||md5(action)
 AND w.organization_id<>p_organization_id) OR (intake_original IS NOT NULL AND direct_original IS NOT NULL)
 THEN RAISE EXCEPTION 'Action already belongs to another original' USING ERRCODE='23505'; END IF;
 original:=coalesce(intake_original,direct_original);
 IF original IS NOT NULL THEN
  SELECT count(*),(array_agg(a.occurrence_id))[1] INTO link_count,link_occurrence
  FROM atlas.ledger_occurrence_work_actions_v1 a
  WHERE a.work_item_id=original AND a.actor_person_id=actor AND a.action_kind='linked' AND a.source_action_id=action;
  IF link_count>1 OR link_occurrence IS DISTINCT FROM p_occurrence_id
  OR (p_occurrence_id IS NOT NULL AND EXISTS(SELECT 1 FROM atlas.ledger_occurrence_work_actions_v1 a
    WHERE a.work_item_id=original AND a.ledger_id=p_ledger_id AND a.occurrence_id=p_occurrence_id AND a.action_kind='removed'))
  THEN RAISE EXCEPTION 'Original Event context changed' USING ERRCODE='23505'; END IF;
 END IF;
 IF NOT p_unassigned AND target<>actor AND p_execution_date IS NOT NULL THEN
  IF intake_original IS NOT NULL THEN RAISE EXCEPTION 'Different original operation' USING ERRCODE='23505'; END IF;
  receipt:=atlas.connected_ledger_direct_assign_self_api_v1(p_ledger_id,target,p_sentence,p_execution_date,action);
  work_id:=(receipt->>'workItemId')::uuid;alloc_id:=(receipt->>'allocationId')::uuid;plan_id:=(receipt->>'planId')::uuid;
  IF receipt->>'ok' IS DISTINCT FROM 'true' OR work_id IS NULL OR alloc_id IS NULL OR plan_id IS NULL
  THEN RAISE EXCEPTION 'Dated original not confirmed' USING ERRCODE='PT409'; END IF;
  review_state:='accepted_for_ledger';
 ELSE
  IF direct_original IS NOT NULL THEN RAISE EXCEPTION 'Different original operation' USING ERRCODE='23505'; END IF;
  receipt:=atlas.record_ledger_work_self_api_v2(p_ledger_id,p_sentence,p_execution_date,action);
  work_id:=(receipt->>'workItemId')::uuid;intake_id:=(receipt->>'intakeId')::uuid;
  review_state:=receipt->>'reviewState';new_now:=receipt->>'createdNow'='true';
  IF receipt->>'ok' IS DISTINCT FROM 'true' OR work_id IS NULL OR intake_id IS NULL
  THEN RAISE EXCEPTION 'Original intake not confirmed' USING ERRCODE='PT409'; END IF;
  IF NOT p_unassigned THEN
   IF review_state IS DISTINCT FROM 'accepted_for_ledger'
   THEN RAISE EXCEPTION 'Accepted original required' USING ERRCODE='42501'; END IF;
   -- Do not turn a prior explicit unassigned submission into a different action.
   IF NOT new_now AND NOT EXISTS(SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=work_id
     AND a.metadata->>'source'='native_ledger_intake_responsibility_v1'
     AND a.establishment_basis->>'sourceActionId'=p_source_action_id::text)
   THEN RAISE EXCEPTION 'Prior action was unassigned' USING ERRCODE='23505'; END IF;
   allocation:=atlas.work_focus_owner_reassign_direct_self_api_v1(p_organization_id,p_ledger_id,work_id,NULL,target,
    'Author selected responsibility in the notebook.',p_source_action_id);
   alloc_id:=(allocation->>'newAllocationId')::uuid;
   IF allocation->>'ok' IS DISTINCT FROM 'true' OR alloc_id IS NULL
    OR allocation->>'currentResponsiblePersonId' IS DISTINCT FROM target::text
   THEN RAISE EXCEPTION 'Original responsibility not confirmed' USING ERRCODE='PT409'; END IF;
   IF p_execution_date IS NOT NULL THEN
    IF target IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Exact self placement required' USING ERRCODE='42501'; END IF;
    IF new_now THEN
     placement:=atlas.connected_person_place_work_self_api_v1(work_id,p_execution_date,'Author selected work day in the notebook.');
     IF placement->>'ok' IS DISTINCT FROM 'true' OR placement->>'executionDate' IS DISTINCT FROM p_execution_date::text
     THEN RAISE EXCEPTION 'Original placement not confirmed' USING ERRCODE='PT409'; END IF;
    END IF;
    SELECT id INTO plan_id FROM atlas.work_execution_plans WHERE work_item_id=work_id AND responsible_allocation_id=alloc_id
     AND plan_state='active' AND planned_service_date=p_execution_date AND exposure_service_date=p_execution_date;
    IF plan_id IS NULL THEN RAISE EXCEPTION 'Original plan changed' USING ERRCODE='PT409'; END IF;
   END IF;
  ELSE
   IF EXISTS(SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=work_id AND a.allocation_role='responsible')
   THEN RAISE EXCEPTION 'Original responsibility changed' USING ERRCODE='PT409'; END IF;
  END IF;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.work_items w WHERE w.id=work_id AND w.organization_id=p_organization_id
   AND w.work_state='open' AND w.title=btrim(p_sentence))
 OR (NOT p_unassigned AND NOT EXISTS(SELECT 1 FROM atlas.work_allocations a
   WHERE a.id=alloc_id AND a.work_item_id=work_id AND a.state='active' AND a.allocation_role='responsible'
    AND a.assignee_canonical_person_id=target))
 OR (p_execution_date IS NOT NULL AND NOT EXISTS(SELECT 1 FROM atlas.work_execution_plans p
   WHERE p.id=plan_id AND p.work_item_id=work_id AND p.responsible_allocation_id=alloc_id
    AND p.plan_state='active' AND p.planned_service_date=p_execution_date AND p.exposure_service_date=p_execution_date))
 OR (p_execution_date IS NULL AND EXISTS(SELECT 1 FROM atlas.work_execution_plans p
   WHERE p.work_item_id=work_id AND p.plan_state IN ('active','needs_replan')))
 THEN RAISE EXCEPTION 'Original Work changed; reopen it' USING ERRCODE='PT409'; END IF;
 IF p_occurrence_id IS NOT NULL THEN
  linked:=atlas.link_existing_ledger_event_work_self_api_v1(p_organization_id,p_ledger_id,p_occurrence_id,work_id,action);
  IF linked->>'ok' IS DISTINCT FROM 'true' OR linked->>'workItemId' IS DISTINCT FROM work_id::text
  THEN RAISE EXCEPTION 'Event context not confirmed' USING ERRCODE='PT409'; END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','contextual_ledger_work_creation_v1',
 'organizationId',p_organization_id,'ledgerId',p_ledger_id,'occurrenceId',p_occurrence_id,
 'workItemId',work_id,'intakeId',intake_id,'allocationId',alloc_id,'planId',plan_id,
 'responsiblePersonId',target,'executionDate',p_execution_date,'reviewState',review_state,
 'newPersonalTaskCreated',false,'oneCanonicalWorkIdentity',true);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid) TO authenticated;
CREATE FUNCTION public.create_contextual_ledger_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_sentence text,
 p_recipient_person_id uuid,p_execution_date date,p_unassigned boolean,p_source_action_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$ SELECT atlas.create_contextual_ledger_work_self_api_v1($1,$2,$3,$4,$5,$6,$7,$8); $fn$;
REVOKE ALL ON FUNCTION public.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_contextual_ledger_work_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid) TO authenticated;
COMMIT;

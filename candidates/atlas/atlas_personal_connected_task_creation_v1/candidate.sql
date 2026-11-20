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
COMMIT;

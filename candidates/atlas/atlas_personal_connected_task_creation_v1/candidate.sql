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
COMMIT;

-- Exact structural custody only; signed original-lifecycle proof is separate.
DO $check$
DECLARE v_table oid;v_fn oid;v_sig text;
BEGIN
 FOREACH v_sig IN ARRAY ARRAY['atlas.personal_task_assignment_revisions_v1','atlas.personal_task_shared_completion_events_v1'] LOOP
  v_table:=to_regclass(v_sig);
  IF v_table IS NULL OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table)
   OR EXISTS(SELECT 1 FROM (VALUES('anon'),('authenticated'),('service_role')) roles(role_name)
    WHERE has_table_privilege(roles.role_name,v_table,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
   OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=v_table AND NOT tgisinternal AND tgname LIKE 'personal_task%immutable_v1')
  THEN RAISE EXCEPTION 'Private immutable personal history custody failed: %',v_sig; END IF;
 END LOOP;
 FOREACH v_sig IN ARRAY ARRAY[
 'atlas.personal_task_ready_person_v1(uuid)',
 'atlas.personal_task_connection_peers_v1(uuid)',
 'atlas.personal_task_assignment_recipient_current_v1(uuid,uuid)',
 'atlas.personal_task_assigned_actor_v1(uuid,uuid,uuid)',
 'atlas.personal_task_lock_recipient_v1(uuid,uuid)']
 LOOP
  v_fn:=to_regprocedure(v_sig);
  IF v_fn IS NULL OR has_function_privilege('anon',v_fn,'EXECUTE')
   OR has_function_privilege('authenticated',v_fn,'EXECUTE')
   OR has_function_privilege('service_role',v_fn,'EXECUTE')
   OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=v_fn AND a.grantee=0 AND a.privilege_type='EXECUTE')
  THEN RAISE EXCEPTION 'Private resolver custody failed: %',v_sig; END IF;
 END LOOP;
 FOREACH v_sig IN ARRAY ARRAY[
 'atlas.read_personal_task_assignment_self_api_v1(uuid)',
 'public.read_personal_task_assignment_self_api_v1(uuid)',
 'atlas.change_personal_task_assignment_self_api_v1(uuid,bigint,uuid,uuid[],uuid)',
 'public.change_personal_task_assignment_self_api_v1(uuid,bigint,uuid,uuid[],uuid)',
 'atlas.personal_sent_original_tasks_self_api_v1(integer,uuid)',
 'public.personal_sent_original_tasks_self_api_v1(integer,uuid)']
 LOOP
  v_fn:=to_regprocedure(v_sig);
  IF v_fn IS NULL OR has_function_privilege('anon',v_fn,'EXECUTE')
   OR NOT has_function_privilege('authenticated',v_fn,'EXECUTE')
   OR has_function_privilege('service_role',v_fn,'EXECUTE')
   OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE p.oid=v_fn AND a.grantee=0 AND a.privilege_type='EXECUTE')
   OR (SELECT prosecdef FROM pg_proc WHERE oid=v_fn) IS DISTINCT FROM (v_sig LIKE 'atlas.%')
  THEN RAISE EXCEPTION 'Signed RPC custody failed: %',v_sig; END IF;
 END LOOP;
 IF position('personal_task_assigned_actor_v1' in (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('atlas.atlas_task_day_self_api_v1(date)')))=0
 OR position('personal_task_lock_recipient_v1' in (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)')))=0
 THEN RAISE EXCEPTION 'Original lifecycle not integrated'; END IF;
 RAISE NOTICE 'PASS structural custody; signed proof must run separately';
END
$check$;

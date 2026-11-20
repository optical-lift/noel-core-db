-- Structural source checks, not signed authorization or lifecycle proof.
DO $check$
DECLARE v_table oid:=to_regclass('atlas.personal_task_assignment_revisions_v1');v_fn oid;v_sig text;
BEGIN
 IF v_table IS NULL OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table)
 OR EXISTS(SELECT 1 FROM (VALUES('anon'),('authenticated'),('service_role')) roles(role_name)
  WHERE has_table_privilege(roles.role_name,v_table,'SELECT,INSERT,UPDATE,DELETE'))
 THEN RAISE EXCEPTION 'Private personal assignment relation required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=v_table AND
  tgname='personal_task_assignment_immutable_v1' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Assignment revision immutability missing'; END IF;
 FOREACH v_sig IN ARRAY ARRAY[
 'atlas.personal_task_ready_person_v1(uuid)',
 'atlas.personal_task_connection_peers_v1(uuid)',
 'atlas.personal_task_assignment_recipient_current_v1(uuid,uuid)',
 'atlas.read_personal_task_assignment_self_api_v1(uuid)',
 'atlas.change_personal_task_assignment_self_api_v1(uuid,bigint,uuid,uuid[],uuid)']
 LOOP
  v_fn:=to_regprocedure(v_sig);
  IF v_fn IS NULL OR has_function_privilege('anon',v_fn,'EXECUTE')
   OR has_function_privilege('authenticated',v_fn,'EXECUTE')
   OR has_function_privilege('service_role',v_fn,'EXECUTE')
   OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid=v_fn AND a.grantee=0 AND a.privilege_type='EXECUTE')
  THEN RAISE EXCEPTION 'Held assignment function custody failed: %',v_sig; END IF;
 END LOOP;
 IF to_regprocedure('public.change_personal_task_assignment_self_api_v1(uuid,bigint,uuid,uuid[],uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'Held assignment must not yet expose public mutation'; END IF;
 RAISE NOTICE 'PASS held structural custody only; no signed proof performed';
END
$check$;

DO $lifecycle$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=to_regclass('atlas.personal_task_shared_completion_events_v1') AND relrowsecurity)
 OR EXISTS(SELECT 1 FROM (VALUES ('anon'),('authenticated'),('service_role')) r(n)
 WHERE has_table_privilege(r.n,'atlas.personal_task_shared_completion_events_v1','SELECT,INSERT,UPDATE,DELETE'))
 THEN RAISE EXCEPTION 'Shared completion private provenance custody missing'; END IF;
 IF to_regprocedure('public.personal_sent_original_tasks_self_api_v1(integer,uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'Held sent reader must not be exposed'; END IF;
 IF position('personal_task_assigned_actor_v1' in (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('atlas.atlas_task_day_self_api_v1(date)')))=0
 OR position('personal_task_lock_recipient_v1' in (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)')))=0
 THEN RAISE EXCEPTION 'Original lifecycle not integrated'; END IF;
END
$lifecycle$;

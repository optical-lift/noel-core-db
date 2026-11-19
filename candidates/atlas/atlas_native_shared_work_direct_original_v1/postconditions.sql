DO $proof$
BEGIN
 IF to_regprocedure('atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('anon','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR pg_catalog.has_function_privilege('service_role','atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR to_regclass('atlas.native_self_participation_active_v1') IS NULL
 OR to_regclass('atlas.native_self_participation_action_v1') IS NULL
 OR to_regclass('atlas.work_allocations_one_active_responsible_idx') IS NULL
 OR to_regprocedure('atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 OR to_regprocedure('atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='atlas.work_items'::regclass AND tgname='native_self_participation_work_terminal_v1' AND NOT tgisinternal)
 OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger WHERE tgrelid='atlas.work_allocations'::regclass AND tgname='native_self_participation_primary_release_v1' AND NOT tgisinternal)
 OR to_regprocedure('atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)') IS NULL
 OR pg_catalog.has_function_privilege('authenticated','atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)','EXECUTE')
 OR to_regclass('atlas.native_direct_participation_actor_action_v1') IS NULL
 THEN RAISE EXCEPTION 'Native participation internal custody postcondition failed'; END IF;
END
$proof$;

-- Verify the exact release-candidate wrapper ACL, not a test-created adapter.
DO $rest$
DECLARE pair text; v_public oid; v_internal oid;
BEGIN
 FOREACH pair IN ARRAY ARRAY['connected_person_my_work_self_api_v2(integer,uuid)',
   'owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid)',
   'owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)',
   'native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)',
   'join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)',
   'leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)'] LOOP
   v_public:=to_regprocedure('public.'||pair); v_internal:=to_regprocedure('atlas.'||pair);
   IF v_public IS NULL OR v_internal IS NULL
     OR NOT has_function_privilege('authenticated',v_public,'EXECUTE')
     OR has_function_privilege('anon',v_public,'EXECUTE')
     OR has_function_privilege('service_role',v_public,'EXECUTE')
     OR has_function_privilege('authenticated',v_internal,'EXECUTE')
     OR has_function_privilege('anon',v_internal,'EXECUTE')
     OR has_function_privilege('service_role',v_internal,'EXECUTE')
     OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
       WHERE p.oid IN(v_public,v_internal) AND x.grantee=0 AND x.privilege_type='EXECUTE')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_public AND p.prosecdef AND ('search_path=""'=ANY(p.proconfig)))
   THEN RAISE EXCEPTION 'Shared Work REST custody differs: %',pair; END IF;
 END LOOP;
END
$rest$;
-- VALIDATION-ONLY: run in disposable clone after loading candidate.sql.
-- This is not a database migration and does not authorize Production access.
DO $postconditions$
DECLARE
  v_table oid := to_regclass('atlas.native_original_work_comments_v1');
  v_actor oid := to_regprocedure(
    'atlas.native_original_work_comment_actor_v1(uuid,uuid,uuid,boolean)');
  v_write oid := to_regprocedure(
    'atlas.append_native_original_work_comment_self_api_v1(uuid,uuid,uuid,uuid,text)');
  v_read oid := to_regprocedure(
    'atlas.read_native_original_work_comments_self_api_v1(uuid,uuid,uuid,integer,timestamptz,uuid)');
  v_pub_write oid := to_regprocedure(
    'public.append_native_original_work_comment_self_api_v1(uuid,uuid,uuid,uuid,text)');
  v_pub_read oid := to_regprocedure(
    'public.read_native_original_work_comments_self_api_v1(uuid,uuid,uuid,integer,timestamptz,uuid)');
  v_fn oid;
BEGIN
  IF v_table IS NULL OR v_actor IS NULL OR v_write IS NULL OR
     v_read IS NULL OR v_pub_write IS NULL OR v_pub_read IS NULL THEN
    RAISE EXCEPTION 'Work comments candidate incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c WHERE c.oid=v_table AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'Comment table lacks RLS';
  END IF;
  IF has_table_privilege('anon',v_table,'SELECT')
    OR has_table_privilege('authenticated',v_table,'SELECT')
    OR has_table_privilege('authenticated',v_table,'INSERT')
    OR has_table_privilege('authenticated',v_table,'UPDATE')
    OR has_table_privilege('authenticated',v_table,'DELETE') THEN
    RAISE EXCEPTION 'Direct browser table access is forbidden';
  END IF;
  FOR v_fn IN SELECT unnest(ARRAY[v_actor,v_write,v_read]) LOOP
    IF has_function_privilege('anon',v_fn,'EXECUTE')
      OR has_function_privilege('authenticated',v_fn,'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_proc p, LATERAL aclexplode(
          coalesce(p.proacl,acldefault('f',p.proowner))
        ) x WHERE p.oid=v_fn AND x.grantee=0 AND x.privilege_type='EXECUTE'
      ) THEN
      RAISE EXCEPTION 'Internal Work comment function publicly callable';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=v_fn AND p.prosecdef
        AND ('search_path=""'=ANY(p.proconfig))
    ) THEN
      RAISE EXCEPTION 'Internal Work comment function shape changed';
    END IF;
  END LOOP;
  FOR v_fn IN SELECT unnest(ARRAY[v_pub_write,v_pub_read]) LOOP
    IF NOT has_function_privilege('authenticated',v_fn,'EXECUTE')
      OR has_function_privilege('anon',v_fn,'EXECUTE')
      OR EXISTS (
        SELECT 1 FROM pg_proc p, LATERAL aclexplode(
          coalesce(p.proacl,acldefault('f',p.proowner))
        ) x WHERE p.oid=v_fn AND x.grantee=0 AND x.privilege_type='EXECUTE'
      ) THEN
      RAISE EXCEPTION 'Public Work comment wrapper ACL changed';
    END IF;
  END LOOP;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid=v_table
      AND t.tgname='reject_native_original_work_comment_mutation_v1'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'Immutable comment mutation trigger missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid=v_table
      AND c.conname='native_original_work_comment_replay_v1'
      AND c.contype='u'
  ) THEN
    RAISE EXCEPTION 'Unique same-actor action receipt missing';
  END IF;
  RAISE NOTICE 'Structural candidate checks PASS; signed authority tests NOT run';
END;
$postconditions$;

DO $direct$
DECLARE v_sig text; v_fn oid;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.native_intake_responsibility_owner_context_v1(uuid,uuid,uuid)')) IS DISTINCT FROM '06be4722570129e02f2ba96bb07c1a21' THEN RAISE EXCEPTION 'Pinned original source differs: native_intake_responsibility_owner_context_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)')) IS DISTINCT FROM '18d75444286f5fd33aa8d28b5ae4d645' THEN RAISE EXCEPTION 'Pinned original source differs: owner_set_connected_person_work_day_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)')) IS DISTINCT FROM 'a7bc5d132c73adc927bb09bedbfb8b8f' THEN RAISE EXCEPTION 'Pinned original source differs: work_focus_owner_reassign_direct_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid)')) IS DISTINCT FROM '08cc9cfd306ecb71563ea1eab8e87695' THEN RAISE EXCEPTION 'Pinned original source differs: work_focus_owner_reassignment_preflight_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.guard_work_allocation_responsibility_establishment_v2()')) IS DISTINCT FROM '411b87c710cee0e49ddbae84bf95e3f2' THEN RAISE EXCEPTION 'Pinned original source differs: guard_work_allocation_responsibility_establishment_v2'; END IF;
 v_fn:=to_regprocedure('atlas.native_original_work_participation_owner_context_v1(uuid,uuid,uuid)');
 IF v_fn IS NULL OR has_function_privilege('authenticated',v_fn,'EXECUTE') OR has_function_privilege('anon',v_fn,'EXECUTE') OR has_function_privilege('service_role',v_fn,'EXECUTE') OR EXISTS(SELECT 1 FROM pg_proc p,LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE p.oid=v_fn AND x.grantee=0 AND x.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'Internal participation resolver ACL differs'; END IF;
 FOREACH v_sig IN ARRAY ARRAY['atlas.guard_work_allocation_participation_establishment_v1()', 'atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)', 'atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)', 'atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)', 'atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)', 'atlas.owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid)'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(v_sig) AND p.prosrc LIKE '%native_original_work_participation_owner_context_v1(%' AND p.prosecdef) THEN RAISE EXCEPTION 'Participation consumer not reconciled: %',v_sig; END IF;
 END LOOP;
END
$direct$;

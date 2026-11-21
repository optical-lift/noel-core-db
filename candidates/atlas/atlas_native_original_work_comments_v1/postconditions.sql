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

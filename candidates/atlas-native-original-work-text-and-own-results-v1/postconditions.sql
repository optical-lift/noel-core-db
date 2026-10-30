-- Clone/rollback-only structural and negative security checks.
-- Run AFTER candidate.sql inside a disposable transaction. No production write.
-- These tests do NOT prove actual signed-owner positive acceptance, nor
-- reveal other participants' notes; those are mandatory human release gates.

DO $check$
DECLARE
  v_table regclass:=to_regclass('atlas.native_work_text_revision_events_v1');
  v_func regprocedure;
BEGIN
  IF v_table IS NULL THEN RAISE EXCEPTION 'No native Work revision log'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_class WHERE oid=v_table AND relrowsecurity
  ) THEN RAISE EXCEPTION 'Revision log RLS is not enabled'; END IF;
  IF has_table_privilege('authenticated',v_table,'SELECT')
     OR has_table_privilege('authenticated',v_table,'INSERT')
     OR has_table_privilege('authenticated',v_table,'UPDATE')
     OR has_table_privilege('authenticated',v_table,'DELETE')
     OR has_table_privilege('anon',v_table,'SELECT') THEN
    RAISE EXCEPTION 'Browser roles must not query/mutate Work revisions directly';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_trigger t WHERE t.tgrelid=v_table
      AND t.tgname='native_work_text_revision_append_only_v1'
      AND NOT t.tgisinternal
  ) THEN RAISE EXCEPTION 'Immutable audit trigger absent'; END IF;
  FOR v_func IN
    SELECT oid FROM pg_proc WHERE oid IN(
      'public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)'::regprocedure,
      'public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)'::regprocedure,
      'public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)'::regprocedure)
  LOOP
    IF NOT has_function_privilege('authenticated',v_func,'EXECUTE')
       OR has_function_privilege('anon',v_func,'EXECUTE') THEN
      RAISE EXCEPTION 'Signed-only native Work read/write membrane is not enforced';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_proc WHERE oid IN(
      'public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)'::regprocedure,
      'public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)'::regprocedure,
      'public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)'::regprocedure))<>3 THEN
    RAISE EXCEPTION 'Native Work source membrane incomplete';
  END IF;
END $check$;

-- Fail-closed signed role with NO actor JWT. This proves 42501, not a 404.
-- SET ROLE (not SET LOCAL ROLE outside a transaction) ensures the denial
-- tests really run as authenticated, not as the clone superuser.
SET ROLE authenticated;
DO $check$
DECLARE
  v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM public.read_native_original_work_text_owner_self_api_v1(
      '00000000-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000002'::uuid,
      '00000000-0000-0000-0000-000000000003'::uuid);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=true; END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'No-JWT signed actor could read native Work text';
  END IF;
  v_denied:=false;
  BEGIN
    PERFORM public.read_native_original_work_own_results_self_api_v1(
      '00000000-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000002'::uuid,
      '00000000-0000-0000-0000-000000000003'::uuid,30);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=true; END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'No-JWT signed actor could read Work Result narrative';
  END IF;
  v_denied:=false;
  BEGIN
    PERFORM public.revise_native_original_work_text_owner_self_api_v1(
      '00000000-0000-0000-0000-000000000001'::uuid,
      '00000000-0000-0000-0000-000000000002'::uuid,
      '00000000-0000-0000-0000-000000000003'::uuid,
      clock_timestamp(),'unauthorized',null);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=true; END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'No-JWT signed actor could revise original Work text';
  END IF;
END $check$;
RESET ROLE;

-- Positive validation MUST be on a disposable copy of real authorized
-- original Work (not imaginary fixtures): governor original, signed worker
-- original, unrelated Person, same Work after amendment, idempotent/no-op,
-- stale-version 40001 rejection, immutable history, unrelated Results intact.

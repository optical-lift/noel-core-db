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
-- Read-only structural postconditions on disposable clone only.
DO $check$
DECLARE
  source_text text;
  writer regprocedure;
BEGIN
  writer:=to_regprocedure('atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)');
  IF writer IS NULL THEN RAISE EXCEPTION 'Existing owner planner missing'; END IF;
  source_text:=pg_get_functiondef(writer::oid);
  IF position('ledger_connection_direct_assignment' in source_text)=0
     OR position('person_has_native_ledger_connection_v1' in source_text)=0
     OR position('company_work_native_ledger_owner_self_v1' in source_text)=0
     OR position('company_work_execution_plan_window_check_v1' in source_text)=0
     OR position('establishment_basis->>''nativeLedgerId''=p_ledger_id::text' in source_text)=0
  THEN RAISE EXCEPTION 'Direct native owner planning or its existing source guards missing'; END IF;
  IF to_regprocedure('public.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)') IS NULL THEN
    RAISE EXCEPTION 'Existing public authenticated RPC membrane missing';
  END IF;
  -- These real source uniqueness constraints prevent two active allocations
  -- or competing current plans from making a one-row writer nondeterministic.
  -- A clone missing them must not be approved even if the function compiles.
  IF NOT EXISTS(
    SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND tablename='work_allocations'
      AND indexname='work_allocations_one_active_responsible_idx'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%'
      AND indexdef LIKE '%(work_item_id)%'
      AND indexdef LIKE '%state = ''active''%'
  ) THEN RAISE EXCEPTION 'One active responsible allocation source constraint missing'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND tablename='work_execution_plans'
      AND indexname='work_execution_plans_one_current_idx'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%'
      AND indexdef LIKE '%(work_item_id)%'
      AND indexdef LIKE '%needs_replan%'
  ) THEN RAISE EXCEPTION 'One current plan source constraint missing'; END IF;
  RAISE NOTICE 'PASS source-only function/guard presence; signed behavior NOT TESTED';
END
$check$;
-- Structural gate only. Run after my-work-status-candidate.sql on the
-- protected disposable PG17 production-schema clone; never on production.
-- This does NOT substitute for signed Auth/REST, revoked Person or outsider proof.
DO $status$
DECLARE
  s text;
  f regprocedure;
BEGIN
  f:=to_regprocedure('atlas.connected_person_my_work_self_api_v1(integer,uuid)');
  IF f IS NULL THEN
    RAISE EXCEPTION 'Existing signed Person My Work reader absent';
  END IF;
  s:=pg_get_functiondef(f::oid);
  IF position('latestResultKind' in s)=0 OR
     position('latest_result.result_kind' in s)=0 OR
     position('r.responsible_allocation_id=a.id' in s)=0 OR
     position('r.work_item_id=w.id' in s)=0 OR
     position('a.assignee_canonical_person_id=v_self' in s)=0 OR
     position('a.state=''active''' in s)=0 OR
     position('w.work_state=''open''' in s)=0 OR
     position('person_original_work_identity_disclosed_self_v1' in s)=0 OR
     position('person_has_native_ledger_connection_v1' in s)=0 OR
     position('optionalRequestsExcluded' in s)=0
  THEN
    RAISE EXCEPTION 'My Work result status is missing a source-identity, connected-Person, or exact responsible-allocation guard';
  END IF;
  IF position('r.payload' in s)>0 OR
     position('payload.note' in s)>0 OR
     position('noteText' in s)>0
  THEN
    RAISE EXCEPTION 'My Work summary must not expose a Result narrative';
  END IF;
  RAISE NOTICE 'PASS structural latest-Result-kind custody only; actor authorization NOT TESTED';
END
$status$;

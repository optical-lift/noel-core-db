-- Run AFTER candidate.sql, 02, 04 and 05 source scripts on disposable
-- production-schema clone only. This does not claim a successful real
-- signed Person/Today test and cannot release the API into production.
DO $test$
DECLARE
  v_writer regprocedure;
BEGIN
  v_writer:=to_regprocedure(
    'atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)');
  IF v_writer IS NULL THEN
    RAISE EXCEPTION 'Observed Need → original Work owner writer missing';
  END IF;
  IF has_function_privilege('anon',v_writer,'EXECUTE')
    OR has_function_privilege('authenticated',v_writer,'EXECUTE')
    OR has_function_privilege('service_role',v_writer,'EXECUTE') THEN
    RAISE EXCEPTION 'Unvalidated original Work source authoring is exposed to clients';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_writer
      AND p.prosecdef AND p.provolatile='v'
      AND 'search_path='=ANY(p.proconfig)
  ) THEN
    RAISE EXCEPTION 'Original Work writer lacks constrained signed source context';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_items'::regclass
      AND c.conname='work_items_one_native_custody_v1'
  ) THEN RAISE EXCEPTION 'One native Work custody proof missing'; END IF;
  IF to_regprocedure(
    'atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Existing accepted Person assignment source must be reused';
  END IF;
  IF to_regprocedure(
    'atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)'
  ) IS NULL THEN
    RAISE EXCEPTION 'Original Subject disclosure membrane is unavailable';
  END IF;
  RAISE NOTICE 'Owner source shape protected; actual signed authoring and Today readback NOT proven';
END;
$test$;

DO $negative$
DECLARE
  v_rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
      '00000000-0000-4000-8000-000000000001'::uuid,
      '00000000-0000-4000-8000-000000000002'::uuid,
      '00000000-0000-4000-8000-000000000003'::uuid,
      '00000000-0000-4000-8000-000000000004'::uuid,
      'ready_for_mowing','This observation is synthetic, never a real physical assertion.',
      now(),current_date,
      '00000000-0000-4000-8000-000000000005'::uuid);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_rejected:=true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unknown or unsigned governor cannot originate continuing Work';
  END IF;
  RAISE NOTICE 'Unknown/unsigned synthetic owner rejected';
END;
$negative$;

-- SIGNED ACCEPTANCE REQUIRED BEFORE UNREVOKING THE API:
-- - Governor with accepted ledger-wide Anna-like Person scope and a real
--   specifically disclosed growing_object produces 1 original Work.
-- - Signed Person sees it on actual Today, opens original Work Focus, and
--   reports a real source-qualified physical Actual.
-- - Signed other Ledger, outsider and un-disclosed connected Person
--   cannot discover even the task/Subject identity.
-- - Repeating action ID produces 0 new Work; a new observation against an
--   existing open Need cannot reassign or fabricate another Work.
-- - After completed Actual, old original Work/history remains immutable;
--   subsequent genuine fresh observed Need can create one NEW serving
--   without the legacy task queue or a bulk backlog.
-- - No phantom Clock admission, farm employee membership or legacy task.
-- - Household Laundry existing Need/Work/Result lifecycle still passes.

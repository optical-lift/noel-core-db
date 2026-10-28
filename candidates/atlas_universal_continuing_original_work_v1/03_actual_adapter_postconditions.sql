-- Disposable protected schema-clone postconditions after candidate.sql
-- and 02_farm_care_actual_adapter.sql. No production test mutations.
-- Signed positive tests MUST still be run with a real connected Person session.
DO $checks$
DECLARE
  v_reporter regprocedure;
  v_contract regprocedure;
BEGIN
  v_reporter:=to_regprocedure(
    'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)');
  v_contract:=to_regprocedure(
    'atlas.continuing_original_work_result_continuation_internal_v1(uuid)');
  IF v_reporter IS NULL OR v_contract IS NULL THEN
    RAISE EXCEPTION 'Original Work physical Actual and continuation functions required';
  END IF;

  IF has_function_privilege('anon',v_reporter,'EXECUTE')
    OR has_function_privilege('authenticated',v_reporter,'EXECUTE')
    OR has_function_privilege('service_role',v_reporter,'EXECUTE')
    OR has_function_privilege('anon',v_contract,'EXECUTE')
    OR has_function_privilege('authenticated',v_contract,'EXECUTE')
  THEN
    RAISE EXCEPTION 'Pre-release Actual or Result continuation exposed to clients';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_proc p
    WHERE p.oid=v_reporter AND p.prosecdef AND p.provolatile='v'
      AND 'search_path='=ANY(p.proconfig)
  ) THEN
    RAISE EXCEPTION 'Care Actual must be source-constrained and volatile';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies pol
    WHERE pol.contract_key='continuing_care_actual_v1'
      AND pol.source_domain='organization'
      AND pol.acceptance_mode='domain_adapter' AND pol.active
      AND pol.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Physical Actual does not have source-owned Result policy';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.care_observation_events'::regclass
      AND t.tgname='care_observation_events_apply_current_state'
      AND t.tgenabled IN ('O','A')
  ) THEN
    RAISE EXCEPTION 'Physical observations cannot update original Subject state';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_result_acceptances'::regclass
      AND c.conname='work_result_acceptances_one_native_custody_v1'
  ) THEN
    RAISE EXCEPTION 'Original Work Actual lacks native custody constraint';
  END IF;

  RAISE NOTICE 'Source Result adapter shape, private grants and core custody checks passed. Signed positive/negative validation remains mandatory.';
END;
$checks$;

-- Negatives in disposable clone. They must not create any Work/Actual.
DO $negative$
DECLARE
  v_denied boolean:=false;
BEGIN
  BEGIN
    PERFORM atlas.record_continuing_care_actual_self_api_v1(
      '00000000-0000-4000-8000-000000000090'::uuid,
      '00000000-0000-4000-8000-000000000091'::uuid,
      'mowed_full','resting',30,'synthetic rejected Result',NULL);
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '42501' THEN
    v_denied:=true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Unsigned or unknown physical Actual did not fail closed';
  END IF;
  RAISE NOTICE 'Unknown/unsigned physical Actual rejected; this is NOT a real signed connected Person test';
END;
$negative$;

-- Required external signed acceptance (not asserted by this file):
-- 1. Native governor establishes exact original Subject + need + Work,
--    proves Ledger relevance, permits worker disclosure and assignment.
-- 2. Signed responsible Person records mowed_full / weeded_full:
--    one accepted original Result + real care event + observation +
--    source state update + satisfaction, no second Work automatically.
-- 3. Partial, acceptable-no-action and blocked each preserve their
--    distinct physical meaning and source state. Replays are idempotent;
--    mixed-payload collisions are denied.
-- 4. Signed unrelated Person/other Ledger/wrong Subject cannot read,
--    report, submit evidence, or enumerate existence.
-- 5. Previous event Work and Household laundry remain unaffected.
-- 6. Reevaluate Need after a genuine result; authorize next Work only
--    when fresh condition/season and native responsibility permit it.

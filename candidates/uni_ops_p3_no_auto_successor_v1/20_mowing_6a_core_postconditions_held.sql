-- UNI-OPS-01 / first mowing 6A scope: isolated PG17 postconditions only.
-- SOURCE-ONLY TEST INPUT. NOT migration, not an API, not runtime acceptance.
-- Run after independently source-approved U1A/U1B/U2A/B/U2C, R01/R02,
-- and the P3 01/02/03/04/06/11/12 source protection subset.
-- The parent deferred_postconditions.sql is the broader farm / legacy
-- suite; do NOT install P3 farm decision table 17 beside Company #2567.
-- This bounded test does not assert Goal, Harvest, seed, other old Done
-- carriers or non-rhythm subjects. Full 6A release proof remains open.
DO $mowing_post$
DECLARE
  v_eval text;
  v_signal text;
  v_original_guard text;
  v_deferred text;
  v_private regprocedure;
  v_name text;
BEGIN
  IF pg_catalog.to_regprocedure(
    'atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)') IS NULL
    OR pg_catalog.to_regprocedure(
    'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)') IS NULL
    OR pg_catalog.to_regprocedure(
    'atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)') IS NULL
    OR pg_catalog.to_regprocedure(
    'atlas.require_uni_ops_original_finalize_on_commit_v1()') IS NULL
    OR pg_catalog.to_regprocedure(
    'atlas.guard_uni_ops_governed_care_original_acceptance_v1()') IS NULL
  THEN
    RAISE EXCEPTION 'Core 6A exact accepted-first/original source missing';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(
    'atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)'::regprocedure)
  INTO v_eval;
  IF position('qualified_evaluation_no_successor' IN v_eval)=0
     OR position('workflow_result' IN v_eval)=0
     OR position('game_master_satisfaction' IN v_eval)=0
     OR position('activation_prerequisite_completed' IN v_eval)=0
     OR position('record_rhythm_transition_v1' IN v_eval)=0
  THEN
    RAISE EXCEPTION 'Result/Done must evaluate state without issuing new Work';
  END IF;

  SELECT pg_catalog.pg_get_functiondef(
    'atlas.signal_work_occurrence_v1(uuid,text,jsonb)'::regprocedure)
  INTO v_signal;
  IF v_signal IS NULL
     OR position('governed_rhythm_clock_signal_held' IN v_signal)=0
     OR position('automatic_task_release_authorized' IN v_signal)=0
     OR position('noAutomaticNextTask' IN v_signal)=0
     OR position('release_eligible_work_v1' IN v_signal)=0
  THEN
    RAISE EXCEPTION 'Source-specific governed clock hold or preserved independent signal missing';
  END IF;

  FOREACH v_name IN ARRAY ARRAY[
    'atlas.ensure_rhythm_task_v1(uuid,text,timestamptz)',
    'atlas.ensure_rhythm_task_v1_base(uuid,text,timestamptz)',
    'atlas.ensure_rhythm_task_without_physical_gate_v1(uuid,text,timestamptz)',
    'atlas.guard_continuing_original_rhythm_old_carrier_v1()'
  ] LOOP
    v_private:=pg_catalog.to_regprocedure(v_name);
    IF v_private IS NULL OR position(
      'uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
      pg_catalog.pg_get_functiondef(v_private))=0
    THEN
      RAISE EXCEPTION 'Existing legacy rhythm Task/occurrence bypass remains';
    END IF;
  END LOOP;

  SELECT pg_catalog.pg_get_functiondef(
    'atlas.guard_uni_ops_governed_care_original_acceptance_v1()'::regprocedure)
  INTO v_original_guard;
  SELECT pg_catalog.pg_get_functiondef(
    'atlas.require_uni_ops_original_finalize_on_commit_v1()'::regprocedure)
  INTO v_deferred;
  IF position('uni_ops_accepted_first_original_source_receipt_held_v1' IN
       v_original_guard)=0
     OR position('require_accepted_prework_standing_original_v1' IN
       v_original_guard)=0
     OR position('resolve_governed_canonical_farm_rule_authority_v1' IN
       v_deferred)=0
  THEN
    RAISE EXCEPTION 'One accepted first original guard or governed COMMIT proof missing';
  END IF;
  IF NOT EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='atlas.work_items'::regclass
        AND t.tgname='c_uni_ops_governed_care_original_acceptance_v1'
        AND t.tgenabled<>'D'
    ) OR NOT EXISTS(
      SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid='atlas.work_items'::regclass
        AND t.tgname='z_uni_ops_governed_original_finalization_v1'
        AND t.tgdeferrable AND t.tginitdeferred AND t.tgenabled<>'D'
    ) THEN
    RAISE EXCEPTION 'Atomic first-original triggers not attached and enabled';
  END IF;

  FOREACH v_name IN ARRAY ARRAY[
    'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)',
    'atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)',
    'atlas.guard_uni_ops_governed_care_original_acceptance_v1()',
    'atlas.require_uni_ops_original_finalize_on_commit_v1()'
  ] LOOP
    v_private:=pg_catalog.to_regprocedure(v_name);
    IF v_private IS NULL
      OR pg_catalog.has_function_privilege('anon',v_private,'EXECUTE')
      OR pg_catalog.has_function_privilege('authenticated',v_private,'EXECUTE')
      OR pg_catalog.has_function_privilege('service_role',v_private,'EXECUTE')
    THEN
      RAISE EXCEPTION 'Private 6A authority became callable by API role';
    END IF;
  END LOOP;
  RAISE NOTICE 'CORE_MOWING_P3_STRUCTURE=PASS; signed Result/Need/issuer side-effects still require real disposable proof';
END
$mowing_post$;

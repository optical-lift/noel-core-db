-- HELD P3: run ONLY in an isolated current-schema PG17 clone AFTER
-- assembling U1A,U1B,U2A/U2B,U2C, approved R01/R02 source, and this P3.
-- Pure structural assertions: not substitute for real signed actor tests.
DO $post$
DECLARE
 v_eval text;
 v_receipt text;
BEGIN
 IF pg_catalog.to_regprocedure(
   'atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)'
 ) IS NULL OR pg_catalog.to_regprocedure(
   'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'
 ) IS NULL THEN
  RAISE EXCEPTION 'P3 original evaluator or U1/U2 receipt missing';
 END IF;
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_eval
 FROM pg_catalog.pg_proc p
 WHERE p.oid='atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)'::regprocedure;
 IF position('qualified_evaluation_no_successor' IN v_eval)=0
    OR position('workflow_precheck' IN v_eval)=0
    OR position('workflow_result' IN v_eval)=0
    OR position('game_master_satisfaction' IN v_eval)=0
    OR position('record_rhythm_transition_v1' IN v_eval)=0
    OR position('ensure_rhythm_task_v1' IN v_eval)=0
 THEN
  RAISE EXCEPTION 'P3 state evaluation or protected non-Result clock branch drift';
 END IF;
 SELECT pg_catalog.pg_get_functiondef(p.oid) INTO v_receipt
 FROM pg_catalog.pg_proc p
 WHERE p.oid='atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'::regprocedure;
 IF position('require_accepted_prework_standing_original_v1' IN v_receipt)=0
   OR position('resolve_governed_canonical_farm_rule_authority_v1' IN v_receipt)=0
   OR position('company_work_native_ledger_owner_self_v1' IN v_receipt)=0
   OR position('sourcePreflightIsNotAnIssuanceReservation' IN v_receipt)=0
 THEN
  RAISE EXCEPTION 'P3 original preflight no longer rechecks one source authority';
 END IF;
 IF pg_catalog.has_function_privilege('anon',
   'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'::regprocedure,
   'EXECUTE')
   OR pg_catalog.has_function_privilege('authenticated',
   'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'::regprocedure,
   'EXECUTE')
   OR pg_catalog.has_function_privilege('service_role',
   'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'::regprocedure,
   'EXECUTE')
 THEN
  RAISE EXCEPTION 'P3 private source receipt exposed to API role';
 END IF;
 IF pg_catalog.to_regprocedure(
  'atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)'
 ) IS NULL OR position(
   'uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
   pg_catalog.pg_get_functiondef(
     'atlas.ensure_rhythm_task_v1(uuid,text,timestamptz)'::regprocedure)
 )=0 OR position(
   'uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
   pg_catalog.pg_get_functiondef(
     'atlas.guard_continuing_original_rhythm_old_carrier_v1()'::regprocedure)
 )=0 THEN
  RAISE EXCEPTION 'Governed Rulebook legacy task and direct insert guards are not assembled';
 END IF;

 IF position('activation_prerequisite_completed' IN v_eval)=0 THEN
  RAISE EXCEPTION 'Done-activated rhythm still has an automatic source issuance gap';
 END IF;
 IF pg_catalog.to_regprocedure(
  'atlas.guard_uni_ops_governed_care_original_acceptance_v1()'
 ) IS NULL OR pg_catalog.to_regprocedure(
  'atlas.require_uni_ops_original_finalize_on_commit_v1()'
 ) IS NULL THEN
  RAISE EXCEPTION 'Canonical governed original INSERT or atomic COMMIT guard missing';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.work_items'::regclass
    AND t.tgname='c_uni_ops_governed_care_original_acceptance_v1'
    AND t.tgenabled<>'D'
 ) OR NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.work_items'::regclass
    AND t.tgname='z_uni_ops_governed_original_finalization_v1'
    AND t.tgdeferrable
    AND t.tginitdeferred
    AND t.tgenabled<>'D'
 ) THEN
   RAISE EXCEPTION 'Required source/atomic original guards are not attached and deferred';
 END IF;
 IF pg_catalog.has_function_privilege(
    'authenticated','atlas.guard_uni_ops_governed_care_original_acceptance_v1()'::regprocedure,'EXECUTE'
 ) OR pg_catalog.has_function_privilege(
    'service_role','atlas.require_uni_ops_original_finalize_on_commit_v1()'::regprocedure,'EXECUTE'
 ) THEN
   RAISE EXCEPTION 'Private governed original guard exposed to client/API roles';
 END IF;
 -- Source-only structural check for the seven known old Done/event/clock
 -- callbacks. Dynamic SQL/indirect scheduling require separate signed tests.
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND (
      (p.proname IN (
         'release_after_task_terminal_v1','advance_task_dependency_clocks_v1',
         'apply_workflow_event_v1')
       AND pg_catalog.pg_get_functiondef(p.oid) ~*
          'perform[[:space:]]+atlas[.]release_eligible_work_v1[[:space:]]*[(]'
      )
      OR (p.proname IN (
         'advance_anna_weeding_serial_queue_v1',
         'advance_owner_completion_gated_queue_v1',
         'advance_pot_up_serial_queue_v1')
       AND pg_catalog.pg_get_functiondef(p.oid) ~*
          'perform[[:space:]]+atlas[.]apply_[[:alnum:]_]+_release_effect_v1[[:space:]]*[(]'
      )
      OR (p.proname='advance_gentle_pressure_wash_serial_queue_v1'
       AND pg_catalog.pg_get_functiondef(p.oid) ~*
          'perform[[:space:]]+atlas[.]release_next_pressure_wash_task_v1[[:space:]]*[(]')
      OR (p.proname='apply_workflow_event_v1'
       AND pg_catalog.pg_get_functiondef(p.oid) ~*
          'perform[[:space:]]+atlas[.]record_task_transition_v1_internal[[:space:]]*[(]')
    )
 ) THEN
  RAISE EXCEPTION 'An explicit known legacy Done/event/dependency source still automatically releases Work';
 END IF;

 RAISE NOTICE 'P3 source contract structurally present; signed outcome/ACL/collision and no-DML verification remain HELD';
END;
$post$;

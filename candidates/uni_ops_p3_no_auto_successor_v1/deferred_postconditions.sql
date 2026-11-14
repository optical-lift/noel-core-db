-- HELD P3: run ONLY in an isolated current-schema PG17 clone AFTER
-- assembling U1A,U1B,U2A/U2B,U2C, approved R01/R02 source, and this P3.
-- Pure structural assertions: not substitute for real signed actor tests.
DO $post$
DECLARE
 v_eval text;
 v_receipt text;
 v_signal text;
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


 IF position('independent_new_work_authorization_required' IN
  pg_catalog.pg_get_functiondef(
    'atlas.release_next_task_in_queue_v1(uuid,text,date)'::regprocedure)
 )=0 THEN
  RAISE EXCEPTION 'Completion-gated direct old queue release bypass still present';
 END IF;
 IF position('owner_direction_pending_without_auto_work' IN
  pg_catalog.pg_get_functiondef(
   'atlas.ensure_weekly_harvest_owner_review_handoff_v1(uuid,uuid)'::regprocedure)
 )=0 THEN
  RAISE EXCEPTION 'Thursday Harvest Done-to-owner automatic successor not yet staged';
 END IF;
 -- File 11 enforces the exact original source MD5 BEFORE replacing it.
 -- After installation that original hash must differ. Checking it here
 -- would reject the successful source-guard overlay unconditionally.
 -- The assembled postcondition checks the held branch AND retention of
 -- the independently sourced release path; signed behavior remains open.
 SELECT pg_catalog.pg_get_functiondef(
   'atlas.signal_work_occurrence_v1(uuid,text,jsonb)'::regprocedure
 ) INTO v_signal;
 IF v_signal IS NULL
    OR position('governed_rhythm_clock_signal_held' IN v_signal)=0
    OR position('automatic_task_release_authorized' IN v_signal)=0
    OR position('noAutomaticNextTask' IN v_signal)=0
    OR position('release_eligible_work_v1' IN v_signal)=0
    OR position('gate_satisfied_at' IN v_signal)=0
    OR position('uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
       pg_catalog.pg_get_functiondef(
         'atlas.ensure_rhythm_task_v1_base(uuid,text,timestamptz)'::regprocedure)
    )=0
    OR position('uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
  pg_catalog.pg_get_functiondef(
   'atlas.ensure_rhythm_task_v1_base(uuid,text,timestamptz)'::regprocedure)
 )=0 OR position('uni_ops_legacy_rhythm_under_governed_rulebook_held_v1' IN
  pg_catalog.pg_get_functiondef(
   'atlas.ensure_rhythm_task_without_physical_gate_v1(uuid,text,timestamptz)'::regprocedure)
 )=0 THEN
   RAISE EXCEPTION 'Governed clock signal or direct old rhythm writer bypass remains';
 END IF;


 IF position('evaluate_goal_unlocks_v1' IN
   pg_catalog.pg_get_functiondef(
     'atlas.goal_source_changed_v1()'::regprocedure)
 )=0 OR position('::date,false)' IN
   pg_catalog.pg_get_functiondef(
     'atlas.goal_source_changed_v1()'::regprocedure)
 )=0 OR position('::date,false)' IN
   pg_catalog.pg_get_functiondef(
     'atlas.goal_clock_tick_v1()'::regprocedure)
 )=0 THEN
  RAISE EXCEPTION 'Goal trigger or Clock still releases a Task automatically';
 END IF;
 IF position('ensure_flower_preparation_task_v1' IN
   pg_catalog.pg_get_functiondef(
     'atlas.queue_flower_preparation_after_harvest_v1()'::regprocedure)
 )>0 AND
   pg_catalog.pg_get_functiondef(
     'atlas.queue_flower_preparation_after_harvest_v1()'::regprocedure)
       ~* 'perform[[:space:]]+atlas[.]ensure_flower_preparation_task_v1'
 THEN RAISE EXCEPTION 'Harvest output still automatically creates next prep Task'; END IF;
 IF pg_catalog.pg_get_functiondef(
   'atlas.record_seed_inventory_result_core_v1(uuid,uuid,text,text,numeric,numeric,text,text,date,text,text,boolean)'::regprocedure
 ) ~* 'atlas[.]sync_seed_inventory_dependency_tasks_v1[[:space:]]*[(]'
 THEN RAISE EXCEPTION 'Seed Result still automatically births dependency Task'; END IF;


 IF position('harvest-preparation-needs-owner-direction:' IN
   pg_catalog.pg_get_functiondef(
    'atlas.queue_flower_preparation_after_harvest_v1()'::regprocedure)
 )=0 THEN
   RAISE EXCEPTION 'P3 Harvest Result no-auto Work has no owner attention replacement';
 END IF;
 IF position('seed-shortfall-needs-owner-decision:' IN
   pg_catalog.pg_get_functiondef(
     'atlas.record_seed_inventory_result_core_v1(uuid,uuid,text,text,numeric,numeric,text,text,date,text,text,boolean)'::regprocedure)
 )=0 THEN
   RAISE EXCEPTION 'P3 seed shortfall missing source-qualified owner attention';
 END IF;
 IF pg_catalog.to_regprocedure(
  'atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(uuid,uuid,date,date)'
 ) IS NULL THEN
   RAISE EXCEPTION 'P3 true Ledger-governor-only attention reader missing';
 END IF;
 IF pg_catalog.has_function_privilege('authenticated',
  'atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(uuid,uuid,date,date)'::regprocedure,
  'EXECUTE') OR pg_catalog.has_function_privilege('service_role',
  'atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(uuid,uuid,date,date)'::regprocedure,
  'EXECUTE') THEN
   RAISE EXCEPTION 'Private P3 governed owner attention exposed to an API role';
 END IF;


 IF pg_catalog.to_regclass(
   'atlas.uni_ops_p3_owner_attention_decision_events_v1'
 ) IS NULL OR pg_catalog.to_regprocedure(
   'atlas.uni_ops_p3_owner_decide_source_attention_self_held_v1(uuid,uuid,text,text,uuid,uuid)'
 ) IS NULL THEN
   RAISE EXCEPTION 'Immutable current signed owner source decision not staged';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgrelid=
     'atlas.uni_ops_p3_owner_attention_decision_events_v1'::regclass
     AND t.tgname='uni_ops_p3_owner_attention_decision_immutable_v1'
     AND t.tgenabled<>'D'
 ) THEN
   RAISE EXCEPTION 'Source owner choice has no append-only protection';
 END IF;
 IF pg_catalog.has_function_privilege('authenticated',
   'atlas.uni_ops_p3_owner_decide_source_attention_self_held_v1(uuid,uuid,text,text,uuid,uuid)'::regprocedure,'EXECUTE')
 OR pg_catalog.has_function_privilege('service_role',
   'atlas.uni_ops_p3_owner_decide_source_attention_self_held_v1(uuid,uuid,text,text,uuid,uuid)'::regprocedure,'EXECUTE')
 THEN
   RAISE EXCEPTION 'Private source governor decision transport exposed';
 END IF;
 IF position('uni_ops_p3_owner_attention_decision_events_v1' IN
    pg_catalog.pg_get_functiondef(
     'atlas.uni_ops_p3_owner_pending_decisions_self_held_v1(uuid,uuid,date,date)'::regprocedure)
 )=0 THEN
   RAISE EXCEPTION 'Owner source attention does not track its actual governor decision';
 END IF;

 IF pg_catalog.to_regclass(
   'atlas.uni_ops_governed_case_decision_events_v1'
 ) IS NOT NULL THEN
   RAISE EXCEPTION 'Farm P3 independent governor decisions conflict with canonical Company decision history';
 END IF;

 RAISE NOTICE 'P3 source contract structurally present; signed outcome/ACL/collision and no-DML verification remain HELD';
END;
$post$;

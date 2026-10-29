-- HELD POSTCONDITIONS: all 16 original source validations, not signed acceptance.

-- Original held postcondition: universal_laundry_calibration_without_implicit_rhythm_v1/postconditions.sql
-- Run after candidate in an isolated Atlas schema clone, NOT as a live mutation.
DO $proof$
DECLARE v_sql text;
BEGIN
 SELECT pg_get_functiondef('atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure) INTO v_sql;
 IF v_sql IS NULL THEN RAISE EXCEPTION 'Laundry calibration function absent'; END IF;
 IF strpos(v_sql,'principal_upsert_household_rhythm_api_v1')<>0 THEN
   RAISE EXCEPTION 'Calibration must never write a Household Rhythm';
 END IF;
 IF strpos(v_sql,'insert into atlas.household_kernel_instances')=0 THEN
   RAISE EXCEPTION 'Arrangement calibration no longer writes its legitimate instance';
 END IF;
 IF strpos(v_sql,'''contractVersion'', ''household_laundry_calibration_v1''')=0 THEN
   RAISE EXCEPTION 'Existing signed client calibration receipt changed without contract review';
 END IF;
END
$proof$;


-- Original held postcondition: governed_legacy_farm_reader_disclosure_v1/postconditions.sql
-- Postconditions on a disposable production-shaped schema clone.
DO $check$
DECLARE v_name text; v_def text;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['zone_registry_source_v1','object_crop_bed_map_v1','farm_care_zone_v1','farm_care_object_v1','farm_care_summary_v1','farm_snapshot_for_member_v1']) LOOP
   SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
   JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname=v_name LIMIT 1;
   IF v_def IS NULL OR position('require_governed_farm_full_disclosure_self_v1' IN v_def)=0 THEN
     RAISE EXCEPTION 'Legacy disclosure reader not guarded: %',v_name;
   END IF;
   IF position('atlas.is_farm_member' IN v_def)>0
      OR position('atlas.current_farm_role' IN v_def)>0
      OR position('atlas.farm_memberships' IN v_def)>0 THEN
     RAISE EXCEPTION 'Legacy membership bypass persists: %',v_name;
   END IF;
 END LOOP;
 IF has_function_privilege('authenticated',
    'atlas.require_governed_farm_full_disclosure_self_v1(uuid)', 'EXECUTE') THEN
   RAISE EXCEPTION 'Internal authorization helper must not be callable directly';
 END IF;
END
$check$;
-- Signed owner/connected Person/outsider/anon direct-RPC denial is still
-- mandatory; static clone assertions alone do not establish effective access.


-- Original held postcondition: governed_legacy_farm_reader_disclosure_gate0_extension_v1/postconditions.sql
-- Read-only postconditions for production-shaped disposable clone.
DO $proof$
DECLARE n text; v_src text;
BEGIN
 FOR n IN SELECT unnest(ARRAY['farm_continuity_audit_v2','bed_components_state_v1','farm_continuity_audit_v1','farm_continuity_audit_v3','grow_room_state_v1','mowing_rhythm_dashboard_v1','weeding_cycle_v1','weeding_rhythm_pilot_v1','walkway_cards_v1','tending_board_v1','real_operation_explanation_v1','weed_card_task_focus_v1']) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='atlas' AND p.proname=n LIMIT 1;
  IF v_src IS NULL OR
     position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' in v_src)=0
  THEN RAISE EXCEPTION 'Unprotected legacy full farm reader %',n;END IF;
 END LOOP;
END $proof$;
-- Required independently signed negative tests:
-- old farm_hand, manager, former worker, unconnected Person, anon:
-- each reader denies before returning object existence/count/metadata.
-- current native Ledger governor may still inspect full farm information.
-- task-scoped worker access instead goes through exact approved original
-- Work, Subject and per-Person field disclosure with signed session.


-- Original held postcondition: governed_legacy_farm_reader_disclosure_gate0_context_v1/postconditions.sql
DO $proof$
DECLARE n text; src text;
BEGIN
 FOR n IN SELECT unnest(ARRAY['manual_task_context_v1','maintenance_directive_context_v1','resolve_effective_rhythm_rule_v1','task_schedule_v1','tending_bed_v1','weed_selected_crop_turnover_focus_v1','worker_hand_context_v1','worker_day_operational_task_cards_v1']) LOOP
   SELECT pg_get_functiondef(p.oid) INTO src FROM pg_proc p
   JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='atlas' AND p.proname=n LIMIT 1;
   IF src IS NULL OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' in src)=0
   THEN RAISE EXCEPTION 'Legacy broad context read not source-guarded: %',n;END IF;
 END LOOP;
END $proof$;
-- Signed owner, former farm_hand, manager, unconnected Person and anon
-- must be tested for absence of roster/card/crop existence side channels.
-- Old worker-specific paths intentionally do not substitute for a modern
-- canonical Work+Subject+field decision.


-- Original held postcondition: governed_legacy_farm_reader_disclosure_gate0_deep_v1/postconditions.sql
DO $deep_gate0$
DECLARE
 v_name text;
 v_body text;
 v_found integer;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['object_workbench_v1','farm_continuity_audit_v6','farm_continuity_audit_v7','farm_continuity_audit_v8','crop_cycle_profile_source_state_v1','crop_cycle_stage_continuity_state_v1','crop_cycle_biological_progression_state_v1','crop_cycle_postproduction_state_v1','crop_cycle_lawful_dwell_state_v1','farm_goal_list_v1','flower_sale_buyer_options_v1','home_task_cards_v1','task_plant_contents_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_body
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname=v_name
   LIMIT 1;
  IF v_body IS NULL
    OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(' IN v_body)=0
    OR position('SECURITY DEFINER' IN v_body)=0 THEN
    RAISE EXCEPTION 'Gate0 additional inherited reader % is not source-guarded',v_name;
  END IF;
 END LOOP;
 SELECT count(*) INTO v_found FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname=ANY(ARRAY['object_workbench_v1','farm_continuity_audit_v6','farm_continuity_audit_v7','farm_continuity_audit_v8','crop_cycle_profile_source_state_v1','crop_cycle_stage_continuity_state_v1','crop_cycle_biological_progression_state_v1','crop_cycle_postproduction_state_v1','crop_cycle_lawful_dwell_state_v1','farm_goal_list_v1','flower_sale_buyer_options_v1','home_task_cards_v1','task_plant_contents_v1']::text[]);
 IF v_found<>13 THEN
   RAISE EXCEPTION 'Gate0 deep source reader coverage incomplete (% of 13)',v_found;
 END IF;
END;
$deep_gate0$;


-- Original held postcondition: governed_legacy_farm_reader_disclosure_gate0_residual_v1/postconditions.sql
-- Assert all eight additional original SECURITY DEFINER readers enforce native governor access before legacy membership.
DO $residual_gate0$
DECLARE v_name text; v_body text;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['farm_day_task_cards_v1','home_task_cards_v2','seed_inventory_dashboard_v1','task_cards_v1','tending_task_context_v1','tending_task_context_v2','worker_day_state_transition_cards_v1','worker_future_day_projection_source_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_body FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname=v_name AND p.prosecdef LIMIT 1;
  IF v_body IS NULL OR position('PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);' IN v_body)=0 THEN
   RAISE EXCEPTION 'Legacy full-farm reader % missing original native-governor source guard',v_name;
  END IF;
 END LOOP;
END;
$residual_gate0$;


-- Original held postcondition: universal_subject_bounded_disclosure_v1/postconditions.sql
-- Validate source structure on disposable production-shaped schema clone.
DO $test$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
    WHERE conname='subject_disclosure_action_identity_v1'
      AND conrelid='atlas.subject_disclosure_decision_events_v1'::regclass) THEN
  RAISE EXCEPTION 'Missing strict decision idempotency constraint'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas'
      AND indexname='subject_disclosure_current_lookup_v1') THEN
  RAISE EXCEPTION 'Missing bounded exact-subject lookup index'; END IF;
 -- Report only these two permission booleans: no private data or row values.
 RAISE NOTICE 'Clone ACL: authenticated raw disclosure SELECT=%, anonymous public original Subject RPC EXECUTE=%',
   has_table_privilege('authenticated','atlas.subject_disclosure_decision_events_v1','SELECT'),
   has_function_privilege('anon',
    'public.connected_person_original_work_subject_self_api_v1(uuid,uuid,uuid,text,text,uuid)',
    'EXECUTE');
 IF has_table_privilege('authenticated','atlas.subject_disclosure_decision_events_v1','SELECT') THEN
   RAISE EXCEPTION 'Clone raw disclosure decision table SELECT is exposed to authenticated'; END IF;
 IF has_function_privilege('anon',
   'public.connected_person_original_work_subject_self_api_v1(uuid,uuid,uuid,text,text,uuid)',
   'EXECUTE') THEN
   RAISE EXCEPTION 'Clone public original Subject reader EXECUTE is exposed to anonymous'; END IF;
END $test$;
-- Mandatory signed tests: governor decides identity only, worker sees label
-- but not condition, condition separately granted/withheld, outsider and anon
-- denied, old grant revoked by later withhold, old farm paths still denied.


-- Original held postcondition: governor_effective_subject_disclosure_review_v1/postconditions.sql
-- Run in disposable schema clone against the exact source candidate.
DO $proof$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
  WHERE n.nspname='atlas' AND p.proname='owner_effective_subject_disclosure_review_self_api_v1'
    AND p.prosecdef) THEN
  RAISE EXCEPTION 'Governor-only disclosure source missing';
 END IF;
 IF has_function_privilege('anon',
   'public.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous disclosure review exposure'; END IF;
 IF has_function_privilege('authenticated',
   'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Internal disclosure review not private'; END IF;
END $proof$;
-- Real independently signed owner/worker/outsider and revocation still needed.

-- Current original Subject field-state projection remains bounded and source-derived.
DO $subject_review_fields$
DECLARE v_def text;
BEGIN
 SELECT pg_get_functiondef('atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure) INTO v_def;
 IF position('linkedSubjectDisclosure' in v_def)=0
 OR position('subject_disclosure_decision_events_v1' in v_def)=0
 OR position('has_current_subject_disclosure_v1' in v_def)=0
 OR position('LIMIT 21' in v_def)=0
 OR position('independentlySignedTargetProof' in v_def)=0
 THEN RAISE EXCEPTION 'Governor field-review source evidence incomplete'; END IF;
END $subject_review_fields$;


-- Original held postcondition: original_subject_choices_for_work_decomposition_v1/postconditions.sql
DO $proof$ BEGIN
 IF has_function_privilege('anon',
  'public.owner_original_subject_choices_for_work_self_api_v1(uuid,uuid,uuid,integer,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous subject-choice enumeration'; END IF;
 IF has_function_privilege('authenticated',
  'atlas.owner_original_subject_choices_for_work_self_api_v1(uuid,uuid,uuid,integer,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Direct internal subject-choice enumeration'; END IF;
END $proof$;
-- Signed non-governor must be forbidden; no cross-Ledger choices.


-- Original held postcondition: universal_original_work_decomposition_v1/postconditions.sql
-- Postconditions after source candidate on disposable full-schema clone.
DO $proof$ BEGIN
 IF NOT EXISTS(select 1 from pg_constraint where conname='work_decomposition_once_per_parent'
   and conrelid='atlas.work_decomposition_groups'::regclass) THEN
   RAISE EXCEPTION 'Original parent idempotence constraint missing'; END IF;
 IF NOT EXISTS(select 1 from pg_constraint where conname='work_decomposition_member_distinct_subject'
   and conrelid='atlas.work_decomposition_members'::regclass) THEN
   RAISE EXCEPTION 'Distinct original subjects not source-enforced'; END IF;
 IF has_function_privilege('anon',
   'public.split_original_canonical_work_owner_self_api_v1(uuid,uuid,uuid,jsonb,uuid,text)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous Work decomposition exposure'; END IF;
 IF has_table_privilege('authenticated','atlas.work_decomposition_members','SELECT')
    OR has_table_privilege('authenticated','atlas.work_decomposition_groups','SELECT') THEN
   RAISE EXCEPTION 'Private provenance table exposed'; END IF;
END $proof$;
-- Signed owner/worker/outsider direct RPC denial, idempotent retry, result
-- acceptance and preserved plan/allocation/history readbacks are outstanding.


-- Original held postcondition: universal_household_canonical_work_custody_v1/postconditions.sql
-- Disposable-clone postconditions; never run this as a production write.
DO $test$
DECLARE t text;
BEGIN
 FOR t IN SELECT unnest(ARRAY['work_items','work_allocations','work_execution_plans',
 'work_execution_plan_events','work_execution_results','work_result_acceptances',
 'work_item_context_links','work_time_contracts']) LOOP
  IF NOT EXISTS(
   SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name=t AND column_name='household_id'
    AND is_nullable='YES'
  ) THEN RAISE EXCEPTION 'Missing nullable household custody: %',t; END IF;
  IF NOT EXISTS(
   SELECT 1 FROM pg_constraint
   WHERE conrelid=('atlas.'||t)::regclass AND conname=t||'_one_native_custody_v1'
  ) THEN RAISE EXCEPTION 'Missing exclusive custodian check: %',t; END IF;
 END LOOP;
 IF has_table_privilege('authenticated','atlas.work_items','INSERT') OR
    has_table_privilege('authenticated','atlas.work_execution_results','INSERT')
 THEN RAISE EXCEPTION 'Direct authenticated canonical Work mutation exposure'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.rhythm_satisfactions'::regclass
   AND conname='rhythm_satisfactions_one_native_custody_v1'
 ) THEN RAISE EXCEPTION 'Single satisfaction registry custody not enforced'; END IF;
END $test$;
-- Required clone: existing Org/Event inserts, old allocation provenance,
-- Household Work source-only inserts, cross-Household FKs, and absence of
-- worker-credential inference all tested with BEGIN ... ROLLBACK fixtures.


-- Original held postcondition: universal_household_canonical_work_guards_v1/postconditions.sql
DO $test$ BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE tgname='b_guard_original_household_work_v1'
     AND tgrelid='atlas.work_items'::regclass
 ) THEN RAISE EXCEPTION 'Household Work completion source guard missing'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE tgname='z_guard_household_work_actual_v1'
     AND tgrelid='atlas.work_execution_results'::regclass
 ) THEN RAISE EXCEPTION 'Household Actual acceptance guard missing'; END IF;
 IF has_function_privilege('authenticated',
   'atlas.require_household_governor_self_v1(uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'Private Household governor helper direct invocation'; END IF;
END $test$;
-- Signed Household governor, signed member, unlinked Person and anon must be
-- tested using real sessions, as must repeat results, linked Work and cross-scope.


-- Original held postcondition: universal_household_rhythm_explicit_decision_v1/postconditions.sql
DO $proof$ BEGIN
 IF has_table_privilege('authenticated',
     'atlas.household_rhythm_explicit_decisions_v1','SELECT') THEN
  RAISE EXCEPTION 'Private current Rhythm authority leaked'; END IF;
 IF has_function_privilege('anon',
   'public.household_laundry_explicit_rhythm_decide_self_api_v1(uuid,uuid,text,integer,text)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous Household Rhythm decision writer'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE
   tgrelid='atlas.household_rhythm_explicit_decisions_v1'::regclass
   AND tgname='household_rhythm_decision_append_only_v1'
 ) THEN RAISE EXCEPTION 'Missing append-only Rhythm decision history'; END IF;
END $proof$;
-- Required real signed acceptance:
-- calibration -> no decision and no capacity block;
-- explicit establish -> existing Household rhythm ID, one append-only decision;
-- retry -> identical ID, no extra event;
-- metadata-only forged source flag -> no satisfaction;
-- Actual wash-started -> precisely one conditional satisfaction;
-- repeated Actual -> no duplicate;
-- explicit withdraw -> later Actual yields zero new satisfactions;
-- unrelated household/Person/anon -> denied;
-- native Farm/Program/Event rhythms unaffected.


-- Original held postcondition: household_laundry_original_work_actual_v1/postconditions.sql
DO $proof$
DECLARE n text;
 v_sql text;
 v_actor_pos integer;
 v_carrier_pos integer;
 v_result_pos integer;
 v_replay_pos integer;
BEGIN
 FOR n IN SELECT unnest(ARRAY[
  'record_household_laundry_observation_self_api_v1',
  'establish_household_laundry_original_work_self_api_v1',
  'record_household_laundry_wash_started_self_api_v1'
 ]) LOOP
  IF NOT EXISTS(
   SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='atlas' AND p.proname=n AND p.prosecdef
  ) THEN RAISE EXCEPTION 'Original Laundry source writer absent: %',n;END IF;
 END LOOP;
 SELECT pg_get_functiondef(p.oid) INTO v_sql FROM pg_proc p
 JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='atlas'
   AND p.proname='record_household_laundry_wash_started_self_api_v1'
 LIMIT 1;
 v_actor_pos:=position('v_person:=atlas.household_work_actor_v1' IN v_sql);
 v_carrier_pos:=position('Physical Work Actual requires authorized original carrier' IN v_sql);
 v_result_pos:=position('SELECT id INTO v_result FROM atlas.care_result_events' IN v_sql);
 v_replay_pos:=position('IF v_result IS NOT NULL THEN' IN v_sql);
 IF v_sql IS NULL OR v_actor_pos=0 OR v_carrier_pos=0 OR
    v_result_pos=0 OR v_replay_pos=0 OR
    NOT (v_actor_pos<v_carrier_pos AND v_carrier_pos<v_result_pos
      AND v_result_pos<v_replay_pos)
 THEN
   RAISE EXCEPTION 'Physical-Actual replay must authorize the real owner/carrier before receipt lookup.';
 END IF;
 IF NOT (v_sql LIKE '%household_rhythm_explicit_decisions_v1%' AND
         v_sql LIKE '%explicitDecisionId%') THEN
   RAISE EXCEPTION 'Physical-Actual Rhythm satisfaction has no immutable signed decision.';
 END IF;
 IF has_function_privilege('anon',
  'public.record_household_laundry_wash_started_self_api_v1(uuid,uuid,text)',
  'EXECUTE') THEN RAISE EXCEPTION 'Anonymous physical-Actual writer exposed'; END IF;
END $proof$;
-- Disposable clone signed cases:
-- calibration alone creates 0 Need/Work/Rhythm; actual observation -> 0 Work;
-- explicit establish -> one household-origin work_items UUID + context link;
-- optional self/member without account; unassigned stays unassigned;
-- repeated establish -> same original UUID, no duplicate;
-- wash_started -> one care_result, one accepted work_result, one completed
-- original Work, only begin_cycle Need satisfied, Laundry state washing;
-- no explicit Rhythm -> zero satisfactions/windows changed;
-- explicit qualifying Rhythm -> one conditional satisfaction, next window;
-- cross-Household, anonymous, unrelated Person and forged result denied;
-- source action replays never duplicate or complete unrelated Work.


-- Original held postcondition: household_laundry_original_work_read_v1/postconditions.sql
DO $test$ BEGIN
 IF has_function_privilege('anon',
   'public.household_original_work_focus_self_api_v1(uuid,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Household Work Focus anonymously accessible'; END IF;
 IF has_function_privilege('anon',
   'public.household_laundry_current_self_api_v1()',
   'EXECUTE') THEN RAISE EXCEPTION 'Private Household notebook anonymous'; END IF;
END $test$;
-- Real owner/member/unlinked/anon identity proofs still required, and Work
-- action completion must never read unrelated Household conditions or links.


-- Original held postcondition: original_subject_work_existing_direct_responsibility_v1/postconditions.sql
-- Schema-clone assertions after the reviewed source candidates are applied.
DO $proof$
BEGIN
 IF has_function_privilege('anon',
  'public.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)',
  'EXECUTE') THEN
   RAISE EXCEPTION 'Anonymous original Work assignment exposed';
 END IF;
 IF has_function_privilege('authenticated',
  'atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)',
  'EXECUTE') THEN
   RAISE EXCEPTION 'Internal direct assignment helper exposed';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_constraint c
  WHERE c.conrelid='atlas.work_allocations'::regclass
    AND c.conname='work_allocations_exact_assignee_carrier_v1'
    AND pg_get_constraintdef(c.oid) LIKE '%original_subject_direct_assignment_v1%'
 ) THEN RAISE EXCEPTION 'Original Work direct Person carrier rejected by table source';END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='owner_original_split_work_part_self_api_v1'
    AND p.prosecdef
 ) THEN RAISE EXCEPTION 'Missing governor source proof of original Work part';END IF;
END $proof$;

-- Sign-in integration cases REQUIRED before any release:
-- Governor reads exact original split Bed 3 and Bed 4 IDs;
-- independent result policy review (worker attestation vs manager acceptance);
-- issue one direct allocation + plan for Anna without new Work/task/offer;
-- retry with same action returns same allocation & plan;
-- changed Person/date/action or another active responsible Person is denied;
-- Anna signed in sees exact original Bed 3 through my_work/day/Today,
-- confirms her own physical work with source-specific accepted result;
-- recipient cannot discover other Beds, owner private information or all crops;
-- unconnected Person, unrelated Ledger governor, anon all denied;
-- Event original Work and other preexisting Person assignment flows unchanged.

-- Responsibility may be assigned with NO work-on date. Legacy dated calls
-- remain permitted, but no plan or Today admission may be fabricated for NULL.
DO $original_work_unscheduled_assignment$
DECLARE v_src text;
BEGIN
 SELECT pg_get_functiondef(
   'atlas.owner_direct_assign_existing_original_work_self_api_v1(uuid,uuid,uuid,uuid,date,uuid,text)'::regprocedure)
 INTO v_src;
 IF v_src IS NULL OR
    position('IF p_service_date IS NOT NULL THEN' IN v_src)=0 OR
    position('requestedServiceDate' IN v_src)=0 OR
    position('scheduleState' IN v_src)=0 OR
    position('v_created:=true' IN v_src)=0 OR
    position('p_service_date IS NULL OR p_action_id IS NULL' IN v_src)>0
 THEN RAISE EXCEPTION 'Direct original Work still couples responsibility to a required date'; END IF;
END $original_work_unscheduled_assignment$;

-- Neither native assignment nor old Work text is an identity disclosure
-- authorization; all signed Person Work surfaces must enforce current
-- original Subject identity decisions, including post-assignment revocation.
DO $original_subject_work_visibility$
DECLARE v_reader text;v_sql text;
BEGIN
 IF has_function_privilege('authenticated',
    'atlas.person_original_work_identity_disclosed_self_v1(uuid,uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Original Work identity helper exposed to authenticated'; END IF;
 FOR v_reader IN SELECT unnest(ARRAY[
  'connected_person_my_work_self_api_v1',
  'connected_person_place_work_self_api_v1',
  'report_connected_person_company_work_internal_v1',
  'connected_person_company_work_day_self_api_v1',
  'connected_person_company_work_today_self_api_v1',
  'connected_person_work_prerequisites_self_api_v1'
 ]::text[]) LOOP
   SELECT pg_get_functiondef(p.oid) INTO v_sql
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname=v_reader LIMIT 1;
   IF v_sql IS NULL OR position('person_original_work_identity_disclosed_self_v1(' in v_sql)=0
   THEN RAISE EXCEPTION 'Original Subject Work identity source admission missing from %',v_reader; END IF;
 END LOOP;
END $original_subject_work_visibility$;

-- Historical title/offer/calendar/agenda readers cannot bypass a withheld
-- original growing-object Subject, regardless of legacy membership/role.
DO $alternate_original_work_proof$
DECLARE v_name text; v_definition text;
BEGIN
 FOR v_name IN SELECT unnest(ARRAY['company_work_initial_offers_self_api_v1','company_work_participation_offers_self_api_v1','company_work_responsibility_transfer_offers_self_api_v1','company_work_self_responsibilities_api_v1','connected_ledger_person_agenda_self_api_v1','connected_person_company_work_offers_self_api_v1','my_ledger_event_work_attention_self_api_v1','self_responsible_company_work_today_self_api_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_definition
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='atlas' AND p.proname=v_name AND p.prosecdef LIMIT 1;
  IF v_definition IS NULL
    OR position('work_item_context_links' in v_definition)=0
    OR position('g0.subject_domain' in v_definition)=0
    OR position('g0.subject_kind' in v_definition)=0
    OR position('NOT EXISTS' in v_definition)=0 THEN
    RAISE EXCEPTION 'Historical alternate Work title reader % lacks bounded exclusion',v_name;
  END IF;
 END LOOP;
END $alternate_original_work_proof$;

-- Source proof: old communication picker must not enumerate organization
-- people, places, zones or original Work on legacy membership authority alone.
DO $communication_context_gate$
DECLARE v_sql text;
BEGIN
 SELECT pg_get_functiondef('atlas.communication_work_context_candidates_self_v1(uuid,text)'::regprocedure)
 INTO v_sql;
 IF position('company_work_native_ledger_owner_self_v1(' in v_sql)=0
    OR position('is_compatibility_primary' in v_sql)=0 THEN
  RAISE EXCEPTION 'Communication context original sources missing native governor gate';
 END IF;
END $communication_context_gate$;

-- The old organization-wide management queue can contain historical Work text
-- with NO original Subject link. Link-based filtering alone is not sufficient.
DO $unlinked_historical_management_gate$
DECLARE v_sql text;
BEGIN
 SELECT lower(pg_get_functiondef(
   'atlas.organization_management_company_work_planning_queue_api_v1(uuid,date,date)'::regprocedure
 )) INTO v_sql;
 IF v_sql IS NULL OR
    position('company_work_native_ledger_owner_self_v1(' IN v_sql)=0 OR
    position('is_compatibility_primary' IN v_sql)=0 OR
    position('company_work_native_ledger_owner_self_v1(' IN v_sql)>=position('return query' IN v_sql) THEN
   RAISE EXCEPTION 'Historical organization planning is not gated before unlinked Work reads';
 END IF;
END $unlinked_historical_management_gate$;

-- Five more historic planning, organization-result and correspondence paths
-- cannot disclose spatial growing-object original Work through older seats.
DO $older_work_proof$
DECLARE v_fn text; v_sql text;
BEGIN
 FOR v_fn IN SELECT unnest(ARRAY['organization_correspondence_search_self_api_v1','organization_management_company_work_planning_queue_api_v1','organization_owner_company_work_planning_queue_api_v1','organization_owner_company_work_planning_queue_api_v2','organization_work_accountability_self_api_v1']::text[]) LOOP
  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname=v_fn AND p.prosecdef LIMIT 1;
  IF v_sql IS NULL
     OR position('original_link.subject_domain' IN v_sql)=0
     OR position('original_link.subject_kind' IN v_sql)=0
     OR position('original_link.work_item_id' IN v_sql)=0
     OR position('NOT EXISTS' IN v_sql)=0
  THEN RAISE EXCEPTION 'Historical Work disclosure exclusion missing from %',v_fn; END IF;
 END LOOP;
END $older_work_proof$;

-- Held additional HTTP membrane postconditions. Existing source and exact
-- privacy checks above remain mandatory, not replaced or relaxed.
DO $signed_care_http$
DECLARE
 v_public regprocedure := to_regprocedure(
 'public.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)');
 v_private regprocedure := to_regprocedure(
 'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)');
 v_sql text;
BEGIN
 IF v_public IS NULL OR v_private IS NULL THEN
   RAISE EXCEPTION 'Signed public care RPC and private domain writer must coexist';
 END IF;
 IF has_function_privilege('anon',v_public,'EXECUTE') OR
    has_function_privilege('service_role',v_public,'EXECUTE') OR
    NOT has_function_privilege('authenticated',v_public,'EXECUTE') OR
    has_function_privilege('anon',v_private,'EXECUTE') OR
    has_function_privilege('authenticated',v_private,'EXECUTE') OR
    has_function_privilege('service_role',v_private,'EXECUTE') THEN
   RAISE EXCEPTION 'Care HTTP boundary violates signed-only public/private separation';
 END IF;
 IF NOT EXISTS(
    SELECT 1 FROM pg_proc p WHERE p.oid=v_public
    AND p.prosecdef AND 'search_path=""'=ANY(p.proconfig)
 ) THEN
    RAISE EXCEPTION 'Public signed care RPC lacks pinned empty search path';
 END IF;
 v_sql:=pg_get_functiondef(v_public);
 IF position('atlas.current_person_id_v1' in v_sql)=0 OR
    position('atlas.record_continuing_care_actual_self_api_v1' in v_sql)=0
 THEN
   RAISE EXCEPTION 'Care HTTP RPC does not enforce native Person and delegate to private source';
 END IF;
END;
$signed_care_http$;

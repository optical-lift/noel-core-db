-- Disposable protected production-schema clone postconditions ONLY.
-- Source ACL, no missing handler, negative synthetic checks. NOT a signed-positive fixture.

-- POSTCONDITION SECTION: postconditions.sql
-- CANDIDATE postconditions: run ONLY after applying the candidate in a disposable
-- schema clone. NOT a production mutation or a signed human/worker acceptance.
DO $check$
DECLARE
  v_fn oid;
  v_acl text;
BEGIN
  SELECT p.oid INTO v_fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND p.proname='establish_continuing_original_work_internal_v1'
    AND pg_get_function_identity_arguments(p.oid)=
    'p_custody_kind text, p_custody_id uuid, p_ledger_id uuid, p_need_kind text, p_need_id uuid, p_serving_key text, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_title text, p_instructions text, p_result_contract_key text';
  IF v_fn IS NULL THEN
    RAISE EXCEPTION 'Missing exact universal continuing Work internal source contract';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR has_function_privilege('authenticated',v_fn,'EXECUTE')
     OR has_function_privilege('service_role',v_fn,'EXECUTE') THEN
    RAISE EXCEPTION 'Internal Work writer is exposed to an application credential';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p WHERE p.oid=v_fn AND p.prosecdef
      AND ('search_path=""'=ANY(p.proconfig) OR 'search_path='=ANY(p.proconfig))
  ) THEN
    RAISE EXCEPTION 'Internal Work writer is missing constrained function context';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_items'::regclass
      AND c.conname='work_items_one_native_custody_v1'
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid='atlas.work_item_context_links'::regclass
      AND c.conname='work_item_context_links_one_native_custody_v1'
  ) THEN
    RAISE EXCEPTION 'Native Household/Organization custody invariants missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='atlas' AND t.relname='household_need_occurrences_v1'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace
    WHERE n.nspname='atlas' AND t.relname='rhythm_state'
  ) THEN
    RAISE EXCEPTION 'One of two real Need source owners is unavailable';
  END IF;
  IF to_regprocedure(
      'atlas.continuing_original_work_result_continuation_internal_v1(uuid)'
     ) IS NULL THEN
    RAISE EXCEPTION 'Missing original Work Result-to-Need continuation review';
  END IF;
  IF has_function_privilege('anon',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE')
     OR has_function_privilege('authenticated',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE')
     OR has_function_privilege('service_role',
       'atlas.continuing_original_work_result_continuation_internal_v1(uuid)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'Cross-scope continuing-Result review is exposed to client credentials';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='atlas.continuing_original_work_result_continuation_internal_v1(uuid)'::regprocedure
      AND p.prosecdef AND p.provolatile='s'
      AND ('search_path=""'=ANY(p.proconfig) OR 'search_path='=ANY(p.proconfig))
  ) THEN
    RAISE EXCEPTION 'Result-to-Need review is not read-only or source-constrained';
  END IF;
  IF to_regprocedure('atlas.reality_continuation_normalize_v1(jsonb)') IS NULL
     OR to_regprocedure('atlas.household_laundry_current_self_api_v1()') IS NULL THEN
    RAISE EXCEPTION 'Existing universal continuation or Laundry source is missing';
  END IF;
  RAISE NOTICE 'Private one-serving and Result-to-Need review contracts protected; signed actual-to-next Work not yet proven';
END;
$check$;


-- Signed-shaped negative in a DISPOSABLE clone only. This is a negative test,
-- not an impersonation of any real person and never authorizes a positive
-- Owner/Worker result. The candidate function cannot disclose or create
-- original Work from a fabricated source Result ID.
DO $negative$
DECLARE
  v_unknown_result uuid := '00000000-0000-4000-8000-000000000091';
  v_rejected boolean := false;
  v_session_sub text;
BEGIN
  v_session_sub:=current_setting('request.jwt.claim.sub', true);
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000092',true);
  BEGIN
    PERFORM atlas.continuing_original_work_result_continuation_internal_v1(
      v_unknown_result);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_rejected:=true;
  END;
  PERFORM set_config('request.jwt.claim.sub',coalesce(v_session_sub,''),true);
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'Unknown original Work Result did not fail closed';
  END IF;
  RAISE NOTICE 'Synthetic unknown signed Result denied; no positive signed proof claimed';
END;
$negative$;


-- POSTCONDITION SECTION: 03_actual_adapter_postconditions.sql
-- Disposable protected schema-clone postconditions after candidate.sql
-- 02_farm_care_actual_adapter.sql, and 04_care_actual_source_guards.sql. No production test mutations.
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
      AND ('search_path=""'=ANY(p.proconfig) OR 'search_path='=ANY(p.proconfig))
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

  IF NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.work_execution_results'::regclass
      AND t.tgname='z_guard_continuing_care_actual_result_v1'
      AND t.tgenabled IN ('O','A')
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.work_result_acceptances'::regclass
      AND t.tgname='z_guard_continuing_care_actual_acceptance_v1'
      AND t.tgenabled IN ('O','A')
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.work_items'::regclass
      AND t.tgname='z_guard_continuing_care_work_completion_v1'
      AND t.tgenabled IN ('O','A')
  ) THEN
    RAISE EXCEPTION 'Physical Actual, acceptance, or satisfaction completion guard missing';
  END IF;
  IF has_function_privilege('authenticated',
      'atlas.guard_continuing_care_actual_result_v1()','EXECUTE')
     OR has_function_privilege('authenticated',
      'atlas.guard_continuing_care_actual_acceptance_v1()','EXECUTE')
     OR has_function_privilege('authenticated',
      'atlas.guard_continuing_care_work_completion_v1()','EXECUTE')
  THEN
    RAISE EXCEPTION 'Source Actual trigger guard has callable client privilege';
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


-- POSTCONDITION SECTION: 06_origin_postconditions.sql
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
      AND ('search_path=""'=ANY(p.proconfig) OR 'search_path='=ANY(p.proconfig))
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
  -- This synthetic unsigned request can fail either the exact-input guard
  -- (22023) or the governor authority guard (42501), both fail closed.
  EXCEPTION WHEN SQLSTATE '42501' OR SQLSTATE '22023' THEN
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

-- POSTCONDITION SECTION: 08_cutover_postconditions.sql
-- Protected-clone gate: source-gated no-duplicate legacy rhythm task cutover.
-- Execute AFTER release_candidate.sql. No actual historical tasks modified.
DO $post$
BEGIN
  IF to_regprocedure('atlas.continuing_rhythm_original_work_has_custody_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.ensure_rhythm_task_v1(uuid,text,timestamp with time zone)') IS NULL
    OR to_regprocedure('atlas.guard_continuing_original_rhythm_old_carrier_v1()') IS NULL
  THEN
    RAISE EXCEPTION 'Legacy-clock-to-canonical-original membrane is missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.tasks'::regclass
      AND t.tgname='z_guard_continuing_original_rhythm_old_task_v1'
      AND t.tgenabled IN ('O','A')
  ) OR NOT EXISTS(
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid='atlas.planned_work_occurrences'::regclass
      AND t.tgname='z_guard_continuing_original_rhythm_old_occurrence_v1'
      AND t.tgenabled IN ('O','A')
  ) THEN
    RAISE EXCEPTION 'Direct old task/occurrence path still unprotected';
  END IF;
  IF has_function_privilege('anon',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
    OR has_function_privilege('authenticated',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
    OR has_function_privilege('service_role',
       'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Internal cutover classifier must not become a discoverable reader';
  END IF;
  IF to_regprocedure('atlas.farm_rhythm_tick_v1(uuid,timestamp with time zone,integer)') IS NULL
  THEN
    RAISE EXCEPTION 'Original unadopted farm rhythm clock changed unexpectedly';
  END IF;
  RAISE NOTICE 'Source guard presence confirmed; actual same-Need synthetic positive+negative test still required';
END;
$post$;

-- Protected-clone fixture must establish synthetic owned/assigned original
-- Work for one exact rhythm in a rollback transaction. Then test:
-- 1. existing older task rows and Work history remain unmodified.
-- 2. ensure_rhythm_task_v1 => canonical_original_work_has_custody.
-- 3. insert a new old task with generated_from NULL, metadata.rhythm_state_id
--    set to the adopted source state, and planned_occurrence_id; must reject.
-- 4. insert a new planned_work_occurrences source_kind=rhythm_state
--    source_id=adopted state; must reject.
-- 5. for a non-adopted state, previous legacy task release is unaffected.
-- 6. scheduled tick does not loop on exceptions or issue alternate tasks.
-- Failure on any is a BLOCK on cutover deployment, not a green check.

-- POSTCONDITION SECTION: 09_rhythm_state_raw_worker_disclosure_cutover.sql
-- Protected clone AFTER applying bundle; NOT sufficient for signed positive.
DO $privacy$
DECLARE v_definition text;
BEGIN
 IF to_regprocedure('atlas.can_read_rhythm_state_v1(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Rhythm state direct-read membrane missing';
 END IF;
 SELECT pg_catalog.pg_get_functiondef(
   'atlas.can_read_rhythm_state_v1(uuid)'::regprocedure)
 INTO v_definition;
 IF v_definition NOT LIKE '%WHEN ''assigned_worker'' THEN atlas.is_farm_manager_or_owner(s.farm_id)%'
    OR v_definition NOT LIKE '%ELSE atlas.is_farm_manager_or_owner(s.farm_id)%'
    OR v_definition LIKE '%s.assigned_user_id = auth.uid()%'
 THEN RAISE EXCEPTION 'Legacy worker direct raw Rhythm read path still admitted';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM pg_policy pol
   WHERE pol.polrelid='atlas.rhythm_state'::regclass
     AND pol.polcmd='r'
     AND pg_catalog.pg_get_expr(pol.polqual,pol.polrelid)
       LIKE '%can_read_rhythm_state_v1%'
 ) THEN RAISE EXCEPTION 'Real Rhythm state RLS policy not wired to source gate';
 END IF;
 RAISE NOTICE 'Raw Rhythm worker read guard source present; actual signed RLS probes still REQUIRED';
END;
$privacy$;

-- In disposable full production-schema clone after:
--  candidate.sql, 02, 04, 05, then 10 and 11.
-- Structural source gates only. Genuine signed Auth/REST fixtures required
-- before any authenticated EXECUTE grant or production release.
DO $standing$
DECLARE
  v_writer oid;
  v_preview oid;
  v_writer_def text;
  v_preview_def text;
BEGIN
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_writer,v_writer_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND p.proname='owner_establish_standing_continuing_care_work_self_api_v1'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_organization_id uuid, p_ledger_id uuid, p_rhythm_state_id uuid, p_scope_id uuid, p_visit_reason text, p_service_date date, p_campaign_end_date date, p_action_id uuid';
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_preview,v_preview_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND p.proname='owner_preview_standing_care_candidates_self_api_v1';
  IF v_writer IS NULL OR v_preview IS NULL THEN
    RAISE EXCEPTION 'Standing care writer or candidate source missing';
  END IF;
  IF has_function_privilege('anon',v_writer,'EXECUTE')
    OR has_function_privilege('authenticated',v_writer,'EXECUTE')
    OR has_function_privilege('anon',v_preview,'EXECUTE')
    OR has_function_privilege('authenticated',v_preview,'EXECUTE')
  THEN RAISE EXCEPTION 'Unreviewed standing care exposed to app roles';
  END IF;
  IF v_writer_def NOT LIKE '%company_work_native_ledger_owner_self_v1%'
    OR v_writer_def NOT LIKE '%has_current_subject_disclosure_v1%'
    OR v_writer_def NOT LIKE '%assign_native_ledger_company_work_under_scope_owner_self_api_v1%'
    OR v_writer_def NOT LIKE '%establish_continuing_original_work_internal_v1%'
    OR v_writer_def NOT LIKE '%sourceStandingCampaignId%'
    OR v_writer_def NOT LIKE '%p_campaign_end_date%'
    OR v_writer_def NOT LIKE '%continuing_care_actual_v1%'
    OR v_writer_def LIKE '%INSERT INTO atlas.care_observation_events%'
    OR v_writer_def LIKE '%INSERT INTO atlas.tasks%'
  THEN RAISE EXCEPTION 'Owner-standing original Work custody/physical truth guard missing';
  END IF;
  IF v_preview_def NOT LIKE '%validity_interval_seconds%'
    OR v_preview_def NOT LIKE '%has_current_subject_disclosure_v1%'
    OR v_preview_def NOT LIKE '%sourceStandingCampaignId%'
    OR v_preview_def NOT LIKE '%newWorkCreated%'
    OR v_preview_def LIKE '%INSERT INTO atlas.work_items%'
  THEN RAISE EXCEPTION 'Rule-aware read-only next Subject or privacy guard missing';
  END IF;
END
$standing$;

-- Signed acceptance must include:
-- 1 governor: exact ledger/scope, a real bed rule, owner-approved season
--   and selected date create ONE original Work + scoped allocation + plan;
-- 2 worker: direct owner writer denied; cannot pick hidden Bed4;
-- 3 outsider and revoked worker: original identity, context, result denied;
-- 4 replay: same exact owner action returns same original, changed reason,
--   worker, Ledger, cutoff or service date fails without mutating history;
-- 5 no physical weed condition/observation is asserted by release;
-- 6 distinct intervals (FR8 vs North Redbud Island) rank differently;
-- 7 when no Subject identity+condition grant exists for worker, preview
--   describes disclosure blocker and writer refuses admission;
-- 8 no old legacy open serving or second canonical open serving duplicated;
-- 9 typed full / acceptable / partial / blocked Actuals retain meaning;
-- 10 signed qualifying Actual must result in NEXT eligible independently
--    completable original Work: NOT PROVIDED BY THIS FIRST CANDIDATE.
-- No gate may report launch-ready until (10) is implemented and proven.


DO $standing_continuation$
DECLARE
 v record;
 v_def text;
BEGIN
 FOR v IN
   SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='atlas' AND p.proname IN (
     'governor_grant_standing_care_collection_self_api_v1',
     'standing_care_next_subject_internal_v1',
     'standing_care_auto_successor_authorized_v1',
     'advance_owner_standing_campaign_after_actual_internal_v1'
   )
 LOOP
   IF has_function_privilege('anon',v.oid,'EXECUTE')
     OR has_function_privilege('authenticated',v.oid,'EXECUTE')
   THEN
     RAISE EXCEPTION 'Premature app execution for %',v.proname;
   END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas' AND p.proname IN (
       'governor_grant_standing_care_collection_self_api_v1',
       'standing_care_next_subject_internal_v1',
       'standing_care_auto_successor_authorized_v1',
       'advance_owner_standing_campaign_after_actual_internal_v1'
     )) <> 4 THEN
   RAISE EXCEPTION 'Missing standing-care successor functions';
 END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
 AND p.proname='record_continuing_care_actual_self_api_v1';
 IF v_def NOT LIKE '%advance_owner_standing_campaign_after_actual_internal_v1%'
   OR v_def NOT LIKE '%source_continuation_needs_review%'
   OR v_def NOT LIKE '%campaignContinuation%'
 THEN RAISE EXCEPTION 'Signed Actual does not call bounded continuation'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
 AND p.proname='guard_work_allocation_responsibility_establishment_v2';
 IF v_def NOT LIKE '%standing_care_auto_successor_authorized_v1%'
   OR v_def NOT LIKE '%owner_preapproved_standing_care_actual_successor_v1%'
 THEN RAISE EXCEPTION 'Original Person allocation guard lacks bounded campaign exception'; END IF;
 SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas'
 AND p.proname='advance_owner_standing_campaign_after_actual_internal_v1';
 IF v_def NOT LIKE '%work_result_acceptances%'
   OR v_def NOT LIKE '%rhythm_satisfactions%'
   OR v_def NOT LIKE '%sourceStandingCampaignEndsOn%'
   OR v_def NOT LIKE '%standing_care_next_subject_internal_v1%'
   OR v_def NOT LIKE '%work_execution_plans%'
 THEN RAISE EXCEPTION 'Successor missing satisfaction/plan/season invariants'; END IF;
END;
$standing_continuation$;

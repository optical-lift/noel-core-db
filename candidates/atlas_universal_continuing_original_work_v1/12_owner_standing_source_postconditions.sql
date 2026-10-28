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

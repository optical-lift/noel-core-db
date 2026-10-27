-- Disposable-clone, synthetic-only validation for shared Us financial expectation v1.
-- This script must never be treated as a personal finance data migration.
BEGIN;
DO $test$
DECLARE
 v_user uuid := pg_catalog.gen_random_uuid();
 v_other uuid := pg_catalog.gen_random_uuid();
 v_source uuid;
 v_plan uuid;
 v_revision uuid;
 v_line uuid;
 v_actual numeric;
 v_coverage text;
 v_denied boolean := false;
BEGIN
 IF EXISTS(
   SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='us' AND c.relname IN
    ('financial_expectation_plans','financial_expectation_revisions',
     'financial_expectation_month_lines','financial_expectation_actual_links')
    AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
 ) THEN RAISE EXCEPTION 'Expectation storage RLS is not forced'; END IF;
 IF EXISTS(
  SELECT 1 FROM (VALUES
   ('us.financial_expectation_plans'),('us.financial_expectation_revisions'),
   ('us.financial_expectation_month_lines'),('us.financial_expectation_actual_links'),
   ('us.financial_expectation_month_comparison_v1')) t(name)
   WHERE pg_catalog.has_table_privilege('authenticated',t.name,'SELECT')
      OR pg_catalog.has_table_privilege('anon',t.name,'SELECT')
 ) THEN RAISE EXCEPTION 'Expectation leaked direct client SELECT'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_class WHERE oid='us.financial_expectation_month_comparison_v1'::regclass
  AND reloptions @> ARRAY['security_invoker=true']
 ) THEN RAISE EXCEPTION 'Comparison view not security invoker'; END IF;
 INSERT INTO atlas.evidence_records
  (scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
   source_kind,source_key,value,learned_at,provenance,metadata)
 VALUES('person',v_user,'personal_finance','synthetic_forecast','test',
  'synthetic_test_only','synthetic_clone','test-'||v_user::text,
  '{}'::jsonb,now(),'{}'::jsonb,'{}'::jsonb) RETURNING id INTO v_source;
 BEGIN
  INSERT INTO us.financial_expectation_plans
   (owner_auth_user_id,stable_key,originating_evidence_id,period_start,period_end)
  VALUES(v_other,'synthetic:wrong_scope',v_source,'2027-01-01','2027-06-30');
 EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Wrong person evidence was admitted'; END IF;
 INSERT INTO us.financial_expectation_plans
  (owner_auth_user_id,stable_key,originating_evidence_id,period_start,period_end)
 VALUES(v_user,'synthetic:forecast_self',v_source,'2027-01-01','2027-06-30')
 RETURNING id INTO v_plan;
 INSERT INTO us.financial_expectation_revisions
  (plan_id,revision,source_evidence_id,standing)
 VALUES(v_plan,1,v_source,'adopted') RETURNING id INTO v_revision;
 INSERT INTO us.financial_expectation_month_lines
  (revision_id,period_month,line_key,economic_scope,organization_id,
   money_role,amount_basis,expectation_state,forecast_amount)
 VALUES(v_revision,'2027-01-01','synthetic_tuition','organization',
  pg_catalog.gen_random_uuid(),'gross_inflow','gross','target',900)
 RETURNING id INTO v_line;
 SELECT actual_from_verified_sources,coverage_state
 INTO v_actual,v_coverage
 FROM us.financial_expectation_month_comparison_v1 WHERE line_id=v_line;
 IF v_actual IS NOT NULL OR v_coverage <> 'no_verified_actual_coverage'
 THEN RAISE EXCEPTION 'Missing source incorrectly became a zero actual'; END IF;
 v_denied := false;
 BEGIN
  INSERT INTO us.financial_expectation_actual_links
   (revision_id,line_id,source_kind,source_id)
  VALUES(v_revision,v_line,'atlas_commercial_payment',pg_catalog.gen_random_uuid());
 EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Unowned/missing commercial payment was bound'; END IF;
 v_denied := false;
 BEGIN
  UPDATE us.financial_expectation_month_lines SET forecast_amount=1000 WHERE id=v_line;
 EXCEPTION WHEN insufficient_privilege THEN v_denied := true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Old expectation mutated'; END IF;
END;
$test$;
ROLLBACK;

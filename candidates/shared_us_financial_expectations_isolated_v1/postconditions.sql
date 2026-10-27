-- Synthetic-only disposable-clone acceptance tests. The entire test rolls back.
-- No real person, bank details, business receipts, or private source content.
BEGIN;
DO $test$
DECLARE
  owner_a uuid := pg_catalog.gen_random_uuid();
  owner_b uuid := pg_catalog.gen_random_uuid();
  plan_a uuid;
  revision_a uuid;
  line_a uuid;
  obs_a uuid;
  obs_b uuid;
  snapshot_line uuid;
  snapshot_old uuid;
  snapshot_new uuid;
  n integer;
  observed numeric;
  state text;
  rejected boolean;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
     JOIN pg_catalog.pg_namespace ns ON ns.oid=c.relnamespace
    WHERE ns.nspname='us'
      AND c.relname IN ('financial_expectation_plans','financial_expectation_revisions',
        'financial_expectation_lines','financial_observed_evidence',
        'financial_expectation_actual_links')
      AND (NOT c.relrowsecurity OR NOT c.relforcerowsecurity)
  ) THEN RAISE EXCEPTION 'Financial custody missing forced RLS'; END IF;
  IF EXISTS(
    SELECT 1 FROM (VALUES
      ('us.financial_expectation_plans'),('us.financial_expectation_revisions'),
      ('us.financial_expectation_lines'),('us.financial_observed_evidence'),
      ('us.financial_expectation_actual_links'),
      ('us.financial_expectation_comparison_v1')) AS tbl(name)
    WHERE pg_catalog.has_table_privilege('anon',tbl.name,'SELECT') OR
          pg_catalog.has_table_privilege('authenticated',tbl.name,'SELECT') OR
          pg_catalog.has_table_privilege('authenticated',tbl.name,'INSERT')
  ) THEN RAISE EXCEPTION 'Financial records client-visible or writable'; END IF;
  IF NOT EXISTS(
     SELECT 1 FROM pg_catalog.pg_class
     WHERE oid='us.financial_expectation_comparison_v1'::regclass
      AND reloptions @> ARRAY['security_invoker=true']
  ) THEN RAISE EXCEPTION 'Financial comparison lacks invoker protection'; END IF;

  INSERT INTO us.financial_expectation_plans
    (owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
  VALUES (owner_a,'synthetic:plan_a','Synthetic isolated plan',
    '2027-01-01','2027-08-31','synthetic-private-reference')
  RETURNING id INTO plan_a;
  INSERT INTO us.financial_expectation_revisions
    (owner_auth_user_id,plan_id,revision,standing,source_ref)
  VALUES (owner_a,plan_a,1,'adopted','synthetic-private-revision-a')
  RETURNING id INTO revision_a;
  rejected:=false;
  BEGIN
    INSERT INTO us.financial_expectation_revisions
      (owner_auth_user_id,plan_id,revision,standing,source_ref)
    VALUES (owner_b,plan_a,2,'adopted','synthetic-private-revision-b');
  EXCEPTION WHEN foreign_key_violation THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Other owner could join a plan'; END IF;

  rejected:=false;
  BEGIN
    INSERT INTO us.financial_expectation_revisions
      (owner_auth_user_id,plan_id,revision,standing,source_ref)
    VALUES (owner_a,plan_a,3,'adopted','synthetic-private-revision-c');
  EXCEPTION WHEN invalid_parameter_value THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Skipped revision accepted'; END IF;

  INSERT INTO us.financial_expectation_lines
    (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,
     subject_key,money_role,expectation_state,forecast_amount)
  VALUES (owner_a,revision_a,'2027-01-01','tuition','venture',
      'fictional_school','gross_inflow','target',1000)
  RETURNING id INTO line_a;

  rejected:=false;
  BEGIN
    INSERT INTO us.financial_expectation_lines
      (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,
       subject_key,money_role,expectation_state,forecast_amount)
    VALUES (owner_a,revision_a,'2028-01-01','out_of_range','venture',
      'fictional_school','gross_inflow','target',1);
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Month outside plan was accepted'; END IF;

  SELECT reported_amount,coverage_state INTO observed,state
  FROM us.financial_expectation_comparison_v1 WHERE line_id=line_a;
  IF observed IS NOT NULL OR state<>'unknown_no_source_coverage' THEN
    RAISE EXCEPTION 'Missing actual silently became zero'; END IF;

  INSERT INTO us.financial_observed_evidence
    (owner_auth_user_id,source_family,source_key,observed_on,economic_scope,
     subject_key,money_role,amount,evidence_grade,evidence_ref)
  VALUES (owner_a,'synthetic', 'synthetic:source_a','2027-01-15','venture',
     'fictional_school','gross_inflow',250,'self_reported','synthetic-original')
  RETURNING id INTO obs_a;

  rejected:=false;
  BEGIN
    INSERT INTO us.financial_expectation_actual_links
      (owner_auth_user_id,revision_id,line_id,evidence_id)
    VALUES (owner_b,revision_a,line_a,obs_a);
  EXCEPTION WHEN foreign_key_violation OR insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Cross-owner actual bound'; END IF;
  INSERT INTO us.financial_expectation_actual_links
    (owner_auth_user_id,revision_id,line_id,evidence_id)
  VALUES (owner_a,revision_a,line_a,obs_a);
  SELECT reported_amount,coverage_state INTO observed,state
  FROM us.financial_expectation_comparison_v1 WHERE line_id=line_a;
  IF observed<>250 OR state<>'partial_observed_coverage' THEN
   RAISE EXCEPTION 'Source-backed partial difference failed'; END IF;

  rejected:=false;
  BEGIN
    INSERT INTO us.financial_expectation_actual_links
      (owner_auth_user_id,revision_id,line_id,evidence_id)
    VALUES (owner_a,revision_a,line_a,obs_a);
  EXCEPTION WHEN unique_violation THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Duplicate evidence accepted'; END IF;

  INSERT INTO us.financial_observed_evidence
    (owner_auth_user_id,source_family,source_key,observed_on,economic_scope,
     subject_key,money_role,amount,evidence_grade,evidence_ref,supersedes_id)
  VALUES (owner_a,'synthetic','synthetic:source_b','2027-01-15','venture',
    'fictional_school','gross_inflow',260,'document_correlated',
    'synthetic-revised-document',obs_a) RETURNING id INTO obs_b;
  SELECT reported_amount,coverage_state INTO observed,state
  FROM us.financial_expectation_comparison_v1 WHERE line_id=line_a;
  IF observed IS NOT NULL OR state<>'unknown_no_source_coverage' THEN
   RAISE EXCEPTION 'Superseded actual retained in comparison'; END IF;
  INSERT INTO us.financial_expectation_actual_links
    (owner_auth_user_id,revision_id,line_id,evidence_id)
  VALUES (owner_a,revision_a,line_a,obs_b);
  SELECT reported_amount,coverage_state INTO observed,state
  FROM us.financial_expectation_comparison_v1 WHERE line_id=line_a;
  IF observed<>260 OR state<>'partial_observed_coverage' THEN
   RAISE EXCEPTION 'Corrected source not reflected'; END IF;

  INSERT INTO us.financial_expectation_lines
    (owner_auth_user_id,revision_id,period_month,line_key,economic_scope,money_role,expectation_state,forecast_amount)
    VALUES(owner_a,revision_a,'2027-01-01','snapshot_check','personal','debt_balance','estimated',500)
    RETURNING id INTO snapshot_line;
  INSERT INTO us.financial_observed_evidence
    (owner_auth_user_id,source_family,source_key,observed_on,economic_scope,money_role,amount,evidence_grade,evidence_ref)
    VALUES(owner_a,'synthetic','synthetic:balance_early','2027-01-04','personal','debt_balance',400,'self_reported','synthetic-early')
    RETURNING id INTO snapshot_old;
  INSERT INTO us.financial_observed_evidence
    (owner_auth_user_id,source_family,source_key,observed_on,economic_scope,money_role,amount,evidence_grade,evidence_ref)
    VALUES(owner_a,'synthetic','synthetic:balance_later','2027-01-26','personal','debt_balance',300,'self_reported','synthetic-later')
    RETURNING id INTO snapshot_new;
  INSERT INTO us.financial_expectation_actual_links(owner_auth_user_id,revision_id,line_id,evidence_id)
    VALUES(owner_a,revision_a,snapshot_line,snapshot_old),
          (owner_a,revision_a,snapshot_line,snapshot_new);
  SELECT reported_amount INTO observed FROM us.financial_expectation_comparison_v1 WHERE line_id=snapshot_line;
  IF observed <> 300 THEN RAISE EXCEPTION 'Balance snapshot aggregation wrong'; END IF;
  rejected:=false;
  BEGIN
   UPDATE us.financial_expectation_lines SET forecast_amount=999
   WHERE id=line_a;
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Financial forecast history was mutable'; END IF;
  SELECT count(*) INTO n FROM us.financial_expectation_lines WHERE id=line_a;
  IF n<>1 THEN RAISE EXCEPTION 'Rolled-back test line unexpectedly gone'; END IF;
END;
$test$;
ROLLBACK;

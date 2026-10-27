-- Us-only Financial Expectations v1.
-- Structural candidate for governed migration generation. No personal records,
-- seed amounts, other product schema references, or production SQL deployment.
BEGIN;

CREATE TABLE us.financial_expectation_plans (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  plan_key text NOT NULL CHECK (plan_key ~ '^[a-z][a-z0-9_:-]{7,159}$'),
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 180),
  period_start date NOT NULL,
  period_end date NOT NULL,
  source_ref text NOT NULL CHECK (length(btrim(source_ref)) BETWEEN 5 AND 250),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_fin_plans_valid_dates CHECK (period_end>=period_start),
  CONSTRAINT us_fin_plans_owner_key UNIQUE(owner_auth_user_id,plan_key),
  CONSTRAINT us_fin_plans_id_owner UNIQUE(id,owner_auth_user_id)
);
COMMENT ON TABLE us.financial_expectation_plans IS
 'Us-owned identity of a personal financial expectation, not a ledger or account transaction.';

CREATE TABLE us.financial_expectation_revisions (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  revision integer NOT NULL CHECK (revision BETWEEN 1 AND 1000000),
  standing text NOT NULL CHECK (standing IN ('draft','adopted','withdrawn')),
  source_ref text NOT NULL CHECK (length(btrim(source_ref)) BETWEEN 5 AND 250),
  narrative jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(narrative)='object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_fin_revision_plan FOREIGN KEY(plan_id,owner_auth_user_id)
    REFERENCES us.financial_expectation_plans(id,owner_auth_user_id) ON DELETE RESTRICT,
  CONSTRAINT us_fin_revision_unique UNIQUE(plan_id,revision),
  CONSTRAINT us_fin_revision_source UNIQUE(plan_id,source_ref),
  CONSTRAINT us_fin_revision_owner_key UNIQUE(id,owner_auth_user_id)
);
COMMENT ON TABLE us.financial_expectation_revisions IS
 'Append-only, independently dated user-selected forecasts. Previous versions are never overwritten.';

CREATE TABLE us.financial_expectation_lines (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  period_month date NOT NULL CHECK (extract(day from period_month)=1),
  line_key text NOT NULL CHECK (line_key ~ '^[a-z][a-z0-9_:-]{3,159}$'),
  economic_scope text NOT NULL CHECK (economic_scope IN ('household','personal','venture')),
  subject_key text,
  money_role text NOT NULL CHECK (money_role IN
    ('gross_inflow','available_inflow','cash_outflow','card_charge',
     'card_payment','debt_balance','capital_budget')),
  expectation_state text NOT NULL CHECK (expectation_state IN
    ('committed','estimated','conditional','target')),
  forecast_amount numeric(18,2) NOT NULL CHECK(forecast_amount>=0),
  currency text NOT NULL DEFAULT 'USD' CHECK(currency ~ '^[A-Z]{3}$'),
  explanation text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_fin_line_subject_scope CHECK(
    (economic_scope='venture' AND subject_key IS NOT NULL AND btrim(subject_key)<>'')
    OR (economic_scope<>'venture' AND subject_key IS NULL)),
  CONSTRAINT us_fin_line_revision FOREIGN KEY(revision_id,owner_auth_user_id)
    REFERENCES us.financial_expectation_revisions(id,owner_auth_user_id) ON DELETE RESTRICT,
  CONSTRAINT us_fin_line_unique UNIQUE(revision_id,period_month,line_key),
  CONSTRAINT us_fin_line_owner_revision_key UNIQUE(id,owner_auth_user_id,revision_id)
);
COMMENT ON TABLE us.financial_expectation_lines IS
 'An amount is always scoped to a month, recipient/economic owner and distinct money role.';

-- Observed evidence lives in Us. An external identifier is a deduplication
-- key, NOT a connection or a copy of a transaction at another provider.
-- Corrections append a new source item with a supersedes reference.
CREATE TABLE us.financial_observed_evidence (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  source_family text NOT NULL CHECK (length(btrim(source_family)) BETWEEN 3 AND 100),
  source_key text NOT NULL CHECK (length(btrim(source_key)) BETWEEN 5 AND 250),
  observed_on date NOT NULL,
  economic_scope text NOT NULL CHECK (economic_scope IN ('household','personal','venture')),
  subject_key text,
  money_role text NOT NULL CHECK (money_role IN
    ('gross_inflow','available_inflow','cash_outflow','card_charge',
     'card_payment','debt_balance','capital_budget')),
  amount numeric(18,2) NOT NULL CHECK(amount>=0),
  currency text NOT NULL DEFAULT 'USD' CHECK(currency ~ '^[A-Z]{3}$'),
  evidence_grade text NOT NULL CHECK(evidence_grade IN
    ('self_reported','document_correlated','provider_correlated')),
  evidence_ref text NOT NULL CHECK(length(btrim(evidence_ref)) BETWEEN 5 AND 250),
  supersedes_id uuid,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_fin_evidence_scope CHECK(
    (economic_scope='venture' AND subject_key IS NOT NULL AND btrim(subject_key)<>'')
    OR (economic_scope<>'venture' AND subject_key IS NULL)),
  CONSTRAINT us_fin_evidence_own_id UNIQUE(id,owner_auth_user_id),
  CONSTRAINT us_fin_evidence_source_unique UNIQUE(owner_auth_user_id,source_family,source_key),
  CONSTRAINT us_fin_evidence_superseded_once UNIQUE(supersedes_id),
  CONSTRAINT us_fin_evidence_self_supersession CHECK(supersedes_id IS NULL OR supersedes_id<>id),
  CONSTRAINT us_fin_evidence_supersession_owner FOREIGN KEY(supersedes_id,owner_auth_user_id)
    REFERENCES us.financial_observed_evidence(id,owner_auth_user_id) ON DELETE RESTRICT
);
COMMENT ON TABLE us.financial_observed_evidence IS
 'Source-cited personal financial observations, not verified banking truth or spend custody.';

CREATE TABLE us.financial_expectation_actual_links (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  revision_id uuid NOT NULL,
  line_id uuid NOT NULL,
  evidence_id uuid NOT NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_fin_link_revision FOREIGN KEY(revision_id,owner_auth_user_id)
    REFERENCES us.financial_expectation_revisions(id,owner_auth_user_id) ON DELETE RESTRICT,
  CONSTRAINT us_fin_link_line FOREIGN KEY(line_id,owner_auth_user_id,revision_id)
    REFERENCES us.financial_expectation_lines(id,owner_auth_user_id,revision_id) ON DELETE RESTRICT,
  CONSTRAINT us_fin_link_evidence FOREIGN KEY(evidence_id,owner_auth_user_id)
    REFERENCES us.financial_observed_evidence(id,owner_auth_user_id) ON DELETE RESTRICT,
  CONSTRAINT us_fin_no_duplicate_actual_per_revision UNIQUE(revision_id,evidence_id)
);
COMMENT ON TABLE us.financial_expectation_actual_links IS
 'Maps one Us source observation to at most one financial expectation line per revision.';

CREATE FUNCTION us.financial_expectation_revision_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.plan_id::text,0));
  IF NEW.revision<>coalesce((
      SELECT max(r.revision)+1 FROM us.financial_expectation_revisions r
      WHERE r.plan_id=NEW.plan_id),1)
  THEN RAISE EXCEPTION 'Nonsequential forecast revision' USING ERRCODE='22023'; END IF;
  RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_revision_seq_guard
 BEFORE INSERT ON us.financial_expectation_revisions
 FOR EACH ROW EXECUTE FUNCTION us.financial_expectation_revision_guard_v1();

CREATE FUNCTION us.financial_expectation_line_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM us.financial_expectation_revisions r
  JOIN us.financial_expectation_plans p ON p.id=r.plan_id
   AND p.owner_auth_user_id=r.owner_auth_user_id
  WHERE r.id=NEW.revision_id
    AND r.owner_auth_user_id=NEW.owner_auth_user_id
    AND NEW.period_month BETWEEN
      date_trunc('month',p.period_start::timestamp)::date AND
      date_trunc('month',p.period_end::timestamp)::date
 ) THEN RAISE EXCEPTION 'Forecast outside plan period or owner scope'
   USING ERRCODE='42501'; END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_line_period_guard
 BEFORE INSERT ON us.financial_expectation_lines
 FOR EACH ROW EXECUTE FUNCTION us.financial_expectation_line_guard_v1();

CREATE FUNCTION us.financial_observed_evidence_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_prior us.financial_observed_evidence%ROWTYPE;
BEGIN
 IF NEW.evidence_grade<>'self_reported' AND btrim(NEW.evidence_ref)=''
 THEN RAISE EXCEPTION 'Correlated actual requires source reference' USING ERRCODE='22023'; END IF;
 IF NEW.supersedes_id IS NOT NULL THEN
  SELECT * INTO v_prior FROM us.financial_observed_evidence
   WHERE id=NEW.supersedes_id AND owner_auth_user_id=NEW.owner_auth_user_id;
  IF v_prior.id IS NULL OR v_prior.source_family<>NEW.source_family
   OR v_prior.economic_scope<>NEW.economic_scope
   OR v_prior.subject_key IS DISTINCT FROM NEW.subject_key
   OR v_prior.money_role<>NEW.money_role OR v_prior.currency<>NEW.currency
  THEN RAISE EXCEPTION 'Supersession source or scope mismatch' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_observed_evidence_scope_guard
 BEFORE INSERT ON us.financial_observed_evidence
 FOR EACH ROW EXECUTE FUNCTION us.financial_observed_evidence_guard_v1();

CREATE FUNCTION us.financial_expectation_actual_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_line us.financial_expectation_lines%ROWTYPE;
DECLARE v_evidence us.financial_observed_evidence%ROWTYPE;
BEGIN
 SELECT * INTO v_line FROM us.financial_expectation_lines
 WHERE id=NEW.line_id AND revision_id=NEW.revision_id
   AND owner_auth_user_id=NEW.owner_auth_user_id;
 SELECT * INTO v_evidence FROM us.financial_observed_evidence
 WHERE id=NEW.evidence_id AND owner_auth_user_id=NEW.owner_auth_user_id;
 IF v_line.id IS NULL OR v_evidence.id IS NULL OR
   v_line.economic_scope<>v_evidence.economic_scope OR
   v_line.subject_key IS DISTINCT FROM v_evidence.subject_key OR
   v_line.money_role<>v_evidence.money_role OR
   v_line.currency<>v_evidence.currency OR
   v_line.period_month<>date_trunc('month',v_evidence.observed_on::timestamp)::date
 THEN RAISE EXCEPTION 'Financial source and forecast mismatch'
 USING ERRCODE='42501'; END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_actual_scope_guard
 BEFORE INSERT ON us.financial_expectation_actual_links
 FOR EACH ROW EXECUTE FUNCTION us.financial_expectation_actual_guard_v1();

CREATE FUNCTION us.financial_expectation_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
BEGIN
 RAISE EXCEPTION 'Financial expectation custody is append-only' USING ERRCODE='42501';
END;
$fn$;
CREATE TRIGGER financial_plans_immutable BEFORE UPDATE OR DELETE
 ON us.financial_expectation_plans FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_immutable_v1();
CREATE TRIGGER financial_revisions_immutable BEFORE UPDATE OR DELETE
 ON us.financial_expectation_revisions FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_immutable_v1();
CREATE TRIGGER financial_lines_immutable BEFORE UPDATE OR DELETE
 ON us.financial_expectation_lines FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_immutable_v1();
CREATE TRIGGER financial_evidence_immutable BEFORE UPDATE OR DELETE
 ON us.financial_observed_evidence FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_immutable_v1();
CREATE TRIGGER financial_links_immutable BEFORE UPDATE OR DELETE
 ON us.financial_expectation_actual_links FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_immutable_v1();

-- Every observation is explicitly partial coverage; even correlated sources
-- are not proof that all transactions for the month are present.
-- Corrected evidence is excluded; linking its replacement is separate.
CREATE VIEW us.financial_expectation_comparison_v1
WITH (security_invoker=true) AS
SELECT p.id AS plan_id,p.owner_auth_user_id,p.plan_key,
 r.id AS revision_id,r.revision,r.standing,
 l.id AS line_id,l.period_month,l.line_key,l.economic_scope,l.subject_key,
 l.money_role,l.expectation_state,l.forecast_amount,l.currency,
 observed.reported_amount,observed.correlated_amount,
 observed.source_count,observed.correlated_count,
 CASE WHEN observed.source_count=0 THEN 'unknown_no_source_coverage'
      ELSE 'partial_observed_coverage' END AS coverage_state,
 CASE WHEN observed.source_count=0 THEN NULL
      ELSE observed.reported_amount-l.forecast_amount END AS partial_variance
FROM us.financial_expectation_lines l
JOIN us.financial_expectation_revisions r
 ON r.id=l.revision_id AND r.owner_auth_user_id=l.owner_auth_user_id
JOIN us.financial_expectation_plans p
 ON p.id=r.plan_id AND p.owner_auth_user_id=r.owner_auth_user_id
LEFT JOIN LATERAL (
 -- Debt balances and capital budgets are stocks, not additive cash flows.
 -- Latest observed snapshot wins; tie-break on custody time and immutable id.
 SELECT (CASE WHEN l.money_role IN ('debt_balance','capital_budget')
              THEN (array_agg(e.amount ORDER BY e.observed_on DESC,
                  e.recorded_at DESC,e.id DESC))[1]
              ELSE sum(e.amount) END)::numeric(18,2) AS reported_amount,
        (CASE WHEN l.money_role IN ('debt_balance','capital_budget')
              THEN (array_agg(e.amount ORDER BY e.observed_on DESC,
                  e.recorded_at DESC,e.id DESC)
                  FILTER (WHERE e.evidence_grade<>'self_reported'))[1]
              ELSE sum(e.amount) FILTER (WHERE e.evidence_grade<>'self_reported')
         END)::numeric(18,2) AS correlated_amount,
        count(e.id)::int AS source_count,
        count(e.id) FILTER (WHERE e.evidence_grade<>'self_reported')::int
         AS correlated_count
 FROM us.financial_expectation_actual_links link
 JOIN us.financial_observed_evidence e
  ON e.id=link.evidence_id AND e.owner_auth_user_id=link.owner_auth_user_id
 WHERE link.line_id=l.id AND link.revision_id=l.revision_id
   AND link.owner_auth_user_id=l.owner_auth_user_id
   AND NOT EXISTS(
     SELECT 1 FROM us.financial_observed_evidence next
      WHERE next.supersedes_id=e.id AND next.owner_auth_user_id=e.owner_auth_user_id
   )
) observed ON true;
COMMENT ON VIEW us.financial_expectation_comparison_v1 IS
 'Private Us-only forecast versus source-cited partial observations; absent actual is NULL, never zero; partial variance is not a complete cash-flow reconciliation.';

CREATE INDEX financial_revisions_plan_idx
 ON us.financial_expectation_revisions(plan_id,revision DESC);
CREATE INDEX financial_lines_period_idx
 ON us.financial_expectation_lines(owner_auth_user_id,period_month,money_role);
CREATE INDEX financial_evidence_period_idx
 ON us.financial_observed_evidence(owner_auth_user_id,observed_on,money_role);
CREATE INDEX financial_actual_links_line_idx
 ON us.financial_expectation_actual_links(line_id,revision_id);

-- No client-side or public read/write. An independently authenticated,
-- owner-validated service is the only allowed access path for now.
ALTER TABLE us.financial_expectation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_revisions FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_observed_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_observed_evidence FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_actual_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_actual_links FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.financial_expectation_plans,
 us.financial_expectation_revisions,us.financial_expectation_lines,
 us.financial_observed_evidence,us.financial_expectation_actual_links
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON us.financial_expectation_comparison_v1
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
 us.financial_expectation_revision_guard_v1(),
 us.financial_expectation_line_guard_v1(),
 us.financial_observed_evidence_guard_v1(),
 us.financial_expectation_actual_guard_v1(),
 us.financial_expectation_immutable_v1()
 FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA us TO service_role;
GRANT SELECT,INSERT ON
 us.financial_expectation_plans,us.financial_expectation_revisions,
 us.financial_expectation_lines,us.financial_observed_evidence,
 us.financial_expectation_actual_links TO service_role;
GRANT SELECT ON us.financial_expectation_comparison_v1 TO service_role;
COMMIT;

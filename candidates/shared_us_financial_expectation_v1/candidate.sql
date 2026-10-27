-- Shared Us/Atlas financial expectation contract v1.
-- Structural-only migration candidate. No real or synthetic personal financial data.
-- Generated migration identity and production release MUST use governed repo workflows.
BEGIN;

CREATE TABLE us.financial_expectation_plans (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 owner_auth_user_id uuid NOT NULL,
 stable_key text NOT NULL CHECK (stable_key ~ '^[a-z][a-z0-9_:-]{7,159}$'),
 originating_evidence_id uuid NOT NULL REFERENCES atlas.evidence_records(id) ON DELETE RESTRICT,
 period_start date NOT NULL,
 period_end date NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT us_fin_expectation_valid_period CHECK (period_end >= period_start),
 CONSTRAINT us_fin_expectation_owner_key UNIQUE(owner_auth_user_id,stable_key)
);
COMMENT ON TABLE us.financial_expectation_plans IS
 'Private personal financial expectation identity, pointing to original person-scoped evidence. Neither a bank ledger nor a payment table.';

CREATE TABLE us.financial_expectation_revisions (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 plan_id uuid NOT NULL REFERENCES us.financial_expectation_plans(id) ON DELETE RESTRICT,
 revision integer NOT NULL CHECK (revision > 0),
 source_evidence_id uuid NOT NULL REFERENCES atlas.evidence_records(id) ON DELETE RESTRICT,
 standing text NOT NULL CHECK (standing IN ('proposed','adopted','withdrawn')),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT us_fin_expectation_revision_unique UNIQUE(plan_id,revision),
 CONSTRAINT us_fin_expectation_revision_pair UNIQUE(id,plan_id)
);
COMMENT ON TABLE us.financial_expectation_revisions IS
 'Append-only expectation revisions. Higher revisions preserve earlier expectations rather than overwriting them.';

CREATE TABLE us.financial_expectation_month_lines (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 revision_id uuid NOT NULL REFERENCES us.financial_expectation_revisions(id) ON DELETE RESTRICT,
 period_month date NOT NULL CHECK (extract(day from period_month)=1),
 line_key text NOT NULL CHECK (line_key ~ '^[a-z][a-z0-9_:-]{3,159}$'),
 economic_scope text NOT NULL CHECK (economic_scope IN ('household','personal','organization')),
 organization_id uuid,
 money_role text NOT NULL CHECK (money_role IN
  ('gross_inflow','net_inflow','cash_outflow','card_charge','card_payment','debt_balance','capital_budget')),
 amount_basis text NOT NULL CHECK (amount_basis IN ('gross','net','balance','budget')),
 expectation_state text NOT NULL CHECK (expectation_state IN ('committed','estimated','conditional','target')),
 forecast_amount numeric(18,2) NOT NULL CHECK (forecast_amount>=0),
 currency text NOT NULL DEFAULT 'USD' CHECK (currency ~ '^[A-Z]{3}$'),
 provenance jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(provenance)='object'),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT us_fin_line_scope_check CHECK
  ((economic_scope='organization' AND organization_id IS NOT NULL) OR
   (economic_scope<>'organization' AND organization_id IS NULL)),
 CONSTRAINT us_fin_line_unique UNIQUE(revision_id,period_month,line_key),
 CONSTRAINT us_fin_line_revision_pair UNIQUE(id,revision_id)
);
COMMENT ON TABLE us.financial_expectation_month_lines IS
 'Month-specific forecast only. Gross venture receipts, institutional allocation, household cash, card debt and capital budgets are distinct roles; never sum unlike roles into one revenue number.';

-- A link references canonical actual evidence and contains NO copied actual amount.
-- In v1 only two Atlas-source types can be verified; personal bank feeds are absent.
CREATE TABLE us.financial_expectation_actual_links (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 revision_id uuid NOT NULL,
 line_id uuid NOT NULL,
 source_kind text NOT NULL CHECK (source_kind IN ('atlas_commercial_payment','atlas_organization_spend')),
 source_id uuid NOT NULL,
 verification_basis jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(verification_basis)='object'),
 linked_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT us_fin_link_line_revision_fk FOREIGN KEY (line_id,revision_id)
  REFERENCES us.financial_expectation_month_lines(id,revision_id) ON DELETE RESTRICT,
 CONSTRAINT us_fin_link_no_double_count UNIQUE(revision_id,source_kind,source_id)
);
COMMENT ON TABLE us.financial_expectation_actual_links IS
 'Reviewed reference to canonical Atlas financial actual. One source cannot be counted twice within the same forecast revision. Never use this to infer bank-transaction coverage.';

-- Preserve personal custody: the source evidence must belong to the exact auth person.
CREATE FUNCTION us.financial_expectation_plan_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM atlas.evidence_records e
   WHERE e.id=NEW.originating_evidence_id AND e.scope_kind='person'
    AND e.scope_id=NEW.owner_auth_user_id AND e.subject_domain='personal_finance'
 ) THEN
  RAISE EXCEPTION 'Originating person financial evidence mismatch' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_plan_guard
 BEFORE INSERT ON us.financial_expectation_plans FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_plan_guard_v1();

CREATE FUNCTION us.financial_expectation_revision_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_owner uuid;
BEGIN
 SELECT owner_auth_user_id INTO v_owner FROM us.financial_expectation_plans
 WHERE id=NEW.plan_id;
 IF v_owner IS NULL OR NOT EXISTS (
  SELECT 1 FROM atlas.evidence_records e WHERE e.id=NEW.source_evidence_id
   AND e.scope_kind='person' AND e.scope_id=v_owner AND e.subject_domain='personal_finance'
 ) THEN
  RAISE EXCEPTION 'Revision evidence scope mismatch' USING ERRCODE='42501';
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(NEW.plan_id::text,0));
 IF NEW.revision<>COALESCE((SELECT max(revision)+1
  FROM us.financial_expectation_revisions WHERE plan_id=NEW.plan_id),1) THEN
  RAISE EXCEPTION 'Revision must follow preceding revision' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_revision_guard
 BEFORE INSERT ON us.financial_expectation_revisions FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_revision_guard_v1();

-- Verified canonical event matching requires the same organizational ownership,
-- currency, month and economic direction. Personal/household lines cannot
-- silently consume an organization's payments.
CREATE FUNCTION us.financial_expectation_actual_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
DECLARE v_line us.financial_expectation_month_lines%ROWTYPE;
BEGIN
 SELECT * INTO v_line FROM us.financial_expectation_month_lines
  WHERE id=NEW.line_id AND revision_id=NEW.revision_id;
 IF v_line.id IS NULL OR v_line.economic_scope<>'organization' THEN
  RAISE EXCEPTION 'Unscoped financial binding' USING ERRCODE='42501';
 END IF;
 -- A service-role process cannot infer owner access from a supplied org UUID.
 -- Require active owner membership or active root-governing authority over a
 -- Ledger belonging to that organization before any canonical receipt binds.
 IF NOT EXISTS (
  SELECT 1 FROM us.financial_expectation_revisions r
  JOIN us.financial_expectation_plans plan ON plan.id=r.plan_id
  JOIN atlas.organization_memberships om ON om.organization_id=v_line.organization_id
     AND om.user_id=plan.owner_auth_user_id
     AND om.active=true AND om.role='owner'
  WHERE r.id=NEW.revision_id
 ) AND NOT EXISTS (
  SELECT 1 FROM us.financial_expectation_revisions r
  JOIN us.financial_expectation_plans plan ON plan.id=r.plan_id
  JOIN atlas.principals principal ON principal.user_id=plan.owner_auth_user_id
  JOIN atlas.principal_ledger_authorities a ON a.principal_id=principal.id
   AND a.status='active' AND a.authority_kind='root_governing'
  JOIN atlas.ledgers ledger ON ledger.id=a.ledger_id
   AND ledger.organization_id=v_line.organization_id
  WHERE r.id=NEW.revision_id
 ) THEN
  RAISE EXCEPTION 'No verified owner financial scope for organization'
   USING ERRCODE='42501';
 END IF;
 IF NEW.source_kind='atlas_commercial_payment' THEN
  IF v_line.money_role<>'gross_inflow' OR NOT EXISTS (
   SELECT 1 FROM atlas.commercial_payments p WHERE p.id=NEW.source_id
    AND p.organization_id=v_line.organization_id
    AND p.currency=v_line.currency AND p.observed_state='succeeded'
    AND date_trunc('month',p.paid_at AT TIME ZONE 'UTC')::date=v_line.period_month
  ) THEN
   RAISE EXCEPTION 'Commercial payment scope or receipt mismatch' USING ERRCODE='42501';
  END IF;
 ELSIF NEW.source_kind='atlas_organization_spend' THEN
  IF v_line.money_role<>'cash_outflow' OR NOT EXISTS (
   SELECT 1 FROM atlas.organization_spend_occurrences s WHERE s.id=NEW.source_id
    AND s.organization_id=v_line.organization_id
    AND s.currency=v_line.currency AND s.truth_state='confirmed'
    AND date_trunc('month',s.occurred_on::timestamp)::date=v_line.period_month
  ) THEN
   RAISE EXCEPTION 'Spend scope or source-state mismatch' USING ERRCODE='42501';
  END IF;
 ELSE RAISE EXCEPTION 'Unsupported actual source' USING ERRCODE='22023';
 END IF;
 RETURN NEW;
END;
$fn$;
CREATE TRIGGER financial_expectation_actual_guard
 BEFORE INSERT ON us.financial_expectation_actual_links FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_actual_guard_v1();

CREATE FUNCTION us.financial_expectation_append_only_guard_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $fn$
BEGIN
 RAISE EXCEPTION 'Financial expectation history is append-only' USING ERRCODE='42501';
END;
$fn$;
CREATE TRIGGER financial_expectation_plans_immutable
 BEFORE UPDATE OR DELETE ON us.financial_expectation_plans FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_append_only_guard_v1();
CREATE TRIGGER financial_expectation_revisions_immutable
 BEFORE UPDATE OR DELETE ON us.financial_expectation_revisions FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_append_only_guard_v1();
CREATE TRIGGER financial_expectation_month_lines_immutable
 BEFORE UPDATE OR DELETE ON us.financial_expectation_month_lines FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_append_only_guard_v1();
CREATE TRIGGER financial_expectation_actual_links_immutable
 BEFORE UPDATE OR DELETE ON us.financial_expectation_actual_links FOR EACH ROW
 EXECUTE FUNCTION us.financial_expectation_append_only_guard_v1();

-- A source-backed partial measurement is not proof of complete period coverage.
-- Missing actual = NULL, never zero. No institutional gross may silently become
-- household distributable income.
CREATE VIEW us.financial_expectation_month_comparison_v1
 WITH (security_invoker=true)
AS
SELECT p.owner_auth_user_id,p.id AS plan_id,p.stable_key,r.id AS revision_id,
 r.revision,r.standing,l.id AS line_id,l.period_month,l.line_key,
 l.economic_scope,l.organization_id,l.money_role,l.amount_basis,
 l.expectation_state,l.currency,l.forecast_amount,
 a.actual_from_verified_sources,
 a.verified_source_count,
 CASE WHEN a.verified_source_count>0 THEN 'partial_verified_source_coverage'
      ELSE 'no_verified_actual_coverage' END AS coverage_state,
 CASE WHEN a.verified_source_count>0 THEN a.actual_from_verified_sources-l.forecast_amount
      ELSE NULL END AS partial_variance
FROM us.financial_expectation_month_lines l
JOIN us.financial_expectation_revisions r ON r.id=l.revision_id
JOIN us.financial_expectation_plans p ON p.id=r.plan_id
LEFT JOIN LATERAL (
 SELECT sum(src.actual_amount)::numeric(18,2) AS actual_from_verified_sources,
        count(src.actual_amount)::integer AS verified_source_count
 FROM (
  SELECT pay.amount AS actual_amount
  FROM us.financial_expectation_actual_links link
  JOIN atlas.commercial_payments pay ON pay.id=link.source_id
   AND pay.organization_id=l.organization_id
   AND pay.currency=l.currency AND pay.observed_state='succeeded'
  WHERE link.line_id=l.id AND link.source_kind='atlas_commercial_payment'
   AND l.economic_scope='organization' AND l.money_role='gross_inflow'
   AND date_trunc('month',pay.paid_at AT TIME ZONE 'UTC')::date=l.period_month
  UNION ALL
  SELECT spend.gross_amount AS actual_amount
  FROM us.financial_expectation_actual_links link
  JOIN atlas.organization_spend_occurrences spend ON spend.id=link.source_id
   AND spend.organization_id=l.organization_id
   AND spend.currency=l.currency AND spend.truth_state='confirmed'
  WHERE link.line_id=l.id AND link.source_kind='atlas_organization_spend'
   AND l.economic_scope='organization' AND l.money_role='cash_outflow'
   AND spend.occurred_on>=l.period_month
   AND spend.occurred_on<(l.period_month+interval '1 month')::date
 ) src
) a ON true;
COMMENT ON VIEW us.financial_expectation_month_comparison_v1 IS
 'Plan versus verified canonical source evidence. All observed actual coverage is partial until an independent completeness proof is implemented; source absence is unknown, never zero.';

CREATE INDEX us_fin_plan_owner_idx ON us.financial_expectation_plans(owner_auth_user_id,created_at DESC);
CREATE INDEX us_fin_revision_plan_idx ON us.financial_expectation_revisions(plan_id,revision DESC);
CREATE INDEX us_fin_line_month_idx ON us.financial_expectation_month_lines(revision_id,period_month,money_role);
CREATE INDEX us_fin_link_source_idx ON us.financial_expectation_actual_links(source_kind,source_id);

-- Canonical tables remain private. Only a separately authorized server process
-- may append; there is no new anon/authenticated/public data or function access.
ALTER TABLE us.financial_expectation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_plans FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_revisions FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_month_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_month_lines FORCE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_actual_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.financial_expectation_actual_links FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.financial_expectation_plans,us.financial_expectation_revisions,
 us.financial_expectation_month_lines,us.financial_expectation_actual_links
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON us.financial_expectation_month_comparison_v1 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION us.financial_expectation_plan_guard_v1(),
 us.financial_expectation_revision_guard_v1(),
 us.financial_expectation_actual_guard_v1(),
 us.financial_expectation_append_only_guard_v1() FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA us TO service_role;
GRANT SELECT,INSERT ON us.financial_expectation_plans,us.financial_expectation_revisions,
 us.financial_expectation_month_lines,us.financial_expectation_actual_links TO service_role;
GRANT SELECT ON us.financial_expectation_month_comparison_v1 TO service_role;
COMMIT;

BEGIN;

-- Atlas Organization Expense Reporting v1 schema proof.
--
-- Executable reviewed source only. This is NOT a canonical migration.
-- The final migration identity must be generated through the governed
-- noel-core-db Supabase migration/release lane.
--
-- Governing order:
-- real-world activity -> source evidence -> domain-owned fact
-- -> organization reporting interpretation -> exception review -> finished report
--
-- This tranche owns the reporting interpretation boundary only.
-- It deliberately does NOT invent canonical expense, travel, activity,
-- receipt, organization, or portfolio-unit truth.

create table atlas.organization_expense_reporting_contracts (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  contract_key text not null check (btrim(contract_key) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  reporting_body_name text not null check (btrim(reporting_body_name) <> ''),
  cadence text not null default 'monthly'
    check (cadence in ('monthly','quarterly','annual','custom')),
  base_currency text,
  status text not null default 'draft'
    check (status in ('draft','active','retired')),
  effective_from date not null,
  effective_to date,
  policy_source_ref text,
  policy_source_hash text,
  output_template_ref text,
  output_template_hash text,
  template_config jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (base_currency is null or base_currency ~ '^[A-Z]{3}$'),
  check (policy_source_hash is null or policy_source_hash ~ '^[0-9a-f]{64}$'),
  check (output_template_hash is null or output_template_hash ~ '^[0-9a-f]{64}$'),
  unique (principal_id, contract_key, effective_from),
  unique (id, principal_id)
);

create table atlas.organization_expense_reporting_categories (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  contract_id uuid not null,
  category_key text not null check (btrim(category_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  export_label text not null check (btrim(export_label) <> ''),
  policy_definition text,
  examples jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id, principal_id)
    references atlas.organization_expense_reporting_contracts(id, principal_id)
    on delete cascade,
  unique (contract_id, category_key),
  unique (id, contract_id, principal_id)
);

create table atlas.organization_expense_reporting_periods (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  contract_id uuid not null,
  period_start date not null,
  period_end date not null,
  reporting_identity jsonb not null default '{}'::jsonb,
  state text not null default 'open'
    check (state in ('open','review','ready','submitted','reopened')),
  submitted_artifact_locator text,
  submitted_artifact_hash text,
  submitted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id, principal_id)
    references atlas.organization_expense_reporting_contracts(id, principal_id)
    on delete restrict,
  check (period_end >= period_start),
  check (submitted_artifact_hash is null or submitted_artifact_hash ~ '^[0-9a-f]{64}$'),
  check (state <> 'submitted' or submitted_at is not null),
  unique (contract_id, period_start, period_end),
  unique (id, contract_id, principal_id)
);

create table atlas.organization_expense_reporting_rates (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  period_id uuid not null,
  rate_key text not null check (btrim(rate_key) <> ''),
  rate_kind text not null
    check (rate_kind in ('currency_exchange','mileage','distance','other')),
  from_unit text,
  to_unit text,
  rate numeric not null check (rate > 0),
  effective_from date,
  effective_to date,
  source_kind text not null default 'organization_provided'
    check (source_kind in ('contract_provided','organization_provided','external_reference','human_confirmed')),
  source_ref text,
  source_as_of timestamptz,
  confirmed_by_user_id uuid,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (period_id, principal_id)
    references atlas.organization_expense_reporting_periods(id, principal_id)
    on delete cascade,
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (source_kind <> 'human_confirmed' or (confirmed_by_user_id is not null and confirmed_at is not null)),
  unique (period_id, rate_key, effective_from)
);

create table atlas.organization_expense_reporting_fact_links (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  contract_id uuid not null,
  period_id uuid not null,
  fact_kind text not null
    check (fact_kind in ('expense','travel','impact_activity')),
  source_authority text not null check (btrim(source_authority) <> ''),
  source_ref text not null check (btrim(source_ref) <> ''),
  category_id uuid,
  classification_state text not null default 'unclassified'
    check (classification_state in ('unclassified','suggested','confirmed','not_applicable')),
  classification_confidence numeric,
  reporting_purpose text,
  export_overrides jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id, contract_id, principal_id)
    references atlas.organization_expense_reporting_periods(id, contract_id, principal_id)
    on delete cascade,
  foreign key (category_id, contract_id, principal_id)
    references atlas.organization_expense_reporting_categories(id, contract_id, principal_id)
    on delete restrict,
  check (classification_confidence is null or (classification_confidence >= 0 and classification_confidence <= 1)),
  check (fact_kind = 'expense' or category_id is null),
  unique (contract_id, fact_kind, source_authority, source_ref),
  unique (id, period_id, principal_id)
);

create table atlas.organization_expense_reporting_exceptions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  period_id uuid not null,
  fact_link_id uuid,
  exception_code text not null check (btrim(exception_code) <> ''),
  severity text not null default 'blocking'
    check (severity in ('blocking','warning')),
  question text not null check (btrim(question) <> ''),
  state text not null default 'open'
    check (state in ('open','resolved','waived')),
  resolution jsonb,
  resolution_note text,
  resolved_by_user_id uuid,
  resolved_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id, principal_id)
    references atlas.organization_expense_reporting_periods(id, principal_id)
    on delete cascade,
  foreign key (fact_link_id, period_id, principal_id)
    references atlas.organization_expense_reporting_fact_links(id, period_id, principal_id)
    on delete cascade,
  check (
    (state = 'open' and resolved_at is null and resolved_by_user_id is null)
    or
    (state in ('resolved','waived') and resolved_at is not null and resolved_by_user_id is not null)
  )
);

create index organization_expense_reporting_contracts_principal_status_idx
  on atlas.organization_expense_reporting_contracts
  (principal_id, status, effective_from desc);

create index organization_expense_reporting_categories_contract_order_idx
  on atlas.organization_expense_reporting_categories
  (contract_id, is_active, sort_order, canonical_label);

create index organization_expense_reporting_periods_principal_state_idx
  on atlas.organization_expense_reporting_periods
  (principal_id, state, period_start desc);

create index organization_expense_reporting_fact_links_period_kind_idx
  on atlas.organization_expense_reporting_fact_links
  (period_id, fact_kind, classification_state);

create index organization_expense_reporting_exceptions_period_state_idx
  on atlas.organization_expense_reporting_exceptions
  (period_id, state, severity, created_at);

alter table atlas.organization_expense_reporting_contracts enable row level security;
alter table atlas.organization_expense_reporting_categories enable row level security;
alter table atlas.organization_expense_reporting_periods enable row level security;
alter table atlas.organization_expense_reporting_rates enable row level security;
alter table atlas.organization_expense_reporting_fact_links enable row level security;
alter table atlas.organization_expense_reporting_exceptions enable row level security;

create policy organization_expense_reporting_contracts_self_read
on atlas.organization_expense_reporting_contracts for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_contracts.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

create policy organization_expense_reporting_categories_self_read
on atlas.organization_expense_reporting_categories for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_categories.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

create policy organization_expense_reporting_periods_self_read
on atlas.organization_expense_reporting_periods for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_periods.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

create policy organization_expense_reporting_rates_self_read
on atlas.organization_expense_reporting_rates for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_rates.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

create policy organization_expense_reporting_fact_links_self_read
on atlas.organization_expense_reporting_fact_links for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_fact_links.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

create policy organization_expense_reporting_exceptions_self_read
on atlas.organization_expense_reporting_exceptions for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = organization_expense_reporting_exceptions.principal_id
    and p.user_id = (select auth.uid())
    and p.status = 'active'
));

-- Direct writes are not part of the v1 product contract. The released
-- application surface should use governed RPCs once the source-domain seams
-- and organization identity boundary have been confirmed.
revoke all on atlas.organization_expense_reporting_contracts from anon;
revoke all on atlas.organization_expense_reporting_categories from anon;
revoke all on atlas.organization_expense_reporting_periods from anon;
revoke all on atlas.organization_expense_reporting_rates from anon;
revoke all on atlas.organization_expense_reporting_fact_links from anon;
revoke all on atlas.organization_expense_reporting_exceptions from anon;

grant select on atlas.organization_expense_reporting_contracts to authenticated;
grant select on atlas.organization_expense_reporting_categories to authenticated;
grant select on atlas.organization_expense_reporting_periods to authenticated;
grant select on atlas.organization_expense_reporting_rates to authenticated;
grant select on atlas.organization_expense_reporting_fact_links to authenticated;
grant select on atlas.organization_expense_reporting_exceptions to authenticated;

-- Read-only period bundle. This is intentionally narrow and does not claim
-- authority to admit or mutate source-domain facts.
create or replace function atlas.organization_expense_reporting_period_api_v1(
  p_period_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
begin
  select * into v_period
  from atlas.organization_expense_reporting_periods
  where id = p_period_id;

  if not found then
    return null;
  end if;

  select * into v_contract
  from atlas.organization_expense_reporting_contracts
  where id = v_period.contract_id;

  return jsonb_build_object(
    'schemaVersion', 'atlas_organization_expense_reporting_period_v1',
    'period', jsonb_build_object(
      'id', v_period.id,
      'periodStart', v_period.period_start,
      'periodEnd', v_period.period_end,
      'state', v_period.state,
      'reportingIdentity', v_period.reporting_identity,
      'submittedArtifactLocator', v_period.submitted_artifact_locator,
      'submittedAt', v_period.submitted_at
    ),
    'contract', jsonb_build_object(
      'id', v_contract.id,
      'contractKey', v_contract.contract_key,
      'displayName', v_contract.display_name,
      'reportingBodyName', v_contract.reporting_body_name,
      'cadence', v_contract.cadence,
      'baseCurrency', v_contract.base_currency,
      'templateConfig', v_contract.template_config
    ),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'categoryKey', c.category_key,
        'canonicalLabel', c.canonical_label,
        'exportLabel', c.export_label,
        'policyDefinition', c.policy_definition,
        'sortOrder', c.sort_order
      ) order by c.sort_order, c.canonical_label)
      from atlas.organization_expense_reporting_categories c
      where c.contract_id = v_period.contract_id and c.is_active
    ), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'rateKey', r.rate_key,
        'rateKind', r.rate_kind,
        'fromUnit', r.from_unit,
        'toUnit', r.to_unit,
        'rate', r.rate,
        'effectiveFrom', r.effective_from,
        'effectiveTo', r.effective_to,
        'sourceKind', r.source_kind,
        'sourceRef', r.source_ref,
        'sourceAsOf', r.source_as_of
      ) order by r.rate_key, r.effective_from)
      from atlas.organization_expense_reporting_rates r
      where r.period_id = v_period.id
    ), '[]'::jsonb),
    'factLinks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id,
        'factKind', f.fact_kind,
        'sourceAuthority', f.source_authority,
        'sourceRef', f.source_ref,
        'categoryId', f.category_id,
        'classificationState', f.classification_state,
        'classificationConfidence', f.classification_confidence,
        'reportingPurpose', f.reporting_purpose,
        'exportOverrides', f.export_overrides
      ) order by f.created_at, f.id)
      from atlas.organization_expense_reporting_fact_links f
      where f.period_id = v_period.id
    ), '[]'::jsonb),
    'exceptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id,
        'factLinkId', e.fact_link_id,
        'exceptionCode', e.exception_code,
        'severity', e.severity,
        'question', e.question,
        'state', e.state,
        'resolution', e.resolution,
        'resolutionNote', e.resolution_note,
        'resolvedAt', e.resolved_at
      ) order by case e.severity when 'blocking' then 0 else 1 end, e.created_at, e.id)
      from atlas.organization_expense_reporting_exceptions e
      where e.period_id = v_period.id
    ), '[]'::jsonb),
    'closeState', jsonb_build_object(
      'blockingExceptionCount', (
        select count(*)
        from atlas.organization_expense_reporting_exceptions e
        where e.period_id = v_period.id
          and e.state = 'open'
          and e.severity = 'blocking'
      ),
      'ready', not exists (
        select 1
        from atlas.organization_expense_reporting_exceptions e
        where e.period_id = v_period.id
          and e.state = 'open'
          and e.severity = 'blocking'
      )
    )
  );
end;
$function$;

revoke all on function atlas.organization_expense_reporting_period_api_v1(uuid) from public, anon;
grant execute on function atlas.organization_expense_reporting_period_api_v1(uuid) to authenticated;

ROLLBACK;

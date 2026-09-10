BEGIN;

-- Atlas Organization Expense Reporting v1 schema proof.
-- Executable reviewed source only. NOT a canonical migration.
-- No production state is changed; this file ends in ROLLBACK.
--
-- Live-schema inspection on 2026-09-10 confirmed canonical Atlas seams for:
--   atlas.organizations
--   atlas.organization_units
--   atlas.organization_memberships
--   atlas.evidence_records
--   atlas.organization_ledger_entries
-- This proof therefore uses organization custody rather than principal custody.
-- It intentionally does NOT invent canonical expense, travel, activity,
-- receipt, or participant truth.

create table atlas.organization_expense_reporting_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_key text not null check (btrim(contract_key) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  reporting_body_name text not null check (btrim(reporting_body_name) <> ''),
  cadence text not null default 'monthly'
    check (cadence in ('monthly','quarterly','annual','custom')),
  base_currency text check (base_currency is null or base_currency ~ '^[A-Z]{3}$'),
  status text not null default 'draft'
    check (status in ('draft','active','retired')),
  effective_from date not null,
  effective_to date,
  policy_source_ref text,
  policy_source_hash text check (policy_source_hash is null or policy_source_hash ~ '^[0-9a-f]{64}$'),
  output_template_ref text,
  output_template_hash text check (output_template_hash is null or output_template_hash ~ '^[0-9a-f]{64}$'),
  template_config jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  unique (organization_id, contract_key, effective_from),
  unique (id, organization_id)
);

create table atlas.organization_expense_reporting_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  contract_id uuid not null,
  category_key text not null check (btrim(category_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  -- Nullable intentionally: the CI pilot has canonical Printing but no
  -- confirmed export mapping because the workbook instead shows Publishing.
  export_label text check (export_label is null or btrim(export_label) <> ''),
  policy_definition text,
  examples jsonb not null default '[]'::jsonb,
  mapping_state text not null default 'confirmed'
    check (mapping_state in ('confirmed','requires_confirmation','unresolved')),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id, organization_id)
    references atlas.organization_expense_reporting_contracts(id, organization_id)
    on delete cascade,
  unique (contract_id, category_key),
  unique (id, contract_id, organization_id)
);

create table atlas.organization_expense_reporting_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_id uuid not null,
  period_start date not null,
  period_end date not null,
  reporting_identity jsonb not null default '{}'::jsonb,
  state text not null default 'open'
    check (state in ('open','review','ready','submitted','reopened')),
  submitted_artifact_locator text,
  submitted_artifact_hash text check (submitted_artifact_hash is null or submitted_artifact_hash ~ '^[0-9a-f]{64}$'),
  submitted_at timestamptz,
  submitted_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id, organization_id)
    references atlas.organization_expense_reporting_contracts(id, organization_id)
    on delete restrict,
  check (period_end >= period_start),
  check (state <> 'submitted' or submitted_at is not null),
  unique (contract_id, period_start, period_end),
  unique (id, organization_id),
  unique (id, contract_id, organization_id)
);

create table atlas.organization_expense_reporting_rates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
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
  confirmed_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (period_id, organization_id)
    references atlas.organization_expense_reporting_periods(id, organization_id)
    on delete cascade,
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (source_kind <> 'human_confirmed' or (confirmed_by_membership_id is not null and confirmed_at is not null)),
  unique (period_id, rate_key, effective_from)
);

create table atlas.organization_expense_reporting_fact_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  contract_id uuid not null,
  period_id uuid not null,
  fact_kind text not null
    check (fact_kind in ('expense','travel','impact_activity')),
  source_authority text not null check (btrim(source_authority) <> ''),
  source_ref text not null check (btrim(source_ref) <> ''),
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  category_id uuid,
  classification_state text not null default 'unclassified'
    check (classification_state in ('unclassified','suggested','confirmed','not_applicable')),
  classification_confidence numeric
    check (classification_confidence is null or (classification_confidence >= 0 and classification_confidence <= 1)),
  reporting_purpose text,
  export_overrides jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id, contract_id, organization_id)
    references atlas.organization_expense_reporting_periods(id, contract_id, organization_id)
    on delete cascade,
  foreign key (category_id, contract_id, organization_id)
    references atlas.organization_expense_reporting_categories(id, contract_id, organization_id)
    on delete restrict,
  check (fact_kind = 'expense' or category_id is null),
  unique (contract_id, fact_kind, source_authority, source_ref),
  unique (id, period_id, organization_id)
);

create table atlas.organization_expense_reporting_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
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
  resolved_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  resolved_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id, organization_id)
    references atlas.organization_expense_reporting_periods(id, organization_id)
    on delete cascade,
  foreign key (fact_link_id, period_id, organization_id)
    references atlas.organization_expense_reporting_fact_links(id, period_id, organization_id)
    on delete cascade,
  check (
    (state = 'open' and resolved_at is null and resolved_by_membership_id is null)
    or
    (state in ('resolved','waived') and resolved_at is not null and resolved_by_membership_id is not null)
  )
);

create index organization_expense_reporting_contracts_org_status_idx
  on atlas.organization_expense_reporting_contracts
  (organization_id, status, effective_from desc);

create index organization_expense_reporting_categories_contract_order_idx
  on atlas.organization_expense_reporting_categories
  (contract_id, is_active, sort_order, canonical_label);

create index organization_expense_reporting_periods_org_state_idx
  on atlas.organization_expense_reporting_periods
  (organization_id, state, period_start desc);

create index organization_expense_reporting_fact_links_period_kind_idx
  on atlas.organization_expense_reporting_fact_links
  (period_id, fact_kind, classification_state);

create index organization_expense_reporting_exceptions_period_state_idx
  on atlas.organization_expense_reporting_exceptions
  (period_id, state, severity, created_at);

-- RLS/write RPC policy is deliberately not invented here. The live schema
-- inspection confirms organization identity/membership, but the governing
-- organization authorization seam must be reused explicitly before release.
-- A canonical migration must establish that policy and expose writes only
-- through governed database functions.

create or replace function atlas.organization_expense_reporting_period_api_v1(
  p_period_id uuid
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog, atlas
as $function$
  select jsonb_build_object(
    'schemaVersion', 'atlas_organization_expense_reporting_period_v1',
    'period', jsonb_build_object(
      'id', p.id,
      'organizationId', p.organization_id,
      'organizationUnitId', p.organization_unit_id,
      'periodStart', p.period_start,
      'periodEnd', p.period_end,
      'state', p.state,
      'reportingIdentity', p.reporting_identity,
      'submittedArtifactLocator', p.submitted_artifact_locator,
      'submittedAt', p.submitted_at
    ),
    'contract', jsonb_build_object(
      'id', c.id,
      'contractKey', c.contract_key,
      'displayName', c.display_name,
      'reportingBodyName', c.reporting_body_name,
      'cadence', c.cadence,
      'baseCurrency', c.base_currency,
      'templateConfig', c.template_config
    ),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'categoryKey', x.category_key,
        'canonicalLabel', x.canonical_label,
        'exportLabel', x.export_label,
        'mappingState', x.mapping_state,
        'policyDefinition', x.policy_definition,
        'sortOrder', x.sort_order
      ) order by x.sort_order, x.canonical_label)
      from atlas.organization_expense_reporting_categories x
      where x.contract_id = c.id and x.is_active
    ), '[]'::jsonb),
    'rates', coalesce((
      select jsonb_agg(to_jsonb(r) - 'organization_id' order by r.rate_key, r.effective_from)
      from atlas.organization_expense_reporting_rates r
      where r.period_id = p.id
    ), '[]'::jsonb),
    'factLinks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id,
        'factKind', f.fact_kind,
        'sourceAuthority', f.source_authority,
        'sourceRef', f.source_ref,
        'evidenceRecordId', f.evidence_record_id,
        'categoryId', f.category_id,
        'classificationState', f.classification_state,
        'classificationConfidence', f.classification_confidence,
        'reportingPurpose', f.reporting_purpose,
        'exportOverrides', f.export_overrides
      ) order by f.created_at, f.id)
      from atlas.organization_expense_reporting_fact_links f
      where f.period_id = p.id
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
      where e.period_id = p.id
    ), '[]'::jsonb),
    'closeState', jsonb_build_object(
      'blockingExceptionCount', (
        select count(*) from atlas.organization_expense_reporting_exceptions e
        where e.period_id = p.id and e.state = 'open' and e.severity = 'blocking'
      ),
      'ready', not exists (
        select 1 from atlas.organization_expense_reporting_exceptions e
        where e.period_id = p.id and e.state = 'open' and e.severity = 'blocking'
      )
    )
  )
  from atlas.organization_expense_reporting_periods p
  join atlas.organization_expense_reporting_contracts c
    on c.id = p.contract_id and c.organization_id = p.organization_id
  where p.id = p_period_id;
$function$;

ROLLBACK;

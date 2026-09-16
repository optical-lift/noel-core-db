begin;

-- Atlas Organization Expense Reporting — Ledger-Custodied v1.
-- Reporting policy interprets canonical Spend; it never replaces Spend authority.

create table atlas.organization_expense_reporting_contracts (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_key text not null check (btrim(contract_key)<>''),
  display_name text not null check (btrim(display_name)<>''),
  reporting_body_name text not null check (btrim(reporting_body_name)<>''),
  cadence text not null default 'monthly' check (cadence in ('monthly','quarterly','annual','custom')),
  report_currency text not null check (report_currency ~ '^[A-Z]{3}$'),
  status text not null default 'active' check (status in ('draft','active','retired')),
  effective_from date not null,
  effective_to date,
  policy_source_ref text,
  policy_source_hash text check (policy_source_hash is null or policy_source_hash ~ '^[0-9a-f]{64}$'),
  output_template_ref text,
  output_template_hash text check (output_template_hash is null or output_template_hash ~ '^[0-9a-f]{64}$'),
  template_config jsonb not null default '{}'::jsonb check (jsonb_typeof(template_config)='object'),
  accounting_handoff_config jsonb not null default '{}'::jsonb check (jsonb_typeof(accounting_handoff_config)='object'),
  created_by_principal_id uuid references atlas.principals(id) on delete restrict,
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to>=effective_from),
  unique (ledger_id,contract_key,effective_from),
  unique (id,ledger_id,organization_id)
);

comment on table atlas.organization_expense_reporting_contracts is
  'Ledger-custodied organization reporting policy/configuration over canonical Spend. The contract does not own payment or Spend truth.';

create table atlas.organization_expense_reporting_categories (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  contract_id uuid not null,
  category_key text not null check (btrim(category_key)<>''),
  canonical_label text not null check (btrim(canonical_label)<>''),
  export_label text,
  policy_definition text,
  examples jsonb not null default '[]'::jsonb check (jsonb_typeof(examples)='array'),
  evidence_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence_rules)='object'),
  mapping_state text not null default 'confirmed' check (mapping_state in ('confirmed','requires_confirmation','unresolved')),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  configured_by_principal_id uuid references atlas.principals(id) on delete restrict,
  configured_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_contracts(id,ledger_id,organization_id)
    on delete cascade,
  check (export_label is null or btrim(export_label)<>''),
  unique (contract_id,category_key),
  unique (id,contract_id,ledger_id,organization_id)
);

comment on table atlas.organization_expense_reporting_categories is
  'Organization reporting category meaning. canonical_label meaning and exact export_label remain distinct authority.';

create table atlas.organization_expense_reporting_periods (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_id uuid not null,
  period_start date not null,
  period_end date not null,
  reporting_identity jsonb not null default '{}'::jsonb check (jsonb_typeof(reporting_identity)='object'),
  state text not null default 'open' check (state in ('open','review','ready','reopened')),
  opened_by_principal_id uuid references atlas.principals(id) on delete restrict,
  opened_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  state_changed_by_principal_id uuid references atlas.principals(id) on delete restrict,
  state_changed_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_contracts(id,ledger_id,organization_id)
    on delete restrict,
  check (period_end>=period_start),
  unique (contract_id,period_start,period_end),
  unique (id,ledger_id,organization_id),
  unique (id,contract_id,ledger_id,organization_id)
);

create table atlas.organization_expense_reporting_rates (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  period_id uuid not null,
  rate_key text not null check (btrim(rate_key)<>''),
  rate_kind text not null default 'currency_exchange' check (rate_kind in ('currency_exchange','other')),
  from_unit text,
  to_unit text,
  quote_value numeric check (quote_value is null or quote_value>0),
  quote_convention text check (quote_convention is null or quote_convention in (
    'source_units_per_one_reporting_unit','reporting_units_per_one_source_unit','canonical_multiplier'
  )),
  conversion_multiplier numeric check (conversion_multiplier is null or conversion_multiplier>0),
  effective_from date,
  effective_to date,
  source_kind text not null default 'organization_provided' check (source_kind in (
    'contract_provided','organization_provided','external_reference','human_confirmed'
  )),
  source_ref text,
  source_as_of timestamptz,
  configured_by_principal_id uuid references atlas.principals(id) on delete restrict,
  configured_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_periods(id,ledger_id,organization_id)
    on delete cascade,
  check (effective_to is null or effective_from is null or effective_to>=effective_from),
  check (
    (rate_kind='currency_exchange'
      and from_unit is not null and to_unit is not null
      and quote_value is not null and quote_convention is not null
      and conversion_multiplier is not null)
    or rate_kind<>'currency_exchange'
  ),
  unique (period_id,rate_key,effective_from),
  unique (id,period_id,ledger_id,organization_id)
);

create table atlas.organization_expense_reporting_fact_links (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  contract_id uuid not null,
  period_id uuid not null,
  spend_allocation_id uuid not null references atlas.organization_spend_allocations(id) on delete restrict,
  category_id uuid,
  inclusion_state text not null default 'unresolved' check (inclusion_state in ('unresolved','suggested','included','excluded')),
  classification_state text not null default 'unclassified' check (classification_state in ('unclassified','suggested','confirmed','not_applicable')),
  classification_confidence numeric check (classification_confidence is null or (classification_confidence>=0 and classification_confidence<=1)),
  claim_treatment text not null default 'unresolved' check (claim_treatment in (
    'unresolved','reimbursement','organization_paid','documentation_only','donated_non_reimbursed','not_applicable'
  )),
  reporting_purpose text,
  report_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(report_fields)='object'),
  confirmed_by_principal_id uuid references atlas.principals(id) on delete restrict,
  confirmed_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id,contract_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_periods(id,contract_id,ledger_id,organization_id)
    on delete cascade,
  foreign key (category_id,contract_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_categories(id,contract_id,ledger_id,organization_id)
    on delete restrict,
  check (reporting_purpose is null or btrim(reporting_purpose)<>''),
  unique (contract_id,spend_allocation_id),
  unique (id,period_id,ledger_id,organization_id)
);

comment on table atlas.organization_expense_reporting_fact_links is
  'Current report interpretation of one canonical active Spend allocation. Inclusion, classification, and claim treatment remain independent decisions.';

create table atlas.organization_expense_reporting_fact_events (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  fact_link_id uuid not null,
  period_id uuid not null,
  event_kind text not null check (event_kind in ('admitted','interpretation_updated')),
  actor_principal_id uuid not null references atlas.principals(id) on delete restrict,
  actor_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  source_kind text not null check (btrim(source_kind)<>''),
  source_key text not null check (btrim(source_key)<>''),
  before_state jsonb,
  after_state jsonb not null check (jsonb_typeof(after_state)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (fact_link_id,period_id,ledger_id,organization_id)
    references atlas.organization_expense_reporting_fact_links(id,period_id,ledger_id,organization_id)
    on delete cascade,
  check (before_state is null or jsonb_typeof(before_state)='object'),
  unique (ledger_id,source_kind,source_key)
);

create index organization_expense_reporting_contracts_custody_idx
  on atlas.organization_expense_reporting_contracts(ledger_id,organization_id,status,effective_from desc);
create index organization_expense_reporting_categories_contract_idx
  on atlas.organization_expense_reporting_categories(contract_id,is_active,sort_order,canonical_label);
create index organization_expense_reporting_periods_custody_idx
  on atlas.organization_expense_reporting_periods(ledger_id,organization_id,state,period_start desc);
create index organization_expense_reporting_rates_period_idx
  on atlas.organization_expense_reporting_rates(period_id,rate_kind,from_unit,to_unit,effective_from,effective_to);
create index organization_expense_reporting_fact_links_period_idx
  on atlas.organization_expense_reporting_fact_links(period_id,inclusion_state,classification_state,claim_treatment);
create index organization_expense_reporting_fact_events_link_idx
  on atlas.organization_expense_reporting_fact_events(fact_link_id,created_at,id);

create or replace function atlas.organization_expense_reporting_normalize_rate_v1(
  p_quote_value numeric,
  p_quote_convention text
)
returns numeric
language sql
immutable
set search_path=pg_catalog
as $function$
  select case
    when p_quote_value is null or p_quote_value<=0 then null
    when p_quote_convention='source_units_per_one_reporting_unit' then 1/p_quote_value
    when p_quote_convention in ('reporting_units_per_one_source_unit','canonical_multiplier') then p_quote_value
    else null
  end;
$function$;

create or replace function atlas.organization_expense_reporting_assert_custody_v1(
  p_ledger_id uuid,
  p_organization_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_ledger_id is null or p_organization_id is null or not exists(
    select 1
    from atlas.ledgers l
    join atlas.ledger_organization_participations p
      on p.ledger_id=l.id
     and p.organization_id=p_organization_id
     and p.status='active'
    where l.id=p_ledger_id and l.status='active'
  ) then
    raise exception 'Expense reporting requires an active Ledger and active Organization participation.' using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_expense_reporting_assert_principal_v1(
  p_principal_id uuid,
  p_label text
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_principal_id is null or not exists(
    select 1 from atlas.principals p where p.id=p_principal_id and p.status='active'
  ) then
    raise exception '% Principal must be active.',coalesce(nullif(btrim(p_label),''),'Referenced') using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_expense_reporting_assert_membership_v1(
  p_organization_id uuid,
  p_membership_id uuid,
  p_label text
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships om
    where om.id=p_membership_id and om.organization_id=p_organization_id and om.active
  ) then
    raise exception '% membership must be active in the reporting Organization.',coalesce(nullif(btrim(p_label),''),'Referenced') using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_expense_reporting_assert_unit_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units ou
    where ou.id=p_organization_unit_id and ou.organization_id=p_organization_id
  ) then
    raise exception 'Reporting Organization Unit does not belong to the reporting Organization.' using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_expense_reporting_root_principal_v1(
  p_ledger_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null or not atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id) then
    raise exception 'Root Ledger authority required.' using errcode='42501';
  end if;
  return v_principal;
end;
$function$;

create or replace function atlas.organization_expense_reporting_fact_snapshot_v1(p_fact_link_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'id',f.id,'ledgerId',f.ledger_id,'organizationId',f.organization_id,
    'contractId',f.contract_id,'periodId',f.period_id,'spendAllocationId',f.spend_allocation_id,
    'categoryId',f.category_id,'inclusionState',f.inclusion_state,
    'classificationState',f.classification_state,'classificationConfidence',f.classification_confidence,
    'claimTreatment',f.claim_treatment,'reportingPurpose',f.reporting_purpose,
    'reportFields',f.report_fields,'confirmedByPrincipalId',f.confirmed_by_principal_id,
    'confirmedByMembershipId',f.confirmed_by_membership_id,'confirmedAt',f.confirmed_at
  )
  from atlas.organization_expense_reporting_fact_links f
  where f.id=p_fact_link_id;
$function$;

create or replace function atlas.guard_organization_expense_reporting_contract_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  perform atlas.organization_expense_reporting_assert_unit_v1(new.organization_id,new.organization_unit_id);
  if new.created_by_principal_id is not null then
    perform atlas.organization_expense_reporting_assert_principal_v1(new.created_by_principal_id,'Contract creator');
  end if;
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.created_by_membership_id,'Contract creator');
  new.contract_key:=lower(btrim(new.contract_key));
  new.display_name:=btrim(new.display_name);
  new.reporting_body_name:=btrim(new.reporting_body_name);
  new.report_currency:=upper(btrim(new.report_currency));
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_contract_v1
before insert or update on atlas.organization_expense_reporting_contracts
for each row execute function atlas.guard_organization_expense_reporting_contract_v1();

create or replace function atlas.guard_organization_expense_reporting_category_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  perform atlas.organization_expense_reporting_assert_principal_v1(new.configured_by_principal_id,'Category configurator');
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.configured_by_membership_id,'Category configurator');
  if not exists(
    select 1 from atlas.organization_expense_reporting_contracts c
    where c.id=new.contract_id and c.ledger_id=new.ledger_id and c.organization_id=new.organization_id
  ) then raise exception 'Reporting category contract custody mismatch.' using errcode='23503'; end if;
  new.category_key:=lower(btrim(new.category_key));
  new.canonical_label:=btrim(new.canonical_label);
  new.export_label:=nullif(btrim(coalesce(new.export_label,'')),'');
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_category_v1
before insert or update on atlas.organization_expense_reporting_categories
for each row execute function atlas.guard_organization_expense_reporting_category_v1();

create or replace function atlas.guard_organization_expense_reporting_period_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  perform atlas.organization_expense_reporting_assert_unit_v1(new.organization_id,new.organization_unit_id);
  if new.opened_by_principal_id is not null then perform atlas.organization_expense_reporting_assert_principal_v1(new.opened_by_principal_id,'Period opener'); end if;
  if new.state_changed_by_principal_id is not null then perform atlas.organization_expense_reporting_assert_principal_v1(new.state_changed_by_principal_id,'Period state actor'); end if;
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.opened_by_membership_id,'Period opener');
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.state_changed_by_membership_id,'Period state actor');

  select * into v_contract from atlas.organization_expense_reporting_contracts c
  where c.id=new.contract_id and c.ledger_id=new.ledger_id and c.organization_id=new.organization_id;
  if v_contract.id is null then raise exception 'Reporting period contract custody mismatch.' using errcode='23503'; end if;
  if new.period_start<v_contract.effective_from or (v_contract.effective_to is not null and new.period_end>v_contract.effective_to) then
    raise exception 'Reporting period falls outside contract effective dates.' using errcode='23514';
  end if;
  if v_contract.organization_unit_id is not null and new.organization_unit_id is distinct from v_contract.organization_unit_id then
    raise exception 'Reporting period must preserve the contract Organization Unit scope.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_period_v1
before insert or update on atlas.organization_expense_reporting_periods
for each row execute function atlas.guard_organization_expense_reporting_period_v1();

create or replace function atlas.guard_organization_expense_reporting_rate_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  perform atlas.organization_expense_reporting_assert_principal_v1(new.configured_by_principal_id,'Rate configurator');
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.configured_by_membership_id,'Rate configurator');
  if not exists(
    select 1 from atlas.organization_expense_reporting_periods p
    where p.id=new.period_id and p.ledger_id=new.ledger_id and p.organization_id=new.organization_id
  ) then raise exception 'Reporting rate period custody mismatch.' using errcode='23503'; end if;
  new.rate_key:=lower(btrim(new.rate_key));
  new.from_unit:=case when new.from_unit is null then null else upper(btrim(new.from_unit)) end;
  new.to_unit:=case when new.to_unit is null then null else upper(btrim(new.to_unit)) end;
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_rate_v1
before insert or update on atlas.organization_expense_reporting_rates
for each row execute function atlas.guard_organization_expense_reporting_rate_v1();

create or replace function atlas.guard_organization_expense_reporting_fact_link_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_alloc atlas.organization_spend_allocations%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_period atlas.organization_expense_reporting_periods%rowtype;
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  if new.confirmed_by_principal_id is not null then perform atlas.organization_expense_reporting_assert_principal_v1(new.confirmed_by_principal_id,'Interpretation confirmer'); end if;
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.confirmed_by_membership_id,'Interpretation confirmer');

  select * into v_period from atlas.organization_expense_reporting_periods p
  where p.id=new.period_id and p.contract_id=new.contract_id and p.ledger_id=new.ledger_id and p.organization_id=new.organization_id;
  if v_period.id is null then raise exception 'Expense fact reporting-period custody mismatch.' using errcode='23503'; end if;

  select * into v_alloc from atlas.organization_spend_allocations a
  where a.id=new.spend_allocation_id and a.ledger_id=new.ledger_id and a.organization_id=new.organization_id and a.allocation_state='active';
  if v_alloc.id is null then raise exception 'Expense fact requires an active Spend allocation in the same Ledger custody.' using errcode='23503'; end if;
  select * into v_spend from atlas.organization_spend_occurrences s
  where s.id=v_alloc.spend_occurrence_id and s.ledger_id=new.ledger_id and s.organization_id=new.organization_id and s.truth_state<>'voided';
  if v_spend.id is null then raise exception 'Expense fact parent Spend occurrence is unavailable.' using errcode='55000'; end if;
  if v_spend.occurred_on not between v_period.period_start and v_period.period_end then raise exception 'Spend date is outside reporting period.' using errcode='23514'; end if;
  if v_period.organization_unit_id is not null and coalesce(v_alloc.organization_unit_id,v_spend.organization_unit_id) is distinct from v_period.organization_unit_id then
    raise exception 'Spend allocation is outside reporting-period Organization Unit scope.' using errcode='23514';
  end if;
  if new.category_id is not null and not exists(
    select 1 from atlas.organization_expense_reporting_categories c
    where c.id=new.category_id and c.contract_id=new.contract_id and c.ledger_id=new.ledger_id and c.organization_id=new.organization_id and c.is_active
  ) then raise exception 'Expense category is outside reporting contract custody.' using errcode='23503'; end if;
  new.reporting_purpose:=nullif(btrim(coalesce(new.reporting_purpose,'')),'');
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_fact_link_v1
before insert or update on atlas.organization_expense_reporting_fact_links
for each row execute function atlas.guard_organization_expense_reporting_fact_link_v1();

create or replace function atlas.guard_organization_expense_reporting_fact_event_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(new.ledger_id,new.organization_id);
  perform atlas.organization_expense_reporting_assert_principal_v1(new.actor_principal_id,'Interpretation actor');
  perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.actor_membership_id,'Interpretation actor');
  if not exists(
    select 1 from atlas.organization_expense_reporting_fact_links f
    where f.id=new.fact_link_id and f.period_id=new.period_id and f.ledger_id=new.ledger_id and f.organization_id=new.organization_id
  ) then raise exception 'Reporting interpretation event custody mismatch.' using errcode='23503'; end if;
  new.source_kind:=lower(btrim(new.source_kind));
  new.source_key:=btrim(new.source_key);
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_fact_event_v1
before insert on atlas.organization_expense_reporting_fact_events
for each row execute function atlas.guard_organization_expense_reporting_fact_event_v1();

create or replace function atlas.prevent_organization_expense_reporting_history_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Expense reporting interpretation history is append-only.' using errcode='55000';
end;
$function$;

create trigger organization_expense_reporting_fact_events_append_only_v1
before update or delete on atlas.organization_expense_reporting_fact_events
for each row execute function atlas.prevent_organization_expense_reporting_history_mutation_v1();

create or replace view atlas.organization_expense_reporting_rate_position_v1 as
select
  p.id period_id,p.ledger_id,p.organization_id,p.contract_id,
  r.id rate_id,r.rate_key,r.rate_kind,r.from_unit,r.to_unit,r.quote_value,r.quote_convention,
  r.conversion_multiplier,r.effective_from,r.effective_to,r.source_kind,r.source_ref,r.source_as_of,r.created_at
from atlas.organization_expense_reporting_periods p
join atlas.organization_expense_reporting_rates r
  on r.period_id=p.id and r.ledger_id=p.ledger_id and r.organization_id=p.organization_id;

create or replace view atlas.organization_expense_reporting_exception_position_v1 as
with base as (
  select
    f.id fact_link_id,f.ledger_id,f.organization_id,f.contract_id,f.period_id,
    f.spend_allocation_id,f.category_id,f.inclusion_state,f.classification_state,f.claim_treatment,
    f.reporting_purpose,f.report_fields,
    p.period_start,p.period_end,p.organization_unit_id period_unit_id,
    con.report_currency,con.template_config,
    c.canonical_label,c.evidence_rules,
    a.operational_purpose,a.allocated_amount,a.organization_unit_id allocation_unit_id,a.spend_occurrence_id,
    s.occurred_on,s.currency,s.funding_kind,s.organization_unit_id spend_unit_id,
    coalesce(rr.rate_count,0) rate_count,
    rr.conversion_multiplier,
    coalesce((c.evidence_rules->>'requiresReceipt')='true',false)
      and (
        nullif(c.evidence_rules->>'receiptConditionField','') is null
        or coalesce((f.report_fields->>(c.evidence_rules->>'receiptConditionField'))='true',false)
      ) requires_receipt,
    exists(
      select 1
      from atlas.organization_spend_evidence_links el
      where el.ledger_id=f.ledger_id
        and el.organization_id=f.organization_id
        and el.spend_occurrence_id=a.spend_occurrence_id
        and (el.spend_allocation_id is null or el.spend_allocation_id=a.id)
        and el.relation_kind in ('receipt','factura','invoice','supporting')
    ) has_required_evidence,
    nullif(con.template_config#>>'{expense,requiredFieldKey}','') required_field_key
  from atlas.organization_expense_reporting_fact_links f
  join atlas.organization_expense_reporting_periods p
    on p.id=f.period_id and p.ledger_id=f.ledger_id and p.organization_id=f.organization_id
  join atlas.organization_expense_reporting_contracts con
    on con.id=f.contract_id and con.ledger_id=f.ledger_id and con.organization_id=f.organization_id
  join atlas.organization_spend_allocations a
    on a.id=f.spend_allocation_id and a.ledger_id=f.ledger_id and a.organization_id=f.organization_id and a.allocation_state='active'
  join atlas.organization_spend_occurrences s
    on s.id=a.spend_occurrence_id and s.ledger_id=f.ledger_id and s.organization_id=f.organization_id and s.truth_state<>'voided'
  left join atlas.organization_expense_reporting_categories c
    on c.id=f.category_id and c.contract_id=f.contract_id and c.ledger_id=f.ledger_id and c.organization_id=f.organization_id
  left join lateral (
    select count(*)::integer rate_count,
           case when count(*)=1 then max(r.conversion_multiplier) else null end conversion_multiplier
    from atlas.organization_expense_reporting_rates r
    where r.period_id=f.period_id and r.ledger_id=f.ledger_id and r.organization_id=f.organization_id
      and r.rate_kind='currency_exchange'
      and r.from_unit=s.currency and r.to_unit=con.report_currency
      and coalesce(r.effective_from,p.period_start)<=s.occurred_on
      and coalesce(r.effective_to,p.period_end)>=s.occurred_on
      and r.conversion_multiplier is not null
  ) rr on true
)
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'reporting_eligibility_unresolved'::text exception_code,'blocking'::text severity,
       'Should this expense be included in this report?'::text question
from base where inclusion_state not in ('included','excluded')
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'purpose_missing','blocking','What was this expense for?'
from base where inclusion_state='included' and coalesce(nullif(btrim(reporting_purpose),''),nullif(btrim(operational_purpose),'')) is null
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'expense_category_unresolved','blocking','Which reporting category should this expense use?'
from base where inclusion_state='included' and (category_id is null or classification_state<>'confirmed')
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'reimbursement_treatment_unresolved','blocking','How should this member-funded expense be treated for this report?'
from base where inclusion_state='included' and funding_kind='organization_member' and claim_treatment='unresolved'
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'exchange_rate_missing','blocking','What exchange rate applies to this expense?'
from base where inclusion_state='included' and currency<>report_currency and rate_count=0
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'exchange_rate_ambiguous','blocking','More than one accepted exchange rate applies to this expense. Which one governs?'
from base where inclusion_state='included' and currency<>report_currency and rate_count>1
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'receipt_required_missing','blocking','A required receipt or supporting document is missing.'
from base where inclusion_state='included' and requires_receipt and not has_required_evidence
union all
select fact_link_id,ledger_id,organization_id,contract_id,period_id,
       'template_field_state_missing','warning','A configured report field still needs a value.'
from base
where inclusion_state='included' and required_field_key is not null and not (report_fields ? required_field_key);

create or replace view atlas.organization_expense_reporting_expense_lines_v1 as
select
  f.id fact_link_id,f.ledger_id,f.organization_id,f.contract_id,f.period_id,
  f.spend_allocation_id,a.spend_occurrence_id,f.category_id,c.category_key,c.canonical_label,c.export_label,c.sort_order,
  s.occurred_on,s.payee_label,a.allocated_amount source_amount,s.currency source_currency,
  con.report_currency,coalesce(nullif(btrim(f.reporting_purpose),''),a.operational_purpose) purpose,
  f.report_fields,
  rr.rate_id,rr.quote_value,rr.quote_convention,rr.conversion_multiplier,
  case
    when s.currency=con.report_currency then a.allocated_amount
    when rr.rate_count=1 then a.allocated_amount*rr.conversion_multiplier
    else null
  end report_amount,
  f.inclusion_state,f.classification_state,f.claim_treatment
from atlas.organization_expense_reporting_fact_links f
join atlas.organization_expense_reporting_periods p
  on p.id=f.period_id and p.ledger_id=f.ledger_id and p.organization_id=f.organization_id
join atlas.organization_expense_reporting_contracts con
  on con.id=f.contract_id and con.ledger_id=f.ledger_id and con.organization_id=f.organization_id
join atlas.organization_spend_allocations a
  on a.id=f.spend_allocation_id and a.ledger_id=f.ledger_id and a.organization_id=f.organization_id and a.allocation_state='active'
join atlas.organization_spend_occurrences s
  on s.id=a.spend_occurrence_id and s.ledger_id=f.ledger_id and s.organization_id=f.organization_id and s.truth_state<>'voided'
left join atlas.organization_expense_reporting_categories c
  on c.id=f.category_id and c.contract_id=f.contract_id and c.ledger_id=f.ledger_id and c.organization_id=f.organization_id
left join lateral(
  select count(*)::integer rate_count,
         case when count(*)=1 then max(r.id) else null end rate_id,
         case when count(*)=1 then max(r.quote_value) else null end quote_value,
         case when count(*)=1 then max(r.quote_convention) else null end quote_convention,
         case when count(*)=1 then max(r.conversion_multiplier) else null end conversion_multiplier
  from atlas.organization_expense_reporting_rates r
  where r.period_id=f.period_id and r.ledger_id=f.ledger_id and r.organization_id=f.organization_id
    and r.rate_kind='currency_exchange'
    and r.from_unit=s.currency and r.to_unit=con.report_currency
    and coalesce(r.effective_from,p.period_start)<=s.occurred_on
    and coalesce(r.effective_to,p.period_end)>=s.occurred_on
    and r.conversion_multiplier is not null
) rr on true
where f.inclusion_state='included';

create or replace view atlas.organization_expense_reporting_category_totals_v1 as
select
  l.ledger_id,l.organization_id,l.contract_id,l.period_id,l.category_id,l.category_key,l.canonical_label,l.export_label,
  min(l.sort_order) sort_order,count(*) detail_count,sum(l.report_amount) report_subtotal,
  jsonb_agg(l.fact_link_id order by l.occurred_on,l.fact_link_id) fact_link_ids,
  jsonb_agg(l.spend_allocation_id order by l.occurred_on,l.fact_link_id) spend_allocation_ids
from atlas.organization_expense_reporting_expense_lines_v1 l
where l.classification_state='confirmed' and l.report_amount is not null
group by l.ledger_id,l.organization_id,l.contract_id,l.period_id,l.category_id,l.category_key,l.canonical_label,l.export_label;

create or replace function atlas.configure_organization_expense_reporting_contract_self_api_v1(
  p_ledger_id uuid,
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_contract_key text,
  p_display_name text,
  p_reporting_body_name text,
  p_cadence text,
  p_report_currency text,
  p_effective_from date,
  p_effective_to date,
  p_categories jsonb,
  p_template_config jsonb default '{}'::jsonb,
  p_accounting_handoff_config jsonb default '{}'::jsonb,
  p_policy_source_ref text default null,
  p_policy_source_hash text default null,
  p_output_template_ref text default null,
  p_output_template_hash text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal uuid;
  v_membership uuid;
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
  v_item jsonb;
  v_key text;
  v_label text;
  v_export text;
  v_mapping text;
  v_sort integer;
  v_category_count integer:=0;
begin
  perform atlas.organization_expense_reporting_assert_custody_v1(p_ledger_id,p_organization_id);
  perform atlas.organization_expense_reporting_assert_unit_v1(p_organization_id,p_organization_unit_id);
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(p_ledger_id);
  v_membership:=atlas.current_organization_membership_v1(p_organization_id);

  if nullif(btrim(coalesce(p_contract_key,'')),'') is null
     or nullif(btrim(coalesce(p_display_name,'')),'') is null
     or nullif(btrim(coalesce(p_reporting_body_name,'')),'') is null
     or p_cadence not in ('monthly','quarterly','annual','custom')
     or upper(btrim(coalesce(p_report_currency,''))) !~ '^[A-Z]{3}$'
     or p_effective_from is null
     or (p_effective_to is not null and p_effective_to<p_effective_from)
     or p_categories is null or jsonb_typeof(p_categories)<>'array' then
    raise exception 'Complete valid reporting contract configuration and category array are required.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas.expense_reporting.contract:'||p_ledger_id::text||':'||lower(btrim(p_contract_key))||':'||p_effective_from::text,0));

  select * into v_contract
  from atlas.organization_expense_reporting_contracts c
  where c.ledger_id=p_ledger_id and c.contract_key=lower(btrim(p_contract_key)) and c.effective_from=p_effective_from
  for update;

  if v_contract.id is not null and exists(
    select 1 from atlas.organization_expense_reporting_periods p where p.contract_id=v_contract.id
  ) then
    raise exception 'A reporting contract version with periods is immutable; create a new effective version.' using errcode='55000';
  end if;

  if v_contract.id is null then
    insert into atlas.organization_expense_reporting_contracts(
      ledger_id,organization_id,organization_unit_id,contract_key,display_name,reporting_body_name,
      cadence,report_currency,status,effective_from,effective_to,policy_source_ref,policy_source_hash,
      output_template_ref,output_template_hash,template_config,accounting_handoff_config,
      created_by_principal_id,created_by_membership_id,metadata
    ) values(
      p_ledger_id,p_organization_id,p_organization_unit_id,p_contract_key,p_display_name,p_reporting_body_name,
      p_cadence,upper(btrim(p_report_currency)),'active',p_effective_from,p_effective_to,p_policy_source_ref,p_policy_source_hash,
      p_output_template_ref,p_output_template_hash,coalesce(p_template_config,'{}'::jsonb),coalesce(p_accounting_handoff_config,'{}'::jsonb),
      v_principal,v_membership,coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_contract;
  else
    if v_contract.organization_id<>p_organization_id then raise exception 'Reporting contract source identity belongs to another Organization.' using errcode='23514'; end if;
    update atlas.organization_expense_reporting_contracts c
    set organization_unit_id=p_organization_unit_id,display_name=p_display_name,reporting_body_name=p_reporting_body_name,
        cadence=p_cadence,report_currency=upper(btrim(p_report_currency)),status='active',effective_to=p_effective_to,
        policy_source_ref=p_policy_source_ref,policy_source_hash=p_policy_source_hash,
        output_template_ref=p_output_template_ref,output_template_hash=p_output_template_hash,
        template_config=coalesce(p_template_config,'{}'::jsonb),accounting_handoff_config=coalesce(p_accounting_handoff_config,'{}'::jsonb),
        metadata=coalesce(p_metadata,'{}'::jsonb),updated_at=now()
    where c.id=v_contract.id returning * into v_contract;
    update atlas.organization_expense_reporting_categories set is_active=false,updated_at=now() where contract_id=v_contract.id;
  end if;

  for v_item in select value from jsonb_array_elements(p_categories)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each reporting category must be an object.' using errcode='22023'; end if;
    v_key:=lower(btrim(coalesce(v_item->>'categoryKey','')));
    v_label:=btrim(coalesce(v_item->>'canonicalLabel',''));
    v_export:=nullif(btrim(coalesce(v_item->>'exportLabel','')),'');
    v_mapping:=coalesce(nullif(btrim(v_item->>'mappingState'),''),'confirmed');
    begin v_sort:=coalesce((v_item->>'sortOrder')::integer,0); exception when others then raise exception 'Category sortOrder must be an integer.' using errcode='22023'; end;
    if v_key='' or v_label='' or v_mapping not in ('confirmed','requires_confirmation','unresolved') then raise exception 'Each category requires a key, label, and valid mapping state.' using errcode='22023'; end if;
    if coalesce(v_item->'examples','[]'::jsonb) is null or jsonb_typeof(coalesce(v_item->'examples','[]'::jsonb))<>'array' then raise exception 'Category examples must be an array.' using errcode='22023'; end if;
    if coalesce(v_item->'evidenceRules','{}'::jsonb) is null or jsonb_typeof(coalesce(v_item->'evidenceRules','{}'::jsonb))<>'object' then raise exception 'Category evidenceRules must be an object.' using errcode='22023'; end if;

    insert into atlas.organization_expense_reporting_categories(
      ledger_id,organization_id,contract_id,category_key,canonical_label,export_label,policy_definition,
      examples,evidence_rules,mapping_state,sort_order,is_active,configured_by_principal_id,configured_by_membership_id,metadata
    ) values(
      p_ledger_id,p_organization_id,v_contract.id,v_key,v_label,v_export,nullif(btrim(coalesce(v_item->>'policyDefinition','')),''),
      coalesce(v_item->'examples','[]'::jsonb),coalesce(v_item->'evidenceRules','{}'::jsonb),v_mapping,v_sort,true,v_principal,v_membership,
      coalesce(v_item->'metadata','{}'::jsonb)
    ) on conflict (contract_id,category_key) do update
      set canonical_label=excluded.canonical_label,export_label=excluded.export_label,policy_definition=excluded.policy_definition,
          examples=excluded.examples,evidence_rules=excluded.evidence_rules,mapping_state=excluded.mapping_state,
          sort_order=excluded.sort_order,is_active=true,configured_by_principal_id=excluded.configured_by_principal_id,
          configured_by_membership_id=excluded.configured_by_membership_id,metadata=excluded.metadata,updated_at=now();
    v_category_count:=v_category_count+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','configure_organization_expense_reporting_contract_self_api_v1',
    'contractId',v_contract.id,'ledgerId',p_ledger_id,'organizationId',p_organization_id,
    'categoryCount',v_category_count,'reportCurrency',v_contract.report_currency,'status',v_contract.status
  );
end;
$function$;

create or replace function atlas.open_organization_expense_reporting_period_self_api_v1(
  p_contract_id uuid,
  p_organization_unit_id uuid,
  p_period_start date,
  p_period_end date,
  p_reporting_identity jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_principal uuid;
  v_membership uuid;
begin
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=p_contract_id and status='active';
  if v_contract.id is null then raise exception 'Active reporting contract required.' using errcode='P0002'; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_contract.ledger_id);
  v_membership:=atlas.current_organization_membership_v1(v_contract.organization_id);
  perform atlas.organization_expense_reporting_assert_unit_v1(v_contract.organization_id,p_organization_unit_id);
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then raise exception 'Valid reporting date window required.' using errcode='22023'; end if;

  select * into v_period from atlas.organization_expense_reporting_periods
  where contract_id=v_contract.id and period_start=p_period_start and period_end=p_period_end;
  if v_period.id is not null then
    return jsonb_build_object('contractVersion','open_organization_expense_reporting_period_self_api_v1','state','unchanged','periodId',v_period.id);
  end if;

  insert into atlas.organization_expense_reporting_periods(
    ledger_id,organization_id,organization_unit_id,contract_id,period_start,period_end,reporting_identity,state,
    opened_by_principal_id,opened_by_membership_id,state_changed_by_principal_id,state_changed_by_membership_id,metadata
  ) values(
    v_contract.ledger_id,v_contract.organization_id,p_organization_unit_id,v_contract.id,p_period_start,p_period_end,
    coalesce(p_reporting_identity,'{}'::jsonb),'open',v_principal,v_membership,v_principal,v_membership,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_period;

  return jsonb_build_object('contractVersion','open_organization_expense_reporting_period_self_api_v1','state','opened','periodId',v_period.id,'ledgerId',v_period.ledger_id,'organizationId',v_period.organization_id);
end;
$function$;

create or replace function atlas.set_organization_expense_reporting_rate_self_api_v1(
  p_period_id uuid,
  p_rate_key text,
  p_from_unit text,
  p_to_unit text,
  p_quote_value numeric,
  p_quote_convention text,
  p_effective_from date,
  p_effective_to date,
  p_source_kind text default 'organization_provided',
  p_source_ref text default null,
  p_source_as_of timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_principal uuid;
  v_membership uuid;
  v_multiplier numeric;
  v_rate atlas.organization_expense_reporting_rates%rowtype;
  v_key text:=lower(btrim(coalesce(p_rate_key,'')));
  v_from text:=upper(btrim(coalesce(p_from_unit,'')));
  v_to text:=upper(btrim(coalesce(p_to_unit,'')));
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then raise exception 'Reporting period not found.' using errcode='P0002'; end if;
  if v_period.state not in ('open','review','reopened') then raise exception 'Reporting period is not editable.' using errcode='55000'; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);
  if v_key='' or v_from !~ '^[A-Z]{3}$' or v_to !~ '^[A-Z]{3}$' or p_quote_value is null or p_quote_value<=0 then raise exception 'Valid currency rate identity, units, and positive quote required.' using errcode='22023'; end if;
  v_multiplier:=atlas.organization_expense_reporting_normalize_rate_v1(p_quote_value,p_quote_convention);
  if v_multiplier is null then raise exception 'Explicit supported rate quote convention required.' using errcode='22023'; end if;
  if p_effective_to is not null and p_effective_from is not null and p_effective_to<p_effective_from then raise exception 'Rate effective window is invalid.' using errcode='22023'; end if;
  if p_source_kind not in ('contract_provided','organization_provided','external_reference','human_confirmed') then raise exception 'Unsupported rate source kind.' using errcode='22023'; end if;

  insert into atlas.organization_expense_reporting_rates(
    ledger_id,organization_id,period_id,rate_key,rate_kind,from_unit,to_unit,quote_value,quote_convention,
    conversion_multiplier,effective_from,effective_to,source_kind,source_ref,source_as_of,
    configured_by_principal_id,configured_by_membership_id,metadata
  ) values(
    v_period.ledger_id,v_period.organization_id,v_period.id,v_key,'currency_exchange',v_from,v_to,p_quote_value,p_quote_convention,
    v_multiplier,p_effective_from,p_effective_to,p_source_kind,p_source_ref,p_source_as_of,
    v_principal,v_membership,coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (period_id,rate_key,effective_from) do update
    set from_unit=excluded.from_unit,to_unit=excluded.to_unit,quote_value=excluded.quote_value,quote_convention=excluded.quote_convention,
        conversion_multiplier=excluded.conversion_multiplier,effective_to=excluded.effective_to,source_kind=excluded.source_kind,
        source_ref=excluded.source_ref,source_as_of=excluded.source_as_of,configured_by_principal_id=excluded.configured_by_principal_id,
        configured_by_membership_id=excluded.configured_by_membership_id,metadata=excluded.metadata,updated_at=now()
  returning * into v_rate;

  return jsonb_build_object(
    'contractVersion','set_organization_expense_reporting_rate_self_api_v1','rateId',v_rate.id,
    'periodId',v_period.id,'fromUnit',v_rate.from_unit,'toUnit',v_rate.to_unit,
    'quoteValue',v_rate.quote_value,'quoteConvention',v_rate.quote_convention,'conversionMultiplier',v_rate.conversion_multiplier
  );
end;
$function$;

create or replace function atlas.interpret_organization_spend_for_expense_report_self_api_v1(
  p_period_id uuid,
  p_spend_allocation_id uuid,
  p_client_event_key text,
  p_inclusion_state text default 'unresolved',
  p_claim_treatment text default 'unresolved',
  p_category_id uuid default null,
  p_classification_state text default 'unclassified',
  p_classification_confidence numeric default null,
  p_reporting_purpose text default null,
  p_report_fields jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_alloc atlas.organization_spend_allocations%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_principal uuid;
  v_membership uuid;
  v_link atlas.organization_expense_reporting_fact_links%rowtype;
  v_event atlas.organization_expense_reporting_fact_events%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_confirmed boolean;
begin
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null then raise exception 'Client event key is required.' using errcode='22023'; end if;
  if p_inclusion_state not in ('unresolved','suggested','included','excluded') then raise exception 'Unsupported inclusion state.' using errcode='22023'; end if;
  if p_classification_state not in ('unclassified','suggested','confirmed','not_applicable') then raise exception 'Unsupported classification state.' using errcode='22023'; end if;
  if p_claim_treatment not in ('unresolved','reimbursement','organization_paid','documentation_only','donated_non_reimbursed','not_applicable') then raise exception 'Unsupported claim treatment.' using errcode='22023'; end if;
  if p_classification_confidence is not null and (p_classification_confidence<0 or p_classification_confidence>1) then raise exception 'Classification confidence must be between 0 and 1.' using errcode='22023'; end if;

  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then raise exception 'Reporting period not found.' using errcode='P0002'; end if;
  if v_period.state not in ('open','review','reopened') then raise exception 'Reporting period is not editable.' using errcode='55000'; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);

  select * into v_alloc from atlas.organization_spend_allocations
  where id=p_spend_allocation_id and ledger_id=v_period.ledger_id and organization_id=v_period.organization_id and allocation_state='active';
  if v_alloc.id is null then raise exception 'Active Spend allocation in reporting Ledger custody required.' using errcode='P0002'; end if;
  select * into v_spend from atlas.organization_spend_occurrences
  where id=v_alloc.spend_occurrence_id and ledger_id=v_period.ledger_id and organization_id=v_period.organization_id and truth_state<>'voided';
  if v_spend.id is null then raise exception 'Active parent Spend occurrence required.' using errcode='P0002'; end if;
  if v_spend.occurred_on not between v_period.period_start and v_period.period_end then raise exception 'Spend date is outside the reporting period.' using errcode='23514'; end if;
  if v_period.organization_unit_id is not null and coalesce(v_alloc.organization_unit_id,v_spend.organization_unit_id) is distinct from v_period.organization_unit_id then raise exception 'Spend is outside reporting Unit scope.' using errcode='23514'; end if;
  if p_category_id is not null and not exists(
    select 1 from atlas.organization_expense_reporting_categories c
    where c.id=p_category_id and c.contract_id=v_period.contract_id and c.ledger_id=v_period.ledger_id and c.organization_id=v_period.organization_id and c.is_active
  ) then raise exception 'Reporting category does not belong to this contract.' using errcode='23503'; end if;

  select * into v_event from atlas.organization_expense_reporting_fact_events e
  where e.ledger_id=v_period.ledger_id and e.source_kind='report_interpretation' and e.source_key=btrim(p_client_event_key);
  if v_event.id is not null then
    return jsonb_build_object('contractVersion','interpret_organization_spend_for_expense_report_self_api_v1','state','unchanged','factLinkId',v_event.fact_link_id,'eventId',v_event.id);
  end if;

  select * into v_link from atlas.organization_expense_reporting_fact_links f
  where f.contract_id=v_period.contract_id and f.spend_allocation_id=p_spend_allocation_id
  for update;
  if v_link.id is not null and v_link.period_id<>v_period.id then raise exception 'Spend allocation is already bound to another period under this contract.' using errcode='23514'; end if;

  v_confirmed:=p_inclusion_state in ('included','excluded') or p_classification_state='confirmed' or p_claim_treatment<>'unresolved';
  if v_link.id is null then
    insert into atlas.organization_expense_reporting_fact_links(
      ledger_id,organization_id,contract_id,period_id,spend_allocation_id,category_id,
      inclusion_state,classification_state,classification_confidence,claim_treatment,reporting_purpose,report_fields,
      confirmed_by_principal_id,confirmed_by_membership_id,confirmed_at,metadata
    ) values(
      v_period.ledger_id,v_period.organization_id,v_period.contract_id,v_period.id,p_spend_allocation_id,p_category_id,
      p_inclusion_state,p_classification_state,p_classification_confidence,p_claim_treatment,nullif(btrim(coalesce(p_reporting_purpose,'')),''),coalesce(p_report_fields,'{}'::jsonb),
      case when v_confirmed then v_principal else null end,case when v_confirmed then v_membership else null end,case when v_confirmed then now() else null end,
      coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_link;
    v_before:=null;
  else
    v_before:=atlas.organization_expense_reporting_fact_snapshot_v1(v_link.id);
    update atlas.organization_expense_reporting_fact_links f
    set category_id=p_category_id,inclusion_state=p_inclusion_state,classification_state=p_classification_state,
        classification_confidence=p_classification_confidence,claim_treatment=p_claim_treatment,
        reporting_purpose=nullif(btrim(coalesce(p_reporting_purpose,'')),''),report_fields=coalesce(p_report_fields,'{}'::jsonb),
        confirmed_by_principal_id=case when v_confirmed then v_principal else null end,
        confirmed_by_membership_id=case when v_confirmed then v_membership else null end,
        confirmed_at=case when v_confirmed then now() else null end,
        metadata=coalesce(p_metadata,'{}'::jsonb),updated_at=now()
    where f.id=v_link.id returning * into v_link;
  end if;
  v_after:=atlas.organization_expense_reporting_fact_snapshot_v1(v_link.id);

  insert into atlas.organization_expense_reporting_fact_events(
    ledger_id,organization_id,fact_link_id,period_id,event_kind,actor_principal_id,actor_membership_id,
    source_kind,source_key,before_state,after_state,metadata
  ) values(
    v_period.ledger_id,v_period.organization_id,v_link.id,v_period.id,
    case when v_before is null then 'admitted' else 'interpretation_updated' end,
    v_principal,v_membership,'report_interpretation',btrim(p_client_event_key),v_before,v_after,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_event;

  return jsonb_build_object(
    'contractVersion','interpret_organization_spend_for_expense_report_self_api_v1',
    'state',case when v_before is null then 'admitted' else 'updated' end,
    'factLinkId',v_link.id,'eventId',v_event.id,'periodId',v_period.id,'spendAllocationId',p_spend_allocation_id,
    'openBlocking',(select count(*) from atlas.organization_expense_reporting_exception_position_v1 e where e.fact_link_id=v_link.id and e.severity='blocking'),
    'openWarnings',(select count(*) from atlas.organization_expense_reporting_exception_position_v1 e where e.fact_link_id=v_link.id and e.severity='warning')
  );
end;
$function$;

create or replace function atlas.mark_organization_expense_reporting_period_ready_self_api_v1(p_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_principal uuid;
  v_membership uuid;
  v_blocking integer;
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id for update;
  if v_period.id is null then raise exception 'Reporting period not found.' using errcode='P0002'; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);
  select count(*) into v_blocking from atlas.organization_expense_reporting_exception_position_v1 e where e.period_id=v_period.id and e.severity='blocking';
  if v_blocking>0 then raise exception 'Reporting period has % blocking exception(s).',v_blocking using errcode='55000'; end if;
  update atlas.organization_expense_reporting_periods
  set state='ready',state_changed_by_principal_id=v_principal,state_changed_by_membership_id=v_membership,updated_at=now()
  where id=v_period.id;
  return jsonb_build_object('contractVersion','mark_organization_expense_reporting_period_ready_self_api_v1','periodId',v_period.id,'state','ready','blockingExceptionCount',0);
end;
$function$;

create or replace function atlas.reopen_organization_expense_reporting_period_self_api_v1(p_period_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_principal uuid;
  v_membership uuid;
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id for update;
  if v_period.id is null then raise exception 'Reporting period not found.' using errcode='P0002'; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);
  if v_period.state<>'ready' then raise exception 'Only a ready reporting period may be reopened.' using errcode='55000'; end if;
  update atlas.organization_expense_reporting_periods
  set state='reopened',state_changed_by_principal_id=v_principal,state_changed_by_membership_id=v_membership,updated_at=now()
  where id=v_period.id;
  return jsonb_build_object('contractVersion','reopen_organization_expense_reporting_period_self_api_v1','periodId',v_period.id,'state','reopened');
end;
$function$;

create or replace function atlas.organization_expense_reporting_period_self_api_v1(p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_principal uuid;
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then return null; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  return jsonb_build_object(
    'schemaVersion','atlas_organization_expense_reporting_period_v1',
    'period',jsonb_build_object(
      'id',v_period.id,'ledgerId',v_period.ledger_id,'organizationId',v_period.organization_id,
      'organizationUnitId',v_period.organization_unit_id,'contractId',v_period.contract_id,
      'periodStart',v_period.period_start,'periodEnd',v_period.period_end,'state',v_period.state,
      'reportingIdentity',v_period.reporting_identity
    ),
    'expenseLines',coalesce((
      select jsonb_agg(jsonb_build_object(
        'factLinkId',l.fact_link_id,'spendAllocationId',l.spend_allocation_id,'spendOccurrenceId',l.spend_occurrence_id,
        'categoryId',l.category_id,'categoryKey',l.category_key,'categoryLabel',l.canonical_label,'exportLabel',l.export_label,
        'occurredOn',l.occurred_on,'payeeLabel',l.payee_label,'sourceAmount',l.source_amount,'sourceCurrency',l.source_currency,
        'reportCurrency',l.report_currency,'purpose',l.purpose,'reportFields',l.report_fields,
        'rateId',l.rate_id,'quoteValue',l.quote_value,'quoteConvention',l.quote_convention,
        'conversionMultiplier',l.conversion_multiplier,'reportAmount',l.report_amount,
        'classificationState',l.classification_state,'claimTreatment',l.claim_treatment
      ) order by l.sort_order nulls last,l.canonical_label nulls last,l.occurred_on,l.fact_link_id)
      from atlas.organization_expense_reporting_expense_lines_v1 l where l.period_id=v_period.id
    ),'[]'::jsonb),
    'exceptions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'factLinkId',e.fact_link_id,'code',e.exception_code,'severity',e.severity,'question',e.question
      ) order by case e.severity when 'blocking' then 0 else 1 end,e.exception_code,e.fact_link_id)
      from atlas.organization_expense_reporting_exception_position_v1 e where e.period_id=v_period.id
    ),'[]'::jsonb),
    'blockingExceptionCount',(select count(*) from atlas.organization_expense_reporting_exception_position_v1 e where e.period_id=v_period.id and e.severity='blocking')
  );
end;
$function$;

create or replace function atlas.organization_expense_reporting_accounting_handoff_self_api_v1(p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
  v_principal uuid;
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then return null; end if;
  v_principal:=atlas.organization_expense_reporting_root_principal_v1(v_period.ledger_id);
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id;
  return jsonb_build_object(
    'schemaVersion','atlas_organization_expense_reporting_accounting_handoff_v1',
    'periodId',v_period.id,'periodState',v_period.state,'reportCurrency',v_contract.report_currency,
    'destination',v_contract.accounting_handoff_config,
    'detailGroups',coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoryId',g.category_id,'categoryKey',g.category_key,'categoryLabel',g.canonical_label,'exportLabel',g.export_label,
        'subtotal',g.report_subtotal,'detailCount',g.detail_count,'factLinkIds',g.fact_link_ids,'spendAllocationIds',g.spend_allocation_ids
      ) order by g.sort_order,g.canonical_label)
      from atlas.organization_expense_reporting_category_totals_v1 g where g.period_id=v_period.id
    ),'[]'::jsonb),
    'reportExpenseTotal',(select coalesce(sum(g.report_subtotal),0) from atlas.organization_expense_reporting_category_totals_v1 g where g.period_id=v_period.id),
    'blockingExceptionCount',(select count(*) from atlas.organization_expense_reporting_exception_position_v1 e where e.period_id=v_period.id and e.severity='blocking')
  );
end;
$function$;

alter table atlas.organization_expense_reporting_contracts enable row level security;
alter table atlas.organization_expense_reporting_categories enable row level security;
alter table atlas.organization_expense_reporting_periods enable row level security;
alter table atlas.organization_expense_reporting_rates enable row level security;
alter table atlas.organization_expense_reporting_fact_links enable row level security;
alter table atlas.organization_expense_reporting_fact_events enable row level security;

revoke all on table atlas.organization_expense_reporting_contracts from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_categories from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_periods from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_rates from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_fact_links from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_fact_events from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_rate_position_v1 from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_exception_position_v1 from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_expense_lines_v1 from public,anon,authenticated,service_role;
revoke all on table atlas.organization_expense_reporting_category_totals_v1 from public,anon,authenticated,service_role;

revoke all on function atlas.organization_expense_reporting_normalize_rate_v1(numeric,text) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_assert_custody_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_assert_principal_v1(uuid,text) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_assert_membership_v1(uuid,uuid,text) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_assert_unit_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_root_principal_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.organization_expense_reporting_fact_snapshot_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_contract_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_category_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_period_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_rate_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_fact_link_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.guard_organization_expense_reporting_fact_event_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.prevent_organization_expense_reporting_history_mutation_v1() from public,anon,authenticated,service_role;

revoke all on function atlas.configure_organization_expense_reporting_contract_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,date,date,jsonb,jsonb,jsonb,text,text,text,text,jsonb) from public,anon,service_role;
revoke all on function atlas.open_organization_expense_reporting_period_self_api_v1(uuid,uuid,date,date,jsonb,jsonb) from public,anon,service_role;
revoke all on function atlas.set_organization_expense_reporting_rate_self_api_v1(uuid,text,text,text,numeric,text,date,date,text,text,timestamp with time zone,jsonb) from public,anon,service_role;
revoke all on function atlas.interpret_organization_spend_for_expense_report_self_api_v1(uuid,uuid,text,text,text,uuid,text,numeric,text,jsonb,jsonb) from public,anon,service_role;
revoke all on function atlas.mark_organization_expense_reporting_period_ready_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.reopen_organization_expense_reporting_period_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.organization_expense_reporting_period_self_api_v1(uuid) from public,anon,service_role;
revoke all on function atlas.organization_expense_reporting_accounting_handoff_self_api_v1(uuid) from public,anon,service_role;

grant execute on function atlas.configure_organization_expense_reporting_contract_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,date,date,jsonb,jsonb,jsonb,text,text,text,text,jsonb) to authenticated;
grant execute on function atlas.open_organization_expense_reporting_period_self_api_v1(uuid,uuid,date,date,jsonb,jsonb) to authenticated;
grant execute on function atlas.set_organization_expense_reporting_rate_self_api_v1(uuid,text,text,text,numeric,text,date,date,text,text,timestamp with time zone,jsonb) to authenticated;
grant execute on function atlas.interpret_organization_spend_for_expense_report_self_api_v1(uuid,uuid,text,text,text,uuid,text,numeric,text,jsonb,jsonb) to authenticated;
grant execute on function atlas.mark_organization_expense_reporting_period_ready_self_api_v1(uuid) to authenticated;
grant execute on function atlas.reopen_organization_expense_reporting_period_self_api_v1(uuid) to authenticated;
grant execute on function atlas.organization_expense_reporting_period_self_api_v1(uuid) to authenticated;
grant execute on function atlas.organization_expense_reporting_accounting_handoff_self_api_v1(uuid) to authenticated;

comment on function atlas.configure_organization_expense_reporting_contract_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,date,date,jsonb,jsonb,jsonb,text,text,text,text,jsonb) is
  'Root-Ledger configuration of organization-specific expense reporting policy. Does not create Spend or accounting transactions.';

comment on function atlas.interpret_organization_spend_for_expense_report_self_api_v1(uuid,uuid,text,text,text,uuid,text,numeric,text,jsonb,jsonb) is
  'Root-Ledger report interpretation over one canonical Spend allocation. Inclusion, category, and claim treatment remain separate current-state decisions.';

commit;

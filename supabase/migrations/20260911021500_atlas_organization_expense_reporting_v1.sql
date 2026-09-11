-- Atlas Organization Expense Reporting v1
-- Stacked candidate over Atlas Organization Spend Kernel v1.
-- Organization-specific reporting interpretation; source Spend remains authoritative.

create table atlas.organization_expense_reporting_contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_key text not null check (btrim(contract_key) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  reporting_body_name text not null check (btrim(reporting_body_name) <> ''),
  cadence text not null default 'monthly' check (cadence in ('monthly','quarterly','annual','custom')),
  report_currency text not null check (report_currency ~ '^[A-Z]{3}$'),
  status text not null default 'draft' check (status in ('draft','active','retired')),
  effective_from date not null,
  effective_to date,
  policy_source_ref text,
  policy_source_hash text check (policy_source_hash is null or policy_source_hash ~ '^[0-9a-f]{64}$'),
  output_template_ref text,
  output_template_hash text check (output_template_hash is null or output_template_hash ~ '^[0-9a-f]{64}$'),
  template_config jsonb not null default '{}'::jsonb check (jsonb_typeof(template_config)='object'),
  accounting_handoff_config jsonb not null default '{}'::jsonb check (jsonb_typeof(accounting_handoff_config)='object'),
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  unique (organization_id, contract_key, effective_from),
  unique (id, organization_id)
);

create table atlas.organization_expense_reporting_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  contract_id uuid not null,
  category_key text not null check (btrim(category_key) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  export_label text check (export_label is null or btrim(export_label) <> ''),
  policy_definition text,
  examples jsonb not null default '[]'::jsonb check (jsonb_typeof(examples)='array'),
  evidence_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence_rules)='object'),
  mapping_state text not null default 'confirmed' check (mapping_state in ('confirmed','requires_confirmation','unresolved')),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id,organization_id)
    references atlas.organization_expense_reporting_contracts(id,organization_id)
    on delete cascade,
  unique (contract_id,category_key),
  unique (id,contract_id,organization_id)
);

create table atlas.organization_expense_reporting_periods (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  contract_id uuid not null,
  period_start date not null,
  period_end date not null,
  reporting_identity jsonb not null default '{}'::jsonb check (jsonb_typeof(reporting_identity)='object'),
  state text not null default 'open' check (state in ('open','review','ready','submitted','reopened')),
  submitted_artifact_locator text,
  submitted_artifact_hash text check (submitted_artifact_hash is null or submitted_artifact_hash ~ '^[0-9a-f]{64}$'),
  submitted_at timestamptz,
  submitted_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  opened_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (contract_id,organization_id)
    references atlas.organization_expense_reporting_contracts(id,organization_id)
    on delete restrict,
  check (period_end >= period_start),
  check ((state='submitted' and submitted_at is not null) or state<>'submitted'),
  unique (contract_id,period_start,period_end),
  unique (id,organization_id),
  unique (id,contract_id,organization_id)
);

create table atlas.organization_expense_reporting_rates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  period_id uuid not null,
  rate_key text not null check (btrim(rate_key) <> ''),
  rate_kind text not null check (rate_kind in ('currency_exchange','mileage','distance','other')),
  from_unit text check (from_unit is null or btrim(from_unit) <> ''),
  to_unit text check (to_unit is null or btrim(to_unit) <> ''),
  quote_value numeric check (quote_value is null or quote_value > 0),
  quote_convention text check (quote_convention is null or quote_convention in (
    'source_units_per_one_reporting_unit','reporting_units_per_one_source_unit','canonical_multiplier'
  )),
  conversion_multiplier numeric check (conversion_multiplier is null or conversion_multiplier > 0),
  effective_from date,
  effective_to date,
  source_kind text not null default 'organization_provided' check (source_kind in (
    'contract_provided','organization_provided','external_reference','human_confirmed'
  )),
  source_ref text,
  source_as_of timestamptz,
  confirmed_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  foreign key (period_id,organization_id)
    references atlas.organization_expense_reporting_periods(id,organization_id)
    on delete cascade,
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check (
    (rate_kind='currency_exchange' and from_unit is not null and to_unit is not null and conversion_multiplier is not null)
    or rate_kind<>'currency_exchange'
  ),
  check (source_kind<>'human_confirmed' or (confirmed_by_membership_id is not null and confirmed_at is not null)),
  unique (period_id,rate_key,effective_from),
  unique (id,period_id,organization_id)
);

create table atlas.organization_expense_reporting_fact_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  contract_id uuid not null,
  period_id uuid not null,
  fact_kind text not null check (fact_kind in ('expense','travel','impact_activity')),
  source_authority text not null check (btrim(source_authority) <> ''),
  source_ref text not null check (btrim(source_ref) <> ''),
  category_id uuid,
  inclusion_state text not null default 'unresolved' check (inclusion_state in ('unresolved','suggested','included','excluded')),
  classification_state text not null default 'unclassified' check (classification_state in ('unclassified','suggested','confirmed','not_applicable')),
  classification_confidence numeric check (classification_confidence is null or (classification_confidence>=0 and classification_confidence<=1)),
  claim_treatment text not null default 'unresolved' check (claim_treatment in (
    'unresolved','reimbursement','organization_paid','documentation_only','donated_non_reimbursed','not_applicable'
  )),
  reporting_purpose text,
  report_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(report_fields)='object'),
  confirmed_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id,contract_id,organization_id)
    references atlas.organization_expense_reporting_periods(id,contract_id,organization_id)
    on delete cascade,
  foreign key (category_id,contract_id,organization_id)
    references atlas.organization_expense_reporting_categories(id,contract_id,organization_id)
    on delete restrict,
  check (fact_kind='expense' or category_id is null),
  check (reporting_purpose is null or btrim(reporting_purpose) <> ''),
  unique (contract_id,fact_kind,source_authority,source_ref),
  unique (id,period_id,organization_id)
);

create table atlas.organization_expense_reporting_fact_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  fact_link_id uuid not null,
  period_id uuid not null,
  event_kind text not null check (event_kind in ('admitted','interpretation_updated')),
  actor_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  source_kind text not null check (btrim(source_kind) <> ''),
  source_key text not null check (btrim(source_key) <> ''),
  before_state jsonb,
  after_state jsonb not null check (jsonb_typeof(after_state)='object'),
  created_at timestamptz not null default now(),
  foreign key (fact_link_id,period_id,organization_id)
    references atlas.organization_expense_reporting_fact_links(id,period_id,organization_id)
    on delete cascade,
  check (before_state is null or jsonb_typeof(before_state)='object'),
  unique (organization_id,source_kind,source_key)
);

create table atlas.organization_expense_reporting_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  period_id uuid not null,
  fact_link_id uuid,
  exception_code text not null check (btrim(exception_code) <> ''),
  severity text not null default 'blocking' check (severity in ('blocking','warning')),
  question text not null check (btrim(question) <> ''),
  state text not null default 'open' check (state in ('open','resolved','waived')),
  resolution jsonb,
  resolution_note text,
  resolved_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  resolved_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (period_id,organization_id)
    references atlas.organization_expense_reporting_periods(id,organization_id)
    on delete cascade,
  foreign key (fact_link_id,period_id,organization_id)
    references atlas.organization_expense_reporting_fact_links(id,period_id,organization_id)
    on delete cascade,
  check (resolution is null or jsonb_typeof(resolution)='object'),
  check (
    (state='open' and resolved_at is null and resolved_by_membership_id is null)
    or (state in ('resolved','waived') and resolved_at is not null and resolved_by_membership_id is not null)
  )
);

create unique index organization_expense_reporting_open_exception_uq
  on atlas.organization_expense_reporting_exceptions(
    period_id,
    coalesce(fact_link_id,'00000000-0000-0000-0000-000000000000'::uuid),
    exception_code
  ) where state='open';

create index organization_expense_reporting_contracts_org_status_idx
  on atlas.organization_expense_reporting_contracts(organization_id,status,effective_from desc);
create index organization_expense_reporting_categories_contract_order_idx
  on atlas.organization_expense_reporting_categories(contract_id,is_active,sort_order,canonical_label);
create index organization_expense_reporting_periods_org_state_idx
  on atlas.organization_expense_reporting_periods(organization_id,state,period_start desc);
create index organization_expense_reporting_fact_links_period_state_idx
  on atlas.organization_expense_reporting_fact_links(period_id,fact_kind,inclusion_state,classification_state);
create index organization_expense_reporting_exceptions_period_state_idx
  on atlas.organization_expense_reporting_exceptions(period_id,state,severity,created_at);

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

create or replace function atlas.organization_expense_reporting_assert_membership_v1(
  p_organization_id uuid,
  p_membership_id uuid,
  p_label text
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_membership_id is null or not exists(
    select 1 from atlas.organization_memberships om
    where om.id=p_membership_id and om.organization_id=p_organization_id and om.active
  ) then
    raise exception '% membership must be active in the reporting organization.',coalesce(nullif(btrim(p_label),''),'Referenced') using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.organization_expense_reporting_assert_unit_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units ou
    where ou.id=p_organization_unit_id and ou.organization_id=p_organization_id
  ) then
    raise exception 'Reporting organization unit does not belong to organization.' using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.guard_organization_expense_reporting_contract_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_unit_v1(new.organization_id,new.organization_unit_id);
  if new.created_by_membership_id is not null then
    perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.created_by_membership_id,'Contract creator');
  end if;
  new.contract_key:=lower(btrim(new.contract_key));
  new.report_currency:=upper(btrim(new.report_currency));
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_contract_v1
before insert or update on atlas.organization_expense_reporting_contracts
for each row execute function atlas.guard_organization_expense_reporting_contract_v1();

create or replace function atlas.guard_organization_expense_reporting_period_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.organization_expense_reporting_assert_unit_v1(new.organization_id,new.organization_unit_id);
  if new.opened_by_membership_id is not null then
    perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.opened_by_membership_id,'Period opener');
  end if;
  if new.submitted_by_membership_id is not null then
    perform atlas.organization_expense_reporting_assert_membership_v1(new.organization_id,new.submitted_by_membership_id,'Period submitter');
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_organization_expense_reporting_period_v1
before insert or update on atlas.organization_expense_reporting_periods
for each row execute function atlas.guard_organization_expense_reporting_period_v1();

create or replace function atlas.organization_expense_reporting_fact_snapshot_v1(p_fact_link_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'id',f.id,
    'organizationId',f.organization_id,
    'contractId',f.contract_id,
    'periodId',f.period_id,
    'factKind',f.fact_kind,
    'sourceAuthority',f.source_authority,
    'sourceRef',f.source_ref,
    'categoryId',f.category_id,
    'inclusionState',f.inclusion_state,
    'classificationState',f.classification_state,
    'classificationConfidence',f.classification_confidence,
    'claimTreatment',f.claim_treatment,
    'reportingPurpose',f.reporting_purpose,
    'reportFields',f.report_fields,
    'confirmedByMembershipId',f.confirmed_by_membership_id,
    'confirmedAt',f.confirmed_at
  ) from atlas.organization_expense_reporting_fact_links f where f.id=p_fact_link_id;
$function$;

create or replace function atlas.organization_expense_reporting_fact_authorized_self_v1(
  p_fact_link_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_link atlas.organization_expense_reporting_fact_links%rowtype;
  v_membership uuid;
  v_alloc atlas.organization_spend_allocations%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
begin
  if auth.uid() is null then return false; end if;
  select * into v_link from atlas.organization_expense_reporting_fact_links where id=p_fact_link_id;
  if v_link.id is null then return false; end if;
  v_membership:=atlas.current_organization_membership_v1(v_link.organization_id);
  if v_membership is null then return false; end if;
  if atlas.is_organization_owner(v_link.organization_id) then return true; end if;
  if v_link.fact_kind<>'expense' or v_link.source_authority<>'atlas.organization_spend_allocations' then return false; end if;
  begin
    select * into v_alloc from atlas.organization_spend_allocations where id=v_link.source_ref::uuid and allocation_state='active';
  exception when invalid_text_representation then
    return false;
  end;
  if v_alloc.id is null then return false; end if;
  select * into v_spend from atlas.organization_spend_occurrences where id=v_alloc.spend_occurrence_id;
  return v_spend.recorded_by_membership_id=v_membership or v_spend.payer_membership_id=v_membership;
end;
$function$;

create or replace function atlas.organization_expense_reporting_rebuild_expense_exceptions_internal_v1(p_fact_link_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_link atlas.organization_expense_reporting_fact_links%rowtype;
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
  v_category atlas.organization_expense_reporting_categories%rowtype;
  v_alloc atlas.organization_spend_allocations%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_purpose text;
  v_rate_count integer;
  v_requires_receipt boolean:=false;
  v_has_receipt boolean:=false;
  v_factura_field_key text;
begin
  select * into v_link from atlas.organization_expense_reporting_fact_links where id=p_fact_link_id;
  if v_link.id is null or v_link.fact_kind<>'expense' or v_link.source_authority<>'atlas.organization_spend_allocations' then
    raise exception 'Spend-backed expense fact link required.' using errcode='22023';
  end if;
  select * into v_period from atlas.organization_expense_reporting_periods where id=v_link.period_id;
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id;
  begin
    select * into v_alloc from atlas.organization_spend_allocations where id=v_link.source_ref::uuid and allocation_state='active';
  exception when invalid_text_representation then
    raise exception 'Expense source reference is not a Spend allocation UUID.' using errcode='22023';
  end;
  if v_alloc.id is null then raise exception 'Expense source Spend allocation is no longer active.' using errcode='55000'; end if;
  select * into v_spend from atlas.organization_spend_occurrences where id=v_alloc.spend_occurrence_id and truth_state<>'voided';
  if v_spend.id is null then raise exception 'Expense source Spend occurrence is unavailable.' using errcode='55000'; end if;

  v_purpose:=coalesce(nullif(btrim(v_link.reporting_purpose),''),nullif(btrim(v_alloc.operational_purpose),''));

  delete from atlas.organization_expense_reporting_exceptions
  where fact_link_id=v_link.id and state='open';

  if v_link.inclusion_state not in ('included','excluded') then
    insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
    values(v_link.organization_id,v_link.period_id,v_link.id,'reporting_eligibility_unresolved','blocking','Should this expense be included in this report?');
  end if;

  if v_link.inclusion_state='included' then
    if v_purpose is null then
      insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
      values(v_link.organization_id,v_link.period_id,v_link.id,'purpose_missing','blocking','What was this expense for?');
    end if;

    if v_link.category_id is null or v_link.classification_state<>'confirmed' then
      insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
      values(v_link.organization_id,v_link.period_id,v_link.id,'expense_category_unresolved','blocking','Which reporting category should this expense use?');
    else
      select * into v_category from atlas.organization_expense_reporting_categories where id=v_link.category_id;
    end if;

    if v_spend.funding_kind='organization_member' and v_link.claim_treatment='unresolved' then
      insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
      values(v_link.organization_id,v_link.period_id,v_link.id,'reimbursement_treatment_unresolved','blocking','How should this member-funded expense be treated for this report?');
    end if;

    if v_spend.currency<>v_contract.report_currency then
      select count(*) into v_rate_count
      from atlas.organization_expense_reporting_rates r
      where r.period_id=v_period.id and r.rate_kind='currency_exchange'
        and upper(r.from_unit)=v_spend.currency and upper(r.to_unit)=v_contract.report_currency
        and coalesce(r.effective_from,v_period.period_start)<=v_spend.occurred_on
        and coalesce(r.effective_to,v_period.period_end)>=v_spend.occurred_on
        and r.conversion_multiplier is not null;
      if v_rate_count=0 then
        insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
        values(v_link.organization_id,v_link.period_id,v_link.id,'exchange_rate_missing','blocking','What exchange rate applies to this expense?');
      elsif v_rate_count>1 then
        insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
        values(v_link.organization_id,v_link.period_id,v_link.id,'exchange_rate_ambiguous','blocking','More than one accepted exchange rate applies to this expense. Which one governs?');
      end if;
    end if;

    if v_category.id is not null then
      v_requires_receipt:=coalesce((v_category.evidence_rules->>'requiresReceipt')::boolean,false);
      if v_category.evidence_rules ? 'receiptConditionField' then
        v_requires_receipt:=v_requires_receipt and coalesce((v_link.report_fields->>(v_category.evidence_rules->>'receiptConditionField'))::boolean,false);
      end if;
      if v_requires_receipt then
        select exists(
          select 1 from atlas.organization_spend_evidence_links el
          where el.spend_occurrence_id=v_spend.id
            and (el.spend_allocation_id is null or el.spend_allocation_id=v_alloc.id)
            and el.relation_kind in ('receipt','factura','invoice','supporting')
        ) into v_has_receipt;
        if not v_has_receipt then
          insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
          values(v_link.organization_id,v_link.period_id,v_link.id,'receipt_required_missing','blocking','A required receipt or supporting document is missing.');
        end if;
      end if;
    end if;

    v_factura_field_key:=nullif(v_contract.template_config#>>'{expense,mexicanFacturaFieldKey}','');
    if v_factura_field_key is not null and not (v_link.report_fields ? v_factura_field_key) then
      insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
      values(v_link.organization_id,v_link.period_id,v_link.id,'template_field_state_missing','warning','A configured report field still needs a value.');
    end if;
  end if;

  return jsonb_build_object(
    'factLinkId',v_link.id,
    'openBlocking',(select count(*) from atlas.organization_expense_reporting_exceptions e where e.fact_link_id=v_link.id and e.state='open' and e.severity='blocking'),
    'openWarnings',(select count(*) from atlas.organization_expense_reporting_exceptions e where e.fact_link_id=v_link.id and e.state='open' and e.severity='warning')
  );
end;
$function$;

create or replace function atlas.admit_organization_spend_to_expense_report_self_api_v1(
  p_period_id uuid,
  p_spend_allocation_id uuid,
  p_client_event_key text,
  p_inclusion_state text default 'unresolved',
  p_claim_treatment text default 'unresolved',
  p_category_id uuid default null,
  p_classification_state text default 'unclassified',
  p_classification_confidence numeric default null,
  p_reporting_purpose text default null,
  p_report_fields jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_contract atlas.organization_expense_reporting_contracts%rowtype;
  v_alloc atlas.organization_spend_allocations%rowtype;
  v_spend atlas.organization_spend_occurrences%rowtype;
  v_membership uuid;
  v_link atlas.organization_expense_reporting_fact_links%rowtype;
  v_event atlas.organization_expense_reporting_fact_events%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_confirmed boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_client_event_key,'')),'') is null then raise exception 'Client event key is required.' using errcode='22023'; end if;
  if p_inclusion_state not in ('unresolved','suggested','included','excluded') then raise exception 'Unsupported inclusion state.' using errcode='22023'; end if;
  if p_classification_state not in ('unclassified','suggested','confirmed','not_applicable') then raise exception 'Unsupported classification state.' using errcode='22023'; end if;
  if p_claim_treatment not in ('unresolved','reimbursement','organization_paid','documentation_only','donated_non_reimbursed','not_applicable') then raise exception 'Unsupported claim treatment.' using errcode='22023'; end if;

  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then raise exception 'Reporting period not found.' using errcode='P0002'; end if;
  if v_period.state not in ('open','review','reopened') then raise exception 'Reporting period is not open for expense interpretation.' using errcode='55000'; end if;
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);
  if v_membership is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id and status='active';
  if v_contract.id is null then raise exception 'Active reporting contract required.' using errcode='55000'; end if;
  select * into v_alloc from atlas.organization_spend_allocations where id=p_spend_allocation_id and allocation_state='active';
  if v_alloc.id is null then raise exception 'Active Spend allocation required.' using errcode='P0002'; end if;
  select * into v_spend from atlas.organization_spend_occurrences where id=v_alloc.spend_occurrence_id and truth_state<>'voided';
  if v_spend.id is null then raise exception 'Active Spend occurrence required.' using errcode='P0002'; end if;
  if v_alloc.organization_id<>v_period.organization_id or v_spend.organization_id<>v_period.organization_id then raise exception 'Spend belongs to another organization.' using errcode='23503'; end if;
  if v_spend.occurred_on not between v_period.period_start and v_period.period_end then raise exception 'Spend date is outside the reporting period.' using errcode='23514'; end if;
  if v_period.organization_unit_id is not null and coalesce(v_alloc.organization_unit_id,v_spend.organization_unit_id) is distinct from v_period.organization_unit_id then raise exception 'Spend is outside the reporting unit scope.' using errcode='23514'; end if;
  if not atlas.is_organization_owner(v_period.organization_id)
     and v_spend.recorded_by_membership_id<>v_membership
     and v_spend.payer_membership_id is distinct from v_membership then
    raise exception 'A member may interpret only Spend they recorded or personally funded.' using errcode='42501';
  end if;
  if p_category_id is not null and not exists(
    select 1 from atlas.organization_expense_reporting_categories c
    where c.id=p_category_id and c.contract_id=v_contract.id and c.organization_id=v_period.organization_id and c.is_active
  ) then raise exception 'Reporting category does not belong to the active contract.' using errcode='23503'; end if;

  select * into v_event from atlas.organization_expense_reporting_fact_events e
  where e.organization_id=v_period.organization_id and e.source_kind='report_interpretation' and e.source_key=btrim(p_client_event_key);
  if v_event.id is not null then
    return jsonb_build_object('contractVersion','admit_organization_spend_to_expense_report_self_api_v1','state','unchanged','factLinkId',v_event.fact_link_id,'eventId',v_event.id);
  end if;

  select * into v_link from atlas.organization_expense_reporting_fact_links f
  where f.contract_id=v_contract.id and f.fact_kind='expense'
    and f.source_authority='atlas.organization_spend_allocations' and f.source_ref=p_spend_allocation_id::text
  for update;

  v_confirmed:=p_inclusion_state in ('included','excluded') or p_classification_state='confirmed' or p_claim_treatment<>'unresolved';

  if v_link.id is null then
    insert into atlas.organization_expense_reporting_fact_links(
      organization_id,contract_id,period_id,fact_kind,source_authority,source_ref,category_id,
      inclusion_state,classification_state,classification_confidence,claim_treatment,reporting_purpose,
      report_fields,confirmed_by_membership_id,confirmed_at
    ) values(
      v_period.organization_id,v_contract.id,v_period.id,'expense','atlas.organization_spend_allocations',p_spend_allocation_id::text,p_category_id,
      p_inclusion_state,p_classification_state,p_classification_confidence,p_claim_treatment,nullif(btrim(coalesce(p_reporting_purpose,'')),''),
      coalesce(p_report_fields,'{}'::jsonb),case when v_confirmed then v_membership else null end,case when v_confirmed then now() else null end
    ) returning * into v_link;
    v_before:=null;
  else
    if v_link.period_id<>v_period.id then raise exception 'Spend allocation is already bound to another period under this contract.' using errcode='23514'; end if;
    if not atlas.organization_expense_reporting_fact_authorized_self_v1(v_link.id) then raise exception 'Expense interpretation authority required.' using errcode='42501'; end if;
    v_before:=atlas.organization_expense_reporting_fact_snapshot_v1(v_link.id);
    update atlas.organization_expense_reporting_fact_links f
    set category_id=p_category_id,
        inclusion_state=p_inclusion_state,
        classification_state=p_classification_state,
        classification_confidence=p_classification_confidence,
        claim_treatment=p_claim_treatment,
        reporting_purpose=nullif(btrim(coalesce(p_reporting_purpose,'')),''),
        report_fields=coalesce(p_report_fields,'{}'::jsonb),
        confirmed_by_membership_id=case when v_confirmed then v_membership else null end,
        confirmed_at=case when v_confirmed then now() else null end,
        updated_at=now()
    where f.id=v_link.id returning * into v_link;
  end if;

  v_after:=atlas.organization_expense_reporting_fact_snapshot_v1(v_link.id);
  insert into atlas.organization_expense_reporting_fact_events(
    organization_id,fact_link_id,period_id,event_kind,actor_membership_id,source_kind,source_key,before_state,after_state
  ) values(
    v_period.organization_id,v_link.id,v_period.id,case when v_before is null then 'admitted' else 'interpretation_updated' end,
    v_membership,'report_interpretation',btrim(p_client_event_key),v_before,v_after
  ) returning * into v_event;

  perform atlas.organization_expense_reporting_rebuild_expense_exceptions_internal_v1(v_link.id);

  return jsonb_build_object(
    'contractVersion','admit_organization_spend_to_expense_report_self_api_v1',
    'state',case when v_before is null then 'admitted' else 'updated' end,
    'factLinkId',v_link.id,'eventId',v_event.id,'periodId',v_period.id,
    'spendAllocationId',p_spend_allocation_id,
    'openBlocking',(select count(*) from atlas.organization_expense_reporting_exceptions e where e.fact_link_id=v_link.id and e.state='open' and e.severity='blocking'),
    'openWarnings',(select count(*) from atlas.organization_expense_reporting_exceptions e where e.fact_link_id=v_link.id and e.state='open' and e.severity='warning')
  );
end;
$function$;

create or replace view atlas.organization_expense_reporting_expense_lines_v1 as
select
  f.id fact_link_id,f.organization_id,f.period_id,f.category_id,c.category_key,c.canonical_label,c.export_label,c.sort_order,
  s.occurred_on,s.payee_label,a.id spend_allocation_id,a.allocated_amount source_amount,s.currency source_currency,
  con.report_currency,coalesce(nullif(btrim(f.reporting_purpose),''),a.operational_purpose) purpose,f.report_fields,
  rr.id rate_id,rr.quote_value,rr.quote_convention,rr.conversion_multiplier,
  case when s.currency=con.report_currency then a.allocated_amount
       when rr.id is not null then a.allocated_amount*rr.conversion_multiplier
       else null end report_amount,
  f.classification_state,f.claim_treatment
from atlas.organization_expense_reporting_fact_links f
join atlas.organization_expense_reporting_periods p on p.id=f.period_id
join atlas.organization_expense_reporting_contracts con on con.id=p.contract_id
join atlas.organization_spend_allocations a on f.source_authority='atlas.organization_spend_allocations' and a.id=f.source_ref::uuid and a.allocation_state='active'
join atlas.organization_spend_occurrences s on s.id=a.spend_occurrence_id and s.truth_state<>'voided'
left join atlas.organization_expense_reporting_categories c on c.id=f.category_id
left join lateral(
  select r.* from atlas.organization_expense_reporting_rates r
  where r.period_id=p.id and r.rate_kind='currency_exchange'
    and upper(r.from_unit)=s.currency and upper(r.to_unit)=con.report_currency
    and coalesce(r.effective_from,p.period_start)<=s.occurred_on
    and coalesce(r.effective_to,p.period_end)>=s.occurred_on
    and r.conversion_multiplier is not null
  order by r.effective_from desc nulls last,r.created_at desc,r.id desc limit 1
) rr on true
where f.fact_kind='expense' and f.inclusion_state='included';

create or replace function atlas.organization_expense_reporting_period_self_api_v1(p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_period atlas.organization_expense_reporting_periods%rowtype;
  v_membership uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then return null; end if;
  v_membership:=atlas.current_organization_membership_v1(v_period.organization_id);
  if v_membership is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

  return jsonb_build_object(
    'schemaVersion','atlas_organization_expense_reporting_period_v1',
    'period',jsonb_build_object('id',v_period.id,'organizationId',v_period.organization_id,'organizationUnitId',v_period.organization_unit_id,'contractId',v_period.contract_id,'periodStart',v_period.period_start,'periodEnd',v_period.period_end,'state',v_period.state,'reportingIdentity',v_period.reporting_identity),
    'expenseLines',coalesce((
      select jsonb_agg(jsonb_build_object(
        'factLinkId',l.fact_link_id,'categoryId',l.category_id,'categoryKey',l.category_key,'categoryLabel',l.canonical_label,'exportLabel',l.export_label,
        'occurredOn',l.occurred_on,'payeeLabel',l.payee_label,'spendAllocationId',l.spend_allocation_id,'sourceAmount',l.source_amount,'sourceCurrency',l.source_currency,
        'reportCurrency',l.report_currency,'purpose',l.purpose,'reportFields',l.report_fields,'quoteValue',l.quote_value,'quoteConvention',l.quote_convention,
        'conversionMultiplier',l.conversion_multiplier,'reportAmount',l.report_amount,'classificationState',l.classification_state,'claimTreatment',l.claim_treatment
      ) order by l.sort_order,l.canonical_label,l.occurred_on,l.fact_link_id)
      from atlas.organization_expense_reporting_expense_lines_v1 l
      join atlas.organization_expense_reporting_fact_links f on f.id=l.fact_link_id
      where l.period_id=v_period.id and (atlas.is_organization_owner(v_period.organization_id) or atlas.organization_expense_reporting_fact_authorized_self_v1(f.id))
    ),'[]'::jsonb),
    'exceptions',coalesce((
      select jsonb_agg(jsonb_build_object('id',e.id,'factLinkId',e.fact_link_id,'code',e.exception_code,'severity',e.severity,'question',e.question,'state',e.state) order by case e.severity when 'blocking' then 0 else 1 end,e.created_at,e.id)
      from atlas.organization_expense_reporting_exceptions e
      where e.period_id=v_period.id and (e.fact_link_id is null or atlas.is_organization_owner(v_period.organization_id) or atlas.organization_expense_reporting_fact_authorized_self_v1(e.fact_link_id))
    ),'[]'::jsonb)
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
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if v_period.id is null then return null; end if;
  if atlas.current_organization_membership_v1(v_period.organization_id) is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  if not atlas.is_organization_owner(v_period.organization_id) then raise exception 'Owner authority required for whole-period accounting handoff.' using errcode='42501'; end if;
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id;

  return jsonb_build_object(
    'schemaVersion','atlas_organization_expense_reporting_accounting_handoff_v1',
    'periodId',v_period.id,
    'destination',v_contract.accounting_handoff_config,
    'detailGroups',coalesce((
      select jsonb_agg(jsonb_build_object(
        'categoryId',g.category_id,'categoryKey',g.category_key,'categoryLabel',g.canonical_label,'exportLabel',g.export_label,'subtotal',g.subtotal,'detailCount',g.detail_count,'factLinkIds',g.fact_link_ids
      ) order by g.sort_order,g.canonical_label)
      from(
        select l.category_id,l.category_key,l.canonical_label,l.export_label,min(l.sort_order) sort_order,
               sum(l.report_amount) subtotal,count(*) detail_count,jsonb_agg(l.fact_link_id order by l.occurred_on,l.fact_link_id) fact_link_ids
        from atlas.organization_expense_reporting_expense_lines_v1 l
        where l.period_id=v_period.id and l.classification_state='confirmed' and l.report_amount is not null
        group by l.category_id,l.category_key,l.canonical_label,l.export_label
      ) g
    ),'[]'::jsonb),
    'reportExpenseTotal',(select coalesce(sum(l.report_amount),0) from atlas.organization_expense_reporting_expense_lines_v1 l where l.period_id=v_period.id and l.classification_state='confirmed' and l.report_amount is not null),
    'blockingExceptionCount',(select count(*) from atlas.organization_expense_reporting_exceptions e where e.period_id=v_period.id and e.state='open' and e.severity='blocking')
  );
end;
$function$;

alter table atlas.organization_expense_reporting_contracts enable row level security;
alter table atlas.organization_expense_reporting_categories enable row level security;
alter table atlas.organization_expense_reporting_periods enable row level security;
alter table atlas.organization_expense_reporting_rates enable row level security;
alter table atlas.organization_expense_reporting_fact_links enable row level security;
alter table atlas.organization_expense_reporting_fact_events enable row level security;
alter table atlas.organization_expense_reporting_exceptions enable row level security;

revoke all on table atlas.organization_expense_reporting_contracts from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_categories from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_periods from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_rates from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_fact_links from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_fact_events from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_exceptions from public,anon,authenticated;
revoke all on table atlas.organization_expense_reporting_expense_lines_v1 from public,anon,authenticated;

revoke all on function atlas.organization_expense_reporting_normalize_rate_v1(numeric,text) from public,anon,authenticated;
revoke all on function atlas.organization_expense_reporting_assert_membership_v1(uuid,uuid,text) from public,anon,authenticated;
revoke all on function atlas.organization_expense_reporting_assert_unit_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.organization_expense_reporting_fact_snapshot_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.organization_expense_reporting_fact_authorized_self_v1(uuid) from public,anon;
revoke all on function atlas.organization_expense_reporting_rebuild_expense_exceptions_internal_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.admit_organization_spend_to_expense_report_self_api_v1(uuid,uuid,text,text,text,uuid,text,numeric,text,jsonb) from public,anon;
revoke all on function atlas.organization_expense_reporting_period_self_api_v1(uuid) from public,anon;
revoke all on function atlas.organization_expense_reporting_accounting_handoff_self_api_v1(uuid) from public,anon;

grant execute on function atlas.organization_expense_reporting_fact_authorized_self_v1(uuid) to authenticated;
grant execute on function atlas.admit_organization_spend_to_expense_report_self_api_v1(uuid,uuid,text,text,text,uuid,text,numeric,text,jsonb) to authenticated;
grant execute on function atlas.organization_expense_reporting_period_self_api_v1(uuid) to authenticated;
grant execute on function atlas.organization_expense_reporting_accounting_handoff_self_api_v1(uuid) to authenticated;

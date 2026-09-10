BEGIN;

-- Atlas Expense Report Admission v1 proof.
-- Development proof only. NOT a canonical migration.
-- Ends in ROLLBACK.

alter table atlas.organization_expense_reporting_fact_links
  add column if not exists inclusion_state text not null default 'unresolved'
    check (inclusion_state in ('unresolved','suggested','included','excluded')),
  add column if not exists claim_treatment text not null default 'unresolved'
    check (claim_treatment in ('unresolved','reimbursement','organization_paid','documentation_only','donated_non_reimbursed')),
  add column if not exists confirmed_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  add column if not exists confirmed_at timestamptz,
  add column if not exists report_fields jsonb not null default '{}'::jsonb;

alter table atlas.organization_expense_reporting_rates
  add column if not exists quote_value numeric,
  add column if not exists quote_convention text
    check (quote_convention is null or quote_convention in ('source_units_per_one_reporting_unit','reporting_units_per_one_source_unit','canonical_multiplier')),
  add column if not exists conversion_multiplier numeric check (conversion_multiplier is null or conversion_multiplier > 0);

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
    when p_quote_value is null or p_quote_value <= 0 then null
    when p_quote_convention='source_units_per_one_reporting_unit' then 1 / p_quote_value
    when p_quote_convention in ('reporting_units_per_one_source_unit','canonical_multiplier') then p_quote_value
    else null
  end;
$function$;

create or replace function atlas.organization_expense_reporting_rebuild_expense_exceptions_v1(
  p_fact_link_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
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
  v_is_accommodation boolean;
  v_has_receipt boolean;
begin
  select * into v_link from atlas.organization_expense_reporting_fact_links where id=p_fact_link_id;
  if not found or v_link.fact_kind<>'expense' then
    raise exception 'Expense fact link required.' using errcode='22023';
  end if;

  if not atlas.is_organization_member(v_link.organization_id) then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;

  select * into v_period from atlas.organization_expense_reporting_periods where id=v_link.period_id;
  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id;

  select * into v_alloc from atlas.organization_spend_allocations where id=v_link.source_ref::uuid;
  select * into v_spend from atlas.organization_spend_occurrences where id=v_alloc.spend_occurrence_id;

  v_purpose := coalesce(nullif(btrim(v_link.reporting_purpose),''), nullif(btrim(v_alloc.operational_purpose),''));

  delete from atlas.organization_expense_reporting_exceptions
  where fact_link_id=p_fact_link_id and state='open'
    and exception_code in (
      'reporting_eligibility_unresolved','purpose_missing','expense_category_unresolved',
      'reimbursement_treatment_unresolved','exchange_rate_missing','exchange_rate_ambiguous',
      'receipt_required_missing','mexican_factura_state_missing'
    );

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

    if v_spend.currency <> v_contract.base_currency then
      select count(*) into v_rate_count
      from atlas.organization_expense_reporting_rates r
      where r.period_id=v_period.id
        and r.rate_kind='currency_exchange'
        and r.from_unit=v_spend.currency
        and r.to_unit=v_contract.base_currency
        and coalesce(r.effective_from,v_period.period_start) <= v_spend.occurred_on
        and coalesce(r.effective_to,v_period.period_end) >= v_spend.occurred_on
        and r.conversion_multiplier is not null;

      if v_rate_count=0 then
        insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
        values(v_link.organization_id,v_link.period_id,v_link.id,'exchange_rate_missing','blocking','What exchange rate applies to this expense?');
      elsif v_rate_count>1 then
        insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
        values(v_link.organization_id,v_link.period_id,v_link.id,'exchange_rate_ambiguous','blocking','More than one exchange rate applies to this expense. Which one governs?');
      end if;
    end if;

    v_is_accommodation := coalesce((v_link.report_fields->>'isAccommodation')::boolean,false);
    if v_category.category_key='hospitality_lodging' and v_is_accommodation then
      select exists(
        select 1 from atlas.organization_spend_evidence_links el
        where el.spend_occurrence_id=v_spend.id
          and (el.spend_allocation_id is null or el.spend_allocation_id=v_alloc.id)
          and el.relation_kind in ('receipt','factura','invoice','supporting')
      ) into v_has_receipt;
      if not v_has_receipt then
        insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
        values(v_link.organization_id,v_link.period_id,v_link.id,'receipt_required_missing','blocking','A receipt is required for this accommodation expense.');
      end if;
    end if;

    if not (v_link.report_fields ? 'mexicanFactura') then
      insert into atlas.organization_expense_reporting_exceptions(organization_id,period_id,fact_link_id,exception_code,severity,question)
      values(v_link.organization_id,v_link.period_id,v_link.id,'mexican_factura_state_missing','warning','Mexican factura state is missing for the workbook field.');
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','organization_expense_reporting_rebuild_expense_exceptions_v1',
    'factLinkId',v_link.id,
    'openBlocking',(
      select count(*) from atlas.organization_expense_reporting_exceptions e
      where e.fact_link_id=v_link.id and e.state='open' and e.severity='blocking'
    ),
    'openWarnings',(
      select count(*) from atlas.organization_expense_reporting_exceptions e
      where e.fact_link_id=v_link.id and e.state='open' and e.severity='warning'
    )
  );
end;
$function$;

create or replace function atlas.admit_organization_spend_to_expense_report_api_v1(
  p_period_id uuid,
  p_spend_allocation_id uuid,
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
  v_confirmed boolean;
begin
  select * into v_period from atlas.organization_expense_reporting_periods where id=p_period_id;
  if not found then raise exception 'Reporting period not found.' using errcode='23503'; end if;
  if v_period.state not in ('open','review','reopened') then
    raise exception 'Reporting period is not open for admission.' using errcode='23514';
  end if;

  v_membership := atlas.current_organization_membership_v1(v_period.organization_id);
  if v_membership is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

  select * into v_contract from atlas.organization_expense_reporting_contracts where id=v_period.contract_id;
  select * into v_alloc from atlas.organization_spend_allocations where id=p_spend_allocation_id and allocation_state='active';
  if not found then raise exception 'Active spend allocation not found.' using errcode='23503'; end if;
  select * into v_spend from atlas.organization_spend_occurrences where id=v_alloc.spend_occurrence_id and truth_state<>'voided';
  if not found then raise exception 'Spend occurrence not available.' using errcode='23503'; end if;

  if v_alloc.organization_id<>v_period.organization_id or v_spend.organization_id<>v_period.organization_id then
    raise exception 'Spend allocation belongs to a different organization.' using errcode='23503';
  end if;
  if v_spend.occurred_on<v_period.period_start or v_spend.occurred_on>v_period.period_end then
    raise exception 'Spend date falls outside reporting period.' using errcode='23514';
  end if;
  if v_period.organization_unit_id is not null and coalesce(v_alloc.organization_unit_id,v_spend.organization_unit_id) is distinct from v_period.organization_unit_id then
    raise exception 'Spend allocation is outside reporting unit scope.' using errcode='23514';
  end if;
  if p_category_id is not null and not exists(
    select 1 from atlas.organization_expense_reporting_categories c
    where c.id=p_category_id and c.contract_id=v_contract.id and c.organization_id=v_period.organization_id
  ) then
    raise exception 'Reporting category does not belong to contract.' using errcode='23503';
  end if;

  v_confirmed := p_inclusion_state in ('included','excluded') or p_classification_state='confirmed';

  select * into v_link
  from atlas.organization_expense_reporting_fact_links f
  where f.contract_id=v_contract.id and f.fact_kind='expense'
    and f.source_authority='atlas.organization_spend_allocations'
    and f.source_ref=p_spend_allocation_id::text
  for update;

  if v_link.id is null then
    insert into atlas.organization_expense_reporting_fact_links(
      organization_id,contract_id,period_id,fact_kind,source_authority,source_ref,
      category_id,classification_state,classification_confidence,reporting_purpose,
      inclusion_state,claim_treatment,confirmed_by_membership_id,confirmed_at,report_fields
    ) values(
      v_period.organization_id,v_contract.id,v_period.id,'expense','atlas.organization_spend_allocations',p_spend_allocation_id::text,
      p_category_id,p_classification_state,p_classification_confidence,nullif(btrim(coalesce(p_reporting_purpose,'')),''),
      p_inclusion_state,p_claim_treatment,case when v_confirmed then v_membership else null end,
      case when v_confirmed then now() else null end,coalesce(p_report_fields,'{}'::jsonb)
    ) returning * into v_link;
  else
    if v_link.period_id<>v_period.id then
      raise exception 'Spend allocation already admitted under this contract to another period.' using errcode='23514';
    end if;
    update atlas.organization_expense_reporting_fact_links
    set category_id=coalesce(p_category_id,category_id),
        classification_state=p_classification_state,
        classification_confidence=p_classification_confidence,
        reporting_purpose=coalesce(nullif(btrim(coalesce(p_reporting_purpose,'')),''),reporting_purpose),
        inclusion_state=p_inclusion_state,
        claim_treatment=p_claim_treatment,
        confirmed_by_membership_id=case when v_confirmed then v_membership else confirmed_by_membership_id end,
        confirmed_at=case when v_confirmed then now() else confirmed_at end,
        report_fields=coalesce(report_fields,'{}'::jsonb) || coalesce(p_report_fields,'{}'::jsonb),
        updated_at=now()
    where id=v_link.id
    returning * into v_link;
  end if;

  perform atlas.organization_expense_reporting_rebuild_expense_exceptions_v1(v_link.id);

  return jsonb_build_object(
    'contractVersion','admit_organization_spend_to_expense_report_api_v1',
    'factLinkId',v_link.id,
    'periodId',v_period.id,
    'spendAllocationId',p_spend_allocation_id,
    'inclusionState',v_link.inclusion_state,
    'classificationState',v_link.classification_state,
    'claimTreatment',v_link.claim_treatment
  );
end;
$function$;

create or replace view atlas.organization_expense_reporting_expense_lines_v1 as
select
  f.id as fact_link_id,
  f.organization_id,
  f.period_id,
  f.category_id,
  c.category_key,
  c.canonical_label,
  c.export_label,
  s.occurred_on,
  a.id as spend_allocation_id,
  a.allocated_amount as source_amount,
  s.currency as source_currency,
  con.base_currency as report_currency,
  coalesce(nullif(btrim(f.reporting_purpose),''),a.operational_purpose) as purpose,
  f.report_fields,
  r.id as rate_id,
  r.quote_value,
  r.quote_convention,
  r.conversion_multiplier,
  case
    when s.currency=con.base_currency then a.allocated_amount
    when r.id is not null then a.allocated_amount*r.conversion_multiplier
    else null
  end as report_amount
from atlas.organization_expense_reporting_fact_links f
join atlas.organization_expense_reporting_periods p on p.id=f.period_id
join atlas.organization_expense_reporting_contracts con on con.id=p.contract_id
join atlas.organization_spend_allocations a on a.id=f.source_ref::uuid and a.allocation_state='active'
join atlas.organization_spend_occurrences s on s.id=a.spend_occurrence_id and s.truth_state<>'voided'
left join atlas.organization_expense_reporting_categories c on c.id=f.category_id
left join lateral (
  select rr.*
  from atlas.organization_expense_reporting_rates rr
  where rr.period_id=p.id and rr.rate_kind='currency_exchange'
    and rr.from_unit=s.currency and rr.to_unit=con.base_currency
    and coalesce(rr.effective_from,p.period_start)<=s.occurred_on
    and coalesce(rr.effective_to,p.period_end)>=s.occurred_on
    and rr.conversion_multiplier is not null
  order by rr.effective_from desc nulls last, rr.created_at desc
  limit 1
) r on true
where f.fact_kind='expense' and f.inclusion_state='included';

create or replace function atlas.organization_expense_reporting_accounting_handoff_api_v1(
  p_period_id uuid
)
returns jsonb
language sql
security invoker
set search_path=pg_catalog,atlas
as $function$
  with lines as (
    select * from atlas.organization_expense_reporting_expense_lines_v1
    where period_id=p_period_id and classification_state='confirmed' and report_amount is not null
  ), groups as (
    select category_id,category_key,canonical_label,export_label,
      count(*) as line_count,sum(report_amount) as subtotal,
      jsonb_agg(jsonb_build_object('factLinkId',fact_link_id,'spendAllocationId',spend_allocation_id,'reportAmount',report_amount)
        order by occurred_on,fact_link_id) as lines
    from lines
    group by category_id,category_key,canonical_label,export_label
  )
  select jsonb_build_object(
    'schemaVersion','atlas_organization_expense_accounting_handoff_v1',
    'periodId',p_period_id,
    'detailGroups',coalesce((select jsonb_agg(jsonb_build_object(
      'categoryId',category_id,'categoryKey',category_key,'canonicalLabel',canonical_label,
      'exportLabel',export_label,'lineCount',line_count,'subtotal',subtotal,'lines',lines
    ) order by canonical_label) from groups),'[]'::jsonb),
    'accountingSummary',coalesce((select jsonb_agg(jsonb_build_object(
      'categoryKey',category_key,'label',coalesce(export_label,canonical_label),'amount',subtotal
    ) order by canonical_label) from groups),'[]'::jsonb),
    'reconciliation',jsonb_build_object(
      'detailTotal',coalesce((select sum(report_amount) from lines),0),
      'subtotalTotal',coalesce((select sum(subtotal) from groups),0),
      'reconciled',coalesce((select sum(report_amount) from lines),0)=coalesce((select sum(subtotal) from groups),0)
    )
  );
$function$;

-- Proof-specific grants remain rolled back with the transaction.
grant select on atlas.organization_expense_reporting_expense_lines_v1 to authenticated;
grant execute on function atlas.admit_organization_spend_to_expense_report_api_v1(uuid,uuid,text,text,uuid,text,numeric,text,jsonb) to authenticated;
grant execute on function atlas.organization_expense_reporting_accounting_handoff_api_v1(uuid) to authenticated;

ROLLBACK;

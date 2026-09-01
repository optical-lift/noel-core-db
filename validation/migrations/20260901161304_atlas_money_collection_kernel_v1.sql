-- Canonical postconditions for 20260901161304_atlas_money_collection_kernel_v1.
-- Runs only against the disposable schema clone created by the governed validator.

do $$
declare
  v_missing text[];
  v_cutover_at timestamptz;
  v_state jsonb;
  v_count integer;
begin
  select array_agg(name order by name)
  into v_missing
  from (
    values
      ('atlas.money_obligations'),
      ('atlas.money_obligation_void_events'),
      ('atlas.money_collection_attempts'),
      ('atlas.money_collection_attempt_obligations'),
      ('atlas.money_collection_provider_bindings'),
      ('atlas.money_provider_events'),
      ('atlas.money_receipts'),
      ('atlas.money_receipt_allocations'),
      ('atlas.money_receipt_reversal_events'),
      ('atlas.money_receipt_allocation_reversal_events'),
      ('atlas.money_source_adapter_coverage')
  ) as required(name)
  where to_regclass(name) is null;

  if v_missing is not null then
    raise exception 'Money Collection relations missing after migration: %', v_missing;
  end if;

  if to_regclass('atlas.community_registration_payments') is not null then
    raise exception 'Legacy community_registration_payments survived Money cutover.';
  end if;

  if exists (
    select 1
    from (values
      ('fee_amount_at_submission'),
      ('fee_currency_at_submission'),
      ('fee_basis_at_submission')
    ) as required(column_name)
    where not exists (
      select 1
      from information_schema.columns c
      where c.table_schema='atlas'
        and c.table_name='community_registrations'
        and c.column_name=required.column_name
    )
  ) then
    raise exception 'Community Registration immutable fee snapshot columns are incomplete.';
  end if;

  if to_regprocedure('atlas.money_source_coverage_state_core_v1(uuid,text,text,text,text,timestamp with time zone,numeric,text)') is null then
    raise exception 'Canonical source-currency coverage reader is missing.';
  end if;
  if to_regprocedure('atlas.money_source_coverage_state_core_v1(uuid,text,text,text,text,timestamp with time zone,numeric)') is not null then
    raise exception 'Obsolete seven-argument source coverage reader survived cutover.';
  end if;

  if to_regprocedure('atlas.record_flower_sale_core_v2_domain_impl(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)') is null then
    raise exception 'Flower Sale v2 subordinate domain implementation is missing.';
  end if;
  if to_regprocedure('atlas.record_flower_sale_core_v2(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)') is null then
    raise exception 'Canonical Flower Sale v2 money-postcondition wrapper is missing.';
  end if;
  if to_regprocedure('atlas.record_flower_sale_from_demand_core_v1_domain_impl(uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean)') is null then
    raise exception 'Demand-to-Sale subordinate implementation is missing.';
  end if;
  if to_regprocedure('atlas.record_flower_sale_from_prospect_core_v1_domain_impl(uuid,numeric,numeric,uuid,text,text,text,numeric,numeric,text,text,boolean)') is null then
    raise exception 'Prospect-to-Sale subordinate implementation is missing.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.record_flower_sale_core_v1(uuid,uuid,text,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'service_role can still execute fenced Flower Sale v1 birth core.';
  end if;

  if has_table_privilege('service_role','atlas.flower_sale_orders','INSERT')
     or has_table_privilege('service_role','atlas.flower_sale_orders','UPDATE')
     or has_table_privilege('service_role','atlas.flower_sale_orders','DELETE')
     or has_table_privilege('service_role','atlas.flower_sale_order_lines','INSERT')
     or has_table_privilege('service_role','atlas.community_registrations','INSERT')
     or has_table_privilege('service_role','atlas.community_registrations','UPDATE')
     or has_table_privilege('service_role','atlas.community_registrations','DELETE')
     or has_table_privilege('service_role','atlas.community_registration_participants','INSERT') then
    raise exception 'A raw service_role source-domain mutation path survived the Money cutover fence.';
  end if;

  select count(*), min(coverage_started_at)
  into v_count, v_cutover_at
  from atlas.money_source_adapter_coverage
  where (source_domain,source_kind,obligation_kind,adapter_contract) in (
    ('community_registration','registration','participation_fee','community_registration_money_v1'),
    ('flower_commerce','flower_sale_order','sale_total','flower_sale_money_v1')
  )
    and status='active'
    and release_provenance='20260901161304_atlas_money_collection_kernel_v1';

  if v_count <> 2 or v_cutover_at is null then
    raise exception 'Expected exactly two active Money source-adapter coverage rows with canonical release provenance.';
  end if;

  if (select count(distinct coverage_started_at) from atlas.money_source_adapter_coverage
      where release_provenance='20260901161304_atlas_money_collection_kernel_v1') <> 1 then
    raise exception 'Money source adapters do not share one actual post-lock cutover timestamp.';
  end if;

  v_state := atlas.money_source_coverage_state_core_v1(
    gen_random_uuid(),
    'flower_commerce','flower_sale_order','historical-proof','sale_total',
    v_cutover_at - interval '1 second',
    10.00,
    'USD'
  );
  if v_state->>'coverageState' <> 'pre_kernel_unknown' then
    raise exception 'Pre-coverage Flower source absence was not preserved as payment-unknown: %', v_state;
  end if;

  v_state := atlas.money_source_coverage_state_core_v1(
    gen_random_uuid(),
    'flower_commerce','flower_sale_order','covered-missing-proof','sale_total',
    v_cutover_at + interval '1 second',
    10.00,
    'USD'
  );
  if v_state->>'coverageState' <> 'invariant_gap' then
    raise exception 'Covered positive source without an obligation did not surface invariant_gap: %', v_state;
  end if;

  v_state := atlas.money_source_coverage_state_core_v1(
    gen_random_uuid(),
    'flower_commerce','flower_sale_order','zero-proof','sale_total',
    v_cutover_at + interval '1 second',
    0.00,
    'USD'
  );
  if v_state->>'coverageState' <> 'payment_not_required' then
    raise exception 'Zero-value source did not resolve as payment_not_required: %', v_state;
  end if;

  if not exists (
    select 1 from atlas.architecture_truth_authorities
    where authority_key='money_collection_effective_position'
      and authority_status='canonical'
  ) then
    raise exception 'Money Collection effective-position truth authority was not registered.';
  end if;
  if not exists (
    select 1 from atlas.architecture_truth_authorities
    where authority_key='money_collection_source_coverage'
      and authority_status='canonical'
  ) then
    raise exception 'Money Collection source-coverage truth authority was not registered.';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conname='connected_sources_id_org_unique'
      and conrelid='atlas.connected_sources'::regclass
  ) then
    raise exception 'Organization-owned connected-source structural custody constraint is missing.';
  end if;
end;
$$;

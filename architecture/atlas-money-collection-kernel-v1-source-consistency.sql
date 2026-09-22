-- Atlas Money Collection Kernel v1 — source/obligation consistency correction.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- Assemble after domain adapters and the Registration fee-snapshot correction.
-- The original seven-argument coverage reader remains an internal historical draft
-- signature; canonical domain readers below use this source-currency-aware overload.

create or replace function atlas.money_source_coverage_state_core_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_source_created_at timestamptz,
  p_source_amount numeric,
  p_source_currency text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source_domain text := lower(nullif(btrim(p_source_domain),''));
  v_source_kind text := lower(nullif(btrim(p_source_kind),''));
  v_source_id text := nullif(btrim(p_source_id),'');
  v_obligation_kind text := lower(nullif(btrim(p_obligation_kind),''));
  v_source_amount numeric(14,2) := round(p_source_amount,2);
  v_source_currency text := upper(nullif(btrim(p_source_currency),''));
  v_obligation atlas.money_obligations%rowtype;
  v_position record;
  v_covered boolean;
begin
  if p_organization_id is null
     or v_source_domain is null
     or v_source_kind is null
     or v_source_id is null
     or v_obligation_kind is null
     or p_source_created_at is null
     or v_source_amount is null
     or v_source_amount<0
     or v_source_currency is null
     or v_source_currency !~ '^[A-Z]{3}$' then
    raise exception 'Money coverage source facts are incomplete.' using errcode='22023';
  end if;

  if v_source_amount=0 then
    return jsonb_build_object(
      'coverageState','payment_not_required',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',0,
      'currency',v_source_currency
    );
  end if;

  select exists(
    select 1
    from atlas.money_source_adapter_coverage c
    where c.source_domain=v_source_domain
      and c.source_kind=v_source_kind
      and c.obligation_kind=v_obligation_kind
      and c.coverage_started_at<=p_source_created_at
      and (c.coverage_ended_at is null or p_source_created_at<c.coverage_ended_at)
  ) into v_covered;

  select * into v_obligation
  from atlas.money_obligations o
  where o.organization_id=p_organization_id
    and o.source_domain=v_source_domain
    and o.source_kind=v_source_kind
    and o.source_id=v_source_id
    and o.obligation_kind=v_obligation_kind;

  if not v_covered then
    if v_obligation.id is not null then
      return jsonb_build_object(
        'coverageState','invariant_gap',
        'sourceDomain',v_source_domain,
        'sourceKind',v_source_kind,
        'sourceId',v_source_id,
        'obligationId',v_obligation.id,
        'effectiveState',null,
        'openAmount',null,
        'currency',v_source_currency,
        'truthBoundary','pre_coverage_source_has_canonical_obligation'
      );
    end if;
    return jsonb_build_object(
      'coverageState','pre_kernel_unknown',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_source_currency
    );
  end if;

  if v_obligation.id is null then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_source_currency,
      'truthBoundary','covered_positive_source_missing_obligation'
    );
  end if;

  if v_obligation.amount is distinct from v_source_amount
     or v_obligation.currency is distinct from v_source_currency then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',v_obligation.id,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_source_currency,
      'truthBoundary','obligation_snapshot_conflicts_with_canonical_source',
      'sourceAmount',v_source_amount,
      'obligationAmount',v_obligation.amount,
      'sourceCurrency',v_source_currency,
      'obligationCurrency',v_obligation.currency
    );
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1 p
  where p.obligation_id=v_obligation.id;

  if v_position.obligation_id is null then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',v_obligation.id,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_source_currency,
      'truthBoundary','obligation_missing_effective_position'
    );
  end if;

  return jsonb_build_object(
    'coverageState','covered',
    'sourceDomain',v_source_domain,
    'sourceKind',v_source_kind,
    'sourceId',v_source_id,
    'obligationId',v_obligation.id,
    'effectiveState',v_position.effective_state,
    'openAmount',v_position.open_amount,
    'currency',v_position.currency
  );
end;
$$;

create or replace function atlas.community_registration_money_position_v1(
  p_registration_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_registration atlas.community_registrations%rowtype;
  v_offering atlas.community_registration_offerings%rowtype;
  v_organization_id uuid;
begin
  select r.* into v_registration
  from atlas.community_registrations r
  where r.id=p_registration_id;
  if v_registration.id is null then
    raise exception 'Community Registration not found.' using errcode='P0002';
  end if;

  select o.* into v_offering
  from atlas.community_registration_offerings o
  where o.id=v_registration.offering_id;
  select f.organization_id into v_organization_id
  from atlas.farms f
  where f.id=v_offering.farm_id;
  if v_offering.id is null or v_organization_id is null then
    raise exception 'Community Registration source custody is incomplete.' using errcode='23503';
  end if;

  return atlas.money_source_coverage_state_core_v1(
    v_organization_id,
    'community_registration',
    'registration',
    v_registration.id::text,
    'participation_fee',
    v_registration.created_at,
    v_registration.fee_amount_at_submission,
    v_registration.fee_currency_at_submission
  );
end;
$$;

create or replace function atlas.flower_sale_money_position_v1(
  p_sale_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_sale atlas.flower_sale_orders%rowtype;
  v_organization_id uuid;
begin
  select s.* into v_sale
  from atlas.flower_sale_orders s
  where s.id=p_sale_order_id;
  if v_sale.id is null then
    raise exception 'Flower Sale not found.' using errcode='P0002';
  end if;

  select f.organization_id into v_organization_id
  from atlas.farms f
  where f.id=v_sale.farm_id;
  if v_organization_id is null then
    raise exception 'Flower Sale source custody is incomplete.' using errcode='23503';
  end if;

  return atlas.money_source_coverage_state_core_v1(
    v_organization_id,
    'flower_commerce',
    'flower_sale_order',
    v_sale.id::text,
    'sale_total',
    v_sale.created_at,
    v_sale.total_amount,
    v_sale.currency
  );
end;
$$;

revoke execute on function atlas.money_source_coverage_state_core_v1(
  uuid,text,text,text,text,timestamptz,numeric,text
) from public,anon,authenticated,service_role;
revoke execute on function atlas.community_registration_money_position_v1(uuid)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.flower_sale_money_position_v1(uuid)
  from public,anon,authenticated,service_role;

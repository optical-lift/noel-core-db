begin;

create table atlas.ledger_commercial_pricing_policies (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  policy_key text not null check (btrim(policy_key)<>''),
  pricing_method text not null
    check (pricing_method in ('gross_margin','markup')),
  target_rate numeric not null,
  minimum_rate numeric not null,
  currency text null,
  benchmark_constraint text not null default 'none'
    check (benchmark_constraint in ('none','at_or_below','strictly_below','discount_rate')),
  benchmark_discount_rate numeric null,
  cost_basis_policy jsonb not null default '{}'::jsonb
    check (jsonb_typeof(cost_basis_policy)='object'),
  effective_from timestamptz not null,
  effective_until timestamptz null,
  policy_state text not null default 'established'
    check (policy_state in ('established','superseded','withdrawn')),
  policy_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(policy_basis)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until>effective_from),
  check (
    (pricing_method='gross_margin'
      and target_rate>=0 and target_rate<1
      and minimum_rate>=0 and minimum_rate<1)
    or
    (pricing_method='markup'
      and target_rate>=0
      and minimum_rate>=0)
  ),
  check (minimum_rate<=target_rate),
  check (
    (currency is null)
    or
    (currency ~ '^[A-Z]{3}$')
  ),
  check (
    (benchmark_constraint='discount_rate'
      and benchmark_discount_rate is not null
      and benchmark_discount_rate>=0
      and benchmark_discount_rate<1)
    or
    (benchmark_constraint<>'discount_rate'
      and benchmark_discount_rate is null)
  ),
  unique(ledger_id,policy_key,effective_from)
);

create index ledger_commercial_pricing_policies_resolve_idx
  on atlas.ledger_commercial_pricing_policies(
    ledger_id,policy_key,effective_from desc
  )
  where policy_state<>'withdrawn';

create table atlas.ledger_commercial_market_observations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  market_actor_entity_id uuid null references reality.entities(id) on delete restrict,
  supersedes_observation_id uuid null
    references atlas.ledger_commercial_market_observations(id) on delete restrict,
  source_label text not null check (btrim(source_label)<>''),
  observation_role text not null
    check (observation_role in (
      'incumbent_benchmark',
      'market_reference',
      'customer_alternative',
      'competitor_quote',
      'public_price'
    )),
  market_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(market_context)='object'),
  item_specification jsonb not null default '{}'::jsonb
    check (jsonb_typeof(item_specification)='object'),
  observed_at timestamptz not null,
  effective_from timestamptz null,
  effective_until timestamptz null,
  price_amount numeric not null check (price_amount>=0),
  currency text null,
  price_quantity numeric null,
  price_unit text null,
  price_basis_state text not null default 'unknown'
    check (price_basis_state in ('source_explicit','confirmed','unknown')),
  pack_quantity numeric null,
  pack_unit text null,
  terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(terms)='object'),
  source_kind text not null
    check (source_kind in (
      'provider_observation',
      'supplier_document',
      'manual_capture',
      'customer_report',
      'imported_record'
    )),
  source_ref text null,
  evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  check (effective_until is null or effective_from is null or effective_until>=effective_from),
  check ((currency is null) or (currency ~ '^[A-Z]{3}$')),
  check (
    (price_quantity is null and price_unit is null)
    or
    (price_quantity is not null and price_quantity>0
      and price_unit is not null and btrim(price_unit)<>'')
  ),
  check (
    (pack_quantity is null and pack_unit is null)
    or
    (pack_quantity is not null and pack_quantity>0
      and pack_unit is not null and btrim(pack_unit)<>'')
  )
);

create index ledger_commercial_market_observations_timeline_idx
  on atlas.ledger_commercial_market_observations(
    ledger_id,observation_role,observed_at desc,id
  );

create index ledger_commercial_market_observations_actor_idx
  on atlas.ledger_commercial_market_observations(
    market_actor_entity_id,observed_at desc
  )
  where market_actor_entity_id is not null;

create table atlas.ledger_commercial_quote_evaluation_receipts (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  evaluation_key text not null check (btrim(evaluation_key)<>''),
  request_ref jsonb not null check (jsonb_typeof(request_ref)='object'),
  pricing_policy_id uuid not null
    references atlas.ledger_commercial_pricing_policies(id) on delete restrict,
  evaluated_at timestamptz not null default now(),
  decision_state text not null
    check (decision_state in (
      'eligible','review_required','blocked','incomplete_evidence'
    )),
  pricing_state text not null
    check (pricing_state in (
      'target_met','minimum_met','below_minimum','unresolved'
    )),
  market_state text not null
    check (market_state in (
      'not_required','passes','fails','missing_benchmark'
    )),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  protected_cost_total numeric not null check (protected_cost_total>=0),
  proposed_quote_total numeric not null check (proposed_quote_total>0),
  benchmark_total numeric null check (benchmark_total is null or benchmark_total>=0),
  gross_profit numeric not null,
  realized_rate numeric null,
  customer_savings_amount numeric null,
  customer_savings_rate numeric null,
  evaluation_packet jsonb not null
    check (jsonb_typeof(evaluation_packet)='object'),
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  result_ref jsonb not null default '{}'::jsonb
    check (jsonb_typeof(result_ref)='object'),
  created_at timestamptz not null default now(),
  unique(ledger_id,evaluation_key)
);

create index ledger_commercial_quote_evaluation_receipts_timeline_idx
  on atlas.ledger_commercial_quote_evaluation_receipts(
    ledger_id,evaluated_at desc,id
  );

create table atlas.ledger_commercial_quote_evaluation_benchmarks (
  receipt_id uuid not null
    references atlas.ledger_commercial_quote_evaluation_receipts(id) on delete restrict,
  market_observation_id uuid not null
    references atlas.ledger_commercial_market_observations(id) on delete restrict,
  benchmark_amount numeric not null check (benchmark_amount>=0),
  line_ref jsonb not null default '{}'::jsonb
    check (jsonb_typeof(line_ref)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  primary key(receipt_id,market_observation_id)
);

create index ledger_commercial_quote_evaluation_benchmarks_observation_idx
  on atlas.ledger_commercial_quote_evaluation_benchmarks(market_observation_id);

create or replace function atlas.guard_ledger_commercial_pricing_policy_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if not exists(
    select 1
    from ledger.ledgers l
    where l.id=new.ledger_id
      and l.ledger_state='active'
  ) then
    raise exception 'Commercial pricing policy requires an active Ledger.'
      using errcode='23514';
  end if;

  if new.policy_state<>'withdrawn'
     and exists(
       select 1
       from atlas.ledger_commercial_pricing_policies p
       where p.ledger_id=new.ledger_id
         and p.policy_key=new.policy_key
         and p.policy_state<>'withdrawn'
         and p.id<>new.id
         and p.effective_from<coalesce(new.effective_until,'infinity'::timestamptz)
         and new.effective_from<coalesce(p.effective_until,'infinity'::timestamptz)
     ) then
    raise exception 'Commercial pricing policy effective windows may not overlap for one Ledger and policy key.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger ledger_commercial_pricing_policy_guard_v1
before insert or update on atlas.ledger_commercial_pricing_policies
for each row execute function atlas.guard_ledger_commercial_pricing_policy_v1();

create or replace function atlas.guard_ledger_commercial_market_observation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_superseded_ledger uuid;
begin
  if not exists(
    select 1 from ledger.ledgers l
    where l.id=new.ledger_id
      and l.ledger_state='active'
  ) then
    raise exception 'Commercial market observation requires an active Ledger.'
      using errcode='23514';
  end if;

  if new.market_actor_entity_id is not null
     and not exists(
       select 1 from reality.entities e
       where e.id=new.market_actor_entity_id
         and e.identity_state<>'retired'
     ) then
    raise exception 'Market actor Entity must be a non-retired Reality Entity.'
      using errcode='23514';
  end if;

  if new.supersedes_observation_id is not null then
    select o.ledger_id
      into v_superseded_ledger
    from atlas.ledger_commercial_market_observations o
    where o.id=new.supersedes_observation_id;

    if v_superseded_ledger is null or v_superseded_ledger<>new.ledger_id then
      raise exception 'A market observation may supersede only an observation from the same Ledger.'
        using errcode='23514';
    end if;
  end if;

  return new;
end
$function$;

create trigger ledger_commercial_market_observation_guard_v1
before insert on atlas.ledger_commercial_market_observations
for each row execute function atlas.guard_ledger_commercial_market_observation_v1();

create or replace function atlas.guard_ledger_commercial_quote_receipt_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_policy_ledger uuid;
begin
  select p.ledger_id
    into v_policy_ledger
  from atlas.ledger_commercial_pricing_policies p
  where p.id=new.pricing_policy_id;

  if v_policy_ledger is null or v_policy_ledger<>new.ledger_id then
    raise exception 'Quote receipt policy must belong to the same Ledger.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

create trigger ledger_commercial_quote_receipt_guard_v1
before insert on atlas.ledger_commercial_quote_evaluation_receipts
for each row execute function atlas.guard_ledger_commercial_quote_receipt_v1();

create or replace function atlas.guard_ledger_commercial_quote_benchmark_link_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_receipt_ledger uuid;
  v_observation_ledger uuid;
begin
  select r.ledger_id into v_receipt_ledger
  from atlas.ledger_commercial_quote_evaluation_receipts r
  where r.id=new.receipt_id;

  select o.ledger_id into v_observation_ledger
  from atlas.ledger_commercial_market_observations o
  where o.id=new.market_observation_id;

  if v_receipt_ledger is null
     or v_observation_ledger is null
     or v_receipt_ledger<>v_observation_ledger then
    raise exception 'Quote benchmark observation must belong to the same Ledger as the receipt.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

create trigger ledger_commercial_quote_benchmark_link_guard_v1
before insert on atlas.ledger_commercial_quote_evaluation_benchmarks
for each row execute function atlas.guard_ledger_commercial_quote_benchmark_link_v1();

create or replace function atlas.record_ledger_commercial_pricing_policy_service_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_pricing_method text,
  p_target_rate numeric,
  p_minimum_rate numeric,
  p_currency text,
  p_benchmark_constraint text,
  p_benchmark_discount_rate numeric,
  p_cost_basis_policy jsonb,
  p_effective_from timestamptz,
  p_policy_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_id uuid;
  v_currency text;
begin
  v_currency:=nullif(upper(btrim(coalesce(p_currency,''))),'');
  if p_ledger_id is null then
    raise exception 'Ledger is required.' using errcode='22023';
  end if;
  if btrim(coalesce(p_policy_key,''))='' then
    raise exception 'Policy key is required.' using errcode='22023';
  end if;
  if p_effective_from is null then
    raise exception 'Policy effective_from is required.' using errcode='22023';
  end if;

  insert into atlas.ledger_commercial_pricing_policies(
    ledger_id,policy_key,pricing_method,target_rate,minimum_rate,currency,
    benchmark_constraint,benchmark_discount_rate,cost_basis_policy,
    effective_from,policy_basis,metadata
  ) values (
    p_ledger_id,btrim(p_policy_key),lower(btrim(p_pricing_method)),
    p_target_rate,p_minimum_rate,v_currency,
    lower(btrim(coalesce(p_benchmark_constraint,'none'))),
    p_benchmark_discount_rate,coalesce(p_cost_basis_policy,'{}'::jsonb),
    p_effective_from,coalesce(p_policy_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end
$function$;

create or replace function atlas.supersede_ledger_commercial_pricing_policy_service_v1(
  p_existing_policy_id uuid,
  p_new_effective_from timestamptz,
  p_pricing_method text,
  p_target_rate numeric,
  p_minimum_rate numeric,
  p_currency text,
  p_benchmark_constraint text,
  p_benchmark_discount_rate numeric,
  p_cost_basis_policy jsonb,
  p_policy_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_old atlas.ledger_commercial_pricing_policies%rowtype;
  v_new_id uuid;
begin
  select * into v_old
  from atlas.ledger_commercial_pricing_policies
  where id=p_existing_policy_id
  for update;

  if v_old.id is null then
    raise exception 'Existing pricing policy not found.' using errcode='22023';
  end if;
  if v_old.policy_state='withdrawn' then
    raise exception 'Withdrawn pricing policy cannot be superseded.' using errcode='23514';
  end if;
  if p_new_effective_from is null or p_new_effective_from<=v_old.effective_from then
    raise exception 'Superseding policy must begin after the existing policy begins.'
      using errcode='23514';
  end if;
  if v_old.effective_until is not null
     and p_new_effective_from>v_old.effective_until then
    raise exception 'Superseding policy may not create an unexplained gap after a closed policy window.'
      using errcode='23514';
  end if;

  update atlas.ledger_commercial_pricing_policies
  set effective_until=p_new_effective_from,
      policy_state='superseded',
      updated_at=now()
  where id=v_old.id;

  v_new_id:=atlas.record_ledger_commercial_pricing_policy_service_v1(
    v_old.ledger_id,
    v_old.policy_key,
    p_pricing_method,
    p_target_rate,
    p_minimum_rate,
    p_currency,
    p_benchmark_constraint,
    p_benchmark_discount_rate,
    p_cost_basis_policy,
    p_new_effective_from,
    p_policy_basis,
    p_metadata
  );

  return v_new_id;
end
$function$;

create or replace function atlas.ledger_commercial_pricing_policy_at_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_policy atlas.ledger_commercial_pricing_policies%rowtype;
begin
  select * into v_policy
  from atlas.ledger_commercial_pricing_policies p
  where p.ledger_id=p_ledger_id
    and p.policy_key=p_policy_key
    and p.policy_state<>'withdrawn'
    and p.effective_from<=p_at
    and (p.effective_until is null or p.effective_until>p_at)
  order by p.effective_from desc
  limit 1;

  if v_policy.id is null then
    return jsonb_build_object(
      'contractVersion','ledger_commercial_pricing_policy_at_v1',
      'state','not_found',
      'ledgerId',p_ledger_id,
      'policyKey',p_policy_key,
      'at',p_at
    );
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_commercial_pricing_policy_at_v1',
    'state','resolved',
    'policyId',v_policy.id,
    'ledgerId',v_policy.ledger_id,
    'policyKey',v_policy.policy_key,
    'pricingMethod',v_policy.pricing_method,
    'targetRate',v_policy.target_rate,
    'minimumRate',v_policy.minimum_rate,
    'currency',v_policy.currency,
    'benchmarkConstraint',v_policy.benchmark_constraint,
    'benchmarkDiscountRate',v_policy.benchmark_discount_rate,
    'costBasisPolicy',v_policy.cost_basis_policy,
    'effectiveFrom',v_policy.effective_from,
    'effectiveUntil',v_policy.effective_until,
    'policyState',v_policy.policy_state,
    'policyBasis',v_policy.policy_basis,
    'metadata',v_policy.metadata
  );
end
$function$;

create or replace function atlas.record_ledger_commercial_market_observation_service_v1(
  p_ledger_id uuid,
  p_market_actor_entity_id uuid,
  p_supersedes_observation_id uuid,
  p_source_label text,
  p_observation_role text,
  p_market_context jsonb,
  p_item_specification jsonb,
  p_observed_at timestamptz,
  p_effective_from timestamptz,
  p_effective_until timestamptz,
  p_price_amount numeric,
  p_currency text,
  p_price_quantity numeric,
  p_price_unit text,
  p_price_basis_state text,
  p_pack_quantity numeric,
  p_pack_unit text,
  p_terms jsonb,
  p_source_kind text,
  p_source_ref text,
  p_evidence jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_id uuid;
  v_currency text;
begin
  v_currency:=nullif(upper(btrim(coalesce(p_currency,''))),'');
  if p_observed_at is null then
    raise exception 'observed_at is required.' using errcode='22023';
  end if;

  insert into atlas.ledger_commercial_market_observations(
    ledger_id,market_actor_entity_id,supersedes_observation_id,
    source_label,observation_role,market_context,item_specification,
    observed_at,effective_from,effective_until,price_amount,currency,
    price_quantity,price_unit,price_basis_state,pack_quantity,pack_unit,
    terms,source_kind,source_ref,evidence,metadata
  ) values (
    p_ledger_id,p_market_actor_entity_id,p_supersedes_observation_id,
    btrim(p_source_label),lower(btrim(p_observation_role)),
    coalesce(p_market_context,'{}'::jsonb),
    coalesce(p_item_specification,'{}'::jsonb),
    p_observed_at,p_effective_from,p_effective_until,p_price_amount,v_currency,
    p_price_quantity,nullif(btrim(coalesce(p_price_unit,'')),''),
    lower(btrim(coalesce(p_price_basis_state,'unknown'))),
    p_pack_quantity,nullif(btrim(coalesce(p_pack_unit,'')),''),
    coalesce(p_terms,'{}'::jsonb),lower(btrim(p_source_kind)),
    nullif(btrim(coalesce(p_source_ref,'')),''),
    coalesce(p_evidence,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end
$function$;

create or replace function atlas.ledger_commercial_quote_envelope_v1(
  p_policy_id uuid,
  p_benchmark_total numeric,
  p_currency text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_policy atlas.ledger_commercial_pricing_policies%rowtype;
  v_currency text;
  v_quote_ceiling numeric:=null;
  v_ceiling_inclusive boolean:=true;
  v_target_cost_ceiling numeric:=null;
  v_minimum_cost_ceiling numeric:=null;
begin
  select * into v_policy
  from atlas.ledger_commercial_pricing_policies
  where id=p_policy_id;

  if v_policy.id is null then
    raise exception 'Pricing policy not found.' using errcode='22023';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency must be a three-letter uppercase code.'
      using errcode='22023';
  end if;
  if v_policy.currency is not null and v_policy.currency<>v_currency then
    raise exception 'Pricing policy currency does not match requested currency.'
      using errcode='22023';
  end if;

  if v_policy.benchmark_constraint<>'none' then
    if p_benchmark_total is null or p_benchmark_total<0 then
      return jsonb_build_object(
        'contractVersion','ledger_commercial_quote_envelope_v1',
        'state','incomplete_evidence',
        'reason','benchmark_required',
        'policyId',v_policy.id,
        'currency',v_currency
      );
    end if;

    if v_policy.benchmark_constraint='discount_rate' then
      v_quote_ceiling:=p_benchmark_total*(1-v_policy.benchmark_discount_rate);
      v_ceiling_inclusive:=true;
    elsif v_policy.benchmark_constraint='strictly_below' then
      v_quote_ceiling:=p_benchmark_total;
      v_ceiling_inclusive:=false;
    else
      v_quote_ceiling:=p_benchmark_total;
      v_ceiling_inclusive:=true;
    end if;

    if v_policy.pricing_method='gross_margin' then
      v_target_cost_ceiling:=v_quote_ceiling*(1-v_policy.target_rate);
      v_minimum_cost_ceiling:=v_quote_ceiling*(1-v_policy.minimum_rate);
    else
      v_target_cost_ceiling:=v_quote_ceiling/(1+v_policy.target_rate);
      v_minimum_cost_ceiling:=v_quote_ceiling/(1+v_policy.minimum_rate);
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_commercial_quote_envelope_v1',
    'state','ready',
    'policyId',v_policy.id,
    'ledgerId',v_policy.ledger_id,
    'currency',v_currency,
    'pricingMethod',v_policy.pricing_method,
    'targetRate',v_policy.target_rate,
    'minimumRate',v_policy.minimum_rate,
    'benchmarkConstraint',v_policy.benchmark_constraint,
    'benchmarkDiscountRate',v_policy.benchmark_discount_rate,
    'benchmarkTotal',p_benchmark_total,
    'marketQuoteCeiling',v_quote_ceiling,
    'marketQuoteCeilingInclusive',v_ceiling_inclusive,
    'targetProtectedCostCeiling',v_target_cost_ceiling,
    'minimumProtectedCostCeiling',v_minimum_cost_ceiling,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotCreateOffer',true,
      'doesNotAuthorizePurchase',true,
      'strictCeilingRemainsExclusive',not v_ceiling_inclusive
    )
  );
end
$function$;

create or replace function atlas.ledger_commercial_quote_evaluate_v1(
  p_policy_id uuid,
  p_protected_cost_total numeric,
  p_proposed_quote_total numeric,
  p_benchmark_total numeric,
  p_currency text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_policy atlas.ledger_commercial_pricing_policies%rowtype;
  v_currency text;
  v_realized_rate numeric:=null;
  v_pricing_state text;
  v_market_state text;
  v_decision_state text;
  v_market_ceiling numeric:=null;
  v_gross_profit numeric;
  v_savings_amount numeric:=null;
  v_savings_rate numeric:=null;
begin
  select * into v_policy
  from atlas.ledger_commercial_pricing_policies
  where id=p_policy_id;

  if v_policy.id is null then
    raise exception 'Pricing policy not found.' using errcode='22023';
  end if;
  if p_protected_cost_total is null or p_protected_cost_total<0 then
    raise exception 'Protected cost total must be nonnegative.'
      using errcode='22023';
  end if;
  if p_proposed_quote_total is null or p_proposed_quote_total<=0 then
    raise exception 'Proposed quote total must be greater than zero.'
      using errcode='22023';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency must be a three-letter uppercase code.'
      using errcode='22023';
  end if;
  if v_policy.currency is not null and v_policy.currency<>v_currency then
    raise exception 'Pricing policy currency does not match quote currency.'
      using errcode='22023';
  end if;

  v_gross_profit:=p_proposed_quote_total-p_protected_cost_total;

  if v_policy.pricing_method='gross_margin' then
    v_realized_rate:=v_gross_profit/p_proposed_quote_total;
  elsif p_protected_cost_total>0 then
    v_realized_rate:=v_gross_profit/p_protected_cost_total;
  else
    v_realized_rate:=null;
  end if;

  if v_realized_rate is null then
    v_pricing_state:='unresolved';
  elsif v_realized_rate>=v_policy.target_rate then
    v_pricing_state:='target_met';
  elsif v_realized_rate>=v_policy.minimum_rate then
    v_pricing_state:='minimum_met';
  else
    v_pricing_state:='below_minimum';
  end if;

  if v_policy.benchmark_constraint='none' then
    v_market_state:='not_required';
  elsif p_benchmark_total is null then
    v_market_state:='missing_benchmark';
  else
    if p_benchmark_total<0 then
      raise exception 'Benchmark total must be nonnegative.'
        using errcode='22023';
    end if;

    if v_policy.benchmark_constraint='discount_rate' then
      v_market_ceiling:=p_benchmark_total*(1-v_policy.benchmark_discount_rate);
      v_market_state:=case
        when p_proposed_quote_total<=v_market_ceiling then 'passes'
        else 'fails'
      end;
    elsif v_policy.benchmark_constraint='strictly_below' then
      v_market_ceiling:=p_benchmark_total;
      v_market_state:=case
        when p_proposed_quote_total<v_market_ceiling then 'passes'
        else 'fails'
      end;
    else
      v_market_ceiling:=p_benchmark_total;
      v_market_state:=case
        when p_proposed_quote_total<=v_market_ceiling then 'passes'
        else 'fails'
      end;
    end if;

    v_savings_amount:=p_benchmark_total-p_proposed_quote_total;
    if p_benchmark_total>0 then
      v_savings_rate:=v_savings_amount/p_benchmark_total;
    end if;
  end if;

  if v_market_state='missing_benchmark' then
    v_decision_state:='incomplete_evidence';
  elsif v_pricing_state in ('below_minimum','unresolved')
     or v_market_state='fails' then
    v_decision_state:='blocked';
  elsif v_pricing_state='target_met' then
    v_decision_state:='eligible';
  else
    v_decision_state:='review_required';
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_commercial_quote_evaluate_v1',
    'policyId',v_policy.id,
    'ledgerId',v_policy.ledger_id,
    'currency',v_currency,
    'protectedCostTotal',p_protected_cost_total,
    'proposedQuoteTotal',p_proposed_quote_total,
    'benchmarkTotal',p_benchmark_total,
    'grossProfit',v_gross_profit,
    'pricingMethod',v_policy.pricing_method,
    'targetRate',v_policy.target_rate,
    'minimumRate',v_policy.minimum_rate,
    'realizedRate',v_realized_rate,
    'pricingState',v_pricing_state,
    'benchmarkConstraint',v_policy.benchmark_constraint,
    'benchmarkDiscountRate',v_policy.benchmark_discount_rate,
    'marketQuoteCeiling',v_market_ceiling,
    'marketState',v_market_state,
    'customerSavingsAmount',v_savings_amount,
    'customerSavingsRate',v_savings_rate,
    'decisionState',v_decision_state,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotCreateOffer',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true
    )
  );
end
$function$;

create or replace function atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
  p_ledger_id uuid,
  p_evaluation_key text,
  p_request_ref jsonb,
  p_pricing_policy_id uuid,
  p_protected_cost_total numeric,
  p_proposed_quote_total numeric,
  p_currency text,
  p_benchmark_lines jsonb default '[]'::jsonb,
  p_evaluation_context jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_result_ref jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_policy atlas.ledger_commercial_pricing_policies%rowtype;
  v_line jsonb;
  v_observation atlas.ledger_commercial_market_observations%rowtype;
  v_observation_id uuid;
  v_benchmark_amount numeric;
  v_benchmark_total numeric:=null;
  v_eval jsonb;
  v_receipt_id uuid;
  v_currency text;
  v_count integer:=0;
begin
  if btrim(coalesce(p_evaluation_key,''))='' then
    raise exception 'Evaluation key is required.' using errcode='22023';
  end if;
  if p_request_ref is null or jsonb_typeof(p_request_ref)<>'object' then
    raise exception 'request_ref must be a JSON object.' using errcode='22023';
  end if;
  if p_benchmark_lines is null or jsonb_typeof(p_benchmark_lines)<>'array' then
    raise exception 'benchmark_lines must be a JSON array.' using errcode='22023';
  end if;
  if p_evaluation_context is null or jsonb_typeof(p_evaluation_context)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_result_ref is null or jsonb_typeof(p_result_ref)<>'object' then
    raise exception 'Evaluation context, provenance, and result_ref must be JSON objects.'
      using errcode='22023';
  end if;

  select * into v_policy
  from atlas.ledger_commercial_pricing_policies
  where id=p_pricing_policy_id;

  if v_policy.id is null or v_policy.ledger_id<>p_ledger_id then
    raise exception 'Pricing policy must belong to the receipt Ledger.'
      using errcode='23514';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));

  for v_line in select value from jsonb_array_elements(p_benchmark_lines)
  loop
    if jsonb_typeof(v_line)<>'object' then
      raise exception 'Each benchmark line must be a JSON object.'
        using errcode='22023';
    end if;
    if nullif(v_line->>'marketObservationId','') is null
       or jsonb_typeof(v_line->'benchmarkAmount')<>'number' then
      raise exception 'Each benchmark line requires marketObservationId and numeric benchmarkAmount.'
        using errcode='22023';
    end if;

    v_observation_id:=(v_line->>'marketObservationId')::uuid;
    v_benchmark_amount:=(v_line->>'benchmarkAmount')::numeric;
    if v_benchmark_amount<0 then
      raise exception 'Benchmark contribution must be nonnegative.'
        using errcode='22023';
    end if;

    select * into v_observation
    from atlas.ledger_commercial_market_observations
    where id=v_observation_id;

    if v_observation.id is null or v_observation.ledger_id<>p_ledger_id then
      raise exception 'Every benchmark observation must belong to the receipt Ledger.'
        using errcode='23514';
    end if;
    if v_observation.price_basis_state='unknown'
       or v_observation.currency is null
       or v_observation.currency<>v_currency
       or v_observation.price_quantity is null
       or v_observation.price_unit is null then
      raise exception 'Computational benchmark requires known price basis and matching currency.'
        using errcode='23514';
    end if;

    v_benchmark_total:=coalesce(v_benchmark_total,0)+v_benchmark_amount;
    v_count:=v_count+1;
  end loop;

  v_eval:=atlas.ledger_commercial_quote_evaluate_v1(
    p_pricing_policy_id,
    p_protected_cost_total,
    p_proposed_quote_total,
    v_benchmark_total,
    v_currency
  );

  insert into atlas.ledger_commercial_quote_evaluation_receipts(
    ledger_id,evaluation_key,request_ref,pricing_policy_id,evaluated_at,
    decision_state,pricing_state,market_state,currency,
    protected_cost_total,proposed_quote_total,benchmark_total,gross_profit,
    realized_rate,customer_savings_amount,customer_savings_rate,
    evaluation_packet,provenance,result_ref
  ) values (
    p_ledger_id,btrim(p_evaluation_key),p_request_ref,p_pricing_policy_id,now(),
    v_eval->>'decisionState',v_eval->>'pricingState',v_eval->>'marketState',
    v_currency,p_protected_cost_total,p_proposed_quote_total,v_benchmark_total,
    (v_eval->>'grossProfit')::numeric,
    case when v_eval->>'realizedRate' is null then null
         else (v_eval->>'realizedRate')::numeric end,
    case when v_eval->>'customerSavingsAmount' is null then null
         else (v_eval->>'customerSavingsAmount')::numeric end,
    case when v_eval->>'customerSavingsRate' is null then null
         else (v_eval->>'customerSavingsRate')::numeric end,
    jsonb_build_object(
      'evaluation',v_eval,
      'benchmarkLines',p_benchmark_lines,
      'benchmarkLineCount',v_count,
      'context',p_evaluation_context
    ),
    p_provenance,p_result_ref
  )
  returning id into v_receipt_id;

  for v_line in select value from jsonb_array_elements(p_benchmark_lines)
  loop
    insert into atlas.ledger_commercial_quote_evaluation_benchmarks(
      receipt_id,market_observation_id,benchmark_amount,line_ref,metadata
    ) values (
      v_receipt_id,
      (v_line->>'marketObservationId')::uuid,
      (v_line->>'benchmarkAmount')::numeric,
      coalesce(v_line->'lineRef','{}'::jsonb),
      coalesce(v_line->'metadata','{}'::jsonb)
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','record_ledger_commercial_quote_evaluation_receipt_service_v1',
    'receiptId',v_receipt_id,
    'ledgerId',p_ledger_id,
    'evaluationKey',btrim(p_evaluation_key),
    'decisionState',v_eval->>'decisionState',
    'pricingState',v_eval->>'pricingState',
    'marketState',v_eval->>'marketState',
    'benchmarkTotal',v_benchmark_total,
    'evaluation',v_eval,
    'truthBoundary',jsonb_build_object(
      'appendOnlyReceipt',true,
      'doesNotCreateOffer',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true
    )
  );
end
$function$;

alter table atlas.ledger_commercial_pricing_policies enable row level security;
alter table atlas.ledger_commercial_market_observations enable row level security;
alter table atlas.ledger_commercial_quote_evaluation_receipts enable row level security;
alter table atlas.ledger_commercial_quote_evaluation_benchmarks enable row level security;

revoke all on atlas.ledger_commercial_pricing_policies
  from public,anon,authenticated,service_role;
revoke all on atlas.ledger_commercial_market_observations
  from public,anon,authenticated,service_role;
revoke all on atlas.ledger_commercial_quote_evaluation_receipts
  from public,anon,authenticated,service_role;
revoke all on atlas.ledger_commercial_quote_evaluation_benchmarks
  from public,anon,authenticated,service_role;

grant select,insert,update on atlas.ledger_commercial_pricing_policies to service_role;grant select,insert on atlas.ledger_commercial_market_observations to service_role;
grant select,insert on atlas.ledger_commercial_quote_evaluation_receipts to service_role;
grant select,insert on atlas.ledger_commercial_quote_evaluation_benchmarks to service_role;

revoke all on function atlas.record_ledger_commercial_pricing_policy_service_v1(
  uuid,text,text,numeric,numeric,text,text,numeric,jsonb,timestamptz,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_ledger_commercial_pricing_policy_service_v1(
  uuid,text,text,numeric,numeric,text,text,numeric,jsonb,timestamptz,jsonb,jsonb
) to service_role;

revoke all on function atlas.supersede_ledger_commercial_pricing_policy_service_v1(
  uuid,timestamptz,text,numeric,numeric,text,text,numeric,jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.supersede_ledger_commercial_pricing_policy_service_v1(
  uuid,timestamptz,text,numeric,numeric,text,text,numeric,jsonb,jsonb,jsonb
) to service_role;

revoke all on function atlas.ledger_commercial_pricing_policy_at_v1(uuid,text,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_pricing_policy_at_v1(uuid,text,timestamptz)
  to service_role;

revoke all on function atlas.record_ledger_commercial_market_observation_service_v1(
  uuid,uuid,uuid,text,text,jsonb,jsonb,timestamptz,timestamptz,timestamptz,
  numeric,text,numeric,text,text,numeric,text,jsonb,text,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_ledger_commercial_market_observation_service_v1(
  uuid,uuid,uuid,text,text,jsonb,jsonb,timestamptz,timestamptz,timestamptz,
  numeric,text,numeric,text,text,numeric,text,jsonb,text,text,jsonb,jsonb
) to service_role;

revoke all on function atlas.ledger_commercial_quote_envelope_v1(uuid,numeric,text)
  from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_quote_envelope_v1(uuid,numeric,text)
  to service_role;

revoke all on function atlas.ledger_commercial_quote_evaluate_v1(uuid,numeric,numeric,numeric,text)
  from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_quote_evaluate_v1(uuid,numeric,numeric,numeric,text)
  to service_role;

revoke all on function atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
  uuid,text,jsonb,uuid,numeric,numeric,text,jsonb,jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
  uuid,text,jsonb,uuid,numeric,numeric,text,jsonb,jsonb,jsonb,jsonb
) to service_role;

comment on table atlas.ledger_commercial_pricing_policies is
  'Effective-dated Ledger-scoped commercial pricing policy. Does not create customer terms by itself.';
comment on table atlas.ledger_commercial_market_observations is
  'Append-only outside-market price evidence. A benchmark observation is not automatically acquirable supply.';
comment on table atlas.ledger_commercial_quote_evaluation_receipts is
  'Append-only provenance for deterministic quote eligibility evaluation. Not a customer offer.';
comment on table atlas.ledger_commercial_quote_evaluation_benchmarks is
  'Market-observation evidence links used to calculate one quote-evaluation benchmark basket.';

commit;
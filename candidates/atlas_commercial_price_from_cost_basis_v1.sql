begin;

create or replace function atlas.commercial_price_from_cost_basis_v1(
  p_quantity numeric,
  p_unit text,
  p_total_cost numeric,
  p_currency text,
  p_policy jsonb,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_unit text;
  v_currency text;
  v_method text;
  v_rate numeric;
  v_min_unit_price numeric:=null;
  v_rounding jsonb;
  v_round_mode text:=null;
  v_round_increment numeric:=null;

  v_unit_cost numeric;
  v_raw_unit_price numeric;
  v_base_unit_price numeric;
  v_proposed_unit_price numeric;
  v_proposed_total numeric;
  v_gross_profit numeric;
  v_realized_margin numeric;
  v_realized_markup numeric;
begin
  if p_quantity is null or p_quantity<=0 then
    raise exception 'Pricing quantity must be greater than zero.'
      using errcode='22023';
  end if;

  v_unit:=nullif(btrim(coalesce(p_unit,'')),'');
  if v_unit is null then
    raise exception 'Pricing unit is required.'
      using errcode='22023';
  end if;

  if p_total_cost is null or p_total_cost<0 then
    raise exception 'Pricing total cost basis must be nonnegative.'
      using errcode='22023';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Pricing currency must be a three-letter uppercase code.'
      using errcode='22023';
  end if;

  if p_policy is null or jsonb_typeof(p_policy)<>'object' then
    raise exception 'Pricing policy input must be a JSON object.'
      using errcode='22023';
  end if;

  if p_policy->>'contractVersion'<>'commercial_price_policy_input_v1' then
    raise exception 'Pricing policy contractVersion must be commercial_price_policy_input_v1.'
      using errcode='22023';
  end if;

  if p_context is null or jsonb_typeof(p_context)<>'object' then
    raise exception 'Pricing context must be a JSON object.'
      using errcode='22023';
  end if;

  v_method:=lower(btrim(coalesce(p_policy->>'method','')));
  if v_method not in ('gross_margin','markup') then
    raise exception 'Pricing method must be gross_margin or markup.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_policy->'rate')<>'number' then
    raise exception 'Pricing policy rate must be numeric.'
      using errcode='22023';
  end if;
  v_rate:=(p_policy->>'rate')::numeric;

  if v_method='gross_margin' and (v_rate<0 or v_rate>=1) then
    raise exception 'Gross-margin rate must be >= 0 and < 1.'
      using errcode='22023';
  end if;

  if v_method='markup' and v_rate<0 then
    raise exception 'Markup rate must be >= 0.'
      using errcode='22023';
  end if;

  if p_policy ? 'minimumUnitPrice' then
    if jsonb_typeof(p_policy->'minimumUnitPrice')<>'number' then
      raise exception 'minimumUnitPrice must be numeric when present.'
        using errcode='22023';
    end if;
    v_min_unit_price:=(p_policy->>'minimumUnitPrice')::numeric;
    if v_min_unit_price<0 then
      raise exception 'minimumUnitPrice must be nonnegative.'
        using errcode='22023';
    end if;
  end if;

  if p_policy ? 'currency' then
    if upper(btrim(coalesce(p_policy->>'currency','')))<>v_currency then
      raise exception 'Policy currency % does not match cost-basis currency %.',
        p_policy->>'currency',v_currency
        using errcode='22023';
    end if;
  end if;

  if p_policy ? 'rounding' then
    v_rounding:=p_policy->'rounding';
    if jsonb_typeof(v_rounding)<>'object' then
      raise exception 'rounding must be an object when present.'
        using errcode='22023';
    end if;

    v_round_mode:=lower(btrim(coalesce(v_rounding->>'mode','')));
    if v_round_mode<>'ceil' then
      raise exception 'V1 rounding mode must be ceil.'
        using errcode='22023';
    end if;

    if jsonb_typeof(v_rounding->'increment')<>'number' then
      raise exception 'rounding.increment must be numeric.'
        using errcode='22023';
    end if;

    v_round_increment:=(v_rounding->>'increment')::numeric;
    if v_round_increment<=0 then
      raise exception 'rounding.increment must be greater than zero.'
        using errcode='22023';
    end if;
  end if;

  v_unit_cost:=p_total_cost/p_quantity;

  if v_method='gross_margin' then
    v_raw_unit_price:=v_unit_cost/(1-v_rate);
  else
    v_raw_unit_price:=v_unit_cost*(1+v_rate);
  end if;

  v_base_unit_price:=greatest(
    v_raw_unit_price,
    coalesce(v_min_unit_price,v_raw_unit_price)
  );

  if v_round_increment is not null then
    v_proposed_unit_price:=ceil(v_base_unit_price/v_round_increment)*v_round_increment;
  else
    v_proposed_unit_price:=v_base_unit_price;
  end if;

  v_proposed_total:=v_proposed_unit_price*p_quantity;
  v_gross_profit:=v_proposed_total-p_total_cost;

  if v_proposed_total<>0 then
    v_realized_margin:=v_gross_profit/v_proposed_total;
  end if;

  if p_total_cost<>0 then
    v_realized_markup:=v_gross_profit/p_total_cost;
  end if;

  return jsonb_build_object(
    'contractVersion','commercial_price_from_cost_basis_v1',
    'state','priced',
    'currency',v_currency,
    'quantity',p_quantity,
    'unit',v_unit,
    'totalCostBasis',p_total_cost,
    'costPerUnit',v_unit_cost,
    'policy',jsonb_build_object(
      'contractVersion','commercial_price_policy_input_v1',
      'method',v_method,
      'rate',v_rate,
      'minimumUnitPrice',v_min_unit_price,
      'rounding',case
        when v_round_increment is null then null
        else jsonb_build_object('mode','ceil','increment',v_round_increment)
      end
    ),
    'rawUnitPrice',v_raw_unit_price,
    'proposedUnitPrice',v_proposed_unit_price,
    'proposedTotal',v_proposed_total,
    'grossProfitAgainstCostBasis',v_gross_profit,
    'realizedGrossMarginAgainstCostBasis',v_realized_margin,
    'realizedMarkupAgainstCostBasis',v_realized_markup,
    'context',p_context,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'costBasisMustBeGovernedUpstream',true,
      'doesNotPersistPricingPolicy',true,
      'doesNotCreateStandingPrice',true,
      'doesNotCreateCommercialOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_pooled_commercial_price_protection_v1","purpose":"Shared pure pricing law from an explicit governed cost basis and explicit pricing policy.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;

begin;

create or replace function atlas.commercial_price_evaluate_v1(
  p_fulfillment_packet jsonb,
  p_policy jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_position jsonb;
  v_currency text;
  v_total_cost numeric;
  v_quantity numeric;
  v_unit text;
  v_price jsonb;
begin
  v_position:=atlas.fulfillment_composition_position_v1(p_fulfillment_packet);

  if v_position->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','invalid_fulfillment_composition',
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'blockedCreatesNoCommercialTerms',true
      )
    );
  end if;

  if v_position->>'coverageState'<>'exact' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','fulfillment_not_exactly_covered',
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'underOrOverCoverageDoesNotBecomePrice',true
      )
    );
  end if;

  if v_position->>'economicState'<>'known' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason',case v_position->>'economicState'
        when 'unresolved' then 'required_cost_unresolved'
        when 'known_multi_currency' then 'multi_currency_without_governed_conversion'
        when 'no_cost_evidence' then 'no_cost_evidence'
        else 'economic_position_not_known'
      end,
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'unknownCostIsNeverZero',true,
        'noImplicitFxConversion',true
      )
    );
  end if;

  select key,(value)::numeric
  into v_currency,v_total_cost
  from jsonb_each_text(v_position->'knownCostTotalsByCurrency')
  order by key
  limit 1;

  if v_currency is null or v_total_cost is null then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','known_economic_position_missing_single_currency_total',
      'fulfillmentPosition',v_position
    );
  end if;

  v_quantity:=(v_position->>'requiredQuantity')::numeric;
  v_unit:=v_position->>'unit';

  v_price:=atlas.commercial_price_from_cost_basis_v1(
    v_quantity,
    v_unit,
    v_total_cost,
    v_currency,
    p_policy,
    jsonb_build_object(
      'source','fulfillment_composition_position_v1',
      'planKey',v_position->>'planKey'
    )
  );

  return jsonb_build_object(
    'contractVersion','commercial_price_evaluation_v1',
    'state','priced',
    'currency',v_price->>'currency',
    'quantity',(v_price->>'quantity')::numeric,
    'unit',v_price->>'unit',
    'totalKnownFulfillmentCost',(v_price->>'totalCostBasis')::numeric,
    'costPerUnit',(v_price->>'costPerUnit')::numeric,
    'policy',v_price->'policy',
    'rawUnitPrice',(v_price->>'rawUnitPrice')::numeric,
    'proposedUnitPrice',(v_price->>'proposedUnitPrice')::numeric,
    'proposedTotal',(v_price->>'proposedTotal')::numeric,
    'grossProfit',(v_price->>'grossProfitAgainstCostBasis')::numeric,
    'realizedGrossMargin',
      case when v_price->>'realizedGrossMarginAgainstCostBasis' is null then null
           else (v_price->>'realizedGrossMarginAgainstCostBasis')::numeric end,
    'realizedMarkup',
      case when v_price->>'realizedMarkupAgainstCostBasis' is null then null
           else (v_price->>'realizedMarkupAgainstCostBasis')::numeric end,
    'sharedPriceResult',v_price,
    'fulfillmentPosition',v_position,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sharedPricingLaw',true,
      'derivedTermsOnly',true,
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

revoke all on function atlas.commercial_price_evaluate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_price_evaluate_v1(jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.commercial_price_evaluate_v1(jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_price_evaluation_v1","purpose":"Read-only deterministic price evaluation from exact known fulfillment economics and explicit policy input.","classificationRuleVersion":3}'::jsonb,
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

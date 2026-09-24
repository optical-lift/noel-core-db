begin;

create or replace function atlas.work_requirement_pool_price_evaluate_v1(
  p_pool_packet jsonb,
  p_policy jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_pool jsonb;
  v_basis text;
  v_pricing_policy jsonb;

  v_known_pool_cost numeric;
  v_currency text;
  v_output_quantity numeric;
  v_planned_quantity numeric;
  v_excess_quantity numeric;
  v_unit text;

  v_source_price jsonb;
  v_full_price jsonb;
  v_selected_price jsonb;

  v_source_current_revenue numeric;
  v_source_whole_pool_profit numeric;
  v_source_whole_pool_margin numeric;

  v_full_current_revenue numeric;
  v_full_whole_pool_profit numeric;
  v_full_whole_pool_margin numeric;

  v_selected_current_revenue numeric;
  v_selected_whole_pool_profit numeric;
  v_selected_whole_pool_margin numeric;

  v_requirement_prices jsonb:='[]'::jsonb;
begin
  v_pool:=atlas.work_requirement_pool_position_v1(p_pool_packet);

  if v_pool->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','invalid_pool_position',
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'blockedCreatesNoCommercialTerms',true
      )
    );
  end if;

  if v_pool->>'demandPosition'<>'all_covered' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','aggregate_demand_not_fully_covered',
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'incompleteFulfillmentDoesNotBecomeCustomerPrice',true
      )
    );
  end if;

  if v_pool->>'economicState'<>'known' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason',case v_pool->>'economicState'
        when 'unresolved' then 'required_pool_cost_unresolved'
        when 'known_multi_currency' then 'multi_currency_without_governed_conversion'
        when 'no_cost_evidence' then 'no_pool_cost_evidence'
        else 'pool_economic_position_not_known'
      end,
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'unknownCostIsNeverZero',true,
        'noImplicitFxConversion',true
      )
    );
  end if;

  if p_policy is null or jsonb_typeof(p_policy)<>'object' then
    raise exception 'Pooled pricing policy must be a JSON object.'
      using errcode='22023';
  end if;

  if p_policy->>'contractVersion'<>'work_requirement_pool_price_policy_v1' then
    raise exception 'Pooled pricing policy contractVersion must be work_requirement_pool_price_policy_v1.'
      using errcode='22023';
  end if;

  v_basis:=lower(btrim(coalesce(p_policy->>'costRecoveryBasis','')));
  if v_basis not in ('full_pool_on_planned_output','source_output') then
    raise exception 'costRecoveryBasis must be full_pool_on_planned_output or source_output.'
      using errcode='22023';
  end if;

  v_pricing_policy:=p_policy->'pricingPolicy';
  if v_pricing_policy is null or jsonb_typeof(v_pricing_policy)<>'object' then
    raise exception 'pricingPolicy must be an explicit JSON object.'
      using errcode='22023';
  end if;

  v_known_pool_cost:=(v_pool->>'knownPoolCost')::numeric;
  v_currency:=v_pool->>'knownCostCurrency';
  v_output_quantity:=(v_pool->>'outputQuantity')::numeric;
  v_planned_quantity:=(v_pool->>'plannedOutputQuantity')::numeric;
  v_excess_quantity:=(v_pool->>'excessOutputQuantity')::numeric;
  v_unit:=v_pool->>'outputUnit';

  if v_planned_quantity<=0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','no_planned_output',
      'poolPosition',v_pool
    );
  end if;

  v_source_price:=atlas.commercial_price_from_cost_basis_v1(
    v_output_quantity,
    v_unit,
    v_known_pool_cost,
    v_currency,
    v_pricing_policy,
    jsonb_build_object(
      'source','work_requirement_pool_position_v1',
      'poolKey',v_pool->>'poolKey',
      'costRecoveryBasis','source_output',
      'scenarioOnly',(v_excess_quantity>0)
    )
  );

  v_full_price:=atlas.commercial_price_from_cost_basis_v1(
    v_planned_quantity,
    v_unit,
    v_known_pool_cost,
    v_currency,
    v_pricing_policy,
    jsonb_build_object(
      'source','work_requirement_pool_position_v1',
      'poolKey',v_pool->>'poolKey',
      'costRecoveryBasis','full_pool_on_planned_output',
      'scenarioOnly',false
    )
  );

  v_source_current_revenue:=(v_source_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_source_whole_pool_profit:=v_source_current_revenue-v_known_pool_cost;
  if v_source_current_revenue<>0 then
    v_source_whole_pool_margin:=v_source_whole_pool_profit/v_source_current_revenue;
  end if;

  v_full_current_revenue:=(v_full_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_full_whole_pool_profit:=v_full_current_revenue-v_known_pool_cost;
  if v_full_current_revenue<>0 then
    v_full_whole_pool_margin:=v_full_whole_pool_profit/v_full_current_revenue;
  end if;

  if v_basis='source_output' and v_excess_quantity>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','excess_recovery_not_established',
      'selectedCostRecoveryBasis',v_basis,
      'poolPosition',v_pool,
      'scenarioComparison',jsonb_build_object(
        'sourceOutput',jsonb_build_object(
          'protectionState','unprotected_without_excess_recovery',
          'priceResult',v_source_price,
          'currentPlannedRevenue',v_source_current_revenue,
          'wholePoolGrossProfitIfExcessRecoversZero',v_source_whole_pool_profit,
          'wholePoolGrossMarginIfExcessRecoversZero',v_source_whole_pool_margin
        ),
        'fullPoolOnPlannedOutput',jsonb_build_object(
          'protectionState','protected_against_zero_excess_recovery',
          'priceResult',v_full_price,
          'currentPlannedRevenue',v_full_current_revenue,
          'wholePoolGrossProfit',v_full_whole_pool_profit,
          'wholePoolGrossMargin',v_full_whole_pool_margin
        )
      ),
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'futureExcessSaleIsNotRecoveryEvidence',true,
        'blockedCreatesNoCommercialTerms',true,
        'doesNotCreateOfferSnapshot',true,
        'doesNotCreateOrder',true,
        'doesNotPurchase',true
      )
    );
  end if;

  if v_basis='source_output' then
    v_selected_price:=v_source_price;
  else
    v_selected_price:=v_full_price;
  end if;

  v_selected_current_revenue:=(v_selected_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_selected_whole_pool_profit:=v_selected_current_revenue-v_known_pool_cost;
  if v_selected_current_revenue<>0 then
    v_selected_whole_pool_margin:=v_selected_whole_pool_profit/v_selected_current_revenue;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'useKey',rp.value->>'useKey',
        'workRequirementId',rp.value->>'workRequirementId',
        'plannedQuantity',(rp.value->>'plannedFromPool')::numeric,
        'unit',rp.value->>'unit',
        'proposedUnitPrice',(v_selected_price->>'proposedUnitPrice')::numeric,
        'proposedTotal',
          (rp.value->>'plannedFromPool')::numeric*(v_selected_price->>'proposedUnitPrice')::numeric
      )
      order by rp.value->>'useKey'
    ),
    '[]'::jsonb
  )
  into v_requirement_prices
  from jsonb_array_elements(v_pool->'requirementPositions') as rp(value);

  return jsonb_build_object(
    'contractVersion','work_requirement_pool_price_evaluation_v1',
    'state','priced',
    'organizationId',v_pool->'organizationId',
    'poolKey',v_pool->>'poolKey',
    'selectedCostRecoveryBasis',v_basis,
    'currency',v_currency,
    'unit',v_unit,
    'knownPoolCost',v_known_pool_cost,
    'plannedOutputQuantity',v_planned_quantity,
    'excessOutputQuantity',v_excess_quantity,
    'protectedCostBasisQuantity',(v_selected_price->>'quantity')::numeric,
    'protectedCostBasis',(v_selected_price->>'totalCostBasis')::numeric,
    'protectedCostPerUnit',(v_selected_price->>'costPerUnit')::numeric,
    'protectedProposedUnitPrice',(v_selected_price->>'proposedUnitPrice')::numeric,
    'protectedProposedRevenueOnPlannedOutput',v_selected_current_revenue,
    'protectedWholePoolGrossProfit',v_selected_whole_pool_profit,
    'protectedWholePoolGrossMargin',v_selected_whole_pool_margin,
    'selectedPriceResult',v_selected_price,
    'requirementPrices',v_requirement_prices,
    'scenarioComparison',jsonb_build_object(
      'sourceOutput',jsonb_build_object(
        'protectionState',case
          when v_excess_quantity=0 then 'protected_no_excess'
          else 'unprotected_without_excess_recovery'
        end,
        'priceResult',v_source_price,
        'currentPlannedRevenue',v_source_current_revenue,
        'wholePoolGrossProfitIfExcessRecoversZero',v_source_whole_pool_profit,
        'wholePoolGrossMarginIfExcessRecoversZero',v_source_whole_pool_margin
      ),
      'fullPoolOnPlannedOutput',jsonb_build_object(
        'protectionState','protected_against_zero_excess_recovery',
        'priceResult',v_full_price,
        'currentPlannedRevenue',v_full_current_revenue,
        'wholePoolGrossProfit',v_full_whole_pool_profit,
        'wholePoolGrossMargin',v_full_whole_pool_margin
      )
    ),
    'poolPosition',v_pool,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'costRecoveryBasisIsExplicit',true,
      'futureExcessSaleIsNotRecoveryEvidence',true,
      'onePoolWidePolicyEvaluated',true,
      'requirementPricesAreDerivedNotOffers',true,
      'doesNotPersistPricingPolicy',true,
      'doesNotCreateStandingPrice',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotCreateAllocation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_pooled_commercial_price_protection_v1","purpose":"Read-only protected pooled pricing from explicit break-bulk economics, explicit cost-recovery basis, and shared pricing law.","classificationRuleVersion":3}'::jsonb,
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

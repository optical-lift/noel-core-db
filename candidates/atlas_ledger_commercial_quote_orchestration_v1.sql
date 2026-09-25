begin;

create or replace function atlas.ledger_commercial_pricing_policy_input_v1(
  p_policy_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_policy atlas.ledger_commercial_pricing_policies%rowtype;
  v_result jsonb;
  v_rounding jsonb;
  v_min_unit_price jsonb;
begin
  select * into v_policy
  from atlas.ledger_commercial_pricing_policies
  where id=p_policy_id;

  if v_policy.id is null then
    raise exception 'Pricing policy not found.' using errcode='22023';
  end if;

  v_result:=jsonb_build_object(
    'contractVersion','commercial_price_policy_input_v1',
    'method',v_policy.pricing_method,
    'rate',v_policy.target_rate
  );

  if v_policy.currency is not null then
    v_result:=v_result||jsonb_build_object('currency',v_policy.currency);
  end if;

  if v_policy.cost_basis_policy ? 'rounding' then
    v_rounding:=v_policy.cost_basis_policy->'rounding';
    if jsonb_typeof(v_rounding)<>'object' then
      raise exception 'cost_basis_policy.rounding must be an object when present.'
        using errcode='23514';
    end if;
    v_result:=v_result||jsonb_build_object('rounding',v_rounding);
  end if;

  if v_policy.cost_basis_policy ? 'minimumUnitPrice' then
    v_min_unit_price:=v_policy.cost_basis_policy->'minimumUnitPrice';
    if jsonb_typeof(v_min_unit_price)<>'number' then
      raise exception 'cost_basis_policy.minimumUnitPrice must be numeric when present.'
        using errcode='23514';
    end if;
    v_result:=v_result||jsonb_build_object('minimumUnitPrice',v_min_unit_price);
  end if;

  return v_result||jsonb_build_object(
    'policyRef',jsonb_build_object(
      'policyId',v_policy.id,
      'ledgerId',v_policy.ledger_id,
      'policyKey',v_policy.policy_key,
      'effectiveFrom',v_policy.effective_from,
      'effectiveUntil',v_policy.effective_until
    )
  );
end
$function$;


create or replace function atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_at timestamptz,
  p_currency text,
  p_benchmark_lines jsonb default '[]'::jsonb
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
  v_line jsonb;
  v_obs atlas.ledger_commercial_market_observations%rowtype;
  v_obs_id uuid;
  v_amount numeric;
  v_total numeric:=null;
  v_count integer:=0;
  v_envelope jsonb;
  v_lines jsonb:='[]'::jsonb;
begin
  if p_at is null then
    raise exception 'Evaluation time is required.' using errcode='22023';
  end if;
  if btrim(coalesce(p_policy_key,''))='' then
    raise exception 'Policy key is required.' using errcode='22023';
  end if;
  if p_benchmark_lines is null or jsonb_typeof(p_benchmark_lines)<>'array' then
    raise exception 'Benchmark lines must be a JSON array.' using errcode='22023';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Currency must be a three-letter uppercase code.'
      using errcode='22023';
  end if;

  select * into v_policy
  from atlas.ledger_commercial_pricing_policies p
  where p.ledger_id=p_ledger_id
    and p.policy_key=btrim(p_policy_key)
    and p.policy_state<>'withdrawn'
    and p.effective_from<=p_at
    and (p.effective_until is null or p.effective_until>p_at)
  order by p.effective_from desc
  limit 1;

  if v_policy.id is null then
    return jsonb_build_object(
      'contractVersion','ledger_commercial_benchmark_envelope_from_observations_v1',
      'state','incomplete_evidence',
      'reason','pricing_policy_not_found',
      'ledgerId',p_ledger_id,
      'policyKey',btrim(p_policy_key),
      'at',p_at,
      'currency',v_currency
    );
  end if;

  if v_policy.currency is not null and v_policy.currency<>v_currency then
    raise exception 'Policy currency does not match benchmark currency.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_benchmark_lines)
  loop
    if jsonb_typeof(v_line)<>'object'
       or nullif(btrim(coalesce(v_line->>'marketObservationId','')),'') is null
       or jsonb_typeof(v_line->'benchmarkAmount')<>'number' then
      raise exception 'Each benchmark line requires marketObservationId and numeric benchmarkAmount.'
        using errcode='22023';
    end if;

    v_obs_id:=(v_line->>'marketObservationId')::uuid;
    v_amount:=(v_line->>'benchmarkAmount')::numeric;
    if v_amount<0 then
      raise exception 'Benchmark amount must be nonnegative.'
        using errcode='22023';
    end if;

    select * into v_obs
    from atlas.ledger_commercial_market_observations
    where id=v_obs_id;

    if v_obs.id is null or v_obs.ledger_id<>p_ledger_id then
      raise exception 'Every benchmark observation must belong to the requested Ledger.'
        using errcode='23514';
    end if;

    if v_obs.observed_at>p_at
       or (v_obs.effective_from is not null and v_obs.effective_from>p_at)
       or (v_obs.effective_until is not null and v_obs.effective_until<p_at) then
      raise exception 'Benchmark observation is not temporally valid for the evaluation time.'
        using errcode='23514';
    end if;

    if exists(
      select 1
      from atlas.ledger_commercial_market_observations newer
      where newer.ledger_id=p_ledger_id
        and newer.supersedes_observation_id=v_obs.id
        and newer.observed_at<=p_at
    ) then
      raise exception 'Superseded benchmark observation cannot be used for this evaluation time.'
        using errcode='23514';
    end if;

    if v_obs.price_basis_state='unknown'
       or v_obs.currency is null
       or v_obs.currency<>v_currency
       or v_obs.price_quantity is null
       or v_obs.price_unit is null then
      raise exception 'Computational benchmark requires known price basis and matching currency.'
        using errcode='23514';
    end if;

    v_total:=coalesce(v_total,0)+v_amount;
    v_count:=v_count+1;
    v_lines:=v_lines||jsonb_build_array(
      jsonb_build_object(
        'marketObservationId',v_obs.id,
        'sourceLabel',v_obs.source_label,
        'observationRole',v_obs.observation_role,
        'benchmarkAmount',v_amount,
        'currency',v_currency,
        'lineRef',coalesce(v_line->'lineRef','{}'::jsonb),
        'metadata',coalesce(v_line->'metadata','{}'::jsonb)
      )
    );
  end loop;

  v_envelope:=atlas.ledger_commercial_quote_envelope_v1(
    v_policy.id,
    v_total,
    v_currency
  );

  return jsonb_build_object(
    'contractVersion','ledger_commercial_benchmark_envelope_from_observations_v1',
    'state',v_envelope->>'state',
    'reason',v_envelope->>'reason',
    'ledgerId',p_ledger_id,
    'policyId',v_policy.id,
    'policyKey',v_policy.policy_key,
    'at',p_at,
    'currency',v_currency,
    'benchmarkLineCount',v_count,
    'benchmarkTotal',v_total,
    'benchmarkLines',v_lines,
    'envelope',v_envelope,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'benchmarkAmountsRemainCallerCalculatedFromSourceBackedTerms',true,
      'temporalValidityChecked',true,
      'supersededObservationBlocked',true,
      'doesNotChooseSupplier',true,
      'doesNotCreateOffer',true,
      'doesNotAuthorizePurchase',true
    )
  );
end
$function$;


create or replace function atlas.ledger_commercial_quote_packet_evaluate_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_at timestamptz,
  p_quote_packet jsonb,
  p_benchmark_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_currency text;
  v_protected_cost numeric;
  v_quote_total numeric;
  v_line jsonb;
  v_line_cost_sum numeric:=0;
  v_line_count integer:=0;
  v_envelope_packet jsonb;
  v_envelope jsonb;
  v_eval jsonb;
begin
  if p_quote_packet is null or jsonb_typeof(p_quote_packet)<>'object' then
    raise exception 'Quote packet must be a JSON object.' using errcode='22023';
  end if;

  if p_quote_packet->>'state'<>'complete' then
    return jsonb_build_object(
      'contractVersion','ledger_commercial_quote_packet_evaluate_v1',
      'state','incomplete_evidence',
      'reason','quote_packet_incomplete',
      'ledgerId',p_ledger_id,
      'quotePacket',p_quote_packet,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'incompleteQuoteDoesNotBecomeCommerciallyEligible',true
      )
    );
  end if;

  v_currency:=upper(btrim(coalesce(p_quote_packet->>'currency','')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Complete quote packet requires a three-letter currency.'
      using errcode='23514';
  end if;

  if jsonb_typeof(p_quote_packet->'protectedCostTotal')<>'number'
     or jsonb_typeof(p_quote_packet->'wholeOrderTotal')<>'number' then
    raise exception 'Complete quote packet requires numeric protectedCostTotal and wholeOrderTotal.'
      using errcode='23514';
  end if;

  v_protected_cost:=(p_quote_packet->>'protectedCostTotal')::numeric;
  v_quote_total:=(p_quote_packet->>'wholeOrderTotal')::numeric;

  if v_protected_cost<0 or v_quote_total<=0 then
    raise exception 'Quote totals are outside permitted numeric bounds.'
      using errcode='23514';
  end if;

  if jsonb_typeof(p_quote_packet->'lines') is distinct from 'array'
     or jsonb_array_length(p_quote_packet->'lines')=0 then
    raise exception 'Complete quote packet requires a non-empty lines array.'
      using errcode='23514';
  end if;

  for v_line in select value from jsonb_array_elements(p_quote_packet->'lines')
  loop
    v_line_count:=v_line_count+1;

    if v_line->>'state'<>'priced'
       or jsonb_typeof(v_line->'totalKnownFulfillmentCost')<>'number'
       or upper(btrim(coalesce(v_line->>'currency','')))<>v_currency then
      raise exception 'Every line in a complete quote packet must be priced with known matching-currency cost.'
        using errcode='23514';
    end if;

    if (v_line->>'totalKnownFulfillmentCost')::numeric<0 then
      raise exception 'Line protected cost must be nonnegative.'
        using errcode='23514';
    end if;

    v_line_cost_sum:=v_line_cost_sum+(v_line->>'totalKnownFulfillmentCost')::numeric;
  end loop;

  if abs(v_line_cost_sum-v_protected_cost)>0.000001 then
    raise exception 'Quote packet protectedCostTotal does not equal the sum of line protected costs.'
      using errcode='23514';
  end if;

  v_envelope_packet:=atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
    p_ledger_id,p_policy_key,p_at,v_currency,p_benchmark_lines
  );

  if v_envelope_packet->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','ledger_commercial_quote_packet_evaluate_v1',
      'state','incomplete_evidence',
      'reason',coalesce(v_envelope_packet->>'reason','commercial_envelope_not_ready'),
      'ledgerId',p_ledger_id,
      'currency',v_currency,
      'protectedCostTotal',v_protected_cost,
      'wholeOrderTotal',v_quote_total,
      'commercialEnvelope',v_envelope_packet,
      'quotePacket',p_quote_packet
    );
  end if;

  v_envelope:=v_envelope_packet->'envelope';

  v_eval:=atlas.ledger_commercial_quote_evaluate_v1(
    (v_envelope_packet->>'policyId')::uuid,
    v_protected_cost,
    v_quote_total,
    case when v_envelope_packet->>'benchmarkTotal' is null
      then null else (v_envelope_packet->>'benchmarkTotal')::numeric end,
    v_currency
  );

  return jsonb_build_object(
    'contractVersion','ledger_commercial_quote_packet_evaluate_v1',
    'state','evaluated',
    'decisionState',v_eval->>'decisionState',
    'ledgerId',p_ledger_id,
    'policyId',(v_envelope_packet->>'policyId')::uuid,
    'policyKey',p_policy_key,
    'at',p_at,
    'currency',v_currency,
    'protectedCostTotal',v_protected_cost,
    'wholeOrderTotal',v_quote_total,
    'benchmarkTotal',case when v_envelope_packet->>'benchmarkTotal' is null
      then null else (v_envelope_packet->>'benchmarkTotal')::numeric end,
    'lineCount',v_line_count,
    'commercialEnvelope',v_envelope_packet,
    'evaluation',v_eval,
    'quotePacket',p_quote_packet,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'quoteCostSumVerified',true,
      'marketAndMarginGatesApplied',true,
      'doesNotCreateOffer',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true
    )
  );
end
$function$;


create or replace function atlas.record_ledger_commercial_quote_packet_receipt_service_v1(
  p_ledger_id uuid,
  p_evaluation_key text,
  p_request_ref jsonb,
  p_policy_key text,
  p_at timestamptz,
  p_quote_packet jsonb,
  p_benchmark_lines jsonb default '[]'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_result_ref jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_assessment jsonb;
  v_receipt jsonb;
begin
  v_assessment:=atlas.ledger_commercial_quote_packet_evaluate_v1(
    p_ledger_id,p_policy_key,p_at,p_quote_packet,p_benchmark_lines
  );

  if v_assessment->>'state'<>'evaluated' then
    return jsonb_build_object(
      'contractVersion','record_ledger_commercial_quote_packet_receipt_service_v1',
      'state','not_recorded',
      'reason',coalesce(v_assessment->>'reason','quote_assessment_not_complete'),
      'assessment',v_assessment,
      'truthBoundary',jsonb_build_object(
        'incompleteNumericalEvidenceDoesNotBecomeReceipt',true,
        'doesNotCreateOffer',true,
        'doesNotAuthorizePurchase',true
      )
    );
  end if;

  v_receipt:=atlas.record_ledger_commercial_quote_evaluation_receipt_service_v1(
    p_ledger_id,
    p_evaluation_key,
    p_request_ref,
    (v_assessment->>'policyId')::uuid,
    (v_assessment->>'protectedCostTotal')::numeric,
    (v_assessment->>'wholeOrderTotal')::numeric,
    v_assessment->>'currency',
    p_benchmark_lines,
    jsonb_build_object(
      'contractVersion','ledger_commercial_quote_packet_receipt_context_v1',
      'evaluatedAt',p_at,
      'quotePacket',p_quote_packet,
      'assessment',v_assessment
    ),
    coalesce(p_provenance,'{}'::jsonb),
    coalesce(p_result_ref,'{}'::jsonb)
  );

  return jsonb_build_object(
    'contractVersion','record_ledger_commercial_quote_packet_receipt_service_v1',
    'state','recorded',
    'assessment',v_assessment,
    'receipt',v_receipt,
    'truthBoundary',jsonb_build_object(
      'appendOnlyEvaluationReceipt',true,
      'doesNotCreateOffer',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true
    )
  );
end
$function$;


create or replace function atlas.feast_guild_flower_commercial_viability_from_candidates_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_at timestamptz,
  p_basket jsonb,
  p_line_candidate_sets jsonb,
  p_currency text,
  p_benchmark_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_envelope_packet jsonb;
  v_envelope jsonb;
  v_target_ceiling numeric:=null;
  v_minimum_ceiling numeric:=null;
  v_ceiling_inclusive boolean:=true;

  v_basket_key text;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_set jsonb;
  v_set_count integer;
  v_candidate jsonb;
  v_eval jsonb;
  v_evals jsonb;
  v_cheapest_eval jsonb;
  v_cheapest_cost numeric;

  v_positions jsonb:='[]'::jsonb;
  v_final_positions jsonb:='[]'::jsonb;
  v_position jsonb;
  v_candidate_viability jsonb;
  v_min_total numeric:=0;
  v_blocked_count integer:=0;
  v_target_line_ceiling numeric;
  v_minimum_line_ceiling numeric;
  v_eval_cost numeric;
  v_target_ok boolean;
  v_minimum_ok boolean;
  v_target_basket_ok boolean;
  v_minimum_basket_ok boolean;
  v_commercial_state text;
begin
  if p_basket is null
     or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;
  if jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket lines must be a non-empty array.'
      using errcode='22023';
  end if;
  if p_line_candidate_sets is null
     or jsonb_typeof(p_line_candidate_sets)<>'array' then
    raise exception 'Line candidate sets must be a JSON array.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  if v_basket_key is null then
    raise exception 'Basket key is required.' using errcode='22023';
  end if;

  v_envelope_packet:=atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
    p_ledger_id,p_policy_key,p_at,p_currency,p_benchmark_lines
  );

  if v_envelope_packet->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_commercial_viability_from_candidates_v1',
      'state','incomplete_evidence',
      'reason',coalesce(v_envelope_packet->>'reason','commercial_envelope_not_ready'),
      'commercialEnvelope',v_envelope_packet,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'doesNotChooseSupplier',true,
        'doesNotPurchase',true
      )
    );
  end if;

  v_envelope:=v_envelope_packet->'envelope';
  if v_envelope->>'targetProtectedCostCeiling' is not null then
    v_target_ceiling:=(v_envelope->>'targetProtectedCostCeiling')::numeric;
  end if;
  if v_envelope->>'minimumProtectedCostCeiling' is not null then
    v_minimum_ceiling:=(v_envelope->>'minimumProtectedCostCeiling')::numeric;
  end if;
  if v_envelope->>'marketQuoteCeilingInclusive' is not null then
    v_ceiling_inclusive:=(v_envelope->>'marketQuoteCeilingInclusive')::boolean;
  end if;

  for v_line in select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    if v_line_key is null then
      raise exception 'Every basket line requires lineKey.' using errcode='22023';
    end if;

    select count(*) into v_set_count
    from jsonb_array_elements(p_line_candidate_sets) s(value)
    where s.value->>'lineKey'=v_line_key;

    v_evals:='[]'::jsonb;
    v_cheapest_eval:=null;
    v_cheapest_cost:=null;

    if v_set_count=1 then
      select s.value into v_set
      from jsonb_array_elements(p_line_candidate_sets) s(value)
      where s.value->>'lineKey'=v_line_key
      limit 1;

      if jsonb_typeof(v_set->'candidates')='array' then
        v_line_packet:=jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true);

        for v_candidate in select value from jsonb_array_elements(v_set->'candidates')
        loop
          v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(
            v_line_packet,v_candidate
          );
          v_evals:=v_evals||jsonb_build_array(v_eval);

          if v_eval->>'state'='selectable' then
            v_eval_cost:=(v_eval->>'landedEconomicCost')::numeric;
            if v_cheapest_cost is null or v_eval_cost<v_cheapest_cost then
              v_cheapest_cost:=v_eval_cost;
              v_cheapest_eval:=v_eval;
            elsif v_eval_cost=v_cheapest_cost
              and coalesce(v_eval->'candidateRef'->>'sourceRef','')
                  <coalesce(v_cheapest_eval->'candidateRef'->>'sourceRef','') then
              v_cheapest_eval:=v_eval;
            end if;
          end if;
        end loop;
      end if;
    end if;

    if v_cheapest_eval is null then
      v_blocked_count:=v_blocked_count+1;
      v_positions:=v_positions||jsonb_build_array(
        jsonb_build_object(
          'lineKey',v_line_key,
          'state','blocked',
          'reason',case
            when v_set_count=0 then 'candidate_set_missing'
            when v_set_count>1 then 'candidate_set_duplicate'
            else 'no_selectable_candidate'
          end,
          'candidateEvaluations',v_evals
        )
      );
    else
      v_min_total:=v_min_total+v_cheapest_cost;
      v_positions:=v_positions||jsonb_build_array(
        jsonb_build_object(
          'lineKey',v_line_key,
          'state','ready',
          'cheapestLandedCost',v_cheapest_cost,
          'currency',v_cheapest_eval->>'currency',
          'cheapestCandidateRef',v_cheapest_eval->'candidateRef',
          'candidateEvaluations',v_evals
        )
      );
    end if;
  end loop;

  if v_blocked_count>0 then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_commercial_viability_from_candidates_v1',
      'state','incomplete',
      'basketKey',v_basket_key,
      'blockedLineCount',v_blocked_count,
      'commercialEnvelope',v_envelope_packet,
      'linePositions',v_positions,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'minimumFeasibleCostNotClaimedUntilEveryLineHasCandidate',true,
        'doesNotChooseSupplier',true,
        'doesNotPurchase',true
      )
    );
  end if;

  v_target_basket_ok:=case
    when v_target_ceiling is null then true
    when v_ceiling_inclusive then v_min_total<=v_target_ceiling
    else v_min_total<v_target_ceiling
  end;

  v_minimum_basket_ok:=case
    when v_minimum_ceiling is null then true
    when v_ceiling_inclusive then v_min_total<=v_minimum_ceiling
    else v_min_total<v_minimum_ceiling
  end;

  v_commercial_state:=case
    when v_target_ceiling is null and v_minimum_ceiling is null then 'unbounded_by_market_gate'
    when v_target_basket_ok then 'target_viable'
    when v_minimum_basket_ok then 'minimum_only'
    else 'blocked'
  end;

  for v_position in select value from jsonb_array_elements(v_positions)
  loop
    v_target_line_ceiling:=case when v_target_ceiling is null then null
      else v_target_ceiling-(v_min_total-(v_position->>'cheapestLandedCost')::numeric) end;
    v_minimum_line_ceiling:=case when v_minimum_ceiling is null then null
      else v_minimum_ceiling-(v_min_total-(v_position->>'cheapestLandedCost')::numeric) end;

    v_candidate_viability:='[]'::jsonb;
    for v_eval in select value from jsonb_array_elements(v_position->'candidateEvaluations')
    loop
      if v_eval->>'state'='selectable' then
        v_eval_cost:=(v_eval->>'landedEconomicCost')::numeric;

        v_target_ok:=case
          when v_target_line_ceiling is null then true
          when v_ceiling_inclusive then v_eval_cost<=v_target_line_ceiling
          else v_eval_cost<v_target_line_ceiling
        end;

        v_minimum_ok:=case
          when v_minimum_line_ceiling is null then true
          when v_ceiling_inclusive then v_eval_cost<=v_minimum_line_ceiling
          else v_eval_cost<v_minimum_line_ceiling
        end;

        v_candidate_viability:=v_candidate_viability||jsonb_build_array(
          jsonb_build_object(
            'candidateRef',v_eval->'candidateRef',
            'sourcePreferenceTier',v_eval->>'sourcePreferenceTier',
            'landedEconomicCost',v_eval_cost,
            'currency',v_eval->>'currency',
            'targetCommerciallyViableWithOtherLinesAtCheapest',v_target_ok,
            'minimumCommerciallyViableWithOtherLinesAtCheapest',v_minimum_ok
          )
        );
      end if;
    end loop;

    v_final_positions:=v_final_positions||jsonb_build_array(
      v_position||jsonb_build_object(
        'targetLineCostCeiling',v_target_line_ceiling,
        'minimumLineCostCeiling',v_minimum_line_ceiling,
        'ceilingInclusive',v_ceiling_inclusive,
        'candidateCommercialViability',v_candidate_viability
      )
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_commercial_viability_from_candidates_v1',
    'state','ready',
    'commercialState',v_commercial_state,
    'basketKey',v_basket_key,
    'currency',upper(btrim(p_currency)),
    'minimumFeasibleBasketCost',v_min_total,
    'targetProtectedCostCeiling',v_target_ceiling,
    'minimumProtectedCostCeiling',v_minimum_ceiling,
    'ceilingInclusive',v_ceiling_inclusive,
    'targetHeadroom',case when v_target_ceiling is null then null else v_target_ceiling-v_min_total end,
    'minimumHeadroom',case when v_minimum_ceiling is null then null else v_minimum_ceiling-v_min_total end,
    'commercialEnvelope',v_envelope_packet,
    'linePositions',v_final_positions,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'minimumFeasibleBasketUsesCheapestSelectableCandidatePerLine',true,
      'lineHeadroomAssumesOtherLinesRemainAtCheapest',true,
      'multiplePreferenceUpgradesMustBeRecheckedAsWholeBasket',true,
      'doesNotChooseFinalSupplierPlan',true,
      'doesNotReserve',true,
      'doesNotPurchase',true,
      'doesNotCreateOffer',true
    )
  );
end
$function$;


create or replace function atlas.feast_guild_flower_ledger_quote_prepare_v1(
  p_basket jsonb,
  p_selected_line_plans jsonb,
  p_pricing_policy jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_basket_key text;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_description text;
  v_quantity numeric;
  v_unit text;
  v_plan jsonb;
  v_plan_count integer;
  v_eval jsonb;
  v_price jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_blocking jsonb:='[]'::jsonb;
  v_line_result jsonb;
  v_line_count integer:=0;
  v_priced_count integer:=0;
  v_blocked_count integer:=0;
  v_currency text:=null;
  v_cost_total numeric:=0;
  v_quote_total numeric:=0;
begin
  if p_basket is null
     or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;
  if jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket lines must be a non-empty array.'
      using errcode='22023';
  end if;
  if p_selected_line_plans is null
     or jsonb_typeof(p_selected_line_plans)<>'array' then
    raise exception 'Selected line plans must be a JSON array.'
      using errcode='22023';
  end if;
  if p_pricing_policy is null
     or jsonb_typeof(p_pricing_policy)<>'object'
     or p_pricing_policy->>'contractVersion'<>'commercial_price_policy_input_v1' then
    raise exception 'Pricing policy must use commercial_price_policy_input_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  if v_basket_key is null then
    raise exception 'Basket key is required.' using errcode='22023';
  end if;

  for v_line in select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_count:=v_line_count+1;
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_description:=nullif(btrim(coalesce(v_line->>'description','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_description is null or v_unit is null
       or jsonb_typeof(v_line->'quantity')<>'number' then
      raise exception 'Every basket line requires lineKey, description, numeric quantity, and unit.'
        using errcode='22023';
    end if;
    v_quantity:=(v_line->>'quantity')::numeric;
    if v_quantity<=0 then
      raise exception 'Basket line quantity must be greater than zero.'
        using errcode='22023';
    end if;

    select count(*) into v_plan_count
    from jsonb_array_elements(p_selected_line_plans) p(value)
    where p.value->>'lineKey'=v_line_key;

    if v_plan_count<>1 then
      v_blocked_count:=v_blocked_count+1;
      v_line_result:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'state','blocked',
        'requestedQuantity',v_quantity,
        'unit',v_unit,
        'blockingReasons',jsonb_build_array(
          jsonb_build_object(
            'reason',case when v_plan_count=0
              then 'missing_selected_line_plan'
              else 'multiple_selected_line_plans' end,
            'matchingPlanCount',v_plan_count
          )
        )
      );
      v_lines:=v_lines||jsonb_build_array(v_line_result);
      continue;
    end if;

    select p.value into v_plan
    from jsonb_array_elements(p_selected_line_plans) p(value)
    where p.value->>'lineKey'=v_line_key
    limit 1;

    v_line_packet:=jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true);
    v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(v_line_packet,v_plan);

    if v_eval->>'state'<>'selectable' then
      v_blocked_count:=v_blocked_count+1;
      v_line_result:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'state','blocked',
        'requestedQuantity',v_quantity,
        'unit',v_unit,
        'selectedCandidateRef',v_plan->'candidateRef',
        'candidateEvaluation',v_eval,
        'blockingReasons',coalesce(v_eval->'reasons','[]'::jsonb)
      );
      v_lines:=v_lines||jsonb_build_array(v_line_result);
      continue;
    end if;

    v_price:=atlas.commercial_price_evaluate_v1(
      v_plan->'fulfillmentPacket',
      p_pricing_policy-'policyRef'
    );

    if v_price->>'state'<>'priced' then
      v_blocked_count:=v_blocked_count+1;
      v_line_result:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'state','blocked',
        'requestedQuantity',v_quantity,
        'unit',v_unit,
        'selectedCandidateRef',v_plan->'candidateRef',
        'candidateEvaluation',v_eval,
        'pricing',v_price,
        'blockingReasons',jsonb_build_array(
          jsonb_build_object('reason','line_pricing_blocked','pricingReason',v_price->>'reason')
        )
      );
      v_lines:=v_lines||jsonb_build_array(v_line_result);
      continue;
    end if;

    if v_currency is null then
      v_currency:=v_price->>'currency';
    elsif v_currency is distinct from v_price->>'currency' then
      raise exception 'Whole basket uses more than one pricing currency.'
        using errcode='23514';
    end if;

    v_priced_count:=v_priced_count+1;
    v_cost_total:=v_cost_total+(v_price->>'totalKnownFulfillmentCost')::numeric;
    v_quote_total:=v_quote_total+(v_price->>'proposedTotal')::numeric;

    v_line_result:=jsonb_build_object(
      'lineKey',v_line_key,
      'description',v_description,
      'state','priced',
      'requestedQuantity',v_quantity,
      'unit',v_unit,
      'selectedCandidateRef',v_plan->'candidateRef',
      'selectionBasis',coalesce(v_plan->'selectionBasis','{}'::jsonb),
      'customerFacingSourceFacts',coalesce(v_plan->'customerFacingSourceFacts','{}'::jsonb),
      'candidateEvaluation',v_eval,
      'fulfillmentPlanKey',v_plan->'fulfillmentPacket'->>'planKey',
      'totalKnownFulfillmentCost',(v_price->>'totalKnownFulfillmentCost')::numeric,
      'costPerUnit',(v_price->>'costPerUnit')::numeric,
      'currency',v_price->>'currency',
      'proposedUnitPrice',(v_price->>'proposedUnitPrice')::numeric,
      'proposedTotal',(v_price->>'proposedTotal')::numeric
    );
    v_lines:=v_lines||jsonb_build_array(v_line_result);
  end loop;

  if jsonb_array_length(p_selected_line_plans)<>v_line_count then
    v_blocking:=v_blocking||jsonb_build_array(
      jsonb_build_object(
        'reason','selected_line_plan_count_mismatch',
        'basketLineCount',v_line_count,
        'selectedPlanCount',jsonb_array_length(p_selected_line_plans)
      )
    );
  end if;

  if v_blocked_count>0 then
    v_blocking:=v_blocking||jsonb_build_array(
      jsonb_build_object(
        'reason','one_or_more_lines_blocked',
        'blockedLineCount',v_blocked_count
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_ledger_quote_preparation_v1',
    'state',case
      when v_blocked_count=0
       and jsonb_array_length(p_selected_line_plans)=v_line_count
      then 'complete' else 'incomplete' end,
    'basketKey',v_basket_key,
    'lineCount',v_line_count,
    'pricedLineCount',v_priced_count,
    'blockedLineCount',v_blocked_count,
    'currency',case when v_blocked_count=0 then v_currency else null end,
    'pricedProtectedCostSubtotal',v_cost_total,
    'pricedQuoteSubtotal',v_quote_total,
    'protectedCostTotal',case
      when v_blocked_count=0
       and jsonb_array_length(p_selected_line_plans)=v_line_count
      then v_cost_total else null end,
    'wholeOrderTotal',case
      when v_blocked_count=0
       and jsonb_array_length(p_selected_line_plans)=v_line_count
      then v_quote_total else null end,
    'lines',v_lines,
    'blockingReasons',v_blocking,
    'pricingPolicyRef',coalesce(p_pricing_policy->'policyRef','{}'::jsonb),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'ledgerNativePacket',true,
      'noLegacyOrganizationContextRequired',true,
      'doesNotCreateLegacyOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreatePayment',true
    )
  );
end
$function$;


create or replace function atlas.feast_guild_flower_quote_under_ledger_policy_v1(
  p_ledger_id uuid,
  p_policy_key text,
  p_at timestamptz,
  p_basket jsonb,
  p_selected_line_plans jsonb,
  p_benchmark_lines jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definerset search_path=''
as $function$
declare
  v_policy_position jsonb;
  v_policy_input jsonb;
  v_quote jsonb;
  v_assessment jsonb;
begin
  v_policy_position:=atlas.ledger_commercial_pricing_policy_at_v1(
    p_ledger_id,p_policy_key,p_at
  );

  if v_policy_position->>'state'<>'resolved' then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_quote_under_ledger_policy_v1',
      'state','incomplete_evidence',
      'reason','pricing_policy_not_found',
      'policyPosition',v_policy_position
    );
  end if;

  v_policy_input:=atlas.ledger_commercial_pricing_policy_input_v1(
    (v_policy_position->>'policyId')::uuid
  );

  v_quote:=atlas.feast_guild_flower_ledger_quote_prepare_v1(
    p_basket,p_selected_line_plans,v_policy_input
  );

  v_assessment:=atlas.ledger_commercial_quote_packet_evaluate_v1(
    p_ledger_id,p_policy_key,p_at,v_quote,p_benchmark_lines
  );

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_quote_under_ledger_policy_v1',
    'state',case
      when v_assessment->>'state'<>'evaluated' then 'incomplete_evidence'
      else v_assessment->>'decisionState'
    end,
    'ledgerId',p_ledger_id,
    'policyPosition',v_policy_position,
    'pricingPolicyInput',v_policy_input,
    'quotePacket',v_quote,
    'commercialAssessment',v_assessment,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sourcePlanIsExplicitInput',true,
      'marketAndMarginRulesAppliedAfterQuoteMath',true,
      'doesNotCreateOffer',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecuteFulfillment',true
    )
  );
end
$function$;


revoke all on function atlas.ledger_commercial_pricing_policy_input_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_pricing_policy_input_v1(uuid)
  to service_role;

revoke all on function atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
  uuid,text,timestamptz,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_benchmark_envelope_from_observations_v1(
  uuid,text,timestamptz,text,jsonb
) to service_role;

revoke all on function atlas.ledger_commercial_quote_packet_evaluate_v1(
  uuid,text,timestamptz,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ledger_commercial_quote_packet_evaluate_v1(
  uuid,text,timestamptz,jsonb,jsonb
) to service_role;

revoke all on function atlas.record_ledger_commercial_quote_packet_receipt_service_v1(
  uuid,text,jsonb,text,timestamptz,jsonb,jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_ledger_commercial_quote_packet_receipt_service_v1(
  uuid,text,jsonb,text,timestamptz,jsonb,jsonb,jsonb,jsonb
) to service_role;

revoke all on function atlas.feast_guild_flower_commercial_viability_from_candidates_v1(
  uuid,text,timestamptz,jsonb,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_commercial_viability_from_candidates_v1(
  uuid,text,timestamptz,jsonb,jsonb,text,jsonb
) to service_role;

revoke all on function atlas.feast_guild_flower_ledger_quote_prepare_v1(
  jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_ledger_quote_prepare_v1(
  jsonb,jsonb,jsonb
) to service_role;

revoke all on function atlas.feast_guild_flower_quote_under_ledger_policy_v1(
  uuid,text,timestamptz,jsonb,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_quote_under_ledger_policy_v1(
  uuid,text,timestamptz,jsonb,jsonb,jsonb
) to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.ledger_commercial_pricing_policy_input_v1(uuid)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Translate one exact Ledger pricing-policy version into the existing universal commercial pricing input without changing the policy.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.ledger_commercial_benchmark_envelope_from_observations_v1(uuid,text,timestamptz,text,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Aggregate temporally valid source-backed benchmark observations and derive the Ledger commercial quote/protected-cost envelope.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.ledger_commercial_quote_packet_evaluate_v1(uuid,text,timestamptz,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Apply effective Ledger margin and market rules to a complete governed quote packet.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_ledger_commercial_quote_packet_receipt_service_v1(uuid,text,jsonb,text,timestamptz,jsonb,jsonb,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Preserve append-only evaluation provenance for a complete quote packet through the existing Ledger commercial receipt authority.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_commercial_viability_from_candidates_v1(uuid,text,timestamptz,jsonb,jsonb,text,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Evaluate whether the cheapest qualified Feast Guild source basket fits the Ledger market/margin envelope and expose per-line economic headroom without selecting suppliers.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_ledger_quote_prepare_v1(jsonb,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Prepare a Ledger-native Feast Guild whole-order quote packet from explicit qualified source plans without legacy Organization snapshot context.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_quote_under_ledger_policy_v1(uuid,text,timestamptz,jsonb,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_ledger_commercial_quote_orchestration_v1","purpose":"Bind an explicit Feast Guild source plan to the effective Ledger pricing policy and outside-market benchmark gate.","classificationRuleVersion":3}'::jsonb,
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
begin;

create or replace function atlas.feast_guild_flower_source_selection_policy_v1()
returns jsonb
language sql
immutable
set search_path=pg_catalog,atlas
as $function$
  select jsonb_build_object(
    'contractVersion','feast_guild_flower_source_selection_policy_v1',
    'comparisonBasis','landed_economic_cost',
    'currency','USD',
    'maximumPreferencePremiumRate',0.10,
    'preferenceTiers',jsonb_build_array(
      jsonb_build_object('tier','elm_owned_or_grown','rank',1),
      jsonb_build_object('tier','regional_us','rank',2),
      jsonb_build_object('tier','us_grown','rank',3),
      jsonb_build_object('tier','imported','rank',4)
    ),
    'truthBoundary',jsonb_build_object(
      'feastGuildSpecific',true,
      'qualificationPrecedesPreference',true,
      'landedEconomicCostRequired',true,
      'unknownCostIsNeverZero',true,
      'tierRequiresEvidence',true,
      'automaticPremiumBandCannotBeWidenedByCaller',true,
      'operatorExceptionRequiresSeparateAuthority',true
    )
  );
$function$;


create or replace function atlas.feast_guild_flower_source_candidate_evaluate_v1(
  p_line jsonb,
  p_candidate jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_policy jsonb:=atlas.feast_guild_flower_source_selection_policy_v1();
  v_policy_currency text:=v_policy->>'currency';

  v_basket_key text;
  v_line_key text;
  v_quantity numeric;
  v_unit text;
  v_requirements jsonb;

  v_candidate_ref jsonb;
  v_nodes jsonb;
  v_packet jsonb;
  v_preference jsonb;
  v_preference_tier text;
  v_preference_evidence jsonb;
  v_preference_evidence_item jsonb;
  v_tier_rank integer;

  v_requirement jsonb;
  v_requirement_key text;
  v_required boolean;
  v_evidence_required boolean;
  v_matching_count integer;
  v_matching_node jsonb;

  v_requirement_ref jsonb;
  v_qualification jsonb;
  v_position jsonb;
  v_cost numeric;
  v_cost_currency text;

  v_reasons jsonb:='[]'::jsonb;
  v_reason text;
begin
  if p_line is null or jsonb_typeof(p_line)<>'object' then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_source_candidate_evaluation_v1',
      'state','excluded',
      'reasons',jsonb_build_array(jsonb_build_object(
        'reason','line_not_object'
      ))
    );
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_line->>'basketKey','')),'');
  v_line_key:=nullif(btrim(coalesce(p_line->>'lineKey','')),'');
  v_unit:=nullif(lower(btrim(coalesce(p_line->>'unit',''))),'');
  v_requirements:=p_line->'requirements';

  if v_basket_key is null or v_line_key is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','line_identity_missing'
    ));
  end if;

  if jsonb_typeof(p_line->'quantity') is distinct from 'number' then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','line_quantity_invalid'
    ));
  else
    v_quantity:=(p_line->>'quantity')::numeric;
    if v_quantity<=0 then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','line_quantity_invalid'
      ));
    end if;
  end if;

  if v_unit is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','line_unit_missing'
    ));
  end if;

  if jsonb_typeof(v_requirements) is distinct from 'array'
     or jsonb_array_length(coalesce(v_requirements,'[]'::jsonb))=0 then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','line_requirements_missing'
    ));
  end if;

  if p_candidate is null or jsonb_typeof(p_candidate)<>'object' then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_source_candidate_evaluation_v1',
      'state','excluded',
      'lineKey',v_line_key,
      'reasons',v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','candidate_not_object'
      ))
    );
  end if;

  v_candidate_ref:=p_candidate->'candidateRef';
  v_nodes:=p_candidate->'qualificationNodes';
  v_packet:=p_candidate->'fulfillmentPacket';
  v_preference:=p_candidate->'sourcePreference';

  if jsonb_typeof(v_candidate_ref) is distinct from 'object'
     or nullif(btrim(coalesce(v_candidate_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(v_candidate_ref->>'sourceRef','')),'') is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','candidate_ref_invalid'
    ));
  end if;

  if jsonb_typeof(v_nodes) is distinct from 'array' then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','qualification_nodes_missing'
    ));
    v_nodes:='[]'::jsonb;
  end if;

  if jsonb_typeof(v_packet) is distinct from 'object' then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','fulfillment_packet_missing'
    ));
  end if;

  if jsonb_typeof(v_preference) is distinct from 'object' then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
      'reason','source_preference_missing'
    ));
  else
    v_preference_tier:=nullif(lower(btrim(coalesce(v_preference->>'tier',''))),'');
    v_preference_evidence:=v_preference->'evidence';

    if v_preference_tier is null then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','source_preference_tier_missing'
      ));
    end if;

    if jsonb_typeof(v_preference_evidence) is distinct from 'array'
       or jsonb_array_length(coalesce(v_preference_evidence,'[]'::jsonb))=0 then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','source_preference_evidence_missing'
      ));
    else
      for v_preference_evidence_item in
        select value from jsonb_array_elements(v_preference_evidence)
      loop
        if jsonb_typeof(v_preference_evidence_item)<>'object'
           or nullif(btrim(coalesce(v_preference_evidence_item->>'sourceRef','')),'') is null
           or nullif(btrim(coalesce(v_preference_evidence_item->>'fact','')),'') is null then
          v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
            'reason','source_preference_evidence_invalid'
          ));
        end if;
      end loop;
    end if;

    select (t.value->>'rank')::integer
    into v_tier_rank
    from jsonb_array_elements(v_policy->'preferenceTiers') as t(value)
    where t.value->>'tier'=v_preference_tier
    limit 1;

    if v_preference_tier is not null and v_tier_rank is null then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','source_preference_tier_unknown',
        'tier',v_preference_tier
      ));
    end if;
  end if;

  if jsonb_typeof(v_requirements)='array'
     and jsonb_typeof(v_nodes)='array' then
    for v_requirement in
      select value from jsonb_array_elements(v_requirements)
    loop
      if jsonb_typeof(v_requirement)<>'object' then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
          'reason','requirement_definition_invalid'
        ));
        continue;
      end if;

      v_requirement_key:=nullif(btrim(coalesce(v_requirement->>'requirementKey','')),'');
      if v_requirement_key is null then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
          'reason','requirement_key_missing'
        ));
        continue;
      end if;

      if v_requirement ? 'required' then
        if jsonb_typeof(v_requirement->'required')<>'boolean' then
          v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
            'reason','requirement_required_invalid',
            'requirementKey',v_requirement_key
          ));
          v_required:=true;
        else
          v_required:=(v_requirement->>'required')::boolean;
        end if;
      else
        v_required:=true;
      end if;

      if v_requirement ? 'evidenceRequired' then
        if jsonb_typeof(v_requirement->'evidenceRequired')<>'boolean' then
          v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
            'reason','requirement_evidence_required_invalid',
            'requirementKey',v_requirement_key
          ));
          v_evidence_required:=v_required;
        else
          v_evidence_required:=(v_requirement->>'evidenceRequired')::boolean;
        end if;
      else
        v_evidence_required:=v_required;
      end if;

      if v_required then
        select count(*)
        into v_matching_count
        from jsonb_array_elements(v_nodes) as n(value)
        where n.value->>'requirementKey'=v_requirement_key;

        if v_matching_count<>1 then
          v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
            'reason',case when v_matching_count=0
              then 'required_qualification_node_missing'
              else 'required_qualification_node_duplicate'
            end,
            'requirementKey',v_requirement_key,
            'matchingNodeCount',v_matching_count
          ));
        else
          select n.value
          into v_matching_node
          from jsonb_array_elements(v_nodes) as n(value)
          where n.value->>'requirementKey'=v_requirement_key
          limit 1;

          if v_evidence_required
             and lower(btrim(coalesce(v_matching_node->>'state','')))='satisfied'
             and (
               jsonb_typeof(v_matching_node->'evidence') is distinct from 'array'
               or jsonb_array_length(coalesce(v_matching_node->'evidence','[]'::jsonb))=0
             ) then
            v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
              'reason','required_qualification_evidence_missing',
              'requirementKey',v_requirement_key
            ));
          end if;
        end if;
      end if;
    end loop;
  end if;

  v_requirement_ref:=jsonb_build_object(
    'sourceDomain','feast_guild_flower_basket_v1',
    'sourceRef',coalesce(v_basket_key,'?')||':'||coalesce(v_line_key,'?')
  );

  if jsonb_array_length(v_reasons)=0 then
    v_qualification:=atlas.fulfillment_candidate_qualification_v1(
      v_requirement_ref,
      v_candidate_ref,
      v_nodes,
      jsonb_build_object(
        'sourceSelectionPolicy','feast_guild_flower_source_selection_policy_v1',
        'lineKey',v_line_key
      )
    );

    if v_qualification->>'qualificationState'<>'qualified' then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','candidate_not_qualified',
        'qualificationState',v_qualification->>'qualificationState'
      ));
    end if;
  end if;

  if jsonb_array_length(v_reasons)=0 then
    if v_packet->'requirementRef'->>'sourceDomain'
         is distinct from v_requirement_ref->>'sourceDomain'
       or v_packet->'requirementRef'->>'sourceRef'
         is distinct from v_requirement_ref->>'sourceRef' then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','fulfillment_requirement_ref_mismatch'
      ));
    end if;

    if jsonb_typeof(v_packet->'requirement'->'quantity') is distinct from 'number'
       or (v_packet->'requirement'->>'quantity')::numeric<>v_quantity
       or lower(btrim(coalesce(v_packet->'requirement'->>'unit','')))<>v_unit then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','fulfillment_quantity_or_unit_mismatch'
      ));
    end if;
  end if;

  if jsonb_array_length(v_reasons)=0 then
    v_position:=atlas.fulfillment_composition_position_v1(v_packet);

    if v_position->>'state'<>'ready' then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','fulfillment_composition_invalid'
      ));
    elsif v_position->>'coverageState'<>'exact' then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','fulfillment_not_exactly_covered',
        'coverageState',v_position->>'coverageState'
      ));
    elsif v_position->>'economicState'<>'known' then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
        'reason','landed_economic_cost_not_known',
        'economicState',v_position->>'economicState'
      ));
    else
      select e.key,(e.value)::numeric
      into v_cost_currency,v_cost
      from jsonb_each_text(v_position->'knownCostTotalsByCurrency') as e(key,value)
      order by e.key
      limit 1;

      if v_cost_currency is null or v_cost is null then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
          'reason','landed_economic_cost_missing'
        ));
      elsif v_cost_currency<>v_policy_currency then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object(
          'reason','policy_currency_mismatch',
          'policyCurrency',v_policy_currency,
          'candidateCurrency',v_cost_currency
        ));
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_source_candidate_evaluation_v1',
    'state',case when jsonb_array_length(v_reasons)=0 then 'selectable' else 'excluded' end,
    'lineKey',v_line_key,
    'requirementRef',v_requirement_ref,
    'candidateRef',v_candidate_ref,
    'sourcePreference',v_preference,
    'sourcePreferenceTier',v_preference_tier,
    'sourcePreferenceRank',v_tier_rank,
    'landedEconomicCost',v_cost,
    'currency',v_cost_currency,
    'qualification',v_qualification,
    'fulfillmentPosition',v_position,
    'candidatePlan',p_candidate,
    'reasons',v_reasons,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'qualificationPrecedesPreference',true,
      'sourceTierRequiresEvidence',true,
      'landedCostMustBeKnown',true,
      'doesNotSelect',true,
      'doesNotReserve',true,
      'doesNotPurchase',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_source_plan_select_v1(
  p_line jsonb,
  p_candidates jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_policy jsonb:=atlas.feast_guild_flower_source_selection_policy_v1();
  v_rate numeric:=(v_policy->>'maximumPreferencePremiumRate')::numeric;

  v_candidate jsonb;
  v_eval jsonb;
  v_evaluations jsonb:='[]'::jsonb;

  v_selectable_count integer:=0;
  v_min_cost numeric;
  v_ceiling numeric;
  v_best_available_rank integer;

  v_selected_eval jsonb;
  v_selected_rank integer;
  v_selected_cost numeric;
  v_selected_source_ref text;

  v_eval_rank integer;
  v_eval_cost numeric;
  v_eval_source_ref text;

  v_preferred_outside jsonb;
  v_preferred_outside_rank integer;
  v_preferred_outside_cost numeric;
  v_preferred_outside_source_ref text;

  v_selected_plan jsonb;
  v_premium_amount numeric;
  v_premium_rate numeric;
begin
  if p_candidates is null
     or jsonb_typeof(p_candidates)<>'array'
     or jsonb_array_length(p_candidates)=0 then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_source_plan_selection_v1',
      'state','blocked',
      'reason','no_candidate_plans',
      'policy',v_policy,
      'candidateEvaluations','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'noCandidateDoesNotBecomeAvailability',true
      )
    );
  end if;

  for v_candidate in
    select value from jsonb_array_elements(p_candidates)
  loop
    v_eval:=atlas.feast_guild_flower_source_candidate_evaluate_v1(
      p_line,
      v_candidate
    );

    v_evaluations:=v_evaluations||jsonb_build_array(v_eval);

    if v_eval->>'state'='selectable' then
      v_selectable_count:=v_selectable_count+1;
      v_eval_cost:=(v_eval->>'landedEconomicCost')::numeric;
      v_eval_rank:=(v_eval->>'sourcePreferenceRank')::integer;

      if v_min_cost is null or v_eval_cost<v_min_cost then
        v_min_cost:=v_eval_cost;
      end if;

      if v_best_available_rank is null or v_eval_rank<v_best_available_rank then
        v_best_available_rank:=v_eval_rank;
      end if;
    end if;
  end loop;

  if v_selectable_count=0 then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_source_plan_selection_v1',
      'state','blocked',
      'reason','no_qualified_known_landed_cost_candidate',
      'policy',v_policy,
      'candidateEvaluations',v_evaluations,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'unknownCostIsNeverZero',true,
        'unqualifiedCandidateCannotBePreferredIntoSelection',true
      )
    );
  end if;

  v_ceiling:=v_min_cost*(1+v_rate);

  for v_eval in
    select value from jsonb_array_elements(v_evaluations)
  loop
    continue when v_eval->>'state'<>'selectable';

    v_eval_cost:=(v_eval->>'landedEconomicCost')::numeric;
    v_eval_rank:=(v_eval->>'sourcePreferenceRank')::integer;
    v_eval_source_ref:=v_eval->'candidateRef'->>'sourceRef';

    if v_eval_cost<=v_ceiling then
      if v_selected_eval is null
         or v_eval_rank<v_selected_rank
         or (
           v_eval_rank=v_selected_rank
           and v_eval_cost<v_selected_cost
         )
         or (
           v_eval_rank=v_selected_rank
           and v_eval_cost=v_selected_cost
           and v_eval_source_ref<v_selected_source_ref
         ) then
        v_selected_eval:=v_eval;
        v_selected_rank:=v_eval_rank;
        v_selected_cost:=v_eval_cost;
        v_selected_source_ref:=v_eval_source_ref;
      end if;
    end if;
  end loop;

  if v_selected_eval is null then
    return jsonb_build_object(
      'contractVersion','feast_guild_flower_source_plan_selection_v1',
      'state','blocked',
      'reason','internal_no_in_band_candidate',
      'policy',v_policy,
      'cheapestQualifiedLandedCost',v_min_cost,
      'preferenceCeiling',v_ceiling,
      'candidateEvaluations',v_evaluations
    );
  end if;

  for v_eval in
    select value from jsonb_array_elements(v_evaluations)
  loop
    continue when v_eval->>'state'<>'selectable';

    v_eval_cost:=(v_eval->>'landedEconomicCost')::numeric;
    v_eval_rank:=(v_eval->>'sourcePreferenceRank')::integer;
    v_eval_source_ref:=v_eval->'candidateRef'->>'sourceRef';

    if v_eval_rank<v_selected_rank and v_eval_cost>v_ceiling then
      if v_preferred_outside is null
         or v_eval_rank<v_preferred_outside_rank
         or (
           v_eval_rank=v_preferred_outside_rank
           and v_eval_cost<v_preferred_outside_cost
         )
         or (
           v_eval_rank=v_preferred_outside_rank
           and v_eval_cost=v_preferred_outside_cost
           and v_eval_source_ref<v_preferred_outside_source_ref
         ) then
        v_preferred_outside:=v_eval;
        v_preferred_outside_rank:=v_eval_rank;
        v_preferred_outside_cost:=v_eval_cost;
        v_preferred_outside_source_ref:=v_eval_source_ref;
      end if;
    end if;
  end loop;

  v_premium_amount:=v_selected_cost-v_min_cost;
  v_premium_rate:=case
    when v_min_cost=0 then 0
    else v_premium_amount/v_min_cost
  end;

  v_selected_plan:=jsonb_set(
    v_selected_eval->'candidatePlan',
    '{selectionBasis}',
    jsonb_build_object(
      'decisionKind','feast_guild_source_policy_v1',
      'policyVersion','feast_guild_flower_source_selection_policy_v1',
      'comparisonBasis','landed_economic_cost',
      'cheapestQualifiedLandedCost',v_min_cost,
      'preferenceCeiling',v_ceiling,
      'selectedLandedCost',v_selected_cost,
      'selectedPreferenceTier',v_selected_eval->>'sourcePreferenceTier',
      'selectedPreferenceRank',v_selected_rank,
      'premiumAmount',v_premium_amount,
      'premiumRate',v_premium_rate,
      'morePreferredCandidateOutsideBand',(v_preferred_outside is not null),
      'operatorApprovalRequiredToUseMorePreferredOutsideBand',(v_preferred_outside is not null)
    ),
    true
  );

  v_selected_plan:=jsonb_set(
    v_selected_plan,
    '{lineKey}',
    to_jsonb(p_line->>'lineKey'),
    true
  );

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_source_plan_selection_v1',
    'state','selected',
    'policy',v_policy,
    'lineKey',p_line->>'lineKey',
    'requirementRef',v_selected_eval->'requirementRef',
    'selectableCandidateCount',v_selectable_count,
    'cheapestQualifiedLandedCost',v_min_cost,
    'preferenceCeiling',v_ceiling,
    'selectedCandidateRef',v_selected_eval->'candidateRef',
    'selectedPreferenceTier',v_selected_eval->>'sourcePreferenceTier',
    'selectedPreferenceRank',v_selected_rank,
    'selectedLandedCost',v_selected_cost,
    'currency',v_selected_eval->>'currency',
    'premiumAmount',v_premium_amount,
    'premiumRate',v_premium_rate,
    'selectedPlan',v_selected_plan,
    'morePreferredCandidateOutsideBand',(v_preferred_outside is not null),
    'operatorApprovalRequiredToUseMorePreferredOutsideBand',(v_preferred_outside is not null),
    'preferredCandidateOutsideBand',v_preferred_outside,
    'candidateEvaluations',v_evaluations,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'selectionIsPlanningNotPurchase',true,
      'preferenceBandFixedByFeastGuildPolicy',true,
      'operatorExceptionCannotBeSelfAuthorizedHere',true,
      'doesNotReserve',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreateOffer',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_quote_prepare_from_candidates_v1(
  p_basket jsonb,
  p_line_candidate_sets jsonb,
  p_pricing_policy jsonb,
  p_quote_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_set jsonb;
  v_set_count integer;
  v_selection jsonb;

  v_selections jsonb:='[]'::jsonb;
  v_selected_plans jsonb:='[]'::jsonb;
  v_quote jsonb;
  v_selection_blocked_count integer:=0;
begin
  if p_basket is null
     or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  if v_basket_key is null then
    raise exception 'Basket key is required.'
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

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    if v_line_key is null then
      raise exception 'Every basket line requires lineKey.'
        using errcode='22023';
    end if;

    select count(*)
    into v_set_count
    from jsonb_array_elements(p_line_candidate_sets) s(value)
    where s.value->>'lineKey'=v_line_key;

    if v_set_count=1 then
      select s.value
      into v_set
      from jsonb_array_elements(p_line_candidate_sets) s(value)
      where s.value->>'lineKey'=v_line_key
      limit 1;

      if jsonb_typeof(v_set->'candidates') is distinct from 'array' then
        v_selection:=jsonb_build_object(
          'contractVersion','feast_guild_flower_source_plan_selection_v1',
          'state','blocked',
          'lineKey',v_line_key,
          'reason','candidate_set_candidates_missing',
          'candidateEvaluations','[]'::jsonb
        );
      else
        v_line_packet:=jsonb_set(
          v_line,
          '{basketKey}',
          to_jsonb(v_basket_key),
          true
        );

        v_selection:=atlas.feast_guild_flower_source_plan_select_v1(
          v_line_packet,
          v_set->'candidates'
        );
      end if;
    else
      v_selection:=jsonb_build_object(
        'contractVersion','feast_guild_flower_source_plan_selection_v1',
        'state','blocked',
        'lineKey',v_line_key,
        'reason',case when v_set_count=0
          then 'candidate_set_missing'
          else 'candidate_set_duplicate'
        end,
        'matchingCandidateSetCount',v_set_count,
        'candidateEvaluations','[]'::jsonb
      );
    end if;

    v_selections:=v_selections||jsonb_build_array(v_selection);

    if v_selection->>'state'='selected' then
      v_selected_plans:=v_selected_plans||jsonb_build_array(
        v_selection->'selectedPlan'
      );
    else
      v_selection_blocked_count:=v_selection_blocked_count+1;
    end if;
  end loop;

  v_quote:=atlas.feast_guild_flower_quote_prepare_v1(
    p_basket,
    v_selected_plans,
    p_pricing_policy,
    p_quote_context
  );

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_quote_from_candidates_v1',
    'state',case
      when v_selection_blocked_count=0 and v_quote->>'state'='complete' then 'complete'
      else 'incomplete'
    end,
    'sourceSelectionPolicy',atlas.feast_guild_flower_source_selection_policy_v1(),
    'lineSelectionCount',jsonb_array_length(v_selections),
    'blockedSelectionCount',v_selection_blocked_count,
    'lineSelections',v_selections,
    'selectedLinePlans',v_selected_plans,
    'quote',v_quote,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sourceSelectionIsPlanning',true,
      'quotePreparationIsReadOnly',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSupplierCommitment',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotExecuteFulfillment',true
    )
  );
end;
$function$;


revoke all on function atlas.feast_guild_flower_source_selection_policy_v1()
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_source_selection_policy_v1()
  to service_role;

revoke all on function atlas.feast_guild_flower_source_candidate_evaluate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_source_candidate_evaluate_v1(jsonb,jsonb)
  to service_role;

revoke all on function atlas.feast_guild_flower_source_plan_select_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_source_plan_select_v1(jsonb,jsonb)
  to service_role;

revoke all on function atlas.feast_guild_flower_quote_prepare_from_candidates_v1(jsonb,jsonb,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_quote_prepare_from_candidates_v1(jsonb,jsonb,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.feast_guild_flower_source_selection_policy_v1()',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_source_selection_policy_v1","purpose":"Immutable Feast Guild V1 source preference policy: Elm/regional/U.S./imported with fixed +10% landed-cost preference band.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_source_candidate_evaluate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_source_selection_policy_v1","purpose":"Read-only flower candidate admission into Feast Guild source selection; qualification and exact known landed economics precede preference.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_source_plan_select_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_source_selection_policy_v1","purpose":"Read-only deterministic Feast Guild source selection using fixed source tiers and +10% landed-economic-cost band.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_quote_prepare_from_candidates_v1(jsonb,jsonb,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_source_selection_policy_v1","purpose":"Read-only whole-basket orchestration from candidate sets through Feast Guild source policy into the existing quote preparation adapter.","classificationRuleVersion":3}'::jsonb,
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

begin;

create or replace function atlas.work_requirement_pool_position_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_source_ref jsonb;
  v_use jsonb;
  v_cost jsonb;
  v_requirement atlas.work_requirements%rowtype;
  v_coverage jsonb;

  v_pool_key text;
  v_source_quantity numeric;
  v_source_unit text;
  v_output_quantity numeric;
  v_output_unit text;

  v_use_key text;
  v_work_requirement_id uuid;
  v_qualification_state text;
  v_planned_quantity numeric;
  v_use_unit text;
  v_required_quantity numeric;
  v_required_unit text;
  v_already_secured numeric;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_use_state text;

  v_use_keys text[]:='{}'::text[];
  v_requirement_ids uuid[]:='{}'::uuid[];
  v_cost_keys text[]:='{}'::text[];

  v_cost_key text;
  v_cost_state text;
  v_cost_required boolean;
  v_cost_amount numeric;
  v_cost_currency text;

  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_requirement_positions jsonb:='[]'::jsonb;

  v_planned_output_quantity numeric:=0;
  v_aggregate_outstanding_before numeric:=0;
  v_unallocated_demand_quantity numeric:=0;
  v_excess_output_quantity numeric:=0;

  v_known_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_cost_component_count integer:=0;
  v_currency_count integer:=0;
  v_known_cost_totals jsonb:='{}'::jsonb;
  v_economic_state text;
  v_known_pool_cost numeric;
  v_known_currency text;
  v_source_basis_unit_cost numeric;
  v_allocated_output_cost_basis numeric;
  v_excess_output_cost_basis numeric;
  v_full_cost_burden_per_planned_unit numeric;

  v_pool_utilization_state text;
  v_demand_position text;
begin
  if p_packet is null or jsonb_typeof(p_packet)<>'object' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_position_v1',
      'state','invalid',
      'violations',jsonb_build_array(jsonb_build_object(
        'key','packet_not_object',
        'message','Pool packet must be a JSON object.'
      )),
      'warnings','[]'::jsonb
    );
  end if;

  if p_packet->>'contractVersion'<>'work_requirement_pool_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version',
      'message','contractVersion must be work_requirement_pool_v1.'
    ));
  end if;

  v_pool_key:=nullif(btrim(coalesce(p_packet->>'poolKey','')),'');
  if v_pool_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_pool_key'
    ));
  end if;

  v_source_ref:=p_packet->'sourceRef';
  if v_source_ref is null
     or jsonb_typeof(v_source_ref)<>'object'
     or nullif(btrim(coalesce(v_source_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(v_source_ref->>'sourceRef','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_ref'
    ));
  end if;

  if jsonb_typeof(p_packet->'sourceQuantity')<>'number' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_quantity'
    ));
  else
    v_source_quantity:=(p_packet->>'sourceQuantity')::numeric;
    if v_source_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_source_quantity',
        'message','sourceQuantity must be greater than zero.'
      ));
    end if;
  end if;

  v_source_unit:=nullif(btrim(coalesce(p_packet->>'sourceUnit','')),'');
  if v_source_unit is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_unit'
    ));
  end if;

  if jsonb_typeof(p_packet->'outputQuantity')<>'number' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_output_quantity'
    ));
  else
    v_output_quantity:=(p_packet->>'outputQuantity')::numeric;
    if v_output_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_output_quantity',
        'message','outputQuantity must be greater than zero.'
      ));
    end if;
  end if;

  v_output_unit:=nullif(btrim(coalesce(p_packet->>'outputUnit','')),'');
  if v_output_unit is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_output_unit'
    ));
  end if;

  if p_packet ? 'metadata'
     and jsonb_typeof(p_packet->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata'
    ));
  end if;

  if jsonb_typeof(p_packet->'plannedUses')<>'array'
     or jsonb_array_length(coalesce(p_packet->'plannedUses','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_planned_uses',
      'message','plannedUses must be a non-empty array.'
    ));
  else
    for v_use in
      select value
      from jsonb_array_elements(p_packet->'plannedUses')
    loop
      if jsonb_typeof(v_use)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_use_not_object'
        ));
        continue;
      end if;

      v_use_key:=nullif(btrim(coalesce(v_use->>'useKey','')),'');
      if v_use_key is null or v_use_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_use_key',
          'useKey',v_use->>'useKey'
        ));
        continue;
      end if;

      if v_use_key=any(v_use_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_use_key',
          'useKey',v_use_key
        ));
        continue;
      end if;
      v_use_keys:=array_append(v_use_keys,v_use_key);

      begin
        v_work_requirement_id:=nullif(btrim(coalesce(v_use->>'workRequirementId','')),'')::uuid;
      exception when invalid_text_representation then
        v_work_requirement_id:=null;
      end;

      if v_work_requirement_id is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_work_requirement_id',
          'useKey',v_use_key
        ));
        continue;
      end if;

      if v_work_requirement_id=any(v_requirement_ids) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_work_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;
      v_requirement_ids:=array_append(v_requirement_ids,v_work_requirement_id);

      select * into v_requirement
      from atlas.work_requirements
      where id=v_work_requirement_id;

      if v_requirement.id is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_found',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      if v_requirement.state<>'active' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_active',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'requirementState',v_requirement.state
        ));
      end if;

      if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
         or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_quantified',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      v_required_quantity:=(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric;
      v_required_unit:=btrim(v_requirement.metadata->'commercialFulfillment'->>'unit');

      if v_required_quantity<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_work_requirement_quantity',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      if v_required_unit<>v_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','requirement_pool_unit_mismatch',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'requirementUnit',v_required_unit,
          'poolOutputUnit',v_output_unit
        ));
      end if;

      v_qualification_state:=lower(btrim(coalesce(v_use->>'qualificationState','')));
      if v_qualification_state<>'qualified' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','source_not_qualified_for_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'qualificationState',v_use->>'qualificationState'
        ));
      end if;

      if jsonb_typeof(v_use->'plannedQuantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_planned_quantity',
          'useKey',v_use_key
        ));
        continue;
      end if;

      v_planned_quantity:=(v_use->>'plannedQuantity')::numeric;
      if v_planned_quantity<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_planned_quantity',
          'useKey',v_use_key,
          'message','plannedQuantity must be greater than zero.'
        ));
      end if;

      v_use_unit:=nullif(btrim(coalesce(v_use->>'unit','')),'');
      if v_use_unit is null
         or v_use_unit<>v_required_unit
         or v_use_unit<>v_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_use_unit_mismatch',
          'useKey',v_use_key,
          'plannedUnit',v_use_unit,
          'requirementUnit',v_required_unit,
          'poolOutputUnit',v_output_unit
        ));
      end if;

      if v_use ? 'existingCoverageFacts'
         and jsonb_typeof(v_use->'existingCoverageFacts')<>'array' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_existing_coverage_facts',
          'useKey',v_use_key
        ));
        v_coverage:=null;
      else
        v_coverage:=atlas.work_requirement_coverage_position_v1(
          v_work_requirement_id,
          coalesce(v_use->'existingCoverageFacts','[]'::jsonb)
        );
      end if;

      if v_coverage is null or v_coverage->>'state'<>'ready' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','existing_coverage_invalid',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'coveragePosition',v_coverage
        ));
        v_already_secured:=0;
      else
        v_already_secured:=coalesce((v_coverage->>'securedQuantity')::numeric,0);
      end if;

      v_outstanding_before:=greatest(v_required_quantity-v_already_secured,0);

      if v_planned_quantity>v_outstanding_before then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_quantity_exceeds_outstanding_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'plannedQuantity',v_planned_quantity,
          'outstandingBeforePool',v_outstanding_before
        ));
      end if;

      v_outstanding_after:=greatest(v_outstanding_before-v_planned_quantity,0);

      v_use_state:=case
        when v_outstanding_before=0 then 'already_secured'
        when v_planned_quantity=0 then 'uncovered'
        when v_planned_quantity<v_outstanding_before then 'partial'
        when v_planned_quantity=v_outstanding_before then 'exact'
        else 'overplanned'
      end;

      v_planned_output_quantity:=v_planned_output_quantity+greatest(v_planned_quantity,0);
      v_aggregate_outstanding_before:=v_aggregate_outstanding_before+v_outstanding_before;
      v_unallocated_demand_quantity:=v_unallocated_demand_quantity+v_outstanding_after;

      v_requirement_positions:=v_requirement_positions||jsonb_build_array(jsonb_build_object(
        'useKey',v_use_key,
        'workRequirementId',v_work_requirement_id,
        'requirementStableKey',v_requirement.stable_key,
        'requirementSummary',v_requirement.summary,
        'requiredQuantity',v_required_quantity,
        'unit',v_required_unit,
        'alreadySecuredQuantity',v_already_secured,
        'outstandingBeforePool',v_outstanding_before,
        'plannedFromPool',v_planned_quantity,
        'outstandingAfterPool',v_outstanding_after,
        'plannedCoverageState',v_use_state,
        'qualificationState',v_qualification_state,
        'existingCoveragePosition',v_coverage
      ));
    end loop;
  end if;

  if v_output_quantity is not null and v_planned_output_quantity>v_output_quantity then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','planned_output_exceeds_pool_output',
      'plannedOutputQuantity',v_planned_output_quantity,
      'poolOutputQuantity',v_output_quantity
    ));
  end if;

  if p_packet ? 'costComponents' then
    if jsonb_typeof(p_packet->'costComponents')<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_cost_components'
      ));
    else
      for v_cost in
        select value
        from jsonb_array_elements(p_packet->'costComponents')
      loop
        v_cost_component_count:=v_cost_component_count+1;

        if jsonb_typeof(v_cost)<>'object' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','cost_component_not_object'
          ));
          continue;
        end if;

        v_cost_key:=nullif(btrim(coalesce(v_cost->>'componentKey','')),'');
        if v_cost_key is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','missing_cost_component_key'
          ));
        elsif v_cost_key=any(v_cost_keys) then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','duplicate_cost_component_key',
            'componentKey',v_cost_key
          ));
        else
          v_cost_keys:=array_append(v_cost_keys,v_cost_key);
        end if;

        v_cost_state:=lower(btrim(coalesce(v_cost->>'state','')));
        if v_cost_state not in ('known','unresolved','not_applicable') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_state',
            'componentKey',v_cost_key
          ));
          continue;
        end if;

        if v_cost ? 'required' then
          if jsonb_typeof(v_cost->'required')<>'boolean' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_cost_required',
              'componentKey',v_cost_key
            ));
            v_cost_required:=true;
          else
            v_cost_required:=(v_cost->>'required')::boolean;
          end if;
        else
          v_cost_required:=true;
        end if;

        if v_cost_state='known' then
          if jsonb_typeof(v_cost->'amount')<>'number' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','known_cost_without_amount',
              'componentKey',v_cost_key
            ));
          else
            v_cost_amount:=(v_cost->>'amount')::numeric;
            if v_cost_amount<0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','negative_cost_amount',
                'componentKey',v_cost_key
              ));
            end if;
          end if;

          v_cost_currency:=upper(btrim(coalesce(v_cost->>'currency','')));
          if v_cost_currency !~ '^[A-Z]{3}$' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_cost_currency',
              'componentKey',v_cost_key
            ));
          else
            v_known_cost_count:=v_known_cost_count+1;
          end if;
        elsif v_cost_state='unresolved' then
          if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','unresolved_cost_has_amount',
              'componentKey',v_cost_key
            ));
          end if;
          if v_cost_required then
            v_unresolved_required_cost_count:=v_unresolved_required_cost_count+1;
          end if;
        else
          if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','not_applicable_cost_has_amount',
              'componentKey',v_cost_key
            ));
          end if;
        end if;

        if v_cost ? 'details'
           and jsonb_typeof(v_cost->'details')<>'object' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_details',
            'componentKey',v_cost_key
          ));
        end if;
      end loop;
    end if;
  end if;

  if jsonb_array_length(v_violations)>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_position_v1',
      'state','invalid',
      'poolKey',v_pool_key,
      'sourceRef',v_source_ref,
      'violations',v_violations,
      'warnings',v_warnings,
      'requirementPositions',v_requirement_positions,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidPoolCreatesNoTruth',true
      )
    );
  end if;

  select
    coalesce(jsonb_object_agg(q.currency,to_jsonb(q.total_amount) order by q.currency),'{}'::jsonb),
    count(*)
  into v_known_cost_totals,v_currency_count
  from (
    select
      upper(c->>'currency') as currency,
      sum((c->>'amount')::numeric) as total_amount
    from jsonb_array_elements(coalesce(p_packet->'costComponents','[]'::jsonb)) c
    where c->>'state'='known'
      and jsonb_typeof(c->'amount')='number'
      and upper(coalesce(c->>'currency','')) ~ '^[A-Z]{3}$'
    group by upper(c->>'currency')
  ) q;

  if v_cost_component_count=0
     or (v_known_cost_count=0 and v_unresolved_required_cost_count=0) then
    v_economic_state:='no_cost_evidence';
  elsif v_unresolved_required_cost_count>0 then
    v_economic_state:='unresolved';
  elsif v_currency_count>1 then
    v_economic_state:='known_multi_currency';
  else
    v_economic_state:='known';
  end if;

  v_excess_output_quantity:=greatest(v_output_quantity-v_planned_output_quantity,0);

  v_pool_utilization_state:=case
    when v_planned_output_quantity<v_output_quantity then 'partial_use'
    else 'fully_used'
  end;

  v_demand_position:=case
    when v_unallocated_demand_quantity=0 then 'all_covered'
    else 'partially_covered'
  end;

  if v_economic_state='known' then
    select key,(value)::numeric
    into v_known_currency,v_known_pool_cost
    from jsonb_each_text(v_known_cost_totals)
    order by key
    limit 1;

    v_source_basis_unit_cost:=v_known_pool_cost/v_output_quantity;
    v_allocated_output_cost_basis:=v_source_basis_unit_cost*v_planned_output_quantity;
    v_excess_output_cost_basis:=v_source_basis_unit_cost*v_excess_output_quantity;

    if v_planned_output_quantity>0 then
      v_full_cost_burden_per_planned_unit:=v_known_pool_cost/v_planned_output_quantity;
    end if;

    select coalesce(
      jsonb_agg(
        rp || jsonb_build_object(
          'proportionalCostBasis',
          (rp->>'plannedFromPool')::numeric * v_source_basis_unit_cost,
          'costCurrency',
          v_known_currency
        )
        order by rp->>'useKey'
      ),
      '[]'::jsonb
    )
    into v_requirement_positions
    from jsonb_array_elements(v_requirement_positions) rp;
  end if;

  return jsonb_build_object(
    'contractVersion','work_requirement_pool_position_v1',
    'state','ready',
    'poolKey',v_pool_key,
    'sourceRef',v_source_ref,
    'sourceQuantity',v_source_quantity,
    'sourceUnit',v_source_unit,
    'outputQuantity',v_output_quantity,
    'outputUnit',v_output_unit,
    'plannedOutputQuantity',v_planned_output_quantity,
    'excessOutputQuantity',v_excess_output_quantity,
    'poolUtilizationState',v_pool_utilization_state,
    'aggregateOutstandingBeforePool',v_aggregate_outstanding_before,
    'unallocatedDemandQuantity',v_unallocated_demand_quantity,
    'demandPosition',v_demand_position,
    'requirementCount',jsonb_array_length(v_requirement_positions),
    'requirementPositions',v_requirement_positions,
    'economicState',v_economic_state,
    'knownCostTotalsByCurrency',v_known_cost_totals,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'knownPoolCost',v_known_pool_cost,
    'knownCostCurrency',v_known_currency,
    'sourceBasisUnitCost',v_source_basis_unit_cost,
    'allocatedOutputCostBasis',v_allocated_output_cost_basis,
    'excessOutputCostBasis',v_excess_output_cost_basis,
    'fullCostBurdenPerPlannedUnit',v_full_cost_burden_per_planned_unit,
    'metadata',coalesce(p_packet->'metadata','{}'::jsonb),
    'violations','[]'::jsonb,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sourcePoolMayBeOnlyProposed',true,
      'plannedUseIsNotAllocation',true,
      'plannedUseIsNotSecuredCoverage',true,
      'sourceEconomicsRemainSourceBacked',true,
      'excessRemainsExplicit',true,
      'proportionalCostBasisIsDerivedScenario',true,
      'fullCostBurdenIsConservativeScenario',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCreateAllocation',true,
      'doesNotCreateReservation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreatePayment',true,
      'doesNotFulfill',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_pool_position_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_pool_position_v1(jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_pool_position_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_work_requirement_pool_position_v1","purpose":"Read-only break-bulk position for one proposed source pool across several quantified Company Work Requirements, preserving residual demand, source excess, and shared economics.","classificationRuleVersion":3}'::jsonb,
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

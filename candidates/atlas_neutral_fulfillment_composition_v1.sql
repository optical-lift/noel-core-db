begin;

create or replace function atlas.fulfillment_composition_validate_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_requirement jsonb;
  v_requirement_ref jsonb;
  v_allocation jsonb;
  v_cost jsonb;
  v_excess jsonb;
  v_candidate_ref jsonb;
  v_keys text[]:='{}'::text[];
  v_cost_keys text[];
  v_key text;
  v_cost_key text;
  v_state text;
  v_required boolean;
  v_req_qty numeric;
  v_req_unit text;
  v_out_qty numeric;
  v_out_unit text;
  v_source_qty numeric;
  v_source_unit text;
  v_amount numeric;
  v_currency text;
  v_allocation_count integer:=0;
  v_cost_count integer:=0;
  v_known_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_output_total numeric:=0;
begin
  if p_packet is null or jsonb_typeof(p_packet)<>'object' then
    return jsonb_build_object(
      'contractVersion','fulfillment_composition_validation_v1',
      'validationState','rejected',
      'violations',jsonb_build_array(jsonb_build_object(
        'key','packet_not_object',
        'message','Fulfillment composition packet must be a JSON object.'
      )),
      'warnings','[]'::jsonb
    );
  end if;

  if p_packet->>'contractVersion'<>'neutral_fulfillment_composition_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version',
      'message','contractVersion must be neutral_fulfillment_composition_v1.'
    ));
  end if;

  v_requirement_ref:=p_packet->'requirementRef';
  if v_requirement_ref is null
     or jsonb_typeof(v_requirement_ref)<>'object'
     or nullif(btrim(coalesce(v_requirement_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(v_requirement_ref->>'sourceRef','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement_ref',
      'message','requirementRef requires sourceDomain and sourceRef.'
    ));
  end if;

  if nullif(btrim(coalesce(p_packet->>'planKey','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_plan_key',
      'message','planKey is required.'
    ));
  end if;

  v_requirement:=p_packet->'requirement';
  if v_requirement is null or jsonb_typeof(v_requirement)<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement',
      'message','requirement must be a JSON object.'
    ));
  else
    if jsonb_typeof(v_requirement->'quantity')<>'number' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_quantity',
        'message','requirement.quantity must be numeric.'
      ));
    else
      v_req_qty:=(v_requirement->>'quantity')::numeric;
      if v_req_qty<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_requirement_quantity',
          'message','requirement.quantity must be greater than zero.'
        ));
      end if;
    end if;

    v_req_unit:=nullif(lower(btrim(coalesce(v_requirement->>'unit',''))),'');
    if v_req_unit is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_unit',
        'message','requirement.unit is required.'
      ));
    end if;
  end if;

  if p_packet ? 'constraints'
     and jsonb_typeof(p_packet->'constraints')<>'array' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_constraints',
      'message','constraints must be an array when present.'
    ));
  end if;

  if p_packet ? 'unresolved'
     and jsonb_typeof(p_packet->'unresolved')<>'array' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_unresolved',
      'message','unresolved must be an array when present.'
    ));
  end if;

  if p_packet ? 'metadata'
     and jsonb_typeof(p_packet->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata',
      'message','metadata must be an object when present.'
    ));
  end if;

  if jsonb_typeof(p_packet->'allocations')<>'array'
     or jsonb_array_length(coalesce(p_packet->'allocations','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_allocations',
      'message','allocations must be a non-empty array.'
    ));
  else
    for v_allocation in
      select value from jsonb_array_elements(p_packet->'allocations')
    loop
      v_allocation_count:=v_allocation_count+1;

      if jsonb_typeof(v_allocation)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocation_not_object',
          'allocationIndex',v_allocation_count
        ));
        continue;
      end if;

      v_key:=nullif(btrim(coalesce(v_allocation->>'allocationKey','')),'');
      if v_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','missing_allocation_key',
          'allocationIndex',v_allocation_count
        ));
      elsif v_key=any(v_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_allocation_key',
          'allocationKey',v_key
        ));
      else
        v_keys:=array_append(v_keys,v_key);
      end if;

      v_candidate_ref:=v_allocation->'candidateRef';
      if v_candidate_ref is null
         or jsonb_typeof(v_candidate_ref)<>'object'
         or nullif(btrim(coalesce(v_candidate_ref->>'sourceDomain','')),'') is null
         or nullif(btrim(coalesce(v_candidate_ref->>'sourceRef','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_candidate_ref',
          'allocationKey',v_key
        ));
      end if;

      if lower(btrim(coalesce(v_allocation->>'qualificationState','')))<>'qualified' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','candidate_not_qualified',
          'allocationKey',v_key,
          'qualificationState',v_allocation->>'qualificationState'
        ));
      end if;

      if jsonb_typeof(v_allocation->'outputQuantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_quantity',
          'allocationKey',v_key
        ));
      else
        v_out_qty:=(v_allocation->>'outputQuantity')::numeric;
        if v_out_qty<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_output_quantity',
            'allocationKey',v_key,
            'message','outputQuantity must be greater than zero.'
          ));
        else
          v_output_total:=v_output_total+v_out_qty;
        end if;
      end if;

      v_out_unit:=nullif(lower(btrim(coalesce(v_allocation->>'outputUnit',''))),'');
      if v_out_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_unit',
          'allocationKey',v_key
        ));
      elsif v_req_unit is not null and v_out_unit<>v_req_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_unit_mismatch',
          'allocationKey',v_key,
          'requirementUnit',v_req_unit,
          'outputUnit',v_out_unit,
          'message','V1 requires allocation outputUnit to equal requirement.unit; conversion must be explicit upstream.'
        ));
      end if;

      if (v_allocation ? 'sourceQuantity') or (v_allocation ? 'sourceUnit') then
        if jsonb_typeof(v_allocation->'sourceQuantity')<>'number' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_quantity',
            'allocationKey',v_key
          ));
        else
          v_source_qty:=(v_allocation->>'sourceQuantity')::numeric;
          if v_source_qty<=0 then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_source_quantity',
              'allocationKey',v_key
            ));
          end if;
        end if;

        v_source_unit:=nullif(lower(btrim(coalesce(v_allocation->>'sourceUnit',''))),'');
        if v_source_unit is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_unit',
            'allocationKey',v_key
          ));
        end if;
      end if;

      if v_allocation ? 'facts'
         and jsonb_typeof(v_allocation->'facts')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_allocation_facts',
          'allocationKey',v_key
        ));
      end if;

      if v_allocation ? 'excess' then
        v_excess:=v_allocation->'excess';
        if jsonb_typeof(v_excess)<>'object'
           or jsonb_typeof(v_excess->'quantity')<>'number'
           or (v_excess->>'quantity')::numeric<0
           or nullif(lower(btrim(coalesce(v_excess->>'unit',''))),'') is null
           or nullif(btrim(coalesce(v_excess->>'dispositionState','')),'') is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_excess',
            'allocationKey',v_key,
            'message','excess requires nonnegative quantity, unit, and dispositionState.'
          ));
        end if;
      end if;

      v_cost_keys:='{}'::text[];
      if v_allocation ? 'costComponents' then
        if jsonb_typeof(v_allocation->'costComponents')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_components',
            'allocationKey',v_key
          ));
        else
          for v_cost in
            select value from jsonb_array_elements(v_allocation->'costComponents')
          loop
            v_cost_count:=v_cost_count+1;
            if jsonb_typeof(v_cost)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','cost_component_not_object',
                'allocationKey',v_key
              ));
              continue;
            end if;

            v_cost_key:=nullif(btrim(coalesce(v_cost->>'componentKey','')),'');
            if v_cost_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','missing_cost_component_key',
                'allocationKey',v_key
              ));
            elsif v_cost_key=any(v_cost_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','duplicate_cost_component_key',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
            else
              v_cost_keys:=array_append(v_cost_keys,v_cost_key);
            end if;

            v_state:=lower(btrim(coalesce(v_cost->>'state','')));
            if v_state not in ('known','unresolved','not_applicable') then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_cost_state',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
              continue;
            end if;

            if v_cost ? 'required' then
              if jsonb_typeof(v_cost->'required')<>'boolean' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','invalid_cost_required',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
                v_required:=true;
              else
                v_required:=(v_cost->>'required')::boolean;
              end if;
            else
              v_required:=true;
            end if;

            if v_state='known' then
              v_known_cost_count:=v_known_cost_count+1;
              if jsonb_typeof(v_cost->'amount')<>'number' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','known_cost_without_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              else
                v_amount:=(v_cost->>'amount')::numeric;
                if v_amount<0 then
                  v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                    'key','negative_cost_amount',
                    'allocationKey',v_key,
                    'componentKey',v_cost_key
                  ));
                end if;
              end if;

              v_currency:=upper(btrim(coalesce(v_cost->>'currency','')));
              if v_currency !~ '^[A-Z]{3}$' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','invalid_cost_currency',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
            elsif v_state='unresolved' then
              if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','unresolved_cost_has_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
              if v_required then
                v_unresolved_required_cost_count:=v_unresolved_required_cost_count+1;
              end if;
            else
              if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','not_applicable_cost_has_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
            end if;

            if v_cost ? 'details' and jsonb_typeof(v_cost->'details')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_cost_details',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
            end if;
          end loop;
        end if;
      end if;
    end loop;
  end if;

  if v_req_qty is not null and v_output_total>v_req_qty then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
      'key','allocated_output_exceeds_requirement',
      'requiredQuantity',v_req_qty,
      'outputQuantity',v_output_total,
      'message','Prefer representing pack/yield overage as source excess rather than allocated requirement output.'
    ));
  end if;

  return jsonb_build_object(
    'contractVersion','fulfillment_composition_validation_v1',
    'validationState',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'violations',v_violations,
    'warnings',v_warnings,
    'requirementQuantity',v_req_qty,
    'requirementUnit',v_req_unit,
    'allocationCount',v_allocation_count,
    'outputQuantity',v_output_total,
    'costComponentCount',v_cost_count,
    'knownCostComponentCount',v_known_cost_count,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotSelectCandidates',true,
      'doesNotReserveResources',true,
      'doesNotCreateCoverage',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


create or replace function atlas.fulfillment_composition_position_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_validation jsonb;
  v_req_qty numeric;
  v_req_unit text;
  v_output_qty numeric;
  v_coverage_state text;
  v_cost_totals jsonb:='{}'::jsonb;
  v_currency_count integer:=0;
  v_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_economic_state text;
  v_blocking_plan_unresolved_count integer:=0;
  v_complete boolean:=false;
begin
  v_validation:=atlas.fulfillment_composition_validate_v1(p_packet);

  if v_validation->>'validationState'<>'passed' then
    return jsonb_build_object(
      'contractVersion','fulfillment_composition_position_v1',
      'state','invalid',
      'validation',v_validation,
      'completeForPlanning',false,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidPacketCreatesNoTruth',true
      )
    );
  end if;

  v_req_qty:=(v_validation->>'requirementQuantity')::numeric;
  v_req_unit:=v_validation->>'requirementUnit';
  v_output_qty:=(v_validation->>'outputQuantity')::numeric;
  v_cost_count:=(v_validation->>'costComponentCount')::integer;
  v_unresolved_required_cost_count:=(v_validation->>'unresolvedRequiredCostComponentCount')::integer;

  v_coverage_state:=case
    when v_output_qty<v_req_qty then 'undercovered'
    when v_output_qty>v_req_qty then 'overcovered'
    else 'exact'
  end;

  select
    coalesce(jsonb_object_agg(q.currency,to_jsonb(q.total_amount) order by q.currency),'{}'::jsonb),
    count(*)
  into v_cost_totals,v_currency_count
  from (
    select
      upper(c->>'currency') as currency,
      sum((c->>'amount')::numeric) as total_amount
    from jsonb_array_elements(p_packet->'allocations') a
    cross join lateral jsonb_array_elements(coalesce(a->'costComponents','[]'::jsonb)) c
    where c->>'state'='known'
      and jsonb_typeof(c->'amount')='number'
      and upper(coalesce(c->>'currency','')) ~ '^[A-Z]{3}$'
    group by upper(c->>'currency')
  ) q;

  if v_cost_count=0 then
    v_economic_state:='no_cost_evidence';
  elsif v_unresolved_required_cost_count>0 then
    v_economic_state:='unresolved';
  elsif v_currency_count>1 then
    v_economic_state:='known_multi_currency';
  else
    v_economic_state:='known';
  end if;

  if jsonb_typeof(coalesce(p_packet->'unresolved','[]'::jsonb))='array' then
    select count(*)
    into v_blocking_plan_unresolved_count
    from jsonb_array_elements(coalesce(p_packet->'unresolved','[]'::jsonb)) u
    where jsonb_typeof(u)='object'
      and jsonb_typeof(coalesce(u->'blockingFor','[]'::jsonb))='array'
      and exists(
        select 1
        from jsonb_array_elements_text(coalesce(u->'blockingFor','[]'::jsonb)) x
        where x='planning'
      );
  end if;

  v_complete:=
    v_coverage_state='exact'
    and v_blocking_plan_unresolved_count=0;

  return jsonb_build_object(
    'contractVersion','fulfillment_composition_position_v1',
    'state','ready',
    'planKey',p_packet->>'planKey',
    'requirementRef',p_packet->'requirementRef',
    'coverageState',v_coverage_state,
    'requiredQuantity',v_req_qty,
    'outputQuantity',v_output_qty,
    'unit',v_req_unit,
    'allocationCount',(v_validation->>'allocationCount')::integer,
    'economicState',v_economic_state,
    'knownCostTotalsByCurrency',v_cost_totals,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'blockingPlanningUnresolvedCount',v_blocking_plan_unresolved_count,
    'completeForPlanning',v_complete,
    'validation',v_validation,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'physicalCoverageDoesNotMeanSecuredCoverage',true,
      'economicPositionIsDerived',true,
      'unknownCostIsNeverZero',true,
      'multiCurrencyIsNotAutoConverted',true,
      'doesNotCreateCommercialTerms',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotReserveResources',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.fulfillment_composition_validate_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_composition_validate_v1(jsonb)
  to service_role;

revoke all on function atlas.fulfillment_composition_position_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_composition_position_v1(jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.fulfillment_composition_validate_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_neutral_fulfillment_composition_v1","purpose":"Read-only validation of one proposed quantified fulfillment composition packet.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.fulfillment_composition_position_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_neutral_fulfillment_composition_v1","purpose":"Read-only coverage and economic position for one validated fulfillment composition packet.","classificationRuleVersion":3}'::jsonb,
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

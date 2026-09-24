begin;

create or replace function atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
  p_line jsonb,
  p_facts jsonb,
  p_extra_nodes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_requirement jsonb;
  v_key text;
  v_expected jsonb;
  v_source_key text;
  v_source_value text;
  v_source_numeric numeric;
  v_state text;
  v_details jsonb;
  v_evidence jsonb;
  v_nodes jsonb:='[]'::jsonb;
  v_required boolean;
begin
  if p_line is null or jsonb_typeof(p_line)<>'object' then
    raise exception 'Flower line must be a JSON object.' using errcode='22023';
  end if;

  if p_facts is null or jsonb_typeof(p_facts)<>'object' then
    raise exception 'Flower source facts must be a JSON object.' using errcode='22023';
  end if;

  if jsonb_typeof(p_line->'requirements') is distinct from 'array' then
    raise exception 'Flower line requirements must be a JSON array.' using errcode='22023';
  end if;

  if p_extra_nodes is null or jsonb_typeof(p_extra_nodes)<>'array' then
    raise exception 'Extra qualification nodes must be a JSON array.' using errcode='22023';
  end if;

  for v_requirement in
    select value from jsonb_array_elements(p_line->'requirements')
  loop
    if jsonb_typeof(v_requirement)<>'object' then
      raise exception 'Requirement definitions must be JSON objects.' using errcode='22023';
    end if;

    v_key:=nullif(lower(btrim(coalesce(v_requirement->>'requirementKey',''))),'');
    if v_key is null then
      raise exception 'Requirement definition requires requirementKey.' using errcode='22023';
    end if;

    if v_requirement ? 'required' then
      if jsonb_typeof(v_requirement->'required')<>'boolean' then
        raise exception 'Requirement % required must be boolean.',v_key using errcode='22023';
      end if;
      v_required:=(v_requirement->>'required')::boolean;
    else
      v_required:=true;
    end if;

    v_source_key:=case v_key
      when 'flower_family' then 'flowerFamily'
      when 'product_family' then 'productFamily'
      when 'product_label' then 'productLabel'
      when 'variety' then 'variety'
      when 'cultivar' then 'cultivar'
      when 'color' then 'color'
      when 'grade' then 'grade'
      when 'product_form' then 'productForm'
      when 'stem_length_cm' then 'stemLengthCm'
      else null
    end;

    v_expected:=v_requirement->'expected';
    v_source_value:=case
      when v_source_key is null then null
      else nullif(btrim(coalesce(p_facts->>v_source_key,'')),'')
    end;
    v_state:='unresolved';
    v_details:=jsonb_build_object(
      'sourceFactKey',v_source_key,
      'sourceValue',v_source_value,
      'expected',v_expected
    );
    v_evidence:='[]'::jsonb;

    if v_source_key is not null and v_source_value is not null then
      v_evidence:=jsonb_build_array(jsonb_build_object(
        'sourceRef',coalesce(p_facts->>'sourceRef','unknown'),
        'fact',v_source_key||'='||v_source_value
      ));
    end if;

    if v_source_key is null then
      v_details:=v_details||jsonb_build_object('reason','unsupported_flower_requirement_key');
    elsif v_source_value is null then
      v_details:=v_details||jsonb_build_object('reason','source_fact_missing');
    elsif v_expected is null or jsonb_typeof(v_expected)<>'object' then
      v_details:=v_details||jsonb_build_object('reason','expected_rule_missing_or_invalid');
    elsif v_expected ? 'equals' then
      if jsonb_typeof(v_expected->'equals') not in ('string','number','boolean') then
        v_details:=v_details||jsonb_build_object('reason','equals_rule_not_scalar');
      else
        v_state:=case
          when lower(btrim(v_source_value))=lower(btrim(v_expected->>'equals'))
            then 'satisfied'
          else 'unsatisfied'
        end;
      end if;
    elsif v_expected ? 'minimum' or v_expected ? 'maximum' then
      begin
        v_source_numeric:=v_source_value::numeric;
      exception when others then
        v_source_numeric:=null;
      end;

      if v_source_numeric is null then
        v_details:=v_details||jsonb_build_object('reason','source_fact_not_numeric');
      elsif (v_expected ? 'minimum' and jsonb_typeof(v_expected->'minimum')<>'number')
         or (v_expected ? 'maximum' and jsonb_typeof(v_expected->'maximum')<>'number') then
        v_details:=v_details||jsonb_build_object('reason','numeric_rule_invalid');
      elsif (not (v_expected ? 'minimum') or v_source_numeric >= (v_expected->>'minimum')::numeric)
        and (not (v_expected ? 'maximum') or v_source_numeric <= (v_expected->>'maximum')::numeric) then
        v_state:='satisfied';
      else
        v_state:='unsatisfied';
      end if;
    else
      v_details:=v_details||jsonb_build_object('reason','unsupported_expected_operator');
    end if;

    v_nodes:=v_nodes||jsonb_build_array(jsonb_build_object(
      'requirementKey',v_key,
      'required',v_required,
      'state',v_state,
      'evidence',v_evidence,
      'details',v_details
    ));
  end loop;

  return v_nodes||p_extra_nodes;
end;
$function$;


create or replace function atlas.feast_guild_flower_owned_ready_candidate_v1(
  p_line jsonb,
  p_ready jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text:=nullif(btrim(coalesce(p_line->>'basketKey','')),'');
  v_line_key text:=nullif(btrim(coalesce(p_line->>'lineKey','')),'');
  v_req_qty numeric;
  v_req_unit text:=nullif(lower(btrim(coalesce(p_line->>'unit',''))),'');
  v_req_date date;
  v_ready_id text:=nullif(btrim(coalesce(p_ready->>'readyLotId','')),'');
  v_farm_id text:=nullif(btrim(coalesce(p_ready->>'farmId','')),'');
  v_available numeric;
  v_ready_unit text:=nullif(lower(btrim(coalesce(p_ready->>'unit',''))),'');
  v_ready_date date;
  v_usable_through date;
  v_exactness text:=lower(btrim(coalesce(p_ready->>'quantityExactness','')));
  v_output_qty numeric;
  v_facts jsonb;
  v_extra jsonb;
  v_nodes jsonb;
  v_availability_state text;
  v_capacity_state text;
  v_date_state text;
  v_freshness_state text;
begin
  if jsonb_typeof(p_line->'quantity') is distinct from 'number'
     or v_basket_key is null or v_line_key is null or v_req_unit is null then
    raise exception 'Owned Ready candidate requires basketKey, lineKey, numeric quantity, and unit.'
      using errcode='22023';
  end if;

  if p_ready is null or jsonb_typeof(p_ready)<>'object'
     or v_ready_id is null or v_farm_id is null then
    raise exception 'Owned Ready source packet requires readyLotId and farmId.'
      using errcode='22023';
  end if;

  v_req_qty:=(p_line->>'quantity')::numeric;
  v_req_date:=(p_line->>'requestedForDate')::date;
  v_available:=case
    when jsonb_typeof(p_ready->'availableQuantity')='number'
      then (p_ready->>'availableQuantity')::numeric
    else null
  end;
  v_ready_date:=case
    when nullif(btrim(coalesce(p_ready->>'readyDate','')),'') is not null
      then (p_ready->>'readyDate')::date
    else null
  end;

  v_usable_through:=case
    when nullif(btrim(coalesce(p_ready->'metadata'->>'usableThroughDate','')),'') is not null
      then (p_ready->'metadata'->>'usableThroughDate')::date
    else null
  end;

  v_availability_state:=case
    when v_available is null then 'unresolved'
    when v_available>0 and v_exactness='exact' then 'satisfied'
    when v_available<=0 then 'unsatisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available is null then 'unresolved'
    when v_ready_unit is distinct from v_req_unit then 'unsatisfied'
    when v_available>=v_req_qty then 'satisfied'
    else 'unsatisfied'
  end;

  v_date_state:=case
    when v_ready_date is null then 'unresolved'
    when v_ready_date<=v_req_date then 'satisfied'
    else 'unsatisfied'
  end;

  v_freshness_state:=case
    when v_usable_through is null then 'unresolved'
    when v_usable_through>=v_req_date then 'satisfied'
    else 'unsatisfied'
  end;

  v_output_qty:=case
    when v_available is null or v_available<=0 then v_req_qty
    else least(v_req_qty,v_available)
  end;

  v_facts:=jsonb_build_object(
    'sourceRef',v_ready_id,
    'flowerFamily',p_ready->'metadata'->>'flowerFamily',
    'productFamily',coalesce(
      nullif(btrim(coalesce(p_ready->'metadata'->>'productFamily','')),''),
      nullif(btrim(coalesce(p_ready->>'cropLabel','')),'')
    ),
    'productLabel',p_ready->>'productLabel',
    'variety',coalesce(
      nullif(btrim(coalesce(p_ready->'metadata'->>'variety','')),''),
      nullif(btrim(coalesce(p_ready->>'variety','')),'')
    ),
    'cultivar',p_ready->'metadata'->>'cultivar',
    'color',p_ready->'metadata'->>'color',
    'grade',p_ready->'metadata'->>'grade',
    'productForm',coalesce(
      nullif(btrim(coalesce(p_ready->'metadata'->>'productForm','')),''),
      nullif(btrim(coalesce(p_ready->>'inventoryKind','')),'')
    ),
    'stemLengthCm',p_ready->'metadata'->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_ready_id,
        'fact','availableQuantity='||coalesce(v_available::text,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_ready_id,
        'fact','requested='||v_req_qty::text||' '||v_req_unit||
               '; available='||coalesce(v_available::text,'unknown')||' '||coalesce(v_ready_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_ready_id,
        'fact','readyDate='||coalesce(v_ready_date::text,'unknown')||
               '; requestedForDate='||v_req_date::text
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_freshness',
      'required',true,
      'state',v_freshness_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_ready_id,
        'fact','usableThroughDate='||coalesce(v_usable_through::text,'unknown')||
               '; requestedForDate='||v_req_date::text
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','flower_ready_inventory',
      'sourceRef',v_ready_id
    ),
    'qualificationNodes',v_nodes,
    'fulfillmentPacket',jsonb_build_object(
      'contractVersion','neutral_fulfillment_composition_v1',
      'requirementRef',jsonb_build_object(
        'sourceDomain','feast_guild_flower_basket_v1',
        'sourceRef',v_basket_key||':'||v_line_key
      ),
      'requirement',jsonb_build_object(
        'quantity',v_req_qty,
        'unit',v_req_unit,
        'requiredBy',v_req_date
      ),
      'planKey','elm-ready:'||v_ready_id,
      'allocations',jsonb_build_array(jsonb_build_object(
        'allocationKey','elm-ready:'||v_ready_id,
        'candidateRef',jsonb_build_object(
          'sourceDomain','flower_ready_inventory',
          'sourceRef',v_ready_id
        ),
        'qualificationState',case
          when v_availability_state='satisfied'
           and v_capacity_state='satisfied'
           and v_date_state='satisfied'
           and v_freshness_state='satisfied' then 'qualified'
          else 'unresolved'
        end,
        'sourceQuantity',v_output_qty,
        'sourceUnit',v_req_unit,
        'outputQuantity',v_output_qty,
        'outputUnit',v_req_unit,
        'costComponents',jsonb_build_array(jsonb_build_object(
          'componentKey','owned_inventory_economic_cost',
          'state','unresolved',
          'required',true,
          'details',jsonb_build_object(
            'reason','governed_owned_inventory_cost_basis_not_established',
            'retailUnitValueIgnored',p_ready->'retailUnitValue',
            'retailCurrencyIgnored',p_ready->'retailCurrency'
          )
        ))
      )),
      'metadata',jsonb_build_object(
        'source','flower_ready_inventory_position_v1',
        'readyLotId',v_ready_id,
        'farmId',v_farm_id,
        'availableQuantity',v_available,
        'birthQuantity',p_ready->'birthQuantity',
        'retailValuationIsNotCost',true
      )
    ),
    'sourcePreference',jsonb_build_object(
      'tier','elm_owned_or_grown',
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_ready_id,
        'fact','ready inventory custody at Elm source farm '||v_farm_id
      ))
    ),
    'customerFacingSourceFacts',jsonb_build_object(
      'sourceClass','elm_owned_or_grown',
      'farmId',v_farm_id,
      'productLabel',p_ready->>'productLabel',
      'cropLabel',p_ready->>'cropLabel',
      'variety',p_ready->>'variety'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','flower_ready_inventory_position_v1',
      'usesAvailableQuantity',true,
      'usesBirthQuantityAsAvailability',false,
      'retailValuationUsedAsCost',false,
      'freshnessRequiresUsableThroughEvidence',true
    )
  );
end;
$function$;


revoke all on function atlas.feast_guild_flower_requirement_nodes_from_facts_v1(jsonb,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_requirement_nodes_from_facts_v1(jsonb,jsonb,jsonb)
  to service_role;

revoke all on function atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)
  to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.feast_guild_flower_requirement_nodes_from_facts_v1(jsonb,jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_helpers_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_helpers_v1","purpose":"Read-only Ready flower candidate projection that uses available quantity and never treats retail valuation as owned economic cost.","classificationRuleVersion":3}'::jsonb,
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

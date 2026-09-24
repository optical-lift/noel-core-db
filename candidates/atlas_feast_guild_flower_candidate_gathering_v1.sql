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
    raise exception 'Flower line must be a JSON object.'
      using errcode='22023';
  end if;

  if p_facts is null or jsonb_typeof(p_facts)<>'object' then
    raise exception 'Flower source facts must be a JSON object.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_line->'requirements') is distinct from 'array' then
    raise exception 'Flower line requirements must be a JSON array.'
      using errcode='22023';
  end if;

  if p_extra_nodes is null or jsonb_typeof(p_extra_nodes)<>'array' then
    raise exception 'Extra qualification nodes must be a JSON array.'
      using errcode='22023';
  end if;

  for v_requirement in
    select value from jsonb_array_elements(p_line->'requirements')
  loop
    if jsonb_typeof(v_requirement)<>'object' then
      raise exception 'Requirement definitions must be JSON objects.'
        using errcode='22023';
    end if;

    v_key:=nullif(lower(btrim(coalesce(v_requirement->>'requirementKey',''))),'');
    if v_key is null then
      raise exception 'Requirement definition requires requirementKey.'
        using errcode='22023';
    end if;

    if v_requirement ? 'required' then
      if jsonb_typeof(v_requirement->'required')<>'boolean' then
        raise exception 'Requirement % required must be boolean.',v_key
          using errcode='22023';
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
      v_state:='unresolved';
      v_details:=v_details||jsonb_build_object(
        'reason','unsupported_flower_requirement_key'
      );
    elsif v_source_value is null then
      v_state:='unresolved';
      v_details:=v_details||jsonb_build_object(
        'reason','source_fact_missing'
      );
    elsif v_expected is null or jsonb_typeof(v_expected)<>'object' then
      v_state:='unresolved';
      v_details:=v_details||jsonb_build_object(
        'reason','expected_rule_missing_or_invalid'
      );
    elsif v_expected ? 'equals' then
      if jsonb_typeof(v_expected->'equals') not in ('string','number','boolean') then
        v_state:='unresolved';
        v_details:=v_details||jsonb_build_object(
          'reason','equals_rule_not_scalar'
        );
      else
        v_state:=case
          when lower(btrim(v_source_value))=
               lower(btrim(v_expected->>'equals')) then 'satisfied'
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
        v_state:='unresolved';
        v_details:=v_details||jsonb_build_object(
          'reason','source_fact_not_numeric'
        );
      elsif (v_expected ? 'minimum' and jsonb_typeof(v_expected->'minimum')<>'number')
         or (v_expected ? 'maximum' and jsonb_typeof(v_expected->'maximum')<>'number') then
        v_state:='unresolved';
        v_details:=v_details||jsonb_build_object(
          'reason','numeric_rule_invalid'
        );
      elsif (not (v_expected ? 'minimum') or v_source_numeric >= (v_expected->>'minimum')::numeric)
        and (not (v_expected ? 'maximum') or v_source_numeric <= (v_expected->>'maximum')::numeric) then
        v_state:='satisfied';
      else
        v_state:='unsatisfied';
      end if;
    else
      v_state:='unresolved';
      v_details:=v_details||jsonb_build_object(
        'reason','unsupported_expected_operator'
      );
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
  v_exactness text:=lower(btrim(coalesce(p_ready->>'quantityExactness','')));
  v_output_qty numeric;
  v_facts jsonb;
  v_extra jsonb:='[]'::jsonb;
  v_nodes jsonb;
  v_availability_state text;
  v_capacity_state text;
  v_date_state text;
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

  v_output_qty:=case
    when v_available is null or v_available<=0 then v_req_qty
    else least(v_req_qty,v_available)
  end;

  v_facts:=jsonb_build_object(
    'sourceRef',v_ready_id,
    'flowerFamily',coalesce(
      nullif(btrim(coalesce(p_ready->'metadata'->>'flowerFamily','')),''),
      nullif(btrim(coalesce(p_ready->>'cropLabel','')),'')
    ),
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
           and v_date_state='satisfied' then 'qualified'
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
      'evidence',jsonb_build_array(
        jsonb_build_object(
          'sourceRef',v_ready_id,
          'fact','ready inventory custody at Elm source farm '||v_farm_id
        )
      )
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
      'retailValuationUsedAsCost',false
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_external_offer_candidate_v1(
  p_line jsonb,
  p_offering jsonb,
  p_observation jsonb,
  p_at_date date
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
  v_offering_id text:=nullif(btrim(coalesce(p_offering->>'externalSupplyOfferingId','')),'');
  v_observation_id text:=nullif(btrim(coalesce(p_observation->>'externalSupplyOfferObservationId','')),'');
  v_spec jsonb:=coalesce(p_offering->'specification','{}'::jsonb);
  v_context jsonb:=coalesce(p_observation->'sourceContext','{}'::jsonb);
  v_terms jsonb:=coalesce(p_observation->'terms','{}'::jsonb);

  v_price numeric;
  v_currency text:=nullif(upper(btrim(coalesce(p_observation->>'currency',''))),'');
  v_price_basis text:=lower(btrim(coalesce(p_observation->>'priceBasisState','unknown')));
  v_price_qty numeric;
  v_price_unit text:=nullif(lower(btrim(coalesce(p_observation->>'priceUnit',''))),'');
  v_pack_qty numeric;
  v_pack_unit text:=nullif(lower(btrim(coalesce(p_observation->>'packUnit',''))),'');
  v_min_qty numeric;
  v_min_unit text:=nullif(lower(btrim(coalesce(p_observation->>'minimumOrderUnit',''))),'');
  v_source_qty numeric;
  v_merchandise_cost numeric;

  v_availability text:=lower(btrim(coalesce(p_observation->>'availabilityState','unknown')));
  v_available_qty numeric;
  v_available_unit text:=nullif(lower(btrim(coalesce(v_context->>'availableQuantityUnit',''))),'');
  v_availability_state text;
  v_capacity_state text;
  v_date_state text;
  v_delivery_date date;
  v_lead_value numeric;
  v_lead_unit text:=nullif(lower(btrim(coalesce(p_observation->>'leadTimeUnit',''))),'');
  v_derived_available_by date;

  v_facts jsonb;
  v_extra jsonb;
  v_nodes jsonb;
  v_costs jsonb:='[]'::jsonb;
  v_freight_included boolean:=false;
  v_freight_amount numeric;
  v_freight_currency text;
  v_handling_amount numeric;
  v_handling_currency text;
  v_service_fee_amount numeric;
  v_service_fee_currency text;
  v_additional_fees_complete boolean:=false;
  v_source_preference jsonb;
  v_excess numeric;
begin
  if jsonb_typeof(p_line->'quantity') is distinct from 'number'
     or v_basket_key is null or v_line_key is null or v_req_unit is null then
    raise exception 'External candidate requires basketKey, lineKey, numeric quantity, and unit.'
      using errcode='22023';
  end if;

  if p_offering is null or jsonb_typeof(p_offering)<>'object'
     or p_observation is null or jsonb_typeof(p_observation)<>'object'
     or v_offering_id is null or v_observation_id is null then
    raise exception 'External candidate requires offering and observation identities.'
      using errcode='22023';
  end if;

  v_req_qty:=(p_line->>'quantity')::numeric;
  v_req_date:=(p_line->>'requestedForDate')::date;
  v_price:=case when jsonb_typeof(p_observation->'priceAmount')='number'
    then (p_observation->>'priceAmount')::numeric else null end;
  v_price_qty:=case when jsonb_typeof(p_observation->'priceQuantity')='number'
    then (p_observation->>'priceQuantity')::numeric else null end;
  v_pack_qty:=case when jsonb_typeof(p_observation->'packQuantity')='number'
    then (p_observation->>'packQuantity')::numeric else null end;
  v_min_qty:=case when jsonb_typeof(p_observation->'minimumOrderQuantity')='number'
    then (p_observation->>'minimumOrderQuantity')::numeric else null end;

  v_source_qty:=v_req_qty;

  if v_pack_qty is not null and v_pack_qty>0 and v_pack_unit=v_req_unit then
    v_source_qty:=ceil(v_source_qty/v_pack_qty)*v_pack_qty;
  end if;

  if v_min_qty is not null and v_min_unit=v_req_unit and v_min_qty>v_source_qty then
    v_source_qty:=v_min_qty;
    if v_pack_qty is not null and v_pack_qty>0 and v_pack_unit=v_req_unit then
      v_source_qty:=ceil(v_source_qty/v_pack_qty)*v_pack_qty;
    end if;
  end if;

  v_excess:=greatest(v_source_qty-v_req_qty,0);

  if v_price is not null
     and v_price_basis in ('source_explicit','confirmed')
     and v_price_qty is not null and v_price_qty>0
     and v_price_unit=v_req_unit
     and v_currency ~ '^[A-Z]{3}
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object(
        'reason','price_basis_or_unit_not_sufficient_for_requested_unit',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case when jsonb_typeof(v_terms->'freightIncluded')='boolean'
      then (v_terms->>'freightIncluded')::boolean else null end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case when jsonb_typeof(v_terms->'freightAmount')='number'
      then (v_terms->>'freightAmount')::numeric else null end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency is not null then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','known',
        'required',true,
        'amount',v_freight_amount,
        'currency',v_freight_currency,
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','freight_not_established')
      ));
    end if;
  end if;

  v_handling_amount:=case when jsonb_typeof(v_terms->'handlingAmount')='number'
    then (v_terms->>'handlingAmount')::numeric else null end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');
  if v_handling_amount is not null then
    if coalesce(v_handling_currency,v_currency) ~ '^[A-Z]{3}

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    if coalesce(v_service_fee_currency,v_currency) ~ '^[A-Z]{3}

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
    v_merchandise_cost:=v_price*v_source_qty/v_price_qty;
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','known',
      'required',true,
      'amount',v_merchandise_cost,
      'currency',v_currency,
      'sourceRef',v_observation_id
    ));
  else
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object(
        'reason','price_basis_or_unit_not_sufficient_for_requested_unit',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case when jsonb_typeof(v_terms->'freightIncluded')='boolean'
      then (v_terms->>'freightIncluded')::boolean else null end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case when jsonb_typeof(v_terms->'freightAmount')='number'
      then (v_terms->>'freightAmount')::numeric else null end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency is not null then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','known',
        'required',true,
        'amount',v_freight_amount,
        'currency',v_freight_currency,
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','freight_not_established')
      ));
    end if;
  end if;

  v_handling_amount:=case when jsonb_typeof(v_terms->'handlingAmount')='number'
    then (v_terms->>'handlingAmount')::numeric else null end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');
  if v_handling_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','handling',
      'state','known',
      'required',true,
      'amount',v_handling_amount,
      'currency',coalesce(v_handling_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','handling',
        'state','known',
        'required',true,
        'amount',v_handling_amount,
        'currency',coalesce(v_handling_currency,v_currency),
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','handling',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','handling_currency_not_established')
      ));
    end if;
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
    v_merchandise_cost:=v_price*v_source_qty/v_price_qty;
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','known',
      'required',true,
      'amount',v_merchandise_cost,
      'currency',v_currency,
      'sourceRef',v_observation_id
    ));
  else
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object(
        'reason','price_basis_or_unit_not_sufficient_for_requested_unit',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case when jsonb_typeof(v_terms->'freightIncluded')='boolean'
      then (v_terms->>'freightIncluded')::boolean else null end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case when jsonb_typeof(v_terms->'freightAmount')='number'
      then (v_terms->>'freightAmount')::numeric else null end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency is not null then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','known',
        'required',true,
        'amount',v_freight_amount,
        'currency',v_freight_currency,
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','freight_not_established')
      ));
    end if;
  end if;

  v_handling_amount:=case when jsonb_typeof(v_terms->'handlingAmount')='number'
    then (v_terms->>'handlingAmount')::numeric else null end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');
  if v_handling_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','handling',
      'state','known',
      'required',true,
      'amount',v_handling_amount,
      'currency',coalesce(v_handling_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','service_fee',
        'state','known',
        'required',true,
        'amount',v_service_fee_amount,
        'currency',coalesce(v_service_fee_currency,v_currency),
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','service_fee',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','service_fee_currency_not_established')
      ));
    end if;
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
    v_merchandise_cost:=v_price*v_source_qty/v_price_qty;
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','known',
      'required',true,
      'amount',v_merchandise_cost,
      'currency',v_currency,
      'sourceRef',v_observation_id
    ));
  else
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object(
        'reason','price_basis_or_unit_not_sufficient_for_requested_unit',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case when jsonb_typeof(v_terms->'freightIncluded')='boolean'
      then (v_terms->>'freightIncluded')::boolean else null end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case when jsonb_typeof(v_terms->'freightAmount')='number'
      then (v_terms->>'freightAmount')::numeric else null end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency is not null then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','known',
        'required',true,
        'amount',v_freight_amount,
        'currency',v_freight_currency,
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','freight_not_established')
      ));
    end if;
  end if;

  v_handling_amount:=case when jsonb_typeof(v_terms->'handlingAmount')='number'
    then (v_terms->>'handlingAmount')::numeric else null end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');
  if v_handling_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','handling',
      'state','known',
      'required',true,
      'amount',v_handling_amount,
      'currency',coalesce(v_handling_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','handling',
        'state','known',
        'required',true,
        'amount',v_handling_amount,
        'currency',coalesce(v_handling_currency,v_currency),
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','handling',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','handling_currency_not_established')
      ));
    end if;
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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
 then
    v_merchandise_cost:=v_price*v_source_qty/v_price_qty;
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','known',
      'required',true,
      'amount',v_merchandise_cost,
      'currency',v_currency,
      'sourceRef',v_observation_id
    ));
  else
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','supplier_merchandise',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object(
        'reason','price_basis_or_unit_not_sufficient_for_requested_unit',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case when jsonb_typeof(v_terms->'freightIncluded')='boolean'
      then (v_terms->>'freightIncluded')::boolean else null end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case when jsonb_typeof(v_terms->'freightAmount')='number'
      then (v_terms->>'freightAmount')::numeric else null end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency is not null then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','known',
        'required',true,
        'amount',v_freight_amount,
        'currency',v_freight_currency,
        'sourceRef',v_observation_id
      ));
    else
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','freight',
        'state','unresolved',
        'required',true,
        'sourceRef',v_observation_id,
        'details',jsonb_build_object('reason','freight_not_established')
      ));
    end if;
  end if;

  v_handling_amount:=case when jsonb_typeof(v_terms->'handlingAmount')='number'
    then (v_terms->>'handlingAmount')::numeric else null end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');
  if v_handling_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','handling',
      'state','known',
      'required',true,
      'amount',v_handling_amount,
      'currency',coalesce(v_handling_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_service_fee_amount:=case when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
    then (v_terms->>'serviceFeeAmount')::numeric else null end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');
  if v_service_fee_amount is not null then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','service_fee',
      'state','known',
      'required',true,
      'amount',v_service_fee_amount,
      'currency',coalesce(v_service_fee_currency,v_currency),
      'sourceRef',v_observation_id
    ));
  end if;

  v_additional_fees_complete:=coalesce(
    case when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
      then (v_terms->>'additionalFeesComplete')::boolean else null end,
    false
  );

  if not v_additional_fees_complete then
    v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
      'componentKey','additional_fees',
      'state','unresolved',
      'required',true,
      'sourceRef',v_observation_id,
      'details',jsonb_build_object('reason','additional_fee_completeness_not_established')
    ));
  end if;

  v_available_qty:=case when jsonb_typeof(v_context->'availableQuantity')='number'
    then (v_context->>'availableQuantity')::numeric else null end;

  v_availability_state:=case
    when v_availability='unavailable' then 'unsatisfied'
    when v_availability='available' then 'satisfied'
    when v_availability='limited' and v_available_qty is not null and v_available_qty>0 then 'satisfied'
    else 'unresolved'
  end;

  v_capacity_state:=case
    when v_available_qty is not null and v_available_unit=v_req_unit
      then case when v_available_qty>=v_source_qty then 'satisfied' else 'unsatisfied' end
    when lower(btrim(coalesce(v_context->>'capacityState','')))=
         'sufficient_for_requested_quantity' then 'satisfied'
    else 'unresolved'
  end;

  v_delivery_date:=case
    when nullif(btrim(coalesce(v_context->>'deliveryDate','')),'') is not null
      then (v_context->>'deliveryDate')::date
    when nullif(btrim(coalesce(v_context->>'availableByDate','')),'') is not null
      then (v_context->>'availableByDate')::date
    else null
  end;

  v_lead_value:=case when jsonb_typeof(p_observation->'leadTimeValue')='number'
    then (p_observation->>'leadTimeValue')::numeric else null end;

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_value is not null and v_lead_unit in ('day','days') then
    v_derived_available_by:=p_at_date+ceil(v_lead_value)::integer;
    v_date_state:=case when v_derived_available_by<=v_req_date then 'satisfied' else 'unsatisfied' end;
  else
    v_date_state:='unresolved';
  end if;

  v_facts:=jsonb_build_object(
    'sourceRef',v_observation_id,
    'flowerFamily',v_spec->>'flowerFamily',
    'productFamily',v_spec->>'productFamily',
    'productLabel',coalesce(v_spec->>'productLabel',p_offering->>'sourceLabel'),
    'variety',v_spec->>'variety',
    'cultivar',v_spec->>'cultivar',
    'color',v_spec->>'color',
    'grade',v_spec->>'grade',
    'productForm',v_spec->>'productForm',
    'stemLengthCm',v_spec->>'stemLengthCm'
  );

  v_extra:=jsonb_build_array(
    jsonb_build_object(
      'requirementKey','source_availability',
      'required',true,
      'state',v_availability_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','availabilityState='||v_availability
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_quantity_capacity',
      'required',true,
      'state',v_capacity_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact','requiredSourceQuantity='||v_source_qty::text||
               '; availableQuantity='||coalesce(v_available_qty::text,'unknown')||
               '; availableUnit='||coalesce(v_available_unit,'unknown')
      ))
    ),
    jsonb_build_object(
      'requirementKey','source_requested_date',
      'required',true,
      'state',v_date_state,
      'evidence',jsonb_build_array(jsonb_build_object(
        'sourceRef',v_observation_id,
        'fact',case
          when v_delivery_date is not null then 'sourceDate='||v_delivery_date::text
          when v_derived_available_by is not null then 'derivedFromLeadTime='||v_derived_available_by::text
          else 'requestedDateEvidence=unknown'
        end
      ))
    )
  );

  v_nodes:=atlas.feast_guild_flower_requirement_nodes_from_facts_v1(
    p_line,v_facts,v_extra
  );

  v_source_preference:=case
    when jsonb_typeof(v_context->'sourcePreference')='object'
      then v_context->'sourcePreference'
    else '{}'::jsonb
  end;

  return jsonb_build_object(
    'candidateRef',jsonb_build_object(
      'sourceDomain','external_supply_offering',
      'sourceRef',v_offering_id
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
      'planKey','external:'||v_offering_id||':'||v_observation_id,
      'allocations',jsonb_build_array(
        jsonb_build_object(
          'allocationKey','external:'||v_observation_id,
          'candidateRef',jsonb_build_object(
            'sourceDomain','external_supply_offering',
            'sourceRef',v_offering_id
          ),
          'qualificationState',case
            when v_availability_state='satisfied'
             and v_capacity_state='satisfied'
             and v_date_state='satisfied' then 'qualified'
            else 'unresolved'
          end,
          'sourceQuantity',v_source_qty,
          'sourceUnit',v_req_unit,
          'outputQuantity',v_req_qty,
          'outputUnit',v_req_unit,
          'excess',jsonb_build_object(
            'quantity',v_excess,
            'unit',v_req_unit,
            'dispositionState',case when v_excess>0 then 'unresolved_recovery' else 'none' end
          ),
          'costComponents',v_costs,
          'facts',jsonb_build_object(
            'supplierRelationshipId',p_offering->>'supplierRelationshipId',
            'externalSupplyOfferObservationId',v_observation_id
          )
        )
      ),
      'metadata',jsonb_build_object(
        'source','external_supply_offer_observation',
        'externalSupplyOfferingId',v_offering_id,
        'externalSupplyOfferObservationId',v_observation_id,
        'sourceLabel',p_offering->>'sourceLabel'
      )
    ),
    'sourcePreference',v_source_preference,
    'customerFacingSourceFacts',jsonb_build_object(
      'sourcePreferenceTier',v_source_preference->>'tier',
      'originCountry',v_context->>'originCountry',
      'originState',v_context->>'originState',
      'grower',v_context->>'grower'
    ),
    'gatheringBasis',jsonb_build_object(
      'source','external_supply_offer_observation',
      'quoteDate',p_at_date,
      'sourceQuantity',v_source_qty,
      'packQuantity',v_pack_qty,
      'minimumOrderQuantity',v_min_qty,
      'merchandiseCost',v_merchandise_cost,
      'freightIncluded',v_freight_included,
      'additionalFeesComplete',v_additional_fees_complete,
      'priceEffectiveDateIsNotDeliveryDate',true
    )
  );
end;
$function$;


create or replace function atlas.feast_guild_flower_candidate_sets_gather_service_v1(
  p_basket jsonb,
  p_source_organization_id uuid,
  p_elm_farm_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_basket_key text;
  v_requested_date date;
  v_line jsonb;
  v_line_packet jsonb;
  v_line_key text;
  v_unit text;
  v_candidates jsonb;
  v_candidate jsonb;
  v_ready jsonb;
  v_offering jsonb;
  v_observation jsonb;
  v_sets jsonb:='[]'::jsonb;
  v_owned_count integer;
  v_external_count integer;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object'
     or p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket must use feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_date:=(p_basket->>'requestedForDate')::date;

  if v_basket_key is null
     or jsonb_typeof(p_basket->'lines') is distinct from 'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket requires basketKey, requestedForDate, and non-empty lines.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farms f
    where f.id=p_elm_farm_id
      and f.organization_id=p_source_organization_id
      and f.status='active'
  ) then
    raise exception 'Elm source farm must be active and belong to the source organization.'
      using errcode='23514';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    if v_line_key is null or v_unit is null then
      raise exception 'Every basket line requires lineKey and unit.'
        using errcode='22023';
    end if;

    v_line_packet:=jsonb_set(
      jsonb_set(v_line,'{basketKey}',to_jsonb(v_basket_key),true),
      '{requestedForDate}',to_jsonb(v_requested_date::text),true
    );

    v_candidates:='[]'::jsonb;
    v_owned_count:=0;
    v_external_count:=0;

    for v_ready in
      select jsonb_build_object(
        'readyLotId',i.id,
        'farmId',i.farm_id,
        'cropProfileId',i.crop_profile_id,
        'cropLabel',i.crop_label,
        'variety',i.variety,
        'productLabel',i.product_label,
        'inventoryKind',i.inventory_kind,
        'birthQuantity',p.birth_quantity,
        'availableQuantity',p.available_quantity,
        'unit',i.unit,
        'quantityExactness',i.quantity_exactness,
        'readyDate',i.ready_date,
        'metadata',i.metadata,
        'retailUnitValue',i.retail_unit_value,
        'retailCurrency',i.retail_currency
      )
      from atlas.flower_ready_inventory_identity_v1 i
      join atlas.flower_ready_inventory_position_v1 p on p.id=i.id
      where i.farm_id=p_elm_farm_id
        and p.available_quantity>0
        and i.quantity_exactness='exact'
        and i.ready_date<=v_requested_date
        and lower(i.unit)=v_unit
      order by i.ready_date desc,i.id
    loop
      v_candidate:=atlas.feast_guild_flower_owned_ready_candidate_v1(
        v_line_packet,v_ready
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_owned_count:=v_owned_count+1;
    end loop;

    for v_offering,v_observation in
      select
        jsonb_build_object(
          'externalSupplyOfferingId',o.id,
          'supplierRelationshipId',o.supplier_relationship_id,
          'stableKey',o.stable_key,
          'sourceItemKey',o.source_item_key,
          'sourceLabel',o.source_label,
          'offeringKind',o.offering_kind,
          'sourceUnit',o.source_unit,
          'specification',o.specification
        ),
        jsonb_build_object(
          'externalSupplyOfferObservationId',obs.id,
          'observationKey',obs.observation_key,
          'observedAt',obs.observed_at,
          'effectiveFrom',obs.effective_from,
          'effectiveUntil',obs.effective_until,
          'priceAmount',obs.price_amount,
          'currency',obs.currency,
          'priceBasisState',obs.price_basis_state,
          'priceQuantity',obs.price_quantity,
          'priceUnit',obs.price_unit,
          'packQuantity',obs.pack_quantity,
          'packUnit',obs.pack_unit,
          'minimumOrderQuantity',obs.minimum_order_quantity,
          'minimumOrderUnit',obs.minimum_order_unit,
          'leadTimeValue',obs.lead_time_value,
          'leadTimeUnit',obs.lead_time_unit,
          'availabilityState',obs.availability_state,
          'terms',obs.terms,
          'sourceContext',obs.source_context,
          'sourceKind',obs.source_kind,
          'sourceRef',obs.source_ref
        )
      from atlas.external_supply_offerings o
      join atlas.external_relationships r
        on r.id=o.supplier_relationship_id
       and r.organization_id=p_source_organization_id
       and r.relationship_state='active'
      join atlas.external_relationship_roles rr
        on rr.external_relationship_id=r.id
       and rr.role_key='supplier'
       and rr.role_state='active'
      join lateral (
        select x.*
        from atlas.external_supply_offer_observations x
        where x.external_supply_offering_id=o.id
          and (x.effective_from is null or x.effective_from<=p_at_date)
          and (x.effective_until is null or x.effective_until>=p_at_date)
        order by x.observed_at desc,x.created_at desc,x.id desc
        limit 1
      ) obs on true
      where o.organization_id=p_source_organization_id
        and o.status='active'
        and (
          o.source_unit is null
          or lower(o.source_unit)=v_unit
          or lower(coalesce(obs.price_unit,''))=v_unit
          or lower(coalesce(obs.pack_unit,''))=v_unit
        )
      order by o.source_label,o.id
    loop
      v_candidate:=atlas.feast_guild_flower_external_offer_candidate_v1(
        v_line_packet,v_offering,v_observation,p_at_date
      );
      v_candidates:=v_candidates||jsonb_build_array(v_candidate);
      v_external_count:=v_external_count+1;
    end loop;

    v_sets:=v_sets||jsonb_build_array(jsonb_build_object(
      'lineKey',v_line_key,
      'ownedReadyCandidateCount',v_owned_count,
      'externalCandidateCount',v_external_count,
      'candidateCount',jsonb_array_length(v_candidates),
      'candidates',v_candidates
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_candidate_sets_v1',
    'basketKey',v_basket_key,
    'sourceOrganizationId',p_source_organization_id,
    'elmFarmId',p_elm_farm_id,
    'atDate',p_at_date,
    'requestedForDate',v_requested_date,
    'lineCandidateSets',v_sets,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'readyInventoryUsesAvailableQuantity',true,
      'retailValuationIsNotOwnedCost',true,
      'sourceListingDoesNotMeanAvailability',true,
      'priceEffectiveDateIsNotDeliveryPromise',true,
      'doesNotReserveInventory',true,
      'doesNotReserveSupplierStock',true,
      'doesNotSelectWinner',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotPurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateWork',true,
      'doesNotExecuteFulfillment',true
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

revoke all on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)
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
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only normalized flower requirement matching; unsupported or missing facts remain unresolved.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_owned_ready_candidate_v1(jsonb,jsonb)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of actual Ready flower availability into a Feast Guild candidate plan without treating retail valuation as economic cost.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Read-only projection of one admitted supplier offer observation into flower qualification, pack economics, and landed-cost evidence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)',
  'service_internal','provisional','active',
  false,true,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_v1","purpose":"Service-only read of actual Elm Ready inventory and admitted external supply observations into per-line candidate sets.","classificationRuleVersion":3}'::jsonb,
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

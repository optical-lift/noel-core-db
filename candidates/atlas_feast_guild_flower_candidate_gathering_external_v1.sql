begin;

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
  v_excess numeric;

  v_availability text:=lower(btrim(coalesce(p_observation->>'availabilityState','unknown')));
  v_available_qty numeric;
  v_available_unit text:=nullif(lower(btrim(coalesce(v_context->>'availableQuantityUnit',''))),'');
  v_availability_state text;
  v_capacity_state text;
  v_date_state text;
  v_delivery_date date;
  v_lead_value numeric;
  v_lead_unit text:=nullif(lower(btrim(coalesce(p_observation->>'leadTimeUnit',''))),'');
  v_lead_time_usable boolean:=false;
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

  v_price:=case
    when jsonb_typeof(p_observation->'priceAmount')='number'
      then (p_observation->>'priceAmount')::numeric
    else null
  end;
  v_price_qty:=case
    when jsonb_typeof(p_observation->'priceQuantity')='number'
      then (p_observation->>'priceQuantity')::numeric
    else null
  end;
  v_pack_qty:=case
    when jsonb_typeof(p_observation->'packQuantity')='number'
      then (p_observation->>'packQuantity')::numeric
    else null
  end;
  v_min_qty:=case
    when jsonb_typeof(p_observation->'minimumOrderQuantity')='number'
      then (p_observation->>'minimumOrderQuantity')::numeric
    else null
  end;

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
     and v_currency ~ '^[A-Z]{3}$' then
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
        'reason','price_basis_currency_or_unit_not_sufficient',
        'priceBasisState',v_price_basis,
        'priceQuantity',v_price_qty,
        'priceUnit',v_price_unit,
        'currency',v_currency,
        'requestedUnit',v_req_unit
      )
    ));
  end if;

  v_freight_included:=coalesce(
    case
      when jsonb_typeof(v_terms->'freightIncluded')='boolean'
        then (v_terms->>'freightIncluded')::boolean
      else null
    end,
    false
  );

  if not v_freight_included then
    v_freight_amount:=case
      when jsonb_typeof(v_terms->'freightAmount')='number'
        then (v_terms->>'freightAmount')::numeric
      else null
    end;
    v_freight_currency:=nullif(upper(btrim(coalesce(v_terms->>'freightCurrency',''))),'');

    if v_freight_amount is not null and v_freight_currency ~ '^[A-Z]{3}$' then
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

  v_handling_amount:=case
    when jsonb_typeof(v_terms->'handlingAmount')='number'
      then (v_terms->>'handlingAmount')::numeric
    else null
  end;
  v_handling_currency:=nullif(upper(btrim(coalesce(v_terms->>'handlingCurrency',''))),'');

  if v_handling_amount is not null then
    if v_handling_currency ~ '^[A-Z]{3}$' then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','handling',
        'state','known',
        'required',true,
        'amount',v_handling_amount,
        'currency',v_handling_currency,
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

  v_service_fee_amount:=case
    when jsonb_typeof(v_terms->'serviceFeeAmount')='number'
      then (v_terms->>'serviceFeeAmount')::numeric
    else null
  end;
  v_service_fee_currency:=nullif(upper(btrim(coalesce(v_terms->>'serviceFeeCurrency',''))),'');

  if v_service_fee_amount is not null then
    if v_service_fee_currency ~ '^[A-Z]{3}$' then
      v_costs:=v_costs||jsonb_build_array(jsonb_build_object(
        'componentKey','service_fee',
        'state','known',
        'required',true,
        'amount',v_service_fee_amount,
        'currency',v_service_fee_currency,
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
    case
      when jsonb_typeof(v_terms->'additionalFeesComplete')='boolean'
        then (v_terms->>'additionalFeesComplete')::boolean
      else null
    end,
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

  v_available_qty:=case
    when jsonb_typeof(v_context->'availableQuantity')='number'
      then (v_context->>'availableQuantity')::numeric
    else null
  end;

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

  v_lead_value:=case
    when jsonb_typeof(p_observation->'leadTimeValue')='number'
      then (p_observation->>'leadTimeValue')::numeric
    else null
  end;

  v_lead_time_usable:=coalesce(
    case
      when jsonb_typeof(v_context->'leadTimeUsableForRequestedDate')='boolean'
        then (v_context->>'leadTimeUsableForRequestedDate')::boolean
      else null
    end,
    false
  );

  if v_delivery_date is not null then
    v_date_state:=case when v_delivery_date<=v_req_date then 'satisfied' else 'unsatisfied' end;
  elsif v_lead_time_usable
     and v_lead_value is not null
     and v_lead_unit in ('day','days') then
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
      'allocations',jsonb_build_array(jsonb_build_object(
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
      )),
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

revoke all on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)
  to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.feast_guild_flower_external_offer_candidate_v1(jsonb,jsonb,jsonb,date)',
  'service_internal','provisional','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_flower_candidate_gathering_external_v1","purpose":"Read-only admitted supplier offer projection into normalized flower qualification, pack economics, availability/date evidence, and explicit landed-cost completeness.","classificationRuleVersion":3}'::jsonb,
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

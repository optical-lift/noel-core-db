begin;

create or replace function atlas.feast_guild_flower_quote_prepare_v1(
  p_basket jsonb,
  p_line_plans jsonb,
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
  v_requested_for_date text;
  v_line jsonb;
  v_line_key text;
  v_line_keys text[]:='{}'::text[];
  v_description text;
  v_quantity numeric;
  v_unit text;
  v_requirements jsonb;
  v_requirement_definition jsonb;
  v_requirement_key text;
  v_requirement_required boolean;
  v_evidence_required boolean;

  v_plan jsonb;
  v_plan_candidate jsonb;
  v_plan_nodes jsonb;
  v_plan_node jsonb;
  v_plan_count integer;
  v_matching_node_count integer;
  v_fulfillment_packet jsonb;
  v_requirement_ref jsonb;
  v_qualification jsonb;
  v_price jsonb;
  v_source_facts jsonb;
  v_selection_basis jsonb;

  v_lines jsonb:='[]'::jsonb;
  v_snapshot_lines jsonb:='[]'::jsonb;
  v_blocking_reasons jsonb:='[]'::jsonb;
  v_line_result jsonb;
  v_line_block_reasons jsonb;
  v_snapshot_line jsonb;

  v_line_count integer:=0;
  v_priced_count integer:=0;
  v_blocked_count integer:=0;
  v_priced_subtotal numeric:=0;
  v_order_currency text;
  v_currency_mismatch boolean:=false;
  v_quote_state text;

  v_org_id text;
  v_org_unit_id text;
  v_snapshot_key text;
  v_snapshot_title text;
  v_valid_from text;
  v_valid_until text;
  v_source_ref text;
begin
  if p_basket is null or jsonb_typeof(p_basket)<>'object' then
    raise exception 'Feast Guild basket must be a JSON object.'
      using errcode='22023';
  end if;

  if p_basket->>'contractVersion'<>'feast_guild_flower_basket_v1' then
    raise exception 'Basket contractVersion must be feast_guild_flower_basket_v1.'
      using errcode='22023';
  end if;

  v_basket_key:=nullif(btrim(coalesce(p_basket->>'basketKey','')),'');
  v_requested_for_date:=nullif(btrim(coalesce(p_basket->>'requestedForDate','')),'');
  if v_basket_key is null or v_requested_for_date is null then
    raise exception 'Basket requires basketKey and requestedForDate.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_basket->'lines')<>'array'
     or jsonb_array_length(p_basket->'lines')=0 then
    raise exception 'Basket lines must be a non-empty JSON array.'
      using errcode='22023';
  end if;

  if p_line_plans is null
     or jsonb_typeof(p_line_plans)<>'array' then
    raise exception 'Selected line plans must be a JSON array.'
      using errcode='22023';
  end if;

  if p_pricing_policy is null
     or jsonb_typeof(p_pricing_policy)<>'object' then
    raise exception 'Pricing policy must be a JSON object.'
      using errcode='22023';
  end if;

  if p_quote_context is null
     or jsonb_typeof(p_quote_context)<>'object' then
    raise exception 'Quote context must be a JSON object.'
      using errcode='22023';
  end if;

  v_org_id:=nullif(btrim(coalesce(p_quote_context->>'organizationId','')),'');
  v_org_unit_id:=nullif(btrim(coalesce(p_quote_context->>'organizationUnitId','')),'');
  v_snapshot_key:=nullif(btrim(coalesce(p_quote_context->>'snapshotKey','')),'');
  v_snapshot_title:=nullif(btrim(coalesce(p_quote_context->>'title','')),'');
  v_valid_from:=nullif(btrim(coalesce(p_quote_context->>'validFrom','')),'');
  v_valid_until:=nullif(btrim(coalesce(p_quote_context->>'validUntil','')),'');
  v_source_ref:=nullif(btrim(coalesce(p_quote_context->>'sourceRef','')),'');

  if v_org_id is null
     or v_snapshot_key is null
     or v_snapshot_title is null
     or v_valid_from is null
     or v_valid_until is null
     or v_source_ref is null then
    raise exception 'Quote context requires organizationId, snapshotKey, title, validFrom, validUntil, and sourceRef.'
      using errcode='22023';
  end if;

  for v_line in
    select value
    from jsonb_array_elements(p_basket->'lines')
  loop
    v_line_count:=v_line_count+1;
    v_line_block_reasons:='[]'::jsonb;

    if jsonb_typeof(v_line)<>'object' then
      raise exception 'Every basket line must be a JSON object.'
        using errcode='22023';
    end if;

    v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
    v_description:=nullif(btrim(coalesce(v_line->>'description','')),'');
    v_unit:=nullif(lower(btrim(coalesce(v_line->>'unit',''))),'');
    v_requirements:=v_line->'requirements';

    if v_line_key is null or v_description is null or v_unit is null then
      raise exception 'Every basket line requires lineKey, description, and unit.'
        using errcode='22023';
    end if;

    if v_line_key=any(v_line_keys) then
      raise exception 'Basket line key % appears more than once.',v_line_key
        using errcode='22023';
    end if;
    v_line_keys:=array_append(v_line_keys,v_line_key);

    if jsonb_typeof(v_line->'quantity')<>'number' then
      raise exception 'Basket line % quantity must be numeric.',v_line_key
        using errcode='22023';
    end if;
    v_quantity:=(v_line->>'quantity')::numeric;
    if v_quantity<=0 then
      raise exception 'Basket line % quantity must be greater than zero.',v_line_key
        using errcode='22023';
    end if;

    if v_requirements is null
       or jsonb_typeof(v_requirements)<>'array'
       or jsonb_array_length(v_requirements)=0 then
      raise exception 'Basket line % requires a non-empty requirements array.',v_line_key
        using errcode='22023';
    end if;

    select count(*)
    into v_plan_count
    from jsonb_array_elements(p_line_plans) as p(value)
    where p.value->>'lineKey'=v_line_key;

    if v_plan_count<>1 then
      v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
        jsonb_build_object(
          'reason',case when v_plan_count=0
            then 'missing_selected_line_plan'
            else 'multiple_selected_line_plans'
          end,
          'lineKey',v_line_key,
          'matchingPlanCount',v_plan_count
        )
      );
      v_plan:=null;
    else
      select p.value
      into v_plan
      from jsonb_array_elements(p_line_plans) as p(value)
      where p.value->>'lineKey'=v_line_key
      limit 1;
    end if;

    if v_plan is not null then
      if jsonb_typeof(v_plan->'candidateRef')<>'object' then
        v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
          jsonb_build_object('reason','missing_candidate_ref','lineKey',v_line_key)
        );
      else
        v_plan_candidate:=v_plan->'candidateRef';
      end if;

      if jsonb_typeof(v_plan->'qualificationNodes')<>'array' then
        v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
          jsonb_build_object('reason','missing_qualification_nodes','lineKey',v_line_key)
        );
        v_plan_nodes:='[]'::jsonb;
      else
        v_plan_nodes:=v_plan->'qualificationNodes';
      end if;

      if jsonb_typeof(v_plan->'fulfillmentPacket')<>'object' then
        v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
          jsonb_build_object('reason','missing_fulfillment_packet','lineKey',v_line_key)
        );
        v_fulfillment_packet:=null;
      else
        v_fulfillment_packet:=v_plan->'fulfillmentPacket';
      end if;

      if v_plan ? 'customerFacingSourceFacts'
         and jsonb_typeof(v_plan->'customerFacingSourceFacts')<>'object' then
        raise exception 'Line plan % customerFacingSourceFacts must be an object.',v_line_key
          using errcode='22023';
      end if;
      v_source_facts:=coalesce(v_plan->'customerFacingSourceFacts','{}'::jsonb);

      if v_plan ? 'selectionBasis'
         and jsonb_typeof(v_plan->'selectionBasis')<>'object' then
        raise exception 'Line plan % selectionBasis must be an object.',v_line_key
          using errcode='22023';
      end if;
      v_selection_basis:=coalesce(v_plan->'selectionBasis','{}'::jsonb);

      for v_requirement_definition in
        select value from jsonb_array_elements(v_requirements)
      loop
        if jsonb_typeof(v_requirement_definition)<>'object' then
          raise exception 'Basket line % requirement definitions must be objects.',v_line_key
            using errcode='22023';
        end if;

        v_requirement_key:=nullif(btrim(coalesce(v_requirement_definition->>'requirementKey','')),'');
        if v_requirement_key is null then
          raise exception 'Basket line % requirement definition requires requirementKey.',v_line_key
            using errcode='22023';
        end if;

        if v_requirement_definition ? 'required' then
          if jsonb_typeof(v_requirement_definition->'required')<>'boolean' then
            raise exception 'Basket line % requirement % required must be boolean.',
              v_line_key,v_requirement_key using errcode='22023';
          end if;
          v_requirement_required:=(v_requirement_definition->>'required')::boolean;
        else
          v_requirement_required:=true;
        end if;

        if v_requirement_definition ? 'evidenceRequired' then
          if jsonb_typeof(v_requirement_definition->'evidenceRequired')<>'boolean' then
            raise exception 'Basket line % requirement % evidenceRequired must be boolean.',
              v_line_key,v_requirement_key using errcode='22023';
          end if;
          v_evidence_required:=(v_requirement_definition->>'evidenceRequired')::boolean;
        else
          v_evidence_required:=v_requirement_required;
        end if;

        if v_requirement_required then
          select count(*)
          into v_matching_node_count
          from jsonb_array_elements(v_plan_nodes) as n(value)
          where n.value->>'requirementKey'=v_requirement_key;

          if v_matching_node_count<>1 then
            v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
              jsonb_build_object(
                'reason',case when v_matching_node_count=0
                  then 'missing_required_qualification_node'
                  else 'duplicate_required_qualification_node'
                end,
                'lineKey',v_line_key,
                'requirementKey',v_requirement_key,
                'matchingNodeCount',v_matching_node_count
              )
            );
          else
            select n.value
            into v_plan_node
            from jsonb_array_elements(v_plan_nodes) as n(value)
            where n.value->>'requirementKey'=v_requirement_key
            limit 1;

            if v_evidence_required
               and lower(btrim(coalesce(v_plan_node->>'state','')))= 'satisfied'
               and (
                 jsonb_typeof(v_plan_node->'evidence')<>'array'
                 or jsonb_array_length(v_plan_node->'evidence')=0
               ) then
              v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
                jsonb_build_object(
                  'reason','required_qualification_evidence_missing',
                  'lineKey',v_line_key,
                  'requirementKey',v_requirement_key
                )
              );
            end if;
          end if;
        end if;
      end loop;

      v_requirement_ref:=jsonb_build_object(
        'sourceDomain','feast_guild_flower_basket_v1',
        'sourceRef',v_basket_key||':'||v_line_key
      );

      if jsonb_array_length(v_line_block_reasons)=0 then
        v_qualification:=atlas.fulfillment_candidate_qualification_v1(
          v_requirement_ref,
          v_plan_candidate,
          v_plan_nodes,
          jsonb_build_object(
            'basketKey',v_basket_key,
            'lineKey',v_line_key,
            'requestedForDate',v_requested_for_date,
            'selectedPlan',true
          )
        );

        if v_qualification->>'qualificationState'<>'qualified' then
          v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
            jsonb_build_object(
              'reason','selected_candidate_not_qualified',
              'lineKey',v_line_key,
              'qualificationState',v_qualification->>'qualificationState'
            )
          );
        end if;
      end if;

      if v_fulfillment_packet is not null
         and jsonb_array_length(v_line_block_reasons)=0 then
        if v_fulfillment_packet->'requirementRef'->>'sourceDomain'
             is distinct from v_requirement_ref->>'sourceDomain'
           or v_fulfillment_packet->'requirementRef'->>'sourceRef'
             is distinct from v_requirement_ref->>'sourceRef' then
          v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
            jsonb_build_object(
              'reason','fulfillment_requirement_ref_mismatch',
              'lineKey',v_line_key
            )
          );
        end if;

        if jsonb_typeof(v_fulfillment_packet->'requirement'->'quantity')<>'number'
           or (v_fulfillment_packet->'requirement'->>'quantity')::numeric<>v_quantity
           or lower(btrim(coalesce(v_fulfillment_packet->'requirement'->>'unit','')))<>v_unit then
          v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
            jsonb_build_object(
              'reason','fulfillment_quantity_or_unit_mismatch',
              'lineKey',v_line_key,
              'requestedQuantity',v_quantity,
              'requestedUnit',v_unit
            )
          );
        end if;
      end if;

      if v_fulfillment_packet is not null
         and jsonb_array_length(v_line_block_reasons)=0 then
        v_price:=atlas.commercial_price_evaluate_v1(
          v_fulfillment_packet,
          p_pricing_policy
        );

        if v_price->>'state'<>'priced' then
          v_line_block_reasons:=v_line_block_reasons||jsonb_build_array(
            jsonb_build_object(
              'reason','line_pricing_blocked',
              'lineKey',v_line_key,
              'pricingReason',v_price->>'reason'
            )
          );
        end if;
      end if;
    else
      v_plan_candidate:=null;
      v_plan_nodes:='[]'::jsonb;
      v_fulfillment_packet:=null;
      v_qualification:=null;
      v_price:=null;
      v_source_facts:='{}'::jsonb;
      v_selection_basis:='{}'::jsonb;
    end if;

    if jsonb_array_length(v_line_block_reasons)=0 then
      v_priced_count:=v_priced_count+1;
      v_priced_subtotal:=v_priced_subtotal+(v_price->>'proposedTotal')::numeric;

      if v_order_currency is null then
        v_order_currency:=v_price->>'currency';
      elsif v_order_currency is distinct from v_price->>'currency' then
        v_currency_mismatch:=true;
      end if;

      v_line_result:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'state','priced',
        'requestedQuantity',v_quantity,
        'unit',v_unit,
        'selectedCandidateRef',v_plan_candidate,
        'selectionBasis',v_selection_basis,
        'customerFacingSourceFacts',v_source_facts,
        'qualification',v_qualification,
        'fulfillmentPlanKey',v_fulfillment_packet->>'planKey',
        'totalKnownFulfillmentCost',(v_price->>'totalKnownFulfillmentCost')::numeric,
        'costPerUnit',(v_price->>'costPerUnit')::numeric,
        'currency',v_price->>'currency',
        'proposedUnitPrice',(v_price->>'proposedUnitPrice')::numeric,
        'proposedTotal',(v_price->>'proposedTotal')::numeric
      );

      v_snapshot_line:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'quantityAvailable',v_quantity,
        'unit',v_unit,
        'unitPrice',(v_price->>'proposedUnitPrice')::numeric,
        'currency',v_price->>'currency',
        'priceBasis','derived_from_fulfillment_economics',
        'terms',jsonb_build_object(
          'quotedQuantity',v_quantity,
          'proposedTotal',(v_price->>'proposedTotal')::numeric,
          'requestedForDate',v_requested_for_date,
          'fulfillmentPlanKey',v_fulfillment_packet->>'planKey'
        ),
        'sourceRef',v_plan_candidate->>'sourceRef',
        'metadata',jsonb_build_object(
          'quotePreparationContract','feast_guild_flower_quote_preparation_v1',
          'sourceDomain',v_plan_candidate->>'sourceDomain',
          'customerFacingSourceFacts',v_source_facts,
          'selectionBasis',v_selection_basis
        )
      );
    else
      v_blocked_count:=v_blocked_count+1;

      v_line_result:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'state','blocked',
        'requestedQuantity',v_quantity,
        'unit',v_unit,
        'selectedCandidateRef',v_plan_candidate,
        'selectionBasis',v_selection_basis,
        'customerFacingSourceFacts',v_source_facts,
        'blockingReasons',v_line_block_reasons,
        'qualification',v_qualification,
        'pricing',v_price
      );

      v_snapshot_line:=jsonb_build_object(
        'lineKey',v_line_key,
        'description',v_description,
        'quantityAvailable',null,
        'unit',v_unit,
        'unitPrice',null,
        'currency',null,
        'priceBasis',null,
        'terms',jsonb_build_object(
          'quoteState','blocked',
          'requestedQuantity',v_quantity,
          'requestedForDate',v_requested_for_date,
          'blockingReasons',v_line_block_reasons
        ),
        'sourceRef',case
          when v_plan_candidate is null then null
          else v_plan_candidate->>'sourceRef'
        end,
        'metadata',jsonb_build_object(
          'quotePreparationContract','feast_guild_flower_quote_preparation_v1',
          'incompleteEvidence',true
        )
      );

      v_blocking_reasons:=v_blocking_reasons||jsonb_build_array(
        jsonb_build_object(
          'lineKey',v_line_key,
          'reasons',v_line_block_reasons
        )
      );
    end if;

    v_lines:=v_lines||jsonb_build_array(v_line_result);
    v_snapshot_lines:=v_snapshot_lines||jsonb_build_array(v_snapshot_line);
  end loop;

  if jsonb_array_length(p_line_plans)<>v_line_count then
    v_blocking_reasons:=v_blocking_reasons||jsonb_build_array(
      jsonb_build_object(
        'reason','selected_line_plan_count_mismatch',
        'basketLineCount',v_line_count,
        'selectedPlanCount',jsonb_array_length(p_line_plans)
      )
    );
  end if;

  if v_currency_mismatch then
    v_blocking_reasons:=v_blocking_reasons||jsonb_build_array(
      jsonb_build_object(
        'reason','whole_order_currency_mismatch',
        'message','Whole-order total is blocked until all priced lines use one currency.'
      )
    );
  end if;

  v_quote_state:=case
    when v_blocked_count=0
      and not v_currency_mismatch
      and jsonb_array_length(p_line_plans)=v_line_count
      then 'complete'
    else 'incomplete'
  end;

  return jsonb_build_object(
    'contractVersion','feast_guild_flower_quote_preparation_v1',
    'basketKey',v_basket_key,
    'requestedForDate',v_requested_for_date,
    'state',v_quote_state,
    'lineCount',v_line_count,
    'pricedLineCount',v_priced_count,
    'blockedLineCount',v_blocked_count,
    'currency',case when v_currency_mismatch then null else v_order_currency end,
    'pricedSubtotal',v_priced_subtotal,
    'wholeOrderTotal',case
      when v_quote_state='complete' then v_priced_subtotal
      else null
    end,
    'lines',v_lines,
    'blockingReasons',v_blocking_reasons,
    'snapshotDraft',jsonb_build_object(
      'organizationId',v_org_id,
      'organizationUnitId',v_org_unit_id,
      'snapshotKey',v_snapshot_key,
      'title',v_snapshot_title,
      'offerState',case
        when v_quote_state='complete' then 'complete'
        else 'incomplete_evidence'
      end,
      'validFrom',v_valid_from,
      'validUntil',v_valid_until,
      'lines',v_snapshot_lines,
      'assets','[]'::jsonb,
      'sourceKind','domain_snapshot',
      'sourceRef',v_source_ref,
      'metadata',jsonb_build_object(
        'quotePreparationContract','feast_guild_flower_quote_preparation_v1',
        'basketKey',v_basket_key,
        'requestedForDate',v_requested_for_date,
        'wholeOrderState',v_quote_state,
        'pricedSubtotal',v_priced_subtotal,
        'wholeOrderTotal',case
          when v_quote_state='complete' then v_priced_subtotal
          else null
        end
      )
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'selectedPlanIsExplicitInput',true,
      'doesNotChooseSupplier',true,
      'doesNotInferProductEquivalence',true,
      'unknownCostIsNeverZero',true,
      'incompleteLineBlocksWholeOrderTotal',true,
      'customerFacingSourceFactsArePresentationOnly',true,
      'doesNotPersistPricingPolicy',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true,
      'doesNotCreateSupplierCommitment',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCreatePayment',true,
      'doesNotExecuteFulfillment',true
    )
  );
end;
$function$;

revoke all on function atlas.feast_guild_flower_quote_prepare_v1(jsonb,jsonb,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.feast_guild_flower_quote_prepare_v1(jsonb,jsonb,jsonb,jsonb)
  to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.feast_guild_flower_quote_prepare_v1(jsonb,jsonb,jsonb,jsonb)',
  'service_internal','candidate','active',
  false,false,true,0,1,
  '{"source":"atlas_feast_guild_whole_order_quote_v1","purpose":"Read-only Feast Guild flower basket adapter over universal qualification, fulfillment composition, and protected price evaluation.","classificationRuleVersion":3}'::jsonb,
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

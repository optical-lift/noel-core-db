begin;

create or replace function atlas.work_requirement_coverage_position_v1(
  p_work_requirement_id uuid,
  p_coverage_facts jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_requirement atlas.work_requirements%rowtype;
  v_fact jsonb;
  v_key text;
  v_state text;
  v_extent text;
  v_quantity numeric;
  v_unit text;
  v_required_quantity numeric;
  v_required_unit text;
  v_quantified boolean:=false;
  v_keys text[]:='{}'::text[];
  v_violations jsonb:='[]'::jsonb;
  v_normalized jsonb:='[]'::jsonb;

  v_secured_quantity numeric:=0;
  v_provisional_quantity numeric:=0;

  v_secured_count integer:=0;
  v_provisional_count integer:=0;
  v_released_count integer:=0;
  v_failed_count integer:=0;
  v_unresolved_count integer:=0;

  v_secured_full_count integer:=0;
  v_secured_partial_count integer:=0;
  v_provisional_full_count integer:=0;
  v_provisional_partial_count integer:=0;

  v_hard_state text;
  v_fully_secured boolean:=false;
begin
  if p_coverage_facts is null or jsonb_typeof(p_coverage_facts)<>'array' then
    raise exception 'Coverage facts must be a JSON array.'
      using errcode='22023';
  end if;

  select * into v_requirement
  from atlas.work_requirements
  where id=p_work_requirement_id;

  if v_requirement.id is null then
    raise exception 'Work Requirement not found.'
      using errcode='P0002';
  end if;

  if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')='number'
     and nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is not null then
    v_required_quantity:=(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric;
    v_required_unit:=btrim(v_requirement.metadata->'commercialFulfillment'->>'unit');
    v_quantified:=true;
    if v_required_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_quantity_metadata',
        'message','Quantified Work Requirement quantity must be greater than zero.'
      ));
    end if;
  elsif (v_requirement.metadata->'commercialFulfillment' ? 'quantity')
     or (v_requirement.metadata->'commercialFulfillment' ? 'unit') then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement_quantity_metadata',
      'message','Quantified Work Requirement metadata must contain numeric quantity and nonblank unit.'
    ));
  end if;

  for v_fact in
    select value
    from jsonb_array_elements(p_coverage_facts)
  loop
    if jsonb_typeof(v_fact)<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','coverage_fact_not_object'
      ));
      continue;
    end if;

    v_key:=nullif(btrim(coalesce(v_fact->>'coverageKey','')),'');
    if v_key is null or v_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_key',
        'coverageKey',v_fact->>'coverageKey'
      ));
      continue;
    end if;

    if v_key=any(v_keys) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','duplicate_coverage_key',
        'coverageKey',v_key
      ));
      continue;
    end if;
    v_keys:=array_append(v_keys,v_key);

    if jsonb_typeof(v_fact->'sourceRef')<>'object'
       or nullif(btrim(coalesce(v_fact->'sourceRef'->>'sourceDomain','')),'') is null
       or nullif(btrim(coalesce(v_fact->'sourceRef'->>'sourceRef','')),'') is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_source_ref',
        'coverageKey',v_key
      ));
    end if;

    if v_fact ? 'metadata'
       and jsonb_typeof(v_fact->'metadata')<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_metadata',
        'coverageKey',v_key
      ));
    end if;

    if v_fact ? 'evidence'
       and jsonb_typeof(v_fact->'evidence')<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_evidence',
        'coverageKey',v_key
      ));
    end if;

    v_state:=lower(btrim(coalesce(v_fact->>'state','')));
    if v_state not in ('secured','provisional','released','failed','unresolved') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_state',
        'coverageKey',v_key,
        'state',v_fact->>'state'
      ));
      continue;
    end if;

    v_quantity:=null;
    v_unit:=null;
    v_extent:=null;

    if v_quantified then
      if v_state in ('secured','provisional') then
        if jsonb_typeof(v_fact->'quantity')<>'number' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','missing_coverage_quantity',
            'coverageKey',v_key,
            'state',v_state
          ));
        else
          v_quantity:=(v_fact->>'quantity')::numeric;
          if v_quantity<=0 then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_coverage_quantity',
              'coverageKey',v_key
            ));
          end if;
        end if;

        v_unit:=nullif(btrim(coalesce(v_fact->>'unit','')),'');
        if v_unit is null or v_unit<>v_required_unit then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','coverage_unit_mismatch',
            'coverageKey',v_key,
            'requiredUnit',v_required_unit,
            'coverageUnit',v_unit
          ));
        end if;
      elsif (v_fact ? 'quantity') or (v_fact ? 'unit') then
        if jsonb_typeof(v_fact->'quantity')='number' then
          v_quantity:=(v_fact->>'quantity')::numeric;
        end if;
        v_unit:=nullif(btrim(coalesce(v_fact->>'unit','')),'');
        if v_quantity is not null and v_quantity<0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_noncurrent_coverage_quantity',
            'coverageKey',v_key
          ));
        end if;
        if v_unit is not null and v_unit<>v_required_unit then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','coverage_unit_mismatch',
            'coverageKey',v_key,
            'requiredUnit',v_required_unit,
            'coverageUnit',v_unit
          ));
        end if;
      end if;

      if v_state='secured' and v_quantity is not null and v_quantity>0 and v_unit=v_required_unit then
        v_secured_quantity:=v_secured_quantity+v_quantity;
      elsif v_state='provisional' and v_quantity is not null and v_quantity>0 and v_unit=v_required_unit then
        v_provisional_quantity:=v_provisional_quantity+v_quantity;
      end if;
    else
      if v_state in ('secured','provisional') then
        v_extent:=lower(btrim(coalesce(v_fact->>'extent','')));
        if v_extent not in ('full','partial') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_coverage_extent',
            'coverageKey',v_key,
            'state',v_state
          ));
        end if;
      elsif v_fact ? 'extent' then
        v_extent:=lower(btrim(coalesce(v_fact->>'extent','')));
        if v_extent not in ('full','partial') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_coverage_extent',
            'coverageKey',v_key,
            'state',v_state
          ));
        end if;
      end if;

      if v_state='secured' and v_extent='full' then
        v_secured_full_count:=v_secured_full_count+1;
      elsif v_state='secured' and v_extent='partial' then
        v_secured_partial_count:=v_secured_partial_count+1;
      elsif v_state='provisional' and v_extent='full' then
        v_provisional_full_count:=v_provisional_full_count+1;
      elsif v_state='provisional' and v_extent='partial' then
        v_provisional_partial_count:=v_provisional_partial_count+1;
      end if;
    end if;

    case v_state
      when 'secured' then v_secured_count:=v_secured_count+1;
      when 'provisional' then v_provisional_count:=v_provisional_count+1;
      when 'released' then v_released_count:=v_released_count+1;
      when 'failed' then v_failed_count:=v_failed_count+1;
      when 'unresolved' then v_unresolved_count:=v_unresolved_count+1;
    end case;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'coverageKey',v_key,
      'sourceRef',v_fact->'sourceRef',
      'state',v_state,
      'quantity',v_quantity,
      'unit',v_unit,
      'extent',v_extent,
      'evidence',coalesce(v_fact->'evidence','[]'::jsonb),
      'metadata',coalesce(v_fact->'metadata','{}'::jsonb)
    ));
  end loop;

  if jsonb_array_length(v_violations)>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_coverage_position_v1',
      'state','invalid',
      'workRequirementId',v_requirement.id,
      'requirementState',v_requirement.state,
      'quantified',v_quantified,
      'violations',v_violations,
      'coverageFacts',v_normalized,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidCoverageFactsCreateNoTruth',true
      )
    );
  end if;

  if v_quantified then
    v_hard_state:=case
      when v_secured_quantity=0 then 'none'
      when v_secured_quantity<v_required_quantity then 'partial'
      when v_secured_quantity=v_required_quantity then 'exact'
      else 'overcovered'
    end;
    v_fully_secured:=v_secured_quantity>=v_required_quantity;
  else
    v_hard_state:=case
      when v_secured_full_count>0 then 'full'
      when v_secured_partial_count>0 then 'partial'
      else 'none'
    end;
    v_fully_secured:=v_secured_full_count>0;
  end if;

  return jsonb_build_object(
    'contractVersion','work_requirement_coverage_position_v1',
    'state','ready',
    'workRequirementId',v_requirement.id,
    'organizationId',v_requirement.organization_id,
    'requirementState',v_requirement.state,
    'responsibilityActive',(v_requirement.state='active'),
    'quantified',v_quantified,
    'requiredQuantity',v_required_quantity,
    'requiredUnit',v_required_unit,
    'securedQuantity',case when v_quantified then v_secured_quantity else null end,
    'provisionalQuantity',case when v_quantified then v_provisional_quantity else null end,
    'hardCoverageState',v_hard_state,
    'fullySecured',v_fully_secured,
    'securedFactCount',v_secured_count,
    'provisionalFactCount',v_provisional_count,
    'releasedFactCount',v_released_count,
    'failedFactCount',v_failed_count,
    'unresolvedFactCount',v_unresolved_count,
    'securedFullFactCount',case when v_quantified then null else v_secured_full_count end,
    'securedPartialFactCount',case when v_quantified then null else v_secured_partial_count end,
    'provisionalFullFactCount',case when v_quantified then null else v_provisional_full_count end,
    'provisionalPartialFactCount',case when v_quantified then null else v_provisional_partial_count end,
    'coverageFacts',v_normalized,
    'violations','[]'::jsonb,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'workRequirementRemainsAuthorityForResponsibility',true,
      'sourceObjectsRemainAuthorityForSecuringFacts',true,
      'coverageDoesNotMeanFulfillment',true,
      'coverageDoesNotCloseWorkRequirement',true,
      'provisionalDoesNotCountAsSecured',true,
      'unresolvedDoesNotBecomeZeroOrFailure',true,
      'doesNotCreateAllocation',true,
      'doesNotCreateReservation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_coverage_position_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_coverage_position_v1(uuid,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_coverage_position_v1(uuid,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_company_work_coverage_position_v1","purpose":"Read-only normalized coverage position over explicit source-owned allocation/reservation/assignment/acquisition facts for one Company Work Requirement.","classificationRuleVersion":3}'::jsonb,
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

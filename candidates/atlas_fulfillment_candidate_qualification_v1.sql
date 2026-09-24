begin;

create or replace function atlas.requirement_set_evaluate_v2(
  p_requirements jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_node jsonb;
  v_key text;
  v_state text;
  v_required boolean;
  v_keys text[]:='{}'::text[];

  v_total integer:=0;
  v_required_total integer:=0;
  v_optional_total integer:=0;

  v_required_satisfied integer:=0;
  v_required_unsatisfied integer:=0;
  v_required_unresolved integer:=0;

  v_optional_satisfied integer:=0;
  v_optional_unsatisfied integer:=0;
  v_optional_unresolved integer:=0;

  v_result_state text;
begin
  if p_requirements is null
     or jsonb_typeof(p_requirements)<>'array' then
    raise exception 'Requirement set must be a JSON array.'
      using errcode='22023';
  end if;

  if jsonb_array_length(p_requirements)=0 then
    raise exception 'Requirement set must contain at least one requirement node.'
      using errcode='22023';
  end if;

  for v_node in
    select value
    from jsonb_array_elements(p_requirements)
  loop
    if jsonb_typeof(v_node)<>'object' then
      raise exception 'Each requirement node must be a JSON object.'
        using errcode='22023';
    end if;

    v_key:=nullif(btrim(coalesce(v_node->>'requirementKey','')),'');
    if v_key is null then
      raise exception 'Each requirement node requires requirementKey.'
        using errcode='22023';
    end if;

    if v_key=any(v_keys) then
      raise exception 'Requirement key % appears more than once.',v_key
        using errcode='22023';
    end if;
    v_keys:=array_append(v_keys,v_key);

    v_state:=lower(btrim(coalesce(v_node->>'state','')));
    if v_state not in ('satisfied','unsatisfied','unresolved') then
      raise exception 'Requirement % requires state satisfied, unsatisfied, or unresolved.',v_key
        using errcode='22023';
    end if;

    if v_node ? 'required' then
      if jsonb_typeof(v_node->'required')<>'boolean' then
        raise exception 'Requirement % required must be boolean.',v_key
          using errcode='22023';
      end if;
      v_required:=(v_node->>'required')::boolean;
    else
      v_required:=true;
    end if;

    if v_node ? 'evidence'
       and jsonb_typeof(v_node->'evidence')<>'array' then
      raise exception 'Requirement % evidence must be an array.',v_key
        using errcode='22023';
    end if;

    if v_node ? 'details'
       and jsonb_typeof(v_node->'details')<>'object' then
      raise exception 'Requirement % details must be an object.',v_key
        using errcode='22023';
    end if;

    v_total:=v_total+1;

    if v_required then
      v_required_total:=v_required_total+1;
      case v_state
        when 'satisfied' then v_required_satisfied:=v_required_satisfied+1;
        when 'unsatisfied' then v_required_unsatisfied:=v_required_unsatisfied+1;
        when 'unresolved' then v_required_unresolved:=v_required_unresolved+1;
      end case;
    else
      v_optional_total:=v_optional_total+1;
      case v_state
        when 'satisfied' then v_optional_satisfied:=v_optional_satisfied+1;
        when 'unsatisfied' then v_optional_unsatisfied:=v_optional_unsatisfied+1;
        when 'unresolved' then v_optional_unresolved:=v_optional_unresolved+1;
      end case;
    end if;
  end loop;

  if v_required_total=0 then
    raise exception 'Requirement set must contain at least one required node.'
      using errcode='22023';
  end if;

  v_result_state:=case
    when v_required_unsatisfied>0 then 'unsatisfied'
    when v_required_unresolved>0 then 'unresolved'
    else 'satisfied'
  end;

  return jsonb_build_object(
    'contractVersion','requirement_set_evaluation_v2',
    'aggregation','all_required_three_state',
    'state',v_result_state,
    'satisfied',(v_result_state='satisfied'),
    'requirementCount',v_total,
    'requiredCount',v_required_total,
    'optionalCount',v_optional_total,
    'requiredSatisfiedCount',v_required_satisfied,
    'requiredUnsatisfiedCount',v_required_unsatisfied,
    'requiredUnresolvedCount',v_required_unresolved,
    'optionalSatisfiedCount',v_optional_satisfied,
    'optionalUnsatisfiedCount',v_optional_unsatisfied,
    'optionalUnresolvedCount',v_optional_unresolved,
    'requirements',p_requirements,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'evidenceRemainsDomainOwned',true,
      'evaluationDoesNotCreateBoundaryEvent',true,
      'evaluationDoesNotExecuteEffects',true,
      'unresolvedRemainsUnresolved',true,
      'allRequiredNodesMustBeExplicit',true
    )
  );
end;
$function$;


create or replace function atlas.fulfillment_candidate_qualification_v1(
  p_requirement_ref jsonb,
  p_candidate_ref jsonb,
  p_requirements jsonb,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_evaluation jsonb;
  v_eval_state text;
  v_qualification_state text;
begin
  if p_requirement_ref is null
     or jsonb_typeof(p_requirement_ref)<>'object' then
    raise exception 'Requirement ref must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_requirement_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(p_requirement_ref->>'sourceRef','')),'') is null then
    raise exception 'Requirement ref requires sourceDomain and sourceRef.'
      using errcode='22023';
  end if;

  if p_candidate_ref is null
     or jsonb_typeof(p_candidate_ref)<>'object' then
    raise exception 'Candidate ref must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_candidate_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(p_candidate_ref->>'sourceRef','')),'') is null then
    raise exception 'Candidate ref requires sourceDomain and sourceRef.'
      using errcode='22023';
  end if;

  if p_context is null
     or jsonb_typeof(p_context)<>'object' then
    raise exception 'Qualification context must be a JSON object.'
      using errcode='22023';
  end if;

  v_evaluation:=atlas.requirement_set_evaluate_v2(p_requirements);
  v_eval_state:=v_evaluation->>'state';

  v_qualification_state:=case v_eval_state
    when 'satisfied' then 'qualified'
    when 'unsatisfied' then 'incompatible'
    else 'unresolved'
  end;

  return jsonb_build_object(
    'contractVersion','fulfillment_candidate_qualification_v1',
    'requirementRef',p_requirement_ref,
    'candidateRef',p_candidate_ref,
    'qualificationState',v_qualification_state,
    'mayEnterPlanning',(v_qualification_state='qualified'),
    'evaluation',v_evaluation,
    'context',p_context,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'requirementTruthRemainsSourceOwned',true,
      'candidateTruthRemainsSourceOwned',true,
      'qualificationIsDirectional',true,
      'qualificationDoesNotAssertIdentity',true,
      'qualificationDoesNotRankCandidates',true,
      'qualificationDoesNotReserveAvailability',true,
      'qualificationDoesNotCreateCoverage',true,
      'qualificationDoesNotAuthorizePurchase',true,
      'qualificationDoesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.requirement_set_evaluate_v2(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.requirement_set_evaluate_v2(jsonb)
  to service_role;

revoke all on function atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.requirement_set_evaluate_v2(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_fulfillment_candidate_qualification_v1","purpose":"Read-only three-state aggregation of explicit requirement nodes; evidence remains domain-owned.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_fulfillment_candidate_qualification_v1","purpose":"Read-only directional candidate-to-requirement qualification wrapper for fulfillment planning.","classificationRuleVersion":3}'::jsonb,
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

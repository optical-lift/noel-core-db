begin;

-- Principal Consequence Clock Characterization v1.
--
-- Real consequence truth remains separate from Clock characterization.
-- Characterization remains separate from Clock candidate admission.

create or replace function atlas.person_life_consequence_clock_characterization_completeness_v1(
  p_value jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_blockers jsonb := '[]'::jsonb;
  v_timing jsonb;
  v_has_relevance_start boolean := false;
begin
  if p_value is null or jsonb_typeof(p_value)<>'object' then
    return jsonb_build_object(
      'complete',false,
      'blockers',jsonb_build_array('clock_characterization_required')
    );
  end if;

  if not (p_value ? 'expectedMinutes') then
    v_blockers := v_blockers || '"expected_minutes_required"'::jsonb;
  elsif jsonb_typeof(p_value->'expectedMinutes')<>'number'
     or (p_value->>'expectedMinutes')::numeric<=0
     or trunc((p_value->>'expectedMinutes')::numeric)<>(p_value->>'expectedMinutes')::numeric then
    v_blockers := v_blockers || '"expected_minutes_required"'::jsonb;
  end if;

  if not (p_value ? 'protectionLevel')
     or p_value->>'protectionLevel' not in ('critical','protected','standard','optional') then
    v_blockers := v_blockers || '"protection_level_required"'::jsonb;
  end if;

  if not (p_value ? 'floorClass') then
    v_blockers := v_blockers || '"floor_class_required"'::jsonb;
  elsif jsonb_typeof(p_value->'floorClass')<>'number'
     or (p_value->>'floorClass')::numeric<1
     or (p_value->>'floorClass')::numeric>7
     or trunc((p_value->>'floorClass')::numeric)<>(p_value->>'floorClass')::numeric then
    v_blockers := v_blockers || '"floor_class_required"'::jsonb;
  end if;

  if not (p_value ? 'interruptibility')
     or p_value->>'interruptibility' not in ('interruptible','low_interruptibility','should_not_interrupt') then
    v_blockers := v_blockers || '"interruptibility_required"'::jsonb;
  end if;

  if not (p_value ? 'delegable')
     or jsonb_typeof(p_value->'delegable')<>'boolean' then
    v_blockers := v_blockers || '"delegability_required"'::jsonb;
  end if;

  if not (p_value ? 'ownerRequired')
     or jsonb_typeof(p_value->'ownerRequired')<>'boolean' then
    v_blockers := v_blockers || '"owner_required_characterization_required"'::jsonb;
  end if;

  if nullif(btrim(p_value->>'consequenceOfDelay'),'') is null then
    v_blockers := v_blockers || '"consequence_of_delay_required"'::jsonb;
  end if;

  if nullif(btrim(p_value->>'reasonForFloor'),'') is null then
    v_blockers := v_blockers || '"reason_for_floor_required"'::jsonb;
  end if;

  v_timing := p_value->'timing';
  if jsonb_typeof(v_timing)='object' then
    v_has_relevance_start :=
      nullif(btrim(v_timing->>'windowStart'),'') is not null
      or nullif(btrim(v_timing->>'fixedStart'),'') is not null;
  end if;

  if not v_has_relevance_start then
    v_blockers := v_blockers || '"relevance_start_required"'::jsonb;
  end if;

  return jsonb_build_object(
    'complete',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'truthBoundary',jsonb_build_object(
      'missingRelevanceStartDoesNotMeanOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'completenessDoesNotMeanClockAdmission',true
    )
  );
end;
$$;

comment on function atlas.person_life_consequence_clock_characterization_completeness_v1(jsonb) is
  'Pure completeness test for person-life consequence Clock characterization. Missing timing is an admission blocker and never means an open current window.';

revoke all on function atlas.person_life_consequence_clock_characterization_completeness_v1(jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.record_person_life_consequence_clock_characterization_self_api_v1(
  p_consequence_instance_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_source_action_id text;
  v_value jsonb;
  v_timing jsonb;
  v_key text;
  v_supersedes_claim_id uuid;
  v_current atlas.claim_records%rowtype;
  v_result jsonb;
  v_completeness jsonb;
  v_time_key text;
  v_time_value text;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_fixed_start timestamptz;
  v_must_begin_by timestamptz;
  v_must_finish_by timestamptz;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_consequence_instance_id is null
     or p_input is null
     or jsonb_typeof(p_input)<>'object' then
    raise exception 'consequenceInstanceId and characterization input object are required.'
      using errcode='22023';
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open person Life Consequence not found for the signed-in user.'
      using errcode='42501';
  end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  v_value := p_input->'characterization';

  if v_source_action_id is null or jsonb_typeof(v_value)<>'object' then
    raise exception 'sourceActionId and characterization object are required.'
      using errcode='22023';
  end if;

  if v_value='{}'::jsonb then
    raise exception 'characterization must contain at least one explicit field.'
      using errcode='22023';
  end if;

  for v_key in select jsonb_object_keys(v_value)
  loop
    if v_key not in (
      'expectedMinutes',
      'protectionLevel',
      'floorClass',
      'interruptibility',
      'delegable',
      'ownerRequired',
      'timing',
      'consequenceOfDelay',
      'reasonForFloor'
    ) then
      raise exception 'Unsupported Clock characterization field: %',v_key
        using errcode='22023';
    end if;
  end loop;

  if v_value ? 'expectedMinutes' then
    if jsonb_typeof(v_value->'expectedMinutes')<>'number'
       or (v_value->>'expectedMinutes')::numeric<=0
       or trunc((v_value->>'expectedMinutes')::numeric)<>(v_value->>'expectedMinutes')::numeric then
      raise exception 'expectedMinutes must be a positive integer.'
        using errcode='22023';
    end if;
  end if;

  if v_value ? 'protectionLevel'
     and v_value->>'protectionLevel' not in ('critical','protected','standard','optional') then
    raise exception 'Unsupported protectionLevel.' using errcode='22023';
  end if;

  if v_value ? 'floorClass' then
    if jsonb_typeof(v_value->'floorClass')<>'number'
       or (v_value->>'floorClass')::numeric<1
       or (v_value->>'floorClass')::numeric>7
       or trunc((v_value->>'floorClass')::numeric)<>(v_value->>'floorClass')::numeric then
      raise exception 'floorClass must be an integer from 1 through 7.'
        using errcode='22023';
    end if;
  end if;

  if v_value ? 'interruptibility'
     and v_value->>'interruptibility' not in ('interruptible','low_interruptibility','should_not_interrupt') then
    raise exception 'Unsupported interruptibility.' using errcode='22023';
  end if;

  if v_value ? 'delegable' and jsonb_typeof(v_value->'delegable')<>'boolean' then
    raise exception 'delegable must be boolean.' using errcode='22023';
  end if;

  if v_value ? 'ownerRequired' and jsonb_typeof(v_value->'ownerRequired')<>'boolean' then
    raise exception 'ownerRequired must be boolean.' using errcode='22023';
  end if;

  if v_value ? 'consequenceOfDelay'
     and nullif(btrim(v_value->>'consequenceOfDelay'),'') is null then
    raise exception 'consequenceOfDelay must be non-empty when supplied.'
      using errcode='22023';
  end if;

  if v_value ? 'reasonForFloor'
     and nullif(btrim(v_value->>'reasonForFloor'),'') is null then
    raise exception 'reasonForFloor must be non-empty when supplied.'
      using errcode='22023';
  end if;

  if v_value ? 'timing' then
    v_timing := v_value->'timing';
    if jsonb_typeof(v_timing)<>'object' then
      raise exception 'timing must be an object.' using errcode='22023';
    end if;

    for v_time_key in select jsonb_object_keys(v_timing)
    loop
      if v_time_key not in (
        'windowStart',
        'windowEnd',
        'fixedStart',
        'mustBeginBy',
        'mustFinishBy'
      ) then
        raise exception 'Unsupported Clock timing field: %',v_time_key
          using errcode='22023';
      end if;

      v_time_value := nullif(btrim(v_timing->>v_time_key),'');
      if v_time_value is not null
         and not atlas.personal_reality_timestamp_is_explicit_v1(v_time_value) then
        raise exception 'Clock timing field % requires an explicit timestamp offset.',v_time_key
          using errcode='22023';
      end if;
    end loop;

    begin
      v_window_start := nullif(v_timing->>'windowStart','')::timestamptz;
      v_window_end := nullif(v_timing->>'windowEnd','')::timestamptz;
      v_fixed_start := nullif(v_timing->>'fixedStart','')::timestamptz;
      v_must_begin_by := nullif(v_timing->>'mustBeginBy','')::timestamptz;
      v_must_finish_by := nullif(v_timing->>'mustFinishBy','')::timestamptz;
    exception when others then
      raise exception 'Clock timing contains an invalid timestamp.'
        using errcode='22023';
    end;

    if v_window_start is not null
       and v_window_end is not null
       and v_window_end<=v_window_start then
      raise exception 'windowEnd must be after windowStart.'
        using errcode='22023';
    end if;

    if v_must_begin_by is not null
       and v_must_finish_by is not null
       and v_must_finish_by<v_must_begin_by then
      raise exception 'mustFinishBy must not precede mustBeginBy.'
        using errcode='22023';
    end if;

    if v_fixed_start is not null
       and v_window_end is not null
       and v_fixed_start>=v_window_end then
      raise exception 'fixedStart must precede windowEnd when both are supplied.'
        using errcode='22023';
    end if;
  end if;

  begin
    v_supersedes_claim_id := nullif(p_input->>'supersedesClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'supersedesClaimId must be a UUID.'
      using errcode='22023';
  end;

  select *
  into v_current
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=v_instance.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_current.id is not null
     and v_current.source_key<>(v_source_action_id||':clock_characterization')
     and v_supersedes_claim_id is null then
    raise exception 'This consequence already has current accepted Clock characterization; durable correction requires supersedesClaimId.'
      using errcode='23505';
  end if;

  if v_supersedes_claim_id is not null
     and (v_current.id is null or v_current.id<>v_supersedes_claim_id) then
    raise exception 'supersedesClaimId must identify the current accepted Clock characterization for this consequence.'
      using errcode='23505';
  end if;

  v_completeness := atlas.person_life_consequence_clock_characterization_completeness_v1(v_value);

  v_result := atlas.record_person_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_source_action_id||':clock_characterization',
    'subject',jsonb_build_object(
      'domain','principal.clock',
      'kind','person_life_consequence',
      'id',v_instance.id::text
    ),
    'evidence',jsonb_build_object(
      'kind','principal_clock_characterization_input',
      'value',v_value,
      'confidence',1,
      'provenance',jsonb_build_object(
        'consequenceInstanceId',v_instance.id,
        'definitionId',v_instance.definition_id,
        'sourceActionId',v_source_action_id
      ),
      'metadata',jsonb_build_object(
        'characterizationComplete',coalesce((v_completeness->>'complete')::boolean,false)
      )
    ),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'claimType','clock_characterization',
      'lifecycleState','accepted',
      'value',v_value,
      'confidence',1,
      'supersedesClaimId',v_supersedes_claim_id,
      'metadata',jsonb_build_object(
        'consequenceInstanceId',v_instance.id,
        'definitionId',v_instance.definition_id,
        'characterizationComplete',coalesce((v_completeness->>'complete')::boolean,false)
      )
    ))
  ));

  return v_result || jsonb_build_object(
    'contractVersion','person_life_consequence_clock_characterization_v1',
    'consequenceInstanceId',v_instance.id,
    'characterization',v_value,
    'completeness',v_completeness,
    'truthBoundary',jsonb_build_object(
      'consequenceTruthRemainsSeparate',true,
      'partialCharacterizationIsPreserved',true,
      'completeCharacterizationDoesNotMeanClockAdmission',true,
      'missingRelevanceStartDoesNotMeanOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'doesNotCreateClockCandidate',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb) is
  'Record or explicitly correct source-backed person Clock characterization for an owned open Person Life Consequence. Partial characterization is preserved; no Clock candidate or placement is created.';

revoke all on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)
  from public, anon;
grant execute on function atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)
  to authenticated, service_role;


create or replace function atlas.person_life_consequence_clock_admission_state_v1(
  p_owner_user_id uuid,
  p_consequence_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_principal_id uuid;
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_completeness jsonb;
  v_blockers jsonb := '[]'::jsonb;
  v_principal_carrier_ref text;
begin
  if p_owner_user_id is null or p_consequence_instance_id is null then
    raise exception 'owner user and consequence instance are required.'
      using errcode='22023';
  end if;

  select p.id
  into v_principal_id
  from atlas.principals p
  where p.user_id=p_owner_user_id
    and p.status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select *
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=p_owner_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open Person Life Consequence not found for this owner.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=p_owner_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=v_instance.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  v_completeness :=
    atlas.person_life_consequence_clock_characterization_completeness_v1(v_claim.value);

  if v_instance.requirement_state<>'established' then
    v_blockers := v_blockers || '"requirement_not_established"'::jsonb;
  end if;

  v_principal_carrier_ref := 'principal:'||v_principal_id::text;

  if v_instance.carrier_state<>'established'
     or v_instance.carrier_ref is distinct from v_principal_carrier_ref then
    v_blockers := v_blockers || '"principal_carrier_required"'::jsonb;
  end if;

  if v_instance.execution_readiness<>'ready' then
    v_blockers := v_blockers || '"execution_readiness_required"'::jsonb;
  end if;

  if v_claim.id is null then
    v_blockers := v_blockers || '"clock_characterization_required"'::jsonb;
  elsif not coalesce((v_completeness->>'complete')::boolean,false) then
    v_blockers := v_blockers || '"clock_characterization_incomplete"'::jsonb;
  end if;

  return jsonb_build_object(
    'contractVersion','person_life_consequence_clock_admission_state_v1',
    'principalId',v_principal_id,
    'consequenceInstanceId',v_instance.id,
    'requirementState',v_instance.requirement_state,
    'carrierRef',v_instance.carrier_ref,
    'carrierState',v_instance.carrier_state,
    'executionReadiness',v_instance.execution_readiness,
    'placementState',v_instance.placement_state,
    'characterizationClaimId',v_claim.id,
    'characterization',v_claim.value,
    'characterizationCompleteness',v_completeness,
    'admitted',jsonb_array_length(v_blockers)=0,
    'blockers',v_blockers,
    'truthBoundary',jsonb_build_object(
      'admissionIsNotRequirementTruth',true,
      'admissionRequiresPrincipalCarrier',true,
      'admissionRequiresExecutionReadiness',true,
      'admissionRequiresCompleteClockCharacterization',true,
      'missingRelevanceStartNeverMeansOpenNow',true,
      'deadlineAloneDoesNotEstablishCurrentRelevance',true,
      'admissionDoesNotPlaceClock',true
    )
  );
end;
$$;

comment on function atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid) is
  'Internal read of whether an open person Life Consequence has enough independent authority to become a Principal Clock candidate. No candidate or placement is created.';

revoke all on function atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.person_life_consequence_clock_admission_self_api_v1(
  p_consequence_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  return atlas.person_life_consequence_clock_admission_state_v1(
    v_user_id,
    p_consequence_instance_id
  );
end;
$;

comment on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid) is
  'Read the signed-in owner admission state for one open Person Life Consequence. Returns blockers instead of manufacturing missing Clock characterization, carrier, or readiness.';

revoke all on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid)
  from public, anon;
grant execute on function atlas.person_life_consequence_clock_admission_self_api_v1(uuid)
  to authenticated, service_role;


insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Record explicit source-backed Clock characterization for an owned open Person Life Consequence without creating a Clock candidate.',
      'authorizationBoundary','SECURITY DEFINER fixes person custody to auth.uid(); only approved characterization fields are admitted; corrections require explicit supersession; missing timing never defaults to current relevance.',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.person_life_consequence_clock_admission_self_api_v1(uuid)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Return Clock admission blockers for one owned open Person Life Consequence.',
      'authorizationBoundary','Read-only SECURITY DEFINER endpoint. Admission requires established Principal carrier, ready execution, and complete accepted Clock characterization; no candidate/placement is created.',
      'directSignedInEndpoint',true
    ),
    now(),
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
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;

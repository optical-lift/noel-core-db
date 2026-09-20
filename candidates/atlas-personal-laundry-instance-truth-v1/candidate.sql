begin;

-- Atlas Personal Laundry Instance Truth v1
--
-- Progressive household-specific Laundry facts over the universal
-- Household Claim/Evidence membrane.
--
-- Authority deliberately stops at:
--   Laundry instance root + explicit Household Evidence/Claims.
--
-- This candidate creates no Household Rhythm, task, Person Life Consequence,
-- execution carrier, capacity block, or Clock placement.

create or replace function atlas.record_laundry_instance_fact_internal_v1(
  p_instance_id uuid,
  p_source_action_id text,
  p_fact_key text,
  p_value jsonb,
  p_supersedes_claim_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_source_action_id text := nullif(btrim(p_source_action_id),'');
  v_fact_key text := nullif(btrim(p_fact_key),'');
  v_source_key text;
  v_current_claim atlas.claim_records%rowtype;
  v_metadata jsonb := coalesce(p_metadata,'{}'::jsonb);
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  if p_instance_id is null or v_source_action_id is null or v_fact_key is null then
    raise exception 'instanceId, sourceActionId, and factKey are required.' using errcode='22023';
  end if;

  if p_value is null then
    raise exception 'Laundry fact value is required; use explicit JSON null only inside a structured fact if needed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(v_metadata)<>'object' then
    raise exception 'Laundry fact metadata must be an object.' using errcode='22023';
  end if;

  if not exists (
    select 1
    from atlas.household_kernel_instances i
    where i.id=p_instance_id
      and i.household_id=v_household_id
      and i.kernel_key='household.laundry'
      and i.state='active'
  ) then
    raise exception 'Active Laundry instance not found in the current Principal household.'
      using errcode='42501';
  end if;

  v_source_key := v_source_action_id||':'||v_fact_key;

  select * into v_current_claim
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=p_instance_id::text
    and c.claim_type=v_fact_key
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_current_claim.id is not null
     and v_current_claim.source_key<>v_source_key
     and p_supersedes_claim_id is null then
    raise exception 'Laundry fact % already has accepted truth; durable correction requires explicit supersession.',
      v_fact_key using errcode='23505';
  end if;

  if p_supersedes_claim_id is not null
     and (v_current_claim.id is null or v_current_claim.id<>p_supersedes_claim_id) then
    raise exception 'Laundry supersession must identify the current accepted claim for fact %.',
      v_fact_key using errcode='23505';
  end if;

  return atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
    'sourceKey',v_source_key,
    'subject',jsonb_build_object(
      'domain','household.laundry',
      'kind','kernel_instance',
      'id',p_instance_id::text
    ),
    'evidence',jsonb_build_object(
      'kind','principal_calibration_answer',
      'value',p_value,
      'confidence',1,
      'provenance',jsonb_strip_nulls(
        v_metadata
        || jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'factKey',v_fact_key
        )
      )
    ),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'claimType',v_fact_key,
      'lifecycleState','accepted',
      'value',p_value,
      'confidence',1,
      'supersedesClaimId',p_supersedes_claim_id,
      'metadata',v_metadata || jsonb_build_object('factKey',v_fact_key)
    ))
  ));
end;
$$;

comment on function atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb) is
  'Internal Laundry fact adapter. Fixes custody to the signed-in Principal current Household and active Laundry instance; requires explicit supersession for an already-accepted singleton fact; routes persistence through Household Claim/Evidence only.';

revoke all on function atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_source_action_id text;
  v_location text;
  v_responsibility jsonb;
  v_responsibility_mode text;
  v_need_driver text;
  v_process_variants jsonb;
  v_turnaround jsonb;
  v_supersedes jsonb;
  v_instance atlas.household_kernel_instances%rowtype;
  v_variant jsonb;
  v_variant_key text;
  v_seen_keys text[] := '{}'::text[];
  v_forbidden_key text;
  v_result jsonb;
  v_claims jsonb := '[]'::jsonb;
  v_fact_count integer := 0;
  v_supersedes_claim_id uuid;
  v_common_metadata jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Laundry V2 calibration input must be an object.' using errcode='22023';
  end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then
    raise exception 'sourceActionId is required.' using errcode='22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select max(k.version)
  into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key='household.laundry'
    and k.active;

  if v_kernel_version is null then
    raise exception 'Active Laundry world kernel required.' using errcode='23514';
  end if;

  -- A source-controlled model is context for questioning, not Household truth.
  -- V2 validates modelKey when supplied but never copies model configuration
  -- into accepted Household facts.
  v_model_key := nullif(btrim(p_input->>'modelKey'),'');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key='household.laundry'
      and m.kernel_version=v_kernel_version
      and m.model_key=v_model_key
      and m.active;

    if v_model.model_key is null then
      raise exception 'Unknown Laundry model.' using errcode='22023';
    end if;
  end if;

  if p_input ? 'laundryLocation' then
    v_location := nullif(btrim(p_input->>'laundryLocation'),'');
    if v_location='building' then
      -- Current Reality Discovery exposes "building" for the same real-world
      -- answer V2 names shared_machines.
      v_location := 'shared_machines';
    end if;

    if v_location is null
       or v_location not in ('home','shared_machines','laundromat','service','other') then
      raise exception 'Unsupported laundryLocation.' using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'responsibility' then
    v_responsibility := p_input->'responsibility';

    if jsonb_typeof(v_responsibility)<>'object' then
      raise exception 'responsibility must be an object.' using errcode='22023';
    end if;

    v_responsibility_mode := nullif(btrim(v_responsibility->>'mode'),'');
    if v_responsibility_mode is null
       or v_responsibility_mode not in (
         'self',
         'shared',
         'other_household_member',
         'outside_household',
         'service',
         'unresolved',
         'other'
       ) then
      raise exception 'Unsupported responsibility.mode.' using errcode='22023';
    end if;

    if (v_responsibility - 'mode') <> '{}'::jsonb then
      raise exception 'Laundry V2 responsibility accepts mode only; identity, scheduling, notes, and carrier details require their own governed authority.'
        using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'needDriver' then
    v_need_driver := nullif(btrim(p_input->>'needDriver'),'');

    if v_need_driver is null
       or v_need_driver not in (
         'accumulation_threshold',
         'steady_flow',
         'main_reset',
         'deadline_driven',
         'mixed',
         'other'
       ) then
      raise exception 'Unsupported needDriver.' using errcode='22023';
    end if;

    v_fact_count := v_fact_count + 1;
  end if;

  if p_input ? 'processVariants' then
    v_process_variants := p_input->'processVariants';

    if jsonb_typeof(v_process_variants)<>'array' then
      raise exception 'processVariants must be an array.' using errcode='22023';
    end if;

    v_seen_keys := '{}'::text[];

    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      if jsonb_typeof(v_variant)<>'object' then
        raise exception 'Each process variant must be an object.' using errcode='22023';
      end if;

      v_variant_key := nullif(btrim(v_variant->>'key'),'');
      if v_variant_key is null then
        raise exception 'Each process variant requires key.' using errcode='22023';
      end if;

      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*$' then
        raise exception 'process variant key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_seen_keys) then
        raise exception 'processVariants keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_seen_keys := array_append(v_seen_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule',
        'recurrence',
        'nextDueAt',
        'dueAt',
        'dueDate',
        'floorClass',
        'protectionLevel',
        'principalRequired',
        'blocksCapacity',
        'clockPlacement',
        'todayPlacement',
        'expectedMinutes',
        'personId',
        'memberId',
        'userId'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Process variant may not carry scheduling, Clock, or identity authority field: %',
            v_forbidden_key using errcode='22023';
        end if;
      end loop;

      if v_variant ? 'supersedesClaimId' then
        begin
          perform nullif(v_variant->>'supersedesClaimId','')::uuid;
        exception when invalid_text_representation then
          raise exception 'process variant supersedesClaimId must be a UUID.'
            using errcode='22023';
        end;
      end if;
    end loop;

    v_fact_count := v_fact_count + jsonb_array_length(v_process_variants);
  end if;

  if p_input ? 'turnaroundRelationships' then
    v_turnaround := p_input->'turnaroundRelationships';

    if jsonb_typeof(v_turnaround)<>'array' then
      raise exception 'turnaroundRelationships must be an array.' using errcode='22023';
    end if;

    v_seen_keys := '{}'::text[];

    for v_variant in
      select value from jsonb_array_elements(v_turnaround)
    loop
      if jsonb_typeof(v_variant)<>'object' then
        raise exception 'Each turnaround relationship must be an object.'
          using errcode='22023';
      end if;

      v_variant_key := nullif(btrim(v_variant->>'key'),'');
      if v_variant_key is null then
        raise exception 'Each turnaround relationship requires key.'
          using errcode='22023';
      end if;

      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*$' then
        raise exception 'turnaround relationship key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_seen_keys) then
        raise exception 'turnaroundRelationships keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_seen_keys := array_append(v_seen_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule',
        'recurrence',
        'nextDueAt',
        'dueAt',
        'dueDate',
        'floorClass',
        'protectionLevel',
        'principalRequired',
        'blocksCapacity',
        'clockPlacement',
        'todayPlacement',
        'expectedMinutes',
        'personId',
        'memberId',
        'userId'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Turnaround relationship may not carry scheduling, Clock, or identity authority field: %',
            v_forbidden_key using errcode='22023';
        end if;
      end loop;
    end loop;

    -- Explicit [] is meaningful: "no currently known special turnaround
    -- relationship." Absence of the key remains unknown.
    v_fact_count := v_fact_count + 1;
  end if;

  v_supersedes := coalesce(p_input->'supersedes','{}'::jsonb);
  if jsonb_typeof(v_supersedes)<>'object' then
    raise exception 'supersedes must be an object.' using errcode='22023';
  end if;

  if v_fact_count=0 then
    raise exception 'At least one explicit Laundry fact is required; modelKey alone is not household truth.'
      using errcode='22023';
  end if;

  -- Establish the durable instance root. Existing legacy configuration is
  -- preserved for compatibility, but V2 marks Claim/Evidence as fact authority.
  select * into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id
    and i.kernel_key='household.laundry'
  limit 1;

  if v_instance.id is null then
    insert into atlas.household_kernel_instances(
      household_id,
      kernel_key,
      kernel_version,
      state,
      configuration,
      calibrated_at,
      metadata
    ) values (
      v_household_id,
      'household.laundry',
      v_kernel_version,
      'active',
      jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
      now(),
      jsonb_build_object(
        'source','principal_progressive_calibration',
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      )
    )
    returning * into v_instance;
  else
    if v_instance.kernel_version is distinct from v_kernel_version
       or v_instance.state is distinct from 'active'
       or v_instance.configuration->>'factAuthority' is distinct from 'household_claim_evidence_v1'
       or v_instance.configuration->>'calibrationContract' is distinct from 'household_laundry_instance_truth_v1'
       or v_instance.metadata->>'factAuthority' is distinct from 'household_claim_evidence_v1'
       or v_instance.metadata->>'calibrationContract' is distinct from 'household_laundry_instance_truth_v1' then

      update atlas.household_kernel_instances
      set kernel_version=v_kernel_version,
          state='active',
          configuration=configuration || jsonb_build_object(
            'factAuthority','household_claim_evidence_v1',
            'calibrationContract','household_laundry_instance_truth_v1'
          ),
          metadata=metadata || jsonb_build_object(
            'factAuthority','household_claim_evidence_v1',
            'calibrationContract','household_laundry_instance_truth_v1'
          ),
          updated_at=now()
      where id=v_instance.id
      returning * into v_instance;
    end if;
  end if;

  v_common_metadata := jsonb_strip_nulls(jsonb_build_object(
    'kernelVersion',v_kernel_version,
    'selectedModelKey',v_model_key,
    'calibrationContract','household_laundry_instance_truth_v1',
    'modelIsSuggestionContextOnly',true
  ));

  if v_location is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'location',
      jsonb_build_object('kind',v_location),
      v_supersedes_claim_id,
      v_common_metadata
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'ordinary_responsibility',
      jsonb_build_object('mode',v_responsibility_mode),
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('carrierSelectionAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'need_generation',
      jsonb_build_object('kind',v_need_driver),
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('recurrenceAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.'
          using errcode='22023';
      end;

      v_result := atlas.record_laundry_instance_fact_internal_v1(
        v_instance.id,
        v_source_action_id,
        'process_variant:'||v_variant_key,
        v_variant - 'supersedesClaimId',
        v_supersedes_claim_id,
        v_common_metadata || jsonb_build_object('schedulingAuthority',false)
      );

      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.'
        using errcode='22023';
    end;

    v_result := atlas.record_laundry_instance_fact_internal_v1(
      v_instance.id,
      v_source_action_id,
      'turnaround_relationships',
      v_turnaround,
      v_supersedes_claim_id,
      v_common_metadata || jsonb_build_object('deadlineConsequenceAuthority',false)
    );

    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','household_laundry_instance_truth_v1',
    'householdId',v_household_id,
    'sourceActionId',v_source_action_id,
    'selectedModelKey',v_model_key,
    'instance',jsonb_build_object(
      'id',v_instance.id,
      'state',v_instance.state,
      'kernelKey',v_instance.kernel_key,
      'kernelVersion',v_instance.kernel_version,
      'configuration',v_instance.configuration,
      'metadata',v_instance.metadata
    ),
    'factClaims',v_claims,
    'rhythm',null,
    'rhythmMutation','none',
    'truthBoundary',jsonb_build_object(
      'instanceRootIsHouseholdKernelInstance',true,
      'factAuthority','household_claim_evidence_v1',
      'modelIsSuggestionContextNotHouseholdTruth',true,
      'unmentionedFactsRemainUnknown',true,
      'responsibilityDoesNotSelectCarrier',true,
      'needGenerationDoesNotCreateRecurrence',true,
      'turnaroundRelationshipDoesNotCreateDeadline',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateTask',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateCapacity',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb) is
  'Progressively establish explicit household-specific Laundry facts against the durable Laundry kernel instance through Household Claim/Evidence authority. Unmentioned facts remain unknown; model defaults are not promoted; no Rhythm, task, consequence, carrier, capacity, or Clock authority is created.';


create or replace function atlas.personal_laundry_kernel_self_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
  v_accepted_facts jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  v_base := atlas.personal_laundry_kernel_self_api_v1();

  begin
    v_instance_id := nullif(v_base#>>'{instance,id}','')::uuid;
  exception when invalid_text_representation then
    raise exception 'Laundry V1 projection returned invalid instance identity.'
      using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
    v_accepted_facts := '[]'::jsonb;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'claimId',c.id,
      'claimType',c.claim_type,
      'lifecycleState',c.lifecycle_state,
      'authorityKind',c.authority_kind,
      'value',c.value,
      'primaryEvidenceId',c.primary_evidence_id,
      'validFrom',c.valid_from,
      'validUntil',c.valid_until,
      'recordedAt',c.recorded_at,
      'metadata',c.metadata
    ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_facts
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance_id::text
      and c.lifecycle_state not in ('superseded','expired','rejected');

    select coalesce(jsonb_agg(jsonb_build_object(
      'claimId',c.id,
      'claimType',c.claim_type,
      'value',c.value,
      'primaryEvidenceId',c.primary_evidence_id,
      'recordedAt',c.recorded_at,
      'metadata',c.metadata
    ) order by c.recorded_at,c.id),'[]'::jsonb)
    into v_accepted_facts
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance_id::text
      and c.lifecycle_state='accepted';
  end if;

  return v_base || jsonb_build_object(
    'contractVersion','personal_laundry_kernel_self_api_v2',
    'instanceFacts',v_facts,
    'acceptedInstanceFacts',v_accepted_facts,
    'truthBoundary',jsonb_build_object(
      'worldKernelAndHouseholdInstanceRemainDistinct',true,
      'instanceFactsComeFromHouseholdClaimEvidence',true,
      'acceptedFactsRemainLifecycleExplicit',true,
      'legacyConfigurationIsNotV2FactAuthority',true,
      'rhythmIsSeparateDownstreamAuthority',true,
      'readCreatesNoTruth',true,
      'readCreatesNoClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read current Household Laundry world-kernel/instance projection plus current source-backed Household Claim/Evidence facts. Any Household Rhythm remains a separate downstream projection, not calibration fact authority.';


revoke all on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)
  from public, anon;
revoke all on function atlas.personal_laundry_kernel_self_api_v2()
  from public, anon;

grant execute on function atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)
  to authenticated, service_role;
grant execute on function atlas.personal_laundry_kernel_self_api_v2()
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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Progressively establish explicit household-specific Laundry facts on the Laundry kernel instance through Household Claim/Evidence.',
      'authorizationBoundary','SECURITY DEFINER derives current Household from auth.uid(); model defaults remain suggestions; unmentioned facts remain unknown; no Rhythm, task, carrier, consequence, capacity, or Clock authority.',
      'dependsOn','atlas.record_current_household_claim_evidence_api_v1(jsonb)',
      'directSignedInEndpoint',true
    ),
    now(),
    false
  ),
  (
    'atlas.personal_laundry_kernel_self_api_v2()',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose','Read Laundry world-kernel/instance projection with current Household Claim/Evidence facts while preserving Rhythm as separate authority.',
      'authorizationBoundary','SECURITY DEFINER fixes Household to auth.uid() Principal custody; read creates no truth, task, or Clock placement.',
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

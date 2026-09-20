begin;

-- Atlas Personal Laundry Instance Truth v1
--
-- Progressive household-specific Laundry facts over the universal
-- Household Claim/Evidence membrane. This writer creates/updates only the
-- Laundry instance shell plus explicit accepted fact claims. It creates no
-- Household Rhythm, task, Person Life Consequence, capacity block, or Clock placement.

create or replace function atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
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
  v_variant_keys text[] := '{}'::text[];
  v_forbidden_key text;
  v_result jsonb;
  v_claims jsonb := '[]'::jsonb;
  v_fact_count integer := 0;
  v_supersedes_claim_id uuid;
  v_existing_claim atlas.claim_records%rowtype;
  v_claim_type text;
  v_source_key text;
  v_fact_value jsonb;
  v_fact_name text;
begin
  v_user_id := auth.uid();
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
         'self','shared','other_household_member','outside_household','service','unresolved','other'
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
         'accumulation_threshold','steady_flow','main_reset','deadline_driven','mixed','other'
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
      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*
        raise exception 'processVariants keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_variant_keys := array_append(v_variant_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule','recurrence','nextDueAt','dueAt','dueDate',
        'floorClass','protectionLevel','principalRequired','blocksCapacity',
        'clockPlacement','todayPlacement','expectedMinutes'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Process variant may not carry scheduling/Clock authority field: %',v_forbidden_key
            using errcode='22023';
        end if;
      end loop;

      if v_variant ? 'supersedesClaimId' then
        begin
          perform nullif(v_variant->>'supersedesClaimId','')::uuid;
        exception when invalid_text_representation then
          raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
        end;
      end if;
    end loop;

    if jsonb_array_length(v_process_variants)>0 then
      v_fact_count := v_fact_count + jsonb_array_length(v_process_variants);
    end if;
  end if;

  if p_input ? 'turnaroundRelationships' then
    v_turnaround := p_input->'turnaroundRelationships';
    if jsonb_typeof(v_turnaround)<>'array' then
      raise exception 'turnaroundRelationships must be an array.' using errcode='22023';
    end if;

    v_variant_keys := '{}'::text[];
    for v_variant in
      select value from jsonb_array_elements(v_turnaround)
    loop
      if jsonb_typeof(v_variant)<>'object' then
        raise exception 'Each turnaround relationship must be an object.' using errcode='22023';
      end if;

      v_variant_key := nullif(btrim(v_variant->>'key'),'');
      if v_variant_key is null then
        raise exception 'Each turnaround relationship requires key.' using errcode='22023';
      end if;
      if v_variant_key !~ '^[a-z0-9][a-z0-9._-]*

  v_supersedes := coalesce(p_input->'supersedes','{}'::jsonb);
  if jsonb_typeof(v_supersedes)<>'object' then
    raise exception 'supersedes must be an object.' using errcode='22023';
  end if;

  if v_fact_count=0 then
    raise exception 'At least one explicit Laundry fact is required; modelKey alone is not household truth.'
      using errcode='22023';
  end if;

  -- Establish only the durable instance root. Existing configuration is
  -- preserved; V2 fact authority lives in Household Claim/Evidence.
  insert into atlas.household_kernel_instances(
    household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata
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
    jsonb_strip_nulls(jsonb_build_object(
      'source','principal_progressive_calibration',
      'sourceActionId',v_source_action_id,
      'calibratedBy',v_user_id,
      'factAuthority','household_claim_evidence_v1',
      'calibrationContract','household_laundry_instance_truth_v1',
      'selectedModelKey',v_model_key
    ))
  )
  on conflict(household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,
    state='active',
    configuration=atlas.household_kernel_instances.configuration
      || jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
    calibrated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.calibrated_at
      else now()
    end,
    metadata=atlas.household_kernel_instances.metadata
      || jsonb_strip_nulls(jsonb_build_object(
        'source','principal_progressive_calibration',
        'sourceActionId',v_source_action_id,
        'calibratedBy',v_user_id,
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1',
        'selectedModelKey',v_model_key
      )),
    updated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.updated_at
      else now()
    end
  returning * into v_instance;

  -- Helper pattern repeated for singleton facts:
  -- if there is already a current accepted claim of this exact type, a new
  -- source action must explicitly supersede it. Same sourceAction retries are
  -- handled idempotently by the Household Claim/Evidence membrane.

  if v_location is not null then
    v_fact_name := 'location';
    v_claim_type := 'location';
    v_source_key := v_source_action_id||':location';
    v_fact_value := jsonb_build_object('kind',v_location);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry location already has current truth; supply supersedes.location for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.location must identify the current Laundry location claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object('factName',v_fact_name)
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    v_fact_name := 'ordinary_responsibility';
    v_claim_type := 'ordinary_responsibility';
    v_source_key := v_source_action_id||':ordinary_responsibility';
    v_fact_value := jsonb_build_object('mode',v_responsibility_mode);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry ordinary responsibility already has current truth; supply supersedes.ordinary_responsibility for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.ordinary_responsibility must identify the current Laundry responsibility claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'carrierSelectionAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    v_fact_name := 'need_generation';
    v_claim_type := 'need_generation';
    v_source_key := v_source_action_id||':need_generation';
    v_fact_value := jsonb_build_object('kind',v_need_driver);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry need generation already has current truth; supply supersedes.need_generation for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.need_generation must identify the current Laundry need-generation claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'recurrenceAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');
      v_fact_name := 'process_variant:'||v_variant_key;
      v_claim_type := v_fact_name;
      v_source_key := v_source_action_id||':process_variant:'||v_variant_key;
      v_fact_value := v_variant - 'supersedesClaimId';

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
      end;

      select * into v_existing_claim
      from atlas.claim_records c
      where c.scope_kind='household'
        and c.scope_id=v_household_id
        and c.subject_domain='household.laundry'
        and c.subject_kind='kernel_instance'
        and c.subject_id=v_instance.id::text
        and c.claim_type=v_claim_type
        and c.lifecycle_state not in ('superseded','expired','rejected')
      order by c.recorded_at desc,c.id desc
      limit 1;

      if v_existing_claim.id is not null
         and v_existing_claim.source_key<>v_source_key
         and v_supersedes_claim_id is null then
        raise exception 'Laundry process variant % already has current truth; supply its supersedesClaimId for durable correction.',v_variant_key
          using errcode='23505';
      end if;
      if v_supersedes_claim_id is not null
         and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
        raise exception 'process variant supersedesClaimId must identify the current claim for variant %.',v_variant_key
          using errcode='23505';
      end if;

      v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
        'sourceKey',v_source_key,
        'subject',jsonb_build_object(
          'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
        ),
        'evidence',jsonb_build_object(
          'kind','principal_calibration_answer',
          'value',v_fact_value,
          'confidence',1,
          'provenance',jsonb_strip_nulls(jsonb_build_object(
            'sourceActionId',v_source_action_id,
            'kernelKey','household.laundry',
            'kernelVersion',v_kernel_version,
            'selectedModelKey',v_model_key,
            'calibrationContract','household_laundry_instance_truth_v1'
          ))
        ),
        'claim',jsonb_strip_nulls(jsonb_build_object(
          'claimType',v_claim_type,
          'lifecycleState','accepted',
          'value',v_fact_value,
          'confidence',1,
          'supersedesClaimId',v_supersedes_claim_id,
          'metadata',jsonb_build_object(
            'factName',v_fact_name,
            'schedulingAuthority',false
          )
        ))
      ));
      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    v_fact_name := 'turnaround_relationships';
    v_claim_type := 'turnaround_relationships';
    v_source_key := v_source_action_id||':turnaround_relationships';
    v_fact_value := v_turnaround;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry turnaround relationships already have current truth; supply supersedes.turnaround_relationships for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.turnaround_relationships must identify the current Laundry turnaround relationship claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'deadlineConsequenceAuthority',false
        )
      ))
    ));
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
  v_user_id uuid;
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
begin
  v_user_id := auth.uid();
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
    raise exception 'Laundry V1 projection returned invalid instance identity.' using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
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
  end if;

  return v_base
    || jsonb_build_object(
      'contractVersion','personal_laundry_kernel_self_api_v2',
      'instanceFacts',v_facts,
      'truthBoundary',jsonb_build_object(
        'worldKernelAndHouseholdInstanceRemainDistinct',true,
        'instanceFactsComeFromHouseholdClaimEvidence',true,
        'legacyConfigurationIsNotV2FactAuthority',true,
        'rhythmIsSeparateDownstreamAuthority',true,
        'readCreatesNoTruth',true,
        'readCreatesNoClockPlacement',true
      )
    );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read the current Household Laundry world-kernel projection plus current source-backed Household Claim/Evidence facts for its durable instance. Any Rhythm remains separately projected and is not treated as calibration fact authority.';

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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)',
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry V2 instance-truth registration.';
  end if;
end
$$;

commit;
 then
        raise exception 'process variant key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_variant_keys) then
        raise exception 'processVariants keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_variant_keys := array_append(v_variant_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule','recurrence','nextDueAt','dueAt','dueDate',
        'floorClass','protectionLevel','principalRequired','blocksCapacity',
        'clockPlacement','todayPlacement','expectedMinutes'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Process variant may not carry scheduling/Clock authority field: %',v_forbidden_key
            using errcode='22023';
        end if;
      end loop;

      if v_variant ? 'supersedesClaimId' then
        begin
          perform nullif(v_variant->>'supersedesClaimId','')::uuid;
        exception when invalid_text_representation then
          raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
        end;
      end if;
    end loop;

    if jsonb_array_length(v_process_variants)>0 then
      v_fact_count := v_fact_count + jsonb_array_length(v_process_variants);
    end if;
  end if;

  if p_input ? 'turnaroundRelationships' then
    v_turnaround := p_input->'turnaroundRelationships';
    if jsonb_typeof(v_turnaround)<>'array' then
      raise exception 'turnaroundRelationships must be an array.' using errcode='22023';
    end if;
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

  -- Establish only the durable instance root. Existing configuration is
  -- preserved; V2 fact authority lives in Household Claim/Evidence.
  insert into atlas.household_kernel_instances(
    household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata
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
    jsonb_strip_nulls(jsonb_build_object(
      'source','principal_progressive_calibration',
      'sourceActionId',v_source_action_id,
      'calibratedBy',v_user_id,
      'factAuthority','household_claim_evidence_v1',
      'calibrationContract','household_laundry_instance_truth_v1',
      'selectedModelKey',v_model_key
    ))
  )
  on conflict(household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,
    state='active',
    configuration=atlas.household_kernel_instances.configuration
      || jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
    calibrated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.calibrated_at
      else now()
    end,
    metadata=atlas.household_kernel_instances.metadata
      || jsonb_strip_nulls(jsonb_build_object(
        'source','principal_progressive_calibration',
        'sourceActionId',v_source_action_id,
        'calibratedBy',v_user_id,
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1',
        'selectedModelKey',v_model_key
      )),
    updated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.updated_at
      else now()
    end
  returning * into v_instance;

  -- Helper pattern repeated for singleton facts:
  -- if there is already a current accepted claim of this exact type, a new
  -- source action must explicitly supersede it. Same sourceAction retries are
  -- handled idempotently by the Household Claim/Evidence membrane.

  if v_location is not null then
    v_fact_name := 'location';
    v_claim_type := 'location';
    v_source_key := v_source_action_id||':location';
    v_fact_value := jsonb_build_object('kind',v_location);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry location already has current truth; supply supersedes.location for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.location must identify the current Laundry location claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object('factName',v_fact_name)
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    v_fact_name := 'ordinary_responsibility';
    v_claim_type := 'ordinary_responsibility';
    v_source_key := v_source_action_id||':ordinary_responsibility';
    v_fact_value := v_responsibility;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry ordinary responsibility already has current truth; supply supersedes.ordinary_responsibility for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.ordinary_responsibility must identify the current Laundry responsibility claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'carrierSelectionAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    v_fact_name := 'need_generation';
    v_claim_type := 'need_generation';
    v_source_key := v_source_action_id||':need_generation';
    v_fact_value := jsonb_build_object('kind',v_need_driver);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry need generation already has current truth; supply supersedes.need_generation for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.need_generation must identify the current Laundry need-generation claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'recurrenceAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');
      v_fact_name := 'process_variant:'||v_variant_key;
      v_claim_type := v_fact_name;
      v_source_key := v_source_action_id||':process_variant:'||v_variant_key;
      v_fact_value := v_variant - 'supersedesClaimId';

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
      end;

      select * into v_existing_claim
      from atlas.claim_records c
      where c.scope_kind='household'
        and c.scope_id=v_household_id
        and c.subject_domain='household.laundry'
        and c.subject_kind='kernel_instance'
        and c.subject_id=v_instance.id::text
        and c.claim_type=v_claim_type
        and c.lifecycle_state not in ('superseded','expired','rejected')
      order by c.recorded_at desc,c.id desc
      limit 1;

      if v_existing_claim.id is not null
         and v_existing_claim.source_key<>v_source_key
         and v_supersedes_claim_id is null then
        raise exception 'Laundry process variant % already has current truth; supply its supersedesClaimId for durable correction.',v_variant_key
          using errcode='23505';
      end if;
      if v_supersedes_claim_id is not null
         and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
        raise exception 'process variant supersedesClaimId must identify the current claim for variant %.',v_variant_key
          using errcode='23505';
      end if;

      v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
        'sourceKey',v_source_key,
        'subject',jsonb_build_object(
          'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
        ),
        'evidence',jsonb_build_object(
          'kind','principal_calibration_answer',
          'value',v_fact_value,
          'confidence',1,
          'provenance',jsonb_strip_nulls(jsonb_build_object(
            'sourceActionId',v_source_action_id,
            'kernelKey','household.laundry',
            'kernelVersion',v_kernel_version,
            'selectedModelKey',v_model_key,
            'calibrationContract','household_laundry_instance_truth_v1'
          ))
        ),
        'claim',jsonb_strip_nulls(jsonb_build_object(
          'claimType',v_claim_type,
          'lifecycleState','accepted',
          'value',v_fact_value,
          'confidence',1,
          'supersedesClaimId',v_supersedes_claim_id,
          'metadata',jsonb_build_object(
            'factName',v_fact_name,
            'schedulingAuthority',false
          )
        ))
      ));
      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    v_fact_name := 'turnaround_relationships';
    v_claim_type := 'turnaround_relationships';
    v_source_key := v_source_action_id||':turnaround_relationships';
    v_fact_value := v_turnaround;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry turnaround relationships already have current truth; supply supersedes.turnaround_relationships for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.turnaround_relationships must identify the current Laundry turnaround relationship claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'deadlineConsequenceAuthority',false
        )
      ))
    ));
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
  v_user_id uuid;
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
begin
  v_user_id := auth.uid();
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
    raise exception 'Laundry V1 projection returned invalid instance identity.' using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
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
  end if;

  return v_base
    || jsonb_build_object(
      'contractVersion','personal_laundry_kernel_self_api_v2',
      'instanceFacts',v_facts,
      'truthBoundary',jsonb_build_object(
        'worldKernelAndHouseholdInstanceRemainDistinct',true,
        'instanceFactsComeFromHouseholdClaimEvidence',true,
        'legacyConfigurationIsNotV2FactAuthority',true,
        'rhythmIsSeparateDownstreamAuthority',true,
        'readCreatesNoTruth',true,
        'readCreatesNoClockPlacement',true
      )
    );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read the current Household Laundry world-kernel projection plus current source-backed Household Claim/Evidence facts for its durable instance. Any Rhythm remains separately projected and is not treated as calibration fact authority.';

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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)',
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry V2 instance-truth registration.';
  end if;
end
$$;

commit;
 then
        raise exception 'turnaround relationship key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;
      if v_variant_key = any(v_variant_keys) then
        raise exception 'turnaroundRelationships keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_variant_keys := array_append(v_variant_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule','recurrence','nextDueAt','dueAt','dueDate',
        'floorClass','protectionLevel','principalRequired','blocksCapacity',
        'clockPlacement','todayPlacement','expectedMinutes'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Turnaround relationship may not carry scheduling/Clock authority field: %',v_forbidden_key
            using errcode='22023';
        end if;
      end loop;
    end loop;

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

  -- Establish only the durable instance root. Existing configuration is
  -- preserved; V2 fact authority lives in Household Claim/Evidence.
  insert into atlas.household_kernel_instances(
    household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata
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
    jsonb_strip_nulls(jsonb_build_object(
      'source','principal_progressive_calibration',
      'sourceActionId',v_source_action_id,
      'calibratedBy',v_user_id,
      'factAuthority','household_claim_evidence_v1',
      'calibrationContract','household_laundry_instance_truth_v1',
      'selectedModelKey',v_model_key
    ))
  )
  on conflict(household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,
    state='active',
    configuration=atlas.household_kernel_instances.configuration
      || jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
    calibrated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.calibrated_at
      else now()
    end,
    metadata=atlas.household_kernel_instances.metadata
      || jsonb_strip_nulls(jsonb_build_object(
        'source','principal_progressive_calibration',
        'sourceActionId',v_source_action_id,
        'calibratedBy',v_user_id,
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1',
        'selectedModelKey',v_model_key
      )),
    updated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.updated_at
      else now()
    end
  returning * into v_instance;

  -- Helper pattern repeated for singleton facts:
  -- if there is already a current accepted claim of this exact type, a new
  -- source action must explicitly supersede it. Same sourceAction retries are
  -- handled idempotently by the Household Claim/Evidence membrane.

  if v_location is not null then
    v_fact_name := 'location';
    v_claim_type := 'location';
    v_source_key := v_source_action_id||':location';
    v_fact_value := jsonb_build_object('kind',v_location);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry location already has current truth; supply supersedes.location for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.location must identify the current Laundry location claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object('factName',v_fact_name)
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    v_fact_name := 'ordinary_responsibility';
    v_claim_type := 'ordinary_responsibility';
    v_source_key := v_source_action_id||':ordinary_responsibility';
    v_fact_value := v_responsibility;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry ordinary responsibility already has current truth; supply supersedes.ordinary_responsibility for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.ordinary_responsibility must identify the current Laundry responsibility claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'carrierSelectionAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    v_fact_name := 'need_generation';
    v_claim_type := 'need_generation';
    v_source_key := v_source_action_id||':need_generation';
    v_fact_value := jsonb_build_object('kind',v_need_driver);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry need generation already has current truth; supply supersedes.need_generation for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.need_generation must identify the current Laundry need-generation claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'recurrenceAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');
      v_fact_name := 'process_variant:'||v_variant_key;
      v_claim_type := v_fact_name;
      v_source_key := v_source_action_id||':process_variant:'||v_variant_key;
      v_fact_value := v_variant - 'supersedesClaimId';

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
      end;

      select * into v_existing_claim
      from atlas.claim_records c
      where c.scope_kind='household'
        and c.scope_id=v_household_id
        and c.subject_domain='household.laundry'
        and c.subject_kind='kernel_instance'
        and c.subject_id=v_instance.id::text
        and c.claim_type=v_claim_type
        and c.lifecycle_state not in ('superseded','expired','rejected')
      order by c.recorded_at desc,c.id desc
      limit 1;

      if v_existing_claim.id is not null
         and v_existing_claim.source_key<>v_source_key
         and v_supersedes_claim_id is null then
        raise exception 'Laundry process variant % already has current truth; supply its supersedesClaimId for durable correction.',v_variant_key
          using errcode='23505';
      end if;
      if v_supersedes_claim_id is not null
         and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
        raise exception 'process variant supersedesClaimId must identify the current claim for variant %.',v_variant_key
          using errcode='23505';
      end if;

      v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
        'sourceKey',v_source_key,
        'subject',jsonb_build_object(
          'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
        ),
        'evidence',jsonb_build_object(
          'kind','principal_calibration_answer',
          'value',v_fact_value,
          'confidence',1,
          'provenance',jsonb_strip_nulls(jsonb_build_object(
            'sourceActionId',v_source_action_id,
            'kernelKey','household.laundry',
            'kernelVersion',v_kernel_version,
            'selectedModelKey',v_model_key,
            'calibrationContract','household_laundry_instance_truth_v1'
          ))
        ),
        'claim',jsonb_strip_nulls(jsonb_build_object(
          'claimType',v_claim_type,
          'lifecycleState','accepted',
          'value',v_fact_value,
          'confidence',1,
          'supersedesClaimId',v_supersedes_claim_id,
          'metadata',jsonb_build_object(
            'factName',v_fact_name,
            'schedulingAuthority',false
          )
        ))
      ));
      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    v_fact_name := 'turnaround_relationships';
    v_claim_type := 'turnaround_relationships';
    v_source_key := v_source_action_id||':turnaround_relationships';
    v_fact_value := v_turnaround;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry turnaround relationships already have current truth; supply supersedes.turnaround_relationships for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.turnaround_relationships must identify the current Laundry turnaround relationship claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'deadlineConsequenceAuthority',false
        )
      ))
    ));
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
  v_user_id uuid;
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
begin
  v_user_id := auth.uid();
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
    raise exception 'Laundry V1 projection returned invalid instance identity.' using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
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
  end if;

  return v_base
    || jsonb_build_object(
      'contractVersion','personal_laundry_kernel_self_api_v2',
      'instanceFacts',v_facts,
      'truthBoundary',jsonb_build_object(
        'worldKernelAndHouseholdInstanceRemainDistinct',true,
        'instanceFactsComeFromHouseholdClaimEvidence',true,
        'legacyConfigurationIsNotV2FactAuthority',true,
        'rhythmIsSeparateDownstreamAuthority',true,
        'readCreatesNoTruth',true,
        'readCreatesNoClockPlacement',true
      )
    );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read the current Household Laundry world-kernel projection plus current source-backed Household Claim/Evidence facts for its durable instance. Any Rhythm remains separately projected and is not treated as calibration fact authority.';

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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)',
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry V2 instance-truth registration.';
  end if;
end
$$;

commit;
 then
        raise exception 'process variant key must be a stable lowercase token using letters, numbers, dot, underscore, or hyphen.'
          using errcode='22023';
      end if;

      if v_variant_key = any(v_variant_keys) then
        raise exception 'processVariants keys must be unique within one calibration call.'
          using errcode='22023';
      end if;
      v_variant_keys := array_append(v_variant_keys,v_variant_key);

      foreach v_forbidden_key in array array[
        'cadenceRule','recurrence','nextDueAt','dueAt','dueDate',
        'floorClass','protectionLevel','principalRequired','blocksCapacity',
        'clockPlacement','todayPlacement','expectedMinutes'
      ] loop
        if v_variant ? v_forbidden_key then
          raise exception 'Process variant may not carry scheduling/Clock authority field: %',v_forbidden_key
            using errcode='22023';
        end if;
      end loop;

      if v_variant ? 'supersedesClaimId' then
        begin
          perform nullif(v_variant->>'supersedesClaimId','')::uuid;
        exception when invalid_text_representation then
          raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
        end;
      end if;
    end loop;

    if jsonb_array_length(v_process_variants)>0 then
      v_fact_count := v_fact_count + jsonb_array_length(v_process_variants);
    end if;
  end if;

  if p_input ? 'turnaroundRelationships' then
    v_turnaround := p_input->'turnaroundRelationships';
    if jsonb_typeof(v_turnaround)<>'array' then
      raise exception 'turnaroundRelationships must be an array.' using errcode='22023';
    end if;
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

  -- Establish only the durable instance root. Existing configuration is
  -- preserved; V2 fact authority lives in Household Claim/Evidence.
  insert into atlas.household_kernel_instances(
    household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata
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
    jsonb_strip_nulls(jsonb_build_object(
      'source','principal_progressive_calibration',
      'sourceActionId',v_source_action_id,
      'calibratedBy',v_user_id,
      'factAuthority','household_claim_evidence_v1',
      'calibrationContract','household_laundry_instance_truth_v1',
      'selectedModelKey',v_model_key
    ))
  )
  on conflict(household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,
    state='active',
    configuration=atlas.household_kernel_instances.configuration
      || jsonb_build_object(
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1'
      ),
    calibrated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.calibrated_at
      else now()
    end,
    metadata=atlas.household_kernel_instances.metadata
      || jsonb_strip_nulls(jsonb_build_object(
        'source','principal_progressive_calibration',
        'sourceActionId',v_source_action_id,
        'calibratedBy',v_user_id,
        'factAuthority','household_claim_evidence_v1',
        'calibrationContract','household_laundry_instance_truth_v1',
        'selectedModelKey',v_model_key
      )),
    updated_at=case
      when atlas.household_kernel_instances.metadata->>'sourceActionId'=v_source_action_id
        then atlas.household_kernel_instances.updated_at
      else now()
    end
  returning * into v_instance;

  -- Helper pattern repeated for singleton facts:
  -- if there is already a current accepted claim of this exact type, a new
  -- source action must explicitly supersede it. Same sourceAction retries are
  -- handled idempotently by the Household Claim/Evidence membrane.

  if v_location is not null then
    v_fact_name := 'location';
    v_claim_type := 'location';
    v_source_key := v_source_action_id||':location';
    v_fact_value := jsonb_build_object('kind',v_location);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'location','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.location must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry location already has current truth; supply supersedes.location for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.location must identify the current Laundry location claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object('factName',v_fact_name)
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_responsibility is not null then
    v_fact_name := 'ordinary_responsibility';
    v_claim_type := 'ordinary_responsibility';
    v_source_key := v_source_action_id||':ordinary_responsibility';
    v_fact_value := v_responsibility;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'ordinary_responsibility','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.ordinary_responsibility must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry ordinary responsibility already has current truth; supply supersedes.ordinary_responsibility for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.ordinary_responsibility must identify the current Laundry responsibility claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'carrierSelectionAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_need_driver is not null then
    v_fact_name := 'need_generation';
    v_claim_type := 'need_generation';
    v_source_key := v_source_action_id||':need_generation';
    v_fact_value := jsonb_build_object('kind',v_need_driver);

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'need_generation','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.need_generation must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry need generation already has current truth; supply supersedes.need_generation for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.need_generation must identify the current Laundry need-generation claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'recurrenceAuthority',false
        )
      ))
    ));
    v_claims := v_claims || jsonb_build_array(v_result);
  end if;

  if v_process_variants is not null then
    for v_variant in
      select value from jsonb_array_elements(v_process_variants)
    loop
      v_variant_key := btrim(v_variant->>'key');
      v_fact_name := 'process_variant:'||v_variant_key;
      v_claim_type := v_fact_name;
      v_source_key := v_source_action_id||':process_variant:'||v_variant_key;
      v_fact_value := v_variant - 'supersedesClaimId';

      begin
        v_supersedes_claim_id := nullif(v_variant->>'supersedesClaimId','')::uuid;
      exception when invalid_text_representation then
        raise exception 'process variant supersedesClaimId must be a UUID.' using errcode='22023';
      end;

      select * into v_existing_claim
      from atlas.claim_records c
      where c.scope_kind='household'
        and c.scope_id=v_household_id
        and c.subject_domain='household.laundry'
        and c.subject_kind='kernel_instance'
        and c.subject_id=v_instance.id::text
        and c.claim_type=v_claim_type
        and c.lifecycle_state not in ('superseded','expired','rejected')
      order by c.recorded_at desc,c.id desc
      limit 1;

      if v_existing_claim.id is not null
         and v_existing_claim.source_key<>v_source_key
         and v_supersedes_claim_id is null then
        raise exception 'Laundry process variant % already has current truth; supply its supersedesClaimId for durable correction.',v_variant_key
          using errcode='23505';
      end if;
      if v_supersedes_claim_id is not null
         and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
        raise exception 'process variant supersedesClaimId must identify the current claim for variant %.',v_variant_key
          using errcode='23505';
      end if;

      v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
        'sourceKey',v_source_key,
        'subject',jsonb_build_object(
          'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
        ),
        'evidence',jsonb_build_object(
          'kind','principal_calibration_answer',
          'value',v_fact_value,
          'confidence',1,
          'provenance',jsonb_strip_nulls(jsonb_build_object(
            'sourceActionId',v_source_action_id,
            'kernelKey','household.laundry',
            'kernelVersion',v_kernel_version,
            'selectedModelKey',v_model_key,
            'calibrationContract','household_laundry_instance_truth_v1'
          ))
        ),
        'claim',jsonb_strip_nulls(jsonb_build_object(
          'claimType',v_claim_type,
          'lifecycleState','accepted',
          'value',v_fact_value,
          'confidence',1,
          'supersedesClaimId',v_supersedes_claim_id,
          'metadata',jsonb_build_object(
            'factName',v_fact_name,
            'schedulingAuthority',false
          )
        ))
      ));
      v_claims := v_claims || jsonb_build_array(v_result);
    end loop;
  end if;

  if v_turnaround is not null then
    v_fact_name := 'turnaround_relationships';
    v_claim_type := 'turnaround_relationships';
    v_source_key := v_source_action_id||':turnaround_relationships';
    v_fact_value := v_turnaround;

    begin
      v_supersedes_claim_id := nullif(v_supersedes->>'turnaround_relationships','')::uuid;
    exception when invalid_text_representation then
      raise exception 'supersedes.turnaround_relationships must be a UUID.' using errcode='22023';
    end;

    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type=v_claim_type
      and c.lifecycle_state not in ('superseded','expired','rejected')
    order by c.recorded_at desc,c.id desc
    limit 1;

    if v_existing_claim.id is not null
       and v_existing_claim.source_key<>v_source_key
       and v_supersedes_claim_id is null then
      raise exception 'Laundry turnaround relationships already have current truth; supply supersedes.turnaround_relationships for durable correction.'
        using errcode='23505';
    end if;
    if v_supersedes_claim_id is not null
       and (v_existing_claim.id is null or v_existing_claim.id<>v_supersedes_claim_id) then
      raise exception 'supersedes.turnaround_relationships must identify the current Laundry turnaround relationship claim.'
        using errcode='23505';
    end if;

    v_result := atlas.record_current_household_claim_evidence_api_v1(jsonb_build_object(
      'sourceKey',v_source_key,
      'subject',jsonb_build_object(
        'domain','household.laundry','kind','kernel_instance','id',v_instance.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','principal_calibration_answer',
        'value',v_fact_value,
        'confidence',1,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_action_id,
          'kernelKey','household.laundry',
          'kernelVersion',v_kernel_version,
          'selectedModelKey',v_model_key,
          'calibrationContract','household_laundry_instance_truth_v1'
        ))
      ),
      'claim',jsonb_strip_nulls(jsonb_build_object(
        'claimType',v_claim_type,
        'lifecycleState','accepted',
        'value',v_fact_value,
        'confidence',1,
        'supersedesClaimId',v_supersedes_claim_id,
        'metadata',jsonb_build_object(
          'factName',v_fact_name,
          'deadlineConsequenceAuthority',false
        )
      ))
    ));
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
  v_user_id uuid;
  v_household_id uuid;
  v_base jsonb;
  v_instance_id uuid;
  v_facts jsonb;
begin
  v_user_id := auth.uid();
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
    raise exception 'Laundry V1 projection returned invalid instance identity.' using errcode='23514';
  end;

  if v_instance_id is null then
    v_facts := '[]'::jsonb;
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
  end if;

  return v_base
    || jsonb_build_object(
      'contractVersion','personal_laundry_kernel_self_api_v2',
      'instanceFacts',v_facts,
      'truthBoundary',jsonb_build_object(
        'worldKernelAndHouseholdInstanceRemainDistinct',true,
        'instanceFactsComeFromHouseholdClaimEvidence',true,
        'legacyConfigurationIsNotV2FactAuthority',true,
        'rhythmIsSeparateDownstreamAuthority',true,
        'readCreatesNoTruth',true,
        'readCreatesNoClockPlacement',true
      )
    );
end;
$$;

comment on function atlas.personal_laundry_kernel_self_api_v2() is
  'Read the current Household Laundry world-kernel projection plus current source-backed Household Claim/Evidence facts for its durable instance. Any Rhythm remains separately projected and is not treated as calibration fact authority.';

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
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(p_input jsonb)',
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry V2 instance-truth registration.';
  end if;
end
$$;

commit;

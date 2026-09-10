-- Complete household Cleaning as a dedicated Personal Reality Kernel, following Laundry's pattern.
-- The kernel describes what Cleaning is and how this household tends to carry it.
-- FlyLady-derived five-zone attention is a separate standing exposure policy; it is not a selectable model here.

update atlas.world_kernel_definitions
set active=false
where kernel_key='household.cleaning' and version=1;

insert into atlas.world_kernel_definitions(kernel_key,version,scope_kind,title,definition,active)
values(
  'household.cleaning',
  2,
  'household',
  'Cleaning',
  jsonb_build_object(
    'contractVersion','household_cleaning_world_kernel_v1',
    'ordinary',true,
    'topology',jsonb_build_array('use_space','accumulate_disorder_soil','reset_clean','restore_ready_state'),
    'dependencies',jsonb_build_array('people','occupied_spaces','surfaces','supplies','care_load','hosting','property_scale'),
    'nonClaims',jsonb_build_array(
      'room_count_known',
      'property_size_known',
      'children_present',
      'pets_present',
      'hosting_frequency_known',
      'room_zone_assignment_known',
      'physical_condition_known',
      'specific_cadence'
    )
  ),
  true
)
on conflict (kernel_key,version) do update set
  scope_kind=excluded.scope_kind,
  title=excluded.title,
  definition=excluded.definition,
  active=true;

insert into atlas.world_kernel_models(
  kernel_key,kernel_version,audience_key,model_key,title,summary,configuration,position,active,context_tags
)
values
  (
    'household.cleaning',2,'general','cleaning_steady_reset','Steady reset',
    'Small resets keep ordinary rooms from tipping over.',
    jsonb_build_object('style','steady_reset','usualPattern','little_most_days','expectedMinutes',30),
    1,true,'[]'::jsonb
  ),
  (
    'household.cleaning',2,'general','cleaning_weekly_reset','Weekly reset',
    'Daily life is tolerated and most cleaning effort is concentrated into one larger reset.',
    jsonb_build_object('style','weekly_reset','usualPattern','main_day','expectedMinutes',120),
    2,true,'[]'::jsonb
  ),
  (
    'household.cleaning',2,'general','cleaning_host_ready','Host-ready rhythm',
    'Frequent quick resets protect the rooms guests actually see.',
    jsonb_build_object('style','host_ready','usualPattern','few_times_week','expectedMinutes',45),
    3,true,'[]'::jsonb
  )
on conflict (kernel_key,kernel_version,model_key) do update set
  audience_key=excluded.audience_key,
  title=excluded.title,
  summary=excluded.summary,
  configuration=excluded.configuration,
  position=excluded.position,
  active=true,
  context_tags=excluded.context_tags;

create or replace function atlas.personal_cleaning_kernel_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_kernel atlas.world_kernel_definitions%rowtype;
  v_instance atlas.household_kernel_instances%rowtype;
  v_rhythm atlas.household_rhythms%rowtype;
  v_member_count integer := 0;
  v_models jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  select * into v_kernel
  from atlas.world_kernel_definitions k
  where k.kernel_key='household.cleaning' and k.active
  order by k.version desc
  limit 1;
  if v_kernel.kernel_key is null then raise exception 'Cleaning world kernel is unavailable.' using errcode='55000'; end if;

  select count(*)::integer into v_member_count
  from atlas.household_members m
  where m.household_id=v_household_id and m.active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'modelKey',m.model_key,
    'audienceKey',m.audience_key,
    'title',m.title,
    'summary',m.summary,
    'configuration',m.configuration
  ) order by m.position),'[]'::jsonb)
  into v_models
  from atlas.world_kernel_models m
  where m.kernel_key=v_kernel.kernel_key
    and m.kernel_version=v_kernel.version
    and m.audience_key='general'
    and m.active;

  select * into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id and i.kernel_key='household.cleaning'
  limit 1;

  select * into v_rhythm
  from atlas.household_rhythms r
  where r.household_id=v_household_id and r.stable_key='kernel:household.cleaning:general'
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_kernel_self_api_v1',
    'householdId',v_household_id,
    'modelSelection',jsonb_build_object(
      'audienceKey','general',
      'knownMemberCount',v_member_count,
      'basis','general_cleaning_workload_starting_points',
      'assumptionsMade',false,
      'zoneExposurePolicySeparate',true
    ),
    'models',v_models,
    'kernel',jsonb_build_object(
      'key',v_kernel.kernel_key,
      'version',v_kernel.version,
      'title',v_kernel.title,
      'definition',v_kernel.definition,
      'ordinaryRealityExpected',true
    ),
    'instance',case when v_instance.id is null then null else jsonb_build_object(
      'id',v_instance.id,
      'state',v_instance.state,
      'configuration',v_instance.configuration,
      'calibratedAt',v_instance.calibrated_at,
      'metadata',v_instance.metadata
    ) end,
    'rhythm',case when v_rhythm.id is null then null else jsonb_build_object(
      'id',v_rhythm.id,
      'title',v_rhythm.title,
      'cadenceRule',v_rhythm.cadence_rule,
      'expectedMinutes',v_rhythm.expected_minutes,
      'active',v_rhythm.active,
      'nextWindowStart',v_rhythm.next_window_start,
      'nextWindowEnd',v_rhythm.next_window_end,
      'metadata',v_rhythm.metadata
    ) end
  );
end;
$function$;

create or replace function atlas.calibrate_personal_cleaning_kernel_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_config jsonb := '{}'::jsonb;
  v_style text;
  v_pattern text;
  v_priority text[] := '{}'::text[];
  v_notes text;
  v_expected integer;
  v_instance atlas.household_kernel_instances%rowtype;
  v_rhythm_result jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Cleaning calibration input must be an object.' using errcode='22023'; end if;

  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  select max(k.version) into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key='household.cleaning' and k.active;
  if v_kernel_version is null then raise exception 'Cleaning world kernel is unavailable.' using errcode='55000'; end if;

  v_model_key:=nullif(trim(p_input->>'modelKey'),'');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key='household.cleaning'
      and m.kernel_version=v_kernel_version
      and m.model_key=v_model_key
      and m.active;
    if v_model.model_key is null then raise exception 'Unknown Cleaning model.' using errcode='22023'; end if;
    v_config:=v_model.configuration;
  end if;

  v_config:=v_config || jsonb_strip_nulls(jsonb_build_object(
    'style',nullif(trim(p_input->>'style'),''),
    'usualPattern',nullif(trim(p_input->>'usualPattern'),''),
    'notes',nullif(trim(p_input->>'notes'),''),
    'expectedMinutes',case when nullif(p_input->>'expectedMinutes','') is null then null else (p_input->>'expectedMinutes')::integer end
  ));

  if p_input ? 'priorityAreas' then
    if jsonb_typeof(p_input->'priorityAreas') <> 'array' then raise exception 'priorityAreas must be an array.' using errcode='22023'; end if;
    v_config:=v_config || jsonb_build_object('priorityAreas',p_input->'priorityAreas');
  end if;

  v_style:=nullif(trim(v_config->>'style'),'');
  v_pattern:=nullif(trim(v_config->>'usualPattern'),'');
  v_notes:=nullif(trim(v_config->>'notes'),'');
  v_expected:=coalesce(nullif(v_config->>'expectedMinutes','')::integer,45);

  if v_style is null or v_style not in ('steady_reset','weekly_reset','host_ready','other') then
    raise exception 'Supported cleaning style required.' using errcode='22023';
  end if;
  if v_pattern is null or v_pattern not in ('little_most_days','few_times_week','main_day','as_needed','other') then
    raise exception 'Supported cleaning pattern required.' using errcode='22023';
  end if;
  if v_expected <= 0 then raise exception 'expectedMinutes must be positive.' using errcode='22023'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::text[])
  into v_priority
  from jsonb_array_elements_text(coalesce(v_config->'priorityAreas','[]'::jsonb)) t(x)
  where x in ('kitchen','bathrooms','floors','entry_living','bedrooms','work_spaces','other');
  v_config:=v_config || jsonb_build_object('priorityAreas',to_jsonb(v_priority));

  insert into atlas.household_kernel_instances(
    household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata
  ) values(
    v_household_id,'household.cleaning',v_kernel_version,'active',v_config,now(),
    jsonb_strip_nulls(jsonb_build_object(
      'source','principal_calibration',
      'calibratedBy',auth.uid(),
      'calibrationContract','household_cleaning_calibration_v1',
      'selectedModelKey',v_model_key,
      'selectedModelAudience',case when v_model_key is null then null else v_model.audience_key end
    ))
  )
  on conflict (household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,
    state='active',
    configuration=atlas.household_kernel_instances.configuration || excluded.configuration,
    calibrated_at=now(),
    metadata=atlas.household_kernel_instances.metadata || excluded.metadata,
    updated_at=now()
  returning * into v_instance;

  v_rhythm_result:=atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
    'stableKey','kernel:household.cleaning:general',
    'area','cleaning',
    'title','Cleaning workload',
    'cadenceRule',v_pattern,
    'expectedMinutes',v_expected,
    'protectionLevel','protected',
    'floorClass',3,
    'interruptibility','interruptible',
    'principalRequired',true,
    'blocksCapacity',true,
    'consequence','Occupied household spaces need recurring restoration to remain usable for ordinary life.',
    'reasonForFloor','Broad household Cleaning workload calibrated separately from five-zone area exposure.',
    'metadata',jsonb_strip_nulls(jsonb_build_object(
      'worldKernelKey','household.cleaning',
      'worldKernelVersion',v_kernel_version,
      'source','household_cleaning_calibration_v1',
      'selectedModelKey',v_model_key,
      'semanticCadence',true,
      'clockWindowEstablished',false,
      'zoneExposurePolicySeparate',true
    ))
  ));

  return jsonb_build_object(
    'ok',true,
    'contractVersion','household_cleaning_calibration_v1',
    'selectedModelKey',v_model_key,
    'instance',jsonb_build_object(
      'id',v_instance.id,
      'state',v_instance.state,
      'configuration',v_instance.configuration,
      'calibratedAt',v_instance.calibrated_at,
      'metadata',v_instance.metadata
    ),
    'rhythm',v_rhythm_result,
    'claimsCreated',jsonb_build_object(
      'roomCountKnown',false,
      'propertySizeKnown',false,
      'childrenPresent',false,
      'petsPresent',false,
      'hostingFrequencyKnown',false,
      'roomZoneAssignmentKnown',false,
      'physicalConditionKnown',false
    )
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_kernel_self_api_v1() from public,anon;
revoke all on function atlas.calibrate_personal_cleaning_kernel_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.personal_cleaning_kernel_self_api_v1() to authenticated,service_role;
grant execute on function atlas.calibrate_personal_cleaning_kernel_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.personal_cleaning_kernel_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_cleaning_kernel_self_api_v1(); $function$;

create or replace function public.calibrate_personal_cleaning_kernel_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.calibrate_personal_cleaning_kernel_self_api_v1(p_input); $function$;

revoke all on function public.personal_cleaning_kernel_self_api_v1() from public,anon;
revoke all on function public.calibrate_personal_cleaning_kernel_self_api_v1(jsonb) from public,anon;
grant execute on function public.personal_cleaning_kernel_self_api_v1() to authenticated,service_role;
grant execute on function public.calibrate_personal_cleaning_kernel_self_api_v1(jsonb) to authenticated,service_role;

-- Cleaning no longer uses the generic model-acceptance carrier. Keep that path only for Groceries
-- until Groceries receives its own dedicated kernel contract.
create or replace function atlas.accept_personal_kernel_model_self_api_v1(p_kernel_key text,p_model_key text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_instance atlas.household_kernel_instances%rowtype;
  v_pattern text;
  v_expected integer;
  v_rhythm jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_kernel_key <> 'household.groceries' then raise exception 'Kernel is not available through generic model acceptance.' using errcode='22023'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  select max(version) into v_version from atlas.world_kernel_definitions where kernel_key=p_kernel_key and active;
  select * into v_model from atlas.world_kernel_models where kernel_key=p_kernel_key and kernel_version=v_version and model_key=p_model_key and active;
  if v_model.model_key is null then raise exception 'Unknown kernel model.' using errcode='22023'; end if;

  insert into atlas.household_kernel_instances(household_id,kernel_key,kernel_version,state,configuration,calibrated_at,metadata)
  values(v_household_id,p_kernel_key,v_version,'active',v_model.configuration,now(),jsonb_build_object('source','principal_model_acceptance','selectedModelKey',v_model.model_key,'selectedAt',now(),'calibratedBy',auth.uid()))
  on conflict(household_id,kernel_key) do update set
    kernel_version=excluded.kernel_version,state='active',configuration=excluded.configuration,calibrated_at=now(),metadata=atlas.household_kernel_instances.metadata||excluded.metadata,updated_at=now()
  returning * into v_instance;

  v_pattern:=nullif(v_model.configuration->>'usualPattern','');
  v_expected:=coalesce(nullif(v_model.configuration->>'expectedMinutes','')::integer,45);
  if v_pattern is not null then
    v_rhythm:=atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
      'stableKey','kernel:'||p_kernel_key||':general',
      'area','groceries',
      'title','Groceries',
      'cadenceRule',v_pattern,
      'expectedMinutes',v_expected,
      'protectionLevel','protected',
      'floorClass',3,
      'interruptibility','interruptible',
      'principalRequired',true,
      'blocksCapacity',true,
      'reasonForFloor','Ordinary household reality calibrated from a source-controlled Personal Reality Kernel model.',
      'metadata',jsonb_build_object('worldKernelKey',p_kernel_key,'worldKernelVersion',v_version,'selectedModelKey',v_model.model_key,'semanticCadence',true,'clockWindowEstablished',false)
    ));
  end if;

  return jsonb_build_object('ok',true,'kernelKey',p_kernel_key,'selectedModelKey',v_model.model_key,'instance',jsonb_build_object('id',v_instance.id,'configuration',v_instance.configuration,'calibratedAt',v_instance.calibrated_at),'rhythm',v_rhythm);
end;
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.personal_cleaning_kernel_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read the dedicated household Cleaning world kernel, workload models, calibrated instance, and broad rhythm independently of the standing five-zone attention policy.'),now()),
  ('atlas.calibrate_personal_cleaning_kernel_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Calibrate household Cleaning workload/style without selecting or disabling the standing five-zone attention policy.'),now())
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence || excluded.evidence,
  reviewed_at=now();

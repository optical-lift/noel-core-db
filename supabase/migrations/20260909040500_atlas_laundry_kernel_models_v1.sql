-- Set Laundry model library for Personal Atlas.
-- Models are generic starting configurations selected from known Household evidence.
-- A model is not Household truth until the Principal chooses/calibrates it.

create table if not exists atlas.world_kernel_models (
  kernel_key text not null,
  kernel_version integer not null,
  audience_key text not null,
  model_key text not null,
  title text not null,
  summary text not null,
  configuration jsonb not null,
  position smallint not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (kernel_key, kernel_version, model_key),
  foreign key (kernel_key, kernel_version)
    references atlas.world_kernel_definitions(kernel_key, version)
);

comment on table atlas.world_kernel_models is
  'Source-controlled preset models for a world kernel. Models are candidate starting configurations chosen from known context; they do not assert household-specific truth until accepted/calibrated.';

alter table atlas.world_kernel_models enable row level security;
revoke all on atlas.world_kernel_models from public, anon, authenticated;

insert into atlas.world_kernel_models (
  kernel_key, kernel_version, audience_key, model_key, title, summary, configuration, position, active
) values
  ('household.laundry', 1, 'general', 'general_steady_home',
   'Keep it moving',
   'Laundry happens at home in a steady background rhythm rather than one giant reset.',
   jsonb_build_object('laundryLocation','home','usualPattern','few_times_week','expectedMinutes',45,'divisionStyle','shared_flow'), 1, true),
  ('household.laundry', 1, 'general', 'general_batch_day',
   'One laundry day',
   'Most laundry is gathered up and handled in one main block.',
   jsonb_build_object('laundryLocation','home','usualPattern','main_day','expectedMinutes',75,'divisionStyle','batch'), 2, true),
  ('household.laundry', 1, 'general', 'general_outside_help',
   'Somebody else handles most of it',
   'Laundry is mostly handled by a service, another household, or another arrangement outside the ordinary home-machine flow.',
   jsonb_build_object('laundryLocation','service','usualPattern','as_needed','expectedMinutes',25,'divisionStyle','outside_help'), 3, true),

  ('household.laundry', 1, 'one_person', 'one_person_home_reset',
   'Home reset',
   'One person, home machines, and one main reset when the basket is ready.',
   jsonb_build_object('laundryLocation','home','usualPattern','main_day','expectedMinutes',45,'divisionStyle','single_person'), 1, true),
  ('household.laundry', 1, 'one_person', 'one_person_laundromat',
   'Laundromat run',
   'Laundry gets collected and handled in one laundromat trip.',
   jsonb_build_object('laundryLocation','laundromat','usualPattern','main_day','expectedMinutes',90,'divisionStyle','single_person'), 2, true),
  ('household.laundry', 1, 'one_person', 'one_person_handled_elsewhere',
   'Mostly handled for me',
   'Dry cleaner, wash-and-fold, family help, or another arrangement handles most of the laundry.',
   jsonb_build_object('laundryLocation','service','usualPattern','as_needed','expectedMinutes',20,'divisionStyle','outside_help'), 3, true),

  ('household.laundry', 1, 'shared_household', 'shared_steady_flow',
   'Shared steady flow',
   'A couple or small household keeps laundry moving in a few ordinary passes through the week.',
   jsonb_build_object('laundryLocation','home','usualPattern','few_times_week','expectedMinutes',55,'divisionStyle','shared_flow'), 1, true),
  ('household.laundry', 1, 'shared_household', 'shared_person_lanes',
   'Separate lanes',
   'People mostly keep their own loads or categories separate, with several passes through the week.',
   jsonb_build_object('laundryLocation','home','usualPattern','few_times_week','expectedMinutes',50,'divisionStyle','by_person_or_category'), 2, true),
  ('household.laundry', 1, 'shared_household', 'shared_weekend_reset',
   'Weekend reset',
   'The household lets most laundry accumulate and handles the bulk of it in one larger reset.',
   jsonb_build_object('laundryLocation','home','usualPattern','main_day','expectedMinutes',90,'divisionStyle','batch'), 3, true),

  ('household.laundry', 1, 'family_busy', 'family_continuous_flow',
   'Keep the machines moving',
   'Laundry is a background household system: small or medium loads keep moving most days.',
   jsonb_build_object('laundryLocation','home','usualPattern','little_most_days','expectedMinutes',75,'divisionStyle','continuous_flow'), 1, true),
  ('household.laundry', 1, 'family_busy', 'family_laundry_days',
   'A few laundry days',
   'The household concentrates laundry into a few recurring days instead of carrying it every day.',
   jsonb_build_object('laundryLocation','home','usualPattern','few_times_week','expectedMinutes',90,'divisionStyle','calendar_days'), 2, true),
  ('household.laundry', 1, 'family_busy', 'family_people_lanes',
   'People have lanes',
   'Laundry is divided by person, room, or category so a large household does not become one giant pile.',
   jsonb_build_object('laundryLocation','home','usualPattern','few_times_week','expectedMinutes',75,'divisionStyle','by_person_or_room'), 3, true)
on conflict (kernel_key, kernel_version, model_key) do update set
  audience_key = excluded.audience_key,
  title = excluded.title,
  summary = excluded.summary,
  configuration = excluded.configuration,
  position = excluded.position,
  active = excluded.active;

create or replace function atlas.personal_laundry_kernel_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_kernel atlas.world_kernel_definitions%rowtype;
  v_instance atlas.household_kernel_instances%rowtype;
  v_rhythm atlas.household_rhythms%rowtype;
  v_member_count integer := 0;
  v_child_count integer := 0;
  v_composition_complete boolean := false;
  v_audience_key text := 'general';
  v_models jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select * into v_kernel
  from atlas.world_kernel_definitions k
  where k.kernel_key = 'household.laundry'
    and k.active
  order by k.version desc
  limit 1;

  select count(*)::integer,
         count(*) filter (where lower(coalesce(m.relationship,'')) in ('child','son','daughter','dependent_child'))::integer
    into v_member_count, v_child_count
  from atlas.household_members m
  where m.household_id = v_household_id
    and m.active;

  select coalesce((h.metadata->>'compositionComplete')::boolean, false)
    into v_composition_complete
  from atlas.households h
  where h.id = v_household_id;

  if v_member_count >= 5 or v_child_count >= 3 then
    v_audience_key := 'family_busy';
  elsif v_member_count >= 2 then
    v_audience_key := 'shared_household';
  elsif v_member_count = 1 and v_composition_complete then
    v_audience_key := 'one_person';
  else
    v_audience_key := 'general';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'modelKey', m.model_key,
    'audienceKey', m.audience_key,
    'title', m.title,
    'summary', m.summary,
    'configuration', m.configuration
  ) order by m.position), '[]'::jsonb)
    into v_models
  from atlas.world_kernel_models m
  where m.kernel_key = v_kernel.kernel_key
    and m.kernel_version = v_kernel.version
    and m.audience_key = v_audience_key
    and m.active;

  select * into v_instance
  from atlas.household_kernel_instances i
  where i.household_id = v_household_id
    and i.kernel_key = 'household.laundry'
  limit 1;

  select * into v_rhythm
  from atlas.household_rhythms r
  where r.household_id = v_household_id
    and r.stable_key = 'kernel:household.laundry:general'
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'personal_laundry_kernel_self_api_v1',
    'householdId', v_household_id,
    'modelSelection', jsonb_build_object(
      'audienceKey', v_audience_key,
      'knownMemberCount', v_member_count,
      'knownChildCount', v_child_count,
      'compositionComplete', v_composition_complete,
      'basis', case
        when v_audience_key = 'family_busy' then 'known_household_size'
        when v_audience_key = 'shared_household' then 'known_shared_household'
        when v_audience_key = 'one_person' then 'confirmed_one_person_household'
        else 'household_composition_not_yet_complete'
      end
    ),
    'models', v_models,
    'kernel', jsonb_build_object(
      'key', v_kernel.kernel_key,
      'version', v_kernel.version,
      'title', v_kernel.title,
      'definition', v_kernel.definition,
      'ordinaryRealityExpected', true
    ),
    'instance', case when v_instance.id is null then null else jsonb_build_object(
      'id', v_instance.id,
      'state', v_instance.state,
      'configuration', v_instance.configuration,
      'calibratedAt', v_instance.calibrated_at,
      'metadata', v_instance.metadata
    ) end,
    'rhythm', case when v_rhythm.id is null then null else jsonb_build_object(
      'id', v_rhythm.id,
      'title', v_rhythm.title,
      'cadenceRule', v_rhythm.cadence_rule,
      'expectedMinutes', v_rhythm.expected_minutes,
      'active', v_rhythm.active,
      'nextWindowStart', v_rhythm.next_window_start,
      'nextWindowEnd', v_rhythm.next_window_end,
      'metadata', v_rhythm.metadata
    ) end
  );
end;
$$;

create or replace function atlas.calibrate_personal_laundry_kernel_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_kernel_version integer;
  v_model atlas.world_kernel_models%rowtype;
  v_model_key text;
  v_config jsonb := '{}'::jsonb;
  v_location text;
  v_pattern text;
  v_special text[];
  v_notes text;
  v_expected integer;
  v_instance atlas.household_kernel_instances%rowtype;
  v_rhythm_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;
  if p_input is null or jsonb_typeof(p_input) <> 'object' then
    raise exception 'Laundry calibration input must be an object.' using errcode = '22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  select max(k.version) into v_kernel_version
  from atlas.world_kernel_definitions k
  where k.kernel_key = 'household.laundry' and k.active;

  v_model_key := nullif(trim(p_input->>'modelKey'), '');
  if v_model_key is not null then
    select * into v_model
    from atlas.world_kernel_models m
    where m.kernel_key = 'household.laundry'
      and m.kernel_version = v_kernel_version
      and m.model_key = v_model_key
      and m.active;
    if v_model.model_key is null then
      raise exception 'Unknown Laundry model.' using errcode = '22023';
    end if;
    v_config := v_model.configuration;
  end if;

  v_config := v_config || jsonb_strip_nulls(jsonb_build_object(
    'laundryLocation', nullif(trim(p_input->>'laundryLocation'), ''),
    'usualPattern', nullif(trim(p_input->>'usualPattern'), ''),
    'notes', nullif(trim(p_input->>'notes'), ''),
    'expectedMinutes', case when nullif(p_input->>'expectedMinutes','') is null then null else (p_input->>'expectedMinutes')::integer end
  ));

  if p_input ? 'specialTurnaround' then
    v_config := v_config || jsonb_build_object('specialTurnaround', p_input->'specialTurnaround');
  end if;

  v_location := nullif(trim(v_config->>'laundryLocation'), '');
  v_pattern := nullif(trim(v_config->>'usualPattern'), '');
  v_notes := nullif(trim(v_config->>'notes'), '');
  v_expected := coalesce(nullif(v_config->>'expectedMinutes','')::integer, 45);

  if v_location is not null and v_location not in ('home','shared_machines','laundromat','service','other') then
    raise exception 'Unsupported laundryLocation.' using errcode = '22023';
  end if;
  if v_pattern is not null and v_pattern not in ('little_most_days','few_times_week','main_day','as_needed','other') then
    raise exception 'Unsupported usualPattern.' using errcode = '22023';
  end if;
  if v_expected <= 0 then
    raise exception 'expectedMinutes must be positive.' using errcode = '22023';
  end if;

  select coalesce(array_agg(x), '{}'::text[]) into v_special
  from jsonb_array_elements_text(coalesce(v_config->'specialTurnaround', '[]'::jsonb)) t(x);
  v_config := v_config || jsonb_build_object('specialTurnaround', to_jsonb(v_special));

  if v_location is null or v_pattern is null then
    raise exception 'Laundry location and usual pattern are required after model selection/calibration.' using errcode = '22023';
  end if;

  insert into atlas.household_kernel_instances (
    household_id, kernel_key, kernel_version, state, configuration, calibrated_at, metadata
  ) values (
    v_household_id,
    'household.laundry',
    v_kernel_version,
    'active',
    v_config,
    now(),
    jsonb_strip_nulls(jsonb_build_object(
      'source', 'principal_calibration',
      'calibratedBy', auth.uid(),
      'calibrationContract', 'household_laundry_calibration_v1',
      'selectedModelKey', v_model_key,
      'selectedModelAudience', case when v_model_key is null then null else v_model.audience_key end
    ))
  )
  on conflict (household_id, kernel_key) do update set
    kernel_version = excluded.kernel_version,
    state = 'active',
    configuration = atlas.household_kernel_instances.configuration || excluded.configuration,
    calibrated_at = now(),
    metadata = atlas.household_kernel_instances.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_instance;

  v_rhythm_result := atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
    'stableKey', 'kernel:household.laundry:general',
    'area', 'laundry',
    'title', 'Laundry',
    'cadenceRule', v_pattern,
    'expectedMinutes', v_expected,
    'protectionLevel', 'protected',
    'floorClass', 3,
    'interruptibility', 'interruptible',
    'principalRequired', true,
    'blocksCapacity', true,
    'consequence', 'Clean clothing must remain available for ordinary household life and time-bound garment needs.',
    'reasonForFloor', 'Ordinary household laundry rhythm calibrated through the Laundry world kernel.',
    'metadata', jsonb_strip_nulls(jsonb_build_object(
      'worldKernelKey', 'household.laundry',
      'worldKernelVersion', v_kernel_version,
      'source', 'household_laundry_calibration_v1',
      'selectedModelKey', v_model_key,
      'semanticCadence', true,
      'clockWindowEstablished', false
    ))
  ));

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'household_laundry_calibration_v1',
    'selectedModelKey', v_model_key,
    'instance', jsonb_build_object(
      'id', v_instance.id,
      'state', v_instance.state,
      'configuration', v_instance.configuration,
      'calibratedAt', v_instance.calibrated_at
    ),
    'rhythm', v_rhythm_result,
    'claimsCreated', jsonb_build_object(
      'washerOwned', false,
      'dryerOwned', false,
      'childExists', false,
      'sportsUniformExists', false
    )
  );
end;
$$;

revoke all on function atlas.personal_laundry_kernel_self_api_v1() from public, anon, authenticated;
revoke all on function atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb) from public, anon, authenticated;
revoke all on atlas.world_kernel_models from public, anon, authenticated;

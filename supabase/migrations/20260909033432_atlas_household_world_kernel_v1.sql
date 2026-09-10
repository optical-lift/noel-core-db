-- Atlas Personal Reality Kernel foundation.
-- Generic world structure is source-controlled and distinct from household-specific truth.
-- First admitted kernel: household.laundry v1.

create table if not exists atlas.world_kernel_definitions (
  kernel_key text not null,
  version integer not null check (version > 0),
  scope_kind text not null check (scope_kind in ('person','household')),
  title text not null,
  definition jsonb not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (kernel_key, version)
);

comment on table atlas.world_kernel_definitions is
  'Source-controlled generic world structure. A definition may describe ordinary reality without asserting that any household-specific detail is true.';

create table if not exists atlas.household_kernel_instances (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  kernel_key text not null,
  kernel_version integer not null,
  state text not null default 'calibrating' check (state in ('calibrating','active','retired')),
  configuration jsonb not null default '{}'::jsonb,
  calibrated_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (household_id, kernel_key),
  foreign key (kernel_key, kernel_version)
    references atlas.world_kernel_definitions(kernel_key, version)
);

comment on table atlas.household_kernel_instances is
  'Household-specific calibration of a generic world kernel. Existence of a world definition does not itself populate configuration or establish household-specific facts.';

alter table atlas.world_kernel_definitions enable row level security;
alter table atlas.household_kernel_instances enable row level security;
revoke all on atlas.world_kernel_definitions from public, anon, authenticated;
revoke all on atlas.household_kernel_instances from public, anon, authenticated;

insert into atlas.world_kernel_definitions (
  kernel_key, version, scope_kind, title, definition, active
) values (
  'household.laundry',
  1,
  'household',
  'Laundry',
  jsonb_build_object(
    'contractVersion', 'household_laundry_world_kernel_v1',
    'ordinary', true,
    'topology', jsonb_build_array(
      'worn_or_dirty',
      'collection',
      'washing',
      'drying',
      'readying',
      'return_to_use'
    ),
    'dependencies', jsonb_build_array(
      'people',
      'collection_place',
      'washing_method',
      'drying_method',
      'cleaning_consumable',
      'storage_place',
      'special_garment_turnaround',
      'equipment_maintenance',
      'replenishment',
      'backlog_pressure'
    ),
    'nonClaims', jsonb_build_array(
      'washer_owned',
      'dryer_owned',
      'folding_required',
      'children_present',
      'sports_uniform_present',
      'specific_cadence',
      'specific_consumable'
    )
  ),
  true
)
on conflict (kernel_key, version) do update set
  scope_kind = excluded.scope_kind,
  title = excluded.title,
  definition = excluded.definition,
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

  v_location := nullif(trim(p_input->>'laundryLocation'), '');
  v_pattern := nullif(trim(p_input->>'usualPattern'), '');
  v_notes := nullif(trim(p_input->>'notes'), '');
  v_expected := coalesce(nullif(p_input->>'expectedMinutes','')::integer, 45);

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
  from jsonb_array_elements_text(coalesce(p_input->'specialTurnaround', '[]'::jsonb)) t(x);

  insert into atlas.household_kernel_instances (
    household_id, kernel_key, kernel_version, state, configuration, calibrated_at, metadata
  ) values (
    v_household_id,
    'household.laundry',
    v_kernel_version,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'laundryLocation', v_location,
      'usualPattern', v_pattern,
      'specialTurnaround', to_jsonb(v_special),
      'notes', v_notes,
      'expectedMinutes', v_expected
    )),
    now(),
    jsonb_build_object(
      'source', 'principal_calibration',
      'calibratedBy', auth.uid(),
      'calibrationContract', 'household_laundry_calibration_v1'
    )
  )
  on conflict (household_id, kernel_key) do update set
    kernel_version = excluded.kernel_version,
    state = 'active',
    configuration = atlas.household_kernel_instances.configuration || excluded.configuration,
    calibrated_at = now(),
    metadata = atlas.household_kernel_instances.metadata || excluded.metadata,
    updated_at = now()
  returning * into v_instance;

  if v_pattern is not null then
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
      'metadata', jsonb_build_object(
        'worldKernelKey', 'household.laundry',
        'worldKernelVersion', v_kernel_version,
        'source', 'household_laundry_calibration_v1',
        'semanticCadence', true,
        'clockWindowEstablished', false
      )
    ));
  end if;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'household_laundry_calibration_v1',
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

create or replace function public.personal_laundry_kernel_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select atlas.personal_laundry_kernel_self_api_v1();
$$;

create or replace function public.calibrate_personal_laundry_kernel_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.calibrate_personal_laundry_kernel_self_api_v1(p_input);
$$;

revoke all on function atlas.personal_laundry_kernel_self_api_v1() from public, anon, authenticated;
revoke all on function atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb) from public, anon, authenticated;
revoke all on function public.personal_laundry_kernel_self_api_v1() from public, anon;
revoke all on function public.calibrate_personal_laundry_kernel_self_api_v1(jsonb) from public, anon;

grant execute on function public.personal_laundry_kernel_self_api_v1() to authenticated, service_role;
grant execute on function public.calibrate_personal_laundry_kernel_self_api_v1(jsonb) to authenticated, service_role;

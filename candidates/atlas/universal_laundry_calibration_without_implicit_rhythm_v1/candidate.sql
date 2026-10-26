BEGIN;
-- Atlas V1 Laundry calibration remains signed, Household-scoped and config-only.
-- No implicit recurring Rhythm, Work, assignment, Clock right or deletion.
-- Reviewed source candidate; do not release until schema-clone + signed proofs.
CREATE OR REPLACE FUNCTION atlas.calibrate_personal_laundry_kernel_self_api_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
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

  -- Calibration records arrangement only. Establishing a Rhythm is a distinct
  -- explicitly authorized operation; preserve any pre-existing Rhythm unchanged.


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
    'rhythm', null,
    'claimsCreated', jsonb_build_object(
      'washerOwned', false,
      'dryerOwned', false,
      'childExists', false,
      'sportsUniformExists', false
    )
  );
end;
$function$;
COMMIT;

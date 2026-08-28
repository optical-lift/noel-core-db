-- A governed AFTER INSERT trigger may migrate a just-created task back to its
-- planned occurrence and delete the redundant task row before later AFTER triggers run.
-- Capacity profiling must not create an FK child for a carrier that no longer exists.

create or replace function atlas.refresh_task_capacity_profile_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_default record;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  if new.farm_id is null then return new; end if;

  -- AFTER triggers on atlas.tasks are ordered independently. Serial-release custody
  -- may have already migrated this carrier back to planned_work_occurrences and
  -- removed the redundant task row. In that case there is no task to profile.
  if not exists(select 1 from atlas.tasks t where t.id=new.id) then
    return new;
  end if;

  select * into v_default from atlas.task_capacity_default_v1(new);

  insert into atlas.task_capacity_profiles (
    task_id, farm_id, expected_active_minutes, physical_load, base_obligation_class,
    micro_round_key, estimate_source, estimate_confidence,
    recovery_origin_due_date, recovery_started_on, metadata
  ) values (
    new.id, new.farm_id, v_default.expected_active_minutes, v_default.physical_load,
    v_default.base_obligation_class, v_default.micro_round_key,
    v_default.estimate_source, v_default.estimate_confidence,
    case when new.status in ('open','blocked') and new.due_date < v_today then new.due_date end,
    case when new.status in ('open','blocked') and new.due_date < v_today then new.due_date + 1 end,
    jsonb_build_object('generatedBy','refresh_task_capacity_profile_v1')
  )
  on conflict (task_id) do update
  set farm_id = excluded.farm_id,
      expected_active_minutes = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.expected_active_minutes else excluded.expected_active_minutes end,
      physical_load = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.physical_load else excluded.physical_load end,
      base_obligation_class = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.base_obligation_class else excluded.base_obligation_class end,
      micro_round_key = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.micro_round_key else excluded.micro_round_key end,
      estimate_source = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.estimate_source else excluded.estimate_source end,
      estimate_confidence = case when atlas.task_capacity_profiles.owner_locked
        then atlas.task_capacity_profiles.estimate_confidence else excluded.estimate_confidence end,
      recovery_origin_due_date = coalesce(
        atlas.task_capacity_profiles.recovery_origin_due_date,
        excluded.recovery_origin_due_date
      ),
      recovery_started_on = coalesce(
        atlas.task_capacity_profiles.recovery_started_on,
        excluded.recovery_started_on
      ),
      metadata = atlas.task_capacity_profiles.metadata || jsonb_build_object('refreshedAt',now()),
      updated_at = now();

  return new;
end;
$function$;

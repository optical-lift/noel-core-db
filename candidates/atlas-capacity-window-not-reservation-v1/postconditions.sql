-- Structural and behavioral proof runs only in a disposable production-schema clone.
do $structure$
declare
  v_source text;
begin
  select pg_get_viewdef('atlas.principal_capacity_blocks_v1'::regclass,true) into v_source;
  if v_source is null
    or position('atlas_household_five_zone_attention' in v_source)=0
    or position('executionGenerated' in v_source)=0
    or position('from atlas.household_events' in lower(v_source))=0
    or position('from atlas.principal_capacity_blocks' in lower(v_source))=0 then
    raise exception 'Capacity reservation view is not preserving owned source boundaries';
  end if;
  if not coalesce((
      select 'security_invoker=true'=any(c.reloptions)
      from pg_class c where c.oid='atlas.principal_capacity_blocks_v1'::regclass
    ),false)
    or has_table_privilege('anon','atlas.principal_capacity_blocks_v1','SELECT') then
    raise exception 'Capacity view invoker/anonymous-access boundary changed';
  end if;
end
$structure$;

do $behavior$
declare
  v_user uuid := '61000000-0000-4000-8000-000000000001';
  v_principal uuid;
  v_household uuid;
  v_today date := (statement_timestamp() at time zone 'America/Chicago')::date;
  v_prior jsonb;
  v_after_event jsonb;
  v_after_block jsonb;
  v_event uuid;
  v_block uuid;
  v_zones integer;
begin
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',
   jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);

  select p.id,p.active_household_id into strict v_principal,v_household
  from atlas.principals p where p.user_id=v_user;
  if v_household is null then raise exception 'Synthetic current Household unavailable'; end if;
  select count(*) into v_zones from atlas.household_rhythms r
  where r.household_id=v_household and r.active
    and r.metadata @> '{"policyKey":"atlas_household_five_zone_attention","releaseKind":"protected_attention","executionGenerated":false}'::jsonb;
  if v_zones<>5 then
    raise exception 'Actual bootstrap did not establish exactly five protected attention rhythms; got %',v_zones;
  end if;
  if exists(
    select 1 from atlas.principal_capacity_blocks_v1 b
    join atlas.household_rhythms r on b.source_id=r.id
    where b.principal_id=v_principal and b.source_type='household_rhythm'
      and r.household_id=v_household
      and r.metadata->>'policyKey'='atlas_household_five_zone_attention'
  ) then
    raise exception 'Non-executing five-zone attention was still treated as a time reservation';
  end if;

  v_prior:=atlas.principal_capacity_day_state_v1(v_principal,v_today);
  if (v_prior->>'capacityKnown')::boolean is distinct from true
    or (v_prior->>'blockedMinutes')::integer<>0
    or (v_prior->>'availableElapsedMinutes')::integer<>600
    or (v_prior->>'discretionaryCapacityMinutes')::integer<>120 then
    raise exception 'Five-zone attention still consumes full-day capacity: %',v_prior;
  end if;

  insert into atlas.household_events(
    household_id,stable_key,title,event_kind,starts_at,ends_at,
    fixed,blocks_capacity,expected_minutes,protection_level,
    floor_class,interruptibility,principal_required,source
  ) values (
    v_household,'ci-real-one-hour-event','Synthetic actual fixed commitment','family_commitment',
    (v_today::timestamp+time '09:00') at time zone 'America/Chicago',
    (v_today::timestamp+time '10:00') at time zone 'America/Chicago',
    true,true,60,'protected',3,'interruptible',true,'isolated_clone_fixture'
  ) returning id into v_event;
  v_after_event:=atlas.principal_capacity_day_state_v1(v_principal,v_today);
  if (v_after_event->>'blockedMinutes')::integer<>60
    or (v_after_event->>'availableElapsedMinutes')::integer<>540
    or not exists(
      select 1 from atlas.principal_capacity_blocks_v1 b
      where b.principal_id=v_principal and b.source_id=v_event and b.source_type='household_event'
    ) then
    raise exception 'Actual fixed Household event lost its true interval reservation: %',v_after_event;
  end if;

  insert into atlas.principal_capacity_blocks(
    principal_id,title,block_kind,starts_at,ends_at,blocks_capacity,
    floor_class,protection_level,reason_for_floor
  ) values (
    v_principal,'Synthetic personal time block','protected_time',
    (v_today::timestamp+time '11:00') at time zone 'America/Chicago',
    (v_today::timestamp+time '12:00') at time zone 'America/Chicago',
    true,3,'protected','Synthetic real one-hour unavailable time'
  ) returning id into v_block;
  v_after_block:=atlas.principal_capacity_day_state_v1(v_principal,v_today);
  if (v_after_block->>'blockedMinutes')::integer<>120
    or (v_after_block->>'availableElapsedMinutes')::integer<>480
    or not exists(
      select 1 from atlas.principal_capacity_blocks_v1 b
      where b.principal_id=v_principal and b.source_id=v_block and b.source_type='principal_capacity_block'
    ) then
    raise exception 'Personal interval block lost true reservation behavior: %',v_after_block;
  end if;
  raise notice 'Capacity distinction proved: five-zone protected attention retained, zero ghost time blocked; real fixed event and direct block each reserve sixty minutes.';
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
end
$behavior$;

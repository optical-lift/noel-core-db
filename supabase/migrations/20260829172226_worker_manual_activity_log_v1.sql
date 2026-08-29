alter table atlas.field_logs
  add column if not exists retracted_at timestamptz,
  add column if not exists retracted_by_user_id uuid;

create index if not exists field_logs_worker_manual_day_idx
  on atlas.field_logs (farm_id, actor_membership_id, log_date, created_at)
  where source = 'worker_manual_log' and retracted_at is null;

create or replace function atlas.emit_field_log_workflow_event_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_action text;
begin
  -- A worker manual log is raw lived-day evidence, not an operational workflow event.
  -- It is read through the dedicated activity-log projection and must not acquire
  -- task/object/crop consequence semantics merely because it lives in field_logs.
  if new.source = 'worker_manual_log' then
    return new;
  end if;

  perform atlas.emit_workflow_event_v1(
    new.farm_id,
    'field_log',
    new.id,
    coalesce(nullif(new.idempotency_key, ''), new.id::text),
    'logged',
    new.log_date,
    'field-log:' || new.id::text || ':logged',
    jsonb_build_object(
      'field_log_id', new.id,
      'action_types', to_jsonb(coalesce(new.action_types, array[]::text[])),
      'source', new.source,
      'metadata', new.metadata
    )
  );

  foreach v_action in array coalesce(new.action_types, array[]::text[])
  loop
    if nullif(btrim(v_action), '') is not null then
      perform atlas.emit_workflow_event_v1(
        new.farm_id,
        'field_log',
        new.id,
        coalesce(nullif(new.idempotency_key, ''), new.id::text),
        'action:' || lower(btrim(v_action)),
        new.log_date,
        'field-log:' || new.id::text || ':action:' || md5(lower(btrim(v_action))),
        jsonb_build_object(
          'field_log_id', new.id,
          'action_type', lower(btrim(v_action)),
          'source', new.source,
          'metadata', new.metadata
        )
      );
    end if;
  end loop;
  return new;
end;
$function$;

create or replace function atlas.record_worker_activity_log_v1(
  p_farm_id uuid,
  p_log_date date,
  p_summary_sentence text,
  p_idempotency_key text,
  p_clock_now_task_id uuid default null,
  p_clock_now_start_at timestamptz default null,
  p_clock_now_end_at timestamptz default null,
  p_clock_projection_revision text default null
)
returns table(
  field_log_id uuid,
  actor_membership_id uuid,
  logged_at timestamptz,
  replayed boolean
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_membership_id uuid;
  v_role text;
  v_worker_key text;
  v_log_id uuid;
  v_logged_at timestamptz;
  v_existing atlas.field_logs%rowtype;
  v_today date := (now() at time zone 'America/Chicago')::date;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  select fm.id, fm.role, fm.worker_key
  into v_membership_id, v_role, v_worker_key
  from atlas.farm_memberships fm
  where fm.user_id = v_user_id
    and fm.farm_id = p_farm_id
    and fm.active = true
  limit 1;

  if v_membership_id is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  -- The UI records "just did" work for the live farm day. Yesterday is accepted
  -- only so an idempotent mobile retry crossing midnight cannot destroy a log.
  if p_log_date is null or p_log_date < v_today - 1 or p_log_date > v_today then
    raise exception 'Worker activity must belong to the current farm day.' using errcode = '22023';
  end if;

  if nullif(btrim(p_summary_sentence), '') is null
     or char_length(btrim(p_summary_sentence)) < 3
     or char_length(btrim(p_summary_sentence)) > 500 then
    raise exception 'Worker activity must be 3 to 500 characters.' using errcode = '22023';
  end if;

  if nullif(btrim(p_idempotency_key), '') is null
     or char_length(btrim(p_idempotency_key)) < 8
     or char_length(btrim(p_idempotency_key)) > 120 then
    raise exception 'Worker activity idempotency key must be 8 to 120 characters.' using errcode = '22023';
  end if;

  if p_clock_now_task_id is not null and not exists (
    select 1 from atlas.tasks t where t.id = p_clock_now_task_id and t.farm_id = p_farm_id
  ) then
    raise exception 'Clock NOW task is outside the active farm.' using errcode = '42501';
  end if;

  select fl.* into v_existing
  from atlas.field_logs fl
  where fl.farm_id = p_farm_id
    and fl.idempotency_key = btrim(p_idempotency_key)
  limit 1;

  if v_existing.id is not null then
    if v_existing.source <> 'worker_manual_log' or v_existing.actor_membership_id <> v_membership_id then
      raise exception 'Idempotency key belongs to another record.' using errcode = '23505';
    end if;
    return query select v_existing.id, v_existing.actor_membership_id, v_existing.created_at, true;
    return;
  end if;

  insert into atlas.field_logs (
    farm_id,
    log_date,
    action_types,
    summary_sentence,
    note,
    source,
    metadata,
    actor_user_id,
    actor_membership_id,
    actor_role,
    idempotency_key
  ) values (
    p_farm_id,
    p_log_date,
    array[]::text[],
    btrim(p_summary_sentence),
    null,
    'worker_manual_log',
    jsonb_strip_nulls(jsonb_build_object(
      'evidence_only', true,
      'actor_worker_key', v_worker_key,
      'clock_now_task_id', p_clock_now_task_id,
      'clock_now_start_at', p_clock_now_start_at,
      'clock_now_end_at', p_clock_now_end_at,
      'clock_projection_revision', nullif(btrim(coalesce(p_clock_projection_revision, '')), '')
    )),
    v_user_id,
    v_membership_id,
    v_role,
    btrim(p_idempotency_key)
  )
  returning id, created_at into v_log_id, v_logged_at;

  return query select v_log_id, v_membership_id, v_logged_at, false;
end;
$function$;

create or replace function atlas.worker_activity_logs_for_day_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_day date := coalesce(p_day, (now() at time zone 'America/Chicago')::date);
  v_result jsonb;
begin
  if not exists (
    select 1
    from atlas.farm_memberships fm
    where fm.id = p_membership_id
      and fm.farm_id = p_farm_id
      and fm.active = true
      and (fm.user_id = auth.uid() or atlas.is_farm_manager_or_owner(p_farm_id))
  ) then
    raise exception 'An active readable farm membership is required.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'activityLogId', fl.id,
    'actorMembershipId', fl.actor_membership_id,
    'rawText', fl.summary_sentence,
    'loggedAt', fl.created_at,
    'activityDate', fl.log_date,
    'source', fl.source,
    'clockNowTaskId', nullif(fl.metadata ->> 'clock_now_task_id', ''),
    'clockNowStartAt', nullif(fl.metadata ->> 'clock_now_start_at', ''),
    'clockNowEndAt', nullif(fl.metadata ->> 'clock_now_end_at', ''),
    'clockProjectionRevision', nullif(fl.metadata ->> 'clock_projection_revision', '')
  ) order by fl.created_at, fl.id), '[]'::jsonb)
  into v_result
  from atlas.field_logs fl
  where fl.farm_id = p_farm_id
    and fl.actor_membership_id = p_membership_id
    and fl.log_date = v_day
    and fl.source = 'worker_manual_log'
    and fl.retracted_at is null;

  return v_result;
end;
$function$;

create or replace function atlas.retract_worker_activity_log_v1(p_field_log_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_log atlas.field_logs%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  select * into v_log from atlas.field_logs where id = p_field_log_id;
  if v_log.id is null or v_log.source <> 'worker_manual_log' then
    raise exception 'Worker activity log not found.' using errcode = 'P0002';
  end if;

  if v_log.actor_user_id <> v_user_id and not atlas.is_farm_manager_or_owner(v_log.farm_id) then
    raise exception 'Worker activity log is not editable by this member.' using errcode = '42501';
  end if;

  if v_log.retracted_at is null then
    update atlas.field_logs
    set retracted_at = now(), retracted_by_user_id = v_user_id, updated_at = now()
    where id = p_field_log_id;
  end if;

  return true;
end;
$function$;

revoke all on function atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) from public;
revoke all on function atlas.worker_activity_logs_for_day_v1(uuid,uuid,date) from public;
revoke all on function atlas.retract_worker_activity_log_v1(uuid) from public;
grant execute on function atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function atlas.worker_activity_logs_for_day_v1(uuid,uuid,date) to authenticated;
grant execute on function atlas.retract_worker_activity_log_v1(uuid) to authenticated;
-- UNI-OPS-01 P3: HELD legacy independent evaluation, NOT an issuer.
-- The previously admitted Work may become ELIGIBLE after a dependency
-- deadline or source Event, but even a later clock/event callback may not
-- bypass a freshly authorized Rulebook, recipient acceptance and Work plan.
-- These are exact current owner-source snapshots, replacements ONLY for
-- automatic legacy issue/schedule effects. Run no production SQL.
BEGIN;
DO $live_source_gate$
DECLARE v_name text; v_expected text; v_actual text;
BEGIN
 FOR v_name,v_expected IN SELECT * FROM (VALUES
  ('advance_task_dependency_clocks_v1','eedb5dee063b8fab613d22564b5f4326'),
  ('apply_workflow_event_v1','883c522e765bb3039511f172ccb1f69a')
 ) AS x(name,checksum)
 LOOP
  SELECT md5(pg_catalog.pg_get_functiondef(p.oid)) INTO v_actual
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname=v_name;
  IF v_actual IS DISTINCT FROM v_expected
  THEN RAISE EXCEPTION '6A source owner drift on %',v_name
    USING ERRCODE='42501'; END IF;
 END LOOP;
END;
$live_source_gate$;

-- Live source MD5 prior to 6A correction: eedb5dee063b8fab613d22564b5f4326; one delayed release site (and one legacy target reschedule for workflow events) held.
CREATE OR REPLACE FUNCTION atlas.advance_task_dependency_clocks_v1(p_as_of timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 100), 500));
  v_clock atlas.task_dependency_clocks%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_task atlas.tasks%rowtype;
  v_timezone text;
  v_user_id uuid;
  v_outbox_id uuid;
  v_notifications_enabled boolean;
  v_category_enabled boolean;
  v_released integer := 0;
  v_waiting_capacity integer := 0;
  v_pending_independent_issuance integer := 0;
  v_initial_notifications integer := 0;
  v_followup_notifications integer := 0;
begin
  for v_clock in
    select clock.*
    from atlas.task_dependency_clocks clock
    where clock.state in ('counting','ready')
      and clock.ready_at is not null
      and clock.ready_at <= p_as_of
    order by clock.ready_at, clock.id
    limit v_limit
    for update skip locked
  loop
    select occurrence.*
    into v_occurrence
    from atlas.planned_work_occurrences occurrence
    where occurrence.id = v_clock.downstream_occurrence_id
    for update;

    if v_occurrence.id is null or v_occurrence.state in ('completed','cancelled') then
      update atlas.task_dependency_clocks
      set state = 'cancelled',
          metadata = metadata || jsonb_build_object(
            'cancelled_reason', 'downstream_occurrence_closed',
            'cancelled_at', p_as_of
          ),
          updated_at = p_as_of
      where id = v_clock.id;
      continue;
    end if;

    if v_occurrence.gate_satisfied_at is null then
      update atlas.planned_work_occurrences
      set state = case when state = 'failed' then 'eligible' else state end,
          gate_satisfied_at = v_clock.ready_at,
          metadata = metadata || jsonb_build_object(
            'dependency_clock_id', v_clock.id,
            'dependency_clock_state', 'ready',
            'dependency_source_task_id', v_clock.source_task_id,
            'dependency_ready_at', v_clock.ready_at
          ),
          updated_at = p_as_of
      where id = v_occurrence.id;
    end if;

    update atlas.task_dependency_clocks
    set state = 'ready', updated_at = p_as_of
    where id = v_clock.id and state = 'counting';

    select coalesce(settings.timezone_name, 'America/Chicago')
    into v_timezone
    from atlas.farm_task_release_settings settings
    where settings.farm_id = v_clock.farm_id;
    v_timezone := coalesce(v_timezone, 'America/Chicago');

    NULL; -- 6A: source eligibility may be recorded, but no Work or Clock is released by this event/clock.

    select occurrence.*
    into v_occurrence
    from atlas.planned_work_occurrences occurrence
    where occurrence.id = v_clock.downstream_occurrence_id;

    if v_occurrence.released_task_id is null then
      v_pending_independent_issuance := v_pending_independent_issuance + 1;
      continue;
    end if;

    select task.*
    into v_task
    from atlas.tasks task
    where task.id = v_occurrence.released_task_id;

    update atlas.task_dependency_clocks
    set state = 'released',
        downstream_task_id = v_occurrence.released_task_id,
        released_at = coalesce(v_occurrence.released_at, p_as_of),
        metadata = metadata || jsonb_build_object(
          'released_task_id', v_occurrence.released_task_id,
          'released_at', coalesce(v_occurrence.released_at, p_as_of)
        ),
        updated_at = p_as_of
    where id = v_clock.id;

    update atlas.planned_work_occurrences
    set metadata = metadata || jsonb_build_object(
      'dependency_clock_state', 'released',
      'dependency_released_task_id', v_occurrence.released_task_id
    ),
    updated_at = p_as_of
    where id = v_occurrence.id;

    v_released := v_released + 1;

    v_user_id := coalesce(
      v_task.assigned_user_id,
      (
        select membership.user_id
        from atlas.farm_memberships membership
        where membership.id = v_task.assigned_membership_id
          and membership.active = true
      )
    );

    if v_user_id is not null
      and coalesce((v_clock.notification_policy ->> 'notify_when_ready')::boolean, true)
    then
      select coalesce(preference.enabled, true),
             coalesce((preference.categories ->> 'dependency_ready')::boolean, true)
      into v_notifications_enabled, v_category_enabled
      from (select 1) seed
      left join atlas.notification_preferences preference
        on preference.user_id = v_user_id
       and preference.farm_id = v_clock.farm_id;

      if v_notifications_enabled and v_category_enabled then
        v_outbox_id := atlas.enqueue_direct_push_v1(
          v_clock.farm_id,
          v_user_id,
          'dependency_ready',
          coalesce(nullif(v_clock.notification_policy ->> 'ready_title', ''), v_task.title || ' is ready'),
          coalesce(nullif(v_clock.notification_policy ->> 'ready_body', ''), v_task.title || ' is ready to begin.'),
          '/task-focus/' || v_task.id::text || '?returnTo=%2Fwork%2Ftoday',
          'dependency-clock:' || v_clock.id::text || ':ready',
          coalesce(nullif(v_clock.notification_policy ->> 'importance', ''), 'normal'),
          atlas.notification_next_available_at_v1(v_user_id, v_clock.farm_id, p_as_of),
          jsonb_build_object(
            'dependencyClockId', v_clock.id,
            'sourceTaskId', v_clock.source_task_id,
            'taskId', v_task.id,
            'readyAt', v_clock.ready_at,
            'kind', 'dependency_ready'
          )
        );

        if v_outbox_id is not null then
          update atlas.task_dependency_clocks
          set initial_notified_at = p_as_of, updated_at = p_as_of
          where id = v_clock.id;
          v_initial_notifications := v_initial_notifications + 1;
        end if;
      end if;
    end if;
  end loop;

  for v_clock in
    select clock.*
    from atlas.task_dependency_clocks clock
    join atlas.tasks task on task.id = clock.downstream_task_id
    where clock.state = 'released'
      and clock.initial_notified_at is not null
      and clock.followup_notified_at is null
      and task.status in ('open','blocked')
      and coalesce(clock.notification_policy ->> 'followup_after_minutes', '') ~ '^\d+$'
      and p_as_of >= clock.initial_notified_at
        + make_interval(mins => (clock.notification_policy ->> 'followup_after_minutes')::integer)
      and not exists (
        select 1
        from atlas.task_transitions transition
        where transition.task_id = task.id
          and transition.created_at > coalesce(clock.released_at, clock.initial_notified_at)
      )
    order by clock.initial_notified_at, clock.id
    limit v_limit
    for update of clock skip locked
  loop
    select task.* into v_task from atlas.tasks task where task.id = v_clock.downstream_task_id;
    v_user_id := coalesce(
      v_task.assigned_user_id,
      (
        select membership.user_id
        from atlas.farm_memberships membership
        where membership.id = v_task.assigned_membership_id
          and membership.active = true
      )
    );

    if v_user_id is null then
      continue;
    end if;

    select coalesce(preference.enabled, true),
           coalesce((preference.categories ->> 'dependency_ready')::boolean, true)
    into v_notifications_enabled, v_category_enabled
    from (select 1) seed
    left join atlas.notification_preferences preference
      on preference.user_id = v_user_id
     and preference.farm_id = v_clock.farm_id;

    if not v_notifications_enabled or not v_category_enabled then
      continue;
    end if;

    v_outbox_id := atlas.enqueue_direct_push_v1(
      v_clock.farm_id,
      v_user_id,
      'dependency_ready',
      coalesce(nullif(v_clock.notification_policy ->> 'followup_title', ''), 'Still waiting: ' || v_task.title),
      coalesce(nullif(v_clock.notification_policy ->> 'followup_body', ''), v_task.title || ' is ready and has not been started.'),
      '/task-focus/' || v_task.id::text || '?returnTo=%2Fwork%2Ftoday',
      'dependency-clock:' || v_clock.id::text || ':followup',
      coalesce(nullif(v_clock.notification_policy ->> 'importance', ''), 'normal'),
      atlas.notification_next_available_at_v1(v_user_id, v_clock.farm_id, p_as_of),
      jsonb_build_object(
        'dependencyClockId', v_clock.id,
        'sourceTaskId', v_clock.source_task_id,
        'taskId', v_task.id,
        'readyAt', v_clock.ready_at,
        'kind', 'dependency_ready_followup'
      )
    );

    if v_outbox_id is not null then
      update atlas.task_dependency_clocks
      set followup_notified_at = p_as_of, updated_at = p_as_of
      where id = v_clock.id;
      v_followup_notifications := v_followup_notifications + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'asOf', p_as_of,
    'released', v_released,
    'waitingForCapacity', v_waiting_capacity,
    'awaitingIndependentIssuance',v_pending_independent_issuance,
    'successorAutoReleased',false,
    'initialNotifications', v_initial_notifications,
    'followupNotifications', v_followup_notifications
  );
end;
$function$

-- Live source MD5 prior to 6A correction: 883c522e765bb3039511f172ccb1f69a; one delayed release site (and one legacy target reschedule for workflow events) held.
CREATE OR REPLACE FUNCTION atlas.apply_workflow_event_v1(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_event atlas.workflow_events%rowtype; v_handoff atlas.workflow_handoffs%rowtype; v_occurrence atlas.planned_work_occurrences%rowtype; v_due_date date; v_applied integer:=0; v_skipped integer:=0;
begin
 select * into v_event from atlas.workflow_events where id=p_event_id; if v_event.id is null then raise exception 'Workflow event was not found.' using errcode='P0002'; end if;
 for v_handoff in select h.* from atlas.workflow_handoffs h where h.farm_id=v_event.farm_id and h.active and h.satisfied_at is null and h.source_kind=v_event.source_kind and h.source_event=v_event.source_event and (h.source_id is null or h.source_id=v_event.source_id) and (h.source_key is null or h.source_key=v_event.source_key) and (h.source_filter='{}'::jsonb or v_event.payload@>h.source_filter) order by h.created_at,h.id for update skip locked
 loop
  v_due_date:=coalesce(v_handoff.target_date,v_event.event_date+v_handoff.delay_days,v_event.event_date);
  if v_handoff.target_occurrence_id is not null then select * into v_occurrence from atlas.planned_work_occurrences where id=v_handoff.target_occurrence_id for update; if v_occurrence.id is null or v_occurrence.state in ('completed','cancelled') then v_skipped:=v_skipped+1; continue; end if; update atlas.planned_work_occurrences set planned_due_date=coalesce(planned_due_date,v_due_date),gate_satisfied_at=now(),state='eligible',metadata=metadata||jsonb_build_object('workflow_event_id',v_event.id,'workflow_handoff_id',v_handoff.id,'workflow_gate_state','ready'),updated_at=now() where id=v_occurrence.id; NULL; -- 6A: source eligibility may be recorded, but no Work or Clock is released by this event/clock. update atlas.workflow_handoffs set target_task_id=(select released_task_id from atlas.planned_work_occurrences where id=v_occurrence.id),satisfied_at=now(),satisfied_by_event_id=v_event.id,metadata=metadata||jsonb_build_object('satisfaction_state','source_satisfied_awaiting_independent_issuance','successorAutoReleased',false,'resolved_due_date',v_due_date),updated_at=now() where id=v_handoff.id; v_applied:=v_applied+1;
  elsif v_handoff.target_task_id is not null then update atlas.workflow_handoffs set satisfied_at=now(),satisfied_by_event_id=v_event.id,metadata=metadata||jsonb_build_object('satisfaction_state','legacy_target_waiting_independent_schedule','successorAutoScheduled',false,'resolved_due_date',v_due_date),updated_at=now() where id=v_handoff.id; NULL; -- 6A: a source event may satisfy a prerequisite, but never automatically reschedules the downstream existing task. v_applied:=v_applied+1;
  else v_skipped:=v_skipped+1; end if;
 end loop; return jsonb_build_object('eventId',v_event.id,'applied',v_applied,'successorAutoReleased',false,'skipped',v_skipped);
end;$function$
COMMIT;

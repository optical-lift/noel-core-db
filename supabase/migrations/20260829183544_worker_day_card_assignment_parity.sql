create or replace function atlas.worker_day_operational_task_cards_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_service_date date,
  p_task_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_target atlas.farm_memberships%rowtype;
  v_ids uuid[] := array[]::uuid[];
  v_move_context jsonb := '{}'::jsonb;
  v_cards jsonb := '[]'::jsonb;
  v_is_management boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_service_date is null then
    raise exception 'Service date required.' using errcode='22023';
  end if;

  select * into v_target
  from atlas.farm_memberships membership
  where membership.id = p_membership_id
    and membership.farm_id = p_farm_id
    and membership.active = true;

  if v_target.id is null then
    raise exception 'Active target membership required.' using errcode='42501';
  end if;

  v_is_management := atlas.is_farm_manager_or_owner(p_farm_id);

  if v_target.user_id is distinct from auth.uid()
     and not v_is_management then
    raise exception 'Only farm management may read another member''s operational Day cards.' using errcode='42501';
  end if;

  select coalesce(array_agg(distinct candidate.task_id), array[]::uuid[])
  into v_ids
  from (
    select unnest(coalesce(p_task_ids, array[]::uuid[])) as task_id
    union all
    select task.id
    from atlas.tasks task
    where task.farm_id = p_farm_id
      and task.parent_task_id is null
      and task.status = 'done'
      and task.completed_at is not null
      and coalesce(
        (
          select transition.target_date
          from atlas.task_transitions transition
          where transition.task_id = task.id
            and transition.next_status = 'done'
            and transition.target_date is not null
          order by transition.created_at desc, transition.id desc
          limit 1
        ),
        (task.completed_at at time zone 'America/Chicago')::date
      ) = p_service_date
      and (
        task.assigned_membership_id = p_membership_id
        or task.assigned_user_id = v_target.user_id
        or task.metadata ->> 'executor_membership_id' = p_membership_id::text
        or (
          nullif(lower(btrim(v_target.worker_key)), '') is not null
          and lower(coalesce(
            nullif(task.metadata ->> 'executor_worker_key',''),
            nullif(task.metadata ->> 'assignee_key',''),
            nullif(task.metadata ->> 'assigned_to',''),
            nullif(task.metadata ->> 'work_route','')
          )) = nullif(lower(btrim(v_target.worker_key)), '')
        )
      )
  ) candidate;

  if coalesce(array_length(v_ids, 1), 0) = 0 then
    return '[]'::jsonb;
  end if;

  if v_is_management then
    v_move_context := coalesce(atlas.task_move_context_batch_v1(v_ids), '{}'::jsonb);
  end if;

  select coalesce(jsonb_agg(card order by card.ordinal, card.created_at), '[]'::jsonb)
  into v_cards
  from (
    select
      coalesce(array_position(p_task_ids, task.id), 2147483647) as ordinal,
      task.created_at,
      jsonb_build_object(
        'farm_key', farm.stable_key,
        'task_id', task.id,
        'title', task.title,
        'task_type', task.task_type,
        'status', task.status,
        'priority', task.priority,
        'due_date', task.due_date,
        'unlock_text', task.unlock_text,
        'blocker_text', task.blocker_text,
        'note', task.note,
        'generated_from', task.generated_from,
        'generated_from_id', task.generated_from_id,
        'action_key', task.action_key,
        'work_class', task.work_class,
        'operation_class', task.operation_class,
        'operation_class_source', task.operation_class_source,
        'parent_task_id', task.parent_task_id,
        'task_series_key', task.task_series_key,
        'engine_instance_key', task.engine_instance_key,
        'created_at', task.created_at,
        'updated_at', task.updated_at,
        'metadata', coalesce(task.metadata, '{}'::jsonb),
        'zone_id', zone.id,
        'zone_key', zone.stable_key,
        'zone_label', zone.label,
        'objects', coalesce(objects.items, '[]'::jsonb),
        'resource_requirements', '[]'::jsonb,
        'action_templates', '[]'::jsonb,
        'task_logs', '[]'::jsonb,
        'task_outcomes', coalesce(outcome.items, '[]'::jsonb),
        'task_transitions', coalesce(transition.items, '[]'::jsonb),
        'move_context', v_move_context -> task.id::text
      ) as card
    from atlas.tasks task
    join atlas.farms farm on farm.id = task.farm_id
    left join atlas.zones zone on zone.id = task.zone_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'object_id', growing.id,
        'object_key', growing.stable_key,
        'object_label', growing.label,
        'object_type', growing.object_type,
        'object_mode', growing.object_mode,
        'life_status', state.life_status,
        'weed_pressure', state.weed_pressure,
        'water_status', state.water_status,
        'last_touched_at', state.last_touched_at,
        'last_weeded_at', state.last_weeded_at,
        'last_watered_at', state.last_watered_at,
        'last_checked_at', state.last_checked_at,
        'decision_required', state.decision_required,
        'presentability', state.presentability,
        'state_metadata', state.metadata
      ) order by link.role, growing.label, growing.id) as items
      from atlas.task_objects link
      join atlas.growing_objects growing on growing.id = link.object_id
      left join atlas.object_state state on state.object_id = growing.id
      where link.task_id = task.id
    ) objects on true
    left join lateral (
      select jsonb_agg(item) as items
      from (
        select jsonb_build_object(
          'event_id', event.id,
          'outcome', event.outcome,
          'lane_key', event.lane_key,
          'work_key', event.work_key,
          'blocker_reason', event.blocker_reason,
          'note', event.note,
          'created_at', event.created_at
        ) as item
        from atlas.task_outcome_events event
        where event.task_id = task.id
        order by event.created_at desc, event.id desc
        limit 1
      ) latest
    ) outcome on true
    left join lateral (
      select jsonb_agg(item) as items
      from (
        select jsonb_build_object(
          'transition_id', event.id,
          'transition', event.transition,
          'previous_status', event.previous_status,
          'next_status', event.next_status,
          'previous_due_date', event.previous_due_date,
          'target_date', event.target_date,
          'action_key', event.action_key,
          'work_class', event.work_class,
          'note', event.note,
          'reason', event.reason,
          'field_log_id', event.field_log_id,
          'created_at', event.created_at
        ) as item
        from atlas.task_transitions event
        where event.task_id = task.id
        order by event.created_at desc, event.id desc
        limit 1
      ) latest
    ) transition on true
    where task.farm_id = p_farm_id
      and task.id = any(v_ids)
      and coalesce(task.visibility_scope,'') <> 'system_internal'
      and (
        task.status = 'done'
        or task.id = any(coalesce(p_task_ids, array[]::uuid[]))
      )
      and (
        task.assigned_membership_id = p_membership_id
        or task.assigned_user_id = v_target.user_id
        or task.metadata ->> 'executor_membership_id' = p_membership_id::text
        or (
          nullif(lower(btrim(v_target.worker_key)), '') is not null
          and lower(coalesce(
            nullif(task.metadata ->> 'executor_worker_key',''),
            nullif(task.metadata ->> 'assignee_key',''),
            nullif(task.metadata ->> 'assigned_to',''),
            nullif(task.metadata ->> 'work_route','')
          )) = nullif(lower(btrim(v_target.worker_key)), '')
        )
        or task.id in (
          select placement.task_id
          from atlas.worker_day_task_placements placement
          where placement.farm_id = p_farm_id
            and placement.membership_id = p_membership_id
            and placement.task_id = task.id
        )
      )
  ) card;

  return v_cards;
end;
$function$;
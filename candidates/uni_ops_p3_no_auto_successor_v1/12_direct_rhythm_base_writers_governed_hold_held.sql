-- HELD / 6A direct legacy Rhythm task writer closure for actually governed
-- U1A/U1B native rhythm State only. This is NOT a generic Clock shutdown.
-- Applies after source-approved P3 03 native Rulebook helper.
-- Doesn't mutate the old task, occurrence or original Work.
BEGIN;
DO $pin$
BEGIN
 IF pg_catalog.to_regprocedure('atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)') IS NULL THEN
  RAISE EXCEPTION 'Existing one-Rulebook native source guard required';
 END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='ensure_rhythm_task_v1_base') IS DISTINCT FROM '3de2d9dd8a0a843480b8a5ab8ef11488' THEN RAISE EXCEPTION 'Source drift ensure_rhythm_task_v1_base'; END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='ensure_rhythm_task_without_physical_gate_v1') IS DISTINCT FROM '6ebb993052cc226691d933d20a17a7e2' THEN RAISE EXCEPTION 'Source drift ensure_rhythm_task_without_physical_gate_v1'; END IF;
END;
$pin$;

-- Exact live ensure_rhythm_task_v1_base MD5 3de2d9dd8a0a843480b8a5ab8ef11488 before this scoped early hold.
CREATE OR REPLACE FUNCTION atlas.ensure_rhythm_task_v1_base(p_state_id uuid, p_target_state text, p_boundary_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_state atlas.rhythm_state%rowtype;
  v_rule atlas.rhythm_rules%rowtype;
  v_template jsonb;
  v_existing_task_id uuid;
  v_occurrence_id uuid;
  v_released_task_id uuid;
  v_zone_id uuid;
  v_object_id uuid;
  v_crop_cycle_id uuid;
  v_assigned_membership_id uuid;
  v_visibility text;
  v_task_payload jsonb;
  v_relation_payload jsonb := '{}'::jsonb;
  v_occurrence_key text;
  v_due_date date;
begin
  select * into v_state from atlas.rhythm_state where id = p_state_id for update;
  if v_state.id is null then
    raise exception 'Rhythm state not found.' using errcode = 'P0002';
  end if;

  IF atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(
    v_state.id
  ) THEN
    -- An old direct private caller is not an independent new-work issuer.
    -- Keep the existing Work/task untouched, and do not update an old
    -- occurrence's eligibility or create a new Task from due/failure Clock.
    RETURN pg_catalog.jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','governed_rhythm_needs_independent_accepted_first_work',
      'sourceRhythmStateId',v_state.id,
      'newWorkCreated',false,'legacyTaskCreated',false,
      'clockAdmitted',false,'historicalTaskOrOccurrenceMutated',false);
  END IF;

  select * into v_rule from atlas.rhythm_rules where id = v_state.rhythm_rule_id;

  v_template := case
    when p_target_state = 'due' then v_rule.failure_consequence -> 'dueTask'
    when p_target_state = 'fallen_out_of_rhythm' then
      coalesce(v_rule.failure_consequence -> 'failureTask', v_rule.failure_consequence -> 'dueTask')
    else null
  end;

  if v_template is null or jsonb_typeof(v_template) <> 'object'
     or nullif(btrim(v_template ->> 'title'), '') is null then
    return jsonb_build_object('taskId', null, 'occurrenceId', null, 'action', 'no_explicit_task_template');
  end if;

  if v_state.current_task_id is not null and exists (
    select 1 from atlas.tasks t
    where t.id = v_state.current_task_id and t.status in ('open','blocked')
  ) then
    return jsonb_build_object('taskId', v_state.current_task_id, 'occurrenceId', v_state.current_occurrence_id, 'action', 'kept_current');
  end if;

  select t.id into v_existing_task_id
  from atlas.tasks t
  where (
      t.farm_id = v_state.farm_id
      or (v_state.subject_kind = 'project' and exists (
        select 1 from atlas.project_task_links project_link
        where project_link.project_id = v_state.subject_id and project_link.task_id = t.id
      ))
    )
    and t.status in ('open','blocked')
    and (
      (t.generated_from = 'rhythm_clock' and t.generated_from_id = v_state.id)
      or t.metadata ->> 'rhythm_state_id' = v_state.id::text
      or (
        (v_template ? 'taskType' or v_template ? 'actionKey' or v_template ? 'workClass')
        and (not (v_template ? 'taskType') or t.task_type = v_template ->> 'taskType')
        and (not (v_template ? 'actionKey') or t.action_key = v_template ->> 'actionKey')
        and (not (v_template ? 'workClass') or t.work_class = v_template ->> 'workClass')
        and (
          v_state.subject_kind = 'farm'
          or (v_state.subject_kind = 'zone' and t.zone_id = v_state.subject_id)
          or (v_state.subject_kind = 'growing_object' and exists (
            select 1 from atlas.task_objects task_object
            where task_object.task_id = t.id and task_object.object_id = v_state.subject_id
          ))
          or (v_state.subject_kind = 'crop_cycle' and exists (
            select 1 from atlas.task_crop_cycles task_cycle
            where task_cycle.task_id = t.id and task_cycle.crop_cycle_id = v_state.subject_id
          ))
          or (v_state.subject_kind = 'project' and exists (
            select 1 from atlas.project_task_links project_link
            where project_link.project_id = v_state.subject_id and project_link.task_id = t.id
          ))
        )
      )
    )
  order by
    case when t.generated_from = 'rhythm_clock' and t.generated_from_id = v_state.id then 0 else 1 end,
    t.created_at,
    t.id
  limit 1;

  if v_existing_task_id is not null then
    update atlas.tasks
    set metadata = metadata || jsonb_build_object(
          'rhythm_state_id', v_state.id,
          'rhythm_binding_id', v_state.rhythm_binding_id,
          'rhythm_rule_id', v_state.rhythm_rule_id,
          'rhythm_key', v_state.rhythm_key,
          'adopted_by_clock_at', now()
        ),
        updated_at = now()
    where id = v_existing_task_id;

    update atlas.rhythm_state
    set current_task_id = v_existing_task_id,
        current_occurrence_id = (select planned_occurrence_id from atlas.tasks where id = v_existing_task_id),
        updated_at = now()
    where id = v_state.id;

    return jsonb_build_object(
      'taskId', v_existing_task_id,
      'occurrenceId', (select planned_occurrence_id from atlas.tasks where id = v_existing_task_id),
      'action', 'adopted_existing_explicit_work'
    );
  end if;

  if v_state.subject_kind = 'growing_object' then
    v_object_id := v_state.subject_id;
    select zone_id into v_zone_id from atlas.growing_objects where id = v_object_id;
    v_relation_payload := jsonb_build_object(
      'task_objects', jsonb_build_array(jsonb_build_object('object_id', v_object_id, 'role', 'target'))
    );
  elsif v_state.subject_kind = 'crop_cycle' then
    v_crop_cycle_id := v_state.subject_id;
    select object_id into v_object_id from atlas.crop_cycles where id = v_crop_cycle_id;
    select zone_id into v_zone_id from atlas.growing_objects where id = v_object_id;
    v_relation_payload := jsonb_build_object(
      'task_crop_cycles', jsonb_build_array(jsonb_build_object(
        'crop_cycle_id', v_crop_cycle_id,
        'role', 'affects',
        'confidence', 'confirmed',
        'source', 'rhythm_clock_v1'
      )),
      'task_objects', case when v_object_id is null then '[]'::jsonb else
        jsonb_build_array(jsonb_build_object('object_id', v_object_id, 'role', 'target')) end
    );
  elsif v_state.subject_kind = 'zone' then
    v_zone_id := v_state.subject_id;
  end if;

  if nullif(v_template ->> 'zoneId', '') is not null then
    v_zone_id := (v_template ->> 'zoneId')::uuid;
  end if;

  if nullif(v_template ->> 'assignedMembershipId', '') is not null then
    v_assigned_membership_id := (v_template ->> 'assignedMembershipId')::uuid;
  elsif nullif(v_rule.player_routing ->> 'assignedMembershipId', '') is not null then
    v_assigned_membership_id := (v_rule.player_routing ->> 'assignedMembershipId')::uuid;
  end if;

  v_visibility := coalesce(
    nullif(v_template ->> 'visibilityScope', ''),
    nullif(v_rule.player_routing ->> 'visibilityScope', ''),
    v_state.visibility_scope,
    'farm_shared'
  );
  if v_visibility not in ('owner','management','assigned_worker','farm_shared','project_shared','system_internal') then
    v_visibility := 'farm_shared';
  end if;

  v_due_date := (p_boundary_at at time zone 'America/Chicago')::date;
  v_occurrence_key := 'rhythm:' || v_state.id::text || ':' || p_target_state || ':' || extract(epoch from p_boundary_at)::bigint::text;

  v_task_payload := jsonb_strip_nulls(jsonb_build_object(
    'zone_id', v_zone_id,
    'task_type', coalesce(nullif(v_template ->> 'taskType', ''), 'general'),
    'priority', coalesce(nullif(v_template ->> 'priority', ''), case when p_target_state = 'fallen_out_of_rhythm' then 'high' else 'normal' end),
    'unlock_text', nullif(v_template ->> 'unlockText', ''),
    'generated_from', 'rhythm_clock',
    'generated_from_id', v_state.id,
    'note', nullif(v_template ->> 'note', ''),
    'action_key', nullif(v_template ->> 'actionKey', ''),
    'work_class', nullif(v_template ->> 'workClass', ''),
    'work_lane', nullif(v_template ->> 'workLane', ''),
    'task_series_key', 'rhythm:' || v_state.rhythm_key || ':' || v_state.subject_kind || ':' || v_state.subject_id::text,
    'engine_instance_key', 'rhythm:' || v_state.id::text,
    'visibility_scope', v_visibility,
    'assigned_membership_id', v_assigned_membership_id,
    'metadata', coalesce(v_template -> 'metadata', '{}'::jsonb) || jsonb_build_object(
      'rhythm_state_id', v_state.id,
      'rhythm_binding_id', v_state.rhythm_binding_id,
      'rhythm_rule_id', v_state.rhythm_rule_id,
      'rhythm_key', v_state.rhythm_key,
      'rhythm_target_state', p_target_state,
      'rhythm_boundary_at', p_boundary_at,
      'clock_version', 'rhythm_clock_v1'
    )
  ));

  v_occurrence_id := atlas.plan_work_occurrence_v1(
    p_farm_id => v_state.farm_id,
    p_definition_key => 'rhythm:' || v_state.rhythm_key || ':' || p_target_state,
    p_policy_key => 'rhythm:' || v_state.rhythm_key || ':' || p_target_state || ':immediate',
    p_occurrence_key => v_occurrence_key,
    p_title => v_template ->> 'title',
    p_task_type => coalesce(nullif(v_template ->> 'taskType', ''), 'general'),
    p_due_date => v_due_date,
    p_source_kind => 'rhythm_state',
    p_source_id => v_state.id,
    p_gate_type => 'immediate',
    p_horizon_days => 0,
    p_maximum_active_instances => 1,
    p_task_payload => v_task_payload,
    p_relation_payload => v_relation_payload,
    p_gate_config => jsonb_build_object('clockVersion', 'rhythm_clock_v1'),
    p_not_before_date => v_due_date,
    p_metadata => jsonb_build_object(
      'rhythm_state_id', v_state.id,
      'transition_state', p_target_state,
      'boundary_at', p_boundary_at
    )
  );

  if nullif(v_template ->> 'workLane', '') is not null then
    update atlas.planned_work_occurrences
    set work_lane = v_template ->> 'workLane',
        updated_at = now()
    where id = v_occurrence_id;
  end if;

  perform atlas.signal_work_occurrence_v1(
    v_occurrence_id,
    'rhythm_clock:' || p_target_state,
    jsonb_build_object('rhythm_state_id', v_state.id, 'boundary_at', p_boundary_at)
  );

  select released_task_id into v_released_task_id
  from atlas.planned_work_occurrences
  where id = v_occurrence_id;

  if v_state.subject_kind = 'project' and v_released_task_id is not null then
    insert into atlas.project_task_links (project_id, task_id, link_role, source, metadata)
    values (
      v_state.subject_id,
      v_released_task_id,
      'belongs_to',
      'rhythm_clock_v1',
      jsonb_build_object('rhythm_state_id', v_state.id)
    )
    on conflict (project_id, task_id) do update
      set source = excluded.source,
          metadata = atlas.project_task_links.metadata || excluded.metadata,
          updated_at = now();
  end if;

  update atlas.rhythm_state
  set current_task_id = v_released_task_id,
      current_occurrence_id = v_occurrence_id,
      updated_at = now()
  where id = v_state.id;

  return jsonb_build_object(
    'taskId', v_released_task_id,
    'occurrenceId', v_occurrence_id,
    'action', case when v_released_task_id is null then 'planned_awaiting_capacity' else 'released' end
  );
end;
$function$


-- Exact live ensure_rhythm_task_without_physical_gate_v1 MD5 6ebb993052cc226691d933d20a17a7e2 before this scoped early hold.
CREATE OR REPLACE FUNCTION atlas.ensure_rhythm_task_without_physical_gate_v1(p_state_id uuid, p_target_state text, p_boundary_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_state atlas.rhythm_state%rowtype;
  v_rule atlas.rhythm_rules%rowtype;
  v_template jsonb;
  v_task atlas.tasks%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_due_date date;
  v_release jsonb;
  v_released_task_id uuid;
  v_action text;
begin
  select * into v_state
  from atlas.rhythm_state
  where id = p_state_id
  for update;

  if v_state.id is null then
    raise exception 'Rhythm state not found.' using errcode = 'P0002';
  end if;

  IF atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(
    v_state.id
  ) THEN
    -- An old direct private caller is not an independent new-work issuer.
    -- Keep the existing Work/task untouched, and do not update an old
    -- occurrence's eligibility or create a new Task from due/failure Clock.
    RETURN pg_catalog.jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','governed_rhythm_needs_independent_accepted_first_work',
      'sourceRhythmStateId',v_state.id,
      'newWorkCreated',false,'legacyTaskCreated',false,
      'clockAdmitted',false,'historicalTaskOrOccurrenceMutated',false);
  END IF;


  select * into v_rule
  from atlas.rhythm_rules
  where id = v_state.rhythm_rule_id;

  v_template := case
    when p_target_state = 'due' then v_rule.failure_consequence -> 'dueTask'
    when p_target_state = 'fallen_out_of_rhythm' then
      coalesce(v_rule.failure_consequence -> 'failureTask', v_rule.failure_consequence -> 'dueTask')
    else null
  end;

  if v_template is null or jsonb_typeof(v_template) <> 'object'
     or nullif(btrim(v_template ->> 'title'), '') is null then
    return jsonb_build_object(
      'taskId', null,
      'occurrenceId', null,
      'action', 'no_explicit_task_template'
    );
  end if;

  v_due_date := (p_boundary_at at time zone 'America/Chicago')::date;

  if v_state.current_task_id is not null then
    select * into v_task
    from atlas.tasks
    where id = v_state.current_task_id
      and status in ('open', 'blocked')
    for update;
  end if;

  if v_task.id is not null then
    if p_target_state = 'fallen_out_of_rhythm' then
      update atlas.tasks
      set title = v_template ->> 'title',
          task_type = coalesce(nullif(v_template ->> 'taskType', ''), task_type),
          priority = coalesce(nullif(v_template ->> 'priority', ''), 'high'),
          due_date = least(coalesce(due_date, v_due_date), v_due_date),
          unlock_text = coalesce(nullif(v_template ->> 'unlockText', ''), unlock_text),
          note = coalesce(nullif(v_template ->> 'note', ''), note),
          action_key = coalesce(nullif(v_template ->> 'actionKey', ''), action_key),
          work_class = coalesce(nullif(v_template ->> 'workClass', ''), work_class),
          metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
            'rhythm_target_state', p_target_state,
            'rhythm_failure_escalated_at', p_boundary_at,
            'rhythm_task_identity_preserved', true,
            'clock_version', 'rhythm_clock_v1'
          ),
          updated_at = now()
      where id = v_task.id;

      if v_state.current_occurrence_id is not null then
        update atlas.planned_work_occurrences
        set title = v_template ->> 'title',
            planned_due_date = least(coalesce(planned_due_date, v_due_date), v_due_date),
            task_payload = coalesce(task_payload, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
              'task_type', nullif(v_template ->> 'taskType', ''),
              'priority', coalesce(nullif(v_template ->> 'priority', ''), 'high'),
              'unlock_text', nullif(v_template ->> 'unlockText', ''),
              'note', nullif(v_template ->> 'note', ''),
              'action_key', nullif(v_template ->> 'actionKey', ''),
              'work_class', nullif(v_template ->> 'workClass', ''),
              'metadata', coalesce(task_payload -> 'metadata', '{}'::jsonb) || jsonb_build_object(
                'rhythm_target_state', p_target_state,
                'rhythm_failure_escalated_at', p_boundary_at,
                'rhythm_task_identity_preserved', true
              )
            )),
            metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
              'rhythm_target_state', p_target_state,
              'rhythm_failure_escalated_at', p_boundary_at,
              'rhythm_task_identity_preserved', true
            ),
            updated_at = now()
        where id = v_state.current_occurrence_id;
      end if;

      v_action := 'escalated_current_task';
    else
      v_action := 'kept_current';
    end if;

    return jsonb_build_object(
      'taskId', v_task.id,
      'occurrenceId', v_state.current_occurrence_id,
      'action', v_action
    );
  end if;

  if v_state.current_occurrence_id is not null then
    select * into v_occurrence
    from atlas.planned_work_occurrences
    where id = v_state.current_occurrence_id
      and state in ('planned', 'eligible', 'failed', 'releasing')
      and released_task_id is null
    for update;
  end if;

  if v_occurrence.id is not null then
    update atlas.planned_work_occurrences
    set title = v_template ->> 'title',
        planned_due_date = least(coalesce(planned_due_date, v_due_date), v_due_date),
        task_payload = coalesce(task_payload, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
          'task_type', nullif(v_template ->> 'taskType', ''),
          'priority', coalesce(
            nullif(v_template ->> 'priority', ''),
            case when p_target_state = 'fallen_out_of_rhythm' then 'high' else 'normal' end
          ),
          'unlock_text', nullif(v_template ->> 'unlockText', ''),
          'note', nullif(v_template ->> 'note', ''),
          'action_key', nullif(v_template ->> 'actionKey', ''),
          'work_class', nullif(v_template ->> 'workClass', ''),
          'metadata', coalesce(task_payload -> 'metadata', '{}'::jsonb) || jsonb_build_object(
            'rhythm_target_state', p_target_state,
            'rhythm_boundary_at', p_boundary_at,
            'rhythm_task_identity_preserved', true,
            'clock_version', 'rhythm_clock_v1'
          )
        )),
        metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
          'rhythm_target_state', p_target_state,
          'rhythm_boundary_at', p_boundary_at,
          'rhythm_task_identity_preserved', true
        ),
        state = case when state = 'failed' then 'eligible' else state end,
        updated_at = now()
    where id = v_occurrence.id;

    v_release := atlas.signal_work_occurrence_v1(
      v_occurrence.id,
      'rhythm_clock:' || p_target_state,
      jsonb_build_object(
        'rhythm_state_id', v_state.id,
        'boundary_at', p_boundary_at,
        'task_identity_preserved', true
      )
    );

    select released_task_id into v_released_task_id
    from atlas.planned_work_occurrences
    where id = v_occurrence.id;

    update atlas.rhythm_state
    set current_task_id = v_released_task_id,
        current_occurrence_id = v_occurrence.id,
        updated_at = now()
    where id = v_state.id;

    return jsonb_build_object(
      'taskId', v_released_task_id,
      'occurrenceId', v_occurrence.id,
      'action', case
        when v_released_task_id is null then 'updated_current_occurrence_awaiting_capacity'
        when p_target_state = 'fallen_out_of_rhythm' then 'released_escalated_current_occurrence'
        else 'released_current_occurrence'
      end
    );
  end if;

  return atlas.ensure_rhythm_task_v1_base(
    p_state_id,
    p_target_state,
    p_boundary_at
  );
end;
$function$

COMMIT;

-- Inert source candidate; not a production migration.
-- Based on exact current atlas.release_eligible_work_without_weed_physical_gate_v1
-- from read-only pg_get_functiondef inspection on 2026-10-15.
-- Clone validation required prior to canonical source generation.
begin;
CREATE OR REPLACE FUNCTION atlas.release_eligible_work_without_weed_physical_gate_v1(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date, p_limit integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_settings atlas.farm_task_release_settings%rowtype;
  v_today date;
  v_limit integer;
  v_active_top integer;
  v_released integer := 0;
  v_required integer := 0;
  v_process integer := 0;
  v_rhythm integer := 0;
  v_discretionary integer := 0;
  v_budget_blocked integer := 0;
  v_safety_blocked boolean := false;
  v_row record;
  v_policy_active integer;
  v_task_id uuid;
  v_assigned_membership_id uuid;
  v_assigned_user_id uuid;
  v_day_load jsonb;
  v_budget numeric;
  v_total_units numeric;
  v_enforce boolean;
  v_execution_date date;
  v_relation jsonb;
  v_window_key text;
  v_window jsonb;
  v_release_time time;
  v_close_time time;
  v_existing_satisfaction jsonb;
  v_invalid_org_count integer := 0;

begin
  insert into atlas.farm_task_release_settings(farm_id) values (p_farm_id)
  on conflict (farm_id) do nothing;
  select * into v_settings from atlas.farm_task_release_settings where farm_id=p_farm_id;
  if not coalesce(v_settings.active,true) then
    return jsonb_build_object('farmId',p_farm_id,'released',0,'inactive',true);
  end if;
  v_today := coalesce(p_as_of_date,(now() at time zone v_settings.timezone_name)::date);
  v_limit := least(greatest(coalesce(p_limit,v_settings.maximum_release_batch_size),1),v_settings.maximum_release_batch_size);
  select count(*)::integer into v_active_top from atlas.tasks
  where farm_id=p_farm_id and status in ('open','blocked') and parent_task_id is null;
  if v_active_top >= v_settings.maximum_active_safety_tasks then
    return jsonb_build_object(
      'farmId',p_farm_id,'asOfDate',v_today,'released',0,
      'safetyCircuitBreaker',true,'activeTopLevel',v_active_top,
      'safetyLimit',v_settings.maximum_active_safety_tasks
    );
  end if;

  perform set_config('atlas.release_engine_active','on',true);

  for v_row in
    select occurrence.*, policy.gate_type, policy.maximum_active_instances, policy.active as policy_active
    from atlas.planned_work_occurrences occurrence
    join atlas.work_release_policies policy on policy.id=occurrence.release_policy_id
    where occurrence.farm_id=p_farm_id
      and occurrence.state in ('planned','eligible','failed')
      and policy.active
      and occurrence.not_before_date <= v_today
      and occurrence.planned_due_date <= v_today + least(policy.horizon_days,v_settings.maximum_task_horizon_days)
      and (occurrence.parent_occurrence_id is null or exists (
        select 1 from atlas.planned_work_occurrences parent
        where parent.id=occurrence.parent_occurrence_id and parent.state in ('released','completed')
      ))
      and atlas.work_occurrence_gate_satisfied_v1(occurrence.id,v_today)
    order by case occurrence.work_lane
      when 'required' then 0 when 'process_continuation' then 1 when 'rhythm' then 2 else 3 end,
      occurrence.planned_due_date,occurrence.created_at
    for update of occurrence skip locked
  loop
    exit when v_released >= v_limit;

    v_existing_satisfaction := atlas.work_occurrence_existing_preparation_v1(v_row.id);
    if coalesce((v_existing_satisfaction ->> 'satisfied')::boolean, false) then
      update atlas.planned_work_occurrences
      set state = 'completed',
          gate_satisfied_at = coalesce(gate_satisfied_at, (v_existing_satisfaction ->> 'completedAt')::timestamptz, now()),
          metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
            'completedByExistingObjectState', true,
            'completionEvidenceEventId', v_existing_satisfaction ->> 'eventId',
            'completionEvidenceEventType', v_existing_satisfaction ->> 'eventType',
            'completionEvidenceSource', v_existing_satisfaction ->> 'source',
            'completionEvidenceAt', v_existing_satisfaction ->> 'completedAt',
            'suppressedReleaseAt', now()
          ),
          updated_at = now()
      where id = v_row.id;
      continue;
    end if;
    select count(*)::integer into v_active_top from atlas.tasks
      where farm_id=p_farm_id and status in ('open','blocked') and parent_task_id is null;
    if v_active_top >= v_settings.maximum_active_safety_tasks then
      v_safety_blocked := true;
      exit;
    end if;

    select task.id into v_task_id
    from atlas.tasks task
    where task.planned_occurrence_id=v_row.id and task.status in ('open','blocked')
    order by task.created_at,task.id limit 1;
    if v_task_id is not null then
      update atlas.planned_work_occurrences
      set state='released',released_task_id=v_task_id,released_at=coalesce(released_at,now()),updated_at=now()
      where id=v_row.id;
      continue;
    end if;

    -- A stale organization reference must not abort all farms' task releases.
    -- Keep this occurrence eligible and visible for governed reconciliation.
    -- Never substitute the farm's current organization by inference.
    if nullif(v_row.task_payload ->> 'organization_id','') is not null
       and not exists (
         select 1 from atlas.organizations org
         where org.id::text = v_row.task_payload ->> 'organization_id'
       ) then
      if coalesce(v_row.metadata ->> 'releaseHoldReason','') <> 'unresolved_organization' then
        update atlas.planned_work_occurrences o
        set metadata = coalesce(o.metadata,'{}'::jsonb) || jsonb_build_object(
              'releaseHoldReason','unresolved_organization',
              'releaseHoldOrgId',v_row.task_payload ->> 'organization_id',
              'releaseHoldSource','farm_work_release_organization_guard_v1',
              'releaseHeldAt',now()
            ),
            updated_at = now()
        where o.id=v_row.id;
      end if;
      v_invalid_org_count := v_invalid_org_count + 1;
      continue;
    end if;

    select count(*)::integer into v_policy_active
    from atlas.tasks task
    where task.farm_id=p_farm_id and task.release_policy_id=v_row.release_policy_id
      and task.status in ('open','blocked');
    if v_policy_active >= v_row.maximum_active_instances then continue; end if;

    v_assigned_membership_id := nullif(v_row.task_payload ->> 'assigned_membership_id','')::uuid;
    v_assigned_user_id := nullif(v_row.task_payload ->> 'assigned_user_id','')::uuid;
    v_execution_date := case
      when v_row.commitment_kind in ('floating','persistent') and v_row.planned_due_date < v_today then v_today
      else v_row.planned_due_date
    end;

    if v_row.work_lane='discretionary' and v_assigned_membership_id is not null then
      v_day_load := atlas.member_day_load_core_v1(p_farm_id,v_assigned_membership_id,v_execution_date,v_row.id);
      v_budget := (v_day_load ->> 'dailyUnitBudget')::numeric;
      v_total_units := (v_day_load ->> 'totalUnits')::numeric;
      v_enforce := (v_day_load ->> 'budgetEnforced')::boolean;
      if v_enforce and v_total_units + v_row.effort_units > v_budget then
        update atlas.planned_work_occurrences
        set state='eligible',
            metadata=metadata || jsonb_build_object(
              'lastBudgetCheckAt',now(),
              'lastBudgetCheckDate',v_execution_date,
              'lastBudgetUnits',v_total_units,
              'dailyUnitBudget',v_budget,
              'budgetBlocked',true
            ),updated_at=now()
        where id=v_row.id;
        v_budget_blocked := v_budget_blocked + 1;
        continue;
      end if;
    end if;

    if v_row.work_lane='rhythm' then
      update atlas.planned_work_occurrences older
      set state='cancelled',
          metadata=older.metadata || jsonb_build_object(
            'supersededByRhythmOccurrenceId',v_row.id,
            'supersededAt',now(),
            'supersededReason','Persistent rhythms expose one current serving and do not replay missed copies.'
          ),updated_at=now()
      where older.release_policy_id=v_row.release_policy_id
        and older.work_lane='rhythm'
        and older.state in ('planned','eligible','failed')
        and older.planned_due_date < v_row.planned_due_date;
    end if;

    update atlas.planned_work_occurrences
    set state='releasing',gate_satisfied_at=coalesce(gate_satisfied_at,now()),updated_at=now()
    where id=v_row.id;

    insert into atlas.tasks(
      farm_id,zone_id,title,task_type,status,priority,due_date,unlock_text,note,metadata,
      action_key,work_class,visibility_scope,assigned_membership_id,assigned_user_id,
      created_by_user_id,origin_kind,task_scope,planned_occurrence_id,release_policy_id,
      released_at,release_reason,organization_id,work_lane,commitment_kind,effort_units
    ) values (
      p_farm_id,
      nullif(v_row.task_payload ->> 'zone_id','')::uuid,
      coalesce(nullif(v_row.task_payload ->> 'title',''),v_row.title),
      coalesce(nullif(v_row.task_payload ->> 'task_type',''),'general'),
      'open',coalesce(nullif(v_row.task_payload ->> 'priority',''),'normal'),
      v_execution_date,
      nullif(v_row.task_payload ->> 'unlock_text',''),
      nullif(v_row.task_payload ->> 'note',''),
      coalesce(v_row.task_payload -> 'metadata','{}'::jsonb) || jsonb_build_object(
        'work_lane',v_row.work_lane,
        'commitment_kind',v_row.commitment_kind,
        'effort_units',v_row.effort_units,
        'reservoir_planned_due_date',v_row.planned_due_date,
        'execution_date',v_execution_date
      ),
      nullif(v_row.task_payload ->> 'action_key',''),
      nullif(v_row.task_payload ->> 'work_class',''),
      coalesce(nullif(v_row.task_payload ->> 'visibility_scope',''),'assigned_worker'),
      v_assigned_membership_id,v_assigned_user_id,
      nullif(v_row.task_payload ->> 'created_by_user_id','')::uuid,
      case when v_row.task_payload ->> 'origin_kind' in ('legacy','owner_assigned','contributor_created','generated') then v_row.task_payload ->> 'origin_kind' else 'generated' end,
      coalesce(nullif(v_row.task_payload ->> 'task_scope',''),'farm_operation'),
      v_row.id,v_row.release_policy_id,now(),
      case v_row.work_lane
        when 'required' then 'committed_window'
        when 'process_continuation' then 'process_continuation'
        when 'rhythm' then 'rhythm_serving'
        else 'discretionary_day_budget'
      end,
      nullif(v_row.task_payload ->> 'organization_id','')::uuid,
      v_row.work_lane,v_row.commitment_kind,v_row.effort_units
    ) returning id into v_task_id;

    v_relation := coalesce(v_row.relation_payload,'{}'::jsonb);
    perform atlas.restore_task_relation_payload_v1(v_task_id,v_relation);

    v_window_key := coalesce(
      nullif(v_row.task_payload -> 'metadata' ->> 'work_window_key',''),
      nullif(v_row.task_payload -> 'metadata' ->> 'window_key',''),
      'morning'
    );
    v_window := atlas.maintenance_directive_window_v1(v_window_key);
    if v_window is not null then
      v_release_time := (v_window ->> 'release')::time;
      v_close_time := (v_window ->> 'close')::time;
      insert into atlas.task_notification_plans(
        farm_id,task_id,release_local_time,close_local_time,nudge_after_minutes,
        group_key,group_label,source,active,metadata
      ) values (
        p_farm_id,v_task_id,v_release_time,v_close_time,60,
        'reservoir:' || v_row.release_policy_id::text,
        coalesce(v_window ->> 'label','Farm work'),
        'work_reservoir_execution_window',true,
        jsonb_build_object('occurrenceId',v_row.id,'workLane',v_row.work_lane,'workWindowKey',v_window_key)
      )
      on conflict (task_id) do update
      set release_local_time=excluded.release_local_time,
          close_local_time=excluded.close_local_time,
          nudge_after_minutes=excluded.nudge_after_minutes,
          group_key=excluded.group_key,
          group_label=excluded.group_label,
          source=excluded.source,
          active=true,
          metadata=atlas.task_notification_plans.metadata || excluded.metadata,
          updated_at=now();
    end if;

    update atlas.planned_work_occurrences
    set state='released',released_at=now(),released_task_id=v_task_id,
        metadata=(metadata - 'budgetBlocked') || jsonb_build_object(
          'releasedBy','work_reservoir_execution_window_v1',
          'releasedLane',v_row.work_lane,
          'releasedExecutionDate',v_execution_date
        ),updated_at=now()
    where id=v_row.id;

    insert into atlas.task_release_events(farm_id,occurrence_id,release_policy_id,task_id,release_reason,metadata)
    values (
      p_farm_id,v_row.id,v_row.release_policy_id,v_task_id,
      case v_row.work_lane
        when 'required' then 'committed_window'
        when 'process_continuation' then 'process_continuation'
        when 'rhythm' then 'rhythm_serving'
        else 'discretionary_day_budget'
      end,
      jsonb_build_object('workLane',v_row.work_lane,'commitmentKind',v_row.commitment_kind,'effortUnits',v_row.effort_units,'executionDate',v_execution_date)
    ) on conflict (occurrence_id,task_id) do nothing;

    v_released := v_released+1;
    if v_row.work_lane='required' then v_required:=v_required+1;
    elsif v_row.work_lane='process_continuation' then v_process:=v_process+1;
    elsif v_row.work_lane='rhythm' then v_rhythm:=v_rhythm+1;
    else v_discretionary:=v_discretionary+1;
    end if;
  end loop;

  perform set_config('atlas.release_engine_active','off',true);

  return jsonb_build_object(
    'contractVersion','work_reservoir_execution_window_v1',
    'farmId',p_farm_id,'asOfDate',v_today,'released',v_released,
    'requiredReleased',v_required,'processReleased',v_process,
    'rhythmReleased',v_rhythm,'discretionaryReleased',v_discretionary,
    'budgetBlocked',v_budget_blocked,'invalidOrganizationHeld',v_invalid_org_count,
    'safetyCircuitBreaker',v_safety_blocked,
    'activeTopLevel',v_active_top,'safetyLimit',v_settings.maximum_active_safety_tasks
  );
end;
$function$;

commit;

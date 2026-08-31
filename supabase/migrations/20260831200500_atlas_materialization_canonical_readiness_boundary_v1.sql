BEGIN;

-- A planned occurrence may represent valid work that is not yet executable.
-- Materialization must preserve that obligation without promoting it to open
-- worker work when canonical execution requirements are not satisfied.
--
-- The existing task_execution_readiness_v1 authority already evaluates the
-- generic requirement graph (inventory, equipment, treatment, capability
-- holds, and other registered execution requirements). The materializer must
-- consult that authority only after restoring the occurrence relation payload,
-- because those restored relations are part of the readiness evidence.

create or replace function atlas.materialize_specific_work_occurrence_v1(
  p_occurrence_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_occ atlas.planned_work_occurrences%rowtype;
  v_policy atlas.work_release_policies%rowtype;
  v_settings atlas.farm_task_release_settings%rowtype;
  v_farm atlas.farms%rowtype;
  v_task_id uuid;
  v_existing uuid;
  v_policy_active integer:=0;
  v_active_top integer:=0;
  v_as_of date:=coalesce(p_as_of_date,current_date);
  v_assigned_membership_id uuid;
  v_assigned_user_id uuid;
  v_execution_date date;
  v_relation jsonb;
  v_window_key text;
  v_window jsonb;
  v_release_time time;
  v_close_time time;
  v_existing_satisfaction jsonb;
  v_execution_readiness jsonb;
  v_materialized_status text;
begin
  select * into v_occ from atlas.planned_work_occurrences where id=p_occurrence_id for update;
  if v_occ.id is null then raise exception 'Planned occurrence was not found.' using errcode='P0002'; end if;
  select * into v_policy from atlas.work_release_policies where id=v_occ.release_policy_id;
  if v_policy.id is null or not v_policy.active then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','policy_inactive','occurrenceId',v_occ.id,'taskId',null);
  end if;
  select * into v_farm from atlas.farms where id=v_occ.farm_id;
  insert into atlas.farm_task_release_settings(farm_id) values(v_occ.farm_id) on conflict(farm_id) do nothing;
  select * into v_settings from atlas.farm_task_release_settings where farm_id=v_occ.farm_id;
  if not coalesce(v_settings.active,true) then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','release_disabled','occurrenceId',v_occ.id,'taskId',null);
  end if;

  select t.id into v_existing
  from atlas.tasks t
  where t.planned_occurrence_id=v_occ.id and t.status in ('open','blocked')
  order by t.created_at,t.id limit 1;
  if v_existing is not null then
    update atlas.planned_work_occurrences
    set state='released',released_task_id=v_existing,released_at=coalesce(released_at,now()),updated_at=now()
    where id=v_occ.id;
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','kept_current','occurrenceId',v_occ.id,'taskId',v_existing);
  end if;

  if v_occ.state='completed' then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','already_completed','occurrenceId',v_occ.id,'taskId',v_occ.released_task_id);
  end if;
  if v_occ.state='cancelled' then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','cancelled','occurrenceId',v_occ.id,'taskId',null);
  end if;
  if v_occ.not_before_date is not null and v_occ.not_before_date>v_as_of then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','not_before_boundary','occurrenceId',v_occ.id,'taskId',null,'notBeforeDate',v_occ.not_before_date);
  end if;
  if not atlas.work_occurrence_gate_satisfied_v1(v_occ.id,v_as_of) then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','gate_not_satisfied','occurrenceId',v_occ.id,'taskId',null);
  end if;

  v_existing_satisfaction:=atlas.work_occurrence_existing_preparation_v1(v_occ.id);
  if coalesce((v_existing_satisfaction->>'satisfied')::boolean,false) then
    update atlas.planned_work_occurrences
    set state='completed',gate_satisfied_at=coalesce(gate_satisfied_at,(v_existing_satisfaction->>'completedAt')::timestamptz,now()),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'completedByExistingObjectState',true,
          'completionEvidenceEventId',v_existing_satisfaction->>'eventId',
          'completionEvidenceEventType',v_existing_satisfaction->>'eventType',
          'completionEvidenceSource',v_existing_satisfaction->>'source',
          'completionEvidenceAt',v_existing_satisfaction->>'completedAt',
          'suppressedReleaseAt',now()
        ),updated_at=now()
    where id=v_occ.id;
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','already_satisfied','occurrenceId',v_occ.id,'taskId',null,'evidence',v_existing_satisfaction);
  end if;

  select count(*)::integer into v_active_top from atlas.tasks
  where farm_id=v_occ.farm_id and status in ('open','blocked') and parent_task_id is null;
  if v_active_top>=v_settings.maximum_active_safety_tasks then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','safety_circuit_breaker','occurrenceId',v_occ.id,'taskId',null,'activeTopLevel',v_active_top,'safetyLimit',v_settings.maximum_active_safety_tasks);
  end if;

  select count(*)::integer into v_policy_active
  from atlas.tasks t
  where t.farm_id=v_occ.farm_id and t.release_policy_id=v_occ.release_policy_id and t.status in ('open','blocked');
  if v_policy_active>=v_policy.maximum_active_instances then
    return jsonb_build_object('contractVersion','materialize_specific_work_occurrence_v1','state','policy_active_limit','occurrenceId',v_occ.id,'taskId',null,'activeInstances',v_policy_active,'maximumActiveInstances',v_policy.maximum_active_instances);
  end if;

  v_assigned_membership_id:=nullif(v_occ.task_payload->>'assigned_membership_id','')::uuid;
  v_assigned_user_id:=nullif(v_occ.task_payload->>'assigned_user_id','')::uuid;
  v_execution_date:=case
    when v_occ.commitment_kind in ('floating','persistent') and v_occ.planned_due_date<v_as_of then v_as_of
    else v_occ.planned_due_date
  end;

  perform set_config('atlas.release_engine_active','on',true);
  update atlas.planned_work_occurrences
  set state='releasing',gate_satisfied_at=coalesce(gate_satisfied_at,now()),updated_at=now()
  where id=v_occ.id;

  insert into atlas.tasks(
    farm_id,zone_id,title,task_type,status,priority,due_date,unlock_text,note,metadata,
    action_key,work_class,visibility_scope,assigned_membership_id,assigned_user_id,
    created_by_user_id,origin_kind,task_scope,planned_occurrence_id,release_policy_id,
    released_at,release_reason,organization_id,work_lane,commitment_kind,effort_units
  ) values (
    v_occ.farm_id,
    nullif(v_occ.task_payload->>'zone_id','')::uuid,
    coalesce(nullif(v_occ.task_payload->>'title',''),v_occ.title),
    coalesce(nullif(v_occ.task_payload->>'task_type',''),'general'),
    'open',coalesce(nullif(v_occ.task_payload->>'priority',''),'normal'),
    v_execution_date,
    nullif(v_occ.task_payload->>'unlock_text',''),
    nullif(v_occ.task_payload->>'note',''),
    coalesce(v_occ.task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
      'work_lane',v_occ.work_lane,
      'commitment_kind',v_occ.commitment_kind,
      'effort_units',v_occ.effort_units,
      'reservoir_planned_due_date',v_occ.planned_due_date,
      'execution_date',v_execution_date,
      'materializedBy','materialize_specific_work_occurrence_v1'
    ),
    nullif(v_occ.task_payload->>'action_key',''),
    nullif(v_occ.task_payload->>'work_class',''),
    coalesce(nullif(v_occ.task_payload->>'visibility_scope',''),'assigned_worker'),
    v_assigned_membership_id,v_assigned_user_id,
    nullif(v_occ.task_payload->>'created_by_user_id','')::uuid,
    case when v_occ.task_payload->>'origin_kind' in ('legacy','owner_assigned','contributor_created','generated') then v_occ.task_payload->>'origin_kind' else 'generated' end,
    coalesce(nullif(v_occ.task_payload->>'task_scope',''),'farm_operation'),
    v_occ.id,v_occ.release_policy_id,now(),
    case v_occ.work_lane when 'required' then 'committed_window' when 'process_continuation' then 'process_continuation' when 'rhythm' then 'rhythm_serving' else 'discretionary_day_budget' end,
    coalesce(nullif(v_occ.task_payload->>'organization_id','')::uuid,v_farm.organization_id),
    v_occ.work_lane,v_occ.commitment_kind,v_occ.effort_units
  ) returning id into v_task_id;

  v_relation:=coalesce(v_occ.relation_payload,'{}'::jsonb);
  perform atlas.restore_task_relation_payload_v1(v_task_id,v_relation);

  -- Canonical materialization boundary: requirements are authoritative only
  -- after occurrence relations have been restored. An unmet requirement keeps
  -- the work obligation alive but blocks execution instead of emitting open work.
  v_execution_readiness:=atlas.task_execution_readiness_v1(v_task_id);
  if not coalesce((v_execution_readiness->>'executable')::boolean,false) then
    update atlas.tasks
    set status='blocked',updated_at=now()
    where id=v_task_id and status='open';
  end if;

  select status into v_materialized_status
  from atlas.tasks
  where id=v_task_id;

  v_window_key:=coalesce(nullif(v_occ.task_payload->'metadata'->>'work_window_key',''),nullif(v_occ.task_payload->'metadata'->>'window_key',''),'morning');
  v_window:=atlas.maintenance_directive_window_v1(v_window_key);
  if v_window is not null then
    v_release_time:=(v_window->>'release')::time;
    v_close_time:=(v_window->>'close')::time;
    insert into atlas.task_notification_plans(
      farm_id,task_id,release_local_time,close_local_time,nudge_after_minutes,group_key,group_label,source,active,metadata
    ) values (
      v_occ.farm_id,v_task_id,v_release_time,v_close_time,60,
      'reservoir:'||v_occ.release_policy_id::text,coalesce(v_window->>'label','Farm work'),
      'work_reservoir_execution_window',true,
      jsonb_build_object('occurrenceId',v_occ.id,'workLane',v_occ.work_lane,'workWindowKey',v_window_key)
    )
    on conflict(task_id) do update set
      release_local_time=excluded.release_local_time,close_local_time=excluded.close_local_time,
      nudge_after_minutes=excluded.nudge_after_minutes,group_key=excluded.group_key,group_label=excluded.group_label,
      source=excluded.source,active=true,metadata=atlas.task_notification_plans.metadata||excluded.metadata,updated_at=now();
  end if;

  update atlas.planned_work_occurrences
  set state='released',released_at=now(),released_task_id=v_task_id,
      metadata=(metadata-'budgetBlocked')||jsonb_build_object(
        'releasedBy','materialize_specific_work_occurrence_v1',
        'releasedLane',v_occ.work_lane,
        'releasedExecutionDate',v_execution_date
      ),updated_at=now()
  where id=v_occ.id;

  insert into atlas.task_release_events(farm_id,occurrence_id,release_policy_id,task_id,release_reason,metadata)
  values(
    v_occ.farm_id,v_occ.id,v_occ.release_policy_id,v_task_id,
    case v_occ.work_lane when 'required' then 'committed_window' when 'process_continuation' then 'process_continuation' when 'rhythm' then 'rhythm_serving' else 'discretionary_day_budget' end,
    jsonb_build_object(
      'workLane',v_occ.work_lane,
      'commitmentKind',v_occ.commitment_kind,
      'effortUnits',v_occ.effort_units,
      'executionDate',v_execution_date,
      'materializedBy','materialize_specific_work_occurrence_v1',
      'materializedTaskStatus',v_materialized_status,
      'canonicalExecutionReadiness',coalesce((v_execution_readiness->>'executable')::boolean,false)
    )
  ) on conflict(occurrence_id,task_id) do nothing;

  perform set_config('atlas.release_engine_active','off',true);
  return jsonb_build_object(
    'contractVersion','materialize_specific_work_occurrence_v1',
    'state','released',
    'occurrenceId',v_occ.id,
    'taskId',v_task_id,
    'taskStatus',v_materialized_status,
    'executable',coalesce((v_execution_readiness->>'executable')::boolean,false),
    'workLane',v_occ.work_lane,
    'commitmentKind',v_occ.commitment_kind,
    'executionDate',v_execution_date
  );
end;
$function$;

comment on function atlas.materialize_specific_work_occurrence_v1(uuid,date) is
  'Materializes a planned work occurrence, restores its relation payload, then applies canonical task execution readiness before the task can survive as open worker work. Unmet requirements preserve the task as blocked.';

COMMIT;

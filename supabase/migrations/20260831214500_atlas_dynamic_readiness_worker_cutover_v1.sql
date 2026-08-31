BEGIN;

-- Atlas launch boundary:
--   task status = obligation lifecycle
--   execution readiness = current physical/operational warrant
--   worker presentability = readiness + assignment + routing + operation fit
--
-- Temporary reality (missing seed, broken equipment, unresolved destination,
-- unknown consumable state) must not permanently mutate an obligation into a
-- lifecycle status that needs a separate domain-specific reopen path.

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

  -- Readiness is evidence about execution now, not a lifecycle transition.
  -- Keep the still-valid obligation open; worker presentability and transition
  -- authority consume this same warrant dynamically.
  v_execution_readiness:=atlas.task_execution_readiness_v1(v_task_id);
  update atlas.tasks
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'execution_ready_at_materialization',coalesce((v_execution_readiness->>'executionReady')::boolean,false),
        'execution_readiness_checked_at',now(),
        'execution_readiness_authority','task_execution_readiness_v1'
      ),
      updated_at=now()
  where id=v_task_id;

  select status into v_materialized_status from atlas.tasks where id=v_task_id;

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
      'canonicalExecutionReadiness',coalesce((v_execution_readiness->>'executionReady')::boolean,false),
      'readinessDoesNotMutateObligationLifecycle',true
    )
  ) on conflict(occurrence_id,task_id) do nothing;

  perform set_config('atlas.release_engine_active','off',true);
  return jsonb_build_object(
    'contractVersion','materialize_specific_work_occurrence_v2',
    'state','released',
    'occurrenceId',v_occ.id,
    'taskId',v_task_id,
    'taskStatus',v_materialized_status,
    'executionReady',coalesce((v_execution_readiness->>'executionReady')::boolean,false),
    'workLane',v_occ.work_lane,
    'commitmentKind',v_occ.commitment_kind,
    'executionDate',v_execution_date
  );
end;
$function$;

create or replace function atlas.worker_day_obligation_coverage_audit_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  task_status text,
  due_date date,
  execution_ready boolean,
  routed_for_day boolean,
  presentable boolean,
  hold_reason text,
  coverage_reason text
)
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with member as (
    select fm.user_id,nullif(lower(btrim(fm.worker_key)),'') as worker_key
    from atlas.farm_memberships fm
    where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active
  ), candidates as (
    select t.id,t.status,t.due_date,
      case
        when t.due_date is not null and t.due_date<p_day then 'assigned_overdue'
        when t.due_date=p_day then 'assigned_due_today'
        when coalesce(t.metadata->>'execution_date','') ~ '^\\d{4}-\\d{2}-\\d{2}$'
          and (t.metadata->>'execution_date')::date<p_day then 'assigned_execution_overdue'
        else 'assigned_active_obligation'
      end as reason
    from atlas.tasks t
    cross join member m
    where t.farm_id=p_farm_id
      and t.task_scope='farm_operation'
      and t.status in ('open','blocked')
      and t.parent_task_id is null
      and coalesce(t.visibility_scope,'assigned_worker')<>'system_internal'
      and (
        t.assigned_membership_id=p_membership_id
        or t.assigned_user_id=m.user_id
        or t.metadata->>'executor_membership_id'=p_membership_id::text
        or (
          m.worker_key is not null
          and lower(coalesce(
            nullif(t.metadata->>'executor_worker_key',''),
            nullif(t.metadata->>'assignee_key',''),
            nullif(t.metadata->>'assigned_to',''),
            nullif(t.metadata->>'work_route','')
          ))=m.worker_key
        )
      )
  ), warrants as (
    select c.*,
      atlas.worker_task_presentability_v1(p_farm_id,p_membership_id,c.id,p_day) as warrant
    from candidates c
  )
  select
    w.id,
    w.status,
    w.due_date,
    coalesce((w.warrant->>'executionReady')::boolean,false),
    coalesce((w.warrant->>'routedForDay')::boolean,false),
    coalesce((w.warrant->>'presentable')::boolean,false),
    w.warrant->>'holdReason',
    w.reason
  from warrants w
  order by w.due_date nulls last,w.id;
$function$;

create or replace function atlas.worker_day_work_projection_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  visibility_state text,
  visibility_reason text,
  presentation_state text,
  presentation_reason text,
  selection_rank bigint,
  work_lane text,
  commitment_kind text,
  effort_units numeric,
  budget_units numeric,
  notification_planned boolean,
  overload boolean
)
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with selected as materialized (
    select *
    from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_day)
  ), placed as materialized (
    select distinct p.task_id
    from atlas.worker_day_task_placements p
    where p.farm_id=p_farm_id
      and p.membership_id=p_membership_id
      and p.service_date=p_day
      and p.state='placed'
  ), ids as (
    select s.task_id from selected s
    union
    select p.task_id from placed p
  ), candidates as (
    select
      i.task_id,
      case when p.task_id is not null then 'explicit_placement_today' else 'presentation_selected' end as visibility_reason,
      coalesce(s.presentation_state,'presented') as presentation_state,
      coalesce(s.presentation_reason,'explicit_placement') as presentation_reason,
      coalesce(s.selection_rank,9223372036854775807::bigint) as selection_rank,
      coalesce(s.work_lane,t.work_lane,'required') as work_lane,
      coalesce(s.commitment_kind,t.commitment_kind,'none') as commitment_kind,
      coalesce(s.effort_units,t.effort_units,0::numeric) as effort_units,
      coalesce(s.budget_units,0::numeric) as budget_units,
      coalesce(s.notification_planned,false) as notification_planned,
      coalesce(s.overload,false) as overload,
      atlas.worker_task_presentability_v1(p_farm_id,p_membership_id,i.task_id,p_day) as warrant
    from ids i
    join atlas.tasks t on t.id=i.task_id
    left join selected s on s.task_id=i.task_id
    left join placed p on p.task_id=i.task_id
  )
  select
    c.task_id,
    'visible'::text,
    c.visibility_reason,
    c.presentation_state,
    c.presentation_reason,
    c.selection_rank,
    c.work_lane,
    c.commitment_kind,
    c.effort_units,
    c.budget_units,
    c.notification_planned,
    c.overload
  from candidates c
  where coalesce((c.warrant->>'presentable')::boolean,false)
  order by c.selection_rank,c.task_id;
$function$;

create or replace function atlas.task_notification_profile_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_plan atlas.task_notification_plans%rowtype;
  v_title text;
  v_action text;
  v_task_type text;
  v_collection text;
  v_group_key text;
  v_group_label text;
  v_release time;
  v_close time;
  v_nudge integer;
  v_release_text text;
  v_close_text text;
  v_nudge_text text;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then return null; end if;

  -- Notification is an execution-facing surface. Keep the durable schedule plan
  -- so it can recover automatically, but do not emit a notification profile
  -- while the obligation is closed or current execution reality is not ready.
  if v_task.status<>'open'
     or not coalesce((atlas.task_execution_readiness_v1(v_task.id)->>'executionReady')::boolean,false) then
    return null;
  end if;

  select * into v_plan
  from atlas.task_notification_plans
  where task_id=p_task_id and active;

  if v_plan.id is not null then
    return jsonb_build_object(
      'source',v_plan.source,
      'releaseTime',to_char(v_plan.release_local_time,'HH24:MI'),
      'closeTime',case when v_plan.close_local_time is null then null else to_char(v_plan.close_local_time,'HH24:MI') end,
      'nudgeMinutes',v_plan.nudge_after_minutes,
      'groupKey',coalesce(nullif(v_plan.group_key,''),p_task_id::text),
      'groupLabel',coalesce(nullif(v_plan.group_label,''),nullif(v_task.metadata->>'collection_label',''),v_task.title)
    );
  end if;

  v_release_text:=nullif(v_task.metadata->>'notification_release_local_time','');
  v_close_text:=nullif(v_task.metadata->>'notification_close_local_time','');
  v_nudge_text:=nullif(v_task.metadata->>'notification_nudge_after_minutes','');

  if v_release_text is not null then
    begin v_release:=v_release_text::time; exception when invalid_datetime_format then v_release:=null; end;
    if v_release is not null then
      begin v_close:=case when v_close_text is null then null else v_close_text::time end; exception when invalid_datetime_format then v_close:=null; end;
      begin v_nudge:=case when v_nudge_text is null then null else v_nudge_text::integer end; exception when invalid_text_representation then v_nudge:=null; end;
      v_group_label:=coalesce(nullif(v_task.metadata->>'notification_group_label',''),nullif(v_task.metadata->>'collection_label',''),v_task.title);
      v_group_key:=coalesce(nullif(v_task.metadata->>'notification_group_key',''),trim(both '_' from lower(regexp_replace(v_group_label,'[^a-zA-Z0-9]+','_','g'))));
      if v_group_key in ('owner','owner_work','today_s_work','') then v_group_key:=p_task_id::text; end if;
      return jsonb_build_object(
        'source','task_metadata','releaseTime',to_char(v_release,'HH24:MI'),
        'closeTime',case when v_close is null then null else to_char(v_close,'HH24:MI') end,
        'nudgeMinutes',v_nudge,'groupKey',v_group_key||'@'||replace(to_char(v_release,'HH24:MI'),':',''),'groupLabel',v_group_label
      );
    end if;
  end if;

  v_title:=lower(coalesce(v_task.title,''));
  v_action:=lower(coalesce(nullif(v_task.action_key,''),nullif(v_task.metadata->>'display_action',''),''));
  v_task_type:=lower(coalesce(v_task.task_type,''));
  v_collection:=nullif(v_task.metadata->>'collection_label','');

  if v_title like '%trash%' then
    v_release:=time '19:00'; v_close:=time '20:30'; v_nudge:=35; v_group_label:='Trash to the street';
  elsif v_action='harvest' or v_task_type like '%harvest%' then
    v_release:=time '06:30'; v_close:=time '09:00'; v_nudge:=45; v_group_label:=coalesce(v_collection,'Morning harvest');
  elsif v_action in ('spray','respray') or v_task_type like '%spray%' then
    v_release:=time '07:30'; v_close:=time '10:30'; v_nudge:=60; v_group_label:=coalesce(v_collection,'Morning spraying');
  elsif v_action in ('weed','weeding') or v_task_type like '%weed%' then
    v_release:=time '08:00'; v_close:=time '11:30'; v_nudge:=60; v_group_label:=coalesce(v_collection,'Morning weeding');
  elsif v_action in ('sow','transplant','plant') or v_task_type in ('sowing','transplanting') then
    v_release:=time '09:00'; v_close:=time '13:00'; v_nudge:=60; v_group_label:=coalesce(v_collection,'Morning planting');
  elsif v_action in ('call','send','order','coordinate','network','email') or v_task_type in ('marketing','coordination','purchasing','owner_procurement') then
    v_release:=case when coalesce(v_collection,'')='Saturday Purchases' then time '11:30' else time '10:00' end;
    v_close:=case when coalesce(v_collection,'')='Saturday Purchases' then time '17:00' else time '15:00' end;
    v_nudge:=90; v_group_label:=coalesce(v_collection,'Calls and orders');
  elsif v_action='mow' or v_task_type like '%mow%' then
    v_release:=time '15:00'; v_close:=time '18:00'; v_nudge:=75; v_group_label:=coalesce(v_collection,'Afternoon mowing');
  elsif v_task_type='departure_prep' or v_action in ('pack','find','prepare') then
    v_release:=time '16:00'; v_close:=time '20:00'; v_nudge:=90; v_group_label:=coalesce(v_collection,'Departure preparation');
  elsif v_task_type like '%clean%' or v_action in ('clean','reset') then
    v_release:=time '13:00'; v_close:=time '17:00'; v_nudge:=90; v_group_label:=coalesce(v_collection,'Afternoon reset');
  else
    v_release:=time '10:00'; v_close:=time '17:00'; v_nudge:=90;
    v_group_label:=coalesce(v_collection,nullif(v_task.metadata->>'collection_zone',''),'Today''s work');
  end if;

  v_group_key:=trim(both '_' from lower(regexp_replace(coalesce(v_group_label,p_task_id::text),'[^a-zA-Z0-9]+','_','g')));
  if v_group_key in ('owner','owner_work','today_s_work','') then v_group_key:=p_task_id::text; end if;

  return jsonb_build_object(
    'source','inferred_v1','releaseTime',to_char(v_release,'HH24:MI'),'closeTime',to_char(v_close,'HH24:MI'),
    'nudgeMinutes',v_nudge,'groupKey',v_group_key||'@'||replace(to_char(v_release,'HH24:MI'),':',''),'groupLabel',v_group_label
  );
end;
$function$;

comment on function atlas.materialize_specific_work_occurrence_v1(uuid,date) is
  'Materializes an active obligation and records canonical execution readiness without turning temporary reality into lifecycle status. Worker presentation/transition authority enforce readiness dynamically.';
comment on function atlas.worker_day_work_projection_v1(uuid,uuid,date) is
  'Active Worker Day projection: canonical live selections plus explicit placements only, filtered through worker_task_presentability_v1. Legacy visibility-floor rows are not a presentation source.';
comment on function atlas.worker_day_obligation_coverage_audit_v1(uuid,uuid,date) is
  'Internal coverage audit for active assigned obligations, including overdue/not-ready/not-routed work. Audit visibility never forces worker presentation.';
comment on function atlas.task_notification_profile_v1(uuid) is
  'Notification projection for executable open work only. Durable notification plans remain stored while temporary readiness holds suppress emission dynamically.';
comment on function atlas.worker_day_visibility_floor_v1(uuid,uuid,date) is
  'Deprecated compatibility enumerator. It is not referenced by the active Worker Day projection; use worker_day_obligation_coverage_audit_v1 for coverage auditing.';

revoke all on function atlas.worker_day_obligation_coverage_audit_v1(uuid,uuid,date) from public,anon,authenticated;
grant execute on function atlas.worker_day_obligation_coverage_audit_v1(uuid,uuid,date) to service_role;

COMMIT;

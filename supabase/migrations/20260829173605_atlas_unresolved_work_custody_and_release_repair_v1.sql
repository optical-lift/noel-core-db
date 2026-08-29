create or replace function atlas.enqueue_anna_weeding_deadline_occurrence_v1(
  p_occurrence_id uuid,
  p_maintenance_object_id uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_occ atlas.planned_work_occurrences%rowtype;
  v_existing atlas.task_release_queue_items%rowtype;
  v_insert_position integer;
  v_last_urgent integer;
  v_first_ordinary integer;
  v_max_position integer;
begin
  select * into v_occ from atlas.planned_work_occurrences where id=p_occurrence_id for update;
  if v_occ.id is null then raise exception 'Planned occurrence not found.' using errcode='P0002'; end if;
  if coalesce(v_occ.task_payload->>'action_key','')<>'weed' then raise exception 'Occurrence is not weeding work.' using errcode='22023'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_occ.farm_id::text||':anna_weeding_rotation',0));

  select * into v_existing
  from atlas.task_release_queue_items
  where planned_occurrence_id=v_occ.id and queue_key='anna_weeding_rotation'
  order by created_at desc limit 1;

  if v_existing.id is not null and v_existing.state in ('active','queued') then
    return jsonb_build_object('queueItemId',v_existing.id,'position',v_existing.position,'state',v_existing.state,'deduplicated',true);
  end if;

  select max(position) into v_last_urgent
  from atlas.task_release_queue_items
  where farm_id=v_occ.farm_id and queue_key='anna_weeding_rotation' and state='queued'
    and metadata->>'source'='bed_readiness_deadline_pressure';

  select min(position) into v_first_ordinary
  from atlas.task_release_queue_items
  where farm_id=v_occ.farm_id and queue_key='anna_weeding_rotation' and state='queued'
    and coalesce(metadata->>'source','')<>'bed_readiness_deadline_pressure';

  select coalesce(max(position),0) into v_max_position
  from atlas.task_release_queue_items
  where farm_id=v_occ.farm_id and queue_key='anna_weeding_rotation';

  if v_last_urgent is not null then
    v_insert_position:=v_last_urgent+1;
  elsif v_first_ordinary is not null then
    v_insert_position:=v_first_ordinary;
  else
    v_insert_position:=v_max_position+1;
  end if;

  update atlas.task_release_queue_items
  set position=position+1000000,updated_at=now()
  where farm_id=v_occ.farm_id and queue_key='anna_weeding_rotation' and position>=v_insert_position;

  update atlas.task_release_queue_items
  set position=position-999999,updated_at=now()
  where farm_id=v_occ.farm_id and queue_key='anna_weeding_rotation' and position>=v_insert_position+1000000;

  insert into atlas.task_release_queue_items(
    farm_id,queue_key,task_id,planned_occurrence_id,maintenance_object_id,position,state,initial_batch,original_due_date,metadata
  ) values (
    v_occ.farm_id,'anna_weeding_rotation',null,v_occ.id,p_maintenance_object_id,v_insert_position,'queued',false,v_occ.planned_due_date,
    jsonb_build_object(
      'policy','completion_gated_serial',
      'source','bed_readiness_deadline_pressure',
      'seeded_at',now(),
      'release_timing','same_day',
      'calendar_commitment_kind','queue_only',
      'deadline_pressure',true
    )
  ) returning * into v_existing;

  update atlas.planned_work_occurrences
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'serialWeedingQueued',true,
      'serialWeedingQueuedAt',now(),
      'serialWeedingQueueKey','anna_weeding_rotation',
      'deadlinePressureQueuePosition',v_insert_position
    ),updated_at=now()
  where id=v_occ.id;

  perform atlas.sync_task_release_queue_summary_v1(v_occ.farm_id,'anna_weeding_rotation');

  return jsonb_build_object('queueItemId',v_existing.id,'position',v_existing.position,'state',v_existing.state,'deduplicated',false);
end;
$function$;

revoke all on function atlas.enqueue_anna_weeding_deadline_occurrence_v1(uuid,uuid) from public,anon,authenticated;

create or replace function atlas.ensure_due_bed_readiness_weeding_v1(p_farm_id uuid, p_as_of date default current_date)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_anna uuid;
  v_card_id uuid;
  v_occurrence_id uuid;
  v_count integer := 0;
  v_existing_task_id uuid;
  r record;
begin
  select id into v_anna
  from atlas.farm_memberships
  where farm_id=p_farm_id and worker_key='anna' and active=true
  order by created_at
  limit 1;
  if v_anna is null then return 0; end if;

  for r in
    select
      mo.id as maintenance_object_id,
      mo.object_id,
      mo.zone_id,
      mo.condition,
      greatest(5,coalesce(mo.remaining_effort_minutes,mo.current_effort_minutes,mo.maintenance_effort_minutes,30)) as estimated_minutes,
      go.stable_key as object_key,
      go.label as object_label,
      coalesce(z.label,'Elm Farm') as zone_label,
      min(nullif(md.metadata->>'ready_by_date','')::date) as ready_by,
      min(t.due_date) as dependent_due,
      array_agg(distinct t.id order by t.id) as dependent_task_ids,
      array_agg(distinct t.title order by t.title) as dependent_task_labels
    from atlas.maintenance_dependencies md
    join atlas.maintenance_objects mo on mo.id=md.maintenance_object_id
    join atlas.growing_objects go on go.id=mo.object_id
    left join atlas.zones z on z.id=mo.zone_id
    join atlas.tasks t on t.id=md.dependent_task_id
    where md.farm_id=p_farm_id
      and md.active
      and md.satisfied_at is null
      and md.metadata->>'source'='automatic_bed_readiness'
      and mo.maintenance_type='weed'
      and mo.condition<>'maintained'
      and t.status in ('open','blocked')
    group by mo.id,mo.object_id,mo.zone_id,mo.condition,mo.remaining_effort_minutes,
      mo.current_effort_minutes,mo.maintenance_effort_minutes,go.stable_key,go.label,z.label
    having min(nullif(md.metadata->>'ready_by_date','')::date)<=p_as_of
    order by min(t.due_date), max(mo.planting_block_score) desc, max(mo.owner_priority) desc, go.label
  loop
    select t.id into v_existing_task_id
    from atlas.tasks t
    where t.farm_id=p_farm_id
      and t.assigned_membership_id=v_anna
      and t.status in ('open','blocked')
      and t.action_key='weed'
      and (
        t.generated_from_id=r.maintenance_object_id
        or t.metadata->>'maintenance_object_id'=r.maintenance_object_id::text
        or exists(select 1 from atlas.task_objects x where x.task_id=t.id and x.object_id=r.object_id)
      )
    order by t.due_date nulls last,t.created_at
    limit 1;

    if v_existing_task_id is not null then
      update atlas.tasks
      set due_date=least(coalesce(due_date,p_as_of),p_as_of),
          priority='high',
          unlock_text='Prepares for '||array_to_string(r.dependent_task_labels,' · '),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'bed_readiness_deadline_pressure',true,
            'bed_ready_by_date',r.ready_by,
            'next_planting_due_date',r.dependent_due,
            'blocking_task_count',cardinality(r.dependent_task_ids),
            'dependent_task_ids',to_jsonb(r.dependent_task_ids),
            'dependent_task_labels',to_jsonb(r.dependent_task_labels),
            'blocking_due_now',r.dependent_due<=p_as_of,
            'release_reason','bed_readiness_deadline_pressure'
          ),
          updated_at=now()
      where id=v_existing_task_id;
      continue;
    end if;

    if exists(
      select 1
      from atlas.task_release_queue_items qi
      join atlas.planned_work_occurrences o on o.id=qi.planned_occurrence_id
      where qi.farm_id=p_farm_id
        and qi.queue_key='anna_weeding_rotation'
        and qi.maintenance_object_id=r.maintenance_object_id
        and qi.state in ('active','queued')
        and o.source_kind='maintenance_weeding_bed_readiness'
        and o.source_id=r.maintenance_object_id
        and o.state in ('planned','eligible','released')
    ) then
      continue;
    end if;

    update atlas.planned_work_occurrences o
    set state='cancelled',
        metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object(
          'cancelled_by','bed_readiness_deadline_pressure',
          'cancelled_at',now()
        ),
        updated_at=now()
    from atlas.task_release_queue_items qi
    where qi.farm_id=p_farm_id
      and qi.queue_key='anna_weeding_rotation'
      and qi.maintenance_object_id=r.maintenance_object_id
      and qi.state='queued'
      and qi.planned_occurrence_id=o.id
      and o.state in ('planned','eligible','failed');

    update atlas.task_release_queue_items qi
    set state='skipped',
        completed_at=coalesce(qi.completed_at,now()),
        metadata=coalesce(qi.metadata,'{}'::jsonb)||jsonb_build_object(
          'skipped_by','bed_readiness_deadline_pressure',
          'skipped_at',now()
        ),
        updated_at=now()
    where qi.farm_id=p_farm_id
      and qi.queue_key='anna_weeding_rotation'
      and qi.maintenance_object_id=r.maintenance_object_id
      and qi.state='queued';

    v_card_id := atlas.ensure_weed_card_for_object_v1(r.object_id,null);

    v_occurrence_id := atlas.plan_work_occurrence_v1(
      p_farm_id,
      'maintenance:weeding:bed-readiness',
      'maintenance:weeding:bed-readiness:deadline',
      'bed-readiness:'||r.maintenance_object_id::text||':'||r.dependent_due::text,
      'Weed '||r.object_label,
      'maintenance',
      p_as_of,
      'maintenance_weeding_bed_readiness',
      r.maintenance_object_id,
      'time_window',
      14,
      99,
      jsonb_build_object(
        'farm_id',p_farm_id,
        'zone_id',r.zone_id,
        'title','Weed '||r.object_label,
        'task_type','maintenance',
        'status','open',
        'priority','high',
        'due_date',p_as_of,
        'unlock_text','Prepares for '||array_to_string(r.dependent_task_labels,' · '),
        'generated_from','maintenance_weeding_bed_readiness',
        'generated_from_id',r.maintenance_object_id,
        'metadata',jsonb_build_object(
          'anna_task',true,
          'owner_task',false,
          'assigned_to','Anna',
          'assignee_key','anna',
          'work_route','weed',
          'work_rhythm','Weeding',
          'display_action','Weed',
          'display_title','Weed '||r.object_label,
          'display_subject',r.object_label,
          'display_detail',r.estimated_minutes::text||' min · transplant bed needed now',
          'collection_zone',r.zone_label,
          'collection_label',r.object_label,
          'maintenance_object_id',r.maintenance_object_id,
          'maintenance_type','weed',
          'target_object_id',r.object_id,
          'weed_card_id',v_card_id,
          'weed_card_managed',true,
          'weed_card_session_task',true,
          'persistent_weed_card',true,
          'bed_readiness_deadline_pressure',true,
          'bed_ready_by_date',r.ready_by,
          'next_planting_due_date',r.dependent_due,
          'blocking_task_count',cardinality(r.dependent_task_ids),
          'dependent_task_ids',to_jsonb(r.dependent_task_ids),
          'dependent_task_labels',to_jsonb(r.dependent_task_labels),
          'blocking_due_now',r.dependent_due<=p_as_of,
          'estimated_minutes',r.estimated_minutes,
          'condition',r.condition,
          'release_reason','bed_readiness_deadline_pressure',
          'day_order',600,
          'day_work_order',600,
          'run_sheet_order',600
        ),
        'action_key','weed',
        'work_class','standard',
        'visibility_scope','assigned_worker',
        'assigned_membership_id',v_anna,
        'task_series_key','bed-readiness:'||r.maintenance_object_id::text,
        'engine_instance_key','bed-readiness:'||r.maintenance_object_id::text||':'||r.dependent_due::text
      ),
      jsonb_build_object(
        'task_objects',jsonb_build_array(jsonb_build_object('object_id',r.object_id,'role','target'))
      ),
      jsonb_build_object('maintenance_object_id',r.maintenance_object_id,'deadline_pressure',true),
      p_as_of-14,
      jsonb_build_object(
        'planned_by','ensure_due_bed_readiness_weeding_v1',
        'maintenance_object_id',r.maintenance_object_id,
        'dependent_due_date',r.dependent_due,
        'bed_ready_by_date',r.ready_by
      )
    );

    perform atlas.enqueue_anna_weeding_deadline_occurrence_v1(v_occurrence_id,r.maintenance_object_id);
    v_count:=v_count+1;
  end loop;

  if v_count>0 then
    perform atlas.release_eligible_work_v1(p_farm_id,p_as_of,null);
    perform atlas.reconcile_anna_serial_weeding_v1(p_farm_id);
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,'anna_weeding_rotation');
  end if;

  return v_count;
end;
$function$;

create or replace function atlas.worker_next_up_v2(p_farm_id uuid, p_membership_id uuid, p_day date default null::date)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_day date:=coalesce(p_day,(now() at time zone 'America/Chicago')::date);
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_local_now timestamp:=(now() at time zone 'America/Chicago');
  v_current_daypart text;
  v_capacity jsonb;
  v_capacity_known boolean:=false;
  v_planned_capacity integer:=0;
  v_recovery_capacity integer:=0;
  v_placed_minutes integer:=0;
  v_remaining_planned integer:=0;
  v_remaining_recovery integer:=0;
  v_candidate_ids uuid[]:=array[]::uuid[];
  v_candidate_preview jsonb:='[]'::jsonb;
  v_candidate_count integer:=0;
  v_protected_count integer:=0;
  v_unresolved_consequence_count integer:=0;
  v_unestimated_count integer:=0;
  v_readiness_attention jsonb:='[]'::jsonb;
  v_readiness_attention_count integer:=0;
  v_blocked_protected_count integer:=0;
  v_current_reservation jsonb;
  v_task_id uuid;
  v_task atlas.tasks%rowtype;
  v_traits jsonb;
  v_consequence jsonb;
  v_protected jsonb;
  v_capacity_plan record;
  v_expected integer;
  v_is_protected boolean;
  v_fragmentation text;
  v_allowed integer;
  v_recommended integer;
  v_selected jsonb;
  v_selected_capacity_class text;
  v_state text;
  v_blocker text;
  v_ordering_ready boolean;
begin
  if not exists(
    select 1 from atlas.farm_memberships fm
    where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true and fm.role='farm_hand'
  ) then raise exception 'Active Farm Hand membership required.' using errcode='P0002'; end if;

  v_current_daypart:=case
    when v_local_now::time < time '12:00' then 'morning'
    when v_local_now::time < time '17:00' then 'afternoon'
    else 'evening'
  end;

  v_capacity:=atlas.worker_week_day_capacity_v1(p_farm_id,p_membership_id,v_day);
  v_capacity_known:=coalesce((v_capacity->>'capacityKnown')::boolean,false);
  if coalesce(v_capacity->>'plannedCapacityMinutes','') ~ '^[0-9]+$' then v_planned_capacity:=(v_capacity->>'plannedCapacityMinutes')::integer; end if;
  if coalesce(v_capacity->>'recoveryCapacityMinutes','') ~ '^[0-9]+$' then v_recovery_capacity:=(v_capacity->>'recoveryCapacityMinutes')::integer; end if;

  select coalesce(sum(coalesce(p.planned_duration_minutes,cp.expected_active_minutes,0)),0)::integer
  into v_placed_minutes
  from atlas.worker_day_task_placements p
  join atlas.tasks t on t.id=p.task_id
  cross join lateral atlas.task_capacity_plan_v1(t,v_day) cp
  where p.farm_id=p_farm_id and p.membership_id=p_membership_id and p.service_date=v_day and p.state='placed'
    and t.status in ('open','blocked');

  v_remaining_planned:=greatest(v_planned_capacity-v_placed_minutes,0);
  v_remaining_recovery:=greatest(v_planned_capacity+v_recovery_capacity-v_placed_minutes,0);

  if v_day=v_today then
    select jsonb_build_object('blockKind',b.block_kind,'blockId',b.block_id,'title',b.title,'startsAt',b.starts_at,'endsAt',b.ends_at,'source',b.source)
    into v_current_reservation
    from atlas.member_day_capacity_blocks_v1(p_farm_id,p_membership_id,v_day) b
    where now()>=b.starts_at and now()<b.ends_at
    order by b.starts_at,b.ends_at limit 1;
  end if;

  with candidate_base as (
    select
      t.id as task_id,t.title,t.status,t.due_date,t.work_lane,t.commitment_kind,t.priority,t.action_key,t.task_type,t.metadata,t.planned_occurrence_id,
      o.state as occurrence_state,o.source_kind,o.planned_due_date,o.not_before_date,o.earliest_lawful_date,o.preferred_start_date,o.preferred_end_date,o.latest_lawful_date,o.hard_finish_date,
      atlas.task_clock_function_traits_v2(t.id,v_day) as traits,
      atlas.task_effective_delay_consequence_v1(t.id,v_day) as consequence,
      atlas.task_protected_farm_minimum_v1(t.id,v_day) as protected_minimum,
      atlas.task_operation_contract_v1(t.id,p_membership_id,v_day) as operation_contract,
      atlas.task_capacity_plan_v1(t,v_day) as capacity,
      exists(select 1 from atlas.worker_day_task_placements p where p.farm_id=p_farm_id and p.membership_id=p_membership_id and p.service_date=v_day and p.task_id=t.id and p.state='placed') as placed_today,
      (coalesce(t.commitment_kind,'')='hard_date' or lower(coalesce(t.metadata->>'date_behavior',''))='hard_date' or lower(coalesce(t.metadata->>'date_commitment',''))='hard_date' or lower(coalesce(t.metadata->>'calendar_commitment_kind',''))='owner_hard_date') as hard_date_contract
    from atlas.tasks t
    left join atlas.planned_work_occurrences o on o.id=t.planned_occurrence_id
    where t.farm_id=p_farm_id and t.assigned_membership_id=p_membership_id and t.task_scope='farm_operation' and t.status in ('open','blocked')
      and t.parent_task_id is null and nullif(t.metadata->>'parent_task_id','') is null
      and lower(coalesce(t.metadata->>'is_child_task','false')) not in ('true','yes','1')
      and lower(coalesce(t.metadata->>'personal_task','false')) not in ('true','yes','1')
      and lower(coalesce(t.metadata->>'paid_work','true')) not in ('false','no','0')
      and coalesce(t.visibility_scope,'')<>'system_internal'
  ), temporally_lawful as (
    select c.*
    from candidate_base c
    where (c.planned_occurrence_id is null or c.occurrence_state='released')
      and (c.not_before_date is null or c.not_before_date<=v_day)
      and (c.earliest_lawful_date is null or c.earliest_lawful_date<=v_day)
      and (c.latest_lawful_date is null or c.latest_lawful_date>=v_day)
      and (c.hard_finish_date is null or c.hard_finish_date>=v_day)
      and (
        c.placed_today
        or case
          when c.due_date is not null then c.due_date<=v_day
          when c.planned_due_date is not null then c.planned_due_date<=v_day
          else c.work_lane in ('required','process_continuation','rhythm')
        end
      )
  ), executable as (
    select t.* from temporally_lawful t
    where t.status='open'
      and coalesce(t.operation_contract->>'executionDisposition','')='warranted'
      and not (t.hard_date_contract and t.due_date is not null and t.due_date<v_day and not t.placed_today)
  ), blocked as (
    select t.* from temporally_lawful t
    where t.status='blocked'
       or coalesce(t.operation_contract->>'executionDisposition','')<>'warranted'
       or (t.hard_date_contract and t.due_date is not null and t.due_date<v_day and not t.placed_today)
  ), ranked as (
    select e.*,
      coalesce((e.protected_minimum->>'protectedFarmMinimum')::boolean,false) as is_protected,
      coalesce((e.consequence->>'needsConsequenceResolution')::boolean,true) as consequence_unresolved,
      case when coalesce(e.consequence->>'effectiveTier','') ~ '^[1-6]$' then (e.consequence->>'effectiveTier')::integer else null end as consequence_tier,
      (e.capacity).expected_active_minutes as expected_minutes,
      row_number() over(order by
        case when e.placed_today then 0 else 1 end,
        case when coalesce((e.protected_minimum->>'protectedFarmMinimum')::boolean,false) then 0 else 1 end,
        case when v_day=v_today and e.traits->>'dayWindow'=v_current_daypart then 0 else 1 end,
        case when coalesce(e.consequence->>'effectiveTier','') ~ '^[1-6]$' then (e.consequence->>'effectiveTier')::integer else 99 end,
        e.hard_finish_date nulls last,e.latest_lawful_date nulls last,e.due_date nulls last,
        case e.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 when 'low' then 3 else 4 end,e.title,e.task_id
      ) as rank_order
    from executable e
  )
  select
    coalesce((select array_agg(r.task_id order by r.rank_order) from ranked r),array[]::uuid[]),
    coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'rank',r.rank_order,'taskId',r.task_id,'title',r.title,'dueDate',r.due_date,'workLane',r.work_lane,'commitmentKind',r.commitment_kind,
      'placedToday',r.placed_today,'protectedFarmMinimum',r.is_protected,'protectedCategory',r.protected_minimum->>'category',
      'consequenceTier',r.consequence_tier,'consequenceClass',r.consequence->>'effectiveClass','consequenceNeedsResolution',r.consequence_unresolved,
      'expectedActiveMinutes',r.expected_minutes,'dayWindow',r.traits->>'dayWindow','environment',r.traits->>'environment',
      'physicalLoad',(r.capacity).physical_load,'fragmentation',r.traits->>'fragmentation','interruptibility',r.traits->>'interruptibility',
      'operationClass',r.traits->>'operationClass','plannedOccurrenceId',r.planned_occurrence_id,'occurrenceSourceKind',r.source_kind
    )) order by r.rank_order) from ranked r),'[]'::jsonb),
    (select count(*)::integer from ranked),
    (select count(*)::integer from ranked where is_protected),
    (select count(*)::integer from ranked where consequence_unresolved),
    (select count(*)::integer from ranked where expected_minutes<=0),
    coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'taskId',b.task_id,'title',b.title,'status',b.status,'dueDate',b.due_date,'commitmentKind',b.commitment_kind,
      'attentionReason',case
        when b.hard_date_contract and b.due_date is not null and b.due_date<v_day and not b.placed_today then 'missed_hard_date'
        when b.status='blocked' then 'task_blocked'
        else 'execution_not_ready'
      end,
      'protectedFarmMinimum',b.protected_minimum->'protectedFarmMinimum',
      'protectedCategory',b.protected_minimum->>'category','executionReadiness',atlas.task_execution_readiness_v1(b.task_id),
      'operationClass',b.traits->>'operationClass','dayWindow',b.traits->>'dayWindow','environment',b.traits->>'environment'
    )) order by
      case when b.hard_date_contract and b.due_date is not null and b.due_date<v_day and not b.placed_today then 0 else 1 end,
      coalesce((b.protected_minimum->>'protectedFarmMinimum')::boolean,false) desc,b.due_date nulls last,b.title) from blocked b),'[]'::jsonb),
    (select count(*)::integer from blocked),
    (select count(*)::integer from blocked where coalesce((protected_minimum->>'protectedFarmMinimum')::boolean,false))
  into v_candidate_ids,v_candidate_preview,v_candidate_count,v_protected_count,v_unresolved_consequence_count,v_unestimated_count,
       v_readiness_attention,v_readiness_attention_count,v_blocked_protected_count;

  v_ordering_ready:=v_unresolved_consequence_count=0;

  if v_current_reservation is not null then
    v_state:='human_time_reserved_now'; v_blocker:='A capacity-blocking human-time reservation is active now.';
  elsif not v_capacity_known then
    v_state:='capacity_anchor_required'; v_blocker:='Owner-authored Worker Day Shape is required before Next Up may claim executable capacity.';
  elsif coalesce(v_capacity->>'capacityClass','unknown') in ('unavailable','none') or (v_planned_capacity+v_recovery_capacity)<=0 then
    v_state:='worker_unavailable'; v_blocker:='No worker capacity is available on this service date.';
  elsif v_candidate_count=0 and v_readiness_attention_count>0 then
    v_state:='readiness_resolution_required'; v_blocker:='Work is due, but execution readiness or missed-commitment custody requires resolution.';
  elsif v_candidate_count=0 then
    v_state:='no_lawful_work';
  elsif not v_ordering_ready then
    v_state:='consequence_resolution_required'; v_blocker:='At least one executable candidate has unresolved consequence-of-delay, so Atlas will not manufacture a relative priority.';
  else
    foreach v_task_id in array v_candidate_ids loop
      select * into v_task from atlas.tasks where id=v_task_id;
      v_traits:=atlas.task_clock_function_traits_v2(v_task_id,v_day);
      v_consequence:=atlas.task_effective_delay_consequence_v1(v_task_id,v_day);
      v_protected:=atlas.task_protected_farm_minimum_v1(v_task_id,v_day);
      select * into v_capacity_plan from atlas.task_capacity_plan_v1(v_task,v_day);
      v_expected:=coalesce(v_capacity_plan.expected_active_minutes,0);
      v_is_protected:=coalesce((v_protected->>'protectedFarmMinimum')::boolean,false);
      v_fragmentation:=v_traits->>'fragmentation';
      if v_protected_count>0 and not v_is_protected then continue; end if;
      if v_expected<=0 then v_state:='work_estimate_required'; v_blocker:='The highest-authority executable lane contains work with no active-time estimate.'; exit; end if;
      if v_is_protected then v_allowed:=v_remaining_recovery; else v_allowed:=v_remaining_planned; end if;
      if v_allowed<=0 then continue; end if;
      if v_fragmentation='should_not_fragment' and v_expected>v_allowed then continue; end if;
      v_recommended:=case when v_fragmentation='can_fragment' then least(v_expected,v_allowed) else v_expected end;
      if v_recommended<=0 then continue; end if;
      v_selected_capacity_class:=case when v_recommended<=v_remaining_planned then 'planned' else 'recovery' end;
      v_selected:=jsonb_strip_nulls(jsonb_build_object(
        'taskId',v_task.id,'title',v_task.title,'dueDate',v_task.due_date,'workLane',v_task.work_lane,'commitmentKind',v_task.commitment_kind,
        'expectedActiveMinutes',v_expected,'recommendedBlockMinutes',v_recommended,'fragmented',v_recommended<v_expected,
        'capacityClass',v_selected_capacity_class,'protectedFarmMinimum',v_is_protected,'protectedCategory',v_protected->>'category',
        'consequenceTier',case when coalesce(v_consequence->>'effectiveTier','') ~ '^[1-6]$' then (v_consequence->>'effectiveTier')::integer else null end,
        'consequenceClass',v_consequence->>'effectiveClass','operationClass',v_traits->>'operationClass','traitKeys',v_traits->'traitKeys',
        'dayWindow',v_traits->>'dayWindow','environment',v_traits->>'environment','physicalLoad',v_capacity_plan.physical_load,
        'fragmentation',v_traits->>'fragmentation','interruptibility',v_traits->>'interruptibility',
        'executionDo',nullif(v_task.metadata->>'execution_do',''),'executionDoneWhen',nullif(v_task.metadata->>'execution_done_when','')
      ));
      v_state:='ready'; exit;
    end loop;
    if v_state is null then v_state:='capacity_conflict'; v_blocker:='Lawful work exists, but no highest-authority candidate fits remaining lawful capacity without violating its fragmentation contract.'; end if;
  end if;

  return jsonb_build_object(
    'contractVersion','worker_next_up_v2','farmId',p_farm_id,'membershipId',p_membership_id,'serviceDate',v_day,
    'state',v_state,'blocker',v_blocker,'nextUp',v_selected,'candidateCount',v_candidate_count,'protectedCandidateCount',v_protected_count,
    'unresolvedConsequenceCandidateCount',v_unresolved_consequence_count,'unestimatedCandidateCount',v_unestimated_count,
    'candidateOrderingReady',v_ordering_ready,'candidatePreview',v_candidate_preview,
    'readinessAttentionCount',v_readiness_attention_count,'blockedProtectedReadinessCount',v_blocked_protected_count,'readinessAttention',v_readiness_attention,
    'capacity',v_capacity,'placedMinutes',v_placed_minutes,
    'remainingPlannedMinutes',case when v_capacity_known then v_remaining_planned else null end,
    'remainingRecoveryInclusiveMinutes',case when v_capacity_known then v_remaining_recovery else null end,
    'currentHumanTimeReservation',v_current_reservation,'currentDaypart',case when v_day=v_today then v_current_daypart else null end,
    'failClosedOnUnknownCapacity',true,'failClosedOnUnresolvedConsequenceOrdering',true,'taskDueDatePrecedesHistoricalOccurrenceTarget',true,
    'unresolvedWorkCustodyInvariant','open_or_blocked_due_work_routes_to_candidate_or_attention'
  );
end;
$function$;

update atlas.work_release_policies
set maximum_active_instances=99,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'concurrencyRepair','mowing_routes_must_not_suppress_each_other',
      'concurrencyRepairAt',now(),
      'presentationStillCapacityGoverned',true
    ),updated_at=now()
where farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and stable_key='rhythm:mowing:due:immediate';

create or replace function atlas.reorder_anna_deadline_weeding_queue_v1(p_farm_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_ids uuid[]:=array[]::uuid[];
  v_positions integer[]:=array[]::integer[];
  v_count integer:=0;
  v_offset integer:=0;
  i integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':anna_weeding_rotation',0));

  select coalesce(array_agg(qi.id order by
      coalesce(mo.owner_priority,0) desc,
      coalesce(mo.planting_block_score,0) desc,
      coalesce(nullif(o.task_payload->'metadata'->>'blocking_task_count','')::integer,0) desc,
      nullif(o.metadata->>'dependent_due_date','')::date asc nulls last,
      o.title,
      qi.id
    ),array[]::uuid[]),
    count(*)::integer
  into v_ids,v_count
  from atlas.task_release_queue_items qi
  join atlas.planned_work_occurrences o on o.id=qi.planned_occurrence_id
  left join atlas.maintenance_objects mo on mo.id=qi.maintenance_object_id
  where qi.farm_id=p_farm_id
    and qi.queue_key='anna_weeding_rotation'
    and qi.state='queued'
    and qi.metadata->>'source'='bed_readiness_deadline_pressure';

  if v_count<=1 then
    return jsonb_build_object('reordered',0,'deadlineQueueCount',v_count);
  end if;

  select array_agg(qi.position order by qi.position)
  into v_positions
  from atlas.task_release_queue_items qi
  where qi.id=any(v_ids);

  select coalesce(max(position),0)+1000000 into v_offset
  from atlas.task_release_queue_items
  where farm_id=p_farm_id and queue_key='anna_weeding_rotation';

  for i in 1..v_count loop
    update atlas.task_release_queue_items
    set position=v_offset+i,updated_at=now()
    where id=v_ids[i];
  end loop;

  for i in 1..v_count loop
    update atlas.task_release_queue_items
    set position=v_positions[i],
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'deadlineQueueReorderedAt',now(),
          'deadlineQueueRank',i,
          'deadlineQueueOrdering','owner_priority_then_planting_pressure_then_unlock_count'
        ),
        updated_at=now()
    where id=v_ids[i];
  end loop;

  perform atlas.sync_task_release_queue_summary_v1(p_farm_id,'anna_weeding_rotation');
  return jsonb_build_object('reordered',v_count,'deadlineQueueCount',v_count,'headQueueItemId',v_ids[1]);
end;
$function$;

revoke all on function atlas.reorder_anna_deadline_weeding_queue_v1(uuid) from public,anon,authenticated;

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
      mo.owner_priority,
      mo.planting_block_score,
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
    group by mo.id,mo.object_id,mo.zone_id,mo.condition,mo.owner_priority,mo.planting_block_score,
      mo.remaining_effort_minutes,mo.current_effort_minutes,mo.maintenance_effort_minutes,go.stable_key,go.label,z.label
    having min(nullif(md.metadata->>'ready_by_date','')::date)<=p_as_of
    order by
      coalesce(mo.owner_priority,0) desc,
      coalesce(mo.planting_block_score,0) desc,
      count(distinct t.id) desc,
      min(t.due_date),
      go.label
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
          work_lane='required',
          commitment_kind='dependency',
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
      update atlas.planned_work_occurrences o
      set work_lane='required',
          commitment_kind='dependency',
          metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object(
            'dependencyReleaseClassifiedAt',now(),
            'dependencyReleaseReason','bed_readiness_deadline_pressure'
          ),
          updated_at=now()
      from atlas.task_release_queue_items qi
      where qi.farm_id=p_farm_id
        and qi.queue_key='anna_weeding_rotation'
        and qi.maintenance_object_id=r.maintenance_object_id
        and qi.state in ('active','queued')
        and qi.planned_occurrence_id=o.id
        and o.source_kind='maintenance_weeding_bed_readiness'
        and o.source_id=r.maintenance_object_id;
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

    update atlas.planned_work_occurrences
    set work_lane='required',
        commitment_kind='dependency',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'dependencyReleaseClassifiedAt',now(),
          'dependencyReleaseReason','bed_readiness_deadline_pressure'
        ),
        updated_at=now()
    where id=v_occurrence_id;

    perform atlas.enqueue_anna_weeding_deadline_occurrence_v1(v_occurrence_id,r.maintenance_object_id);
    v_count:=v_count+1;
  end loop;

  perform atlas.reorder_anna_deadline_weeding_queue_v1(p_farm_id);

  if v_count>0 or exists(
    select 1 from atlas.task_release_queue_items qi
    where qi.farm_id=p_farm_id and qi.queue_key='anna_weeding_rotation'
      and qi.state='queued' and qi.metadata->>'source'='bed_readiness_deadline_pressure'
  ) then
    perform atlas.release_eligible_work_v1(p_farm_id,p_as_of,null);
    perform atlas.reconcile_anna_serial_weeding_v1(p_farm_id);
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,'anna_weeding_rotation');
  end if;

  return v_count;
end;
$function$;

update atlas.planned_work_occurrences o
set work_lane='required',
    commitment_kind='dependency',
    metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object(
      'dependencyReleaseClassifiedAt',now(),
      'dependencyReleaseReason','bed_readiness_deadline_pressure'
    ),
    updated_at=now()
where o.farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and o.source_kind='maintenance_weeding_bed_readiness'
  and o.state in ('planned','eligible','released');

select atlas.reorder_anna_deadline_weeding_queue_v1('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid);

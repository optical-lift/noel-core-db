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

  update atlas.planned_work_occurrences
  set work_lane='required',
      commitment_kind='dependency',
      miss_consequence=jsonb_build_object(
        'tier',3,
        'class','prerequisite_unlock',
        'source','bed_readiness_deadline_pressure',
        'reason','Delaying this bed-preparation work keeps represented downstream planting work blocked.'
      ),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'dependencyReleaseClassifiedAt',now(),
        'dependencyReleaseReason','bed_readiness_deadline_pressure',
        'missConsequenceClassifiedAt',now()
      ),
      updated_at=now()
  where id=v_occ.id
  returning * into v_occ;

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

update atlas.planned_work_occurrences
set miss_consequence=jsonb_build_object(
      'tier',3,
      'class','prerequisite_unlock',
      'source','bed_readiness_deadline_pressure',
      'reason','Delaying this bed-preparation work keeps represented downstream planting work blocked.'
    ),
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('missConsequenceClassifiedAt',now()),
    updated_at=now()
where farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and source_kind='maintenance_weeding_bed_readiness'
  and state in ('planned','eligible','released');
begin;

-- Atlas may enqueue a governed Weed Card occurrence before its execution Task
-- is materialized. The serial capture trigger must still instrument that Task
-- so its completion can cross the predecessor-completion boundary and advance
-- Anna's one-card-at-a-time weeding queue.

create or replace function atlas.capture_anna_weeding_serial_queue_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_worker_key text;
  v_queue_key constant text := 'anna_weeding_rotation';
  v_position integer;
  v_existing_item atlas.task_release_queue_items%rowtype;
  v_active_item atlas.task_release_queue_items%rowtype;
  v_active_task atlas.tasks%rowtype;
  v_incoming_maintenance_id uuid;
  v_active_maintenance_id uuid;
  v_max_position integer;
  v_promote boolean := false;
  v_deferral_result text;
begin
  if pg_trigger_depth()>1 then return new; end if;
  if new.status not in ('open','blocked') then return new; end if;
  if lower(coalesce(new.metadata->>'weed_card_managed','false')) not in ('true','yes','1') then return new; end if;
  if lower(coalesce(new.metadata->>'persistent_weed_card','false')) not in ('true','yes','1') then return new; end if;
  if lower(coalesce(new.metadata->>'serial_queue_bypass','false')) in ('true','yes','1') then return new; end if;
  if nullif(new.metadata->>'sequence_key','') is not null then return new; end if;

  select fm.worker_key into v_worker_key
  from atlas.farm_memberships fm
  where fm.id=new.assigned_membership_id and fm.active=true;
  if v_worker_key is distinct from 'anna' then return new; end if;

  perform pg_advisory_xact_lock(hashtextextended(new.farm_id::text||':'||v_queue_key,0));

  v_incoming_maintenance_id:=case
    when coalesce(new.metadata->>'maintenance_object_id','') ~* '^[0-9a-f-]{36}$'
      then (new.metadata->>'maintenance_object_id')::uuid
    else null end;

  select qi.* into v_existing_item
  from atlas.task_release_queue_items qi
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key
    and (qi.task_id=new.id or qi.planned_occurrence_id=new.planned_occurrence_id)
  order by qi.position
  limit 1
  for update;

  if v_existing_item.id is not null then
    v_position:=v_existing_item.position;

    if v_existing_item.state='active' and v_existing_item.task_id is null then
      update atlas.task_release_queue_items
      set task_id=new.id,
          maintenance_object_id=coalesce(maintenance_object_id,v_incoming_maintenance_id),
          activated_at=coalesce(activated_at,now()),
          updated_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'executionCarrierAttachedAt',now(),
            'executionCarrierAttachedBy','capture_anna_weeding_serial_queue_v1'
          )
      where id=v_existing_item.id;
    end if;

    update atlas.tasks
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'release_queue_key',v_queue_key,
      'release_queue_position',v_position,
      'release_queue_policy','completion_gated_serial',
      'weed_serial_gate',true,
      'release_queue_need_aware',true,
      'release_queue_pre_enqueued',true
    ),updated_at=now()
    where id=new.id;

    perform atlas.sync_task_release_queue_summary_v1(new.farm_id,v_queue_key);
    return new;
  end if;

  update atlas.task_release_queue_items qi
  set state='queued',task_id=null,activated_at=null,updated_at=now(),
      metadata=coalesce(qi.metadata,'{}'::jsonb)||jsonb_build_object('demoted_stale_active_at',now())
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key and qi.state='active'
    and not exists(
      select 1 from atlas.tasks t
      where t.id=qi.task_id and t.status in ('open','blocked') and t.action_key='weed'
    );

  select qi.* into v_active_item
  from atlas.task_release_queue_items qi
  join atlas.tasks t on t.id=qi.task_id
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key and qi.state='active'
    and t.status in ('open','blocked') and t.action_key='weed'
  order by qi.position
  limit 1
  for update of qi;

  select coalesce(max(qi.position),0) into v_max_position
  from atlas.task_release_queue_items qi
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key;

  if v_active_item.id is null then
    v_position:=v_max_position+1;
    insert into atlas.task_release_queue_items(
      farm_id,queue_key,task_id,planned_occurrence_id,maintenance_object_id,
      position,state,initial_batch,original_due_date,activated_at,metadata
    ) values (
      new.farm_id,v_queue_key,new.id,new.planned_occurrence_id,v_incoming_maintenance_id,
      v_position,'active',false,new.due_date,now(),
      jsonb_build_object('source','anna_weeding_serial_gate','captured_at',now(),'policy','completion_gated_serial','need_aware',true)
    );
  else
    select * into v_active_task from atlas.tasks where id=v_active_item.task_id for update;
    v_active_maintenance_id:=coalesce(
      v_active_item.maintenance_object_id,
      case when coalesce(v_active_task.metadata->>'maintenance_object_id','') ~* '^[0-9a-f-]{36}$'
        then (v_active_task.metadata->>'maintenance_object_id')::uuid else null end
    );
    v_promote:=atlas.weeding_need_precedes_v1(v_incoming_maintenance_id,v_active_maintenance_id);

    if v_promote then
      v_position:=v_active_item.position;

      update atlas.task_release_queue_items
      set position=v_max_position+1,
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'yielded_to_higher_need_at',now(),
            'yielded_to_task_id',new.id,
            'yielded_to_maintenance_object_id',v_incoming_maintenance_id
          ),
          updated_at=now()
      where id=v_active_item.id;

      v_deferral_result:=atlas.defer_existing_task_to_occurrence_v1(
        v_active_task.id,
        'Yielded to a higher-need Weed Card in Anna serial weeding.'
      );

      insert into atlas.task_release_queue_items(
        farm_id,queue_key,task_id,planned_occurrence_id,maintenance_object_id,
        position,state,initial_batch,original_due_date,activated_at,metadata
      ) values (
        new.farm_id,v_queue_key,new.id,new.planned_occurrence_id,v_incoming_maintenance_id,
        v_position,'active',false,new.due_date,now(),
        jsonb_build_object(
          'source','anna_weeding_serial_gate','captured_at',now(),'policy','completion_gated_serial',
          'need_aware',true,'promoted_over_task_id',v_active_task.id,
          'promoted_over_maintenance_object_id',v_active_maintenance_id,
          'displaced_task_deferral_result',v_deferral_result
        )
      );
    else
      v_position:=v_max_position+1;
      insert into atlas.task_release_queue_items(
        farm_id,queue_key,task_id,planned_occurrence_id,maintenance_object_id,
        position,state,initial_batch,original_due_date,metadata
      ) values (
        new.farm_id,v_queue_key,new.id,new.planned_occurrence_id,v_incoming_maintenance_id,
        v_position,'queued',false,new.due_date,
        jsonb_build_object('source','anna_weeding_serial_gate','captured_at',now(),'policy','completion_gated_serial','need_aware',true)
      );
    end if;
  end if;

  update atlas.tasks
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'release_queue_key',v_queue_key,
    'release_queue_position',v_position,
    'release_queue_policy','completion_gated_serial',
    'weed_serial_gate',true,
    'release_queue_need_aware',true,
    'release_queue_promoted_by_need',v_promote
  ),updated_at=now()
  where id=new.id;

  if v_active_item.id is not null and not v_promote then
    perform atlas.defer_existing_task_to_occurrence_v1(
      new.id,
      'Waiting behind a higher- or equal-need Anna Weed Card.'
    );
  end if;

  perform atlas.sync_task_release_queue_summary_v1(new.farm_id,v_queue_key);
  return new;
end;
$function$;

commit;

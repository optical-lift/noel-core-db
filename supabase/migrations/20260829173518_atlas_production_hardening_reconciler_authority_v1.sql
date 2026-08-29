create or replace function atlas.record_production_hardening_v1(
  p_task_id uuid,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_lot_id uuid;
  v_batch atlas.production_tray_batches%rowtype;
  v_batch_id uuid;
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_readiness_occurrence_id uuid;
  v_readiness_date date;
  v_key text;
  v_existing_event uuid;
  v_reconcile jsonb;
begin
  if p_task_id is null or p_observed_date is null then
    raise exception 'Hardening task and observed date are required.' using errcode='22023';
  end if;

  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'production-hardening:'||p_task_id::text||':'||p_observed_date::text);

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  if lower(coalesce(v_task.action_key,'')) not in ('hardening_off','harden','hardening')
     and lower(coalesce(v_task.task_type,'')) not in ('hardening_off','hardening') then
    raise exception 'Task is not a governed hardening operation.' using errcode='23514';
  end if;

  select plt.production_lot_id,
         coalesce(v_task.generated_from_id,nullif(plt.metadata->>'tray_batch_id','')::uuid)
  into v_lot_id,v_batch_id
  from atlas.production_lot_tasks plt
  where plt.task_id=p_task_id and plt.link_role='hardening'
  order by plt.created_at desc limit 1;

  if v_lot_id is null or v_batch_id is null then
    raise exception 'Hardening task is missing production lot or tray-batch lineage.' using errcode='23514';
  end if;

  select * into v_lot from atlas.production_lots where id=v_lot_id for update;
  select * into v_batch from atlas.production_tray_batches where id=v_batch_id and production_lot_id=v_lot.id for update;
  if v_batch.id is null or v_batch.status not in ('seedling_care','hardening') then
    raise exception 'Hardening task is missing an eligible seedling tray batch.' using errcode='23514';
  end if;

  select * into v_cycle from atlas.crop_cycles where id=v_batch.crop_cycle_id for update;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;

  select id into v_existing_event
  from atlas.production_lot_events
  where farm_id=v_lot.farm_id and idempotency_key=v_key||':event';

  if v_existing_event is not null then
    return jsonb_build_object(
      'contractVersion','record_production_hardening_v1',
      'applied',false,
      'state','already_applied',
      'taskId',p_task_id,
      'productionLotId',v_lot.id,
      'trayBatchId',v_batch.id,
      'eventId',v_existing_event
    );
  end if;

  if v_task.status not in ('open','blocked') then
    raise exception 'Hardening task is not actionable.' using errcode='23514';
  end if;

  update atlas.production_tray_batches
  set status='hardening',
      last_action_at=now(),
      last_observed_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'hardening_started_date',p_observed_date,
        'hardening_task_id',p_task_id,
        'hardening_note',p_note
      ),
      updated_at=now()
  where id=v_batch.id;

  update atlas.production_lots
  set current_stage='hardening',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'last_biological_event','hardening_started',
        'hardening_started_date',p_observed_date,
        'hardening_task_id',p_task_id
      ),
      updated_at=now()
  where id=v_lot.id;

  if v_cycle.id is not null then
    update atlas.crop_cycles
    set cycle_state='hardening_off',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'hardening_started_date',p_observed_date,
          'hardening_task_id',p_task_id,
          'production_tray_batch_id',v_batch.id
        ),
        updated_at=now()
    where id=v_cycle.id;
  end if;

  insert into atlas.production_lot_events(
    farm_id,production_lot_id,tray_batch_id,crop_cycle_id,task_id,event_type,event_date,
    quantity,unit,note,idempotency_key,source,metadata
  ) values(
    v_lot.farm_id,v_lot.id,v_batch.id,v_batch.crop_cycle_id,p_task_id,'hardening_started',p_observed_date,
    v_batch.current_quantity,coalesce(v_batch.current_unit,'seedlings'),p_note,v_key||':event',
    'record_production_hardening_v1',
    jsonb_build_object(
      'containerKind',v_batch.container_kind,
      'trayCount',v_batch.tray_count,
      'potUpRequired',false,
      'readinessCue',v_profile.metadata->>'transplant_readiness_cue',
      'successorAuthority','production_reconciler'
    )
  );

  -- The biological result above is authoritative. Successor work belongs to the
  -- state-derived reconciler, which also creates tenant-local work definitions and
  -- release policies through the production authoring membrane when necessary.
  v_reconcile:=atlas.reconcile_production_work_v1(v_lot.id,p_observed_date);

  select id,planned_due_date
  into v_readiness_occurrence_id,v_readiness_date
  from atlas.planned_work_occurrences
  where farm_id=v_lot.farm_id
    and occurrence_key='production:transplant-readiness:'||v_batch.id::text
    and state<>'cancelled'
  order by created_at desc
  limit 1;

  if v_readiness_occurrence_id is null then
    raise exception 'Production reconciler did not derive transplant readiness after hardening.' using errcode='23514';
  end if;

  perform atlas.record_task_transition_v1_internal(
    p_task_id,'done',v_key||':task',null,p_note,
    'Hardening start was recorded before the task completed.',
    'hardening_off','production_hardening',
    jsonb_build_object(
      'production_lot_id',v_lot.id,
      'tray_batch_id',v_batch.id,
      'hardening_started_date',p_observed_date,
      'readiness_occurrence_id',v_readiness_occurrence_id,
      'readiness_due_date',v_readiness_date,
      'container_kind',v_batch.container_kind,
      'pot_up_required',false,
      'successor_authority','production_reconciler'
    ),
    null
  );

  return jsonb_build_object(
    'contractVersion','record_production_hardening_v1',
    'applied',true,
    'state','hardening_started',
    'taskId',p_task_id,
    'productionLotId',v_lot.id,
    'trayBatchId',v_batch.id,
    'hardeningStartedDate',p_observed_date,
    'readinessOccurrenceId',v_readiness_occurrence_id,
    'readinessDueDate',v_readiness_date,
    'containerKind',v_batch.container_kind,
    'potUpRequired',false,
    'successorAuthority','production_reconciler'
  );
end;
$function$;

comment on function atlas.record_production_hardening_v1(uuid,date,text,text) is 'Records hardening biological truth only, then delegates successor derivation to the state-derived production reconciler. Does not depend on tenant-preseeded readiness work-definition rows and preserves the tray batch actual container kind.';
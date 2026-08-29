create or replace function atlas.record_production_readiness_v1(
  p_task_id uuid,
  p_action text,
  p_surviving_seedlings numeric,
  p_tray_count numeric,
  p_observed_date date,
  p_next_check_date date,
  p_note text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_obs atlas.production_readiness_observations%rowtype;
  v_rows numeric;
  v_spacing numeric;
  v_bed_feet numeric;
  v_req_id uuid;
  v_transition jsonb;
  v_gate jsonb;
  v_owner_task uuid;
  v_key text:=nullif(btrim(p_idempotency_key),'');
begin
  if p_task_id is null or p_action not in ('not_ready','ready','failed') or p_observed_date is null then
    raise exception 'Task, valid readiness action, and date are required' using errcode='22023';
  end if;
  if v_key is null or length(v_key)>120 then raise exception 'A valid readiness idempotency key is required' using errcode='22023'; end if;
  if p_observed_date>v_today+1 then raise exception 'Readiness date cannot be in the future' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  select pl.* into v_lot
  from atlas.production_lot_tasks plt
  join atlas.production_lots pl on pl.id=plt.production_lot_id
  where plt.task_id=p_task_id and plt.link_role='transplant_readiness'
  limit 1 for update of pl;
  if v_task.id is null or v_lot.id is null then raise exception 'Task is not a linked production readiness step' using errcode='22023'; end if;

  select * into v_batch
  from atlas.production_tray_batches
  where id=v_task.generated_from_id and production_lot_id=v_lot.id
  for update;
  if v_batch.id is null or v_batch.status not in ('seedling_care','hardening','transplant_ready') then
    raise exception 'Readiness task is missing its active tray batch' using errcode='22023';
  end if;

  select * into v_obs from atlas.production_readiness_observations where farm_id=v_lot.farm_id and idempotency_key=v_key;
  if v_obs.id is not null then
    return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'observationId',v_obs.id,'action',v_obs.observation_outcome,'deduplicated',true);
  end if;
  if v_task.status not in ('open','blocked') then raise exception 'Readiness task is not open' using errcode='22023'; end if;
  if p_action in ('not_ready','ready') and (p_surviving_seedlings is null or p_surviving_seedlings<=0) then raise exception 'A positive surviving seedling count is required' using errcode='22023'; end if;
  if p_action='failed' and coalesce(p_surviving_seedlings,0)<>0 then raise exception 'Failed seedling care must record zero survivors' using errcode='22023'; end if;
  if p_surviving_seedlings is not null and p_surviving_seedlings>coalesce(v_batch.current_quantity,v_batch.viable_seedlings,v_batch.seeds_sown) then raise exception 'Surviving seedling count exceeds the current tray cohort' using errcode='22023'; end if;
  if p_tray_count is not null and p_tray_count>v_batch.tray_count then raise exception 'Current tray count cannot exceed the prior tray count' using errcode='22023'; end if;

  insert into atlas.production_readiness_observations(
    farm_id,production_lot_id,tray_batch_id,task_id,observation_outcome,observed_date,
    surviving_seedlings,tray_count,confidence,note,idempotency_key,metadata
  ) values (
    v_lot.farm_id,v_lot.id,v_batch.id,p_task_id,p_action,p_observed_date,p_surviving_seedlings,p_tray_count,
    'counted',p_note,v_key,jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind)
  ) returning * into v_obs;

  if p_action='not_ready' then
    if p_next_check_date is null or p_next_check_date<=p_observed_date then raise exception 'A later next-check date is required when seedlings are not ready' using errcode='22023'; end if;
    update atlas.production_tray_batches
    set status=case when status='hardening' then 'hardening' else 'seedling_care' end,
        current_quantity=p_surviving_seedlings,current_unit='seedlings',tray_count=coalesce(p_tray_count,tray_count),
        metadata=metadata||jsonb_build_object('last_readiness_observation_id',v_obs.id,'next_readiness_check_date',p_next_check_date),updated_at=now()
    where id=v_batch.id;
    update atlas.production_lots
    set current_quantity=p_surviving_seedlings,current_unit='seedlings',
        current_stage=case when v_batch.status='hardening' then 'hardening' else 'seedling_care' end,
        metadata=metadata||jsonb_build_object('last_biological_event','transplant_not_ready','next_readiness_check_date',p_next_check_date),updated_at=now()
    where id=v_lot.id;
    insert into atlas.production_lot_events(
      farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata
    ) values (
      v_lot.farm_id,v_lot.id,'transplant_not_ready',p_observed_date,p_surviving_seedlings,'seedlings',p_task_id,v_batch.crop_cycle_id,p_note,
      'production_stage_engine',left(v_key||':event:not-ready',160),jsonb_build_object('readiness_observation_id',v_obs.id,'next_check_date',p_next_check_date,'container_kind',v_batch.container_kind)
    );
    v_transition:=atlas.record_task_transition_v1_internal(
      p_task_id,'rescheduled',left(v_key||':task:rescheduled',160),p_next_check_date,
      coalesce(nullif(btrim(p_note),''),'Seedlings are not transplant-ready yet.'),null,'observe','production_lot',
      jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'readiness_observation_id',v_obs.id,
        'surviving_seedlings',p_surviving_seedlings,'tray_count',coalesce(p_tray_count,v_batch.tray_count),'container_kind',v_batch.container_kind),null
    );
    return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'observationId',v_obs.id,'action','not_ready','nextCheckDate',p_next_check_date,'deduplicated',false);
  end if;

  if p_action='failed' then
    update atlas.production_tray_batches set status='failed',current_quantity=0,current_unit='seedlings',metadata=metadata||jsonb_build_object('last_readiness_observation_id',v_obs.id),updated_at=now() where id=v_batch.id;
    update atlas.production_lots set current_quantity=0,current_unit='seedlings',current_stage='seedling_failure_decision',metadata=metadata||jsonb_build_object('last_biological_event','seedling_care_failed'),updated_at=now() where id=v_lot.id;
    update atlas.crop_cycles set cycle_state='failed',lifecycle_status='archived',coverage_amount=0,coverage_unit='seedlings',metadata=metadata||jsonb_build_object('readiness_observation_id',v_obs.id),updated_at=now() where id=v_batch.crop_cycle_id;
    insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata)
    values(v_lot.farm_id,v_lot.id,'seedling_care_failed',p_observed_date,0,'seedlings',p_task_id,v_batch.crop_cycle_id,p_note,'production_stage_engine',left(v_key||':event:failed',160),jsonb_build_object('readiness_observation_id',v_obs.id));
    v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'done',left(v_key||':task:failed',160),null,coalesce(nullif(btrim(p_note),''),'No seedlings survived seedling care.'),null,'observe','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'readiness_observation_id',v_obs.id,'surviving_seedlings',0),null);
    insert into atlas.tasks(
      farm_id,title,task_type,status,priority,due_date,generated_from,generated_from_id,note,metadata,action_key,work_class,
      task_series_key,engine_instance_key,visibility_scope,organization_id,origin_kind,task_scope,work_lane,commitment_kind
    ) values (
      v_lot.farm_id,'Owner — Decide recovery for '||v_lot.lot_label,'owner_decision','open','high',p_observed_date,
      'production_tray_batch',v_batch.id,'The seedling cohort failed before transplant. Decide whether to reseed, replace, buy plugs, or cancel.',
      jsonb_build_object('task_key','production_seedling_failure_decision_'||v_batch.id::text,'owner_task',true,'anna_task',false,
        'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,
        'display_action','Decide','display_subject',v_lot.lot_label||' recovery','display_detail','0 surviving seedlings','collection_zone','Owner'),
      'decide','light','production-lot:'||v_lot.stable_key||':seedling-failure','production-seedling-failure:'||v_batch.id::text,'owner',
      v_task.organization_id,'generated','farm_operation','required','dependency'
    ) returning id into v_owner_task;
    insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
    values(v_lot.id,v_owner_task,'seedling_failure_decision','production_stage_engine',jsonb_build_object('readiness_observation_id',v_obs.id));
    return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'observationId',v_obs.id,'action','failed','nextTaskId',v_owner_task,'deduplicated',false);
  end if;

  -- Biological readiness is authoritative even when capacity math is not yet known.
  update atlas.production_tray_batches
  set status='transplant_ready',current_quantity=p_surviving_seedlings,current_unit='seedlings',tray_count=coalesce(p_tray_count,tray_count),
      metadata=metadata||jsonb_build_object('last_readiness_observation_id',v_obs.id,'transplant_ready_date',p_observed_date),updated_at=now()
  where id=v_batch.id;
  update atlas.production_lots
  set current_quantity=p_surviving_seedlings,current_unit='seedlings',current_stage='transplant_ready',
      metadata=metadata||jsonb_build_object('last_biological_event','transplant_ready'),updated_at=now()
  where id=v_lot.id;
  update atlas.crop_cycles
  set cycle_state='transplant_ready',coverage_kind='viable_seedlings',coverage_amount=p_surviving_seedlings,coverage_unit='seedlings',
      metadata=metadata||jsonb_build_object('readiness_observation_id',v_obs.id),updated_at=now()
  where id=v_batch.crop_cycle_id;
  insert into atlas.production_lot_events(
    farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata
  ) values (
    v_lot.farm_id,v_lot.id,'transplant_ready',p_observed_date,p_surviving_seedlings,'seedlings',p_task_id,v_batch.crop_cycle_id,p_note,
    'production_stage_engine',left(v_key||':event:ready',160),jsonb_build_object('readiness_observation_id',v_obs.id,'container_kind',v_batch.container_kind)
  );
  v_transition:=atlas.record_task_transition_v1_internal(
    p_task_id,'done',left(v_key||':task:ready',160),null,
    coalesce(nullif(btrim(p_note),''),p_surviving_seedlings::text||' seedlings are transplant-ready.'),null,'observe','production_lot',
    jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'readiness_observation_id',v_obs.id,
      'surviving_seedlings',p_surviving_seedlings,'tray_count',coalesce(p_tray_count,v_batch.tray_count),'container_kind',v_batch.container_kind),null
  );

  select value into v_rows from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_rows_per_three_foot_bed';
  select value into v_spacing from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_in_row_spacing_inches';

  if v_rows is null or v_spacing is null then
    update atlas.production_capacity_requirements
    set quantity_needed=null,calculation_status='blocked',
        metadata=metadata||jsonb_build_object(
          'quantity_truth','awaiting_capacity_measurement',
          'surviving_seedlings',p_surviving_seedlings,
          'missing_measurements',to_jsonb(array_remove(array[
            case when v_rows is null then 'snapdragon_rows_per_three_foot_bed' end,
            case when v_spacing is null then 'snapdragon_in_row_spacing_inches' end
          ],null)),
          'readiness_observation_id',v_obs.id
        ),updated_at=now()
    where production_lot_id=v_lot.id and capacity_kind='bed_feet'
    returning id into v_req_id;
    if v_req_id is null then raise exception 'Production lot is missing its bed-feet requirement' using errcode='22023'; end if;

    v_gate:=atlas.refresh_production_transplant_gate_v1(v_lot.id);

    select id into v_owner_task
    from atlas.tasks
    where farm_id=v_lot.farm_id
      and engine_instance_key='production-bed-math:'||v_lot.id::text
      and status in ('open','blocked')
    order by created_at desc limit 1;

    if v_owner_task is null then
      insert into atlas.tasks(
        farm_id,title,task_type,status,priority,due_date,generated_from,generated_from_id,note,metadata,action_key,work_class,
        task_series_key,engine_instance_key,visibility_scope,organization_id,origin_kind,task_scope,work_lane,commitment_kind
      ) values (
        v_lot.farm_id,'Owner — Set bed-capacity math · '||v_lot.lot_label,'owner_decision','open','high',p_observed_date,
        'production_readiness_observation',v_obs.id,
        'The cohort is biologically transplant-ready. Record the missing snapdragon bed-capacity measurements so Atlas can calculate required bed-feet and open the transplant gate.',
        jsonb_build_object(
          'task_key','production_bed_math_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,
          'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'readiness_observation_id',v_obs.id,
          'surviving_seedlings',p_surviving_seedlings,'destination_program','BW1-BW3',
          'missing_measurements',to_jsonb(array_remove(array[
            case when v_rows is null then 'snapdragon_rows_per_three_foot_bed' end,
            case when v_spacing is null then 'snapdragon_in_row_spacing_inches' end
          ],null)),
          'display_action','Measure + decide','display_subject',v_lot.lot_label||' bed capacity',
          'display_detail',p_surviving_seedlings::text||' ready seedlings · transplant blocked on bed math','collection_zone','Owner',
          'continuity_gate',true,'blocked_stage','transplant','biological_readiness_preserved',true
        ),
        'decide','owner_decision','production-lot:'||v_lot.stable_key||':bed-math','production-bed-math:'||v_lot.id::text,
        'owner',v_task.organization_id,'generated','farm_operation','required','dependency'
      ) returning id into v_owner_task;
      insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
      values(v_lot.id,v_owner_task,'bed_math_decision','production_stage_engine',jsonb_build_object('readiness_observation_id',v_obs.id));
    end if;

    return jsonb_build_object(
      'taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'observationId',v_obs.id,
      'action','ready','survivingSeedlings',p_surviving_seedlings,'requiredBedFeet',null,
      'gate',v_gate,'ownerDecisionTaskId',v_owner_task,'bedMathBlocked',true,'deduplicated',false
    );
  end if;

  v_bed_feet:=ceil((p_surviving_seedlings*v_spacing/12.0)/v_rows);
  update atlas.production_capacity_requirements
  set quantity_needed=v_bed_feet,calculation_status='confirmed',
      metadata=metadata||jsonb_build_object('quantity_basis','counted_surviving_seedlings','surviving_seedlings',p_surviving_seedlings,
        'rows_per_bed',v_rows,'spacing_inches',v_spacing,'readiness_observation_id',v_obs.id),updated_at=now()
  where production_lot_id=v_lot.id and capacity_kind='bed_feet'
  returning id into v_req_id;
  if v_req_id is null then raise exception 'Production lot is missing its bed-feet requirement' using errcode='22023'; end if;
  update atlas.production_lots set metadata=metadata||jsonb_build_object('actual_bed_feet_required',v_bed_feet),updated_at=now() where id=v_lot.id;
  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('actual_bed_feet_required',v_bed_feet),updated_at=now() where id=v_batch.crop_cycle_id;
  v_gate:=atlas.refresh_production_transplant_gate_v1(v_lot.id);
  return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'observationId',v_obs.id,'action','ready','survivingSeedlings',p_surviving_seedlings,'requiredBedFeet',v_bed_feet,'gate',v_gate,'bedMathBlocked',false,'deduplicated',false);
end;
$$;

revoke all on function atlas.record_production_readiness_v1(uuid,text,numeric,numeric,date,date,text,text) from public;
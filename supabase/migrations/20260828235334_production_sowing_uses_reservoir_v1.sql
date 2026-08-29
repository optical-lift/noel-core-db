create or replace function atlas.record_production_sowing_v1(
  p_task_id uuid,p_seed_quantity numeric,p_tray_count numeric,p_sow_date date,p_note text,p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_existing atlas.production_tray_batches%rowtype;
  v_batch_id uuid;
  v_cycle_id uuid;
  v_grow_room_object_id uuid;
  v_batch_number integer;
  v_available numeric;
  v_remaining numeric;
  v_take numeric;
  v_consumed numeric;
  v_reserved numeric;
  v_capacity_checks integer := 0;
  v_req record;
  v_alloc record;
  v_transition jsonb;
  v_key text := nullif(btrim(p_idempotency_key),'');
  v_next jsonb;
  v_germ_date date;
begin
  if p_task_id is null or p_seed_quantity is null or p_seed_quantity<=0 or p_tray_count is null or p_tray_count<=0 or p_sow_date is null then raise exception 'Task, seed quantity, tray count, and sow date are required' using errcode='22023'; end if;
  if v_key is null or length(v_key)>120 then raise exception 'A valid sowing idempotency key is required' using errcode='22023'; end if;
  if p_sow_date>v_today+1 then raise exception 'Actual sow date cannot be in the future' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Sowing task was not found' using errcode='P0002'; end if;
  select pl.* into v_lot from atlas.production_lot_tasks plt join atlas.production_lots pl on pl.id=plt.production_lot_id where plt.task_id=p_task_id and plt.link_role='sowing' limit 1 for update of pl;
  if v_lot.id is null then raise exception 'Task is not linked to a production lot sowing step' using errcode='22023'; end if;

  select * into v_existing from atlas.production_tray_batches where farm_id=v_lot.farm_id and idempotency_key=v_key;
  if v_existing.id is not null then return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_existing.id,'cropCycleId',v_existing.crop_cycle_id,'deduplicated',true); end if;
  if v_task.status not in ('open','blocked') then raise exception 'Sowing task is not open' using errcode='22023'; end if;
  if v_lot.current_stage<>'planned' or v_lot.lifecycle_status<>'planned' then raise exception 'Production lot is not waiting to be sown' using errcode='22023'; end if;
  if v_lot.planned_input_quantity is not null and p_seed_quantity>v_lot.planned_input_quantity then raise exception 'Actual sowing exceeds the planned production-lot seed quantity' using errcode='22023'; end if;

  perform atlas.assert_production_seed_ready_v1(v_lot.id,p_seed_quantity);
  select coalesce(sum(sla.allocated_quantity-coalesce(used.quantity_used,0)),0) into v_available
  from atlas.seed_lot_allocations sla left join lateral (select sum(sac.quantity_consumed) quantity_used from atlas.seed_allocation_consumptions sac where sac.seed_lot_allocation_id=sla.id) used on true
  where sla.production_lot_id=v_lot.id and sla.allocation_status not in ('released','cancelled');
  if v_available<p_seed_quantity then raise exception 'Seed allocations do not cover the actual sowing quantity' using errcode='22023'; end if;

  for v_req in select * from atlas.production_capacity_requirements where production_lot_id=v_lot.id and capacity_kind in ('trays','shelf_positions','lit_shelf_positions') loop
    v_capacity_checks:=v_capacity_checks+1;
    if v_req.calculation_status not in ('calculated','confirmed') or v_req.quantity_needed is null then raise exception 'Production capacity is not calculated for %',v_req.capacity_kind using errcode='22023'; end if;
    select coalesce(sum(r.quantity_reserved),0) into v_reserved from atlas.production_capacity_reservations r where r.requirement_id=v_req.id and r.reservation_status in ('tentative','confirmed') and p_sow_date between r.window_start and r.window_end;
    if v_reserved < (case when v_req.capacity_kind='trays' then p_tray_count else v_req.quantity_needed end) then raise exception 'Reserved % capacity does not cover this sowing',v_req.capacity_kind using errcode='22023'; end if;
  end loop;
  if v_capacity_checks<>3 then raise exception 'Tray, shelf, and lit-shelf requirements must all exist before sowing' using errcode='22023'; end if;

  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  if v_profile.id is null then raise exception 'Production lot is missing its crop profile' using errcode='22023'; end if;
  select id into v_grow_room_object_id from atlas.growing_objects where farm_id=v_lot.farm_id and stable_key='grow_room_seed_shelves' limit 1;
  if v_grow_room_object_id is null then raise exception 'Grow Room seed shelves object is required' using errcode='22023'; end if;
  select coalesce(max(batch_number),0)+1 into v_batch_number from atlas.production_tray_batches where production_lot_id=v_lot.id;

  insert into atlas.crop_cycles(farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,expected_germination_start,expected_germination_end,expected_harvest_watch_start,expected_harvest_watch_end,coverage_kind,coverage_amount,coverage_unit,source_task_id,note,metadata)
  values(v_lot.farm_id,v_grow_room_object_id,v_lot.crop_profile_id,'production_lot_'||v_lot.stable_key||'_tray_'||v_batch_number::text,v_profile.crop_label,v_profile.variety,'sown','active',p_sow_date,case when v_profile.days_to_germination_min is null then null else p_sow_date+v_profile.days_to_germination_min end,case when v_profile.days_to_germination_max is null then null else p_sow_date+v_profile.days_to_germination_max end,v_lot.expected_harvest_start,v_lot.expected_harvest_end,'tray_batch',p_tray_count,'trays',p_task_id,p_note,jsonb_build_object('production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'biological_stage','germination_pending')) returning id into v_cycle_id;

  insert into atlas.production_tray_batches(farm_id,production_lot_id,source_task_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,current_quantity,current_unit,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,p_task_id,v_cycle_id,v_batch_number,v_lot.lot_label||' · Tray Batch '||v_batch_number::text,coalesce(nullif(v_task.metadata->>'container_kind',''),'3/4-inch soil blocks'),case when coalesce(v_task.metadata->>'container_kind','') ilike '%3/4%' then 0.75 else null end,p_seed_quantity,'seeds',p_tray_count,'germination_pending',p_sow_date,case when v_profile.days_to_germination_min is null then null else p_sow_date+v_profile.days_to_germination_min end,case when v_profile.days_to_germination_max is null then null else p_sow_date+v_profile.days_to_germination_max end,p_seed_quantity,'seeds_sown',v_key,jsonb_build_object('production_program_id',v_lot.program_id,'crop_profile_id',v_lot.crop_profile_id,'capacity_validated',true)) returning id into v_batch_id;

  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('production_tray_batch_id',v_batch_id),updated_at=now() where id=v_cycle_id;
  insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata) values(v_lot.id,v_cycle_id,'seedling_batch','confirmed','production_stage_engine',jsonb_build_object('tray_batch_id',v_batch_id));

  v_remaining:=p_seed_quantity;
  for v_alloc in
    select sla.*,coalesce(used.quantity_used,0) quantity_used
    from atlas.seed_lot_allocations sla left join lateral (select sum(quantity_consumed) quantity_used from atlas.seed_allocation_consumptions where seed_lot_allocation_id=sla.id) used on true
    where sla.production_lot_id=v_lot.id and sla.allocation_status not in ('released','cancelled') order by sla.allocated_at,sla.id for update of sla
  loop
    exit when v_remaining<=0;
    v_take:=least(v_remaining,v_alloc.allocated_quantity-v_alloc.quantity_used);
    if v_take>0 then
      insert into atlas.seed_allocation_consumptions(farm_id,seed_lot_allocation_id,production_lot_id,tray_batch_id,source_task_id,quantity_consumed,unit,consumed_date,idempotency_key,metadata)
      values(v_lot.farm_id,v_alloc.id,v_lot.id,v_batch_id,p_task_id,v_take,v_alloc.unit,p_sow_date,left(v_key||':allocation:'||v_alloc.id::text,160),jsonb_build_object('production_lot_key',v_lot.stable_key));
      select coalesce(sum(quantity_consumed),0) into v_consumed from atlas.seed_allocation_consumptions where seed_lot_allocation_id=v_alloc.id;
      update atlas.seed_lot_allocations set allocation_status=case when v_consumed>=allocated_quantity then 'consumed' else 'reserved' end,updated_at=now() where id=v_alloc.id;
      v_remaining:=v_remaining-v_take;
    end if;
  end loop;
  if v_remaining>0 then raise exception 'Seed allocation consumption could not reconcile the sowing quantity'; end if;

  update atlas.production_lots set current_quantity=p_seed_quantity,current_unit='seeds_sown',current_stage='germination_pending',lifecycle_status='active',actual_sow_date=p_sow_date,metadata=metadata||jsonb_build_object('active_tray_batch_id',v_batch_id,'active_crop_cycle_id',v_cycle_id,'last_biological_event','sown'),updated_at=now() where id=v_lot.id;
  insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,'sown',p_sow_date,p_seed_quantity,'seeds',p_task_id,v_cycle_id,p_note,'production_stage_engine',left(v_key||':event:sown',160),jsonb_build_object('tray_batch_id',v_batch_id,'tray_count',p_tray_count));
  v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'done',left(v_key||':task:done',160),null,coalesce(nullif(btrim(p_note),''),'Sowed '||p_seed_quantity::text||' seeds in '||p_tray_count::text||' trays.'),null,'sow','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id,'seed_quantity',p_seed_quantity,'tray_count',p_tray_count),null);

  v_germ_date:=coalesce((select expected_germination_start from atlas.production_tray_batches where id=v_batch_id),p_sow_date+1);
  v_next:=atlas.author_production_work_occurrence_v1(
    v_lot.farm_id,'germination','production:germination:'||v_batch_id::text,
    'Count germination — '||v_lot.lot_label,v_germ_date,v_germ_date,
    'production_tray_batch',v_batch_id,'production_germination_check','observe','light','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
    'Count emerged seedlings for this exact tray batch. “Not yet” moves the check to tomorrow.',
    jsonb_build_object('task_key','production_germination_'||v_batch_id::text,'task_style','production_germination_check','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id,'crop_profile_id',v_lot.crop_profile_id,'production_crop_label',v_profile.crop_label,'production_variety',v_profile.variety,'tray_count',p_tray_count,'seeds_sown',p_seed_quantity,'germination_status','production_managed','display_action','Count','display_subject',v_lot.lot_label||' germination','display_detail',p_tray_count::text||' trays','collection_zone','Grow Room','assigned_to',v_task.metadata->>'assigned_to'),
    jsonb_build_object('task_objects',jsonb_build_array(jsonb_build_object('object_id',v_grow_room_object_id,'role','primary_location')),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_cycle_id,'role','observes','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','germination_check','source','production_stage_engine','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
    'process_continuation','dependency',coalesce((select expected_germination_end from atlas.production_tray_batches where id=v_batch_id),v_germ_date+7),jsonb_build_object('kind','germination_window','effect','Germination needs a counted observation inside the expected window.'),false
  );
  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('next_action','germination_check','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_germ_date),updated_at=now() where id=v_cycle_id;
  update atlas.production_lots set metadata=metadata||jsonb_build_object('next_action','germination_check','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_germ_date),updated_at=now() where id=v_lot.id;

  return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch_id,'cropCycleId',v_cycle_id,'germinationOccurrenceId',v_next->>'occurrenceId','germinationTaskId',v_next->>'taskId','seedQuantity',p_seed_quantity,'trayCount',p_tray_count,'deduplicated',false);
end;
$function$;
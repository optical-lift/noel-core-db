create or replace function atlas.record_production_transplant_v1(
  p_task_id uuid,
  p_placements jsonb,
  p_planted_date date,
  p_note text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_gate atlas.production_transplant_gates%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_total numeric:=0;
  v_field_log_id uuid;
  v_claim_id uuid;
  v_transition jsonb;
  v_establishment jsonb;
  v_row record;
  v_assignment atlas.production_bed_assignments%rowtype;
  v_object atlas.growing_objects%rowtype;
  v_field_cycle uuid;
  v_content_id uuid;
  v_event_id uuid;
  v_rows numeric;
  v_spacing numeric;
  v_max_plants numeric;
  v_existing uuid;
  v_gate_id uuid;
  v_relation_objects jsonb;
  v_relation_cycles jsonb;
begin
  if p_task_id is null or p_planted_date is null or p_placements is null or jsonb_typeof(p_placements)<>'array' or jsonb_array_length(p_placements)=0 then raise exception 'Task, planted date, and bed placements are required' using errcode='22023'; end if;
  if v_key is null or length(v_key)>120 then raise exception 'A valid transplant idempotency key is required' using errcode='22023'; end if;
  if p_planted_date>v_today+1 then raise exception 'Planted date cannot be in the future' using errcode='22023'; end if;

  select id into v_existing from atlas.planting_claims where farm_id=(select farm_id from atlas.tasks where id=p_task_id) and idempotency_key=left(v_key||':planting-claim',160);
  if v_existing is not null then return jsonb_build_object('taskId',p_task_id,'plantingClaimId',v_existing,'deduplicated',true); end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  select pl.* into v_lot
  from atlas.production_lot_tasks plt join atlas.production_lots pl on pl.id=plt.production_lot_id
  where plt.task_id=p_task_id and plt.link_role='transplant' limit 1 for update of pl;
  if v_task.id is null or v_lot.id is null then raise exception 'Task is not a linked production transplant step' using errcode='22023'; end if;

  begin v_gate_id:=nullif(v_task.metadata->>'production_transplant_gate_id','')::uuid; exception when others then v_gate_id:=null; end;
  if v_gate_id is null then
    select nullif(plt.metadata->>'transplant_gate_id','')::uuid into v_gate_id
    from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.link_role='transplant' order by plt.created_at desc limit 1;
  end if;
  v_gate_id:=coalesce(v_gate_id,v_task.generated_from_id);
  select * into v_gate from atlas.production_transplant_gates where id=v_gate_id and production_lot_id=v_lot.id for update;
  if v_gate.id is null or v_gate.gate_status<>'ready' then raise exception 'Transplant gate is not ready' using errcode='22023'; end if;

  select * into v_batch from atlas.production_tray_batches where id=v_gate.tray_batch_id for update;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  select value into v_rows from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_rows_per_three_foot_bed';
  select value into v_spacing from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_in_row_spacing_inches';
  if v_rows is null or v_spacing is null then raise exception 'Planting density measurements are required' using errcode='22023'; end if;

  create temporary table if not exists pg_temp.production_transplant_input(assignment_id uuid primary key,plants numeric not null) on commit drop;
  truncate pg_temp.production_transplant_input;
  insert into pg_temp.production_transplant_input(assignment_id,plants)
  select (x->>'assignmentId')::uuid,(x->>'plants')::numeric from jsonb_array_elements(p_placements) x;
  if exists(select 1 from pg_temp.production_transplant_input where plants<=0) then raise exception 'Each bed placement requires a positive plant count' using errcode='22023'; end if;
  select sum(plants) into v_total from pg_temp.production_transplant_input;
  if v_total>coalesce(v_lot.current_quantity,0) then raise exception 'Transplant count exceeds the surviving seedling cohort' using errcode='22023'; end if;

  for v_row in select * from pg_temp.production_transplant_input loop
    select * into v_assignment from atlas.production_bed_assignments where id=v_row.assignment_id and production_lot_id=v_lot.id and assignment_status='assigned';
    if v_assignment.id is null then raise exception 'Every placement must use an active bed assignment' using errcode='22023'; end if;
    v_max_plants:=floor((v_assignment.quantity_assigned*v_rows*12.0)/v_spacing);
    if v_row.plants>v_max_plants then raise exception 'Placement exceeds the measured density of its assigned bed-feet' using errcode='22023'; end if;
  end loop;

  insert into atlas.field_logs(farm_id,log_date,action_types,summary_sentence,note,created_by,source,idempotency_key,metadata)
  values(v_lot.farm_id,p_planted_date,array['transplant','planting','production_lot'],'Transplanted '||v_total::text||' '||coalesce(v_profile.variety,v_profile.crop_label)||' plants from '||v_lot.lot_label,p_note,'production_stage_engine','production_stage_engine',left(v_key||':field-log',160),jsonb_build_object('production_lot_id',v_lot.id,'production_tray_batch_id',v_batch.id,'production_transplant_gate_id',v_gate.id,'placements',p_placements)) returning id into v_field_log_id;

  insert into atlas.planting_claims(farm_id,field_log_id,crop_profile_id,crop_label,variety,planted_date,planting_method,amount,unit,status,confidence,note,idempotency_key,metadata)
  values(v_lot.farm_id,v_field_log_id,v_lot.crop_profile_id,v_profile.crop_label,v_profile.variety,p_planted_date,'transplant',v_total,'plants','planted','field_logged',p_note,left(v_key||':planting-claim',160),jsonb_build_object('production_lot_id',v_lot.id,'production_tray_batch_id',v_batch.id,'production_transplant_gate_id',v_gate.id,'source_task_id',p_task_id,'placements',p_placements)) returning id into v_claim_id;

  for v_row in select * from pg_temp.production_transplant_input loop
    select * into v_assignment from atlas.production_bed_assignments where id=v_row.assignment_id;
    select * into v_object from atlas.growing_objects where id=v_assignment.object_id;
    insert into atlas.planting_claim_objects(planting_claim_id,object_id,coverage_kind,coverage_amount,coverage_unit) values(v_claim_id,v_object.id,'bed_feet',v_assignment.quantity_assigned,'bed_ft');
    insert into atlas.object_contents(farm_id,object_id,planting_claim_id,crop_profile_id,content_label,content_type,variety,planted_date,status,confidence,start_method,note,metadata)
    values(v_lot.farm_id,v_object.id,v_claim_id,v_lot.crop_profile_id,v_profile.crop_label,'planting',v_profile.variety,p_planted_date,'planted','field_logged','transplant',p_note,jsonb_build_object('production_lot_id',v_lot.id,'plants_transplanted',v_row.plants,'bed_assignment_id',v_assignment.id,'tray_batch_id',v_batch.id)) returning id into v_content_id;
    select id into v_field_cycle from atlas.crop_cycles where object_content_id=v_content_id order by created_at desc limit 1;
    if v_field_cycle is null then
      insert into atlas.crop_cycles(farm_id,object_id,object_content_id,planting_claim_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,planted_date,expected_harvest_watch_start,expected_harvest_watch_end,coverage_kind,coverage_amount,coverage_unit,source_task_id,note,metadata)
      values(v_lot.farm_id,v_object.id,v_content_id,v_claim_id,v_lot.crop_profile_id,'production_lot_'||v_lot.stable_key||'_bed_'||replace(v_object.id::text,'-',''),v_profile.crop_label,v_profile.variety,'establishment','active',p_planted_date,v_lot.expected_harvest_start,v_lot.expected_harvest_end,'plants',v_row.plants,'plants',p_task_id,p_note,jsonb_build_object('production_lot_id',v_lot.id,'source_tray_crop_cycle_id',v_batch.crop_cycle_id,'bed_assignment_id',v_assignment.id)) returning id into v_field_cycle;
    else
      update atlas.crop_cycles set planting_claim_id=v_claim_id,crop_profile_id=v_lot.crop_profile_id,cycle_state='establishment',lifecycle_status='active',planted_date=p_planted_date,coverage_kind='plants',coverage_amount=v_row.plants,coverage_unit='plants',source_task_id=p_task_id,note=p_note,metadata=metadata||jsonb_build_object('production_lot_id',v_lot.id,'source_tray_crop_cycle_id',v_batch.crop_cycle_id,'bed_assignment_id',v_assignment.id),updated_at=now() where id=v_field_cycle;
    end if;
    insert into atlas.production_lot_crop_cycles(production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata) values(v_lot.id,v_field_cycle,'field_batch','confirmed','production_stage_engine',jsonb_build_object('bed_assignment_id',v_assignment.id,'plants_transplanted',v_row.plants));
    insert into atlas.object_activity_events(farm_id,object_id,object_content_id,field_log_id,crop_cycle_id,event_type,event_date,note,quantity,unit,created_by,source,idempotency_key,metadata)
    values(v_lot.farm_id,v_object.id,v_content_id,v_field_log_id,v_field_cycle,'transplanted',p_planted_date,p_note,v_row.plants,'plants','production_stage_engine','production_stage_engine',left(v_key||':object:'||v_object.id::text,160),jsonb_build_object('production_lot_id',v_lot.id,'planting_claim_id',v_claim_id,'bed_assignment_id',v_assignment.id)) returning id into v_event_id;
    insert into atlas.production_transplant_placements(farm_id,production_lot_id,tray_batch_id,transplant_gate_id,source_task_id,bed_assignment_id,object_id,planting_claim_id,crop_cycle_id,plants_transplanted,planted_date,idempotency_key,metadata)
    values(v_lot.farm_id,v_lot.id,v_batch.id,v_gate.id,p_task_id,v_assignment.id,v_object.id,v_claim_id,v_field_cycle,v_row.plants,p_planted_date,left(v_key||':placement:'||v_assignment.id::text,160),jsonb_build_object('object_event_id',v_event_id,'object_content_id',v_content_id));
    insert into atlas.field_log_objects(field_log_id,zone_id,object_id,role) values(v_field_log_id,v_object.zone_id,v_object.id,'transplant_destination') on conflict do nothing;
    insert into atlas.object_state(object_id,farm_id,life_status,weed_pressure,water_status,last_touched_at,last_checked_at,decision_required,harvest_confidence,presentability,metadata)
    values(v_object.id,v_lot.farm_id,'planted','unknown','unknown',p_planted_date,p_planted_date,false,'unknown','unknown',jsonb_build_object('production_lot_id',v_lot.id,'last_planting_claim_id',v_claim_id,'last_crop_cycle_id',v_field_cycle,'plants_transplanted',v_row.plants))
    on conflict(object_id) do update set life_status='planted',last_touched_at=excluded.last_touched_at,last_checked_at=excluded.last_checked_at,decision_required=false,metadata=atlas.object_state.metadata||excluded.metadata,updated_at=now();
  end loop;

  update atlas.production_tray_batches set status='transplanted',current_quantity=coalesce(current_quantity,0)-v_total,current_unit='seedlings_remaining',metadata=metadata||jsonb_build_object('transplanted_date',p_planted_date,'plants_transplanted',v_total,'planting_claim_id',v_claim_id),updated_at=now() where id=v_batch.id;
  update atlas.crop_cycles set cycle_state='transplanted_out',lifecycle_status='complete',coverage_kind='seedlings_remaining',coverage_amount=greatest(coalesce(coverage_amount,0)-v_total,0),coverage_unit='seedlings',metadata=metadata||jsonb_build_object('transplanted_date',p_planted_date,'planting_claim_id',v_claim_id),updated_at=now() where id=v_batch.crop_cycle_id;
  update atlas.production_lots set current_quantity=v_total,current_unit='plants',current_stage='establishment',metadata=metadata||jsonb_build_object('last_biological_event','transplanted','planting_claim_id',v_claim_id,'transplanted_count',v_total),updated_at=now() where id=v_lot.id;
  update atlas.production_transplant_gates set gate_status='transplanted',blocker_text=null,transplant_task_id=p_task_id,metadata=metadata||jsonb_build_object('planted_date',p_planted_date,'planting_claim_id',v_claim_id,'plants_transplanted',v_total),updated_at=now() where id=v_gate.id;
  update atlas.production_capacity_reservations set reservation_status='released',metadata=metadata||jsonb_build_object('released_reason','tray_batch_transplanted','released_date',p_planted_date,'planting_claim_id',v_claim_id),updated_at=now() where production_lot_id=v_lot.id and reservation_status in ('tentative','confirmed') and capacity_pool_id in (select id from atlas.capacity_pools where capacity_kind in ('trays','shelf_positions','lit_shelf_positions'));
  insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,'transplanted',p_planted_date,v_total,'plants',p_task_id,v_batch.crop_cycle_id,p_note,'production_stage_engine',left(v_key||':event:transplanted',160),jsonb_build_object('tray_batch_id',v_batch.id,'transplant_gate_id',v_gate.id,'planting_claim_id',v_claim_id,'placements',p_placements));
  v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'done',left(v_key||':task:done',160),null,coalesce(nullif(btrim(p_note),''),'Transplanted '||v_total::text||' plants.'),null,'transplant','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'transplant_gate_id',v_gate.id,'planting_claim_id',v_claim_id,'plants_transplanted',v_total,'placements',p_placements),v_field_log_id);

  select coalesce(jsonb_agg(jsonb_build_object('object_id',p.object_id,'role','target') order by p.object_id),'[]'::jsonb)
  into v_relation_objects from atlas.production_transplant_placements p where p.planting_claim_id=v_claim_id;
  select coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',p.crop_cycle_id,'role','observes','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('planting_claim_id',v_claim_id)) order by p.crop_cycle_id),'[]'::jsonb)
  into v_relation_cycles from atlas.production_transplant_placements p where p.planting_claim_id=v_claim_id;

  v_establishment:=atlas.author_production_work_occurrence_v1(
    v_lot.farm_id,'establishment','production:establishment:'||v_gate.id::text,
    'Check transplant establishment — '||v_lot.lot_label,p_planted_date+3,p_planted_date+3,
    'production_transplant_gate',v_gate.id,'production_establishment_check','observe','standard','high','assigned_worker',
    v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
    'Count losses and confirm water and establishment in every assigned bed.',
    jsonb_build_object(
      'task_key','production_establishment_'||v_gate.id::text,'task_style','production_establishment_check',
      'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_transplant_gate_id',v_gate.id,
      'planting_claim_id',v_claim_id,'plants_transplanted',v_total,
      'display_action','Check','display_subject',v_lot.lot_label||' establishment',
      'display_detail',v_total::text||' plants across '||jsonb_array_length(p_placements)::text||' beds','collection_zone','Assigned beds'
    ),
    jsonb_build_object(
      'task_objects',coalesce(v_relation_objects,'[]'::jsonb),
      'task_crop_cycles',coalesce(v_relation_cycles,'[]'::jsonb),
      'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','establishment_check','source','production_stage_engine','metadata',jsonb_build_object('planting_claim_id',v_claim_id,'transplant_gate_id',v_gate.id))),
      'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()
    ),'process_continuation','dependency',p_planted_date+6,
    jsonb_build_object('kind','establishment_pressure','effect','New transplants require a governed survival check.'),false
  );

  return jsonb_build_object(
    'taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'transplantGateId',v_gate.id,
    'plantingClaimId',v_claim_id,'fieldLogId',v_field_log_id,'plantsTransplanted',v_total,
    'establishmentOccurrenceId',v_establishment->>'occurrenceId','establishmentTaskId',v_establishment->>'taskId','deduplicated',false
  );
end;
$function$;
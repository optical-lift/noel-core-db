create or replace function atlas.record_production_clear_v1(p_task_id uuid,p_clear_date date,p_note text,p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_event_id uuid;
  v_transition jsonb;
  v_cleared_stands integer:=0;
  v_next jsonb;
  v_objects jsonb;
begin
  if p_task_id is null or p_clear_date is null or v_key is null then raise exception 'Task, clear date, and idempotency key are required' using errcode='22023'; end if;
  if p_clear_date>(now() at time zone 'America/Chicago')::date+1 then raise exception 'Clear date cannot be in the future' using errcode='22023'; end if;
  select * into v_task from atlas.tasks where id=p_task_id for update;
  select pl.* into v_lot from atlas.production_lot_tasks plt join atlas.production_lots pl on pl.id=plt.production_lot_id where plt.task_id=p_task_id and plt.link_role='clear' limit 1 for update of pl;
  if v_task.id is null or v_lot.id is null then raise exception 'Task is not a linked production clear step' using errcode='22023'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_lot.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select id into v_event_id from atlas.production_lot_events where farm_id=v_lot.farm_id and idempotency_key=left(v_key||':event:cleared',160);
  if v_event_id is not null then return jsonb_build_object('eventId',v_event_id,'productionLotId',v_lot.id,'deduplicated',true); end if;
  if v_task.status not in ('open','blocked') then raise exception 'Clear task is not open' using errcode='22023'; end if;

  update atlas.production_field_stands set stand_status='cleared',current_plants=0,total_losses=plants_transplanted,last_observed_date=p_clear_date,metadata=metadata||jsonb_build_object('cleared_date',p_clear_date,'clear_task_id',v_task.id),updated_at=now() where production_lot_id=v_lot.id and stand_status<>'cleared';
  get diagnostics v_cleared_stands=row_count;
  update atlas.crop_cycles set cycle_state='cleared',lifecycle_status='complete',cleared_date=p_clear_date,coverage_kind='plants_alive',coverage_amount=0,coverage_unit='plants',metadata=metadata||jsonb_build_object('production_clear_task_id',v_task.id),updated_at=now() where id in (select crop_cycle_id from atlas.production_field_stands where production_lot_id=v_lot.id);
  update atlas.production_bed_assignments set assignment_status='released',expected_release_date=greatest(coalesce(expected_release_date,p_clear_date),p_clear_date),metadata=metadata||jsonb_build_object('actual_release_date',p_clear_date,'clear_task_id',v_task.id),updated_at=now() where production_lot_id=v_lot.id and assignment_status='assigned';
  update atlas.production_capacity_reservations r set reservation_status='released',metadata=metadata||jsonb_build_object('released_reason','production_cohort_cleared','released_date',p_clear_date,'clear_task_id',v_task.id),updated_at=now() where r.production_lot_id=v_lot.id and r.reservation_status in ('tentative','confirmed') and exists(select 1 from atlas.capacity_pools cp where cp.id=r.capacity_pool_id and cp.capacity_kind='bed_feet');
  update atlas.production_lots set current_quantity=0,current_unit='plants',current_stage='turnover',lifecycle_status='active',metadata=metadata||jsonb_build_object('last_biological_event','cleared','actual_clear_date',p_clear_date),updated_at=now() where id=v_lot.id;

  insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,note,source,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,'cleared',p_clear_date,0,'plants_alive',v_task.id,p_note,'production_stage_engine',left(v_key||':event:cleared',160),jsonb_build_object('cleared_stand_count',v_cleared_stands)) returning id into v_event_id;
  v_transition:=atlas.record_task_transition_v1_internal(v_task.id,'done',left(v_key||':task:done',160),null,coalesce(nullif(btrim(coalesce(p_note,'')),''),'Production cohort cleared.'),null,'clear','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'production_lot_event_id',v_event_id,'cleared_stand_count',v_cleared_stands),null);

  select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','turnover_target') order by object_id),'[]'::jsonb)
  into v_objects from atlas.production_field_stands where production_lot_id=v_lot.id;

  v_next:=atlas.author_production_work_occurrence_v1(
    v_lot.farm_id,'turnover','production:turnover:'||v_lot.id::text,
    'Turn over cleared production beds — '||v_lot.lot_label,p_clear_date,p_clear_date,
    'production_lot_event',v_event_id,'production_turnover','prepare','heavy','medium',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
    'Complete the post-clear turnover state for the beds released by this production lot. This closes the lot lifecycle; the next occupancy remains separate production truth.',
    jsonb_build_object('production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'source_clear_event_id',v_event_id,'display_action','Turn over','display_subject',v_lot.lot_label,'collection_zone','Production beds','operation_class','cultivate_prepare'),
    jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','turnover','source','production_actual_reforecast_v1','metadata',jsonb_build_object('source_clear_event_id',v_event_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
    'process_continuation','dependency',p_clear_date+3,jsonb_build_object('kind','bed_turnover','effect','Beds are crop-free but the production lifecycle is not closed until turnover state is recorded.'),true
  );

  update atlas.production_lots set metadata=metadata||jsonb_build_object('next_action','turnover','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',p_clear_date),updated_at=now() where id=v_lot.id;
  return jsonb_build_object('contractVersion','record_production_clear_v1','productionLotId',v_lot.id,'eventId',v_event_id,'clearedStandCount',v_cleared_stands,'turnoverOccurrenceId',v_next->>'occurrenceId','turnoverTaskId',v_next->>'taskId','deduplicated',false);
end;
$function$;
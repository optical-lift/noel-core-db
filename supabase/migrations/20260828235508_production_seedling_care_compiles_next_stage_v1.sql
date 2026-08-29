create or replace function atlas.record_production_seedling_care_v1(
  p_task_id uuid,p_surviving_seedlings numeric,p_tray_count numeric,p_care_date date,p_note text,p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_existing uuid;
  v_transition jsonb;
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_batch_id uuid;
  v_next_stage record;
  v_due date;
  v_latest date;
  v_next jsonb;
  v_container text;
  v_object_id uuid;
  v_title text;
  v_task_type text;
  v_action_key text;
  v_note text;
  v_metadata jsonb;
  v_link_role text;
begin
  if p_task_id is null or p_surviving_seedlings is null or p_surviving_seedlings<=0 or p_tray_count is null or p_tray_count<=0 or p_care_date is null then raise exception 'Task, surviving seedlings, trays, and care date are required' using errcode='22023'; end if;
  if v_key is null or length(v_key)>120 then raise exception 'A valid seedling-care idempotency key is required' using errcode='22023'; end if;
  if p_care_date>v_today+1 then raise exception 'Care date cannot be in the future' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  select pl.* into v_lot from atlas.production_lot_tasks plt join atlas.production_lots pl on pl.id=plt.production_lot_id where plt.task_id=p_task_id and plt.link_role='seedling_care' limit 1 for update of pl;
  if v_task.id is null or v_lot.id is null then raise exception 'Task is not a linked production seedling-care step' using errcode='22023'; end if;
  begin v_batch_id:=nullif(v_task.metadata->>'production_tray_batch_id','')::uuid; exception when others then v_batch_id:=null; end;
  if v_batch_id is null then select nullif(plt.metadata->>'tray_batch_id','')::uuid into v_batch_id from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.link_role='seedling_care' order by plt.created_at desc limit 1; end if;
  v_batch_id:=coalesce(v_batch_id,v_task.generated_from_id);
  select * into v_batch from atlas.production_tray_batches where id=v_batch_id and production_lot_id=v_lot.id for update;
  if v_batch.id is null or v_batch.status not in ('germinated','seedling_care') then raise exception 'Seedling-care task is missing its germinated tray batch' using errcode='22023'; end if;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;

  select id into v_existing from atlas.production_lot_events where farm_id=v_lot.farm_id and idempotency_key=left(v_key||':event:care',160);
  if v_existing is not null then
    return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'deduplicated',true);
  end if;
  if v_task.status not in ('open','blocked') then raise exception 'Seedling-care task is not open' using errcode='22023'; end if;
  if p_surviving_seedlings>coalesce(v_batch.viable_seedlings,v_batch.seeds_sown) then raise exception 'Surviving seedling count exceeds the tray cohort' using errcode='22023'; end if;
  if p_tray_count>v_batch.tray_count then raise exception 'Current tray count cannot exceed the sown tray count' using errcode='22023'; end if;

  update atlas.production_tray_batches set status='seedling_care',current_quantity=p_surviving_seedlings,current_unit='seedlings',tray_count=p_tray_count,metadata=metadata||jsonb_build_object('seedling_care_started_date',p_care_date),updated_at=now() where id=v_batch.id;
  update atlas.production_lots set current_quantity=p_surviving_seedlings,current_unit='seedlings',current_stage='seedling_care',metadata=metadata||jsonb_build_object('last_biological_event','seedling_care_started'),updated_at=now() where id=v_lot.id;
  update atlas.crop_cycles set cycle_state='seedling_care',coverage_kind='viable_seedlings',coverage_amount=p_surviving_seedlings,coverage_unit='seedlings',metadata=metadata||jsonb_build_object('current_tray_count',p_tray_count),updated_at=now() where id=v_batch.crop_cycle_id;
  insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,crop_cycle_id,note,source,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,'seedling_care_started',p_care_date,p_surviving_seedlings,'seedlings',p_task_id,v_batch.crop_cycle_id,p_note,'production_stage_engine',left(v_key||':event:care',160),jsonb_build_object('tray_batch_id',v_batch.id,'tray_count',p_tray_count));
  v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'done',left(v_key||':task:done',160),null,coalesce(nullif(btrim(p_note),''),'Began seedling care for '||p_surviving_seedlings::text||' seedlings.'),null,'grow_room','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'surviving_seedlings',p_surviving_seedlings,'tray_count',p_tray_count),null);

  select * into v_next_stage from atlas.production_next_propagation_operation_v1(v_lot.crop_profile_id,'seedling_care');
  select object_id into v_object_id from atlas.crop_cycles where id=v_batch.crop_cycle_id;

  if v_next_stage.stage_key is null then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'owner-lifecycle-gap','production:owner-lifecycle-gap:'||v_lot.id::text||':seedling-care',
      'Owner — Resolve next propagation stage · '||v_lot.lot_label,p_care_date,p_care_date,
      'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_task.organization_id,
      'Atlas has living seedlings but the crop lifecycle contract does not name a required downstream propagation operation.',
      jsonb_build_object('task_key','production_lifecycle_gap_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_profile_id',v_lot.crop_profile_id,'blocked_stage','seedling_care','display_action','Resolve lifecycle','display_subject',v_lot.lot_label,'display_detail','No required next propagation stage in crop contract','collection_zone','Owner'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','lifecycle_gap_decision','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'after_stage','seedling_care'))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'required','dependency',null,jsonb_build_object('kind','lifecycle_contract_gap','effect','Living production has no governed next operation.'),true
    );
  elsif v_next_stage.stage_key='pot_up' then
    v_container:=coalesce(nullif(v_next_stage.rule_payload->>'container_kind',''),nullif(v_profile.metadata->>'pot_up_container_kind',''),nullif(v_profile.metadata->>'output_container_kind',''));
    v_due:=greatest(p_care_date,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0));
    v_latest:=case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end;
    if v_container is null then
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'owner-pot-up-method','production:owner-pot-up-method:'||v_lot.id::text,
        'Owner — Set pot-up container · '||v_lot.lot_label,p_care_date,p_care_date,
        'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_task.organization_id,
        'This crop requires pot-up, but Atlas does not have a governed output container. Define the container before worker pot-up work can be released.',
        jsonb_build_object('task_key','production_pot_up_method_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_profile_id',v_lot.crop_profile_id,'required_stage','pot_up','timing_window_start',v_due,'timing_window_end',v_latest,'display_action','Set container','display_subject',v_lot.lot_label||' pot-up','display_detail','Pot-up required · output container unknown','collection_zone','Owner'),
        jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','pot_up_method_decision','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'required_stage','pot_up'))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'required','dependency',v_latest,jsonb_build_object('kind','propagation_method_gap','effect','Required pot-up cannot be released without an output container.'),true
      );
    else
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'pot-up','production:pot-up:'||v_batch.id::text,
        'Pot up · '||v_lot.lot_label,v_due,v_due,
        'production_tray_batch',v_batch.id,'pot_up','pot_up','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
        'Move this exact seedling cohort into the governed output container and record actual living plants and tray count.',
        jsonb_build_object('task_key','production_pot_up_'||v_batch.id::text,'task_style','production_pot_up','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'input_container_kind',v_batch.container_kind,'output_container_kind',v_container,'display_action','Pot up','display_subject',v_lot.lot_label,'display_detail',v_container,'collection_zone','Grow Room','structured_result_required',true),
        jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','pot_up','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_latest,jsonb_build_object('kind','pot_up_window','effect','Required pot-up is entering or inside its biological window.'),false
      );
    end if;
  elsif v_next_stage.stage_key='harden' then
    v_due:=greatest(p_care_date,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>'hardening_start_date','')::date,p_care_date));
    v_latest:=coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start);
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'hardening','production:hardening:'||v_batch.id::text,
      'Harden off · '||v_lot.lot_label,v_due,v_due,
      'production_tray_batch',v_batch.id,'hardening_off','hardening_off','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
      'Begin governed outdoor acclimation for this exact cohort. Preserve its current container unless the lifecycle contract explicitly requires a different operation.',
      jsonb_build_object('task_key','production_hardening_'||v_lot.stable_key,'task_style','production_hardening','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind,'pot_up_required',false,'display_action','Harden off','display_subject',v_lot.lot_label,'display_detail','Begin outdoor acclimation · transplant target '||coalesce(v_lot.expected_transplant_start::text,'unknown'),'collection_zone','Grow Room + hardening area','continuity_contract','seedling_care_to_hardening_to_transplant_v1'),
      jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','hardening','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_latest,jsonb_build_object('kind','biological_pressure','effect','Missing hardening compresses the acclimation window before transplant.'),false
    );
  else
    v_due:=greatest(p_care_date,coalesce(v_lot.expected_transplant_start,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0)));
    v_latest:=coalesce(v_lot.expected_transplant_end,case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end,v_due+5);
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'transplant-readiness','production:transplant-readiness:'||v_batch.id::text,
      'Check transplant readiness · '||v_lot.lot_label,v_due,v_due,
      'production_tray_batch',v_batch.id,'transplant_readiness','transplant_readiness','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
      'Count surviving seedlings and confirm whether this exact cohort is field-ready. If it is not ready, record a later recheck date.',
      jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'task_style','transplant_readiness','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'expected_transplant_start',v_lot.expected_transplant_start,'expected_transplant_end',v_lot.expected_transplant_end,'container_kind',v_batch.container_kind,'display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Counted cohort + field readiness'),'collection_zone','Grow Room','structured_result_required',true),
      jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_latest,jsonb_build_object('kind','transplant_window','effect','Readiness must be checked before the transplant window closes.'),false
    );
  end if;

  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('next_action',case when v_next_stage.stage_key='transplant' then 'transplant_readiness' else coalesce(v_next_stage.stage_key,'owner_decision') end,'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',coalesce(v_due,p_care_date)),updated_at=now() where id=v_batch.crop_cycle_id;
  update atlas.production_lots set metadata=metadata||jsonb_build_object('next_action',case when v_next_stage.stage_key='transplant' then 'transplant_readiness' else coalesce(v_next_stage.stage_key,'owner_decision') end,'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',coalesce(v_due,p_care_date)),updated_at=now() where id=v_lot.id;

  return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'nextStage',v_next_stage.stage_key,'nextOccurrenceId',v_next->>'occurrenceId','nextTaskId',v_next->>'taskId','survivingSeedlings',p_surviving_seedlings,'trayCount',p_tray_count,'deduplicated',false);
end;
$function$;
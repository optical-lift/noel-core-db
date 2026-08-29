create or replace function atlas.record_production_pot_up_v1(p_task_id uuid,p_outputs jsonb,p_care_date date default current_date,p_note text default null,p_idempotency_key text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_output jsonb;
  v_cycle_id uuid;
  v_lot atlas.production_lots%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_batch_id uuid;
  v_batch_number integer;
  v_living numeric;
  v_trays numeric;
  v_container text;
  v_expected_container text;
  v_expected_count integer;
  v_output_count integer;
  v_distinct_output_count integer;
  v_key text;
  v_batch_key text;
  v_result jsonb:='[]'::jsonb;
  v_next_stage record;
  v_due date;
  v_latest date;
  v_next jsonb;
  v_object_id uuid;
begin
  if p_task_id is null then raise exception 'A pot-up task is required.' using errcode='22023'; end if;
  if p_care_date is null then p_care_date:=current_date; end if;
  if jsonb_typeof(p_outputs) is distinct from 'array' or jsonb_array_length(p_outputs)=0 then raise exception 'Pot-up output must be a non-empty array.' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Pot-up task was not found.' using errcode='P0002'; end if;
  if lower(coalesce(v_task.action_key,''))<>'pot_up' and lower(coalesce(v_task.task_type,''))<>'pot_up' then raise exception 'Task is not a pot-up operation.' using errcode='23514'; end if;
  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'production-pot-up:'||p_task_id::text||':'||p_care_date::text);
  v_expected_container:=nullif(btrim(coalesce(v_task.metadata->>'output_container_kind','')),'');

  select count(distinct tc.crop_cycle_id)::integer into v_expected_count
  from atlas.task_crop_cycles tc
  join atlas.production_lot_crop_cycles plc on plc.crop_cycle_id=tc.crop_cycle_id and plc.relation_role='primary'
  join atlas.production_lots pl on pl.id=plc.production_lot_id and pl.lifecycle_status='active'
  where tc.task_id=p_task_id and tc.role in ('preserves','affects');
  select jsonb_array_length(p_outputs),count(distinct (x.value->>'cropCycleId'))::integer into v_output_count,v_distinct_output_count from jsonb_array_elements(p_outputs) x(value);
  if coalesce(v_expected_count,0)=0 then raise exception 'Pot-up task has no active production-lot crop lineage.' using errcode='23514'; end if;
  if v_output_count<>v_expected_count or v_distinct_output_count<>v_expected_count then raise exception 'Pot-up output must contain exactly one result for each production-linked crop cycle (% expected).',v_expected_count using errcode='23514'; end if;

  if v_task.status='done' then
    if (select count(*) from atlas.production_tray_batches b where b.source_task_id=p_task_id and b.idempotency_key like v_key||':batch:%')=v_expected_count then
      return jsonb_build_object('contractVersion','record_production_pot_up_v1','applied',false,'state','already_applied','taskId',p_task_id,'outputs',(
        select coalesce(jsonb_agg(jsonb_build_object('trayBatchId',b.id,'cropCycleId',b.crop_cycle_id,'livingPlants',b.current_quantity,'trayCount',b.tray_count,'containerKind',b.container_kind) order by b.batch_number),'[]'::jsonb)
        from atlas.production_tray_batches b where b.source_task_id=p_task_id and b.idempotency_key like v_key||':batch:%'
      ));
    end if;
    raise exception 'Pot-up task is complete without a matching production output contract.' using errcode='23514';
  end if;
  if v_task.status not in ('open','blocked') then raise exception 'Pot-up task is not actionable.' using errcode='23514'; end if;

  for v_output in select value from jsonb_array_elements(p_outputs)
  loop
    begin v_cycle_id:=(v_output->>'cropCycleId')::uuid; exception when others then raise exception 'Each pot-up output requires a valid cropCycleId.' using errcode='22023'; end;
    v_living:=nullif(v_output->>'livingPlants','')::numeric;
    v_trays:=nullif(v_output->>'trayCount','')::numeric;
    v_container:=nullif(btrim(coalesce(v_output->>'containerKind',v_expected_container,'')),'');
    if v_living is null or v_living<=0 then raise exception 'Pot-up livingPlants must be greater than zero for crop cycle %.',v_cycle_id using errcode='23514'; end if;
    if v_trays is null or v_trays<=0 or trunc(v_trays)<>v_trays then raise exception 'Pot-up trayCount must be a positive whole number for crop cycle %.',v_cycle_id using errcode='23514'; end if;
    if v_container is null then raise exception 'Pot-up containerKind is required for crop cycle %.',v_cycle_id using errcode='23514'; end if;
    if v_expected_container is not null and lower(v_container)<>lower(v_expected_container) then raise exception 'Pot-up output container % does not match the governed task container %.',v_container,v_expected_container using errcode='23514'; end if;
    if not exists(select 1 from atlas.task_crop_cycles tc where tc.task_id=p_task_id and tc.crop_cycle_id=v_cycle_id and tc.role in ('preserves','affects')) then raise exception 'Crop cycle % is not governed by this pot-up task.',v_cycle_id using errcode='23514'; end if;

    select pl.* into v_lot
    from atlas.production_lot_crop_cycles plc join atlas.production_lots pl on pl.id=plc.production_lot_id
    where plc.crop_cycle_id=v_cycle_id and plc.relation_role='primary' and pl.lifecycle_status='active'
    order by pl.created_at desc limit 1;
    if v_lot.id is null then raise exception 'No active production lot is linked to crop cycle %.',v_cycle_id using errcode='23514'; end if;
    select * into v_cycle from atlas.crop_cycles where id=v_cycle_id for update;
    select * into v_profile from atlas.crop_profiles where id=v_cycle.crop_profile_id;
    v_object_id:=v_cycle.object_id;

    v_batch_key:=v_key||':batch:'||v_cycle_id::text;
    select id into v_batch_id from atlas.production_tray_batches where farm_id=v_task.farm_id and idempotency_key=v_batch_key;
    if v_batch_id is null then
      select coalesce(max(batch_number),0)+1 into v_batch_number from atlas.production_tray_batches where production_lot_id=v_lot.id;
      insert into atlas.production_tray_batches(farm_id,production_lot_id,source_task_id,crop_cycle_id,batch_number,batch_label,container_kind,tray_count,status,sown_date,viable_seedlings,current_quantity,current_unit,idempotency_key,last_observed_at,metadata)
      values(v_task.farm_id,v_lot.id,p_task_id,v_cycle_id,v_batch_number,v_lot.lot_label||' · pot-up '||p_care_date::text,v_container,v_trays,'seedling_care',coalesce(v_lot.actual_sow_date,v_cycle.sown_date),v_living,v_living,'seedlings',v_batch_key,now(),jsonb_build_object('source','record_production_pot_up_v1','pot_up_date',p_care_date,'input_container_kind',coalesce(v_task.metadata->>'input_container_kind',v_cycle.metadata->>'current_container_kind'),'output_container_kind',v_container,'actual_living_plants',v_living,'actual_tray_count',v_trays,'source_task_id',p_task_id,'crop_cycle_id',v_cycle_id)) returning id into v_batch_id;
    end if;

    update atlas.production_lots set current_stage='seedling_care',current_quantity=v_living,current_unit='seedlings',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('last_pot_up_task_id',p_task_id,'last_pot_up_date',p_care_date,'current_container_kind',v_container,'current_tray_count',v_trays,'current_tray_batch_id',v_batch_id),updated_at=now() where id=v_lot.id;
    update atlas.crop_cycles set cycle_state='seedling_care',coverage_amount=v_trays,coverage_unit='trays',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('current_container_kind',v_container,'current_container_count',v_trays,'current_live_seedlings',v_living,'last_pot_up_task_id',p_task_id,'last_pot_up_date',p_care_date,'production_tray_batch_id',v_batch_id),updated_at=now() where id=v_cycle_id;
    insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata) values(v_lot.id,p_task_id,'pot_up','record_production_pot_up_v1',jsonb_build_object('crop_cycle_id',v_cycle_id,'tray_batch_id',v_batch_id)) on conflict(production_lot_id,task_id,link_role) do update set metadata=atlas.production_lot_tasks.metadata||excluded.metadata;
    insert into atlas.production_lot_events(farm_id,production_lot_id,tray_batch_id,crop_cycle_id,task_id,event_type,event_date,quantity,unit,note,idempotency_key,source,metadata)
    values(v_task.farm_id,v_lot.id,v_batch_id,v_cycle_id,p_task_id,'pot_up_completed',p_care_date,v_living,'seedlings',p_note,v_key||':event:'||v_cycle_id::text,'record_production_pot_up_v1',jsonb_build_object('containerKind',v_container,'trayCount',v_trays)) on conflict(farm_id,idempotency_key) do nothing;

    select * into v_next_stage from atlas.production_next_propagation_operation_v1(v_lot.crop_profile_id,'pot_up');
    if v_next_stage.stage_key='harden' then
      v_due:=greatest(p_care_date,coalesce(v_lot.actual_sow_date,p_care_date)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>'hardening_start_date','')::date,p_care_date));
      v_latest:=coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,p_care_date)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start);
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'hardening','production:hardening:'||v_batch_id::text,'Harden off · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch_id,'hardening_off','hardening_off','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
        'Begin governed outdoor acclimation for this exact potted-up cohort. Keep its production identity intact and record the actual hardening start.',
        jsonb_build_object('task_key','production_hardening_'||v_lot.stable_key,'task_style','production_hardening','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id,'container_kind',v_container,'display_action','Harden off','display_subject',v_lot.lot_label,'display_detail','Begin outdoor acclimation · transplant target '||coalesce(v_lot.expected_transplant_start::text,'unknown'),'collection_zone','Grow Room + hardening area'),
        jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_cycle_id,'role','affects','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','hardening','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_latest,jsonb_build_object('kind','biological_pressure','effect','Required hardening must precede field readiness.'),false
      );
    elsif v_next_stage.stage_key='transplant' then
      v_due:=greatest(p_care_date,coalesce(v_lot.expected_transplant_start,p_care_date));
      v_latest:=coalesce(v_lot.expected_transplant_end,v_due+5);
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'transplant-readiness','production:transplant-readiness:'||v_batch_id::text,'Check transplant readiness · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch_id,'transplant_readiness','transplant_readiness','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
        'Count surviving seedlings and confirm whether this exact cohort is field-ready. If it is not ready, record a later recheck date.',
        jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'task_style','transplant_readiness','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id,'container_kind',v_container,'display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Counted cohort + field readiness'),'collection_zone','Grow Room','structured_result_required',true),
        jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_cycle_id,'role','observes','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_latest,jsonb_build_object('kind','transplant_window','effect','Readiness must be checked before the transplant window closes.'),false
      );
    else
      v_due:=p_care_date;
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'owner-lifecycle-gap','production:owner-lifecycle-gap:'||v_lot.id::text||':pot-up','Owner — Resolve next stage after pot-up · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch_id,'owner_decision','decide','owner_decision','high','owner',null,null,v_task.organization_id,
        'Pot-up is complete, but the crop lifecycle contract does not name a required downstream propagation operation. Resolve the next stage before worker work is released.',
        jsonb_build_object('owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch_id,'crop_profile_id',v_lot.crop_profile_id,'blocked_stage','pot_up','display_action','Resolve lifecycle','display_subject',v_lot.lot_label,'display_detail','No required next stage after pot-up','collection_zone','Owner'),
        jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_cycle_id,'role','observes','confidence','confirmed','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','lifecycle_gap_decision','source','production_stage_compiler','metadata',jsonb_build_object('tray_batch_id',v_batch_id,'after_stage','pot_up'))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'required','dependency',null,jsonb_build_object('kind','lifecycle_contract_gap','effect','Potted production has no governed next operation.'),true
      );
    end if;

    update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action',coalesce(v_next_stage.stage_key,'owner_decision'),'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due),updated_at=now() where id=v_cycle_id;
    update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action',coalesce(v_next_stage.stage_key,'owner_decision'),'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due),updated_at=now() where id=v_lot.id;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('cropCycleId',v_cycle_id,'productionLotId',v_lot.id,'trayBatchId',v_batch_id,'livingPlants',v_living,'trayCount',v_trays,'containerKind',v_container,'nextStage',v_next_stage.stage_key,'nextOccurrenceId',v_next->>'occurrenceId','nextDueDate',v_due));
  end loop;

  perform atlas.record_task_transition_v1_internal(p_task_id,'done',v_key,null,p_note,'Pot-up output inventory was captured into production lineage before completion.','pot_up','production_pot_up',jsonb_build_object('productionOutputs',v_result,'careDate',p_care_date),null);
  return jsonb_build_object('contractVersion','record_production_pot_up_v1','applied',true,'state','pot_up_recorded','taskId',p_task_id,'careDate',p_care_date,'outputs',v_result);
end;
$function$;
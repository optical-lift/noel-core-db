create or replace function atlas.record_production_pot_up_v1(
  p_task_id uuid,
  p_outputs jsonb,
  p_care_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
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
  v_hardening_date date;
  v_hardening_latest date;
  v_hardening_occurrence_id uuid;
  v_hardening_work_definition_id uuid;
  v_hardening_release_policy_id uuid;
  v_expected_count integer;
  v_output_count integer;
  v_distinct_output_count integer;
  v_key text;
  v_batch_key text;
  v_result jsonb:='[]'::jsonb;
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

  select wd.id,rp.id into v_hardening_work_definition_id,v_hardening_release_policy_id
  from atlas.work_definitions wd join atlas.work_release_policies rp on rp.work_definition_id=wd.id and rp.active
  where wd.farm_id=v_task.farm_id and wd.stable_key='production:hardening:v1' and rp.stable_key='production:hardening:v1:time-window' and wd.active
  limit 1;
  if v_hardening_work_definition_id is null or v_hardening_release_policy_id is null then raise exception 'Canonical production hardening reservoir contract is missing.' using errcode='23514'; end if;

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

    v_batch_key:=v_key||':batch:'||v_cycle_id::text;
    select id into v_batch_id from atlas.production_tray_batches where farm_id=v_task.farm_id and idempotency_key=v_batch_key;
    if v_batch_id is null then
      select coalesce(max(batch_number),0)+1 into v_batch_number from atlas.production_tray_batches where production_lot_id=v_lot.id;
      insert into atlas.production_tray_batches(
        farm_id,production_lot_id,source_task_id,crop_cycle_id,batch_number,batch_label,container_kind,tray_count,status,sown_date,viable_seedlings,current_quantity,current_unit,idempotency_key,last_observed_at,metadata
      ) values (
        v_task.farm_id,v_lot.id,p_task_id,v_cycle_id,v_batch_number,v_lot.lot_label||' · pot-up '||p_care_date::text,v_container,v_trays,'seedling_care',coalesce(v_lot.actual_sow_date,v_cycle.sown_date),v_living,v_living,'seedlings',v_batch_key,now(),
        jsonb_build_object('source','record_production_pot_up_v1','pot_up_date',p_care_date,'input_container_kind',coalesce(v_task.metadata->>'input_container_kind',v_cycle.metadata->>'current_container_kind'),'output_container_kind',v_container,'actual_living_plants',v_living,'actual_tray_count',v_trays,'source_task_id',p_task_id,'crop_cycle_id',v_cycle_id)
      ) returning id into v_batch_id;
    end if;

    update atlas.production_lots set current_stage='seedling_care',current_quantity=v_living,current_unit='seedlings',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('last_pot_up_task_id',p_task_id,'last_pot_up_date',p_care_date,'current_container_kind',v_container,'current_tray_count',v_trays,'current_tray_batch_id',v_batch_id),updated_at=now() where id=v_lot.id;
    update atlas.crop_cycles set cycle_state='seedling_care',coverage_amount=v_trays,coverage_unit='trays',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('current_container_kind',v_container,'current_container_count',v_trays,'current_live_seedlings',v_living,'last_pot_up_task_id',p_task_id,'last_pot_up_date',p_care_date,'production_tray_batch_id',v_batch_id),updated_at=now() where id=v_cycle_id;

    insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata) values(v_lot.id,p_task_id,'pot_up','record_production_pot_up_v1',jsonb_build_object('crop_cycle_id',v_cycle_id,'tray_batch_id',v_batch_id)) on conflict(production_lot_id,task_id,link_role) do update set metadata=atlas.production_lot_tasks.metadata||excluded.metadata;
    insert into atlas.production_lot_events(farm_id,production_lot_id,tray_batch_id,crop_cycle_id,task_id,event_type,event_date,quantity,unit,note,idempotency_key,source,metadata)
    values(v_task.farm_id,v_lot.id,v_batch_id,v_cycle_id,p_task_id,'pot_up_completed',p_care_date,v_living,'seedlings',p_note,v_key||':event:'||v_cycle_id::text,'record_production_pot_up_v1',jsonb_build_object('containerKind',v_container,'trayCount',v_trays)) on conflict(farm_id,idempotency_key) do nothing;

    v_hardening_date:=greatest(p_care_date,coalesce(nullif(v_profile.metadata->>'hardening_start_date','')::date,nullif(v_lot.metadata->>'hardening_start_date','')::date,v_lot.expected_transplant_start-coalesce(nullif(v_profile.metadata->>'hardening_duration_days_max','')::integer,14)));
    v_hardening_latest:=coalesce(v_lot.expected_transplant_start-coalesce(nullif(v_profile.metadata->>'hardening_duration_days_min','')::integer,10),v_hardening_date+4);
    select id into v_hardening_occurrence_id from atlas.planned_work_occurrences where farm_id=v_lot.farm_id and occurrence_key='production:hardening:'||v_batch_id::text limit 1;
    if v_hardening_occurrence_id is null then
      insert into atlas.planned_work_occurrences(
        farm_id,work_definition_id,release_policy_id,occurrence_key,source_kind,source_id,title,planned_due_date,not_before_date,state,task_payload,relation_payload,metadata,work_lane,commitment_kind,effort_units,earliest_lawful_date,preferred_start_date,preferred_end_date,latest_lawful_date,hard_finish_date,miss_consequence,temporal_contract_source
      ) values (
        v_lot.farm_id,v_hardening_work_definition_id,v_hardening_release_policy_id,'production:hardening:'||v_batch_id::text,'production_tray_batch',v_batch_id,'Harden off · '||v_lot.lot_label,
        v_hardening_date,v_hardening_date,'planned',
        jsonb_build_object('title','Harden off · '||v_lot.lot_label,'task_type','hardening_off','priority','high','zone_id',coalesce(v_task.zone_id,'91602b6e-3e8e-4e67-b9fb-bfb01e56fe2f'::uuid),'note','Begin governed outdoor acclimation for the potted-up cohort. Keep the cohort identity intact and record the actual hardening start; transplant readiness remains a separate later check.','action_key','hardening_off','work_class','standard','visibility_scope','assigned_worker','assigned_membership_id',v_task.assigned_membership_id,'assigned_user_id',v_task.assigned_user_id,'origin_kind','generated','task_scope','farm_operation','organization_id',v_task.organization_id,'generated_from','production_tray_batch','generated_from_id',v_batch_id,'work_lane','process_continuation','commitment_kind','dependency','metadata',jsonb_build_object('task_key','production_hardening_'||v_lot.stable_key,'anna_task',true,'owner_task',false,'work_route','hardening_off','assigned_to','Anna','assignee_key','anna','executor_worker_key','anna','executor_membership_id',v_task.assigned_membership_id,'collection_zone','Grow Room + hardening area','collection_label','Overwinter Snapdragon Hardening','display_action','Harden off','display_subject',v_lot.lot_label,'display_detail','Begin outdoor acclimation · transplant target '||coalesce(v_lot.expected_transplant_start::text,'unknown'),'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id,'hardening_start_date',v_hardening_date,'target_transplant_start',v_lot.expected_transplant_start,'target_transplant_end',v_lot.expected_transplant_end,'continuity_contract','pot_up_to_hardening_to_transplant_v1')),
        jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_cycle_id,'role','affects','confidence','confirmed','source','record_production_pot_up_v1','metadata',jsonb_build_object('tray_batch_id',v_batch_id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','hardening','source','record_production_pot_up_v1','metadata',jsonb_build_object('tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        jsonb_build_object('continuity_contract','pot_up_to_hardening_to_transplant_v1','production_lot_id',v_lot.id,'tray_batch_id',v_batch_id,'crop_cycle_id',v_cycle_id),
        'process_continuation','dependency',1,v_hardening_date,v_hardening_date,v_hardening_latest,v_hardening_latest,v_hardening_latest,
        jsonb_build_object('kind','biological_pressure','effect','Missing hardening compresses the acclimation window before transplant.'),'crop_profile_hardening_window'
      ) returning id into v_hardening_occurrence_id;
    end if;
    update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','hardening_off','next_action_occurrence_id',v_hardening_occurrence_id,'next_action_due_date',v_hardening_date),updated_at=now() where id=v_cycle_id;
    update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','hardening_off','next_action_occurrence_id',v_hardening_occurrence_id,'next_action_due_date',v_hardening_date),updated_at=now() where id=v_lot.id;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('cropCycleId',v_cycle_id,'productionLotId',v_lot.id,'trayBatchId',v_batch_id,'livingPlants',v_living,'trayCount',v_trays,'containerKind',v_container,'hardeningOccurrenceId',v_hardening_occurrence_id,'hardeningDueDate',v_hardening_date));
  end loop;

  perform atlas.record_task_transition_v1_internal(p_task_id,'done',v_key,null,p_note,'Pot-up output inventory was captured into production lineage before completion.','pot_up','production_pot_up',jsonb_build_object('productionOutputs',v_result,'careDate',p_care_date),null);
  return jsonb_build_object('contractVersion','record_production_pot_up_v1','applied',true,'state','pot_up_recorded','taskId',p_task_id,'careDate',p_care_date,'outputs',v_result);
end;
$function$;
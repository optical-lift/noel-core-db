create or replace function atlas.record_production_harvest_readiness_v1(
  p_task_id uuid,
  p_action text,
  p_observations jsonb,
  p_observed_date date,
  p_recheck_date date,
  p_note text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_gate atlas.production_harvest_gates%rowtype;
  v_gate_id uuid;
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing uuid;
  v_row record;
  v_stand atlas.production_field_stands%rowtype;
  v_transition jsonb;
  v_estimate numeric:=0;
  v_observation_id uuid;
  v_not_ready integer:=0;
  v_next jsonb;
  v_objects jsonb;
  v_cycles jsonb;
begin
  if p_task_id is null or p_action not in ('not_ready','ready') or p_observations is null or jsonb_typeof(p_observations)<>'array' or jsonb_array_length(p_observations)=0 or p_observed_date is null then raise exception 'Task, readiness action, per-bed observations, and date are required' using errcode='22023'; end if;
  if p_action='not_ready' and (p_recheck_date is null or p_recheck_date<=p_observed_date) then raise exception 'Not-ready observation requires a later recheck date' using errcode='22023'; end if;
  if v_key is null or length(v_key)>120 then raise exception 'A valid harvest-readiness idempotency key is required' using errcode='22023'; end if;
  if p_observed_date>v_today+1 then raise exception 'Readiness date cannot be in the future' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  select pl.* into v_lot from atlas.production_lot_tasks plt join atlas.production_lots pl on pl.id=plt.production_lot_id where plt.task_id=p_task_id and plt.link_role='harvest_readiness' limit 1 for update of pl;
  if v_task.id is null or v_lot.id is null then raise exception 'Task is not a linked harvest-readiness check' using errcode='22023'; end if;

  begin v_gate_id:=nullif(v_task.metadata->>'production_harvest_gate_id','')::uuid; exception when others then v_gate_id:=null; end;
  if v_gate_id is null then
    select nullif(plt.metadata->>'harvest_gate_id','')::uuid into v_gate_id from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.link_role='harvest_readiness' order by plt.created_at desc limit 1;
  end if;
  v_gate_id:=coalesce(v_gate_id,v_task.generated_from_id);
  select * into v_gate from atlas.production_harvest_gates where id=v_gate_id and production_lot_id=v_lot.id for update;
  if v_gate.id is null or v_gate.gate_status not in ('ready_for_watch','harvest_watch') then raise exception 'Harvest gate is not open for readiness observation' using errcode='22023'; end if;
  update atlas.production_harvest_gates set harvest_readiness_task_id=p_task_id,gate_status='harvest_watch',updated_at=now() where id=v_gate.id;

  select id into v_existing from atlas.production_lot_events where farm_id=v_lot.farm_id and idempotency_key=left(v_key||':event:readiness',160);
  if v_existing is not null then return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'action',p_action,'deduplicated',true); end if;
  if v_task.status not in ('open','blocked') then raise exception 'Harvest-readiness task is not open' using errcode='22023'; end if;

  create temporary table if not exists pg_temp.production_harvest_readiness_input(object_id uuid primary key,is_ready boolean not null,marketable_stem_estimate numeric) on commit drop;
  truncate pg_temp.production_harvest_readiness_input;
  insert into pg_temp.production_harvest_readiness_input(object_id,is_ready,marketable_stem_estimate)
  select (x->>'objectId')::uuid,(x->>'ready')::boolean,case when nullif(x->>'marketableStemEstimate','') is null then null else (x->>'marketableStemEstimate')::numeric end from jsonb_array_elements(p_observations) x;
  if (select count(*) from pg_temp.production_harvest_readiness_input)<>(select count(*) from atlas.production_field_stands where production_lot_id=v_lot.id and current_plants>0 and stand_status not in ('failed','cleared')) then raise exception 'Every living field stand requires a readiness observation' using errcode='22023'; end if;
  if exists(select 1 from pg_temp.production_harvest_readiness_input i left join atlas.production_field_stands s on s.production_lot_id=v_lot.id and s.object_id=i.object_id and s.current_plants>0 where s.id is null or coalesce(i.marketable_stem_estimate,0)<0) then raise exception 'Readiness observations must use living field stands and nonnegative estimates' using errcode='22023'; end if;
  select count(*) filter(where not is_ready),coalesce(sum(marketable_stem_estimate),0) into v_not_ready,v_estimate from pg_temp.production_harvest_readiness_input;
  if p_action='ready' and v_not_ready>0 then raise exception 'A ready cohort requires every living field stand to be marked ready' using errcode='22023'; end if;
  if p_action='not_ready' and v_not_ready=0 then raise exception 'Not-ready action requires at least one stand marked not ready' using errcode='22023'; end if;

  for v_row in select * from pg_temp.production_harvest_readiness_input loop
    select * into v_stand from atlas.production_field_stands where production_lot_id=v_lot.id and object_id=v_row.object_id for update;
    insert into atlas.production_field_observations(farm_id,production_lot_id,field_stand_id,task_id,object_id,crop_cycle_id,observation_type,outcome,observed_date,quantity,unit,note,idempotency_key,metadata)
    values(v_lot.farm_id,v_lot.id,v_stand.id,p_task_id,v_stand.object_id,v_stand.crop_cycle_id,'harvest_readiness',case when v_row.is_ready then 'ready' else 'not_ready' end,p_observed_date,v_row.marketable_stem_estimate,'estimated_marketable_stems',p_note,left(v_key||':stand:'||v_stand.id::text,160),jsonb_build_object('next_check_date',case when p_action='not_ready' then p_recheck_date else null end,'confidence',case when v_row.marketable_stem_estimate is null then 'observed' else 'estimated' end)) returning id into v_observation_id;
  end loop;

  insert into atlas.production_lot_events(farm_id,production_lot_id,event_type,event_date,quantity,unit,task_id,note,source,idempotency_key,metadata)
  values(v_lot.farm_id,v_lot.id,case when p_action='ready' then 'harvest_readiness_confirmed' else 'harvest_not_ready' end,p_observed_date,v_estimate,'estimated_marketable_stems',p_task_id,p_note,'production_stage_engine',left(v_key||':event:readiness',160),jsonb_build_object('harvest_gate_id',v_gate.id,'observations',p_observations,'next_check_date',p_recheck_date));

  if p_action='not_ready' then
    v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'rescheduled',left(v_key||':task:not-ready',160),p_recheck_date,coalesce(nullif(btrim(p_note),''),'The field cohort is not ready to cut.'),'Harvest stage not reached.','harvest','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'harvest_gate_id',v_gate.id,'estimated_marketable_stems',v_estimate,'next_check_date',p_recheck_date),null);
    return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'action','not_ready','estimatedMarketableStems',v_estimate,'nextDate',p_recheck_date,'deduplicated',false);
  end if;

  v_transition:=atlas.record_task_transition_v1_internal(p_task_id,'done',left(v_key||':task:ready',160),null,coalesce(nullif(btrim(p_note),''),'Every living field stand reached harvest readiness.'),null,'harvest','production_lot',jsonb_build_object('production_lot_id',v_lot.id,'harvest_gate_id',v_gate.id,'estimated_marketable_stems',v_estimate),null);

  select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','harvest_source') order by object_id),'[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','harvests','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('harvest_gate_id',v_gate.id)) order by crop_cycle_id),'[]'::jsonb)
  into v_objects,v_cycles
  from atlas.production_field_stands where production_lot_id=v_lot.id and current_plants>0;

  v_next:=atlas.author_production_work_occurrence_v1(
    v_lot.farm_id,'harvest','production:harvest:'||v_gate.id::text,
    'Harvest + count marketable stems — '||v_lot.lot_label,p_observed_date,p_observed_date,
    'production_harvest_gate',v_gate.id,'production_harvest','harvest','standard','high',v_task.visibility_scope,v_task.assigned_membership_id,v_task.assigned_user_id,v_task.organization_id,
    'Cut this exact cohort and record actual marketable, second-quality, and discarded stems. The readiness estimate is not the harvest count.',
    jsonb_build_object('task_key','production_harvest_'||v_gate.id::text,'task_style','production_harvest','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_harvest_gate_id',v_gate.id,'readiness_estimated_marketable_stems',v_estimate,'display_action','Harvest + count','display_subject',v_lot.lot_label,'display_detail',case when v_estimate>0 then v_estimate::text||' estimated marketable stems' else 'Count actual cut stems' end,'collection_zone','Production beds'),
    jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','harvest','source','production_stage_engine','metadata',jsonb_build_object('harvest_gate_id',v_gate.id,'readiness_task_id',p_task_id,'estimated_marketable_stems',v_estimate))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
    'required','dependency',p_observed_date+1,jsonb_build_object('kind','harvest_ready','effect','Marketable stems are ready and should be cut and counted.'),true
  );

  update atlas.production_harvest_gates
  set gate_status='harvest_ready',harvest_task_id=coalesce(nullif(v_next->>'taskId','')::uuid,harvest_task_id),ready_at=now(),blocker_text=null,
      metadata=metadata||jsonb_build_object('readiness_date',p_observed_date,'readiness_estimated_marketable_stems',v_estimate,'harvest_occurrence_id',v_next->>'occurrenceId'),updated_at=now()
  where id=v_gate.id;
  update atlas.production_lots set current_stage='harvest_watch',metadata=metadata||jsonb_build_object('last_biological_event','harvest_readiness_confirmed','harvest_readiness_date',p_observed_date,'readiness_estimated_marketable_stems',v_estimate),updated_at=now() where id=v_lot.id;
  update atlas.production_field_stands set stand_status='harvest_watch',metadata=metadata||jsonb_build_object('harvest_readiness_date',p_observed_date),updated_at=now() where production_lot_id=v_lot.id and current_plants>0;
  update atlas.crop_cycles set cycle_state='harvest_watch',expected_harvest_watch_start=coalesce(expected_harvest_watch_start,p_observed_date),metadata=metadata||jsonb_build_object('harvest_readiness_date',p_observed_date),updated_at=now() where id in (select crop_cycle_id from atlas.production_field_stands where production_lot_id=v_lot.id and current_plants>0);

  return jsonb_build_object('taskId',p_task_id,'productionLotId',v_lot.id,'action','ready','estimatedMarketableStems',v_estimate,'harvestOccurrenceId',v_next->>'occurrenceId','harvestTaskId',v_next->>'taskId','deduplicated',false);
end;
$function$;
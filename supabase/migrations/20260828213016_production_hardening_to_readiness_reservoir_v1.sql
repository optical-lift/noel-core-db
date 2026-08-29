create or replace function atlas.record_production_hardening_v1(
  p_task_id uuid,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
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
  v_readiness_work_definition_id uuid;
  v_readiness_release_policy_id uuid;
  v_readiness_date date;
  v_readiness_latest date;
  v_key text;
  v_existing_event uuid;
begin
  if p_task_id is null or p_observed_date is null then raise exception 'Hardening task and observed date are required.' using errcode='22023'; end if;
  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'production-hardening:'||p_task_id::text||':'||p_observed_date::text);
  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  if lower(coalesce(v_task.action_key,'')) not in ('hardening_off','harden','hardening') and lower(coalesce(v_task.task_type,'')) not in ('hardening_off','hardening') then raise exception 'Task is not a governed hardening operation.' using errcode='23514'; end if;

  select plt.production_lot_id,coalesce(v_task.generated_from_id,nullif(plt.metadata->>'tray_batch_id','')::uuid)
  into v_lot_id,v_batch_id
  from atlas.production_lot_tasks plt
  where plt.task_id=p_task_id and plt.link_role='hardening'
  order by plt.created_at desc limit 1;
  if v_lot_id is null or v_batch_id is null then raise exception 'Hardening task is missing production lot or tray-batch lineage.' using errcode='23514'; end if;
  select * into v_lot from atlas.production_lots where id=v_lot_id for update;
  select * into v_batch from atlas.production_tray_batches where id=v_batch_id and production_lot_id=v_lot.id for update;
  if v_batch.id is null or v_batch.status not in ('seedling_care','hardening') then raise exception 'Hardening task is missing an eligible potted-up tray batch.' using errcode='23514'; end if;
  select * into v_cycle from atlas.crop_cycles where id=v_batch.crop_cycle_id for update;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;

  select id into v_existing_event from atlas.production_lot_events where farm_id=v_lot.farm_id and idempotency_key=v_key||':event';
  if v_existing_event is not null then return jsonb_build_object('contractVersion','record_production_hardening_v1','applied',false,'state','already_applied','taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'eventId',v_existing_event); end if;
  if v_task.status not in ('open','blocked') then raise exception 'Hardening task is not actionable.' using errcode='23514'; end if;

  update atlas.production_tray_batches set status='hardening',last_action_at=now(),last_observed_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('hardening_started_date',p_observed_date,'hardening_task_id',p_task_id,'hardening_note',p_note),updated_at=now() where id=v_batch.id;
  update atlas.production_lots set current_stage='hardening',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('last_biological_event','hardening_started','hardening_started_date',p_observed_date,'hardening_task_id',p_task_id),updated_at=now() where id=v_lot.id;
  if v_cycle.id is not null then update atlas.crop_cycles set cycle_state='hardening_off',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('hardening_started_date',p_observed_date,'hardening_task_id',p_task_id,'production_tray_batch_id',v_batch.id),updated_at=now() where id=v_cycle.id; end if;
  insert into atlas.production_lot_events(farm_id,production_lot_id,tray_batch_id,crop_cycle_id,task_id,event_type,event_date,quantity,unit,note,idempotency_key,source,metadata)
  values(v_lot.farm_id,v_lot.id,v_batch.id,v_batch.crop_cycle_id,p_task_id,'hardening_started',p_observed_date,v_batch.current_quantity,coalesce(v_batch.current_unit,'seedlings'),p_note,v_key||':event','record_production_hardening_v1',jsonb_build_object('containerKind',v_batch.container_kind,'trayCount',v_batch.tray_count,'readinessCue',v_profile.metadata->>'transplant_readiness_cue'));

  select wd.id,rp.id into v_readiness_work_definition_id,v_readiness_release_policy_id
  from atlas.work_definitions wd join atlas.work_release_policies rp on rp.work_definition_id=wd.id and rp.active
  where wd.farm_id=v_lot.farm_id and wd.stable_key='production:transplant-readiness:v1' and rp.stable_key='production:transplant-readiness:v1:time-window' and wd.active limit 1;
  if v_readiness_work_definition_id is null or v_readiness_release_policy_id is null then raise exception 'Canonical production readiness reservoir contract is missing.' using errcode='23514'; end if;

  v_readiness_date:=greatest(p_observed_date,coalesce(v_lot.expected_transplant_start,p_observed_date+coalesce(nullif(v_profile.metadata->>'hardening_duration_days_min','')::integer,10)));
  v_readiness_latest:=coalesce(v_lot.expected_transplant_end,v_readiness_date+5);
  select id into v_readiness_occurrence_id from atlas.planned_work_occurrences where farm_id=v_lot.farm_id and occurrence_key='production:transplant-readiness:'||v_batch.id::text limit 1;
  if v_readiness_occurrence_id is null then
    insert into atlas.planned_work_occurrences(
      farm_id,work_definition_id,release_policy_id,occurrence_key,source_kind,source_id,title,planned_due_date,not_before_date,state,task_payload,relation_payload,metadata,work_lane,commitment_kind,effort_units,earliest_lawful_date,preferred_start_date,preferred_end_date,latest_lawful_date,hard_finish_date,miss_consequence,temporal_contract_source
    ) values (
      v_lot.farm_id,v_readiness_work_definition_id,v_readiness_release_policy_id,'production:transplant-readiness:'||v_batch.id::text,'production_tray_batch',v_batch.id,'Check transplant readiness · '||v_lot.lot_label,
      v_readiness_date,v_readiness_date,'planned',
      jsonb_build_object('title','Check transplant readiness · '||v_lot.lot_label,'task_type','transplant_readiness','priority','high','zone_id',v_task.zone_id,'note','Check the hardened cohort against its stored readiness cue. Count the living seedlings and trays. If it is not ready, record a later recheck date rather than forcing transplant.','action_key','transplant_readiness','work_class','standard','visibility_scope','assigned_worker','assigned_membership_id',v_task.assigned_membership_id,'assigned_user_id',v_task.assigned_user_id,'origin_kind','generated','task_scope','farm_operation','organization_id',v_task.organization_id,'generated_from','production_tray_batch','generated_from_id',v_batch.id,'work_lane','process_continuation','commitment_kind','dependency','metadata',jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'anna_task',true,'owner_task',false,'work_route','transplant_readiness','assigned_to','Anna','assignee_key','anna','executor_worker_key','anna','executor_membership_id',v_task.assigned_membership_id,'collection_zone','Hardening area','collection_label','Overwinter Snapdragon Readiness','display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Hardened, rooted seedlings ready for field conditions'),'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'hardening_started_date',p_observed_date,'readiness_cue',v_profile.metadata->>'transplant_readiness_cue','target_transplant_start',v_lot.expected_transplant_start,'target_transplant_end',v_lot.expected_transplant_end,'structured_result_required',true,'continuity_contract','hardening_to_transplant_readiness_v1')),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','record_production_hardening_v1','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','record_production_hardening_v1','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      jsonb_build_object('continuity_contract','hardening_to_transplant_readiness_v1','production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'readiness_cue',v_profile.metadata->>'transplant_readiness_cue'),
      'process_continuation','dependency',1,v_readiness_date,v_readiness_date,v_readiness_latest,v_readiness_latest,v_readiness_latest,
      jsonb_build_object('kind','biological_pressure','effect','Readiness must be checked before the Sep 15-20 transplant window closes.'),'production_transplant_window'
    ) returning id into v_readiness_occurrence_id;
  end if;

  if v_cycle.id is not null then update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_readiness_occurrence_id,'next_action_due_date',v_readiness_date),updated_at=now() where id=v_cycle.id; end if;
  update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_readiness_occurrence_id,'next_action_due_date',v_readiness_date),updated_at=now() where id=v_lot.id;

  perform atlas.record_task_transition_v1_internal(p_task_id,'done',v_key||':task',null,p_note,'Hardening start was recorded before the task completed.','hardening_off','production_hardening',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'hardening_started_date',p_observed_date,'readiness_occurrence_id',v_readiness_occurrence_id,'readiness_due_date',v_readiness_date),null);
  return jsonb_build_object('contractVersion','record_production_hardening_v1','applied',true,'state','hardening_started','taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'hardeningStartedDate',p_observed_date,'readinessOccurrenceId',v_readiness_occurrence_id,'readinessDueDate',v_readiness_date);
end;
$function$;
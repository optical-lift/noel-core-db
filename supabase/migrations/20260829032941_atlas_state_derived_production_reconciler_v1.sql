alter function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean)
rename to author_production_work_occurrence_internal_v1;

revoke all on function atlas.author_production_work_occurrence_internal_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) from public, anon, authenticated, service_role;
grant execute on function atlas.author_production_work_occurrence_internal_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) to postgres;

create or replace function atlas.author_production_work_occurrence_v1(
  p_farm_id uuid,
  p_work_key text,
  p_occurrence_key text,
  p_title text,
  p_due_date date,
  p_not_before_date date,
  p_source_kind text,
  p_source_id uuid,
  p_task_type text,
  p_action_key text,
  p_work_class text,
  p_priority text,
  p_visibility_scope text,
  p_assigned_membership_id uuid,
  p_assigned_user_id uuid,
  p_organization_id uuid,
  p_note text,
  p_metadata jsonb default '{}'::jsonb,
  p_relation_payload jsonb default '{}'::jsonb,
  p_work_lane text default 'process_continuation',
  p_commitment_kind text default 'dependency',
  p_latest_lawful_date date default null,
  p_miss_consequence jsonb default '{}'::jsonb,
  p_release_if_due boolean default false
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_reconciler_active boolean := coalesce(current_setting('atlas.production_reconciler_active', true),'')='on';
  v_governed boolean;
  v_existing atlas.planned_work_occurrences%rowtype;
begin
  v_governed := p_work_key in (
    'hardening','transplant-readiness','owner-seedling-recovery','owner-bed-math',
    'transplant','establishment','field-water','field-weed','owner-field-failure',
    'owner-harvest-rules','harvest-readiness'
  ) or p_work_key like 'field-care-%';

  if v_governed and not v_reconciler_active then
    select * into v_existing
    from atlas.planned_work_occurrences
    where farm_id=p_farm_id and occurrence_key=p_occurrence_key
    order by created_at desc
    limit 1;

    if v_existing.id is not null then
      return jsonb_build_object(
        'occurrenceId',v_existing.id,
        'taskId',v_existing.released_task_id,
        'state',v_existing.state,
        'authority','production_reconciler',
        'deduplicated',true
      );
    end if;

    return jsonb_build_object(
      'occurrenceId',null,
      'taskId',null,
      'state','deferred_to_reconciler',
      'authority','production_reconciler',
      'deduplicated',false
    );
  end if;

  return atlas.author_production_work_occurrence_internal_v1(
    p_farm_id,p_work_key,p_occurrence_key,p_title,p_due_date,p_not_before_date,
    p_source_kind,p_source_id,p_task_type,p_action_key,p_work_class,p_priority,
    p_visibility_scope,p_assigned_membership_id,p_assigned_user_id,p_organization_id,
    p_note,p_metadata,p_relation_payload,p_work_lane,p_commitment_kind,
    p_latest_lawful_date,p_miss_consequence,p_release_if_due
  );
end;
$function$;

revoke all on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) from public, anon, authenticated;
grant execute on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) to postgres, service_role;

create or replace function atlas.reconcile_production_work_v1(
  p_production_lot_id uuid,
  p_as_of_date date default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_today date := coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_prior text := current_setting('atlas.production_reconciler_active',true);
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_source atlas.tasks%rowtype;
  v_event atlas.production_lot_events%rowtype;
  v_obs atlas.production_readiness_observations%rowtype;
  v_gate jsonb;
  v_harvest_gate jsonb;
  v_next jsonb;
  v_next_stage record;
  v_object_id uuid;
  v_due date;
  v_latest date;
  v_rows numeric;
  v_spacing numeric;
  v_bed_feet numeric;
  v_req_id uuid;
  v_transplant_date date;
  v_transplant_gate_id uuid;
  v_relation_objects jsonb;
  v_relation_cycles jsonb;
  v_water_objects jsonb;
  v_water_cycles jsonb;
  v_weed_objects jsonb;
  v_weed_cycles jsonb;
  v_all_cycles jsonb;
  v_work jsonb := '[]'::jsonb;
  v_context_org uuid;
begin
  if p_production_lot_id is null then raise exception 'Production lot is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.production.reconcile:'||p_production_lot_id::text,0));
  perform set_config('atlas.production_reconciler_active','on',true);

  select * into v_lot from atlas.production_lots where id=p_production_lot_id for update;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  select * into v_batch from atlas.production_tray_batches where production_lot_id=v_lot.id order by batch_number desc,created_at desc limit 1;
  select * into v_event from atlas.production_lot_events where production_lot_id=v_lot.id order by event_date desc,created_at desc limit 1;

  if v_event.task_id is not null then select * into v_source from atlas.tasks where id=v_event.task_id; end if;
  if v_source.id is null then
    select t.* into v_source
    from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id
    where plt.production_lot_id=v_lot.id
    order by t.created_at desc limit 1;
  end if;
  v_context_org:=coalesce(v_source.organization_id,(select organization_id from atlas.farms where id=v_lot.farm_id));
  if v_source.visibility_scope is null then v_source.visibility_scope:='assigned_worker'; end if;

  if v_lot.lifecycle_status in ('complete','cancelled','archived') then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    return jsonb_build_object('productionLotId',v_lot.id,'currentStage',v_lot.current_stage,'state','terminal','work',v_work);
  end if;

  if v_lot.current_stage='seedling_care' and v_batch.id is not null and v_batch.status='seedling_care' then
    select * into v_next_stage from atlas.production_next_propagation_operation_v1(v_lot.crop_profile_id,'seedling_care');
    if v_next_stage.stage_key='harden' then
      select object_id into v_object_id from atlas.crop_cycles where id=v_batch.crop_cycle_id;
      v_due:=greatest(
        coalesce(nullif(v_lot.metadata->>'hardening_start_date','')::date,v_today),
        coalesce(v_lot.actual_sow_date,v_today)+coalesce(v_next_stage.timing_min_days,0)
      );
      v_latest:=coalesce(
        case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,v_today)+v_next_stage.timing_max_days end,
        v_lot.expected_transplant_start,
        v_due+7
      );
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'hardening','production:hardening:'||v_batch.id::text,
        'Harden off · '||v_lot.lot_label,v_due,v_due,
        'production_tray_batch',v_batch.id,'hardening_off','hardening_off','standard','high',
        coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_context_org,
        'Begin governed outdoor acclimation for this exact cohort. Preserve its current container unless the lifecycle contract explicitly requires a different operation.',
        jsonb_build_object('task_key','production_hardening_'||v_lot.stable_key,'task_style','production_hardening','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind,'pot_up_required',false,'display_action','Harden off','display_subject',v_lot.lot_label,'display_detail','Begin outdoor acclimation · transplant target '||coalesce(v_lot.expected_transplant_start::text,'unknown'),'collection_zone','Grow Room + hardening area','continuity_contract','state_derived_production_v1','structured_result_required',true),
        jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','hardening','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_latest,jsonb_build_object('kind','biological_pressure','effect','Missing hardening compresses the acclimation window before transplant.'),false
      );
      v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','hardening','occurrenceId',v_next->>'occurrenceId'));
      update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','hardening_off','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due,'next_action_authority','production_reconciler'),updated_at=now() where id=v_lot.id;
      update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','hardening_off','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due,'next_action_authority','production_reconciler'),updated_at=now() where id=v_batch.crop_cycle_id;
    end if;
  end if;

  if v_lot.current_stage='hardening' and v_batch.id is not null then
    v_due:=coalesce(nullif(v_lot.metadata->>'next_readiness_check_date','')::date,v_lot.expected_transplant_start,
      coalesce(v_event.event_date,v_today)+coalesce(nullif(v_profile.metadata->>'hardening_duration_days_min','')::integer,10));
    v_due:=greatest(v_due,coalesce(v_event.event_date,v_today));
    v_latest:=coalesce(v_lot.expected_transplant_end,v_due+5);
    select object_id into v_object_id from atlas.crop_cycles where id=v_batch.crop_cycle_id;
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'transplant-readiness','production:transplant-readiness:'||v_batch.id::text,
      'Check transplant readiness · '||v_lot.lot_label,v_due,v_due,
      'production_tray_batch',v_batch.id,'transplant_readiness','transplant_readiness','standard','high',
      coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_context_org,
      'Count surviving seedlings and confirm whether this exact hardened cohort is field-ready. If it is not ready, record a later recheck date.',
      jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'task_style','transplant_readiness','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'hardening_started_date',v_lot.metadata->>'hardening_started_date','expected_transplant_start',v_lot.expected_transplant_start,'expected_transplant_end',v_lot.expected_transplant_end,'container_kind',v_batch.container_kind,'pot_up_required',false,'display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Counted cohort + field readiness'),'collection_zone','Hardening area','structured_result_required',true,'continuity_contract','state_derived_production_v1'),
      jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_latest,jsonb_build_object('kind','transplant_window','effect','Readiness must be checked before the governed transplant window closes.'),false
    );
    v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','transplant-readiness','occurrenceId',v_next->>'occurrenceId'));
    update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due,'next_action_authority','production_reconciler'),updated_at=now() where id=v_lot.id;
    update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due,'next_action_authority','production_reconciler'),updated_at=now() where id=v_batch.crop_cycle_id;
  end if;

  if v_lot.current_stage='seedling_failure_decision' and v_batch.id is not null then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'owner-seedling-recovery','production:owner-seedling-recovery:'||v_batch.id::text,
      'Owner — Decide recovery for '||v_lot.lot_label,coalesce(v_event.event_date,v_today),coalesce(v_event.event_date,v_today),
      'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_context_org,
      'The seedling cohort failed before transplant. Decide whether to reseed, replace, buy plugs, or cancel.',
      jsonb_build_object('task_key','production_seedling_failure_decision_'||v_batch.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'display_action','Decide','display_subject',v_lot.lot_label||' recovery','display_detail','0 surviving seedlings','collection_zone','Owner'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','seedling_failure_decision','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'required','dependency',null,jsonb_build_object('kind','crop_loss','effect','Production recovery decision remains unresolved.'),true
    );
    v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-seedling-recovery','occurrenceId',v_next->>'occurrenceId'));
  end if;

  if v_lot.current_stage='transplant_ready' then
    select * into v_obs from atlas.production_readiness_observations where production_lot_id=v_lot.id and observation_outcome='ready' order by observed_date desc,created_at desc limit 1;
    if v_obs.id is not null and lower(coalesce(v_profile.crop_label,'')) like '%snapdragon%' then
      select value into v_rows from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_rows_per_three_foot_bed';
      select value into v_spacing from atlas.capacity_measurements where farm_id=v_lot.farm_id and stable_key='snapdragon_in_row_spacing_inches';
      if v_rows is null or v_spacing is null then
        update atlas.production_capacity_requirements set quantity_needed=null,calculation_status='blocked',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('quantity_truth','awaiting_capacity_measurement','surviving_seedlings',v_obs.surviving_seedlings,'readiness_observation_id',v_obs.id,'reconciled_by','production_reconciler'),updated_at=now() where production_lot_id=v_lot.id and capacity_kind='bed_feet' returning id into v_req_id;
      else
        v_bed_feet:=ceil((v_obs.surviving_seedlings*v_spacing/12.0)/v_rows);
        update atlas.production_capacity_requirements set quantity_needed=v_bed_feet,calculation_status='confirmed',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('quantity_basis','counted_surviving_seedlings','surviving_seedlings',v_obs.surviving_seedlings,'rows_per_bed',v_rows,'spacing_inches',v_spacing,'readiness_observation_id',v_obs.id,'reconciled_by','production_reconciler'),updated_at=now() where production_lot_id=v_lot.id and capacity_kind='bed_feet' returning id into v_req_id;
        update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('actual_bed_feet_required',v_bed_feet),updated_at=now() where id=v_lot.id;
      end if;
    end if;

    v_gate:=atlas.refresh_production_transplant_gate_v1(v_lot.id);
    if coalesce(v_gate->>'gateStatus','')='waiting_bed_math' or coalesce(v_gate->>'status','')='waiting_bed_math' then
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'owner-bed-math','production:owner-bed-math:'||v_lot.id::text,
        'Owner — Set bed-capacity math · '||v_lot.lot_label,coalesce(v_obs.observed_date,v_today),coalesce(v_obs.observed_date,v_today),
        'production_readiness_observation',v_obs.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_context_org,
        'The cohort is biologically transplant-ready. Record the missing bed-capacity measurements so Atlas can calculate required bed-feet and open the transplant gate.',
        jsonb_build_object('task_key','production_bed_math_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'readiness_observation_id',v_obs.id,'surviving_seedlings',v_obs.surviving_seedlings,'display_action','Measure + decide','display_subject',v_lot.lot_label||' bed capacity','display_detail',coalesce(v_obs.surviving_seedlings,0)::text||' ready seedlings · transplant blocked on bed math','collection_zone','Owner','continuity_gate',true,'blocked_stage','transplant','biological_readiness_preserved',true),
        jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',case when v_batch.crop_cycle_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('readiness_observation_id',v_obs.id))) end,'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','bed_math_decision','source','production_reconciler','metadata',jsonb_build_object('readiness_observation_id',v_obs.id,'tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'required','dependency',coalesce(v_lot.expected_transplant_end,v_today+5),jsonb_build_object('kind','transplant_blocker','effect','Ready seedlings cannot be placed until bed demand is measurable.'),true
      );
      v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-bed-math','occurrenceId',v_next->>'occurrenceId'));
    else
      update atlas.planned_work_occurrences set state='cancelled',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('cancelled_by','production_reconciler','cancelled_reason','bed_math_resolved'),updated_at=now() where farm_id=v_lot.farm_id and occurrence_key='production:owner-bed-math:'||v_lot.id::text and state not in ('completed','cancelled');
    end if;
  end if;

  if v_lot.current_stage='establishment' then
    select max(event_date) into v_transplant_date from atlas.production_lot_events where production_lot_id=v_lot.id and event_type='transplanted';
    select id into v_transplant_gate_id from atlas.production_transplant_gates where production_lot_id=v_lot.id and gate_status='transplanted' order by updated_at desc limit 1;
    if v_transplant_date is not null and v_transplant_gate_id is not null then
      select coalesce(jsonb_agg(jsonb_build_object('object_id',p.object_id,'role','target') order by p.object_id),'[]'::jsonb) into v_relation_objects from atlas.production_transplant_placements p where p.production_lot_id=v_lot.id and p.transplant_gate_id=v_transplant_gate_id;
      select coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',p.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('transplant_gate_id',v_transplant_gate_id)) order by p.crop_cycle_id),'[]'::jsonb) into v_relation_cycles from atlas.production_transplant_placements p where p.production_lot_id=v_lot.id and p.transplant_gate_id=v_transplant_gate_id;
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'establishment','production:establishment:'||v_transplant_gate_id::text,
        'Check transplant establishment — '||v_lot.lot_label,v_transplant_date+3,v_transplant_date+3,
        'production_transplant_gate',v_transplant_gate_id,'production_establishment_check','observe','standard','high','assigned_worker',v_source.assigned_membership_id,v_source.assigned_user_id,v_context_org,
        'Count losses and confirm water and establishment in every assigned bed.',
        jsonb_build_object('task_key','production_establishment_'||v_transplant_gate_id::text,'task_style','production_establishment_check','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_transplant_gate_id',v_transplant_gate_id,'display_action','Check','display_subject',v_lot.lot_label||' establishment','display_detail',coalesce(v_lot.current_quantity,0)::text||' plants','collection_zone','Assigned beds','structured_result_required',true),
        jsonb_build_object('task_objects',coalesce(v_relation_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_relation_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','establishment_check','source','production_reconciler','metadata',jsonb_build_object('transplant_gate_id',v_transplant_gate_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_transplant_date+6,jsonb_build_object('kind','establishment_pressure','effect','New transplants require a governed survival check.'),false
      );
      v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','establishment','occurrenceId',v_next->>'occurrenceId'));
    end if;
    v_harvest_gate:=atlas.refresh_production_harvest_gate_v1(v_lot.id);
  end if;

  if v_lot.current_stage in ('field_care','field_failure_decision') then
    if v_event.event_type in ('established','establishment_failed','establishment_not_yet') then
      select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','target') order by object_id),'[]'::jsonb),coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata','{}'::jsonb) order by crop_cycle_id),'[]'::jsonb) into v_water_objects,v_water_cycles from atlas.production_field_care_state where production_lot_id=v_lot.id and establishment_status<>'failed' and water_status='needs_water';
      if jsonb_array_length(coalesce(v_water_objects,'[]'::jsonb))>0 then
        v_next:=atlas.author_production_work_occurrence_v1(v_lot.farm_id,'field-water','production:field-water:'||v_lot.id::text||':'||v_event.event_date::text,'Water establishment cohort — '||v_lot.lot_label,v_event.event_date,v_event.event_date,'production_establishment',v_event.task_id,'production_field_care','production_water','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_context_org,'Water every linked bed marked needs-water, then confirm completion for the cohort.',jsonb_build_object('task_key','production_field_water_'||coalesce(v_event.task_id::text,v_lot.id::text),'task_style','production_field_care','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'care_action','water','display_action','Water','display_subject',v_lot.lot_label,'display_detail','Establishment cohort','collection_zone','Production beds'),jsonb_build_object('task_objects',v_water_objects,'task_crop_cycles',v_water_cycles,'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','water_care','source','production_reconciler','metadata',jsonb_build_object('establishment_task_id',v_event.task_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'required','dependency',v_event.event_date+1,jsonb_build_object('kind','water_need','effect','Establishing plants were observed needing water.'),true);
        v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','field-water','occurrenceId',v_next->>'occurrenceId'));
      end if;
      select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','target') order by object_id),'[]'::jsonb),coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata','{}'::jsonb) order by crop_cycle_id),'[]'::jsonb) into v_weed_objects,v_weed_cycles from atlas.production_field_care_state where production_lot_id=v_lot.id and establishment_status<>'failed' and weed_pressure in ('moderate','heavy');
      if jsonb_array_length(coalesce(v_weed_objects,'[]'::jsonb))>0 then
        v_next:=atlas.author_production_work_occurrence_v1(v_lot.farm_id,'field-weed','production:field-weed:'||v_lot.id::text||':'||v_event.event_date::text,'Weed establishment cohort — '||v_lot.lot_label,v_event.event_date,v_event.event_date,'production_establishment',v_event.task_id,'production_field_care','production_weed','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_context_org,'Weed every linked bed carrying moderate or heavy pressure, then confirm completion for the cohort.',jsonb_build_object('task_key','production_field_weed_'||coalesce(v_event.task_id::text,v_lot.id::text),'task_style','production_field_care','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'care_action','weed','display_action','Weed','display_subject',v_lot.lot_label,'display_detail','Establishment cohort','collection_zone','Production beds'),jsonb_build_object('task_objects',v_weed_objects,'task_crop_cycles',v_weed_cycles,'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','weed_care','source','production_reconciler','metadata',jsonb_build_object('establishment_task_id',v_event.task_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'required','dependency',v_event.event_date+1,jsonb_build_object('kind','weed_pressure','effect','Establishing plants were observed under moderate or heavy weed pressure.'),true);
        v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','field-weed','occurrenceId',v_next->>'occurrenceId'));
      end if;
    end if;

    perform atlas.sync_production_care_policies_v1(v_lot.id);
    perform atlas.ensure_production_care_task_v1(v_lot.id,'watering');
    perform atlas.ensure_production_care_task_v1(v_lot.id,'weeding');
    perform atlas.ensure_production_care_task_v1(v_lot.id,'pinching');
    perform atlas.ensure_production_care_task_v1(v_lot.id,'support');
    perform atlas.ensure_production_care_task_v1(v_lot.id,'fertility');

    if v_lot.current_stage='field_failure_decision' then
      select coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata','{}'::jsonb) order by crop_cycle_id),'[]'::jsonb) into v_all_cycles from atlas.production_lot_crop_cycles where production_lot_id=v_lot.id;
      v_next:=atlas.author_production_work_occurrence_v1(v_lot.farm_id,'owner-field-failure','production:owner-field-failure:'||v_lot.id::text,'Owner — Decide field failure recovery — '||v_lot.lot_label,coalesce(v_event.event_date,v_today),coalesce(v_event.event_date,v_today),'production_establishment',v_event.task_id,'owner_decision','decide','owner_decision','high','owner',null,null,v_context_org,'No transplanted plants survived establishment. Decide whether to replant, replace, or cancel the crop cohort.',jsonb_build_object('task_key','production_field_failure_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'display_action','Decide','display_subject',v_lot.lot_label||' field recovery','display_detail','0 established plants','collection_zone','Owner'),jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',coalesce(v_all_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','field_failure_decision','source','production_reconciler','metadata',jsonb_build_object('establishment_task_id',v_event.task_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'required','dependency',null,jsonb_build_object('kind','crop_loss','effect','Field failure requires an owner recovery decision.'),true);
      v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-field-failure','occurrenceId',v_next->>'occurrenceId'));
    end if;
    v_harvest_gate:=atlas.refresh_production_harvest_gate_v1(v_lot.id);
  end if;

  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
  return jsonb_build_object('productionLotId',v_lot.id,'currentStage',v_lot.current_stage,'authority','production_reconciler','work',v_work,'transplantGate',v_gate,'harvestGate',v_harvest_gate);
end;
$function$;

revoke all on function atlas.reconcile_production_work_v1(uuid,date) from public, anon, authenticated;
grant execute on function atlas.reconcile_production_work_v1(uuid,date) to postgres, service_role;

create or replace function atlas.reconcile_production_work_event_trigger_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
begin
  if coalesce(current_setting('atlas.production_reconciler_active',true),'')='on' then return new; end if;
  perform atlas.reconcile_production_work_v1(new.production_lot_id,new.event_date);
  return new;
end;
$function$;
revoke all on function atlas.reconcile_production_work_event_trigger_v1() from public, anon, authenticated, service_role;
grant execute on function atlas.reconcile_production_work_event_trigger_v1() to postgres;

drop trigger if exists zz_reconcile_production_work_from_event_v1 on atlas.production_lot_events;
create trigger zz_reconcile_production_work_from_event_v1 after insert on atlas.production_lot_events for each row execute function atlas.reconcile_production_work_event_trigger_v1();

create or replace function atlas.reconcile_production_lot_change_trigger_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare v_lot_id uuid;
begin
  if coalesce(current_setting('atlas.production_reconciler_active',true),'')='on' then return coalesce(new,old); end if;
  v_lot_id:=coalesce(new.production_lot_id,old.production_lot_id);
  if v_lot_id is not null then perform atlas.reconcile_production_work_v1(v_lot_id,null); end if;
  return coalesce(new,old);
end;
$function$;
revoke all on function atlas.reconcile_production_lot_change_trigger_v1() from public, anon, authenticated, service_role;
grant execute on function atlas.reconcile_production_lot_change_trigger_v1() to postgres;

drop trigger if exists zz_reconcile_production_work_from_requirement_v1 on atlas.production_capacity_requirements;
create trigger zz_reconcile_production_work_from_requirement_v1 after insert or update of quantity_needed,calculation_status on atlas.production_capacity_requirements for each row execute function atlas.reconcile_production_lot_change_trigger_v1();

drop trigger if exists zz_reconcile_production_work_from_bed_assignment_v1 on atlas.production_bed_assignments;
create trigger zz_reconcile_production_work_from_bed_assignment_v1 after insert or update of quantity_assigned,assignment_status,planned_transplant_date or delete on atlas.production_bed_assignments for each row execute function atlas.reconcile_production_lot_change_trigger_v1();

drop trigger if exists zz_reconcile_production_work_from_harvest_rules_v1 on atlas.production_harvest_rules;
create trigger zz_reconcile_production_work_from_harvest_rules_v1 after insert or update of pinch_required,harvest_watch_start,harvest_watch_end on atlas.production_harvest_rules for each row execute function atlas.reconcile_production_lot_change_trigger_v1();

create or replace function atlas.reconcile_production_capacity_measurement_trigger_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare r record;
begin
  if coalesce(current_setting('atlas.production_reconciler_active',true),'')='on' then return new; end if;
  if new.stable_key in ('snapdragon_rows_per_three_foot_bed','snapdragon_in_row_spacing_inches') then
    for r in select id from atlas.production_lots where farm_id=new.farm_id and current_stage='transplant_ready' and lifecycle_status='active' loop
      perform atlas.reconcile_production_work_v1(r.id,null);
    end loop;
  end if;
  return new;
end;
$function$;
revoke all on function atlas.reconcile_production_capacity_measurement_trigger_v1() from public, anon, authenticated, service_role;
grant execute on function atlas.reconcile_production_capacity_measurement_trigger_v1() to postgres;

drop trigger if exists zz_reconcile_production_work_from_capacity_measurement_v1 on atlas.capacity_measurements;
create trigger zz_reconcile_production_work_from_capacity_measurement_v1 after insert or update of value on atlas.capacity_measurements for each row execute function atlas.reconcile_production_capacity_measurement_trigger_v1();

create or replace function atlas.refresh_production_transplant_gate_from_prep_task_v1() returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare v_lot_id uuid;
begin
  if new.status is not distinct from old.status or new.generated_from is distinct from 'production_bed_assignment' then return new; end if;
  begin v_lot_id:=(new.metadata->>'production_lot_id')::uuid; exception when others then v_lot_id:=null; end;
  if v_lot_id is not null and exists(select 1 from atlas.production_transplant_gates where production_lot_id=v_lot_id and gate_status<>'transplanted') then
    perform atlas.reconcile_production_work_v1(v_lot_id,null);
  end if;
  return new;
end;
$function$;

comment on function atlas.reconcile_production_work_v1(uuid,date) is 'Canonical state-derived production work reconciler. Biological/result functions record truth; this function derives downstream work from current production state.';
comment on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) is 'Production work authoring boundary. State-derived downstream work is writable only while the canonical production reconciler is active.';
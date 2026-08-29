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
    'germination','seedling-care','owner-reseed-decision','owner-lifecycle-gap','owner-pot-up-method','pot-up',
    'hardening','transplant-readiness','owner-seedling-recovery','owner-bed-math',
    'transplant','establishment','field-water','field-weed','owner-field-failure',
    'owner-harvest-rules','harvest-readiness'
  ) or p_work_key like 'field-care-%';

  if v_governed and not v_reconciler_active then
    select * into v_existing from atlas.planned_work_occurrences
    where farm_id=p_farm_id and occurrence_key=p_occurrence_key
    order by created_at desc limit 1;
    if v_existing.id is not null then
      return jsonb_build_object('occurrenceId',v_existing.id,'taskId',v_existing.released_task_id,'state',v_existing.state,'authority','production_reconciler','deduplicated',true);
    end if;
    return jsonb_build_object('occurrenceId',null,'taskId',null,'state','deferred_to_reconciler','authority','production_reconciler','deduplicated',false);
  end if;

  return atlas.author_production_work_occurrence_internal_v1(
    p_farm_id,p_work_key,p_occurrence_key,p_title,p_due_date,p_not_before_date,p_source_kind,p_source_id,
    p_task_type,p_action_key,p_work_class,p_priority,p_visibility_scope,p_assigned_membership_id,p_assigned_user_id,
    p_organization_id,p_note,p_metadata,p_relation_payload,p_work_lane,p_commitment_kind,p_latest_lawful_date,
    p_miss_consequence,p_release_if_due
  );
end;
$function$;

create or replace function atlas.reconcile_production_propagation_work_v1(
  p_production_lot_id uuid,
  p_as_of_date date default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_today date:=coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_prior text:=current_setting('atlas.production_reconciler_active',true);
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_source atlas.tasks%rowtype;
  v_event atlas.production_lot_events%rowtype;
  v_next_stage record;
  v_next jsonb;
  v_work jsonb:='[]'::jsonb;
  v_object_id uuid;
  v_org uuid;
  v_due date;
  v_latest date;
  v_after_stage text;
  v_container text;
  v_next_action text;
begin
  perform set_config('atlas.production_reconciler_active','on',true);
  select * into v_lot from atlas.production_lots where id=p_production_lot_id for update;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  select * into v_batch from atlas.production_tray_batches where production_lot_id=v_lot.id order by batch_number desc,created_at desc limit 1;
  select * into v_event from atlas.production_lot_events where production_lot_id=v_lot.id order by event_date desc,created_at desc limit 1;
  if v_event.task_id is not null then select * into v_source from atlas.tasks where id=v_event.task_id; end if;
  if v_source.id is null then
    select t.* into v_source from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id where plt.production_lot_id=v_lot.id order by t.created_at desc limit 1;
  end if;
  v_org:=coalesce(v_source.organization_id,(select organization_id from atlas.farms where id=v_lot.farm_id));
  select object_id into v_object_id from atlas.crop_cycles where id=v_batch.crop_cycle_id;

  if v_lot.lifecycle_status not in ('active','planned') then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    return jsonb_build_object('productionLotId',v_lot.id,'work',v_work,'state','not_active');
  end if;

  if v_lot.current_stage='germination_pending' and v_batch.id is not null then
    v_due:=coalesce(v_batch.expected_germination_start,greatest(coalesce(v_batch.sown_date,v_lot.actual_sow_date,v_today)+1,v_today));
    v_latest:=coalesce(v_batch.expected_germination_end,v_due+7);
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'germination','production:germination:'||v_batch.id::text,
      'Count germination — '||v_lot.lot_label,v_due,v_due,
      'production_tray_batch',v_batch.id,'production_germination_check','observe','light','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_org,
      'Count emerged seedlings for this exact tray batch. “Not yet” moves the check to tomorrow.',
      jsonb_build_object('task_key','production_germination_'||v_batch.id::text,'task_style','production_germination_check','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'crop_profile_id',v_lot.crop_profile_id,'production_crop_label',v_profile.crop_label,'production_variety',v_profile.variety,'tray_count',v_batch.tray_count,'seeds_sown',v_batch.seeds_sown,'germination_status','production_managed','display_action','Count','display_subject',v_lot.lot_label||' germination','display_detail',coalesce(v_batch.tray_count,0)::text||' trays','collection_zone','Grow Room','assigned_to',v_source.metadata->>'assigned_to','next_action_authority','production_reconciler'),
      jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','germination_check','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_latest,jsonb_build_object('kind','germination_window','effect','Germination needs a counted observation inside the expected window.'),false
    );
    v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','germination','occurrenceId',v_next->>'occurrenceId'));
    v_next_action:='germination_check';
  elsif v_lot.current_stage='reseed_decision' and v_batch.id is not null then
    v_due:=coalesce(v_event.event_date,v_today);
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'owner-reseed-decision','production:owner-reseed-decision:'||v_batch.id::text,
      'Owner — Decide whether to reseed '||v_lot.lot_label,v_due,v_due,
      'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_org,
      'The recorded tray batch produced zero seedlings. Decide whether to reseed, replace, or cancel this production lot.',
      jsonb_build_object('task_key','production_reseed_decision_'||v_batch.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'failed_seed_quantity',v_batch.seeds_sown,'display_action','Decide','display_subject',v_lot.lot_label||' reseed','display_detail','0 of '||coalesce(v_batch.seeds_sown,0)::text||' seeds germinated','collection_zone','Owner','assigned_to','Owner','next_action_authority','production_reconciler'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','reseed_decision','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'required','dependency',null,jsonb_build_object('kind','germination_failure','effect','Production cannot continue until recovery is decided.'),true
    );
    v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-reseed-decision','occurrenceId',v_next->>'occurrenceId'));
    v_next_action:='owner_reseed_decision';
  elsif v_lot.current_stage='seedling_care' and v_batch.id is not null then
    if v_batch.status='germinated' then
      v_due:=coalesce(v_batch.germinated_date,v_event.event_date,v_today);
      v_next:=atlas.author_production_work_occurrence_v1(
        v_lot.farm_id,'seedling-care','production:seedling-care:'||v_batch.id::text,
        'Move under lights + begin seedling care — '||v_lot.lot_label,v_due,v_due,
        'production_tray_batch',v_batch.id,'seedling_care','grow_room','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_org,
        'Move this exact tray batch under its reserved lights and begin counted seedling care.',
        jsonb_build_object('task_key','production_seedling_care_'||v_batch.id::text,'task_style','production_seedling_care','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'viable_seedlings',v_batch.current_quantity,'tray_count',v_batch.tray_count,'display_action','Move + care','display_subject',v_lot.lot_label,'display_detail',coalesce(v_batch.current_quantity,0)::text||' seedlings · '||coalesce(v_batch.tray_count,0)::text||' trays','collection_zone','Grow Room','assigned_to',v_source.metadata->>'assigned_to','next_action_authority','production_reconciler'),
        jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','seedling_care','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
        'process_continuation','dependency',v_due+1,jsonb_build_object('kind','seedling_care','effect','Germinated seedlings require immediate grow-room care.'),true
      );
      v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','seedling-care','occurrenceId',v_next->>'occurrenceId'));
      v_next_action:='seedling_care';
    elsif v_batch.status='seedling_care' then
      v_after_stage:=case when v_event.event_type='pot_up_completed' and v_event.tray_batch_id=v_batch.id then 'pot_up' else 'seedling_care' end;
      select * into v_next_stage from atlas.production_next_propagation_operation_v1(v_lot.crop_profile_id,v_after_stage);
      if v_next_stage.stage_key is null then
        v_due:=coalesce(v_event.event_date,v_today);
        v_next:=atlas.author_production_work_occurrence_v1(
          v_lot.farm_id,'owner-lifecycle-gap','production:owner-lifecycle-gap:'||v_lot.id::text||':'||replace(v_after_stage,'_','-'),
          'Owner — Resolve next propagation stage · '||v_lot.lot_label,v_due,v_due,
          'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_org,
          'Atlas has living seedlings but the crop lifecycle contract does not name a required downstream propagation operation.',
          jsonb_build_object('task_key','production_lifecycle_gap_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_profile_id',v_lot.crop_profile_id,'blocked_stage',v_after_stage,'display_action','Resolve lifecycle','display_subject',v_lot.lot_label,'display_detail','No required next propagation stage in crop contract','collection_zone','Owner','next_action_authority','production_reconciler'),
          jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','lifecycle_gap_decision','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'after_stage',v_after_stage))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
          'required','dependency',null,jsonb_build_object('kind','lifecycle_contract_gap','effect','Living production has no governed next operation.'),true
        );
        v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-lifecycle-gap','occurrenceId',v_next->>'occurrenceId'));
        v_next_action:='owner_decision';
      elsif v_next_stage.stage_key='pot_up' then
        v_due:=greatest(coalesce(v_event.event_date,v_today),coalesce(v_lot.actual_sow_date,v_today)+coalesce(v_next_stage.timing_min_days,0));
        v_latest:=case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,v_today)+v_next_stage.timing_max_days end;
        v_container:=coalesce(nullif(v_next_stage.rule_payload->>'container_kind',''),nullif(v_profile.metadata->>'pot_up_container_kind',''),nullif(v_profile.metadata->>'output_container_kind',''));
        if v_container is null then
          v_next:=atlas.author_production_work_occurrence_v1(
            v_lot.farm_id,'owner-pot-up-method','production:owner-pot-up-method:'||v_lot.id::text,'Owner — Set pot-up container · '||v_lot.lot_label,coalesce(v_event.event_date,v_today),coalesce(v_event.event_date,v_today),'production_tray_batch',v_batch.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_org,'This crop requires pot-up, but Atlas does not have a governed output container. Define the container before worker pot-up work can be released.',jsonb_build_object('task_key','production_pot_up_method_'||v_lot.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_profile_id',v_lot.crop_profile_id,'required_stage','pot_up','timing_window_start',v_due,'timing_window_end',v_latest,'display_action','Set container','display_subject',v_lot.lot_label||' pot-up','display_detail','Pot-up required · output container unknown','collection_zone','Owner','next_action_authority','production_reconciler'),jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','pot_up_method_decision','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'required_stage','pot_up'))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'required','dependency',v_latest,jsonb_build_object('kind','propagation_method_gap','effect','Required pot-up cannot be released without an output container.'),true
          );
          v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','owner-pot-up-method','occurrenceId',v_next->>'occurrenceId'));
          v_next_action:='owner_decision';
        else
          v_next:=atlas.author_production_work_occurrence_v1(
            v_lot.farm_id,'pot-up','production:pot-up:'||v_batch.id::text,'Pot up · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch.id,'pot_up','pot_up','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_org,'Move this exact seedling cohort into the governed output container and record actual living plants and tray count.',jsonb_build_object('task_key','production_pot_up_'||v_batch.id::text,'task_style','production_pot_up','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'input_container_kind',v_batch.container_kind,'output_container_kind',v_container,'display_action','Pot up','display_subject',v_lot.lot_label,'display_detail',v_container,'collection_zone','Grow Room','structured_result_required',true,'next_action_authority','production_reconciler'),jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','pot_up','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'process_continuation','dependency',v_latest,jsonb_build_object('kind','pot_up_window','effect','Required pot-up is entering or inside its biological window.'),false
          );
          v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','pot-up','occurrenceId',v_next->>'occurrenceId'));
          v_next_action:='pot_up';
        end if;
      elsif v_next_stage.stage_key='harden' then
        v_due:=greatest(coalesce(v_event.event_date,v_today),coalesce(v_lot.actual_sow_date,v_today)+coalesce(v_next_stage.timing_min_days,0),coalesce(nullif(v_lot.metadata->>'hardening_start_date','')::date,coalesce(v_event.event_date,v_today)));
        v_latest:=coalesce(case when v_next_stage.timing_max_days is null then null else coalesce(v_lot.actual_sow_date,v_today)+v_next_stage.timing_max_days end,v_lot.expected_transplant_start,v_due+7);
        v_next:=atlas.author_production_work_occurrence_v1(
          v_lot.farm_id,'hardening','production:hardening:'||v_batch.id::text,'Harden off · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch.id,'hardening_off','hardening_off','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_org,'Begin governed outdoor acclimation for this exact cohort. Preserve its current container unless the lifecycle contract explicitly requires a different operation.',jsonb_build_object('task_key','production_hardening_'||v_lot.stable_key,'task_style','production_hardening','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind,'display_action','Harden off','display_subject',v_lot.lot_label,'display_detail','Begin outdoor acclimation · transplant target '||coalesce(v_lot.expected_transplant_start::text,'unknown'),'collection_zone','Grow Room + hardening area','structured_result_required',true,'next_action_authority','production_reconciler'),jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','affects','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','hardening','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'process_continuation','dependency',v_latest,jsonb_build_object('kind','biological_pressure','effect','Required hardening must precede field readiness.'),false
        );
        v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','hardening','occurrenceId',v_next->>'occurrenceId'));
        v_next_action:='hardening_off';
      elsif v_next_stage.stage_key='transplant' then
        v_due:=greatest(coalesce(v_event.event_date,v_today),coalesce(v_lot.expected_transplant_start,coalesce(v_event.event_date,v_today)));
        v_latest:=coalesce(v_lot.expected_transplant_end,v_due+5);
        v_next:=atlas.author_production_work_occurrence_v1(
          v_lot.farm_id,'transplant-readiness','production:transplant-readiness:'||v_batch.id::text,'Check transplant readiness · '||v_lot.lot_label,v_due,v_due,'production_tray_batch',v_batch.id,'transplant_readiness','transplant_readiness','standard','high',coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,v_org,'Count surviving seedlings and confirm whether this exact cohort is field-ready. If it is not ready, record a later recheck date.',jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'task_style','transplant_readiness','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind',v_batch.container_kind,'display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Counted cohort + field readiness'),'collection_zone','Grow Room','structured_result_required',true,'next_action_authority','production_reconciler'),jsonb_build_object('task_objects',case when v_object_id is null then jsonb_build_array() else jsonb_build_array(jsonb_build_object('object_id',v_object_id,'role','primary_location')) end,'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id))),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','production_reconciler','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),'process_continuation','dependency',v_latest,jsonb_build_object('kind','transplant_window','effect','Readiness must be checked before the transplant window closes.'),false
        );
        v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','transplant-readiness','occurrenceId',v_next->>'occurrenceId'));
        v_next_action:='transplant_readiness';
      end if;
    end if;
  end if;

  if v_next is not null and v_batch.crop_cycle_id is not null then
    update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action',v_next_action,'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',coalesce(v_due,v_today),'next_action_authority','production_reconciler'),updated_at=now() where id=v_batch.crop_cycle_id;
    update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action',v_next_action,'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',coalesce(v_due,v_today),'next_action_authority','production_reconciler'),updated_at=now() where id=v_lot.id;
  end if;

  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
  return jsonb_build_object('productionLotId',v_lot.id,'currentStage',v_lot.current_stage,'authority','production_reconciler','work',v_work);
end;
$function$;
revoke all on function atlas.reconcile_production_propagation_work_v1(uuid,date) from public,anon,authenticated,service_role;
grant execute on function atlas.reconcile_production_propagation_work_v1(uuid,date) to postgres;

alter function atlas.reconcile_production_work_v1(uuid,date) rename to reconcile_production_work_downstream_v1;
revoke all on function atlas.reconcile_production_work_downstream_v1(uuid,date) from public,anon,authenticated,service_role;
grant execute on function atlas.reconcile_production_work_downstream_v1(uuid,date) to postgres;

create or replace function atlas.reconcile_production_work_v1(p_production_lot_id uuid,p_as_of_date date default null) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_prop jsonb;
  v_down jsonb;
begin
  if p_production_lot_id is null then raise exception 'Production lot is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.production.reconcile:entry:'||p_production_lot_id::text,0));
  v_prop:=atlas.reconcile_production_propagation_work_v1(p_production_lot_id,p_as_of_date);
  v_down:=atlas.reconcile_production_work_downstream_v1(p_production_lot_id,p_as_of_date);
  return jsonb_build_object(
    'productionLotId',p_production_lot_id,
    'authority','production_reconciler',
    'currentStage',coalesce(v_down->>'currentStage',v_prop->>'currentStage'),
    'work',coalesce(v_prop->'work','[]'::jsonb)||coalesce(v_down->'work','[]'::jsonb),
    'transplantGate',v_down->'transplantGate',
    'harvestGate',v_down->'harvestGate'
  );
end;
$function$;
revoke all on function atlas.reconcile_production_work_v1(uuid,date) from public,anon,authenticated;
grant execute on function atlas.reconcile_production_work_v1(uuid,date) to postgres,service_role;

comment on function atlas.reconcile_production_work_v1(uuid,date) is 'Single canonical state-derived production work reconciler. It derives propagation and downstream work from current domain truth; result functions do not own successor work.';
create or replace function atlas.ensure_production_clear_path_v1(p_production_lot_id uuid,p_source_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_event atlas.production_lot_events%rowtype;
  v_source_task atlas.tasks%rowtype;
  v_terminal record;
  v_due date;
  v_offset integer;
  v_next jsonb;
  v_role text;
  v_objects jsonb;
  v_cycles jsonb;
begin
  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_lot.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select * into v_event from atlas.production_lot_events where id=p_source_event_id and production_lot_id=v_lot.id;
  if v_event.id is null or v_event.event_type<>'harvest_recorded' or coalesce(v_event.metadata->>'harvest_action','')<>'complete' then
    return jsonb_build_object('state','not_applicable','productionLotId',v_lot.id,'reason','Clear path is created only after a counted complete harvest event.');
  end if;

  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  select * into v_source_task from atlas.tasks where id=v_event.task_id;
  select c.stage_key,c.disposition,c.rule_payload,c.contract_source,c.note
  into v_terminal
  from atlas.v_crop_lifecycle_contract_v1 c
  where c.crop_profile_id=v_lot.crop_profile_id and c.stage_key='terminal_disposition';
  v_offset:=v_profile.clear_offset_days;

  select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','clear_source') order by object_id),'[]'::jsonb)
  into v_objects from atlas.production_field_stands where production_lot_id=v_lot.id and stand_status<>'cleared';
  select coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','terminates','confidence','confirmed','source','production_actual_reforecast_v1','metadata','{}'::jsonb) order by crop_cycle_id),'[]'::jsonb)
  into v_cycles from atlas.production_field_stands where production_lot_id=v_lot.id and stand_status<>'cleared';

  if coalesce(v_terminal.disposition,'unknown')='required' and v_offset is not null then
    v_due:=v_event.event_date+v_offset;
    v_role:='clear';
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'clear','production:clear:'||v_lot.id::text,
      'Clear finished production cohort — '||v_lot.lot_label,v_due,v_due,
      'production_lot_event',v_event.id,'production_clear','clear','heavy','high',
      coalesce(v_source_task.visibility_scope,'farm_shared'),v_source_task.assigned_membership_id,v_source_task.assigned_user_id,v_source_task.organization_id,
      'Clear the finished field cohort and record the actual release of occupied beds. Turnover remains a separate next state.',
      jsonb_build_object('production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'source_harvest_event_id',v_event.id,'clear_offset_days',v_offset,'display_action','Clear','display_subject',v_lot.lot_label,'collection_zone','Production beds','operation_class','remove_uproot'),
      jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','clear','source','production_actual_reforecast_v1','metadata',jsonb_build_object('source_event_id',v_event.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_due+3,jsonb_build_object('kind','terminal_clear','effect','Finished crop body remains in occupied production beds until physically cleared.'),false
    );
  else
    v_due:=v_event.event_date;
    v_role:='termination_decision';
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'owner-terminal-disposition','production:owner-terminal-disposition:'||v_lot.id::text,
      'Owner — Set post-harvest disposition · '||v_lot.lot_label,v_due,v_due,
      'production_lot_event',v_event.id,'owner_decision','decide','owner_decision','high','owner',null,null,coalesce(v_source_task.organization_id,(select organization_id from atlas.farms where id=v_lot.farm_id)),
      case
        when coalesce(v_terminal.disposition,'unknown')='required' and v_offset is null then 'A complete harvest was recorded and terminal clearing is required, but the crop profile has no confirmed clear timing. Set the clear timing.'
        else 'A complete harvest was recorded, but Atlas does not have a confirmed terminal disposition for this crop. Decide whether this cohort should clear/turn over or persist into its next living season; do not infer annual behavior from the harvest event.' end,
      jsonb_build_object('owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'source_harvest_event_id',v_event.id,'terminal_contract_disposition',coalesce(v_terminal.disposition,'unknown'),'terminal_contract_source',v_terminal.contract_source,'life_cycle',v_profile.life_cycle,'clear_offset_days',v_offset,'display_action','Set disposition','display_subject',v_lot.lot_label,'display_detail',case when coalesce(v_terminal.disposition,'unknown')='required' then 'Clear required · timing unresolved' else 'Clear vs persist unresolved' end,'collection_zone','Owner','continuity_gate',true,'blocked_stage','terminal_disposition'),
      jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','termination_decision','source','production_actual_reforecast_v1','metadata',jsonb_build_object('source_event_id',v_event.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'required','dependency',null,jsonb_build_object('kind','terminal_contract_gap','effect','A completed harvest cannot silently terminate or persist the crop without an explicit lifecycle disposition.'),true
    );
  end if;

  update atlas.production_lots set metadata=metadata||jsonb_build_object('next_action',v_role,'next_action_occurrence_id',v_next->>'occurrenceId','next_action_due_date',v_due,'terminal_disposition_contract',coalesce(v_terminal.disposition,'unknown')),updated_at=now() where id=v_lot.id;
  return jsonb_build_object('state','authored','productionLotId',v_lot.id,'occurrenceId',v_next->>'occurrenceId','taskId',v_next->>'taskId','linkRole',v_role,'dueDate',v_due,'clearOffsetDays',v_offset,'terminalDisposition',coalesce(v_terminal.disposition,'unknown'));
end;
$function$;
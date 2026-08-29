create or replace function atlas.refresh_production_harvest_gate_v1(p_production_lot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_rule atlas.production_harvest_rules%rowtype;
  v_gate atlas.production_harvest_gates%rowtype;
  v_expected integer:=0;
  v_established integer:=0;
  v_alive numeric:=0;
  v_required_policies integer:=0;
  v_satisfied_policies integer:=0;
  v_unsatisfied text;
  v_status text;
  v_blocker text;
  v_visibility text:='assigned_worker';
  v_membership uuid;
  v_user uuid;
  v_org uuid;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_next jsonb;
  v_owner_occ uuid;
  v_harvest_occ uuid;
  v_owner_task uuid;
  v_harvest_task uuid;
  v_objects jsonb;
  v_cycles jsonb;
begin
  select * into v_lot from atlas.production_lots where id=p_production_lot_id for update;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;

  select count(*) filter(where stand_status<>'cleared'),count(*) filter(where stand_status in ('established','field_care','harvest_watch','declining')),coalesce(sum(current_plants) filter(where stand_status<>'cleared'),0)
  into v_expected,v_established,v_alive from atlas.production_field_stands where production_lot_id=v_lot.id;
  select * into v_rule from atlas.production_harvest_rules where production_lot_id=v_lot.id;
  select count(*) filter(where required_before_harvest and policy_status<>'not_required'),count(*) filter(where required_before_harvest and (policy_status='not_required' or current_status in ('satisfied','not_required'))),
         string_agg(case when required_before_harvest and policy_status<>'not_required' and current_status not in ('satisfied','not_required') then initcap(care_kind)||' is '||replace(current_status,'_',' ') end,' · ' order by care_kind)
  into v_required_policies,v_satisfied_policies,v_unsatisfied from atlas.production_care_policies where production_lot_id=v_lot.id;

  select t.visibility_scope,t.assigned_membership_id,t.assigned_user_id,t.organization_id
  into v_visibility,v_membership,v_user,v_org
  from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id
  where plt.production_lot_id=v_lot.id and plt.link_role in ('establishment_check','water_care','weed_care','pinch_care')
  order by t.created_at desc limit 1;
  v_visibility:=coalesce(v_visibility,'assigned_worker');

  if v_expected=0 or v_established<v_expected then v_status:='waiting_establishment';v_blocker:=(v_expected-v_established)::text||' field bed(s) still need counted establishment.';
  elsif v_alive<=0 then v_status:='failed';v_blocker:='No living plants remain in the field cohort.';
  elsif v_rule.id is null or v_rule.pinch_required is null or v_rule.harvest_watch_start is null or v_rule.harvest_watch_end is null then v_status:='waiting_rules';v_blocker:='Owner must confirm whether pinching is required and set the harvest-watch window.';
  elsif v_required_policies<>v_satisfied_policies then v_status:='waiting_care';v_blocker:=coalesce(v_unsatisfied,'Required crop care is not current.');
  else v_status:='ready_for_watch';v_blocker:=null; end if;

  insert into atlas.production_harvest_gates(farm_id,production_lot_id,gate_status,blocker_text,established_beds,expected_beds,plants_alive,ready_at,refresh_version,metadata)
  values(v_lot.farm_id,v_lot.id,v_status,v_blocker,v_established,v_expected,v_alive,case when v_status='ready_for_watch' then now() end,1,jsonb_build_object('required_care_policies',v_required_policies,'satisfied_care_policies',v_satisfied_policies,'unsatisfied_care',v_unsatisfied))
  on conflict(production_lot_id) do update set
    gate_status=case when atlas.production_harvest_gates.gate_status in ('harvest_watch','harvest_ready') and excluded.gate_status='ready_for_watch' then atlas.production_harvest_gates.gate_status else excluded.gate_status end,
    blocker_text=excluded.blocker_text,established_beds=excluded.established_beds,expected_beds=excluded.expected_beds,plants_alive=excluded.plants_alive,
    ready_at=case when excluded.gate_status='ready_for_watch' then coalesce(atlas.production_harvest_gates.ready_at,now()) else null end,
    refresh_version=atlas.production_harvest_gates.refresh_version+1,
    metadata=atlas.production_harvest_gates.metadata||excluded.metadata,updated_at=now()
  returning * into v_gate;

  begin v_owner_occ:=nullif(v_gate.metadata->>'owner_rules_occurrence_id','')::uuid; exception when others then v_owner_occ:=null; end;
  begin v_harvest_occ:=nullif(v_gate.metadata->>'harvest_readiness_occurrence_id','')::uuid; exception when others then v_harvest_occ:=null; end;

  if v_status='waiting_rules' then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'owner-harvest-rules','production:owner-harvest-rules:'||v_gate.id::text,
      'Owner — Set pinch + harvest rules — '||v_lot.lot_label,v_today,v_today,
      'production_harvest_gate',v_gate.id,'owner_decision','decide','owner_decision','high','owner',null,null,v_org,
      'Confirm whether this crop cohort must be pinched and enter a real harvest-watch window before Atlas generates harvest work.',
      jsonb_build_object('task_key','production_harvest_rules_'||v_gate.id::text,'owner_task',true,'anna_task',false,'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_harvest_gate_id',v_gate.id,'display_action','Set rules','display_subject',v_lot.lot_label,'display_detail','Pinch requirement + harvest window','collection_zone','Owner','assigned_to','Owner'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','harvest_rules_decision','source','production_stage_engine','metadata',jsonb_build_object('harvest_gate_id',v_gate.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'required','dependency',null,jsonb_build_object('kind','harvest_contract_gap','effect','Harvest work cannot be generated until crop-specific pinch and watch rules are known.'),true
    );
    v_owner_occ:=nullif(v_next->>'occurrenceId','')::uuid;
    v_owner_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_harvest_gates set owner_decision_task_id=coalesce(v_owner_task,owner_decision_task_id),metadata=metadata||jsonb_build_object('owner_rules_occurrence_id',v_owner_occ),updated_at=now() where id=v_gate.id;
  elsif v_owner_occ is not null then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_harvest_gate','cancelled_at',now(),'cancelled_reason','Harvest rules are no longer missing.'),updated_at=now() where id=v_owner_occ and state not in ('completed');
  end if;

  if v_status='ready_for_watch' then
    select coalesce(jsonb_agg(jsonb_build_object('object_id',object_id,'role','target') order by object_id),'[]'::jsonb),
           coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',crop_cycle_id,'role','observes','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('harvest_gate_id',v_gate.id)) order by crop_cycle_id),'[]'::jsonb)
    into v_objects,v_cycles
    from atlas.production_field_stands where production_lot_id=v_lot.id and current_plants>0 and stand_status<>'cleared';

    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'harvest-readiness','production:harvest-readiness:'||v_gate.id::text,
      'Open harvest readiness — '||v_lot.lot_label,v_rule.harvest_watch_start,v_rule.harvest_watch_start,
      'production_harvest_gate',v_gate.id,'production_harvest_readiness','harvest','standard','high',v_visibility,v_membership,v_user,v_org,
      'Inspect this exact field cohort for cut stage. Do not record harvest until marketable stems are counted.',
      jsonb_build_object('task_key','production_harvest_readiness_'||v_gate.id::text,'task_style','production_harvest_readiness','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_harvest_gate_id',v_gate.id,'harvest_watch_start',v_rule.harvest_watch_start,'harvest_watch_end',v_rule.harvest_watch_end,'plants_alive',v_alive,'display_action','Inspect','display_subject',v_lot.lot_label||' harvest readiness','display_detail',v_alive::text||' living plants','collection_zone','Production beds'),
      jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','harvest_readiness','source','production_stage_engine','metadata',jsonb_build_object('harvest_gate_id',v_gate.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      'process_continuation','dependency',v_rule.harvest_watch_end,jsonb_build_object('kind','harvest_window','effect','The confirmed harvest-watch window closes if readiness is not observed.'),false
    );
    v_harvest_occ:=nullif(v_next->>'occurrenceId','')::uuid;
    v_harvest_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_harvest_gates set harvest_readiness_task_id=coalesce(v_harvest_task,harvest_readiness_task_id),metadata=metadata||jsonb_build_object('harvest_readiness_occurrence_id',v_harvest_occ),updated_at=now() where id=v_gate.id;
  elsif v_harvest_occ is not null and v_status not in ('harvest_watch','harvest_ready') then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_harvest_gate','cancelled_at',now(),'cancelled_gate_status',v_status,'cancelled_reason',v_blocker),updated_at=now() where id=v_harvest_occ and state not in ('completed');
  end if;

  return jsonb_build_object('productionLotId',v_lot.id,'harvestGateId',v_gate.id,'gateStatus',v_status,'blocker',v_blocker,'expectedBeds',v_expected,'establishedBeds',v_established,'plantsAlive',v_alive,'requiredCarePolicies',v_required_policies,'satisfiedCarePolicies',v_satisfied_policies,'unsatisfiedCare',v_unsatisfied,'ownerDecisionOccurrenceId',v_owner_occ,'ownerDecisionTaskId',v_owner_task,'harvestReadinessOccurrenceId',v_harvest_occ,'harvestTaskId',v_harvest_task);
end;
$function$;
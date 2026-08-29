create or replace function atlas.refresh_production_postharvest_gate_v1(p_harvest_lot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_harvest atlas.production_harvest_lots%rowtype;
  v_gate atlas.production_postharvest_gates%rowtype;
  v_source_task atlas.tasks%rowtype;
  v_owner_membership uuid;
  v_assigned numeric:=0;
  v_conditioned numeric:=0;
  v_cooled numeric:=0;
  v_released numeric:=0;
  v_returned numeric:=0;
  v_status text;
  v_blocker text;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_next jsonb;
  v_owner_task uuid;
  v_condition_task uuid;
  v_cooling_task uuid;
  v_wash_task uuid;
  v_owner_occ uuid;
  v_condition_occ uuid;
  v_cooling_occ uuid;
  v_wash_occ uuid;
  v_org uuid;
begin
  select * into v_harvest from atlas.production_harvest_lots where id=p_harvest_lot_id for update;
  if v_harvest.id is null then raise exception 'Harvest lot was not found' using errcode='P0002'; end if;
  select t.* into v_source_task from atlas.tasks t where t.id=v_harvest.source_task_id;
  v_org:=coalesce(v_source_task.organization_id,(select organization_id from atlas.farms where id=v_harvest.farm_id));

  select
    coalesce(sum(assigned_stems) filter(where assignment_status<>'void'),0),
    coalesce(sum(assigned_stems) filter(where assignment_status in ('cooling','ready_for_product','released','awaiting_wash','returned_clean')),0),
    coalesce(sum(assigned_stems) filter(where assignment_status in ('ready_for_product','released','awaiting_wash','returned_clean')),0),
    coalesce(sum(assigned_stems) filter(where assignment_status in ('released','awaiting_wash','returned_clean')),0),
    coalesce(sum(assigned_stems) filter(where assignment_status='returned_clean'),0)
  into v_assigned,v_conditioned,v_cooled,v_released,v_returned
  from atlas.production_harvest_container_assignments
  where harvest_lot_id=v_harvest.id;

  if v_harvest.marketable_stems+v_harvest.seconds_stems=0 then v_status:='closed';v_blocker:=null;
  elsif v_assigned<v_harvest.marketable_stems+v_harvest.seconds_stems then v_status:='waiting_container_assignment';v_blocker:=(v_harvest.marketable_stems+v_harvest.seconds_stems-v_assigned)::text||' usable stems do not have container custody.';
  elsif v_conditioned<v_assigned then v_status:='waiting_conditioning';v_blocker:='Assigned stems have not all been conditioned.';
  elsif v_cooled<v_assigned then v_status:='waiting_cooling';v_blocker:='Conditioned stems have not all reached cooling.';
  elsif v_released=0 then v_status:='ready_for_product';v_blocker:=null;
  elsif v_released<v_assigned then v_status:='partially_released';v_blocker:=(v_assigned-v_released)::text||' cooled stems remain in postharvest custody.';
  elsif v_returned<v_released then v_status:='released';v_blocker:=(v_released-v_returned)::text||' released-stem container capacity still awaits wash return.';
  else v_status:='closed';v_blocker:=null; end if;

  insert into atlas.production_postharvest_gates(farm_id,harvest_lot_id,required_custody_stems,assigned_stems,conditioned_stems,cooled_stems,released_stems,gate_status,blocker_text,refresh_version,metadata)
  values(v_harvest.farm_id,v_harvest.id,v_harvest.marketable_stems+v_harvest.seconds_stems,v_assigned,v_conditioned,v_cooled,v_released,v_status,v_blocker,1,jsonb_build_object('returned_clean_stems',v_returned))
  on conflict(harvest_lot_id) do update set
    required_custody_stems=excluded.required_custody_stems,assigned_stems=excluded.assigned_stems,conditioned_stems=excluded.conditioned_stems,
    cooled_stems=excluded.cooled_stems,released_stems=excluded.released_stems,gate_status=excluded.gate_status,blocker_text=excluded.blocker_text,
    refresh_version=atlas.production_postharvest_gates.refresh_version+1,metadata=atlas.production_postharvest_gates.metadata||excluded.metadata,updated_at=now()
  returning * into v_gate;

  update atlas.production_harvest_lots
  set status=case v_status
    when 'waiting_container_assignment' then 'waiting_container_assignment'
    when 'waiting_conditioning' then 'conditioning'
    when 'waiting_cooling' then 'cooling'
    when 'ready_for_product' then 'ready_for_product'
    when 'partially_released' then 'partially_released'
    when 'released' then 'released'
    when 'closed' then 'closed'
    else status end,updated_at=now()
  where id=v_harvest.id;

  begin v_owner_occ:=nullif(v_gate.metadata->>'owner_assignment_occurrence_id','')::uuid; exception when others then v_owner_occ:=null; end;
  begin v_condition_occ:=nullif(v_gate.metadata->>'conditioning_occurrence_id','')::uuid; exception when others then v_condition_occ:=null; end;
  begin v_cooling_occ:=nullif(v_gate.metadata->>'cooling_occurrence_id','')::uuid; exception when others then v_cooling_occ:=null; end;
  begin v_wash_occ:=nullif(v_gate.metadata->>'wash_occurrence_id','')::uuid; exception when others then v_wash_occ:=null; end;

  if v_status='waiting_container_assignment' then
    select id into v_owner_membership from atlas.farm_memberships where farm_id=v_harvest.farm_id and active and role='owner' order by created_at limit 1;
    v_next:=atlas.author_production_work_occurrence_v1(
      v_harvest.farm_id,'postharvest-container-assignment','production:postharvest-container-assignment:'||v_gate.id::text,
      'Owner — Assign clean containers — '||v_harvest.lot_label,v_harvest.harvest_date,v_harvest.harvest_date,
      'production_postharvest_gate',v_gate.id,'postharvest_container_assignment','assign','light','high','owner',v_owner_membership,null,v_org,
      'Assign clean measured containers to every usable harvested stem. Do not count discarded stems.',
      jsonb_build_object('task_key','postharvest_container_assignment_'||v_gate.id::text,'owner_task',true,'harvest_lot_id',v_harvest.id,'production_lot_id',v_harvest.production_lot_id,'required_custody_stems',v_gate.required_custody_stems,'assigned_stems',v_assigned,'display_action','Assign containers','display_subject',v_harvest.lot_label,'display_detail',v_blocker,'collection_zone','Owner'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array(jsonb_build_object('harvest_lot_id',v_harvest.id,'link_role','container_assignment','source','production_stage_engine','metadata',jsonb_build_object('postharvest_gate_id',v_gate.id)))),
      'required','dependency',null,jsonb_build_object('kind','postharvest_custody','effect','Usable stems lack complete container custody.'),true
    );
    v_owner_occ:=nullif(v_next->>'occurrenceId','')::uuid;v_owner_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_postharvest_gates set owner_assignment_task_id=coalesce(v_owner_task,owner_assignment_task_id),metadata=metadata||jsonb_build_object('owner_assignment_occurrence_id',v_owner_occ),updated_at=now() where id=v_gate.id;
  elsif v_owner_occ is not null then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_postharvest_gate','cancelled_at',now(),'cancelled_reason','Container assignment gate advanced.'),updated_at=now() where id=v_owner_occ and state not in ('completed');
  end if;

  if v_status='waiting_conditioning' then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_harvest.farm_id,'postharvest-conditioning','production:postharvest-conditioning:'||v_gate.id::text,
      'Condition harvested stems — '||v_harvest.lot_label,v_harvest.harvest_date,v_harvest.harvest_date,
      'production_postharvest_gate',v_gate.id,'production_postharvest_conditioning','condition','standard','high',coalesce(v_source_task.visibility_scope,'assigned_worker'),v_source_task.assigned_membership_id,v_source_task.assigned_user_id,v_org,
      'Confirm every assigned container has entered the crop-appropriate conditioning step.',
      jsonb_build_object('task_key','postharvest_conditioning_'||v_gate.id::text,'task_style','postharvest_conditioning','harvest_lot_id',v_harvest.id,'production_lot_id',v_harvest.production_lot_id,'assigned_stems',v_assigned,'display_action','Condition','display_subject',v_harvest.lot_label,'display_detail',v_assigned::text||' stems in assigned containers','collection_zone','Postharvest'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array(jsonb_build_object('harvest_lot_id',v_harvest.id,'link_role','conditioning','source','production_stage_engine','metadata',jsonb_build_object('postharvest_gate_id',v_gate.id)))),
      'required','dependency',v_harvest.harvest_date+1,jsonb_build_object('kind','postharvest_conditioning','effect','Assigned stems require conditioning custody.'),true
    );
    v_condition_occ:=nullif(v_next->>'occurrenceId','')::uuid;v_condition_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_postharvest_gates set conditioning_task_id=coalesce(v_condition_task,conditioning_task_id),metadata=metadata||jsonb_build_object('conditioning_occurrence_id',v_condition_occ),updated_at=now() where id=v_gate.id;
  elsif v_condition_occ is not null then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_postharvest_gate','cancelled_at',now(),'cancelled_reason','Conditioning gate advanced.'),updated_at=now() where id=v_condition_occ and state not in ('completed');
  end if;

  if v_status='waiting_cooling' then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_harvest.farm_id,'postharvest-cooling','production:postharvest-cooling:'||v_gate.id::text,
      'Move conditioned stems to cooling — '||v_harvest.lot_label,v_harvest.harvest_date,v_harvest.harvest_date,
      'production_postharvest_gate',v_gate.id,'production_postharvest_cooling','cool','standard','high',coalesce(v_source_task.visibility_scope,'assigned_worker'),v_source_task.assigned_membership_id,v_source_task.assigned_user_id,v_org,
      'Move every conditioned container into its confirmed cooling location.',
      jsonb_build_object('task_key','postharvest_cooling_'||v_gate.id::text,'task_style','postharvest_cooling','harvest_lot_id',v_harvest.id,'production_lot_id',v_harvest.production_lot_id,'conditioned_stems',v_conditioned,'display_action','Cool','display_subject',v_harvest.lot_label,'display_detail',v_conditioned::text||' conditioned stems','collection_zone','Postharvest'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array(jsonb_build_object('harvest_lot_id',v_harvest.id,'link_role','cooling','source','production_stage_engine','metadata',jsonb_build_object('postharvest_gate_id',v_gate.id)))),
      'required','dependency',v_harvest.harvest_date+1,jsonb_build_object('kind','postharvest_cooling','effect','Conditioned stems require cooling custody.'),true
    );
    v_cooling_occ:=nullif(v_next->>'occurrenceId','')::uuid;v_cooling_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_postharvest_gates set cooling_task_id=coalesce(v_cooling_task,cooling_task_id),metadata=metadata||jsonb_build_object('cooling_occurrence_id',v_cooling_occ),updated_at=now() where id=v_gate.id;
  elsif v_cooling_occ is not null then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_postharvest_gate','cancelled_at',now(),'cancelled_reason','Cooling gate advanced.'),updated_at=now() where id=v_cooling_occ and state not in ('completed');
  end if;

  if v_status in ('released','partially_released') and exists(select 1 from atlas.production_harvest_container_assignments where harvest_lot_id=v_harvest.id and assignment_status='awaiting_wash') then
    v_next:=atlas.author_production_work_occurrence_v1(
      v_harvest.farm_id,'postharvest-wash','production:postharvest-wash:'||v_gate.id::text,
      'Wash released harvest containers — '||v_harvest.lot_label,v_today,v_today,
      'production_postharvest_gate',v_gate.id,'postharvest_container_wash','wash','standard','medium',coalesce(v_source_task.visibility_scope,'assigned_worker'),v_source_task.assigned_membership_id,v_source_task.assigned_user_id,v_org,
      'Wash every released container and return it to clean available inventory.',
      jsonb_build_object('task_key','postharvest_wash_'||v_gate.id::text,'task_style','postharvest_container_wash','harvest_lot_id',v_harvest.id,'production_lot_id',v_harvest.production_lot_id,'display_action','Wash containers','display_subject',v_harvest.lot_label,'display_detail',(v_released-v_returned)::text||' stems of container capacity awaiting wash','collection_zone','Postharvest'),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(),'production_lot_tasks',jsonb_build_array(),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array(jsonb_build_object('harvest_lot_id',v_harvest.id,'link_role','wash','source','production_stage_engine','metadata',jsonb_build_object('postharvest_gate_id',v_gate.id)))),
      'required','dependency',v_today+1,jsonb_build_object('kind','container_return','effect','Released container capacity is unavailable until washed and returned clean.'),true
    );
    v_wash_occ:=nullif(v_next->>'occurrenceId','')::uuid;v_wash_task:=nullif(v_next->>'taskId','')::uuid;
    update atlas.production_postharvest_gates set wash_task_id=coalesce(v_wash_task,wash_task_id),metadata=metadata||jsonb_build_object('wash_occurrence_id',v_wash_occ),updated_at=now() where id=v_gate.id;
  elsif v_wash_occ is not null and v_status not in ('released','partially_released') then
    update atlas.planned_work_occurrences set state=case when state in ('completed','cancelled') then state else 'cancelled' end,metadata=metadata||jsonb_build_object('cancelled_by','production_postharvest_gate','cancelled_at',now(),'cancelled_reason','Wash gate no longer requires work.'),updated_at=now() where id=v_wash_occ and state not in ('completed');
  end if;

  return jsonb_build_object(
    'harvestLotId',v_harvest.id,'postharvestGateId',v_gate.id,'gateStatus',v_status,'blocker',v_blocker,
    'requiredCustodyStems',v_gate.required_custody_stems,'assignedStems',v_assigned,'conditionedStems',v_conditioned,'cooledStems',v_cooled,'releasedStems',v_released,'returnedCleanStems',v_returned,
    'ownerAssignmentOccurrenceId',v_owner_occ,'ownerAssignmentTaskId',coalesce(v_owner_task,v_gate.owner_assignment_task_id),
    'conditioningOccurrenceId',v_condition_occ,'conditioningTaskId',coalesce(v_condition_task,v_gate.conditioning_task_id),
    'coolingOccurrenceId',v_cooling_occ,'coolingTaskId',coalesce(v_cooling_task,v_gate.cooling_task_id),
    'washOccurrenceId',v_wash_occ,'washTaskId',coalesce(v_wash_task,v_gate.wash_task_id)
  );
end;
$function$;
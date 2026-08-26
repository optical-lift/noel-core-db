do $migration$
declare
  v_farm_id uuid;
  v_old_task atlas.tasks%rowtype;
  v_old_cycle atlas.crop_cycles%rowtype;
  v_arch1 uuid;
  v_arch2 uuid;
  v_a1_left uuid;
  v_a1_right uuid;
  v_a2_left uuid;
  v_a2_right uuid;
  v_cycle1 uuid;
  v_cycle2 uuid;
  v_task1 uuid;
  v_task2 uuid;
begin
  select f.id into v_farm_id from atlas.farms f where f.stable_key='elm_farm' limit 1;
  if v_farm_id is null then raise exception 'Elm Farm not found'; end if;

  select cc.* into v_old_cycle from atlas.crop_cycles cc
  where cc.farm_id=v_farm_id and cc.crop_cycle_key='owner-confirmed:muncher-cucumber:2026-08-25' limit 1;
  if v_old_cycle.id is null then raise exception 'Combined Muncher cucumber cycle not found'; end if;

  select t.* into v_old_task from atlas.tasks t
  where t.farm_id=v_farm_id and t.status in ('open','blocked')
    and coalesce(t.metadata->>'weed_management_mode','')='clear_selected_crop'
    and coalesce(t.metadata->>'selected_crop_label','')='Muncher Cucumber'
    and coalesce(t.metadata->>'display_location','')='Curve Garden Arches 1 + 2'
  order by t.created_at desc limit 1;
  if v_old_task.id is null then raise exception 'Combined Muncher cucumber Clear task not found'; end if;

  select id into v_arch1 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01';
  select id into v_arch2 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02';
  select id into v_a1_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_left_bed';
  select id into v_a1_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_right_bed';
  select id into v_a2_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_left_bed';
  select id into v_a2_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_right_bed';
  if v_arch1 is null or v_arch2 is null or v_a1_left is null or v_a1_right is null or v_a2_left is null or v_a2_right is null then
    raise exception 'Curve Garden arch geometry is incomplete';
  end if;

  update atlas.tasks set status='archived', metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('superseded_reason','owner_corrected_independent_arch_scope','superseded_at',now(),'combined_task_invalid',true), updated_at=now() where id=v_old_task.id;
  update atlas.crop_cycles set lifecycle_status='archived', cycle_state='superseded_spatial_split', metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('superseded_reason','owner_corrected_independent_arch_scope','superseded_at',now(),'combined_crop_body_invalid',true), updated_at=now() where id=v_old_cycle.id;

  insert into atlas.crop_cycles(farm_id,object_id,planting_claim_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,planted_date,germination_checked_date,harvest_started_date,last_harvest_date,cleared_date,turnover_date,expected_germination_start,expected_germination_end,expected_harvest_watch_start,expected_harvest_watch_end,expected_clear_date,coverage_kind,coverage_amount,coverage_unit,source_task_id,source_event_id,note,metadata,object_content_id)
  values(v_old_cycle.farm_id,v_arch1,v_old_cycle.planting_claim_id,v_old_cycle.crop_profile_id,'owner-confirmed:muncher-cucumber:curve-arch-01:2026-08-26',v_old_cycle.crop_label,v_old_cycle.variety,'finished_harvest','active',v_old_cycle.sown_date,v_old_cycle.planted_date,v_old_cycle.germination_checked_date,v_old_cycle.harvest_started_date,v_old_cycle.last_harvest_date,null,null,v_old_cycle.expected_germination_start,v_old_cycle.expected_germination_end,v_old_cycle.expected_harvest_watch_start,v_old_cycle.expected_harvest_watch_end,v_old_cycle.expected_clear_date,v_old_cycle.coverage_kind,v_old_cycle.coverage_amount,v_old_cycle.coverage_unit,null,v_old_cycle.source_event_id,'Owner-corrected spatial split from the previously merged Curve Garden Muncher cucumber body.',(coalesce(v_old_cycle.metadata,'{}'::jsonb)-'current_clear_task_id')||jsonb_build_object('location_scope','Curve Arch 1','location_status','owner_confirmed_exact','location_precision','left_side_of_each_40x40_foot_box_plus_arch_surface','root_bed_position_known',true,'root_bed_size_inches',jsonb_build_array(40,40),'root_position','left_side_of_each_box','spatial_correction_source','owner_report_20260826','split_from_crop_cycle_key',v_old_cycle.crop_cycle_key),null)
  returning id into v_cycle1;

  insert into atlas.crop_cycles(farm_id,object_id,planting_claim_id,crop_profile_id,crop_cycle_key,crop_label,variety,cycle_state,lifecycle_status,sown_date,planted_date,germination_checked_date,harvest_started_date,last_harvest_date,cleared_date,turnover_date,expected_germination_start,expected_germination_end,expected_harvest_watch_start,expected_harvest_watch_end,expected_clear_date,coverage_kind,coverage_amount,coverage_unit,source_task_id,source_event_id,note,metadata,object_content_id)
  values(v_old_cycle.farm_id,v_arch2,v_old_cycle.planting_claim_id,v_old_cycle.crop_profile_id,'owner-confirmed:muncher-cucumber:curve-arch-02:2026-08-26',v_old_cycle.crop_label,v_old_cycle.variety,'finished_harvest','active',v_old_cycle.sown_date,v_old_cycle.planted_date,v_old_cycle.germination_checked_date,v_old_cycle.harvest_started_date,v_old_cycle.last_harvest_date,null,null,v_old_cycle.expected_germination_start,v_old_cycle.expected_germination_end,v_old_cycle.expected_harvest_watch_start,v_old_cycle.expected_harvest_watch_end,v_old_cycle.expected_clear_date,v_old_cycle.coverage_kind,v_old_cycle.coverage_amount,v_old_cycle.coverage_unit,null,v_old_cycle.source_event_id,'Owner-corrected spatial split from the previously merged Curve Garden Muncher cucumber body.',(coalesce(v_old_cycle.metadata,'{}'::jsonb)-'current_clear_task_id')||jsonb_build_object('location_scope','Curve Arch 2','location_status','owner_confirmed_exact','location_precision','left_side_of_each_40x40_foot_box_plus_arch_surface','root_bed_position_known',true,'root_bed_size_inches',jsonb_build_array(40,40),'root_position','left_side_of_each_box','spatial_correction_source','owner_report_20260826','split_from_crop_cycle_key',v_old_cycle.crop_cycle_key),null)
  returning id into v_cycle2;

  insert into atlas.crop_placements(farm_id,object_id,crop_cycle_id,placement_key,placement_mode,placement_label,area_sqft,expected_quantity_kind,confidence,metadata,long_start_ft,long_end_ft,cross_start_ft,cross_end_ft,position_confidence)
  values
    (v_farm_id,v_a1_left,v_cycle1,'root:left-box:left-half','square_foot_block','Left side of 40 in x 40 in raised bed',5.555556,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','root_bed','intrinsicSide','left','bedSizeInches',jsonb_build_array(40,40)),0,1.666667,0,3.333333,'high'),
    (v_farm_id,v_a1_right,v_cycle1,'root:right-box:left-half','square_foot_block','Left side of 40 in x 40 in raised bed',5.555556,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','root_bed','intrinsicSide','left','bedSizeInches',jsonb_build_array(40,40)),0,1.666667,0,3.333333,'high'),
    (v_farm_id,v_arch1,v_cycle1,'vine:arch-surface','unknown','Curve Arch 1 vine surface',null,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','vertical_growth_surface','capacitySurface','vertical_arch'),null,null,null,null,'unknown');

  insert into atlas.crop_placements(farm_id,object_id,crop_cycle_id,placement_key,placement_mode,placement_label,area_sqft,expected_quantity_kind,confidence,metadata,long_start_ft,long_end_ft,cross_start_ft,cross_end_ft,position_confidence)
  values
    (v_farm_id,v_a2_left,v_cycle2,'root:left-box:left-half','square_foot_block','Left side of 40 in x 40 in raised bed',5.555556,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','root_bed','intrinsicSide','left','bedSizeInches',jsonb_build_array(40,40)),0,1.666667,0,3.333333,'high'),
    (v_farm_id,v_a2_right,v_cycle2,'root:right-box:left-half','square_foot_block','Left side of 40 in x 40 in raised bed',5.555556,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','root_bed','intrinsicSide','left','bedSizeInches',jsonb_build_array(40,40)),0,1.666667,0,3.333333,'high'),
    (v_farm_id,v_arch2,v_cycle2,'vine:arch-surface','unknown','Curve Arch 2 vine surface',null,'unknown','owner_confirmed',jsonb_build_object('source','owner_report_20260826','physicalRole','vertical_growth_surface','capacitySurface','vertical_arch'),null,null,null,null,'unknown');

  insert into atlas.tasks(farm_id,zone_id,title,task_type,status,priority,due_date,unlock_text,blocker_text,generated_from,generated_from_id,completed_at,completed_by,note,metadata,action_key,work_class,parent_task_id,task_series_key,engine_instance_key,visibility_scope,assigned_membership_id,planned_occurrence_id,release_policy_id,released_at,release_reason,organization_id,task_scope,assigned_user_id,created_by_user_id,origin_kind,work_lane,commitment_kind,effort_units,operation_class,operation_class_source,sky_deferral_mode,sky_deferral_class,sky_deferral_horizon_days,sky_deferral_anchor_at,sky_deferral_reason,sky_deferral_source)
  select t.farm_id,t.zone_id,'Clear finished Muncher cucumber — Curve Arch 1',t.task_type,'open',t.priority,t.due_date,t.unlock_text,null,null,null,null,null,null,(coalesce(t.metadata,'{}'::jsonb)-'planned_occurrence_id'-'source_crop_cycle_id'-'selected_crop_cycle_id'-'crop_cycle_id'-'target_object_id'-'classification_repair'-'classification_repaired_at')||jsonb_build_object('display_title','Curve Arch 1','display_location','Curve Arch 1','turnover_collection_label','Curve Arch 1','turnover_task_title','Clear finished Muncher cucumber — Curve Arch 1','execution_do','Remove the finished Muncher cucumber from Curve Arch 1. It is rooted on the left side of both 40 in x 40 in raised boxes at this arch; remove only the cucumber and take it to compost. Leave every other crop in both boxes in place.','execution_done_when','The Muncher cucumber is removed from Curve Arch 1, including the cucumber rooted on the left side of both 40 in x 40 in boxes, and the removed cucumber biomass is in the compost; all other crops remain in place.','crop_cycle_id',v_cycle1,'source_crop_cycle_id',v_cycle1,'selected_crop_cycle_id',v_cycle1,'target_object_id',v_arch1,'selected_crop_root_bed_position_known',true,'root_bed_size_inches',jsonb_build_array(40,40),'root_position','left_side_of_each_box','spatial_task_scope','single_arch_unit','split_from_combined_task',true,'owner_instruction_source','owner_report_20260826'),'clear',t.work_class,null,'crop-clear:muncher-cucumber:curve-arch-01','owner-corrected:clear:muncher-cucumber:curve-arch-01:2026-08-26',t.visibility_scope,t.assigned_membership_id,null,t.release_policy_id,now(),'owner_corrected_scope',t.organization_id,t.task_scope,t.assigned_user_id,t.created_by_user_id,'owner_assigned',t.work_lane,t.commitment_kind,t.effort_units,t.operation_class,t.operation_class_source,t.sky_deferral_mode,t.sky_deferral_class,t.sky_deferral_horizon_days,t.sky_deferral_anchor_at,t.sky_deferral_reason,t.sky_deferral_source
  from atlas.tasks t where t.id=v_old_task.id returning id into v_task1;

  insert into atlas.tasks(farm_id,zone_id,title,task_type,status,priority,due_date,unlock_text,blocker_text,generated_from,generated_from_id,completed_at,completed_by,note,metadata,action_key,work_class,parent_task_id,task_series_key,engine_instance_key,visibility_scope,assigned_membership_id,planned_occurrence_id,release_policy_id,released_at,release_reason,organization_id,task_scope,assigned_user_id,created_by_user_id,origin_kind,work_lane,commitment_kind,effort_units,operation_class,operation_class_source,sky_deferral_mode,sky_deferral_class,sky_deferral_horizon_days,sky_deferral_anchor_at,sky_deferral_reason,sky_deferral_source)
  select t.farm_id,t.zone_id,'Clear finished Muncher cucumber — Curve Arch 2',t.task_type,'open',t.priority,t.due_date,t.unlock_text,null,null,null,null,null,null,(coalesce(t.metadata,'{}'::jsonb)-'planned_occurrence_id'-'source_crop_cycle_id'-'selected_crop_cycle_id'-'crop_cycle_id'-'target_object_id'-'classification_repair'-'classification_repaired_at')||jsonb_build_object('display_title','Curve Arch 2','display_location','Curve Arch 2','turnover_collection_label','Curve Arch 2','turnover_task_title','Clear finished Muncher cucumber — Curve Arch 2','execution_do','Remove the finished Muncher cucumber from Curve Arch 2. It is rooted on the left side of both 40 in x 40 in raised boxes at this arch; remove only the cucumber and take it to compost. Leave every other crop in both boxes in place.','execution_done_when','The Muncher cucumber is removed from Curve Arch 2, including the cucumber rooted on the left side of both 40 in x 40 in boxes, and the removed cucumber biomass is in the compost; all other crops remain in place.','crop_cycle_id',v_cycle2,'source_crop_cycle_id',v_cycle2,'selected_crop_cycle_id',v_cycle2,'target_object_id',v_arch2,'selected_crop_root_bed_position_known',true,'root_bed_size_inches',jsonb_build_array(40,40),'root_position','left_side_of_each_box','spatial_task_scope','single_arch_unit','split_from_combined_task',true,'owner_instruction_source','owner_report_20260826'),'clear',t.work_class,null,'crop-clear:muncher-cucumber:curve-arch-02','owner-corrected:clear:muncher-cucumber:curve-arch-02:2026-08-26',t.visibility_scope,t.assigned_membership_id,null,t.release_policy_id,now(),'owner_corrected_scope',t.organization_id,t.task_scope,t.assigned_user_id,t.created_by_user_id,'owner_assigned',t.work_lane,t.commitment_kind,t.effort_units,t.operation_class,t.operation_class_source,t.sky_deferral_mode,t.sky_deferral_class,t.sky_deferral_horizon_days,t.sky_deferral_anchor_at,t.sky_deferral_reason,t.sky_deferral_source
  from atlas.tasks t where t.id=v_old_task.id returning id into v_task2;

  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('current_clear_task_id',v_task1) where id=v_cycle1;
  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('current_clear_task_id',v_task2) where id=v_cycle2;

  insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role) values (v_task1,v_cycle1,'clears'),(v_task2,v_cycle2,'clears');
  insert into atlas.task_objects(task_id,object_id,role) values (v_task1,v_arch1,'capacity_surface'),(v_task1,v_a1_left,'work_carrier'),(v_task1,v_a1_right,'work_carrier'),(v_task2,v_arch2,'capacity_surface'),(v_task2,v_a2_left,'work_carrier'),(v_task2,v_a2_right,'work_carrier');

  insert into atlas.crop_observations(farm_id,object_id,crop_cycle_id,observed_date,stage,condition,confidence,source_kind,source_id,note,idempotency_key,metadata)
  values (v_farm_id,v_arch1,v_cycle1,'2026-08-26','finished','declining_end_of_cycle','owner_confirmed','owner_report','owner_report_20260826_curve_arch_split','Owner confirms the Muncher cucumber at Curve Arch 1 is a separate crop body ready to clear; its roots occupy the left side of both 40 in x 40 in raised boxes at this arch.','owner-report:muncher-cucumber:curve-arch-01:spatial-split:20260826',jsonb_build_object('clearNow',true,'rootPosition','left_side_of_each_box','bedSizeInches',jsonb_build_array(40,40))),
         (v_farm_id,v_arch2,v_cycle2,'2026-08-26','finished','declining_end_of_cycle','owner_confirmed','owner_report','owner_report_20260826_curve_arch_split','Owner confirms the Muncher cucumber at Curve Arch 2 is a separate crop body ready to clear; its roots occupy the left side of both 40 in x 40 in raised boxes at this arch.','owner-report:muncher-cucumber:curve-arch-02:spatial-split:20260826',jsonb_build_object('clearNow',true,'rootPosition','left_side_of_each_box','bedSizeInches',jsonb_build_array(40,40)));

  update atlas.tasks set metadata=metadata||jsonb_build_object('superseded_by_task_ids',jsonb_build_array(v_task1,v_task2)) where id=v_old_task.id;
  update atlas.crop_cycles set metadata=metadata||jsonb_build_object('split_into_crop_cycle_ids',jsonb_build_array(v_cycle1,v_cycle2)) where id=v_old_cycle.id;
end
$migration$;
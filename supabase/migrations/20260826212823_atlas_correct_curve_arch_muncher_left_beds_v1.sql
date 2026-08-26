do $migration$
declare
  v_farm_id uuid;
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
  select id into v_farm_id from atlas.farms where stable_key='elm_farm' limit 1;
  select id into v_arch1 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01';
  select id into v_arch2 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02';
  select id into v_a1_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_left_bed';
  select id into v_a1_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_right_bed';
  select id into v_a2_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_left_bed';
  select id into v_a2_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_right_bed';

  select id into v_cycle1 from atlas.crop_cycles where farm_id=v_farm_id and crop_cycle_key='owner-confirmed:muncher-cucumber:curve-arch-01:2026-08-26';
  select id into v_cycle2 from atlas.crop_cycles where farm_id=v_farm_id and crop_cycle_key='owner-confirmed:muncher-cucumber:curve-arch-02:2026-08-26';
  select id into v_task1 from atlas.tasks where farm_id=v_farm_id and engine_instance_key='owner-corrected:clear:muncher-cucumber:curve-arch-01:2026-08-26' and status in ('open','blocked');
  select id into v_task2 from atlas.tasks where farm_id=v_farm_id and engine_instance_key='owner-corrected:clear:muncher-cucumber:curve-arch-02:2026-08-26' and status in ('open','blocked');

  if v_cycle1 is null or v_cycle2 is null or v_task1 is null or v_task2 is null then
    raise exception 'Split Muncher cucumber records not found';
  end if;

  update atlas.crop_cycles
  set object_id=v_a1_left,
      metadata=(coalesce(metadata,'{}'::jsonb)
        - 'root_bed_size_inches'
        - 'root_position'
        - 'location_precision')
        || jsonb_build_object(
          'location_scope','Curve Arch 1 Left Bed + left side of Curve Arch 1',
          'location_status','owner_confirmed_exact',
          'location_precision','rooted_in_left_box_climbing_left_arch_side',
          'root_bed_id',v_a1_left,
          'root_bed_stable_key','curve_arch_01_left_bed',
          'root_bed_size_inches',jsonb_build_array(40,40),
          'arch_surface_id',v_arch1,
          'arch_surface_side','left',
          'right_box_not_occupied_by_this_crop',true,
          'spatial_correction_source','owner_report_20260826_followup'
        ),
      updated_at=now()
  where id=v_cycle1;

  update atlas.crop_cycles
  set object_id=v_a2_left,
      metadata=(coalesce(metadata,'{}'::jsonb)
        - 'root_bed_size_inches'
        - 'root_position'
        - 'location_precision')
        || jsonb_build_object(
          'location_scope','Curve Arch 2 Left Bed + left side of Curve Arch 2',
          'location_status','owner_confirmed_exact',
          'location_precision','rooted_in_left_box_climbing_left_arch_side',
          'root_bed_id',v_a2_left,
          'root_bed_stable_key','curve_arch_02_left_bed',
          'root_bed_size_inches',jsonb_build_array(40,40),
          'arch_surface_id',v_arch2,
          'arch_surface_side','left',
          'right_box_not_occupied_by_this_crop',true,
          'spatial_correction_source','owner_report_20260826_followup'
        ),
      updated_at=now()
  where id=v_cycle2;

  delete from atlas.crop_placements where crop_cycle_id=v_cycle1 and object_id=v_a1_right;
  delete from atlas.crop_placements where crop_cycle_id=v_cycle2 and object_id=v_a2_right;

  update atlas.crop_placements
  set placement_mode='edge_strip',
      placement_label='Cucumber rooted in Curve Arch 1 Left Bed at the arch side',
      area_sqft=null,
      long_start_ft=null,long_end_ft=null,cross_start_ft=null,cross_end_ft=null,
      position_confidence='high',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'source','owner_report_20260826_followup',
        'physicalRole','root_bed',
        'bedSizeInches',jsonb_build_array(40,40),
        'archAssociation','curve_arch_01',
        'archSide','left',
        'rightBoxOccupied',false
      ),
      updated_at=now()
  where crop_cycle_id=v_cycle1 and object_id=v_a1_left;

  update atlas.crop_placements
  set placement_mode='edge_strip',
      placement_label='Cucumber rooted in Curve Arch 2 Left Bed at the arch side',
      area_sqft=null,
      long_start_ft=null,long_end_ft=null,cross_start_ft=null,cross_end_ft=null,
      position_confidence='high',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'source','owner_report_20260826_followup',
        'physicalRole','root_bed',
        'bedSizeInches',jsonb_build_array(40,40),
        'archAssociation','curve_arch_02',
        'archSide','left',
        'rightBoxOccupied',false
      ),
      updated_at=now()
  where crop_cycle_id=v_cycle2 and object_id=v_a2_left;

  update atlas.crop_placements
  set placement_label='Left side of Curve Arch 1',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'source','owner_report_20260826_followup',
        'physicalRole','vertical_growth_surface',
        'surfaceSide','left',
        'rootBedStableKey','curve_arch_01_left_bed'
      ),
      updated_at=now()
  where crop_cycle_id=v_cycle1 and object_id=v_arch1;

  update atlas.crop_placements
  set placement_label='Left side of Curve Arch 2',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'source','owner_report_20260826_followup',
        'physicalRole','vertical_growth_surface',
        'surfaceSide','left',
        'rootBedStableKey','curve_arch_02_left_bed'
      ),
      updated_at=now()
  where crop_cycle_id=v_cycle2 and object_id=v_arch2;

  delete from atlas.task_objects where task_id=v_task1 and object_id=v_a1_right;
  delete from atlas.task_objects where task_id=v_task2 and object_id=v_a2_right;

  update atlas.tasks
  set title='Clear Muncher Cucumber — Curve Arch 1 Left Bed',
      metadata=(coalesce(metadata,'{}'::jsonb)-'root_position')||jsonb_build_object(
        'display_title','Curve Arch 1 Left Bed',
        'display_location','Curve Arch 1 Left Bed',
        'turnover_collection_label','Curve Arch 1 Left Bed',
        'turnover_task_title','Clear Muncher Cucumber — Curve Arch 1 Left Bed',
        'target_object_id',v_a1_left,
        'execution_do','Remove the finished Muncher Cucumber rooted in Curve Arch 1 Left Bed and growing up the left side of Curve Arch 1. Take the cucumber biomass to compost. Leave the right-hand box and every other crop alone.',
        'execution_done_when','The Muncher Cucumber is gone from Curve Arch 1 Left Bed and the left side of Curve Arch 1, and its biomass is in compost; the right-hand box and other crops remain untouched.',
        'root_bed_stable_key','curve_arch_01_left_bed',
        'root_bed_size_inches',jsonb_build_array(40,40),
        'arch_surface_stable_key','curve_arch_01',
        'arch_surface_side','left',
        'right_box_not_in_scope',true,
        'owner_instruction_source','owner_report_20260826_followup'
      ),
      updated_at=now()
  where id=v_task1;

  update atlas.tasks
  set title='Clear Muncher Cucumber — Curve Arch 2 Left Bed',
      metadata=(coalesce(metadata,'{}'::jsonb)-'root_position')||jsonb_build_object(
        'display_title','Curve Arch 2 Left Bed',
        'display_location','Curve Arch 2 Left Bed',
        'turnover_collection_label','Curve Arch 2 Left Bed',
        'turnover_task_title','Clear Muncher Cucumber — Curve Arch 2 Left Bed',
        'target_object_id',v_a2_left,
        'execution_do','Remove the finished Muncher Cucumber rooted in Curve Arch 2 Left Bed and growing up the left side of Curve Arch 2. Take the cucumber biomass to compost. Leave the right-hand box and every other crop alone.',
        'execution_done_when','The Muncher Cucumber is gone from Curve Arch 2 Left Bed and the left side of Curve Arch 2, and its biomass is in compost; the right-hand box and other crops remain untouched.',
        'root_bed_stable_key','curve_arch_02_left_bed',
        'root_bed_size_inches',jsonb_build_array(40,40),
        'arch_surface_stable_key','curve_arch_02',
        'arch_surface_side','left',
        'right_box_not_in_scope',true,
        'owner_instruction_source','owner_report_20260826_followup'
      ),
      updated_at=now()
  where id=v_task2;

  update atlas.crop_observations
  set object_id=v_a1_left,
      note='Owner confirms the Muncher Cucumber for Curve Arch 1 is rooted only in Curve Arch 1 Left Bed and grows up the left side of Curve Arch 1; the right-hand box is not part of this crop.',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('rootBedStableKey','curve_arch_01_left_bed','archSurfaceStableKey','curve_arch_01','archSurfaceSide','left','rightBoxOccupied',false)
  where crop_cycle_id=v_cycle1 and source_id='owner_report_20260826_curve_arch_split';

  update atlas.crop_observations
  set object_id=v_a2_left,
      note='Owner confirms the Muncher Cucumber for Curve Arch 2 is rooted only in Curve Arch 2 Left Bed and grows up the left side of Curve Arch 2; the right-hand box is not part of this crop.',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('rootBedStableKey','curve_arch_02_left_bed','archSurfaceStableKey','curve_arch_02','archSurfaceSide','left','rightBoxOccupied',false)
  where crop_cycle_id=v_cycle2 and source_id='owner_report_20260826_curve_arch_split';
end
$migration$;
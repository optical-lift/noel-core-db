-- Clone fixture for Production Bed Assignment -> destination claim projection v1.

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values(
  'f1000000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_org',
  'Destination Projection Fixture Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_units(
  id,organization_id,stable_key,name,unit_kind,status,metadata
) values(
  'f1100000-0000-4000-8000-000000000001'::uuid,
  'f1000000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_unit',
  'Destination Projection Fixture Unit',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farms(
  id,stable_key,name,status,organization_id,organization_unit_id,metadata
) values(
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_farm',
  'Destination Projection Fixture Farm',
  'active',
  'f1000000-0000-4000-8000-000000000001'::uuid,
  'f1100000-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true,"timezone":"America/Chicago"}'::jsonb
);

insert into atlas.growing_objects(
  id,farm_id,stable_key,label,object_type,length_ft,width_ft,guest_visible,sort_order,metadata
) values
(
  'f1300000-0000-4000-8000-000000000001'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_seed_room',
  'Fixture Seed Room',
  'seed_room',
  null,null,false,1,
  '{"validation_fixture":true}'::jsonb
),
(
  'f1300000-0000-4000-8000-000000000002'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_bed_a',
  'Fixture Bed A',
  'bed',
  20,4,false,2,
  '{"validation_fixture":true}'::jsonb
),
(
  'f1300000-0000-4000-8000-000000000003'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_bed_b',
  'Fixture Bed B',
  'bed',
  20,4,false,3,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.crop_profiles(
  id,stable_key,crop_label,variety,life_cycle,default_planting_method,metadata
) values(
  'f1400000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_snapdragon',
  'Snapdragon',
  'Destination Projection Fixture',
  'annual',
  'seed_started',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.crop_cycles(
  id,farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,
  cycle_state,lifecycle_status,sown_date,coverage_kind,coverage_amount,coverage_unit,metadata
) values(
  'f1500000-0000-4000-8000-000000000001'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'f1300000-0000-4000-8000-000000000001'::uuid,
  'f1400000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_cycle',
  'Snapdragon',
  'Destination Projection Fixture',
  'seedling_care',
  'active',
  current_date-45,
  'viable_seedlings',
  100,
  'seedlings',
  '{"validation_fixture":true,"last_seedling_count":100}'::jsonb
);

insert into atlas.production_programs(
  id,farm_id,stable_key,season_year,program_label,program_kind,promise_text,status,metadata
) values(
  'f1600000-0000-4000-8000-000000000001'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_program',
  2026,
  'Destination Projection Fixture Program',
  'validation',
  'Prove Production destination authority projection.',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_lots(
  id,farm_id,program_id,crop_profile_id,stable_key,lot_label,
  current_quantity,current_unit,current_stage,lifecycle_status,
  actual_sow_date,expected_transplant_start,expected_transplant_end,metadata
) values(
  'f1700000-0000-4000-8000-000000000001'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'f1600000-0000-4000-8000-000000000001'::uuid,
  'f1400000-0000-4000-8000-000000000001'::uuid,
  'destination_projection_fixture_lot',
  'Destination Projection Fixture Cohort',
  100,
  'seedlings',
  'seedling_care',
  'active',
  current_date-45,
  current_date+5,
  current_date+10,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_lot_crop_cycles(
  id,production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata
) values(
  'f1800000-0000-4000-8000-000000000001'::uuid,
  'f1700000-0000-4000-8000-000000000001'::uuid,
  'f1500000-0000-4000-8000-000000000001'::uuid,
  'primary',
  'confirmed',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_capacity_requirements(
  id,farm_id,production_lot_id,stable_key,stage_key,capacity_kind,
  quantity_needed,unit,required_by_date,window_start,window_end,
  preparation_due_date,calculation_status,source,metadata
) values(
  'f1900000-0000-4000-8000-000000000001'::uuid,
  'f1200000-0000-4000-8000-000000000001'::uuid,
  'f1700000-0000-4000-8000-000000000001'::uuid,
  'field_bed_feet',
  'transplant',
  'bed_feet',
  10,
  'bed_ft',
  current_date+5,
  current_date+5,
  current_date+10,
  current_date+3,
  'calculated',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

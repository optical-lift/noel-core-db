-- Clone fixture for Production Current-State Recovery Observation Membrane v1.

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values(
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_org',
  'Production Recovery Fixture Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_units(
  id,organization_id,stable_key,name,unit_kind,status,metadata
) values(
  'e1100000-0000-4000-8000-000000000001'::uuid,
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_unit',
  'Production Recovery Fixture Unit',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farms(
  id,stable_key,name,status,organization_id,organization_unit_id,metadata
) values(
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_farm',
  'Production Recovery Fixture Farm',
  'active',
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'e1100000-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true,"timezone":"America/Chicago"}'::jsonb
);

insert into atlas.growing_objects(
  id,farm_id,stable_key,label,object_type,guest_visible,sort_order,metadata
) values(
  'e1300000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_seed_room',
  'Fixture Seed Room',
  'seed_room',
  false,
  1,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.crop_profiles(
  id,stable_key,crop_label,variety,life_cycle,default_planting_method,metadata
) values(
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_snapdragon',
  'Snapdragon',
  'Recovery Fixture',
  'annual',
  'seed_started',
  '{"validation_fixture":true,"hardening_duration_days_min":7}'::jsonb
);

insert into atlas.crop_cycles(
  id,farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,
  cycle_state,lifecycle_status,sown_date,coverage_kind,coverage_amount,coverage_unit,metadata
) values(
  'e1500000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1300000-0000-4000-8000-000000000001'::uuid,
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_cycle',
  'Snapdragon',
  'Recovery Fixture',
  'seedling_care',
  'active',
  current_date-60,
  'viable_seedlings',
  80,
  'seedlings',
  '{"validation_fixture":true,"last_seedling_count":80}'::jsonb
);

insert into atlas.production_programs(
  id,farm_id,stable_key,season_year,program_label,program_kind,promise_text,status,metadata
) values(
  'e1600000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_program',
  2026,
  'Production Recovery Fixture Program',
  'validation',
  'Prove present-state recovery without historical invention.',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_lots(
  id,farm_id,program_id,crop_profile_id,stable_key,lot_label,
  current_quantity,current_unit,current_stage,lifecycle_status,
  actual_sow_date,expected_transplant_start,expected_transplant_end,metadata
) values(
  'e1700000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1600000-0000-4000-8000-000000000001'::uuid,
  'e1400000-0000-4000-8000-000000000001'::uuid,
  'production_recovery_fixture_lot',
  'Recovery Fixture Snapdragon Cohort',
  80,
  'seedlings',
  'seedling_care',
  'active',
  current_date-60,
  current_date,
  current_date+7,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_lot_crop_cycles(
  id,production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata
) values(
  'e1800000-0000-4000-8000-000000000001'::uuid,
  'e1700000-0000-4000-8000-000000000001'::uuid,
  'e1500000-0000-4000-8000-000000000001'::uuid,
  'primary',
  'confirmed',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.operation_classes(
  stable_key,label,operation_domain,definition,active,metadata
) values(
  'establish_aboveground',
  'Establish aboveground',
  'cultivation',
  'Establish a crop or plant whose working target is primarily aboveground growth, including sowing, potting up, set-out, and ordinary transplanting.',
  true,
  '{}'::jsonb
);

insert into atlas.operation_classes(
  stable_key,label,operation_domain,definition,active,metadata
) values(
  'inspect_assess',
  'Inspect / assess',
  'assessment',
  'Observe, inspect, verify, or assess readiness or state before choosing a later operation.',
  true,
  '{}'::jsonb
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,action_key,status,metadata,
  visibility_scope,task_scope,origin_kind,work_lane,commitment_kind
) values(
  'e1d00000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'Fixture historical sowing provenance',
  'production_sowing',
  'sow',
  'done',
  '{"validation_fixture":true,"fixture_role":"historical_sowing_provenance"}'::jsonb,
  'system_internal',
  'farm_operation',
  'generated',
  'process_continuation',
  'dependency'
);

insert into atlas.production_lot_tasks(
  id,production_lot_id,task_id,link_role,source,metadata
) values(
  'e1e00000-0000-4000-8000-000000000001'::uuid,
  'e1700000-0000-4000-8000-000000000001'::uuid,
  'e1d00000-0000-4000-8000-000000000001'::uuid,
  'sowing',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_tray_batches(
  id,farm_id,production_lot_id,source_task_id,crop_cycle_id,batch_number,batch_label,
  container_kind,seeds_sown,tray_count,status,sown_date,viable_seedlings,
  current_quantity,current_unit,idempotency_key,metadata
) values(
  'e1900000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1700000-0000-4000-8000-000000000001'::uuid,
  'e1d00000-0000-4000-8000-000000000001'::uuid,
  'e1500000-0000-4000-8000-000000000001'::uuid,
  1,
  'Recovery Fixture Tray Batch',
  'soil blocks',
  120,
  4,
  'seedling_care',
  current_date-60,
  80,
  80,
  'seedlings',
  'production-recovery-fixture-tray',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_capacity_requirements(
  id,farm_id,production_lot_id,stable_key,stage_key,capacity_kind,
  quantity_needed,unit,required_by_date,window_start,window_end,
  preparation_due_date,calculation_status,source,metadata
) values(
  'e1a00000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1700000-0000-4000-8000-000000000001'::uuid,
  'field_bed_feet',
  'transplant',
  'bed_feet',
  null,
  'bed_ft',
  current_date,
  current_date,
  current_date+7,
  current_date,
  'blocked',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,status,metadata,
  visibility_scope,task_scope,origin_kind,work_lane,commitment_kind
) values(
  'e1b00000-0000-4000-8000-000000000001'::uuid,
  'e1200000-0000-4000-8000-000000000001'::uuid,
  'e1000000-0000-4000-8000-000000000001'::uuid,
  'Inspect + reclassify Production recovery fixture',
  'general',
  'open',
  '{
    "validation_fixture":true,
    "work_route":"inspect_reconcile",
    "reconciliation_actor":"owner",
    "owner_reconciliation_active":true,
    "execution_do":"Observe current physical state.",
    "execution_done_when":"Every linked body has a current witness."
  }'::jsonb,
  'management',
  'farm_operation',
  'generated',
  'discretionary',
  'floating'
);

insert into atlas.task_crop_cycles(
  id,task_id,crop_cycle_id,role,confidence,source,metadata
) values(
  'e1c00000-0000-4000-8000-000000000001'::uuid,
  'e1b00000-0000-4000-8000-000000000001'::uuid,
  'e1500000-0000-4000-8000-000000000001'::uuid,
  'observes',
  'confirmed',
  'validation_fixture',
  '{"validation_fixture":true}'::jsonb
);

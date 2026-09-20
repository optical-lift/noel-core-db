-- Data-only clone fixture for Structured Production Result Completion Membrane v1.

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values(
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'structured_result_fixture_org',
  'Structured Result Fixture Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.farms(
  id,stable_key,name,status,organization_id,metadata
)
values(
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'structured_result_fixture_farm',
  'Structured Result Fixture Farm',
  'active',
  'c1000000-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_programs(
  id,farm_id,stable_key,season_year,program_label,program_kind,
  promise_text,status,metadata
)
values(
  'c1200000-0000-4000-8000-000000000001'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'structured_result_fixture_program',
  2026,
  'Structured Result Fixture Program',
  'validation',
  'Prove task completion cannot outrun Production evidence.',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.production_lots(
  id,farm_id,program_id,stable_key,lot_label,
  current_stage,lifecycle_status,metadata
)
values(
  'c1300000-0000-4000-8000-000000000001'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1200000-0000-4000-8000-000000000001'::uuid,
  'structured_result_fixture_lot',
  'Structured Result Fixture Lot',
  'seedling_care',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,status,metadata,
  action_key,visibility_scope,task_scope,origin_kind,work_lane,commitment_kind
)
values
(
  'c1400000-0000-4000-8000-000000000001'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'Structured Production result must be recorded',
  'hardening_off',
  'open',
  '{"validation_fixture":true,"structured_result_required":true}'::jsonb,
  'hardening_off',
  'system_internal',
  'farm_operation',
  'generated',
  'process_continuation',
  'dependency'
),
(
  'c1400000-0000-4000-8000-000000000002'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'Historical Production completion without result evidence',
  'hardening_off',
  'done',
  '{"validation_fixture":true,"structured_result_required":true}'::jsonb,
  'hardening_off',
  'system_internal',
  'farm_operation',
  'generated',
  'process_continuation',
  'dependency'
),
(
  'c1400000-0000-4000-8000-000000000003'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'Domain adapter evidence precedes internal completion',
  'hardening_off',
  'open',
  '{"validation_fixture":true,"structured_result_required":true}'::jsonb,
  'hardening_off',
  'system_internal',
  'farm_operation',
  'generated',
  'process_continuation',
  'dependency'
),
(
  'c1400000-0000-4000-8000-000000000004'::uuid,
  'c1100000-0000-4000-8000-000000000001'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'Unstructured Production-linked completion remains lawful',
  'general',
  'open',
  '{"validation_fixture":true,"quick_complete_allowed":true}'::jsonb,
  null,
  'system_internal',
  'farm_operation',
  'generated',
  'discretionary',
  'floating'
);

insert into atlas.production_lot_tasks(
  id,production_lot_id,task_id,link_role,source,metadata
)
values
(
  'c1500000-0000-4000-8000-000000000001'::uuid,
  'c1300000-0000-4000-8000-000000000001'::uuid,
  'c1400000-0000-4000-8000-000000000001'::uuid,
  'hardening','validation_fixture','{"validation_fixture":true}'::jsonb
),
(
  'c1500000-0000-4000-8000-000000000002'::uuid,
  'c1300000-0000-4000-8000-000000000001'::uuid,
  'c1400000-0000-4000-8000-000000000002'::uuid,
  'hardening','validation_fixture','{"validation_fixture":true}'::jsonb
),
(
  'c1500000-0000-4000-8000-000000000003'::uuid,
  'c1300000-0000-4000-8000-000000000001'::uuid,
  'c1400000-0000-4000-8000-000000000003'::uuid,
  'hardening','validation_fixture','{"validation_fixture":true}'::jsonb
),
(
  'c1500000-0000-4000-8000-000000000004'::uuid,
  'c1300000-0000-4000-8000-000000000001'::uuid,
  'c1400000-0000-4000-8000-000000000004'::uuid,
  'inspection','validation_fixture','{"validation_fixture":true}'::jsonb
);

update atlas.tasks
set completed_at='2026-09-05 14:26:42+00'::timestamptz,
    completed_by='validation historical bypass'
where id='c1400000-0000-4000-8000-000000000002'::uuid;

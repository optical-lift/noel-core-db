-- Clone fixture for planned occurrence execution-carrier terminality reconciliation v1.

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values(
  'd1000000-0000-4000-8000-000000000001'::uuid,
  'occurrence_terminality_fixture_org',
  'Occurrence Terminality Fixture Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.farms(id,stable_key,name,status,organization_id,metadata)
values(
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'occurrence_terminality_fixture_farm',
  'Occurrence Terminality Fixture Farm',
  'active',
  'd1000000-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.work_definitions(
  id,farm_id,stable_key,title_template,task_type,
  default_priority,default_visibility_scope,active,metadata
)
values(
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'occurrence_terminality_fixture_work',
  'Occurrence Terminality Fixture Work',
  'general',
  'normal',
  'system_internal',
  true,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.work_release_policies(
  id,farm_id,work_definition_id,stable_key,gate_type,
  horizon_days,maximum_active_instances,gate_config,active,metadata
)
values(
  'd1300000-0000-4000-8000-000000000001'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'occurrence_terminality_fixture_policy',
  'manual',
  30,
  50,
  '{}'::jsonb,
  true,
  '{"validation_fixture":true}'::jsonb
);

-- Historical stale exact pair.
insert into atlas.planned_work_occurrences(
  id,farm_id,work_definition_id,release_policy_id,
  occurrence_key,title,state,task_payload,relation_payload,metadata,
  work_lane,commitment_kind
)
values(
  'd1400000-0000-4000-8000-000000000001'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'd1300000-0000-4000-8000-000000000001'::uuid,
  'fixture:historical-stale-done',
  'Historical stale exact pair',
  'released',
  '{}'::jsonb,'{}'::jsonb,
  '{"validation_fixture":true}'::jsonb,
  'discretionary','floating'
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,status,metadata,
  visibility_scope,task_scope,origin_kind,work_lane,commitment_kind,
  planned_occurrence_id,completed_at,completed_by
)
values(
  'd1500000-0000-4000-8000-000000000001'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1000000-0000-4000-8000-000000000001'::uuid,
  'Historical stale terminality carrier',
  'general',
  'done',
  '{"validation_fixture":true,"quick_complete_allowed":true}'::jsonb,
  'system_internal',
  'farm_operation',
  'generated',
  'discretionary',
  'floating',
  'd1400000-0000-4000-8000-000000000001'::uuid,
  '2026-09-05 14:26:42+00'::timestamptz,
  'validation historical completion'
);

update atlas.planned_work_occurrences
set released_task_id='d1500000-0000-4000-8000-000000000001'::uuid,
    released_at='2026-09-01 05:05:00+00'::timestamptz
where id='d1400000-0000-4000-8000-000000000001'::uuid;

-- Historical archived pair: visible to audit but deliberately not auto-reconciled.
insert into atlas.planned_work_occurrences(
  id,farm_id,work_definition_id,release_policy_id,
  occurrence_key,title,state,task_payload,relation_payload,metadata,
  work_lane,commitment_kind
)
values(
  'd1400000-0000-4000-8000-000000000002'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'd1300000-0000-4000-8000-000000000001'::uuid,
  'fixture:historical-archived',
  'Historical archived carrier requiring classification',
  'released',
  '{}'::jsonb,'{}'::jsonb,
  '{"validation_fixture":true}'::jsonb,
  'discretionary','floating'
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,status,metadata,
  visibility_scope,task_scope,origin_kind,work_lane,commitment_kind,
  planned_occurrence_id
)
values(
  'd1500000-0000-4000-8000-000000000002'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1000000-0000-4000-8000-000000000001'::uuid,
  'Historical archived carrier',
  'general',
  'archived',
  '{"validation_fixture":true}'::jsonb,
  'system_internal',
  'farm_operation',
  'generated',
  'discretionary',
  'floating',
  'd1400000-0000-4000-8000-000000000002'::uuid
);

update atlas.planned_work_occurrences
set released_task_id='d1500000-0000-4000-8000-000000000002'::uuid,
    released_at='2026-09-01 05:05:00+00'::timestamptz
where id='d1400000-0000-4000-8000-000000000002'::uuid;

-- Fresh runtime pair. Candidate migration must not reconcile it because task is still open.
insert into atlas.planned_work_occurrences(
  id,farm_id,work_definition_id,release_policy_id,
  occurrence_key,title,state,task_payload,relation_payload,metadata,
  work_lane,commitment_kind
)
values(
  'd1400000-0000-4000-8000-000000000003'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'd1300000-0000-4000-8000-000000000001'::uuid,
  'fixture:fresh-runtime',
  'Fresh runtime terminality proof',
  'released',
  '{}'::jsonb,'{}'::jsonb,
  '{"validation_fixture":true}'::jsonb,
  'discretionary','floating'
);

insert into atlas.tasks(
  id,farm_id,organization_id,title,task_type,status,metadata,
  visibility_scope,task_scope,origin_kind,work_lane,commitment_kind,
  planned_occurrence_id
)
values(
  'd1500000-0000-4000-8000-000000000003'::uuid,
  'd1100000-0000-4000-8000-000000000001'::uuid,
  'd1000000-0000-4000-8000-000000000001'::uuid,
  'Fresh runtime terminality carrier',
  'general',
  'open',
  '{"validation_fixture":true,"quick_complete_allowed":true}'::jsonb,
  'system_internal',
  'farm_operation',
  'generated',
  'discretionary',
  'floating',
  'd1400000-0000-4000-8000-000000000003'::uuid
);

update atlas.planned_work_occurrences
set released_task_id='d1500000-0000-4000-8000-000000000003'::uuid,
    released_at=now()
where id='d1400000-0000-4000-8000-000000000003'::uuid;

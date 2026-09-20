insert into auth.users(id,email,created_at,updated_at)
values(
  '91000000-0000-0000-0000-000000000001'::uuid,
  'historical-responsibility-fixture@example.test',
  now(),now()
);

insert into atlas.organizations(id,stable_key,name)
values(
  '92000000-0000-0000-0000-000000000001'::uuid,
  'historical-responsibility-fixture',
  'Historical Responsibility Fixture'
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active
) values(
  '93000000-0000-0000-0000-000000000001'::uuid,
  '92000000-0000-0000-0000-000000000001'::uuid,
  '91000000-0000-0000-0000-000000000001'::uuid,
  'member',
  true
);

insert into atlas.work_items(
  id,organization_id,title,work_state,operation_class,jurisdiction_key,stable_key,metadata
) values(
  '94000000-0000-0000-0000-000000000001'::uuid,
  '92000000-0000-0000-0000-000000000001'::uuid,
  'Historical exact responsibility',
  'open',
  'fixture',
  'fixture.history',
  'historical-responsibility-fixture-work',
  '{"source":"pre_establishment_basis_fixture"}'::jsonb
);

insert into atlas.work_allocations(
  id,organization_id,work_item_id,assignee_membership_id,
  allocation_role,state,metadata
) values(
  '95000000-0000-0000-0000-000000000001'::uuid,
  '92000000-0000-0000-0000-000000000001'::uuid,
  '94000000-0000-0000-0000-000000000001'::uuid,
  '93000000-0000-0000-0000-000000000001'::uuid,
  'responsible',
  'active',
  '{"source":"historical_pre_basis"}'::jsonb
);

-- Data-only prerequisite fixture for Package 4 flower notebook admission.
-- The candidate migration must seed durable flower spreads only for the Principal
-- who has both Organization ownership and active farm-level owner/manager authority.

insert into auth.users(id)
values
  ('94180000-0000-4000-8000-000000000001'::uuid),
  ('94180000-0000-4000-8000-000000000002'::uuid);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values (
  '94180000-0000-4000-8000-000000000010'::uuid,
  'flower_notebook_admission_fixture_org',
  'Flower Notebook Admission Fixture',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
values
  ('94180000-0000-4000-8000-000000000010'::uuid,'94180000-0000-4000-8000-000000000001'::uuid,'owner',true,'{}'::jsonb),
  ('94180000-0000-4000-8000-000000000010'::uuid,'94180000-0000-4000-8000-000000000002'::uuid,'owner',true,'{}'::jsonb);

insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
values (
  '94180000-0000-4000-8000-000000000020'::uuid,
  '94180000-0000-4000-8000-000000000010'::uuid,
  'flower_notebook_admission_fixture_farm',
  'Flower Notebook Admission Farm',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farm_memberships(user_id,farm_id,role,active,permissions)
values (
  '94180000-0000-4000-8000-000000000001'::uuid,
  '94180000-0000-4000-8000-000000000020'::uuid,
  'owner',
  true,
  '{}'::jsonb
);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata)
values
  (
    '94180000-0000-4000-8000-000000000101'::uuid,
    '94180000-0000-4000-8000-000000000001'::uuid,
    '94180000-0000-4000-8000-000000000010'::uuid,
    'flower_notebook_admission_eligible_principal',
    'Eligible Flower Notebook Principal',
    'active',
    '{"validation_fixture":true,"expected_flower_spread_admission":true}'::jsonb
  ),
  (
    '94180000-0000-4000-8000-000000000102'::uuid,
    '94180000-0000-4000-8000-000000000002'::uuid,
    '94180000-0000-4000-8000-000000000010'::uuid,
    'flower_notebook_admission_ineligible_principal',
    'Ineligible Flower Notebook Principal',
    'active',
    '{"validation_fixture":true,"expected_flower_spread_admission":false}'::jsonb
  );

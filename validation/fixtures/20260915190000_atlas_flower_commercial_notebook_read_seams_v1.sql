-- Data-only prerequisite fixture for Package 4 commercial notebook admission.
-- Both users own the Organization; only the first has active farm-level authority.

insert into auth.users(id)
values
  ('94190000-0000-4000-8000-000000000001'::uuid),
  ('94190000-0000-4000-8000-000000000002'::uuid);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values (
  '94190000-0000-4000-8000-000000000010'::uuid,
  'flower_commercial_admission_fixture_org',
  'Flower Commercial Admission Fixture',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions)
values
  ('94190000-0000-4000-8000-000000000010'::uuid,'94190000-0000-4000-8000-000000000001'::uuid,'owner',true,'{}'::jsonb),
  ('94190000-0000-4000-8000-000000000010'::uuid,'94190000-0000-4000-8000-000000000002'::uuid,'owner',true,'{}'::jsonb);

insert into atlas.farms(id,organization_id,stable_key,name,status,metadata)
values (
  '94190000-0000-4000-8000-000000000020'::uuid,
  '94190000-0000-4000-8000-000000000010'::uuid,
  'flower_commercial_admission_fixture_farm',
  'Flower Commercial Admission Farm',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.farm_memberships(user_id,farm_id,role,active,permissions)
values (
  '94190000-0000-4000-8000-000000000001'::uuid,
  '94190000-0000-4000-8000-000000000020'::uuid,
  'owner',
  true,
  '{}'::jsonb
);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata)
values
  (
    '94190000-0000-4000-8000-000000000101'::uuid,
    '94190000-0000-4000-8000-000000000001'::uuid,
    '94190000-0000-4000-8000-000000000010'::uuid,
    'flower_commercial_admission_eligible_principal',
    'Eligible Flower Commercial Principal',
    'active',
    '{"validation_fixture":true,"expected_flower_commercial_admission":true}'::jsonb
  ),
  (
    '94190000-0000-4000-8000-000000000102'::uuid,
    '94190000-0000-4000-8000-000000000002'::uuid,
    '94190000-0000-4000-8000-000000000010'::uuid,
    'flower_commercial_admission_ineligible_principal',
    'Ineligible Flower Commercial Principal',
    'active',
    '{"validation_fixture":true,"expected_flower_commercial_admission":false}'::jsonb
  );

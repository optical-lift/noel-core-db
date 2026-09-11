-- Validation-only fixture for Atlas Organization Spend Kernel v1.
-- Synthetic rows exist only inside the disposable production-schema clone.

insert into auth.users (id)
values ('00000000-0000-4000-8000-000000000501'::uuid);

insert into atlas.organizations (
  id, stable_key, name, status, metadata, onboarding_state
) values
(
  '00000000-0000-4000-8000-000000000510'::uuid,
  'fixture_spend_org',
  'Fixture Spend Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
),
(
  '00000000-0000-4000-8000-000000000520'::uuid,
  'fixture_other_org',
  'Fixture Other Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_units (
  id, organization_id, stable_key, name, unit_kind, status, metadata
) values
(
  '00000000-0000-4000-8000-000000000511'::uuid,
  '00000000-0000-4000-8000-000000000510'::uuid,
  'fixture_los_domos',
  'Fixture Los Domos',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '00000000-0000-4000-8000-000000000521'::uuid,
  '00000000-0000-4000-8000-000000000520'::uuid,
  'fixture_other_unit',
  'Fixture Other Unit',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships (
  id, organization_id, user_id, role, active, permissions
) values (
  '00000000-0000-4000-8000-000000000512'::uuid,
  '00000000-0000-4000-8000-000000000510'::uuid,
  '00000000-0000-4000-8000-000000000501'::uuid,
  'owner',
  true,
  '{}'::jsonb
);

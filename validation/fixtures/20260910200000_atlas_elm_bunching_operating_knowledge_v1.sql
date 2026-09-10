-- Validation-only fixture for the schema-only disposable production clone.
-- Synthetic identity rows mirror only the relationships required by the Elm seed.

INSERT INTO atlas.organizations (
  id, stable_key, name, status, metadata, onboarding_state
) VALUES (
  '00000000-0000-4000-8000-000000000101'::uuid,
  'fixture_elm_parent',
  'Fixture Elm Parent Organization',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

INSERT INTO atlas.organization_units (
  id, organization_id, stable_key, name, unit_kind, status, metadata
) VALUES (
  '00000000-0000-4000-8000-000000000102'::uuid,
  '00000000-0000-4000-8000-000000000101'::uuid,
  'fixture_elm_unit',
  'Fixture Elm Unit',
  'operating_business',
  'active',
  '{"validation_fixture":true}'::jsonb
);

INSERT INTO atlas.farms (
  id, stable_key, name, status, notes, organization_id, organization_unit_id, metadata
) VALUES (
  '00000000-0000-4000-8000-000000000103'::uuid,
  'elm_farm',
  'Elm Farm Validation Fixture',
  'active',
  'Synthetic row used only inside production-schema clone validation.',
  '00000000-0000-4000-8000-000000000101'::uuid,
  '00000000-0000-4000-8000-000000000102'::uuid,
  '{"validation_fixture":true}'::jsonb
);

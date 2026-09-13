-- Data-only prerequisite fixture for the disposable production-schema clone.
-- Recreates the minimum current institutional topology needed to prove Ledger backfill.

insert into atlas.organizations(
  id, stable_key, name, status, metadata, onboarding_state
) values
(
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'feast_guild',
  'Feast Guild',
  'active',
  '{"validation_fixture":true,"expected_scope_state":"legacy_mixed_pending_adjudication"}'::jsonb,
  'ready'
),
(
  '11111111-1111-4111-8111-111111111111'::uuid,
  'ledger_validation_company',
  'Ledger Validation Company',
  'active',
  '{"validation_fixture":true,"expected_scope_state":"canonical"}'::jsonb,
  'ready'
);

insert into atlas.organization_units(
  id, organization_id, parent_unit_id, stable_key, name, unit_kind, status, metadata
) values
(
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  null,
  'elm',
  'Elm',
  'operating_business',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  null,
  'waiting_room_farm',
  'Waiting Room Farm',
  'farm',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_ledger_entries(
  id,
  organization_id,
  organization_unit_id,
  event_key,
  source_domain,
  semantic_type,
  source_event_key,
  occurred_at,
  established_at,
  title,
  detail,
  truth_status,
  designation_status,
  payload,
  provenance,
  correlation,
  revision
) values (
  '33333333-3333-4333-8333-333333333333'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
  'ledger-validation-existing-entry',
  'validation_fixture',
  'company_work_result',
  'fixture:existing:1',
  '2026-09-01T12:00:00Z'::timestamptz,
  '2026-09-01T12:00:00Z'::timestamptz,
  'Existing mixed-scope Ledger entry',
  'Pre-migration row whose identity and revision must survive Ledger backfill.',
  'established',
  'designated',
  '{"validation_fixture":true}'::jsonb,
  '{"source":"first_class_ledger_validation_fixture"}'::jsonb,
  '{}'::jsonb,
  4242
);

insert into auth.users(id)
values ('44444444-4444-4444-8444-444444444444'::uuid);

-- Canonical Person compatibility triggers establish/fill person_id from this credential.
insert into atlas.principals(
  id,
  user_id,
  organization_id,
  stable_key,
  name,
  home_timezone,
  status,
  metadata
) values (
  '55555555-5555-4555-8555-555555555555'::uuid,
  '44444444-4444-4444-8444-444444444444'::uuid,
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'ledger_validation_principal',
  'Ledger Validation Principal',
  'America/Chicago',
  'active',
  '{"validation_fixture":true}'::jsonb
);

-- Data-only prerequisite fixture for the disposable production-schema clone.
-- Creates one credential-backed Principal and one credential-backed Person without a Principal.

insert into auth.users(id)
values
  ('66666666-6666-4666-8666-666666666666'::uuid),
  ('88888888-8888-4888-8888-888888888888'::uuid);

-- Principal compatibility trigger establishes canonical Person binding for this credential.
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
  '77777777-7777-4777-8777-777777777777'::uuid,
  '66666666-6666-4666-8666-666666666666'::uuid,
  null,
  'organization_ledger_establishment_fixture_principal',
  'Organization Ledger Establishment Fixture Principal',
  'America/Chicago',
  'active',
  '{"validation_fixture":true}'::jsonb
);

-- Give the second credential a canonical Person but deliberately no Principal.
select atlas.ensure_person_for_auth_user_v1(
  '88888888-8888-4888-8888-888888888888'::uuid,
  'No Principal Fixture Person'
);

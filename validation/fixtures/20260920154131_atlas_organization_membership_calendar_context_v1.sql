-- Data-only fixture for Organization Membership Calendar Context v1 candidate.
-- Apply to a disposable production-schema clone before candidate.sql.

insert into auth.users(id) values
  ('ca100000-0000-4000-8000-000000000001'::uuid),
  ('ca200000-0000-4000-8000-000000000001'::uuid),
  ('ca300000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('ca100000-0000-4000-8000-000000000011'::uuid,'Calendar Setup Actor','active','{"validation_fixture":true}'::jsonb),
  ('ca200000-0000-4000-8000-000000000011'::uuid,'Calendar Root Principal','active','{"validation_fixture":true}'::jsonb),
  ('ca300000-0000-4000-8000-000000000011'::uuid,'Calendar Unrelated Human','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('ca100000-0000-4000-8000-000000000021'::uuid,'ca100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','ca100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('ca200000-0000-4000-8000-000000000021'::uuid,'ca200000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','ca200000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('ca300000-0000-4000-8000-000000000021'::uuid,'ca300000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','ca300000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values
  ('ca110000-0000-4000-8000-000000000001'::uuid,'calendar_fixture_setup_org','Calendar Setup Org','active','{"validation_fixture":true}'::jsonb,'connecting_sources'),
  ('ca210000-0000-4000-8000-000000000001'::uuid,'calendar_fixture_root_org','Calendar Root Org','active','{"validation_fixture":true}'::jsonb,'ready'),
  ('ca310000-0000-4000-8000-000000000001'::uuid,'calendar_fixture_missing_org','Calendar Missing Context Org','active','{"validation_fixture":true}'::jsonb,'ready');

insert into atlas.organization_onboarding_actors(
  organization_id,human_user_id,actor_kind,active,metadata
) values (
  'ca110000-0000-4000-8000-000000000001'::uuid,
  'ca100000-0000-4000-8000-000000000001'::uuid,
  'setup_actor',true,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,person_id,role,active,permissions,
  eligibility_begins_on,eligibility_ends_on
) values (
  'ca110000-0000-4000-8000-000000000031'::uuid,
  'ca110000-0000-4000-8000-000000000001'::uuid,
  'ca100000-0000-4000-8000-000000000001'::uuid,
  'ca100000-0000-4000-8000-000000000011'::uuid,
  'member',true,'{}'::jsonb,
  '2026-09-10'::date,'2026-09-30'::date
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values (
  'ca200000-0000-4000-8000-000000000031'::uuid,
  'ca200000-0000-4000-8000-000000000001'::uuid,
  null,
  'calendar_fixture_root_principal',
  'Calendar Root Principal',
  'Pacific/Honolulu',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ca200000-0000-4000-8000-000000000011'::uuid
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values (
  'ca220000-0000-4000-8000-000000000001'::uuid,
  'calendarfixturerootledger000001',
  'Calendar Root Ledger',
  null,
  'governed_reality',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'ca230000-0000-4000-8000-000000000001'::uuid,
  'ca200000-0000-4000-8000-000000000031'::uuid,
  'ca220000-0000-4000-8000-000000000001'::uuid,
  'root_governing','active','calendar_context_validation',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'ca240000-0000-4000-8000-000000000001'::uuid,
  'ca220000-0000-4000-8000-000000000001'::uuid,
  'ca210000-0000-4000-8000-000000000001'::uuid,
  'governing',true,'active',
  '{"source":"calendar_context_validation"}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into auth.users(
  id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous
) values
('f6100000-0000-4000-8000-000000000001','authenticated','authenticated','obs-owner@example.invalid',now(),now(),false,false),
('f6100000-0000-4000-8000-000000000002','authenticated','authenticated','obs-member@example.invalid',now(),now(),false,false),
('f6100000-0000-4000-8000-000000000003','authenticated','authenticated','obs-setup@example.invalid',now(),now(),false,false),
('f6100000-0000-4000-8000-000000000004','authenticated','authenticated','obs-outsider@example.invalid',now(),now(),false,false);

insert into atlas.organizations(id,stable_key,name,status,metadata)
values
('f6110000-0000-4000-8000-000000000001','fixture-observation-org-a','Fixture Observation Org A','active','{"validationFixture":true}'::jsonb),
('f6110000-0000-4000-8000-000000000002','fixture-observation-org-b','Fixture Observation Org B','active','{"validationFixture":true}'::jsonb);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions
) values
('f6120000-0000-4000-8000-000000000001','f6110000-0000-4000-8000-000000000001','f6100000-0000-4000-8000-000000000001','owner',true,'{}'::jsonb),
('f6120000-0000-4000-8000-000000000002','f6110000-0000-4000-8000-000000000001','f6100000-0000-4000-8000-000000000002','member',true,'{}'::jsonb);

insert into atlas.organization_onboarding_actors(
  organization_id,human_user_id,actor_kind,active,metadata
) values (
  'f6110000-0000-4000-8000-000000000001',
  'f6100000-0000-4000-8000-000000000003',
  'setup_actor',
  true,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.connected_sources(
  id,custodian_user_id,custodian_organization_id,provider_key,provider_account_key,
  display_label,authorization_state,granted_scopes,capabilities,metadata
) values
(
  'f6130000-0000-4000-8000-000000000001',
  null,
  'f6110000-0000-4000-8000-000000000001',
  'flowerbuyer',
  'fixture-flowerbuyer-org-a',
  'Fixture FlowerBuyer',
  'connected',
  '{}'::text[],
  '{"browserObservation":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f6130000-0000-4000-8000-000000000002',
  null,
  'f6110000-0000-4000-8000-000000000001',
  'vendor_no_capability',
  'fixture-no-capability',
  'Fixture No Capability',
  'connected',
  '{}'::text[],
  '{}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f6130000-0000-4000-8000-000000000003',
  null,
  'f6110000-0000-4000-8000-000000000001',
  'vendor_reauth',
  'fixture-reauth',
  'Fixture Reauthorization',
  'reauthorization_required',
  '{}'::text[],
  '{"browserObservation":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f6130000-0000-4000-8000-000000000004',
  'f6100000-0000-4000-8000-000000000001',
  null,
  'personal_fixture',
  'fixture-human-source',
  'Fixture Human Source',
  'connected',
  '{}'::text[],
  '{"browserObservation":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f6130000-0000-4000-8000-000000000005',
  null,
  'f6110000-0000-4000-8000-000000000002',
  'other_org_fixture',
  'fixture-other-org',
  'Fixture Other Org Source',
  'connected',
  '{}'::text[],
  '{"browserObservation":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

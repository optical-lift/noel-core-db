-- Data-only fixture for Ledger-custodied Spend v1.

insert into auth.users(id)
values
  ('95336000-0000-4000-8000-000000000001'::uuid),
  ('95336000-0000-4000-8000-000000000002'::uuid);

insert into atlas.people(id,display_name,status,metadata)
values
(
  '95336000-0000-4000-8000-000000000003'::uuid,
  'Spend Fixture Owner A',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000004'::uuid,
  'Spend Fixture Owner B',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(id,person_id,auth_user_id,status,provenance)
values
(
  '95336000-0000-4000-8000-000000000005'::uuid,
  '95336000-0000-4000-8000-000000000003'::uuid,
  '95336000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000006'::uuid,
  '95336000-0000-4000-8000-000000000004'::uuid,
  '95336000-0000-4000-8000-000000000002'::uuid,
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values
(
  '95336000-0000-4000-8000-000000000010'::uuid,
  'spend_fixture_org_a',
  'Spend Fixture Organization A',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
),
(
  '95336000-0000-4000-8000-000000000011'::uuid,
  'spend_fixture_org_b',
  'Spend Fixture Organization B',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'ready'
);

insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status,metadata)
values
(
  '95336000-0000-4000-8000-000000000020'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  'spend_fixture_unit_a',
  'Spend Fixture Unit A',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000021'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  'spend_fixture_unit_b',
  'Spend Fixture Unit B',
  'operating_unit',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions,person_id
)
values
(
  '95336000-0000-4000-8000-000000000030'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  '95336000-0000-4000-8000-000000000001'::uuid,
  'owner',true,'{}'::jsonb,
  '95336000-0000-4000-8000-000000000003'::uuid
),
(
  '95336000-0000-4000-8000-000000000031'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  '95336000-0000-4000-8000-000000000002'::uuid,
  'owner',true,'{}'::jsonb,
  '95336000-0000-4000-8000-000000000004'::uuid
);

insert into atlas.ledgers(id,stable_key,organization_id,ledger_kind,status,metadata,name)
values
(
  '95336000-0000-4000-8000-000000000040'::uuid,
  'spend_fixture_ledger_a',
  null,
  'organization_governing',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'Spend Fixture Ledger A'
),
(
  '95336000-0000-4000-8000-000000000041'::uuid,
  'spend_fixture_ledger_b',
  null,
  'organization_governing',
  'active',
  '{"validation_fixture":true}'::jsonb,
  'Spend Fixture Ledger B'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
)
values
(
  '95336000-0000-4000-8000-000000000042'::uuid,
  '95336000-0000-4000-8000-000000000040'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  'governing',true,'active',
  '{"validation_fixture":true}'::jsonb,
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000043'::uuid,
  '95336000-0000-4000-8000-000000000041'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  'governing',true,'active',
  '{"validation_fixture":true}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,status,metadata,person_id)
values
(
  '95336000-0000-4000-8000-000000000050'::uuid,
  '95336000-0000-4000-8000-000000000001'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  'spend_fixture_principal_a',
  'Spend Fixture Principal A',
  'active',
  '{"validation_fixture":true}'::jsonb,
  '95336000-0000-4000-8000-000000000003'::uuid
),
(
  '95336000-0000-4000-8000-000000000051'::uuid,
  '95336000-0000-4000-8000-000000000002'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  'spend_fixture_principal_b',
  'Spend Fixture Principal B',
  'active',
  '{"validation_fixture":true}'::jsonb,
  '95336000-0000-4000-8000-000000000004'::uuid
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
)
values
(
  '95336000-0000-4000-8000-000000000052'::uuid,
  '95336000-0000-4000-8000-000000000050'::uuid,
  '95336000-0000-4000-8000-000000000040'::uuid,
  'root_governing','active','validation_fixture','{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000053'::uuid,
  '95336000-0000-4000-8000-000000000051'::uuid,
  '95336000-0000-4000-8000-000000000041'::uuid,
  'root_governing','active','validation_fixture','{"validation_fixture":true}'::jsonb
);

insert into atlas.identity_subjects(id,organization_id,state,created_by_user_id,creation_basis)
values
(
  '95336000-0000-4000-8000-000000000060'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  'active',
  '95336000-0000-4000-8000-000000000001'::uuid,
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000061'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  'active',
  '95336000-0000-4000-8000-000000000002'::uuid,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.external_relationships(
  id,organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata
)
values
(
  '95336000-0000-4000-8000-000000000062'::uuid,
  '95336000-0000-4000-8000-000000000010'::uuid,
  null,
  '95336000-0000-4000-8000-000000000060'::uuid,
  'spend_fixture_vendor_a',
  'active',
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000063'::uuid,
  '95336000-0000-4000-8000-000000000011'::uuid,
  null,
  '95336000-0000-4000-8000-000000000061'::uuid,
  'spend_fixture_vendor_b',
  'active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.evidence_records(
  id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
  source_kind,source_key,actor_user_id,value,confidence,observed_at,provenance,metadata
)
values
(
  '95336000-0000-4000-8000-000000000070'::uuid,
  'principal',
  '95336000-0000-4000-8000-000000000050'::uuid,
  'finance','receipt','spend-fixture-receipt-a','document',
  'validation_fixture','spend-evidence-a',
  '95336000-0000-4000-8000-000000000001'::uuid,
  '{"amount":1650,"currency":"MXN"}'::jsonb,
  1,
  '2026-09-15 17:30:00+00',
  '{"validation_fixture":true}'::jsonb,
  '{"validation_fixture":true}'::jsonb
),
(
  '95336000-0000-4000-8000-000000000071'::uuid,
  'principal',
  '95336000-0000-4000-8000-000000000051'::uuid,
  'finance','receipt','spend-fixture-receipt-b','document',
  'validation_fixture','spend-evidence-b',
  '95336000-0000-4000-8000-000000000002'::uuid,
  '{"amount":500,"currency":"USD"}'::jsonb,
  1,
  '2026-09-15 17:30:00+00',
  '{"validation_fixture":true}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

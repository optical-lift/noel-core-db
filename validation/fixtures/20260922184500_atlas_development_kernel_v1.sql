-- Clone-only fixture for Atlas Development Kernel v1.
-- Supplies two genuinely different Organization/Ledger contexts plus one
-- established Elm Operating Knowledge rule. Development schema does not exist yet.

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values
(
  'd5e00000-0000-4000-8000-000000000001'::uuid,
  'development-proof-ci',
  'Development Proof Camps International',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
),
(
  'd5e00000-0000-4000-8000-000000000101'::uuid,
  'development-proof-elm',
  'Development Proof Elm',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into atlas.ledgers(
  id,stable_key,organization_id,ledger_kind,status,metadata,name
) values
(
  'd5e00000-0000-4000-8000-000000000002'::uuid,
  'development-proof-ci-ledger',
  'd5e00000-0000-4000-8000-000000000001'::uuid,
  'organization_governing',
  'active',
  '{"validationFixture":true}'::jsonb,
  'Development Proof CI Ledger'
),
(
  'd5e00000-0000-4000-8000-000000000102'::uuid,
  'development-proof-elm-ledger',
  'd5e00000-0000-4000-8000-000000000101'::uuid,
  'organization_governing',
  'active',
  '{"validationFixture":true}'::jsonb,
  'Development Proof Elm Ledger'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values
(
  'd5e00000-0000-4000-8000-000000000003'::uuid,
  'd5e00000-0000-4000-8000-000000000002'::uuid,
  'd5e00000-0000-4000-8000-000000000001'::uuid,
  'governing',
  true,
  'active',
  '{"kind":"validation_fixture","reason":"CI Development proof"}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'd5e00000-0000-4000-8000-000000000103'::uuid,
  'd5e00000-0000-4000-8000-000000000102'::uuid,
  'd5e00000-0000-4000-8000-000000000101'::uuid,
  'governing',
  true,
  'active',
  '{"kind":"validation_fixture","reason":"Elm Development proof"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.company_operating_knowledge(
  id,organization_id,organization_unit_id,family_key,stable_key,version,
  knowledge_kind,title,statement,scope_match,effect,precedence,status,
  confidence,effective_from,established_by_label,established_at,
  provenance,metadata
) values (
  'd5e00000-0000-4000-8000-000000000150'::uuid,
  'd5e00000-0000-4000-8000-000000000101'::uuid,
  null,
  'cut_flower_bunch_size',
  'development.fixture.elm.bunch.default',
  1,
  'standard',
  'Development fixture cut-flower bunch default',
  'Fixture cut flowers use 10 stems per bunch unless a more-specific established rule applies.',
  '{"operation":"bunch","category":"cut_flower"}'::jsonb,
  '{"sales_unit":"bunch","quantity_per_unit":10,"quantity_unit":"stem"}'::jsonb,
  0,
  'established',
  1.0000,
  '2026-09-22 00:00:00+00'::timestamptz,
  'Development validation fixture',
  '2026-09-22 00:00:00+00'::timestamptz,
  '{"source_kind":"validation_fixture"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

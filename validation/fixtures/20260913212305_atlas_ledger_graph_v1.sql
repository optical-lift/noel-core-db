-- Data-only fixture for Atlas Ledger Graph v1.
-- Creates pre-graph institutional reality, five Person-backed Principals, one preserved
-- Organization Ledger entry, and one implementation commerce case.

insert into auth.users(id)
values
  ('11111111-1111-4111-8111-111111111111'::uuid),
  ('22222222-2222-4222-8222-222222222221'::uuid),
  ('33333333-3333-4333-8333-333333333331'::uuid),
  ('44444444-4444-4444-8444-444444444441'::uuid),
  ('55555555-5555-4555-8555-555555555551'::uuid);

-- These Organizations are intentionally inserted before Ledger Graph v1, while the old
-- universal trigger still creates exactly one same-key governing Ledger for each.
insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values
(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'ledger_graph_fixture_alpha',
  'Ledger Graph Fixture Alpha',
  'active','{"validation_fixture":true}'::jsonb,'ready'
),
(
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid,
  'ledger_graph_fixture_beta',
  'Ledger Graph Fixture Beta',
  'active','{"validation_fixture":true}'::jsonb,'ready'
);

-- Preserve the pre-migration Ledger IDs in Organization metadata as DML-only evidence.
update atlas.organizations o
set metadata = o.metadata || jsonb_build_object(
  'validationPreGraphLedgerId',(
    select l.id::text from atlas.ledgers l where l.organization_id=o.id limit 1
  )
)
where o.id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata
) values
(
  '11111111-1111-4111-8111-111111111112'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid,
  'ledger_graph_fixture_principal_1','Ledger Graph Fixture Principal 1','America/Chicago','active','{"validation_fixture":true}'::jsonb
),
(
  '22222222-2222-4222-8222-222222222222'::uuid,
  '22222222-2222-4222-8222-222222222221'::uuid,
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'::uuid,
  'ledger_graph_fixture_principal_2','Ledger Graph Fixture Principal 2','America/Chicago','active','{"validation_fixture":true}'::jsonb
),
(
  '33333333-3333-4333-8333-333333333332'::uuid,
  '33333333-3333-4333-8333-333333333331'::uuid,
  null,
  'ledger_graph_fixture_principal_3','Ledger Graph Fixture Principal 3','America/Chicago','active','{"validation_fixture":true}'::jsonb
),
(
  '44444444-4444-4444-8444-444444444442'::uuid,
  '44444444-4444-4444-8444-444444444441'::uuid,
  null,
  'ledger_graph_fixture_principal_4','Ledger Graph Fixture Principal 4','America/Chicago','active','{"validation_fixture":true}'::jsonb
),
(
  '55555555-5555-4555-8555-555555555552'::uuid,
  '55555555-5555-4555-8555-555555555551'::uuid,
  null,
  'ledger_graph_fixture_principal_5','Ledger Graph Fixture Principal 5','America/Chicago','active','{"validation_fixture":true}'::jsonb
);

-- One preexisting root authority grant must survive byte-for-byte in identity.
insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
)
select
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaa1'::uuid,
  '11111111-1111-4111-8111-111111111112'::uuid,
  l.id,
  'root_governing','active','ledger_graph_fixture_preexisting',
  '{"validation_fixture":true}'::jsonb
from atlas.ledgers l
where l.organization_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid;

-- One preexisting organization-scoped Ledger event proves the composite ownership FK can
-- be removed without changing record ID, Ledger ID, or revision.
insert into atlas.organization_ledger_entries(
  id,organization_id,event_key,source_domain,semantic_type,occurred_at,
  title,detail,payload,provenance,correlation,ledger_id
)
select
  'aaaaaaaa-2222-4222-8222-aaaaaaaaaaa2'::uuid,
  o.id,
  'ledger_graph_fixture:preexisting_event',
  'validation_fixture','preexisting_event',now(),
  'Preexisting Ledger Graph event','Must preserve identity and revision.',
  '{"validation_fixture":true}'::jsonb,
  '{"source":"ledger_graph_fixture"}'::jsonb,
  '{}'::jsonb,
  l.id
from atlas.organizations o
join atlas.ledgers l on l.organization_id=o.id
where o.id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid;

update atlas.organizations o
set metadata = o.metadata || jsonb_build_object(
  'validationPreGraphEntryRevision',(
    select e.revision from atlas.organization_ledger_entries e
    where e.id='aaaaaaaa-2222-4222-8222-aaaaaaaaaaa2'::uuid
  )
)
where o.id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::uuid;

-- Minimal commercial implementation case for post-migration binding verification.
insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  '55555555-5555-4555-8555-555555555551'::uuid,
  'active','{"basis":"ledger_graph_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider_checkout_session_id,offer_key,starting_label,payment_option,purchase_state,
  currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values (
  '66666666-6666-4666-8666-666666666601'::uuid,
  'ledger-graph-fixture-checkout','fixture-offer','Ledger Graph Commercial Fixture',
  'pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_cases(id,implementation_purchase_id,state,metadata)
values (
  '66666666-6666-4666-8666-666666666611'::uuid,
  '66666666-6666-4666-8666-666666666601'::uuid,
  'in_implementation','{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
  '66666666-6666-4666-8666-666666666621'::uuid,
  '66666666-6666-4666-8666-666666666611'::uuid,
  '55555555-5555-4555-8555-555555555551'::uuid,
  'practitioner',true,null,'{"basis":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
),
(
  '66666666-6666-4666-8666-666666666622'::uuid,
  '66666666-6666-4666-8666-666666666611'::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  'setup_sponsor',true,now(),'{"basis":"ledger_graph_validation"}'::jsonb,'{}'::jsonb
);

insert into atlas.implementation_establishment_items(
  id,implementation_case_id,category,title,detail,status,author_user_id,basis
) values
(
  '66666666-6666-4666-8666-666666666631'::uuid,
  '66666666-6666-4666-8666-666666666611'::uuid,
  'institution','Institution','','established',
  '55555555-5555-4555-8555-555555555551'::uuid,'{}'::jsonb
),
(
  '66666666-6666-4666-8666-666666666632'::uuid,
  '66666666-6666-4666-8666-666666666611'::uuid,
  'ledger_scope','Ledger Scope','','established',
  '55555555-5555-4555-8555-555555555551'::uuid,'{}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,entitlement_kind,price_class,state,
  setup_price_cents,monthly_price_cents,commercial_basis,metadata
) values (
  '66666666-6666-4666-8666-666666666641'::uuid,
  '66666666-6666-4666-8666-666666666611'::uuid,
  '66666666-6666-4666-8666-666666666601'::uuid,
  1,'atlas_ledger','baseline_first','available',300000,40000,'{}'::jsonb,'{}'::jsonb
);

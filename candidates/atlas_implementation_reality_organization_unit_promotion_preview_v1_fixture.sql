-- Clone-only fixture for Atlas Implementation Reality Organization Unit Promotion Preview v1.
-- Requires live Reality Candidate semantic payload v2.
-- Proves ready, nested-parent, missing-semantic, duplicate-identity,
-- unresolved-parent, and out-of-scope paths.

insert into auth.users(id) values
  ('f4400000-0000-4000-8000-000000000001'::uuid),
  ('f4400000-0000-4000-8000-000000000002'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4400000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider,provider_checkout_session_id,offer_key,starting_label,payment_option,
  purchase_state,currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values (
  'f4400000-0000-4000-8000-000000000101'::uuid,
  'stripe','cs_validation_org_unit_preview','validation_org_unit_preview',
  'Organization Unit Proof','pay_in_full','active','usd',0,0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values (
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
  'f4400000-0000-4000-8000-000000000121'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000001'::uuid,
  'practitioner',true,now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4400000-0000-4000-8000-000000000122'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000002'::uuid,
  'setup_sponsor',true,now(),
  '{"validationFixture":true,"verifiedSetupSponsor":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values
(
  'f4400000-0000-4000-8000-000000000201'::uuid,
  'org_unit_proof_org','Organization Unit Proof','active',
  '{"validationFixture":true}'::jsonb,'ready'
),
(
  'f4400000-0000-4000-8000-000000000202'::uuid,
  'org_unit_outside_org','Outside Organization','active',
  '{"validationFixture":true}'::jsonb,'ready'
);

insert into atlas.organization_units(
  id,organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata
) values
(
  'f4400000-0000-4000-8000-000000000211'::uuid,
  'f4400000-0000-4000-8000-000000000201'::uuid,
  null,'existing_parent','Existing Parent','operating_business','active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4400000-0000-4000-8000-000000000212'::uuid,
  'f4400000-0000-4000-8000-000000000201'::uuid,
  null,'existing_unit','Existing Unit','department','active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.principals(
  id,user_id,stable_key,name,status,metadata
) values (
  'f4400000-0000-4000-8000-000000000221'::uuid,
  'f4400000-0000-4000-8000-000000000002'::uuid,
  'org_unit_setup_sponsor','Organization Unit Setup Sponsor','active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values (
  'f4400000-0000-4000-8000-000000000231'::uuid,
  'orgunitproofledger0001','Organization Unit Proof Ledger',null,
  'governed_reality','active','{"validationFixture":true}'::jsonb
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'f4400000-0000-4000-8000-000000000232'::uuid,
  'f4400000-0000-4000-8000-000000000221'::uuid,
  'f4400000-0000-4000-8000-000000000231'::uuid,
  'root_governing','active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'f4400000-0000-4000-8000-000000000233'::uuid,
  'f4400000-0000-4000-8000-000000000231'::uuid,
  'f4400000-0000-4000-8000-000000000201'::uuid,
  'governing',true,'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,entitlement_kind,
  price_class,state,setup_price_cents,monthly_price_cents,commercial_basis,metadata
) values (
  'f4400000-0000-4000-8000-000000000241'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000101'::uuid,
  1,'atlas_ledger','baseline_first','bound',0,0,
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlement_bindings(
  id,implementation_case_id,ledger_entitlement_id,organization_id,organization_unit_id,
  bound_by_participant_id,state,activated_at,binding_basis,metadata,ledger_id
) values (
  'f4400000-0000-4000-8000-000000000242'::uuid,
  'f4400000-0000-4000-8000-000000000111'::uuid,
  'f4400000-0000-4000-8000-000000000241'::uuid,
  'f4400000-0000-4000-8000-000000000201'::uuid,
  null,
  'f4400000-0000-4000-8000-000000000121'::uuid,
  'activated',now(),
  '{"validationFixture":true,"sponsorGoverned":true}'::jsonb,
  '{"validationFixture":true}'::jsonb,
  'f4400000-0000-4000-8000-000000000231'::uuid
);

-- Reality Candidate rows use the new organization_unit.establish grammar and
-- are inserted by post-migration validation after the operation constraint is widened.

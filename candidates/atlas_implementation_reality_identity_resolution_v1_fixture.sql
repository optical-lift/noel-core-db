-- Clone-only fixture for Atlas Implementation Reality Identity Resolution v1.
-- Creates one practitioner with two assigned cases: one bound to a canonical
-- Organization and one deliberately unbound. A second Organization contains
-- identically named identities and must remain invisible to the bound case.

insert into auth.users(id) values
  ('f4200000-0000-4000-8000-000000000001'::uuid),
  ('f4200000-0000-4000-8000-000000000002'::uuid),
  ('f4200000-0000-4000-8000-000000000003'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4200000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,
  provider,
  provider_checkout_session_id,
  offer_key,
  starting_label,
  payment_option,
  purchase_state,
  currency,
  setup_contract_amount_cents,
  monthly_ledger_unit_price_cents,
  metadata
) values
(
  'f4200000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_identity_bound',
  'validation_reality_identity',
  'Resolver Bound Case',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000102'::uuid,
  'stripe',
  'cs_validation_identity_unbound',
  'validation_reality_identity',
  'Resolver Unbound Case',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values
(
  'f4200000-0000-4000-8000-000000000111'::uuid,
  'f4200000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000112'::uuid,
  'f4200000-0000-4000-8000-000000000102'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,
  implementation_case_id,
  human_user_id,
  relationship_kind,
  active,
  verified_at,
  basis,
  metadata
) values
(
  'f4200000-0000-4000-8000-000000000121'::uuid,
  'f4200000-0000-4000-8000-000000000111'::uuid,
  'f4200000-0000-4000-8000-000000000001'::uuid,
  'practitioner',
  true,
  now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000122'::uuid,
  'f4200000-0000-4000-8000-000000000112'::uuid,
  'f4200000-0000-4000-8000-000000000001'::uuid,
  'practitioner',
  true,
  now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values
(
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'resolver_bound_org',
  'Resolver Bound Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
),
(
  'f4200000-0000-4000-8000-000000000202'::uuid,
  'resolver_outside_org',
  'Resolver Outside Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into atlas.people(id,display_name,status,metadata) values
(
  'f4200000-0000-4000-8000-000000000211'::uuid,
  'Anna Resolver',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000212'::uuid,
  'Anna Resolver Outside',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000215'::uuid,
  'Anna Accountless',
  'active',
  '{"validationFixture":true,"accountless":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000216'::uuid,
  'Anna Accountless',
  'active',
  '{"validationFixture":true,"accountless":true,"outsideScope":true}'::jsonb
);

insert into atlas.institutional_person_records(
  id,organization_id,person_id,status,establishment_basis
) values
(
  'f4200000-0000-4000-8000-000000000217'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'f4200000-0000-4000-8000-000000000215'::uuid,
  'active',
  '{"validationFixture":true,"basisKind":"accountless_resolution_proof"}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000218'::uuid,
  'f4200000-0000-4000-8000-000000000202'::uuid,
  'f4200000-0000-4000-8000-000000000216'::uuid,
  'active',
  '{"validationFixture":true,"basisKind":"outside_scope_accountless_proof"}'::jsonb
);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
(
  'f4200000-0000-4000-8000-000000000213'::uuid,
  'f4200000-0000-4000-8000-000000000211'::uuid,
  'supabase_auth_user',
  'f4200000-0000-4000-8000-000000000002'::uuid,
  'active',
  now(),
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000214'::uuid,
  'f4200000-0000-4000-8000-000000000212'::uuid,
  'supabase_auth_user',
  'f4200000-0000-4000-8000-000000000003'::uuid,
  'active',
  now(),
  '{"validationFixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
(
  'f4200000-0000-4000-8000-000000000213'::uuid,
  'f4200000-0000-4000-8000-000000000211'::uuid,
  'supabase_auth_user',
  'f4200000-0000-4000-8000-000000000002'::uuid,
  'active',
  now(),
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000214'::uuid,
  'f4200000-0000-4000-8000-000000000212'::uuid,
  'supabase_auth_user',
  'f4200000-0000-4000-8000-000000000003'::uuid,
  'active',
  now(),
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,person_id,role,active,permissions
) values
(
  'f4200000-0000-4000-8000-000000000221'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'f4200000-0000-4000-8000-000000000002'::uuid,
  'f4200000-0000-4000-8000-000000000211'::uuid,
  'member',
  true,
  '{}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000222'::uuid,
  'f4200000-0000-4000-8000-000000000202'::uuid,
  'f4200000-0000-4000-8000-000000000003'::uuid,
  'f4200000-0000-4000-8000-000000000212'::uuid,
  'member',
  true,
  '{}'::jsonb
);

insert into atlas.organization_units(
  id,organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata
) values
(
  'f4200000-0000-4000-8000-000000000231'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  null,
  'resolver_bound_root',
  'Bound Root',
  'operating_unit',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000232'::uuid,
  'f4200000-0000-4000-8000-000000000202'::uuid,
  null,
  'resolver_outside_root',
  'Outside Root',
  'operating_unit',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_positions(
  id,organization_id,organization_unit_id,stable_key,display_title,position_kind,status,metadata
) values
(
  'f4200000-0000-4000-8000-000000000241'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'f4200000-0000-4000-8000-000000000231'::uuid,
  'farm_steward',
  'Farm Steward',
  'staff',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000242'::uuid,
  'f4200000-0000-4000-8000-000000000202'::uuid,
  'f4200000-0000-4000-8000-000000000232'::uuid,
  'farm_steward',
  'Farm Steward',
  'staff',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organization_responsibilities(
  id,organization_id,stable_key,name,responsibility_kind,status,metadata
) values
(
  'f4200000-0000-4000-8000-000000000251'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'production_stewardship',
  'Production stewardship',
  'stewardship',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000252'::uuid,
  'f4200000-0000-4000-8000-000000000202'::uuid,
  'production_stewardship',
  'Production stewardship',
  'stewardship',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values (
  'f4200000-0000-4000-8000-000000000261'::uuid,
  'resolverboundledger000001',
  'Resolver Bound Ledger',
  null,
  'governed_reality',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'f4200000-0000-4000-8000-000000000271'::uuid,
  'f4200000-0000-4000-8000-000000000261'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  'governing',
  true,
  'active',
  '{"source":"reality_identity_validation"}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,
  implementation_case_id,
  source_purchase_id,
  entitlement_number,
  entitlement_kind,
  price_class,
  state,
  setup_price_cents,
  monthly_price_cents,
  commercial_basis,
  metadata
) values
(
  'f4200000-0000-4000-8000-000000000281'::uuid,
  'f4200000-0000-4000-8000-000000000111'::uuid,
  'f4200000-0000-4000-8000-000000000101'::uuid,
  1,
  'atlas_ledger',
  'baseline_first',
  'bound',
  0,
  0,
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4200000-0000-4000-8000-000000000282'::uuid,
  'f4200000-0000-4000-8000-000000000112'::uuid,
  'f4200000-0000-4000-8000-000000000102'::uuid,
  1,
  'atlas_ledger',
  'baseline_first',
  'available',
  0,
  0,
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlement_bindings(
  id,
  implementation_case_id,
  ledger_entitlement_id,
  organization_id,
  organization_unit_id,
  bound_by_participant_id,
  state,
  activated_at,
  binding_basis,
  metadata,
  ledger_id
) values (
  'f4200000-0000-4000-8000-000000000291'::uuid,
  'f4200000-0000-4000-8000-000000000111'::uuid,
  'f4200000-0000-4000-8000-000000000281'::uuid,
  'f4200000-0000-4000-8000-000000000201'::uuid,
  null,
  'f4200000-0000-4000-8000-000000000121'::uuid,
  'activated',
  now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb,
  'f4200000-0000-4000-8000-000000000261'::uuid
);

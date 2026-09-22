-- Clone-only fixture for Initial Scope Discovery v1.

insert into auth.users(id) values
  ('f4500000-0000-4000-8000-000000000001'::uuid),
  ('f4500000-0000-4000-8000-000000000002'::uuid),
  ('f4500000-0000-4000-8000-000000000003'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4500000-0000-4000-8000-000000000001'::uuid,
  'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider,provider_checkout_session_id,offer_key,starting_label,
  payment_option,purchase_state,currency,setup_contract_amount_cents,
  monthly_ledger_unit_price_cents,metadata
) values (
  'f4500000-0000-4000-8000-000000000101'::uuid,
  'stripe',
  'cs_validation_scope_discovery',
  'validation_scope_discovery',
  'Scope Discovery Proof',
  'pay_in_full',
  'active',
  'usd',
  0,
  0,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(
  id,implementation_purchase_id,state,metadata
) values (
  'f4500000-0000-4000-8000-000000000111'::uuid,
  'f4500000-0000-4000-8000-000000000101'::uuid,
  'in_implementation',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,
  verified_at,basis,metadata
) values
(
  'f4500000-0000-4000-8000-000000000121'::uuid,
  'f4500000-0000-4000-8000-000000000111'::uuid,
  'f4500000-0000-4000-8000-000000000001'::uuid,
  'practitioner',true,now(),
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000122'::uuid,
  'f4500000-0000-4000-8000-000000000111'::uuid,
  'f4500000-0000-4000-8000-000000000002'::uuid,
  'setup_sponsor',true,now(),
  '{"validationFixture":true,"verifiedSetupSponsor":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.people(id,display_name,status,metadata) values
(
  'f4500000-0000-4000-8000-000000000201'::uuid,
  'Scope Sponsor Person',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000202'::uuid,
  'Outside Principal Person',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
(
  'f4500000-0000-4000-8000-000000000211'::uuid,
  'f4500000-0000-4000-8000-000000000201'::uuid,
  'supabase_auth_user',
  'f4500000-0000-4000-8000-000000000002'::uuid,
  'active',now(),
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000212'::uuid,
  'f4500000-0000-4000-8000-000000000202'::uuid,
  'supabase_auth_user',
  'f4500000-0000-4000-8000-000000000003'::uuid,
  'active',now(),
  '{"validationFixture":true}'::jsonb
);

insert into atlas.principals(
  id,user_id,person_id,stable_key,name,status,metadata
) values
(
  'f4500000-0000-4000-8000-000000000221'::uuid,
  'f4500000-0000-4000-8000-000000000002'::uuid,
  'f4500000-0000-4000-8000-000000000201'::uuid,
  'scope_sponsor_principal',
  'Scope Sponsor Principal',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000222'::uuid,
  'f4500000-0000-4000-8000-000000000003'::uuid,
  'f4500000-0000-4000-8000-000000000202'::uuid,
  'outside_scope_principal',
  'Outside Scope Principal',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values
(
  'f4500000-0000-4000-8000-000000000301'::uuid,
  'scope_visible_org',
  'Visible Sponsor Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
),
(
  'f4500000-0000-4000-8000-000000000302'::uuid,
  'scope_outside_org',
  'Outside Hidden Organization',
  'active',
  '{"validationFixture":true}'::jsonb,
  'ready'
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values
(
  'f4500000-0000-4000-8000-000000000311'::uuid,
  'scope_visible_ledger',
  'Visible Sponsor Ledger',
  null,
  'governed_reality',
  'active',
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000312'::uuid,
  'scope_outside_ledger',
  'Outside Hidden Ledger',
  null,
  'governed_reality',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,
  status,basis,metadata
) values
(
  'f4500000-0000-4000-8000-000000000321'::uuid,
  'f4500000-0000-4000-8000-000000000311'::uuid,
  'f4500000-0000-4000-8000-000000000301'::uuid,
  'governing',true,'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000322'::uuid,
  'f4500000-0000-4000-8000-000000000312'::uuid,
  'f4500000-0000-4000-8000-000000000302'::uuid,
  'governing',true,'active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values
(
  'f4500000-0000-4000-8000-000000000331'::uuid,
  'f4500000-0000-4000-8000-000000000221'::uuid,
  'f4500000-0000-4000-8000-000000000311'::uuid,
  'root_governing','active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
),
(
  'f4500000-0000-4000-8000-000000000332'::uuid,
  'f4500000-0000-4000-8000-000000000222'::uuid,
  'f4500000-0000-4000-8000-000000000312'::uuid,
  'root_governing','active',
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,
  entitlement_kind,price_class,state,setup_price_cents,monthly_price_cents,
  commercial_basis,metadata
) values (
  'f4500000-0000-4000-8000-000000000341'::uuid,
  'f4500000-0000-4000-8000-000000000111'::uuid,
  'f4500000-0000-4000-8000-000000000101'::uuid,
  1,'atlas_ledger','baseline_first','available',0,0,
  '{"validationFixture":true}'::jsonb,
  '{"validationFixture":true}'::jsonb
);

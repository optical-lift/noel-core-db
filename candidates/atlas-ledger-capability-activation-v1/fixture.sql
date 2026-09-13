-- Data-only fixture for Atlas Ledger Capability Activation v1 candidate.
-- Assumes current production schema through Ledger Graph v1, before the candidate is applied.

insert into auth.users(id) values
  ('a1000000-0000-4000-8000-000000000001'::uuid),
  ('b1000000-0000-4000-8000-000000000001'::uuid),
  ('f1000000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('a1000000-0000-4000-8000-000000000011'::uuid,'Capability Fixture Root','active','{"validation_fixture":true}'::jsonb),
  ('b1000000-0000-4000-8000-000000000011'::uuid,'Capability Fixture Org Owner','active','{"validation_fixture":true}'::jsonb),
  ('f1000000-0000-4000-8000-000000000011'::uuid,'Capability Fixture Practitioner','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('a1000000-0000-4000-8000-000000000021'::uuid,'a1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','a1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('b1000000-0000-4000-8000-000000000021'::uuid,'b1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','b1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('f1000000-0000-4000-8000-000000000021'::uuid,'f1000000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','f1000000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values
  ('a1000000-0000-4000-8000-000000000031'::uuid,'a1000000-0000-4000-8000-000000000001'::uuid,null,'cap_fixture_principal_root','Capability Fixture Root','America/Chicago','active','{"validation_fixture":true}'::jsonb,'a1000000-0000-4000-8000-000000000011'::uuid),
  ('b1000000-0000-4000-8000-000000000031'::uuid,'b1000000-0000-4000-8000-000000000001'::uuid,null,'cap_fixture_principal_owner','Capability Fixture Org Owner','America/Chicago','active','{"validation_fixture":true}'::jsonb,'b1000000-0000-4000-8000-000000000011'::uuid);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values
  ('a2000000-0000-4000-8000-000000000001'::uuid,'capabilityfixtureledgerroot000001','Capability Fixture Governed Ledger',null,'governed_reality','active','{"validation_fixture":true}'::jsonb),
  ('b2000000-0000-4000-8000-000000000001'::uuid,'capabilityfixtureledgerother00001','Capability Fixture Other Ledger',null,'governed_reality','active','{"validation_fixture":true}'::jsonb);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values
  ('a3000000-0000-4000-8000-000000000001'::uuid,'a1000000-0000-4000-8000-000000000031'::uuid,'a2000000-0000-4000-8000-000000000001'::uuid,'root_governing','active','capability_activation_validation','{"validation_fixture":true}'::jsonb),
  ('b3000000-0000-4000-8000-000000000001'::uuid,'b1000000-0000-4000-8000-000000000031'::uuid,'b2000000-0000-4000-8000-000000000001'::uuid,'root_governing','active','capability_activation_validation','{"validation_fixture":true}'::jsonb);

-- Organization owner on the governed Ledger, deliberately without Principal/Ledger authority.
insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values (
  'b4000000-0000-4000-8000-000000000001'::uuid,
  'cap_fixture_org_owner',
  'Capability Fixture Organization',
  'active','{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'b4000000-0000-4000-8000-000000000011'::uuid,
  'a2000000-0000-4000-8000-000000000001'::uuid,
  'b4000000-0000-4000-8000-000000000001'::uuid,
  'governing',false,'active','{"source":"capability_activation_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions,person_id
) values (
  'b4000000-0000-4000-8000-000000000021'::uuid,
  'b4000000-0000-4000-8000-000000000001'::uuid,
  'b1000000-0000-4000-8000-000000000001'::uuid,
  'owner',true,'{}'::jsonb,
  'b1000000-0000-4000-8000-000000000011'::uuid
);

-- Commercial implementation evidence bound to the governed Ledger. The setup sponsor is the
-- non-authoritative Organization owner, proving commerce does not manufacture root authority.
insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f1000000-0000-4000-8000-000000000001'::uuid,
  'active','{"basis":"capability_activation_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider_checkout_session_id,offer_key,starting_label,payment_option,purchase_state,
  currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values (
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'capability-activation-fixture-checkout','fixture-titus','Capability Activation Fixture',
  'pay_in_full','active','usd',300000,40000,'{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_cases(id,implementation_purchase_id,state,metadata) values (
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  'in_implementation','{"validation_fixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
  'c1000000-0000-4000-8000-000000000021'::uuid,
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'f1000000-0000-4000-8000-000000000001'::uuid,
  'practitioner',true,null,'{"basis":"capability_activation_validation"}'::jsonb,'{}'::jsonb
),
(
  'c1000000-0000-4000-8000-000000000022'::uuid,
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'b1000000-0000-4000-8000-000000000001'::uuid,
  'setup_sponsor',true,now(),'{"basis":"capability_activation_validation"}'::jsonb,'{}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,entitlement_kind,price_class,state,
  setup_price_cents,monthly_price_cents,commercial_basis,metadata
) values (
  'c1000000-0000-4000-8000-000000000031'::uuid,
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'c1000000-0000-4000-8000-000000000001'::uuid,
  1,'atlas_ledger','baseline_first','activated',300000,40000,
  '{"source":"capability_activation_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
);

insert into atlas.ledger_entitlement_bindings(
  id,implementation_case_id,ledger_entitlement_id,organization_id,organization_unit_id,
  bound_by_participant_id,state,bound_at,activated_at,binding_basis,metadata,ledger_id
) values (
  'c1000000-0000-4000-8000-000000000041'::uuid,
  'c1000000-0000-4000-8000-000000000011'::uuid,
  'c1000000-0000-4000-8000-000000000031'::uuid,
  'b4000000-0000-4000-8000-000000000001'::uuid,
  null,
  'c1000000-0000-4000-8000-000000000021'::uuid,
  'activated',now(),now(),
  '{"source":"capability_activation_validation"}'::jsonb,
  '{"validation_fixture":true}'::jsonb,
  'a2000000-0000-4000-8000-000000000001'::uuid
);
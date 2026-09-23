-- Clone-only fixture for Atlas Implementation Reality Position Promotion Command v1.
-- Requires the separately released Position preview family.

insert into auth.users(id) values
  ('f4700000-0000-4000-8000-000000000001'::uuid),
  ('f4700000-0000-4000-8000-000000000002'::uuid);

insert into atlas.implementation_practitioners(
  human_user_id,status,authorization_basis,metadata
) values (
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'active','{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_purchases(
  id,provider,provider_checkout_session_id,offer_key,starting_label,payment_option,
  purchase_state,currency,setup_contract_amount_cents,monthly_ledger_unit_price_cents,metadata
) values (
  'f4700000-0000-4000-8000-000000000101'::uuid,
  'stripe','cs_validation_position_command','validation_position_command',
  'Position Command Proof','pay_in_full','active','usd',0,0,'{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_cases(id,implementation_purchase_id,state,metadata)
values (
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000101'::uuid,
  'in_implementation','{"validationFixture":true}'::jsonb
);

insert into atlas.implementation_case_participants(
  id,implementation_case_id,human_user_id,relationship_kind,active,verified_at,basis,metadata
) values
(
  'f4700000-0000-4000-8000-000000000121'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000001'::uuid,
  'practitioner',true,now(),'{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
),
(
  'f4700000-0000-4000-8000-000000000122'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000002'::uuid,
  'setup_sponsor',true,now(),'{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values (
  'f4700000-0000-4000-8000-000000000201'::uuid,
  'position_command_org','Position Command Proof','active','{"validationFixture":true}'::jsonb,'ready'
);

insert into atlas.organization_units(
  id,organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata
) values (
  'f4700000-0000-4000-8000-000000000211'::uuid,
  'f4700000-0000-4000-8000-000000000201'::uuid,
  null,'operations','Operations','department','active','{"validationFixture":true}'::jsonb
);

insert into atlas.principals(id,user_id,stable_key,name,status,metadata)
values (
  'f4700000-0000-4000-8000-000000000221'::uuid,
  'f4700000-0000-4000-8000-000000000002'::uuid,
  'position_command_sponsor','Position Command Sponsor','active','{"validationFixture":true}'::jsonb
);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata)
values (
  'f4700000-0000-4000-8000-000000000231'::uuid,
  'positioncommandledger01','Position Command Ledger',null,'governed_reality','active',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'f4700000-0000-4000-8000-000000000232'::uuid,
  'f4700000-0000-4000-8000-000000000221'::uuid,
  'f4700000-0000-4000-8000-000000000231'::uuid,
  'root_governing','active','{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'f4700000-0000-4000-8000-000000000233'::uuid,
  'f4700000-0000-4000-8000-000000000231'::uuid,
  'f4700000-0000-4000-8000-000000000201'::uuid,
  'governing',true,'active','{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlements(
  id,implementation_case_id,source_purchase_id,entitlement_number,entitlement_kind,
  price_class,state,setup_price_cents,monthly_price_cents,commercial_basis,metadata
) values (
  'f4700000-0000-4000-8000-000000000241'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000101'::uuid,
  1,'atlas_ledger','baseline_first','bound',0,0,
  '{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb
);

insert into atlas.ledger_entitlement_bindings(
  id,implementation_case_id,ledger_entitlement_id,organization_id,organization_unit_id,
  bound_by_participant_id,state,activated_at,binding_basis,metadata,ledger_id
) values (
  'f4700000-0000-4000-8000-000000000242'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'f4700000-0000-4000-8000-000000000241'::uuid,
  'f4700000-0000-4000-8000-000000000201'::uuid,
  null,
  'f4700000-0000-4000-8000-000000000121'::uuid,
  'activated',now(),'{"validationFixture":true}'::jsonb,'{"validationFixture":true}'::jsonb,
  'f4700000-0000-4000-8000-000000000231'::uuid
);

insert into atlas.implementation_reality_candidates(
  id,implementation_case_id,contract_version,operation_id,origin_kind,literal_statement,
  subject_binding,object_binding,context_binding,semantic_payload,evidence_refs,
  establishment_basis,candidate_state,author_user_id,provenance
) values
(
  'f4700000-0000-4000-8000-000000000301'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'implementation_reality_candidate_v2','organization_position.establish',
  'manual_semantic_construction','Authored wording should not become canonical rendering.',
  '{"kind":"organization_position","label":"Field Lead","resolution":"proposed"}'::jsonb,
  '{"kind":"organization_unit","label":"Operations","resolution":"canonical","canonicalId":"f4700000-0000-4000-8000-000000000211"}'::jsonb,
  null,'{"positionKind":"operations"}'::jsonb,'["fixture:position:field-lead"]'::jsonb,
  '{"kind":"reconstruction_of_existing_reality"}'::jsonb,'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid,'{"validationFixture":true}'::jsonb
),
(
  'f4700000-0000-4000-8000-000000000302'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'implementation_reality_candidate_v2','organization_position.establish',
  'manual_semantic_construction','Missing kind position.',
  '{"kind":"organization_position","label":"Blocked Position","resolution":"proposed"}'::jsonb,
  '{"kind":"organization_unit","label":"Operations","resolution":"canonical","canonicalId":"f4700000-0000-4000-8000-000000000211"}'::jsonb,
  null,'{}'::jsonb,'[]'::jsonb,null,'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid,'{"validationFixture":true}'::jsonb
),
(
  'f4700000-0000-4000-8000-000000000303'::uuid,
  'f4700000-0000-4000-8000-000000000111'::uuid,
  'implementation_reality_candidate_v2','organization_position.establish',
  'manual_semantic_construction','Second candidate for same institutional role.',
  '{"kind":"organization_position","label":"Field Lead","resolution":"proposed"}'::jsonb,
  '{"kind":"organization_unit","label":"Operations","resolution":"canonical","canonicalId":"f4700000-0000-4000-8000-000000000211"}'::jsonb,
  null,'{"positionKind":"operations"}'::jsonb,'[]'::jsonb,null,'proposed',
  'f4700000-0000-4000-8000-000000000001'::uuid,'{"validationFixture":true}'::jsonb
);

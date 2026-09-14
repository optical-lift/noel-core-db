-- DML-only fixture for Atlas Runtime Institutional Custody Cutover v1.
-- Exercises canonical membership, reassigned employee identity, unresolved legacy owner identity,
-- row-aware Organization-Unit fallback, Company Work, and Correspondence without physical rehome.

insert into auth.users(id,email,raw_user_meta_data) values
('10000000-0000-4000-8000-000000000001'::uuid,'lex-fixture@example.invalid','{}'::jsonb),
('10000000-0000-4000-8000-000000000002'::uuid,'anna-fixture@example.invalid','{}'::jsonb);

insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('11000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,now(),now(),now()+interval '1 day'),
('11000000-0000-4000-8000-000000000002'::uuid,'10000000-0000-4000-8000-000000000002'::uuid,now(),now(),now()+interval '1 day');

insert into atlas.people(id,display_name,status,metadata) values
('12000000-0000-4000-8000-000000000001'::uuid,'Lex Fixture','active','{"validation_fixture":true}'::jsonb),
('12000000-0000-4000-8000-000000000002'::uuid,'Anna Fixture','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(person_id,auth_user_id,status,provenance) values
('12000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,'active','{"validation_fixture":true}'::jsonb),
('12000000-0000-4000-8000-000000000002'::uuid,'10000000-0000-4000-8000-000000000002'::uuid,'active','{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values
('20000000-0000-4000-8000-000000000001'::uuid,'a1b2c3d4e5f6478899aabbccddeeff01','Historical Mixed Carrier','active','{"validation_fixture":true}'::jsonb,'ready'),
('20000000-0000-4000-8000-000000000002'::uuid,'b1c2d3e4f5a6478899aabbccddeeff02','Elm Farm','active','{"validation_fixture":true,"canonical":true}'::jsonb,'ready'),
('20000000-0000-4000-8000-000000000003'::uuid,'c1d2e3f4a5b6478899aabbccddeeff03','Feast Guild','active','{"validation_fixture":true,"canonical":true,"cleanRoom":true}'::jsonb,'ready');

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values
('30000000-0000-4000-8000-000000000001'::uuid,'d1e2f3a4b5c6478899aabbccddeeff01','Historical Mixed Carrier','20000000-0000-4000-8000-000000000001'::uuid,'organization_governing','active','{"validation_fixture":true,"scope_state":"legacy_mixed_pending_adjudication"}'::jsonb),
('30000000-0000-4000-8000-000000000002'::uuid,'e1f2a3b4c5d6478899aabbccddeeff02','Elm Farm',null,'governed_reality','active','{"validation_fixture":true,"canonical":true}'::jsonb),
('30000000-0000-4000-8000-000000000003'::uuid,'f1a2b3c4d5e6478899aabbccddeeff03','Feast Guild',null,'governed_reality','active','{"validation_fixture":true,"canonical":true,"cleanRoom":true}'::jsonb);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values
('31000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,'20000000-0000-4000-8000-000000000001'::uuid,'governing',true,'active','{"fixture":true}'::jsonb,'{}'::jsonb),
('31000000-0000-4000-8000-000000000002'::uuid,'30000000-0000-4000-8000-000000000002'::uuid,'20000000-0000-4000-8000-000000000002'::uuid,'governing',true,'active','{"fixture":true}'::jsonb,'{}'::jsonb),
('31000000-0000-4000-8000-000000000003'::uuid,'30000000-0000-4000-8000-000000000003'::uuid,'20000000-0000-4000-8000-000000000003'::uuid,'governing',true,'active','{"fixture":true}'::jsonb,'{}'::jsonb);

insert into atlas.principals(id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id) values
('32000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,'20000000-0000-4000-8000-000000000001'::uuid,'lex_fixture','Lex Fixture','America/Chicago','active','{"validation_fixture":true}'::jsonb,'12000000-0000-4000-8000-000000000001'::uuid);

insert into atlas.principal_ledger_authorities(id,principal_id,ledger_id,authority_kind,status,basis,metadata) values
('33000000-0000-4000-8000-000000000001'::uuid,'32000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000001'::uuid,'root_governing','active','legacy_fixture','{}'::jsonb),
('33000000-0000-4000-8000-000000000002'::uuid,'32000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000002'::uuid,'root_governing','active','canonical_fixture','{}'::jsonb),
('33000000-0000-4000-8000-000000000003'::uuid,'32000000-0000-4000-8000-000000000001'::uuid,'30000000-0000-4000-8000-000000000003'::uuid,'root_governing','active','canonical_fixture','{}'::jsonb);

insert into atlas.institutional_custody_carriers(
  id,carrier_organization_id,carrier_ledger_id,carrier_kind,status,basis,metadata
) values (
  '34000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '30000000-0000-4000-8000-000000000001'::uuid,
  'legacy_mixed_scope','active','validation_fixture',
  '{"runtimeCutoverState":"pending","validation_fixture":true}'::jsonb
);

insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status,metadata) values (
  '40000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  'elm_fixture_unit','Elm','operating_business','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.identity_subjects(id,organization_id,state,creation_basis) values (
  '50000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  'active','{"validation_fixture":true,"person":"Anna"}'::jsonb
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,person_id,identity_subject_id,role,active,permissions
) values
('51000000-0000-4000-8000-000000000001'::uuid,'20000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,'12000000-0000-4000-8000-000000000001'::uuid,null,'owner',true,'{}'::jsonb),
('51000000-0000-4000-8000-000000000002'::uuid,'20000000-0000-4000-8000-000000000002'::uuid,'10000000-0000-4000-8000-000000000001'::uuid,'12000000-0000-4000-8000-000000000001'::uuid,null,'owner',true,'{}'::jsonb),
('51000000-0000-4000-8000-000000000003'::uuid,'20000000-0000-4000-8000-000000000001'::uuid,'10000000-0000-4000-8000-000000000002'::uuid,'12000000-0000-4000-8000-000000000002'::uuid,'50000000-0000-4000-8000-000000000001'::uuid,'member',true,'{}'::jsonb);

insert into atlas.organization_employee_seats(
  id,organization_id,organization_membership_id,identity_subject_id,seat_class,status,billing_state,billing_unit_price_cents,metadata
) values (
  '52000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '51000000-0000-4000-8000-000000000003'::uuid,
  '50000000-0000-4000-8000-000000000001'::uuid,
  'employee','active','active',700,'{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_member_credentials(
  id,organization_id,organization_membership_id,employee_seat_id,identity_subject_id,
  credential_kind,auth_user_id,status,issued_by_organization_id,provenance
) values (
  '53000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '51000000-0000-4000-8000-000000000003'::uuid,
  '52000000-0000-4000-8000-000000000001'::uuid,
  '50000000-0000-4000-8000-000000000001'::uuid,
  'auth_user','10000000-0000-4000-8000-000000000002'::uuid,'active',
  '20000000-0000-4000-8000-000000000001'::uuid,'{"validation_fixture":true}'::jsonb
);

insert into atlas.user_profiles(user_id,display_name,active,metadata,default_organization_id,onboarding_state) values
('10000000-0000-4000-8000-000000000001'::uuid,'Lex Fixture',true,'{"validation_fixture":true}'::jsonb,'20000000-0000-4000-8000-000000000001'::uuid,'ready'),
('10000000-0000-4000-8000-000000000002'::uuid,'Anna Fixture',false,'{"validation_fixture":true}'::jsonb,'20000000-0000-4000-8000-000000000001'::uuid,'ready');

insert into atlas.institutional_custody_adjudications(
  id,subject_schema,subject_table,subject_key,disposition,historical_organization_id,
  historical_ledger_id,canonical_organization_id,canonical_ledger_id,evidence_basis,evidence,metadata
) values
('60000000-0000-4000-8000-000000000001'::uuid,'atlas','organization_units','40000000-0000-4000-8000-000000000001','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'explicit_elm_unit','{}','{}'),
('60000000-0000-4000-8000-000000000002'::uuid,'atlas','organization_memberships','51000000-0000-4000-8000-000000000001','unresolved','20000000-0000-4000-8000-000000000001'::uuid,null,null,null,'legacy_mixed_remaining_unadjudicated','{}','{}'),
('60000000-0000-4000-8000-000000000003'::uuid,'atlas','organization_memberships','51000000-0000-4000-8000-000000000003','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'anna_is_sole_elm_employee','{}','{}'),
('60000000-0000-4000-8000-000000000004'::uuid,'atlas','organization_employee_seats','52000000-0000-4000-8000-000000000001','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'anna_is_sole_elm_employee','{}','{}'),
('60000000-0000-4000-8000-000000000005'::uuid,'atlas','organization_member_credentials','53000000-0000-4000-8000-000000000001','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'anna_is_sole_elm_employee','{}','{}'),
('60000000-0000-4000-8000-000000000006'::uuid,'atlas','user_profiles','10000000-0000-4000-8000-000000000001','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'current_elm_profile_default','{}','{}'),
('60000000-0000-4000-8000-000000000007'::uuid,'atlas','user_profiles','10000000-0000-4000-8000-000000000002','reassigned','20000000-0000-4000-8000-000000000001'::uuid,null,'20000000-0000-4000-8000-000000000002'::uuid,null,'current_elm_profile_default','{}','{}');

-- No direct work-item or endpoint adjudication on purpose: Stage 2 must derive from the explicit Elm Unit.
insert into atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
) values (
  'custody_cutover_fixture_contract','validation','manager_acceptance',true,'Stage 2 fixture','{"validation_fixture":true}'::jsonb
);

insert into atlas.work_items(
  id,organization_id,organization_unit_id,title,work_state,result_contract_key,stable_key,metadata
) values (
  '70000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'Elm Company Work fixture','open','custody_cutover_fixture_contract','custody_cutover_fixture_work',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.work_execution_results(
  id,organization_id,work_item_id,result_kind,result_contract_key,idempotency_key,payload,metadata
) values (
  '71000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '70000000-0000-4000-8000-000000000001'::uuid,
  'completed','custody_cutover_fixture_contract','custody-cutover-fixture-result','{}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoints(
  id,organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
) values (
  '80000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'email','hello-fixture@elm.invalid','hello-fixture@elm.invalid','Elm Fixture','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.connected_sources(
  id,custodian_organization_id,custodian_organization_unit_id,provider_key,provider_account_key,
  display_label,authorization_state,granted_scopes,capabilities,last_sync_at,metadata
) values (
  '81000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000001'::uuid,
  '40000000-0000-4000-8000-000000000001'::uuid,
  'email','hello-fixture@elm.invalid','Elm Fixture source','connected',
  array['communication.capture']::text[],
  '{"communicationCapture":true,"communicationSend":false}'::jsonb,
  '2026-09-14T00:00:00Z'::timestamptz,
  '{"validation_fixture":true,"communicationHistoryPolicy":{"mode":"from_now"}}'::jsonb
);

insert into atlas.communication_endpoint_source_bindings(
  id,communication_endpoint_id,connected_source_id,binding_role,binding_state,transport_metadata
) values (
  '82000000-0000-4000-8000-000000000001'::uuid,
  '80000000-0000-4000-8000-000000000001'::uuid,
  '81000000-0000-4000-8000-000000000001'::uuid,
  'receive','active','{"validation_fixture":true}'::jsonb
);

-- Clone-only identities and records for native Ledger seat-safe reader validation.
-- No real email, production identity, seat, commercial row, or authority is changed.
insert into auth.users(id,aud,role,created_at,updated_at) values
('e5100000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
('e5100000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now()),
('e5100000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now()),
('e5100000-0000-4000-8000-000000000004','authenticated','authenticated',now(),now());

insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('e5100000-0000-4000-8000-000000000011','e5100000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 day'),
('e5100000-0000-4000-8000-000000000012','e5100000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 day'),
('e5100000-0000-4000-8000-000000000013','e5100000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 day'),
('e5100000-0000-4000-8000-000000000014','e5100000-0000-4000-8000-000000000004',now(),now(),now()+interval '1 day');

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values
('e5100000-0000-4000-8000-000000000101','d0-validation-owner','person','Validation Owner','canonical'),
('e5100000-0000-4000-8000-000000000102','d0-validation-worker','person','Validation Worker','canonical'),
('e5100000-0000-4000-8000-000000000103','d0-validation-outsider','person','Validation Other-Ledger Member','canonical'),
('e5100000-0000-4000-8000-000000000104','d0-validation-no-seat','person','Validation No-Seat Person','canonical'),
('e5100000-0000-4000-8000-000000000201','d0-validation-business','business','Validation Business','canonical');

insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values
('e5100000-0000-4000-8000-000000000001','e5100000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000002','e5100000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000003','e5100000-0000-4000-8000-000000000103','active','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000004','e5100000-0000-4000-8000-000000000104','active','{"cloneFixture":true}');

insert into personal.atlases(person_entity_id,atlas_state,native) values
('e5100000-0000-4000-8000-000000000101','active',true),
('e5100000-0000-4000-8000-000000000102','active',true),
('e5100000-0000-4000-8000-000000000103','active',true),
('e5100000-0000-4000-8000-000000000104','active',true);

insert into atlas.people(id,display_name,status) values
('e5100000-0000-4000-8000-000000000101','Validation Owner','active'),
('e5100000-0000-4000-8000-000000000102','Validation Worker','active'),
('e5100000-0000-4000-8000-000000000103','Validation Other-Ledger Member','active'),
('e5100000-0000-4000-8000-000000000104','Validation No-Seat Person','active');

insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values
('e5100000-0000-4000-8000-000000000111','e5100000-0000-4000-8000-000000000001',
 'e5100000-0000-4000-8000-000000000101','d0-validation-owner-principal','Validation Owner','active');

insert into ledger.onboarding_cases(
  id,subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
  desired_ledger_name,onboarding_state,onboarding_basis
) values
('e5100000-0000-4000-8000-000000000301','e5100000-0000-4000-8000-000000000201',
 'e5100000-0000-4000-8000-000000000101','e5100000-0000-4000-8000-000000000101',
 'Validation Ledger A','ready_to_activate','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000302','e5100000-0000-4000-8000-000000000201',
 'e5100000-0000-4000-8000-000000000101','e5100000-0000-4000-8000-000000000101',
 'Validation Ledger B','ready_to_activate','{"cloneFixture":true}');

insert into ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state) values
('e5100000-0000-4000-8000-000000000401','e5100000-0000-4000-8000-000000000201',
 'e5100000-0000-4000-8000-000000000301','d0-validation-ledger-a','Validation Ledger A','active'),
('e5100000-0000-4000-8000-000000000402','e5100000-0000-4000-8000-000000000201',
 'e5100000-0000-4000-8000-000000000302','d0-validation-ledger-b','Validation Ledger B','active');

insert into ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis) values
('e5100000-0000-4000-8000-000000000501','e5100000-0000-4000-8000-000000000401',
 'e5100000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000502','e5100000-0000-4000-8000-000000000401',
 'e5100000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5100000-0000-4000-8000-000000000503','e5100000-0000-4000-8000-000000000402',
 'e5100000-0000-4000-8000-000000000103','active','{"cloneFixture":true}');

insert into atlas.ledgers(id,stable_key,name,ledger_kind,status) values
('e5100000-0000-4000-8000-000000000401','d0-validation-legacy-a','Validation Ledger A','governed_reality','active');

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis
) values
('e5100000-0000-4000-8000-000000000601',
 'e5100000-0000-4000-8000-000000000111',
 'e5100000-0000-4000-8000-000000000401',
 'root_governing','active','clone_validation_fixture');

insert into ledger.actions(id,ledger_id,action_kind,occurred_at,payload) values
('e5100000-0000-4000-8000-000000000701',
 'e5100000-0000-4000-8000-000000000401',
 'fixture_sensitive_action',now(),
 '{"title":"Owner-only validation movement","detail":"Not available through seat-only read"}');

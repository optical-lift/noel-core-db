-- Local disposable production-schema clone ONLY. Reuse the already signed-tested
-- synthetic original Person/Ledger/Work/Bed/Occurrence fixture; no live identities.
-- Synthetic original Work and Household fixture for disposable clone only.
-- Clone-only synthetic credentials, native Ledger and operating unit for C1 authorization verification.
-- DML-only disposable fixture; no real email, live user, seat, or Work is changed.
insert into auth.users(id,aud,role,created_at,updated_at) values
('e5200000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now()),
('e5200000-0000-4000-8000-000000000004','authenticated','authenticated',now(),now());

insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
('e5200000-0000-4000-8000-000000000011','e5200000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000012','e5200000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000013','e5200000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 day'),
('e5200000-0000-4000-8000-000000000014','e5200000-0000-4000-8000-000000000004',now(),now(),now()+interval '1 day');

insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values
('e5200000-0000-4000-8000-000000000101','c1-validation-owner','person','Validation Owner','canonical'),
('e5200000-0000-4000-8000-000000000102','c1-validation-worker','person','Validation Worker','canonical'),
('e5200000-0000-4000-8000-000000000103','c1-validation-outsider','person','Validation Other-Ledger Member','canonical'),
('e5200000-0000-4000-8000-000000000104','c1-validation-no-seat','person','Validation No-Seat Person','canonical'),
('e5200000-0000-4000-8000-000000000201','c1-validation-business','business','Validation Business','canonical');

insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values
('e5200000-0000-4000-8000-000000000001','e5200000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000002','e5200000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000003','e5200000-0000-4000-8000-000000000103','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000004','e5200000-0000-4000-8000-000000000104','active','{"cloneFixture":true}');

insert into atlas.people(id,display_name,status) values
('e5200000-0000-4000-8000-000000000101','Validation Owner','active'),
('e5200000-0000-4000-8000-000000000102','Validation Worker','active'),
('e5200000-0000-4000-8000-000000000103','Validation Other-Ledger Member','active'),
('e5200000-0000-4000-8000-000000000104','Validation No-Seat Person','active');

-- Align the legacy Atlas credential link with each synthetic reality binding.
-- Without it the principal compatibility trigger creates a second Person.
insert into atlas.person_auth_credentials(
  person_id,credential_kind,auth_user_id,status,provenance
) values
('e5200000-0000-4000-8000-000000000101','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000001','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000102','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000002','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000103','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000003','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000104','supabase_auth_user',
 'e5200000-0000-4000-8000-000000000004','active','{"cloneFixture":true}');

insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values
('e5200000-0000-4000-8000-000000000111','e5200000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000101','c1-validation-owner-principal','Validation Owner','active');

insert into ledger.onboarding_cases(
  id,subject_entity_id,requested_by_person_entity_id,practitioner_person_entity_id,
  desired_ledger_name,onboarding_state,onboarding_basis
) values
('e5200000-0000-4000-8000-000000000301','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000101','e5200000-0000-4000-8000-000000000101',
 'Validation Ledger A','ready_to_activate','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000302','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000101','e5200000-0000-4000-8000-000000000101',
 'Validation Ledger B','ready_to_activate','{"cloneFixture":true}');

insert into ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name,ledger_state) values
('e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000301','c1-validation-ledger-a','Validation Ledger A','active'),
('e5200000-0000-4000-8000-000000000402','e5200000-0000-4000-8000-000000000201',
 'e5200000-0000-4000-8000-000000000302','c1-validation-ledger-b','Validation Ledger B','active');

insert into ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis) values
('e5200000-0000-4000-8000-000000000501','e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000101','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000502','e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000102','active','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000503','e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000103','active','{"cloneFixture":true}');

-- Exact synthetic Atlas institution and operating unit for this Ledger.
insert into atlas.organizations(id,stable_key,name,onboarding_state)
values ('e5200000-0000-4000-8000-000000000801','c1-validation-organization',
        'Clone Operating Organization','ready');
insert into atlas.organization_units(id,organization_id,stable_key,name)
values ('e5200000-0000-4000-8000-000000000802','e5200000-0000-4000-8000-000000000801',
        'c1-validation-farm-unit','Clone Farm Unit');
insert into atlas.ledgers(id,stable_key,name,ledger_kind,status,organization_id) values
('e5200000-0000-4000-8000-000000000401','c1-validation-legacy-a','Validation Ledger A','governed_reality','active','e5200000-0000-4000-8000-000000000801');
insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,basis
) values ('e5200000-0000-4000-8000-000000000803','e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000801',
          'governing',true,'{"cloneFixture":true}');

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis
) values
('e5200000-0000-4000-8000-000000000601',
 'e5200000-0000-4000-8000-000000000111',
 'e5200000-0000-4000-8000-000000000401',
 'root_governing','active','clone_validation_fixture');

insert into ledger.actions(id,ledger_id,action_kind,occurred_at,payload) values
('e5200000-0000-4000-8000-000000000701',
 'e5200000-0000-4000-8000-000000000401',
 'fixture_sensitive_action',now(),
 '{"title":"Owner-only validation movement","detail":"Not available through seat-only read"}');

-- Same synthetic institution, original Work IDs and source-backed Ledger relevance.
insert into atlas.work_items(id,organization_id,title,work_state) values
('e5200000-0000-4000-8000-000000000901','e5200000-0000-4000-8000-000000000801','Clone work: clear walkways','open'),
('e5200000-0000-4000-8000-000000000902','e5200000-0000-4000-8000-000000000801','Clone work: replacement sprayer arrives','open'),
('e5200000-0000-4000-8000-000000000903','e5200000-0000-4000-8000-000000000801','Clone work: alternate preparation','open');

insert into atlas.company_work_native_ledger_relevance(
  organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
  attestation_source_ref,attestation_reason,established_by_person_id)
values
('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000901','e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:original-work-901','Disposable source of Work A from exact Ledger','e5200000-0000-4000-8000-000000000101'),
('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000902','e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:original-work-902','Disposable source of Work B from exact Ledger','e5200000-0000-4000-8000-000000000101'),
('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000903','e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:original-work-903','Disposable source of Work C from exact Ledger','e5200000-0000-4000-8000-000000000101');

-- Two independent accepted native Person scopes: a genuine target and a prior
-- receiver. A different native Ledger's Person has no right to transfer A.
insert into ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis)
values('e5200000-0000-4000-8000-000000000504',
'e5200000-0000-4000-8000-000000000401',
'e5200000-0000-4000-8000-000000000104','active','{"cloneFixture":true}');

insert into personal.atlases(person_entity_id,atlas_state,native)
values
('e5200000-0000-4000-8000-000000000101','active',true),
('e5200000-0000-4000-8000-000000000102','active',true),
('e5200000-0000-4000-8000-000000000103','active',true),
('e5200000-0000-4000-8000-000000000104','active',true);

insert into atlas.company_work_standing_assignment_scopes(
 id,organization_id,ledger_id,worker_person_id,worker_membership_id,
 proposed_by_person_id,proposal_terms,scope_state,accepted_at,accepted_by_person_id,
 coverage_mode
) values (
 'e5200000-0000-4000-8000-000000000a01',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000102',null,
 'e5200000-0000-4000-8000-000000000101',
 'Clone-only accepted ordinary Work responsibility for one connected Person.',
 'active',now(),'e5200000-0000-4000-8000-000000000102','ledger_all_work'
),(
 'e5200000-0000-4000-8000-000000000a02',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000401',
 'e5200000-0000-4000-8000-000000000104',null,
 'e5200000-0000-4000-8000-000000000101',
 'Clone-only accepted prior Work responsibility for another connected Person.',
 'active',now(),'e5200000-0000-4000-8000-000000000104','ledger_all_work'
),(
 'e5200000-0000-4000-8000-000000000a03',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000402',
 'e5200000-0000-4000-8000-000000000103',null,
 'e5200000-0000-4000-8000-000000000101',
 'Clone-only active scope for a different Ledger; cannot authorize Work in Ledger A.',
 'active',now(),'e5200000-0000-4000-8000-000000000103','ledger_all_work'
);

insert into atlas.work_result_contract_policies(
 contract_key,source_domain,acceptance_mode,active,description
) values(
 'ordinary_company_work_worker_attestation_v1','organization',
 'worker_attestation',true,'Clone-only result contract'
);

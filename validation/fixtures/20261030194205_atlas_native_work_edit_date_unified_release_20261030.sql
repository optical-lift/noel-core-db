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

-- Universal original Work acceptance additions: synthetic Bed 3/4, one withheld
-- Bed, and a Household Laundry Subject. These are not the real Elm records.
insert into atlas.farms(id,stable_key,name,organization_id,organization_unit_id,metadata)
values('e5200000-0000-4000-8000-000000000b01',
'clone-universal-garden','Synthetic Bed Test Farm',
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000802','{"cloneFixture":true}');

insert into atlas.growing_objects(id,farm_id,stable_key,label,object_type,metadata) values
('e5200000-0000-4000-8000-000000000b03','e5200000-0000-4000-8000-000000000b01',
 'clone-upick-bed-3','Synthetic U-Pick Bed 3','bed','{"cloneFixture":true,"privateNote":"worker-must-not-see-whole-bed-registry"}'),
('e5200000-0000-4000-8000-000000000b04','e5200000-0000-4000-8000-000000000b01',
 'clone-upick-bed-4','Synthetic U-Pick Bed 4','bed','{"cloneFixture":true}'),
('e5200000-0000-4000-8000-000000000b05','e5200000-0000-4000-8000-000000000b01',
 'clone-withheld-bed-5','Synthetic withheld Bed 5','bed','{"sourceOwnerOnly":true}');

insert into atlas.work_items(
id,organization_id,title,work_state,source_object_type,
source_object_id,result_contract_key,stable_key,metadata
) values (
'e5200000-0000-4000-8000-000000000b10',
'e5200000-0000-4000-8000-000000000801',
'Measure and stake Synthetic U-Pick Beds 3 + 4','open',
'legacy_task_slice','e5200000-0000-4000-8000-000000000901',
'ordinary_company_work_manager_acceptance_v1',
'clone-original-beds-3-and-4','{"cloneFixture":true,"originalCombinedWork":true}'
);

insert into atlas.company_work_native_ledger_relevance(
organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
attestation_source_ref,attestation_reason,established_by_person_id
) values (
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000b10',
'e5200000-0000-4000-8000-000000000401',
'serves_purpose','owner_attested','clone:bed-3-4-original',
'The synthetic original Work serves this governing Ledger',
'e5200000-0000-4000-8000-000000000101'
);

insert into atlas.households(id,principal_id,stable_key,name,timezone)
values(
'e5200000-0000-4000-8000-000000000c01',
'e5200000-0000-4000-8000-000000000111',
'clone-household-laundry','Synthetic Laundry Household','America/Chicago'
);

insert into atlas.household_members(
id,household_id,user_id,display_name,active,person_id
) values (
'e5200000-0000-4000-8000-000000000c02',
'e5200000-0000-4000-8000-000000000c01',
'e5200000-0000-4000-8000-000000000002',
'Synthetic Worker',true,'e5200000-0000-4000-8000-000000000102'
);

insert into atlas.world_kernel_definitions(
kernel_key,version,scope_kind,title,definition,active
) values (
'household.laundry',1,'household','Laundry',
'{"cloneFixture":true,"scope":"household","stateChange":"wash_started"}',true
);

insert into atlas.household_kernel_instances(
id,household_id,kernel_key,kernel_version,state,configuration,metadata
) values (
'e5200000-0000-4000-8000-000000000c03',
'e5200000-0000-4000-8000-000000000c01',
'household.laundry',1,'active',
'{"selectedModelKey":"laundry.basic","expectedMinutes":45}',
'{"cloneFixture":true}'
);

-- Production shape is dumped without policy rows; seed just the admitted
-- existing ordinary Work contracts for local clone acceptance.
insert into atlas.work_result_contract_policies(
 contract_key,source_domain,acceptance_mode,active,description
) values
('ordinary_company_work_manager_acceptance_v1','organization','manager_acceptance',true,
 'Fictional manager decision path for independent Bed Work'),
('ordinary_company_work_worker_attestation_v1','organization','worker_attestation',true,
 'Fictional responsible Person attests physical completion')
;

-- A signed connected Person can still inherit an older farm_hand
-- membership. This fixture forces inherited readers to honor SOURCE-level
-- whole-farm disclosure even after exact Bed 3 identity was granted.
insert into atlas.farm_memberships(
 id,user_id,farm_id,role,worker_key,active,permissions
) values(
 'e5200000-0000-4000-8000-000000000b06',
 'e5200000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000b01',
 'farm_hand','clone-worker-with-legacy-farm-access',true,
 '{}'::jsonb
);

-- Original Event signed regression fixture, separate canonical Event IDs.
-- DISPOSABLE DATABASE CLONE ONLY. Never apply synthetic principals to production.
-- All identities, addresses, labels, and occurrences are artificial.

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES
 ('f5210000-0000-4000-8000-000000000001','atlas-date-proof-org-f521','organization','Synthetic Date Institution'),
 ('f5210000-0000-4000-8000-000000000002','atlas-date-proof-included-f521','person','Synthetic Authorized Person'),
 ('f5210000-0000-4000-8000-000000000003','atlas-date-proof-outsider-f521','person','Synthetic Unconnected Person'),
 ('f5210000-0000-4000-8000-000000000004','atlas-date-proof-governor-f521','person','Synthetic Root Governor');

INSERT INTO atlas.organizations(id,stable_key,name)
VALUES ('f5210000-0000-4000-8000-000000000010','atlas-date-proof-organization-f521','Synthetic Date Institution');

INSERT INTO atlas.farms(id,stable_key,name,organization_id)
VALUES ('f5210000-0000-4000-8000-000000000011','atlas-date-proof-farm-f521','Synthetic Farm',
  'f5210000-0000-4000-8000-000000000010');

INSERT INTO atlas.community_programs(id,farm_id,stable_key,title)
VALUES ('f5210000-0000-4000-8000-000000000012','f5210000-0000-4000-8000-000000000011',
  'atlas-date-proof-program-f521','Synthetic Program');

INSERT INTO ledger.onboarding_cases(id,subject_entity_id,practitioner_person_entity_id,desired_ledger_name,onboarding_state)
VALUES ('f5210000-0000-4000-8000-000000000013','f5210000-0000-4000-8000-000000000001',
  'f5210000-0000-4000-8000-000000000002','Synthetic Date Ledger','ready_to_activate');

INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000001',
  'f5210000-0000-4000-8000-000000000013','atlas-date-proof-ledger-f521','Synthetic Date Ledger');

INSERT INTO atlas.ledgers(id,stable_key,organization_id,name)
VALUES ('f5210000-0000-4000-8000-000000000014','atlas-date-proof-ledger-f521',
  'f5210000-0000-4000-8000-000000000010','Synthetic Date Ledger');

INSERT INTO atlas.ledger_organization_participations(ledger_id,organization_id,participation_kind,status)
VALUES ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000010','operating','active');

-- Two independent occurrences have the SAME local date; third is canonically
-- dated later but its operational overlay asserts the requested local date.
INSERT INTO local_intel.occurrences(id,stable_key,title,occurrence_type,start_at,end_at,status)
VALUES
 ('f5210000-0000-4000-8000-000000000101','atlas-date-proof-occurrence-a-f521',
  'Synthetic Harvest Gathering','community_event','2030-10-30 23:00+00','2030-10-31 01:00+00','scheduled'),
 ('f5210000-0000-4000-8000-000000000102','atlas-date-proof-occurrence-b-f521',
  'Synthetic Early Movement','community_event','2030-10-30 13:00+00','2030-10-30 14:00+00','scheduled'),
 ('f5210000-0000-4000-8000-000000000103','atlas-date-proof-occurrence-c-f521',
  'Synthetic Later Gathering','community_event','2030-11-01 16:00+00',NULL,'planned');

INSERT INTO ledger.occurrence_calendar_bindings(ledger_id,occurrence_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000101','active'),
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000102','active'),
 ('f5210000-0000-4000-8000-000000000014','f5210000-0000-4000-8000-000000000103','active');

INSERT INTO atlas.organization_occurrence_bindings(id,organization_id,occurrence_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000201','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000101','active'),
 ('f5210000-0000-4000-8000-000000000202','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000102','active'),
 ('f5210000-0000-4000-8000-000000000203','f5210000-0000-4000-8000-000000000010',
   'f5210000-0000-4000-8000-000000000103','active');

INSERT INTO atlas.community_events(
 id,farm_id,program_id,stable_key,title,event_kind,event_date,
 start_local_time,end_local_time,timezone_name,status,occurrence_binding_id)
VALUES
 ('f5210000-0000-4000-8000-000000000301',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-a-f521','Synthetic Bonfire Evening','community_event',
  '2030-10-30','16:00','20:00','America/Chicago','planned',
  'f5210000-0000-4000-8000-000000000201'),
 ('f5210000-0000-4000-8000-000000000302',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-b-f521','Synthetic Early Movement','community_event',
  '2030-10-30','08:00','09:00','America/Chicago','scheduled',
  'f5210000-0000-4000-8000-000000000202'),
 ('f5210000-0000-4000-8000-000000000303',
  'f5210000-0000-4000-8000-000000000011','f5210000-0000-4000-8000-000000000012',
  'atlas-date-proof-community-c-f521','Synthetic Later Gathering','community_event',
  '2030-10-30','11:00','12:00','America/Chicago','planned',
  'f5210000-0000-4000-8000-000000000203');

-- Same canonical Occurrence, but this extra Organization assertion is owner-only.
-- An authenticated ordinary Ledger seat must not see its title or its existence.
INSERT INTO atlas.community_events(
 id,farm_id,program_id,stable_key,title,event_kind,event_date,
 start_local_time,end_local_time,timezone_name,status,visibility_scope,occurrence_binding_id)
VALUES (
 'f5210000-0000-4000-8000-000000000304',
 'f5210000-0000-4000-8000-000000000011',
 'f5210000-0000-4000-8000-000000000012',
 'atlas-date-proof-restricted-a-f521','Synthetic Restricted Owner Planning',
 'community_event','2030-10-30','14:00','15:00','America/Chicago','planned','owner',
 'f5210000-0000-4000-8000-000000000201');

INSERT INTO auth.users(id,instance_id,aud,role,email,created_at,updated_at)
VALUES
 ('f5210000-0000-4000-8000-000000000401','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-1@example.invalid',now(),now()),
 ('f5210000-0000-4000-8000-000000000402','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-2@example.invalid',now(),now()),
 ('f5210000-0000-4000-8000-000000000403','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','atlas-date-proof-3@example.invalid',now(),now());

INSERT INTO auth.sessions(id,user_id,created_at,updated_at)
VALUES
 ('f5210000-0000-4000-8000-000000000411','f5210000-0000-4000-8000-000000000401',now(),now()),
 ('f5210000-0000-4000-8000-000000000412','f5210000-0000-4000-8000-000000000402',now(),now()),
 ('f5210000-0000-4000-8000-000000000413','f5210000-0000-4000-8000-000000000403',now(),now());

INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state)
VALUES
 ('f5210000-0000-4000-8000-000000000401','f5210000-0000-4000-8000-000000000002','active'),
 ('f5210000-0000-4000-8000-000000000402','f5210000-0000-4000-8000-000000000003','active'),
 ('f5210000-0000-4000-8000-000000000403','f5210000-0000-4000-8000-000000000004','active');

-- Identity admission can establish a Personal Atlas first.
-- Insert a synthetic native Atlas only for a Person without one.
-- This remains ordinary fixture data setup, not schema/privilege logic.
INSERT INTO personal.atlases(person_entity_id,atlas_state,native)
SELECT seeded.person_entity_id, 'active', true
FROM (VALUES
 ('f5210000-0000-4000-8000-000000000002'::uuid),
 ('f5210000-0000-4000-8000-000000000003'::uuid),
 ('f5210000-0000-4000-8000-000000000004'::uuid)
) AS seeded(person_entity_id)
WHERE NOT EXISTS (
 SELECT 1 FROM personal.atlases existing
 WHERE existing.person_entity_id=seeded.person_entity_id
);

-- Only first Person gets the Ledger relationship; second has valid synthetic
-- session and Atlas, but is NOT authorized to read the Event.
INSERT INTO ledger.seats(ledger_id,person_entity_id,seat_state)
VALUES
 ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000002','active'),
 ('f5210000-0000-4000-8000-000000000014',
  'f5210000-0000-4000-8000-000000000004','active');

-- An unrelated native participant is the ordinary member; the third Person
-- has the *distinct* root_governing authority over this exact Ledger.
-- stable_key is GENERATED ALWAYS as 'person:' || id by the canonical
-- schema. Supply only the source-owned person identity and display name.
INSERT INTO atlas.people(id,display_name)
SELECT 'f5210000-0000-4000-8000-000000000004'::uuid,
  'Synthetic Root Governor'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.people p
 WHERE p.id='f5210000-0000-4000-8000-000000000004'::uuid
);

-- The canonical reality.auth_person_bindings identity does not itself
-- populate legacy atlas.person_auth_credentials. The Principal compatibility
-- trigger resolves that separate bridge and otherwise allocates a second Person.
-- Preserve ONE exact synthetic Person across both already-governed relations.
INSERT INTO atlas.person_auth_credentials(
  person_id,credential_kind,auth_user_id,status,provenance
)
SELECT 'f5210000-0000-4000-8000-000000000004'::uuid,
       'supabase_auth_user',
       'f5210000-0000-4000-8000-000000000403'::uuid,
       'active',
       '{"basis":"disposable_schedule_preflight_canonical_compatibility"}'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM atlas.person_auth_credentials c
  WHERE c.auth_user_id='f5210000-0000-4000-8000-000000000403'::uuid
);

INSERT INTO atlas.principals(user_id,person_id,stable_key,name)
SELECT 'f5210000-0000-4000-8000-000000000403'::uuid,
  'f5210000-0000-4000-8000-000000000004'::uuid,
  'atlas-date-proof-root-principal-f521','Synthetic Root Governor'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.principals p
 WHERE p.user_id='f5210000-0000-4000-8000-000000000403'::uuid
);

INSERT INTO atlas.principal_ledger_authorities(
 principal_id,ledger_id,authority_kind,status,basis
)
SELECT p.id,'f5210000-0000-4000-8000-000000000014'::uuid,
 'root_governing','active','disposable schedule-correction root authorization proof'
FROM atlas.principals p
WHERE p.person_id='f5210000-0000-4000-8000-000000000004'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM atlas.principal_ledger_authorities a
    WHERE a.principal_id=p.id AND
      a.ledger_id='f5210000-0000-4000-8000-000000000014'::uuid
      AND a.status='active'
  );

-- This confirmed Resource claim proves root-only impact visibility while
-- an ordinary authenticated Ledger Person must see NULL, not zero.
INSERT INTO reality.resources(id,owner_entity_id,stable_key,label,resource_kind,
  capacity_mode,timezone_name)
VALUES (
 'f5210000-0000-4000-8000-000000000601',
 'f5210000-0000-4000-8000-000000000001',
 'atlas-date-proof-resource-f521','Synthetic Shared Space',
 'space','shared','America/Chicago');

INSERT INTO ledger.occurrence_resource_claims(
 ledger_id,occurrence_id,resource_id,claim_kind,claim_state,
 starts_at,ends_at,provenance
)
VALUES (
 'f5210000-0000-4000-8000-000000000014',
 'f5210000-0000-4000-8000-000000000101',
 'f5210000-0000-4000-8000-000000000601',
 'shared','confirmed',
 '2030-10-30 21:00+00','2030-10-31 01:00+00',
 '{"source":"disposable_schedule_preflight_fixture"}'::jsonb);

-- This synthetic canonical Event has richer public details than its linked
-- program carrier. Retiming must keep those details and exact subject ID.
UPDATE local_intel.occurrences
SET metadata='{"publicEventLocalTime":"6:00 PM–8:00 PM","vendorInvitationScope":"synthetic visitors","candyStandard":"dye-free","outreachStatus":"invitation planned","keepMe":"original"}'::jsonb
WHERE id='f5210000-0000-4000-8000-000000000101'::uuid;

-- A separate canonical Event on the same date stays a separate identity.
-- Existing confirmed site hold is 4-8 PM, independent from public schedule.

-- Candidate-specific original decomposition is composed onto the existing
-- DISPOSABLE synthetic original Work fixture. No live data, people or email.
INSERT INTO atlas.work_items(
 id,organization_id,title,work_state,source_object_type,source_object_id,result_contract_key,metadata
) VALUES
 ('e5200000-0000-4000-8000-000000000971','e5200000-0000-4000-8000-000000000801','Synthetic original split Work — owner','open',
  'work_decomposition','e5200000-0000-4000-8000-000000000901','ordinary_company_work_worker_attestation_v1',
  '{"originalParentWorkItemId":"e5200000-0000-4000-8000-000000000901","cloneFixture":true}'::jsonb),
 ('e5200000-0000-4000-8000-000000000972','e5200000-0000-4000-8000-000000000801','Synthetic original split Work — worker','open',
  'work_decomposition','e5200000-0000-4000-8000-000000000901','ordinary_company_work_worker_attestation_v1',
  '{"originalParentWorkItemId":"e5200000-0000-4000-8000-000000000901","cloneFixture":true}'::jsonb);
INSERT INTO atlas.work_decomposition_groups(
 id,parent_work_item_id,authorized_ledger_id,action_id,source_fingerprint,
 decision_reason,decided_by_person_id
) VALUES (
 'e5200000-0000-4000-8000-000000000951','e5200000-0000-4000-8000-000000000901','e5200000-0000-4000-8000-000000000401','e5200000-0000-4000-8000-000000000953',
 'clone-native-ledger-self-assignment-split','Two fictional original Work parts for signed responsibility proof.',
 'e5200000-0000-4000-8000-000000000101');
INSERT INTO atlas.work_decomposition_members(
 id,group_id,child_work_item_id,part_ordinal,subject_domain,subject_kind,subject_id
) VALUES
 ('e5200000-0000-4000-8000-000000000961','e5200000-0000-4000-8000-000000000951','e5200000-0000-4000-8000-000000000971',1,'atlas','test_subject','e5200000-0000-4000-8000-000000000901'),
 ('e5200000-0000-4000-8000-000000000962','e5200000-0000-4000-8000-000000000951','e5200000-0000-4000-8000-000000000972',2,'atlas','test_subject','e5200000-0000-4000-8000-000000000902');
INSERT INTO atlas.company_work_native_ledger_relevance(
 organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
 attestation_source_ref,attestation_reason,established_by_person_id
) VALUES
 ('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000971','e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:self-assignment:971',
 'Fictional Work identity and native Ledger scope','e5200000-0000-4000-8000-000000000101'),
 ('e5200000-0000-4000-8000-000000000801','e5200000-0000-4000-8000-000000000972','e5200000-0000-4000-8000-000000000401',
 'serves_purpose','owner_attested','clone:self-assignment:972',
 'Fictional Work identity and native Ledger scope','e5200000-0000-4000-8000-000000000101');
-- Additional fictional records for native editing/date/status signed proof.
-- Applied ONLY after the existing C1 synthetic Person/Ledger fixture on local clone.
UPDATE atlas.work_items SET source_object_type='ledger_occurrence_shared_work',
  title='Synthetic event refreshments', instructions='Original synthetic instructions'
WHERE id='e5200000-0000-4000-8000-000000000901'::uuid;
UPDATE atlas.work_items SET source_object_type='ledger_connected_direct_task',
  title='Synthetic worker setup', instructions='Worker-visible synthetic task'
WHERE id='e5200000-0000-4000-8000-000000000902'::uuid;
INSERT INTO atlas.organization_memberships
  (id,organization_id,user_id,person_id,role,active)
VALUES
 ('e5200000-0000-4000-8000-000000000981'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000001'::uuid,
  'e5200000-0000-4000-8000-000000000101'::uuid,'owner',true),
 ('e5200000-0000-4000-8000-000000000982'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000002'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,'member',true);
-- Source-backed offer to the original fictional Work and exact native Ledger.
-- The fixture seeds an offered relationship, then records one accepted uptake.
-- No real Person, consent, membership, or production Work is touched.
INSERT INTO atlas.company_work_initial_responsibility_offers
  (id,organization_id,work_item_id,ledger_id,offered_by_person_id,
   target_person_id,reason,offer_state)
VALUES
 ('e5200000-0000-4000-8000-000000000985'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000902'::uuid,
  'e5200000-0000-4000-8000-000000000401'::uuid,
  'e5200000-0000-4000-8000-000000000101'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'Synthetic offered Work uptake in disposable clone','offered');
INSERT INTO atlas.work_allocations
 (id,organization_id,work_item_id,assignee_canonical_person_id,
  allocation_role,state,establishment_basis_kind,establishment_basis)
VALUES
 ('e5200000-0000-4000-8000-000000000983'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'e5200000-0000-4000-8000-000000000902'::uuid,
  'e5200000-0000-4000-8000-000000000102'::uuid,
  'responsible','active','person_connection_receiver_uptake',
  '{"contractVersion":"exact_work_responsibility_establishment_v2",
    "basisKind":"person_connection_receiver_uptake",
    "organizationId":"e5200000-0000-4000-8000-000000000801",
    "workItemId":"e5200000-0000-4000-8000-000000000902",
    "targetPersonId":"e5200000-0000-4000-8000-000000000102",
    "nativeLedgerId":"e5200000-0000-4000-8000-000000000401",
    "offerId":"e5200000-0000-4000-8000-000000000985",
    "uptakeKind":"recipient_self_accepted"}'::jsonb);
UPDATE atlas.company_work_initial_responsibility_offers
  SET offer_state='accepted', resolved_at=now(),
      accepted_allocation_id='e5200000-0000-4000-8000-000000000983'::uuid
WHERE id='e5200000-0000-4000-8000-000000000985'::uuid;

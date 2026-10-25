-- DML-only; synthetic users in an isolated local clone.
INSERT INTO auth.users(id,aud,role,created_at,updated_at,is_anonymous)
VALUES
('f1900000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now(),false);

INSERT INTO atlas.principals(id,user_id,stable_key,name,status)
VALUES ('f1900000-0000-4000-8000-000000000202',
'f1900000-0000-4000-8000-000000000002',
'fictional-non-practitioner-20261025','Fictional Personal Principal','active');

INSERT INTO atlas.implementation_practitioners(human_user_id,status,authorization_basis)
VALUES ('f1900000-0000-4000-8000-000000000001','active',
jsonb_build_object('synthetic','signed-discovery-fixture'));

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
SELECT p.person_id,'fictional-inventory-person-'||p.id::text,'person',p.name
FROM atlas.principals p WHERE p.id='f1900000-0000-4000-8000-000000000202';

INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES
('f1900000-0000-4000-8000-000000000499','fictional-discovery-company-a','business','Fictional Company A'),
('f1900000-0000-4000-8000-000000000498','fictional-discovery-company-b','business','Fictional Company B');

INSERT INTO ledger.onboarding_cases(
 id,subject_entity_id,desired_ledger_name,onboarding_state,practitioner_person_entity_id)
SELECT records.case_id,records.subject_id,records.name,
 'ready_to_activate',p.person_id
FROM (VALUES
('f1900000-0000-4000-8000-000000000481'::uuid,'f1900000-0000-4000-8000-000000000499'::uuid,'Fictional A Ledger'),
('f1900000-0000-4000-8000-000000000482'::uuid,'f1900000-0000-4000-8000-000000000498'::uuid,'Fictional B Ledger')
) AS records(case_id,subject_id,name)
CROSS JOIN atlas.principals p
WHERE p.id='f1900000-0000-4000-8000-000000000202';

INSERT INTO atlas.ledgers(id,stable_key,name)
VALUES
('f1900000-0000-4000-8000-000000000491','fictional-a-ledger-20261025','Fictional A Ledger'),
('f1900000-0000-4000-8000-000000000492','fictional-b-ledger-20261025','Fictional B Ledger');

INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES
('f1900000-0000-4000-8000-000000000491','f1900000-0000-4000-8000-000000000499','f1900000-0000-4000-8000-000000000481','fictional-a-ledger-20261025','Fictional A Ledger'),
('f1900000-0000-4000-8000-000000000492','f1900000-0000-4000-8000-000000000498','f1900000-0000-4000-8000-000000000482','fictional-b-ledger-20261025','Fictional B Ledger');

INSERT INTO foundry.events(workspace_id,sequence,event_id,event_type,envelope,inserted_at)
VALUES
('FW-FICTIONAL-INVENTORY-A',1,'fictional-inventory-a-1','WORKSPACE_CREATED',
jsonb_build_object('provisional_subject',jsonb_build_object('subject_ref',
'reality.entities:f1900000-0000-4000-8000-000000000499')),
'2026-10-10'::timestamptz),
('FW-FICTIONAL-INVENTORY-A',2,'fictional-inventory-a-2','OBSERVATION_STAGED',
jsonb_build_object('original_private_source','synthetic confidential example'),
'2026-10-11'::timestamptz),
('FW-FICTIONAL-INVENTORY-B',1,'fictional-inventory-b-1','WORKSPACE_CREATED',
jsonb_build_object('payload',jsonb_build_object('subject',jsonb_build_object('entity_id',
'f1900000-0000-4000-8000-000000000498'),
'existing_ledger_id','f1900000-0000-4000-8000-000000000492')),
'2026-10-11'::timestamptz);

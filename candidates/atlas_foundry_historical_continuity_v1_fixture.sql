-- Fictional source only. Pre-migration setup on a disposable schema clone.
-- Supports real local GoTrue owner/other/unbound sessions, never production.
INSERT INTO auth.users(id,aud,role,created_at,updated_at,is_anonymous)
VALUES
('f1900000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now(),false);
INSERT INTO atlas.principals(id,user_id,stable_key,name,status)
VALUES
('f1900000-0000-4000-8000-000000000201','f1900000-0000-4000-8000-000000000001','foundry-history-fixture-owner','Fictional source owner','active'),
('f1900000-0000-4000-8000-000000000202','f1900000-0000-4000-8000-000000000002','foundry-history-fixture-other','Fictional shared-Ledger governor','active');
INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
SELECT p.person_id, 'history-fixture-person-'||p.id::text,'person',p.name
FROM atlas.principals p
WHERE p.user_id IN ('f1900000-0000-4000-8000-000000000001',
'f1900000-0000-4000-8000-000000000002');
INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES('f1900000-0000-4000-8000-000000000499',
'foundry-history-fixture-subject','organization','Fictional source subject');
INSERT INTO ledger.onboarding_cases(id,subject_entity_id,desired_ledger_name,
 practitioner_person_entity_id,onboarding_state)
SELECT 'f1900000-0000-4000-8000-000000000481',
 'f1900000-0000-4000-8000-000000000499','Fictional source Ledger one',p.person_id,
 'ready_to_activate'
FROM atlas.principals p WHERE p.id='f1900000-0000-4000-8000-000000000201';
INSERT INTO ledger.onboarding_cases(id,subject_entity_id,desired_ledger_name,
 practitioner_person_entity_id,onboarding_state)
SELECT 'f1900000-0000-4000-8000-000000000482',
 'f1900000-0000-4000-8000-000000000499','Fictional source Ledger two',p.person_id,
 'ready_to_activate'
FROM atlas.principals p WHERE p.id='f1900000-0000-4000-8000-000000000201';
INSERT INTO atlas.ledgers(id,stable_key,name)
VALUES
('f1900000-0000-4000-8000-000000000491','foundry-history-fixture-ledger-1','Fictional source Ledger one'),
('f1900000-0000-4000-8000-000000000492','foundry-history-fixture-ledger-2','Fictional source Ledger two');
INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES
('f1900000-0000-4000-8000-000000000491','f1900000-0000-4000-8000-000000000499',
'f1900000-0000-4000-8000-000000000481','foundry-history-fixture-ledger-1','Fictional source Ledger one'),
('f1900000-0000-4000-8000-000000000492','f1900000-0000-4000-8000-000000000499',
'f1900000-0000-4000-8000-000000000482','foundry-history-fixture-ledger-2','Fictional source Ledger two');
INSERT INTO atlas.principal_ledger_authorities(principal_id,ledger_id,basis)
VALUES
('f1900000-0000-4000-8000-000000000201','f1900000-0000-4000-8000-000000000491','Fictional exclusive root governance'),
('f1900000-0000-4000-8000-000000000201','f1900000-0000-4000-8000-000000000492','Fictional shared root governance'),
('f1900000-0000-4000-8000-000000000202','f1900000-0000-4000-8000-000000000492','Fictional shared root governance');
INSERT INTO atlas.implementation_cases(state,case_origin,personal_subject_person_entity_id)
SELECT 'in_implementation','personal_atlas',p.person_id
FROM atlas.principals p WHERE p.id='f1900000-0000-4000-8000-000000000201';
INSERT INTO foundry.events(workspace_id,sequence,event_id,event_type,envelope,inserted_at)
VALUES
('FW-FICTIONAL-001',1,'fictional-old-event-1','WORKSPACE_CREATED',
 jsonb_build_object('workspace_id','FW-FICTIONAL-001',
 'provisional_subject',jsonb_build_object('label','Fictional source subject',
 'subject_ref','reality.entities:f1900000-0000-4000-8000-000000000499'),
 'provisional_field','Fictional operations and prior history','protocol_version','0.1'),
 '2026-10-10'::timestamptz),
('FW-FICTIONAL-001',2,'fictional-old-event-2','ATLAS_EVIDENCE_INVENTORIED',
 jsonb_build_object('workspace_id','FW-FICTIONAL-001',
 'root_facts',jsonb_build_object('ledgers',jsonb_build_array(
 jsonb_build_object('id','f1900000-0000-4000-8000-000000000491'),
 jsonb_build_object('id','f1900000-0000-4000-8000-000000000492'))),
 'protocol_version','0.1'),'2026-10-10'::timestamptz);

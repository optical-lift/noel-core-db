-- DML-only synthetic users for actual signed GoTrue + PostgREST local test.
-- This file is applied exclusively to a disposable full production-schema clone.
-- No real user, live session, or external subject is included.
insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous)
values
('f1900000-0000-4000-8000-000000000001','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000002','authenticated','authenticated',now(),now(),false),
('f1900000-0000-4000-8000-000000000003','authenticated','authenticated',now(),now(),false);

insert into atlas.principals(id,user_id,stable_key,name,status)
values
('f1900000-0000-4000-8000-000000000201','f1900000-0000-4000-8000-000000000001','foundry-local-signed-owner','Fictional Foundry owner','active'),
('f1900000-0000-4000-8000-000000000202','f1900000-0000-4000-8000-000000000002','foundry-local-signed-other','Fictional unrelated Principal','active');

-- A separate genuinely signed outsider with misleading user-editable metadata.
insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous)
values('f1900000-0000-4000-8000-000000000004','authenticated','authenticated',now(),now(),false);
insert into atlas.principals(id,user_id,stable_key,name,status)
values('f1900000-0000-4000-8000-000000000204','f1900000-0000-4000-8000-000000000004','foundry-local-signed-outsider','Fictional unassigned reviewer outsider','active');

-- No legacy organization membership is created for any test Person.
-- All participant relationships below use only canonical Person+native Ledger.
INSERT INTO reality.entities(id,stable_key,entity_kind,display_name)
VALUES
 ('f1900000-0000-4000-8000-000000000401','foundry-native-person-owner-20261024','person','Fictional owner'),
 ('f1900000-0000-4000-8000-000000000402','foundry-native-person-reviewer-20261024','person','Fictional reviewer'),
 ('f1900000-0000-4000-8000-000000000403','foundry-native-person-outsider-20261024','person','Fictional outsider'),
 ('f1900000-0000-4000-8000-000000000405','foundry-native-person-accountless-20261024','person','Fictional accountless person'),
 ('f1900000-0000-4000-8000-000000000499','foundry-native-ledger-subject-20261024','organization','Fictional Ledger subject');

INSERT INTO atlas.people(id,stable_key,display_name)
VALUES
 ('f1900000-0000-4000-8000-000000000401','foundry-native-person-owner-20261024','Fictional owner'),
 ('f1900000-0000-4000-8000-000000000402','foundry-native-person-reviewer-20261024','Fictional reviewer'),
 ('f1900000-0000-4000-8000-000000000403','foundry-native-person-outsider-20261024','Fictional outsider'),
 ('f1900000-0000-4000-8000-000000000405','foundry-native-person-accountless-20261024','Fictional accountless person');

UPDATE atlas.principals SET person_id=CASE
 WHEN user_id='f1900000-0000-4000-8000-000000000001' THEN 'f1900000-0000-4000-8000-000000000401'::uuid
 WHEN user_id='f1900000-0000-4000-8000-000000000002' THEN 'f1900000-0000-4000-8000-000000000402'::uuid
 WHEN user_id='f1900000-0000-4000-8000-000000000004' THEN 'f1900000-0000-4000-8000-000000000403'::uuid
 END
WHERE user_id IN (
 'f1900000-0000-4000-8000-000000000001',
 'f1900000-0000-4000-8000-000000000002',
 'f1900000-0000-4000-8000-000000000004'
);

INSERT INTO ledger.onboarding_cases(id,subject_entity_id,desired_ledger_name)
VALUES('f1900000-0000-4000-8000-000000000480',
       'f1900000-0000-4000-8000-000000000499','Fictional shared Ledger');

INSERT INTO ledger.ledgers(id,subject_entity_id,onboarding_case_id,stable_key,name)
VALUES('f1900000-0000-4000-8000-000000000490',
       'f1900000-0000-4000-8000-000000000499',
       'f1900000-0000-4000-8000-000000000480',
       'foundry-native-shared-ledger-20261024','Fictional shared Ledger');

INSERT INTO atlas.ledgers(id,stable_key,name)
VALUES('f1900000-0000-4000-8000-000000000490',
       'foundry-native-shared-ledger-20261024','Fictional shared Ledger');

INSERT INTO ledger.seats(ledger_id,person_entity_id)
VALUES
 ('f1900000-0000-4000-8000-000000000490','f1900000-0000-4000-8000-000000000401'),
 ('f1900000-0000-4000-8000-000000000490','f1900000-0000-4000-8000-000000000402'),
 ('f1900000-0000-4000-8000-000000000490','f1900000-0000-4000-8000-000000000405');

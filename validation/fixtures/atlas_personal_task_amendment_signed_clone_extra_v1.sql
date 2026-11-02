-- Synthetic Personal Atlas supplement to the existing C1 clone fixture.
-- Never apply outside a disposable localhost PostgreSQL clone.
INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status)
VALUES('a6300000-0000-4000-8000-000000000112',
'e5200000-0000-4000-8000-000000000002',
'e5200000-0000-4000-8000-000000000102',
'personal-clone-second-owner','Synthetic Other Owner','active');

INSERT INTO atlas.personal_atlas_access_grants(principal_id,grant_kind,basis)
VALUES
('e5200000-0000-4000-8000-000000000111','disposable_test','{"cloneOnly":true}'),
('a6300000-0000-4000-8000-000000000112','disposable_test','{"cloneOnly":true}');

INSERT INTO atlas.task_entries(
id,owner_user_id,principal_id,sentence,due_date,status,
source_action_id,completed_at,archived_at)
VALUES
('a6300000-0000-4000-8000-000000000201',
'e5200000-0000-4000-8000-000000000001',
'e5200000-0000-4000-8000-000000000111',
'Synthetic original one','2030-11-04','open','clone-personal-edit-201',NULL,NULL),
('a6300000-0000-4000-8000-000000000202',
'e5200000-0000-4000-8000-000000000001',
'e5200000-0000-4000-8000-000000000111',
'Synthetic completed','2030-11-04','done','clone-personal-edit-202',now(),NULL),
('a6300000-0000-4000-8000-000000000203',
'e5200000-0000-4000-8000-000000000001',
'e5200000-0000-4000-8000-000000000111',
'Synthetic archived','2030-11-04','open','clone-personal-edit-203',NULL,now()),
('a6300000-0000-4000-8000-000000000204',
'e5200000-0000-4000-8000-000000000001',
'e5200000-0000-4000-8000-000000000111',
'Synthetic transferred','2030-11-04','open','clone-personal-edit-204',NULL,NULL),
('a6300000-0000-4000-8000-000000000205',
'e5200000-0000-4000-8000-000000000001',
'e5200000-0000-4000-8000-000000000111',
'Synthetic for deletion','2030-11-04','open','clone-personal-edit-205',NULL,NULL),
('a6300000-0000-4000-8000-000000000206',
'e5200000-0000-4000-8000-000000000002',
'a6300000-0000-4000-8000-000000000112',
'Second owner task','2030-11-04','open','clone-personal-edit-206',NULL,NULL);

INSERT INTO atlas.work_items(
id,organization_id,title,work_state,source_object_type,source_object_id)
VALUES('a6300000-0000-4000-8000-000000000901',
'e5200000-0000-4000-8000-000000000801',
'Synthetic linked Work','open','personal_dated_task',
'a6300000-0000-4000-8000-000000000204');

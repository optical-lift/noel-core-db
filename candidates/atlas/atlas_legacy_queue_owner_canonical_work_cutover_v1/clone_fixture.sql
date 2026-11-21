-- DISPOSABLE C1-only addendum. Requires the EXISTING native Ledger/Person/Work fixture.
-- No live identities, actual farm rows, emails, or production Task data.
-- One canonical fictional Person for proving historical Task-assignee attribution.
INSERT INTO atlas.institutional_person_records(
 id,organization_id,person_id,status,establishment_basis)
VALUES ('e5200000-0000-4000-8000-000000000d31',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000102',
 'active','{"syntheticQueueReview":true}'::jsonb);

INSERT INTO atlas.tasks(id,organization_id,farm_id,title,status,metadata,assigned_user_id)
VALUES
 ('e5200000-0000-4000-8000-000000000d11',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000b01',
  'Synthetic historical queue Task for existing Work','open',
  '{"syntheticQueueReview":true}'::jsonb,'e5200000-0000-4000-8000-000000000002'),
 ('e5200000-0000-4000-8000-000000000d12',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000b01',
  'Synthetic Task already finished, old queue says active','done',
  '{"syntheticQueueReview":true}'::jsonb,NULL),
 ('e5200000-0000-4000-8000-000000000d13',
  'e5200000-0000-4000-8000-000000000801',
  'e5200000-0000-4000-8000-000000000b01',
  'Synthetic queued original for stale and no-current proof','open',
  '{"syntheticQueueReview":true}'::jsonb,NULL);

INSERT INTO atlas.task_release_queue_items
 (id,farm_id,queue_key,position,state,task_id,metadata)
VALUES
 ('e5200000-0000-4000-8000-000000000d21',
  'e5200000-0000-4000-8000-000000000b01',
  'c1_native_queue_owner_match',1,'queued',
  'e5200000-0000-4000-8000-000000000d11','{"clone":true}'::jsonb),
 ('e5200000-0000-4000-8000-000000000d22',
  'e5200000-0000-4000-8000-000000000b01',
  'c1_native_queue_owner_disagreement',1,'active',
  'e5200000-0000-4000-8000-000000000d12','{"clone":true}'::jsonb),
 ('e5200000-0000-4000-8000-000000000d23',
  'e5200000-0000-4000-8000-000000000b01',
  'c1_native_queue_owner_stale',1,'queued',
  'e5200000-0000-4000-8000-000000000d13','{"clone":true}'::jsonb),
 ('e5200000-0000-4000-8000-000000000d24',
  'e5200000-0000-4000-8000-000000000b01',
  'c1_native_queue_owner_without_task',1,'queued',
  NULL,'{"clone":true}'::jsonb);

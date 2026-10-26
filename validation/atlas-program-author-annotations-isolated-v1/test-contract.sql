-- Disposable PostgreSQL only. This tests signed-claim simulation, not
-- actual GoTrue signature verification or production-shaped auth infrastructure.
-- psql -X -v ON_ERROR_STOP=1 -f validation/.../test-contract.sql
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000001';
DO $test$
DECLARE
 v_program uuid:='61000000-0000-4000-8000-000000000201';
 v_version uuid:='61000000-0000-4000-8000-000000000301';
 v_foreign_version uuid:='61000000-0000-4000-8000-000000000302';
 v_note jsonb; v_replay jsonb; v_revised jsonb; v_read jsonb;
 v_note_id uuid;
BEGIN
 v_note:=public.personal_program_author_note_create_self_api_v1(
  v_program,v_version,'W1-A','Read the first',
  'A private source annotation.','isolate-create-note-001');
 v_note_id:=(v_note->>'noteId')::uuid;
 IF v_note->>'ok'<>'true' OR v_note->>'revision'<>'1'
  OR v_note->>'visibility'<>'author_private'
 THEN RAISE EXCEPTION 'Valid author note receipt not confirmed'; END IF;
 v_replay:=public.personal_program_author_note_create_self_api_v1(
  v_program,v_version,'W1-A','Read the first',
  'A private source annotation.','isolate-create-note-001');
 IF v_replay->>'noteId'<>v_note_id::text OR v_replay->>'replay'<>'true'
 THEN RAISE EXCEPTION 'Idempotent create did not identify original note'; END IF;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   v_program,v_version,'W1-A','Read the first',
   'Different request content.','isolate-create-note-001');
  RAISE EXCEPTION 'Conflicting create request was accepted';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   v_program,v_foreign_version,'W1-A',NULL,
   'Cross-Program anchor','isolate-foreign-version');
  RAISE EXCEPTION 'Other Program version admitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   v_program,v_version,'missing',NULL,
   'Unknown component','isolate-missing-component');
  RAISE EXCEPTION 'Unknown component admitted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   v_program,v_version,'W1-A','Invented quote',
   'Incorrect anchor','isolate-mismatched-excerpt');
  RAISE EXCEPTION 'Non-original passage admitted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
 v_revised:=public.personal_program_author_note_revise_self_api_v1(
  v_program,v_note_id,1,
  'Author revised note words.','resolved','isolate-revise-note-001');
 IF v_revised->>'revision'<>'2' OR v_revised->>'standing'<>'resolved'
 THEN RAISE EXCEPTION 'Append-only note revision did not take'; END IF;
 v_replay:=public.personal_program_author_note_revise_self_api_v1(
  v_program,v_note_id,1,
  'Author revised note words.','resolved','isolate-revise-note-001');
 IF v_replay->>'replay'<>'true' OR v_replay->>'revision'<>'2'
 THEN RAISE EXCEPTION 'Idempotent revise replay failed'; END IF;
 BEGIN
  PERFORM public.personal_program_author_note_revise_self_api_v1(
   v_program,v_note_id,1,'Stale words','open','isolate-revise-stale-001');
  RAISE EXCEPTION 'Stale note revision accepted';
 EXCEPTION WHEN SQLSTATE '40001' THEN NULL; END;
 v_read:=public.personal_program_author_notes_read_self_api_v1(v_program);
 IF v_read->>'total'<>'1' OR v_read->>'standing'<>'author_private'
   OR v_read->>'readerOnly'<>'true'
   OR v_read#>>'{items,0,revision}'<>'2'
   OR v_read#>>'{items,0,standing}'<>'resolved'
   OR pg_catalog.jsonb_array_length(v_read#>'{items,0,history}')<>2
 THEN RAISE EXCEPTION 'Source-owned annotation history did not read back'; END IF;
 PERFORM pg_catalog.set_config('test.author_note_id',v_note_id::text,false);
END;
$test$;
COMMIT;

-- Prove event history persisted but source version bytes did not change.
DO $test$
DECLARE v_source jsonb;
BEGIN
 SELECT approved_packet INTO v_source
 FROM atlas.personal_training_program_versions
 WHERE id='61000000-0000-4000-8000-000000000301';
 IF v_source->'components'->0->>'sourceExcerpt'<>'Original first passage.'
  OR (SELECT count(*) FROM atlas.personal_program_author_note_events
    WHERE program_id='61000000-0000-4000-8000-000000000201')<>2
 THEN RAISE EXCEPTION 'Approved author source changed or history missing'; END IF;
END;
$test$;

-- Authenticated but different canonical principal cannot read/write.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000002';
DO $test$
DECLARE v_note_id uuid:=pg_catalog.current_setting('test.author_note_id')::uuid;
BEGIN
 BEGIN
  PERFORM public.personal_program_author_notes_read_self_api_v1(
   '61000000-0000-4000-8000-000000000201');
  RAISE EXCEPTION 'Other author read private notes';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_revise_self_api_v1(
   '61000000-0000-4000-8000-000000000201',
   v_note_id,2,'Unauthorized revision','open','isolate-foreign-revision');
  RAISE EXCEPTION 'Other author revised a private note';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_note_create_self_api_v1(
   '61000000-0000-4000-8000-000000000201',
   '61000000-0000-4000-8000-000000000301',
   'W1-A',NULL,'Unauthorized annotation','isolate-other-create');
  RAISE EXCEPTION 'Other author created private note';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM (SELECT count(*) FROM atlas.personal_program_author_note_events);
  RAISE EXCEPTION 'Direct private table read admitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
ROLLBACK;

-- Even a previously established principal without eligibility is denied.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000003';
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_program_author_notes_read_self_api_v1(
   '61000000-0000-4000-8000-000000000201');
  RAISE EXCEPTION 'Revoked author was admitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
ROLLBACK;

-- No direct RPC or table grants to anonymous sessions.
BEGIN;
SET LOCAL ROLE anon;
DO $test$
BEGIN
 BEGIN
  PERFORM public.personal_program_author_notes_read_self_api_v1(
   '61000000-0000-4000-8000-000000000201');
  RAISE EXCEPTION 'Anonymous caller was admitted to author RPC';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$test$;
ROLLBACK;

-- Recheck the original canonical Program version and exact note revisions.
DO $test$
BEGIN
 IF (SELECT count(*) FROM atlas.personal_program_author_note_events
     WHERE program_id='61000000-0000-4000-8000-000000000201')<>2
 THEN RAISE EXCEPTION 'Negative tests mutated note history'; END IF;
END;
$test$;


-- Large-history semantics: 200 most recently active notes, not the 200
-- lowest UUIDs. This is synthetic isolated-fixture insertion only; real
-- application users can only write through governed authenticated functions.
INSERT INTO atlas.personal_program_author_note_events
 (note_id,revision,program_id,component_key,anchor_version_id,
  body,standing,actor_auth_user_id,request_key,created_at)
SELECT pg_catalog.gen_random_uuid(),1,
 '61000000-0000-4000-8000-000000000201'::uuid,
 'W1-A','61000000-0000-4000-8000-000000000301'::uuid,
 'Synthetic page '||seq::text,'open',
 '61000000-0000-4000-8000-000000000001'::uuid,
 'isolate-paged-note-'||seq::text,
 timestamptz '2031-01-01T00:00:00Z'+seq*interval '1 second'
FROM pg_catalog.generate_series(1,208) AS seq;
INSERT INTO atlas.personal_program_author_note_events
 (note_id,revision,program_id,component_key,anchor_version_id,
  anchor_excerpt,body,standing,actor_auth_user_id,request_key,created_at)
VALUES (
 pg_catalog.current_setting('test.author_note_id')::uuid,3,
 '61000000-0000-4000-8000-000000000201',
 'W1-A','61000000-0000-4000-8000-000000000301',
 'Read the first','Most recently active note','open',
 '61000000-0000-4000-8000-000000000001',
 'isolate-recent-revision-003','2032-01-01T00:00:00Z');
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='61000000-0000-4000-8000-000000000001';
DO $test$
DECLARE v_read jsonb;
BEGIN
 v_read:=public.personal_program_author_notes_read_self_api_v1(
  '61000000-0000-4000-8000-000000000201');
 IF v_read->>'total'<>'209' OR v_read->>'truncated'<>'true'
  OR pg_catalog.jsonb_array_length(v_read->'items')<>200
  OR v_read#>>'{items,0,text}'<>'Most recently active note'
  OR v_read#>>'{items,1,text}'<>'Synthetic page 208'
  OR v_read#>>'{items,199,text}'<>'Synthetic page 10'
  OR pg_catalog.jsonb_array_length(v_read#>'{items,0,history}')<>3
 THEN RAISE EXCEPTION 'Latest-first 200-note page or archival history failed'; END IF;
END;
$test$;
ROLLBACK;

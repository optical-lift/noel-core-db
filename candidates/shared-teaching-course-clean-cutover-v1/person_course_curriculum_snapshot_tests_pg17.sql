-- HELD M3.11: actual author-private Course Version content seal on fictional
-- isolated PG17, not a PostgREST/GoTrue or restored live-schema test.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_course_curriculum_snapshot_candidate.sql

DO $snapshot_private_surface$
BEGIN
 IF has_table_privilege('authenticated',
  'atlas.teaching_course_version_curriculum_snapshots','SELECT')
 OR has_table_privilege('authenticated',
  'atlas.teaching_course_version_curriculum_snapshots','INSERT')
 OR has_table_privilege('anon',
  'atlas.teaching_course_version_curriculum_snapshots','SELECT')
 OR has_function_privilege('anon',
  'public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon',
  'public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_course_curriculum_seal_self_api_v1(uuid,uuid,uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_course_curriculum_snapshot_self_api_v1(uuid)','EXECUTE')
 OR NOT EXISTS (SELECT 1 FROM pg_trigger
  WHERE tgrelid='atlas.teaching_course_version_curriculum_snapshots'::regclass
   AND tgname='teaching_course_curriculum_snapshot_immutable_v1'
   AND NOT tgisinternal) THEN
  RAISE EXCEPTION 'curriculum snapshot is not write-once and author-private';
 END IF;
END $snapshot_private_surface$;

SAVEPOINT author_curriculum_snapshot_fixture;

-- Independently signed institution root with accepted Version-use/title
-- rights STILL cannot seal or read the author's curriculum content.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $institution_cannot_seal_or_read$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_seal_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   current_setting('app.fictional_published_version_id')::uuid,
   '8aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'Ledger governor sealed private Person curriculum';
 END IF;
 denied:=false;
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_snapshot_self_api_v1(
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'Ledger governor read private author curriculum';
 END IF;
END $institution_cannot_seal_or_read$;
RESET ROLE;

-- Preserve an author-written CRLF + Unicode edit at sealing time so
-- read-back proves literal body strings survive JSONB snapshot copying.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author_prepares_exact_bytes$
DECLARE j jsonb;
BEGIN
 j:=public.shared_teaching_course_unit_save_self_api_v1(
   '31111111-1111-4111-8111-111111111111',
   '8bbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   2,E'Unit current \r\nלמד \nFrom original');
 IF j->'material'->>'revisionNumber'<>'3' THEN
  RAISE EXCEPTION 'fictional Unit current revision not saved';
 END IF;
 j:=public.shared_teaching_course_material_save_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   '8ccccccc-cccc-4ccc-8ccc-cccccccccccc',
   1,E'Current manuscript \r\nעברית\nExact');
 IF j->'material'->>'revisionNumber'<>'2' THEN
  RAISE EXCEPTION 'fictional manuscript revision not saved';
 END IF;
END $author_prepares_exact_bytes$;

DO $author_seals_once$
DECLARE a jsonb;b jsonb;item jsonb;sealed jsonb;denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  '8ddddddd-dddd-4ddd-8ddd-dddddddddddd');
 b:=public.shared_teaching_course_curriculum_seal_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  current_setting('app.fictional_published_version_id')::uuid,
  '8ddddddd-dddd-4ddd-8ddd-dddddddddddd');
 IF a->>'alreadyExists'<>'false' OR b->>'alreadyExists'<>'true'
 OR a->>'snapshotId'<>b->>'snapshotId'
 OR a->>'institutionCanRead'<>'false'
 OR a->>'canOpenOffering'<>'false'
 OR a ? 'curriculum' OR a ? 'manuscript'
 OR (a->>'courseId')::uuid IS DISTINCT FROM
  '11111111-1111-4111-8111-111111111111'::uuid THEN
  RAISE EXCEPTION 'exact author curriculum seal or idempotent replay failed';
 END IF;
 sealed:=public.shared_teaching_course_curriculum_snapshot_self_api_v1(
  current_setting('app.fictional_published_version_id')::uuid);
 IF sealed->>'snapshotId'<>a->>'snapshotId'
 OR sealed->>'institutionCanRead'<>'false'
 OR sealed->>'canOpenOffering'<>'false'
 OR sealed->'curriculum'->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR sealed->'curriculum'->>'courseVersionId' IS DISTINCT FROM
      current_setting('app.fictional_published_version_id')
 OR sealed->'curriculum'->'definition'->>'title'<>'Founding Course definition'
 OR sealed->'curriculum'->'manuscript'->>'text'
   IS DISTINCT FROM E'Current manuscript \r\nעברית\nExact'
 OR jsonb_array_length(sealed->'curriculum'->'units')<>2 THEN
  RAISE EXCEPTION 'exact private curriculum payload/Version relation failed';
 END IF;
 item:=sealed->'curriculum'->'units'->0;
 IF item->>'unitId'<>'31111111-1111-4111-8111-111111111111'
 OR item->>'kind'<>'lesson'
 OR item->>'revisionNumber'<>'3'
 OR item->>'text' IS DISTINCT FROM E'Unit current \r\nלמד \nFrom original'
 OR sealed->'curriculum'->'units'->1->>'unitId'
    <>'32222222-2222-4222-8222-222222222222'
 OR sealed->'curriculum'->'units'->1->>'text'
    <>'Research question, not issued Work.' THEN
  RAISE EXCEPTION 'ordered complete Units or UTF8/CRLF bytes not retained';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_seal_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   current_setting('app.fictional_published_version_id')::uuid,
   '8eeeeeee-eeee-4eee-8eee-eeeeeeeeeeee');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'changed sealing request reissued an existing immutable snapshot';
 END IF;
END $author_seals_once$;

-- Author may continue drafting future revisions; the Version snapshot is
-- frozen, not an alias to the mutable working editor's latest revision.
DO $future_edits_do_not_rewrite_seal$
DECLARE j jsonb; s jsonb;
BEGIN
 j:=public.shared_teaching_course_material_save_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '8fffffff-ffff-4fff-8fff-ffffffffffff',
  2,'Future draft text must not replace sealed text');
 IF j->'material'->>'revisionNumber'<>'3' THEN
  RAISE EXCEPTION 'future author revision was not saved';
 END IF;
 s:=public.shared_teaching_course_curriculum_snapshot_self_api_v1(
  current_setting('app.fictional_published_version_id')::uuid);
 IF s->'curriculum'->'manuscript'->>'text'
  IS DISTINCT FROM E'Current manuscript \r\nעברית\nExact' THEN
  RAISE EXCEPTION 'future author edit changed the sealed Version';
 END IF;
END $future_edits_do_not_rewrite_seal$;
RESET ROLE;

DO $immutability_and_one_root$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_version_curriculum_snapshots
     WHERE sealed_by_person_entity_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')<>1 THEN
  RAISE EXCEPTION 'curriculum snapshot minted extra root or lost source author';
 END IF;
 BEGIN
  UPDATE atlas.teaching_course_version_curriculum_snapshots
   SET curriculum_payload='{}'::jsonb;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'sealed curriculum UPDATE unexpectedly allowed'; END IF;
 denied:=false;
 BEGIN DELETE FROM atlas.teaching_course_version_curriculum_snapshots;
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'sealed curriculum DELETE unexpectedly allowed'; END IF;
END $immutability_and_one_root$;

-- Test actual incomplete curriculum refusal, not a permission shortcut.
-- A newly authored empty Unit makes a second Version's seal impossible.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $incomplete_course_rejected$
DECLARE v jsonb; o jsonb;denied boolean:=false;
BEGIN
 v:=public.shared_teaching_course_definition_publish_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '81111111-1111-4111-8111-111111111111',
  'Second fictional future definition','Not complete',ARRAY[]::text[]);
 o:=public.shared_teaching_course_unit_create_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  '82222222-2222-4222-8222-222222222222',
  'lesson','Unwritten new Unit');
 IF jsonb_array_length(o->'units')<>3 THEN
  RAISE EXCEPTION 'incomplete Unit fixture was not created';
 END IF;
 BEGIN
  PERFORM public.shared_teaching_course_curriculum_seal_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   (v->>'courseVersionId')::uuid,
   '83333333-3333-4333-8333-333333333333');
 EXCEPTION WHEN check_violation THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'unwritten Course Unit sealed as if complete';
 END IF;
END $incomplete_course_rejected$;
RESET ROLE;

-- Author's sealed records remain private when the source-held institution
-- operates an accepted metadata-only draft. No institution reader exists.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_cannot_read_after_author_seal$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.shared_teaching_course_curriculum_snapshot_self_api_v1(
   current_setting('app.fictional_published_version_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN
  RAISE EXCEPTION 'institution obtained author-only curriculum from Version use';
 END IF;
END $governor_cannot_read_after_author_seal$;
RESET ROLE;

ROLLBACK TO SAVEPOINT author_curriculum_snapshot_fixture;

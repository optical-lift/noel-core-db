-- M3.9 exact source proof, PG17 fiction / no real GoTrue or production.
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_published_definition_fixture_pg17.sql
\i /source/candidates/shared-teaching-course-clean-cutover-v1/person_published_definition_candidate.sql

DO $version_acl$
DECLARE trigger_count integer;
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_course_versions','SELECT')
 OR has_table_privilege('authenticated','atlas.teaching_course_versions','INSERT')
 OR has_function_privilege('anon',
  'public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])','EXECUTE')
 OR NOT has_function_privilege('authenticated',
  'public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])','EXECUTE')
 THEN RAISE EXCEPTION 'published definition ACL wrong'; END IF;
 SELECT count(*) INTO trigger_count FROM pg_trigger t
 WHERE t.tgrelid='atlas.teaching_course_versions'::regclass
  AND t.tgname='teaching_course_versions_immutable_v1'
  AND NOT t.tgisinternal
  AND (t.tgtype & 16)<>0 AND (t.tgtype & 8)<>0;
 IF trigger_count<>1 THEN
  RAISE EXCEPTION 'immutable Course Version source guard not preserved';
 END IF;
END $version_acl$;

-- Neither institution-only title permission nor accepted standing makes the
-- institution the author of the original Course Version.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $governor_not_author$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.shared_teaching_course_definition_publish_self_api_v1(
    '11111111-1111-4111-8111-111111111111',
    'b9999999-9999-4999-8999-999999999998',
    'Unauthorized Version',NULL,ARRAY[]::text[]);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'governor minted private author Version'; END IF;
END $governor_not_author$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $real_person_definition$
DECLARE a jsonb; b jsonb; denied boolean:=false;
BEGIN
 a:=public.shared_teaching_course_definition_publish_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'b9999999-9999-4999-8999-999999999999',
  'Founding Course definition','Original course version outline only',
  ARRAY['Learn direct observation','Distinguish original from use']);
 b:=public.shared_teaching_course_definition_publish_self_api_v1(
  '11111111-1111-4111-8111-111111111111',
  'b9999999-9999-4999-8999-999999999999',
  'Founding Course definition','Original course version outline only',
  ARRAY['Learn direct observation','Distinguish original from use']);
 IF a->>'courseId'<>'11111111-1111-4111-8111-111111111111'
 OR a->>'publicationScope'<>'definition_metadata_only'
 OR a->>'institutionCanUse'<>'false'
 OR a->>'alreadyExists'<>'false'
 OR b->>'alreadyExists'<>'true'
 OR a->>'courseVersionId'<>b->>'courseVersionId'
 OR a->>'versionNo'<>'1'
 THEN RAISE EXCEPTION 'Person-published immutable definition or exact replay failed'; END IF;
 BEGIN
  PERFORM public.shared_teaching_course_definition_publish_self_api_v1(
   '11111111-1111-4111-8111-111111111111',
   'b9999999-9999-4999-8999-999999999999',
   'Changed version title',NULL,ARRAY[]::text[]);
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'changed immutable publication replay passed'; END IF;
END $real_person_definition$;
RESET ROLE;

DO $immutable_version_test$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_course_versions)<>1
 OR (SELECT count(*) FROM atlas.teaching_courses)<>1
 OR NOT EXISTS (SELECT 1 FROM atlas.teaching_course_versions v
 WHERE v.course_id='11111111-1111-4111-8111-111111111111'
  AND v.published_by_person_entity_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  AND v.published_by_person_id IS NULL
  AND v.published_by_principal_id IS NULL
  AND v.publication_scope='definition_metadata_only'
 ) THEN
  RAISE EXCEPTION 'one canonical Course and Person-version relation failed';
 END IF;
 BEGIN
  UPDATE atlas.teaching_course_versions SET title='Mutated'
  WHERE course_id='11111111-1111-4111-8111-111111111111';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'old immutable version trigger was bypassed'; END IF;
 denied:=false;
 BEGIN DELETE FROM atlas.teaching_course_versions
  WHERE course_id='11111111-1111-4111-8111-111111111111';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Course Version deletion was allowed'; END IF;
END $immutable_version_test$;

-- Expose VERSION ID to later PG17 test code only via current test transaction
-- GUC. The held source never looks at or trusts this synthetic value.
SELECT set_config('app.fictional_published_version_id',
  (SELECT id::text FROM atlas.teaching_course_versions
    WHERE course_id='11111111-1111-4111-8111-111111111111'),
 true);

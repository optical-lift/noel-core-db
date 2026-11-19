-- HELD T5 TEST ONLY. Read-only compatibility assertions before candidate DDL.
DO $base$
DECLARE name text;
BEGIN
 IF current_setting('server_version_num')::int/10000<>17 OR inet_server_addr() IS NOT NULL
 OR current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 THEN RAISE EXCEPTION 'local socket PG17 scratch target required';END IF;
 FOREACH name IN ARRAY ARRAY['atlas.teaching_courses','atlas.teaching_course_versions',
 'atlas.teaching_course_manuscript_revisions','atlas.teaching_course_units','atlas.teaching_course_unit_revisions',
 'reality.entities','reality.auth_person_bindings','titus.course_authoring_access_grants']
 LOOP IF to_regclass(name) IS NULL THEN RAISE EXCEPTION 'released base relation absent: %',name;END IF;END LOOP;
 FOREACH name IN ARRAY ARRAY['atlas.require_private_course_author_self_v1(uuid,boolean)',
 'atlas.current_person_for_private_course_v1()','public.titus_authoring_access_self_api_v1()',
 'public.shared_teaching_course_adopt_self_api_v1(uuid)']
 LOOP IF to_regprocedure(name) IS NULL THEN RAISE EXCEPTION 'released base function absent: %',name;END IF;END LOOP;
 FOREACH name IN ARRAY ARRAY['atlas.teaching_course_composition_revisions',
 'atlas.teaching_course_version_curriculum_snapshots',
 'atlas.teaching_course_private_study_invitations',
 'atlas.teaching_course_private_study_responses',
 'atlas.teaching_course_private_study_terminations',
 'atlas.teaching_course_private_study_unit_decisions',
 'atlas.teaching_course_private_study_answer_revisions',
 'atlas.teaching_course_private_answer_submissions',
 'atlas.teaching_course_private_answer_review_events']
 LOOP IF to_regclass(name) IS NOT NULL THEN RAISE EXCEPTION 'overlapping held source: %',name;END IF;END LOOP;
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='atlas.teaching_course_versions'::regclass
 AND attname IN ('published_by_person_entity_id','publication_request_id','publication_scope') AND NOT attisdropped)
 THEN RAISE EXCEPTION 'overlapping Version source: reconcile before install'; END IF;
END $base$;

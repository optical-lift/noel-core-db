-- Synthetic transaction contract; no real JWT or production data.
DO $test$
DECLARE a uuid:='00000000-0000-4000-8000-000000000001'; b uuid:='00000000-0000-4000-8000-000000000002';
 c uuid; d uuid; u uuid; v uuid; req uuid:=gen_random_uuid(); ureq uuid:=gen_random_uuid(); change_req uuid:=gen_random_uuid();
 r jsonb; first jsonb; 
BEGIN
 PERFORM set_config('fixture.actor',a::text,true);
 c:=(public.shared_teaching_course_create_self_api_v1(req,'Original course')->>'courseId')::uuid;
 u:=((public.shared_teaching_course_unit_create_self_api_v1(c,ureq,'lesson','Original lesson')->'units'->0->>'unitId'))::uuid;
 IF (public.shared_teaching_object_title_read_self_api_v1(c,NULL)->>'revisionNumber')::int<>0 THEN RAISE EXCEPTION 'initial title revision'; END IF;
 first:=public.shared_teaching_object_title_save_self_api_v1(c,NULL,change_req,0,'Original course','New course');
 IF first->>'title'<>'New course' OR first->'current'->>'title'<>'New course' THEN RAISE EXCEPTION 'rename receipt'; END IF;
 IF public.shared_teaching_object_title_save_self_api_v1(c,NULL,change_req,0,'Original course','New course')<>first THEN RAISE EXCEPTION 'replay'; END IF;
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,NULL,change_req,0,'Original course','Changed retry');
  RAISE EXCEPTION 'changed retry accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,NULL,gen_random_uuid(),0,'Original course','Stale');
  RAISE EXCEPTION 'stale accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 r:=public.shared_teaching_object_title_save_self_api_v1(c,NULL,gen_random_uuid(),1,'New course','Current course');
 IF (r->>'revisionNumber')::int<>2 THEN RAISE EXCEPTION 'second revision'; END IF;
 r:=public.shared_teaching_object_title_save_self_api_v1(c,NULL,change_req,0,'Original course','New course');
 IF r->>'revisionId'<>first->>'revisionId' OR r->'current'->>'title'<>'Current course' THEN RAISE EXCEPTION 'historical receipt'; END IF;
 PERFORM public.shared_teaching_object_title_save_self_api_v1(c,u,gen_random_uuid(),0,'Original lesson','New lesson');
 IF public.shared_teaching_course_create_self_api_v1(req,'Original course')->>'courseId'<>c::text THEN RAISE EXCEPTION 'Course creation replay'; END IF;
 IF public.shared_teaching_course_unit_create_self_api_v1(c,ureq,'lesson','Original lesson')->'units'->0->>'unitId'<>u::text THEN RAISE EXCEPTION 'Unit creation replay'; END IF;
 BEGIN
  PERFORM public.shared_teaching_course_create_self_api_v1(req,'Current course');
  RAISE EXCEPTION 'changed founding replay accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT name FROM atlas.teaching_courses WHERE id=c)<>'Current course' OR (SELECT title FROM atlas.teaching_course_units WHERE unit_id=u)<>'New lesson' THEN RAISE EXCEPTION 'canonical names'; END IF;
 PERFORM set_config('fixture.actor',b::text,true);
 d:=(public.shared_teaching_course_create_self_api_v1(req,'Original course')->>'courseId')::uuid;
 v:=(public.shared_teaching_course_unit_create_self_api_v1(d,ureq,'lesson','Original lesson')->'units'->0->>'unitId')::uuid;
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,NULL,gen_random_uuid(),2,'Current course','Wrong person');
  RAISE EXCEPTION 'wrong person accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('fixture.actor',a::text,true);
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,v,gen_random_uuid(),0,'Original lesson','Wrong unit');
  RAISE EXCEPTION 'wrong unit accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,NULL,gen_random_uuid(),2,'Current course',E'bad\nlabel');
  RAISE EXCEPTION 'newline accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 UPDATE titus.fixture_grants SET active=false WHERE person_id=a;
 BEGIN
  PERFORM public.shared_teaching_object_title_save_self_api_v1(c,NULL,gen_random_uuid(),2,'Current course','Revoked');
  RAISE EXCEPTION 'revoked accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF (SELECT count(*) FROM atlas.teaching_object_title_revisions WHERE course_id=c)<>3 THEN RAISE EXCEPTION 'unexpected history count'; END IF;
 BEGIN
  DELETE FROM atlas.teaching_object_title_revisions WHERE course_id=c;
  RAISE EXCEPTION 'history deletion accepted';
 EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
 IF has_table_privilege('authenticated','atlas.teaching_object_title_revisions','INSERT') OR
    has_function_privilege('anon','public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text)','EXECUTE') OR
    has_function_privilege('service_role','public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text)','EXECUTE') THEN RAISE EXCEPTION 'ACL leak'; END IF;
END
$test$;
SELECT 'PASS fictional PG17 title transaction and replay checks';

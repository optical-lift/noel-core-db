\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('fixture.subject','00000000-0000-4000-8000-000000000001',false);
SELECT set_config('fixture.access','active',false);
DO $$
DECLARE
 c uuid:='00000000-0000-4000-8000-000000000010';
 other_course uuid:='00000000-0000-4000-8000-000000000020';
 req uuid:='00000000-0000-4000-8000-000000000030';
 req2 uuid:='00000000-0000-4000-8000-000000000031';
 members jsonb:='[{"unitId":"00000000-0000-4000-8000-000000000012","classUnitId":"00000000-0000-4000-8000-000000000011","depth":"foundational"},{"unitId":"00000000-0000-4000-8000-000000000013","classUnitId":"00000000-0000-4000-8000-000000000011","depth":"advanced"},{"unitId":"00000000-0000-4000-8000-000000000014","classUnitId":"00000000-0000-4000-8000-000000000011","depth":"advanced"}]';
 a jsonb;b jsonb;bad jsonb;
BEGIN
 a:=public.shared_teaching_course_composition_read_self_api_v1(c);
 IF a->>'revisionNumber'<>'0' OR a->'members'<>'[]'::jsonb THEN RAISE EXCEPTION 'empty first';END IF;
 BEGIN PERFORM public.shared_teaching_course_composition_read_self_api_v1(other_course);RAISE EXCEPTION 'cross course read';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(other_course,req,0,'[]');RAISE EXCEPTION 'cross course write';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,jsonb_build_array(jsonb_set(members->0,'{classUnitId}',to_jsonb('00000000-0000-4000-8000-000000000021'::text))));RAISE EXCEPTION 'foreign parent';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,jsonb_build_array(jsonb_set(members->0,'{classUnitId}',to_jsonb('00000000-0000-4000-8000-000000000014'::text))));RAISE EXCEPTION 'assignment parent';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members||jsonb_build_array(members->0));RAISE EXCEPTION 'duplicate';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members||'[{"unitId":"00000000-0000-4000-8000-000000000011","classUnitId":"00000000-0000-4000-8000-000000000013","depth":"advanced"}]'::jsonb);RAISE EXCEPTION 'cycle';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,jsonb_build_array((members->0)||'{"extra":"not allowed"}'::jsonb));RAISE EXCEPTION 'unknown key';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 a:=public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members);
 IF a->>'revisionNumber'<>'1' OR a->'members'<>members THEN RAISE EXCEPTION 'save receipt';END IF;
 b:=public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members);
 IF a<>b THEN RAISE EXCEPTION 'retry receipt';END IF;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,'[]');RAISE EXCEPTION 'changed retry';EXCEPTION WHEN unique_violation THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req2,0,'[]');RAISE EXCEPTION 'stale revision';EXCEPTION WHEN serialization_failure THEN NULL;END;
 b:=public.shared_teaching_course_composition_save_self_api_v1(c,req2,1,'[]');
 IF b->>'revisionNumber'<>'2' OR b->'members'<>'[]'::jsonb THEN RAISE EXCEPTION 'detach';END IF;
 IF public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members)<>a THEN RAISE EXCEPTION 'historical receipt';END IF;
 IF public.shared_teaching_course_composition_read_self_api_v1(c)<>b THEN RAISE EXCEPTION 'current read';END IF;
 PERFORM set_config('fixture.access','revoked',false);
 BEGIN PERFORM public.shared_teaching_course_composition_save_self_api_v1(c,req,0,members);RAISE EXCEPTION 'revoked replay';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('fixture.subject','00000000-0000-4000-8000-000000000002',false);
 BEGIN PERFORM public.shared_teaching_course_composition_read_self_api_v1(c);RAISE EXCEPTION 'other owner';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM atlas.teaching_course_composition_revisions)<>2 OR (SELECT count(*) FROM atlas.teaching_course_units)<>5 THEN RAISE EXCEPTION 'source preservation';END IF;
 IF has_table_privilege('authenticated','atlas.teaching_course_composition_revisions','SELECT') OR has_table_privilege('service_role','atlas.teaching_course_composition_revisions','INSERT') OR has_function_privilege('anon','public.shared_teaching_course_composition_read_self_api_v1(uuid)','EXECUTE') THEN RAISE EXCEPTION 'ACL';END IF;
 BEGIN UPDATE atlas.teaching_course_composition_revisions SET members='[]';RAISE EXCEPTION 'mutable history';EXCEPTION WHEN check_violation THEN NULL;END;
 BEGIN TRUNCATE atlas.teaching_course_composition_revisions;RAISE EXCEPTION 'truncatable history';EXCEPTION WHEN check_violation THEN NULL;END;
END $$;

-- Runs inside actual M3.17B journey after B has independently selected E2.
DO $acl$
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_course_private_study_answer_revisions','SELECT')
 OR has_table_privilege('service_role','atlas.teaching_course_private_study_answer_revisions','INSERT')
 OR has_function_privilege('anon','public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'answer history not private'; END IF;
 IF NOT atlas.private_study_question_valid_v1(E'## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\n\nWhat changed?', '12345678-1234-4234-8234-123456789abc')
 OR atlas.private_study_question_valid_v1(E':::evidence Hidden\n## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\n\nWhat changed?\n:::', '12345678-1234-4234-8234-123456789abc')
 OR atlas.private_study_question_valid_v1(E'## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\n\n# Next', '12345678-1234-4234-8234-123456789abc')
 OR atlas.private_study_question_valid_v1(E'## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\n\nWhat changed?\n## Question {#titus-activity:12345678-1234-4234-8234-123456789abc}\nAgain', '12345678-1234-4234-8234-123456789abc')
 THEN RAISE EXCEPTION 'explicit anchor validation'; END IF;
END $acl$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $own$
DECLARE inv uuid:=current_setting('app.private_e_b')::uuid;u uuid:='31111111-1111-4111-8111-111111111111';
 a uuid:='12345678-1234-4234-8234-123456789abc';req uuid:='12345678-1234-4234-8234-123456789001';req2 uuid:='12345678-1234-4234-8234-123456789002';
 j jsonb;s uuid;r uuid;x jsonb;y jsonb;
BEGIN
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(inv,u);
 s:=(j->>'snapshotId')::uuid;r:=(j->'unit'->>'revisionId')::uuid;
 PERFORM set_config('app.t4_snapshot',s::text,true);PERFORM set_config('app.t4_revision',r::text,true);
 x:=public.shared_teaching_private_study_answer_read_self_api_v1(inv,u,s,r,a);
 IF x->>'revisionNumber'<>'0' OR x->'text'<>'null'::jsonb THEN RAISE EXCEPTION 'empty answer';END IF;
 x:=public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req,0,E'Observed א.\nMy finding.');
 IF x->>'revisionNumber'<>'1' OR x->>'private'<>'true' OR x->>'submitted'<>'false' THEN RAISE EXCEPTION 'own answer receipt';END IF;
 IF x<>public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req,0,E'Observed א.\nMy finding.') THEN RAISE EXCEPTION 'exact replay';END IF;
 BEGIN PERFORM public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req,0,'Changed retry');RAISE EXCEPTION 'changed retry allowed';EXCEPTION WHEN unique_violation THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req2,0,'Stale');RAISE EXCEPTION 'stale allowed';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_private_study_answer_read_self_api_v1(inv,u,s,r,'12345678-1234-4234-8234-123456789fff');RAISE EXCEPTION 'invented question allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.shared_teaching_private_study_answer_read_self_api_v1(inv,u,s,gen_random_uuid(),a);RAISE EXCEPTION 'foreign revision allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 y:=public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req2,1,'Revised finding.');
 IF y->>'revisionNumber'<>'2' OR y<>public.shared_teaching_private_study_answer_read_self_api_v1(inv,u,s,r,a) THEN RAISE EXCEPTION 'revision reopen';END IF;
 IF x<>public.shared_teaching_private_study_answer_save_self_api_v1(inv,u,s,r,a,req,0,E'Observed א.\nMy finding.') THEN RAISE EXCEPTION 'historical receipt';END IF;
END $own$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $other$
BEGIN
 BEGIN PERFORM public.shared_teaching_private_study_answer_read_self_api_v1(current_setting('app.private_e_b')::uuid,
 '31111111-1111-4111-8111-111111111111',current_setting('app.t4_snapshot')::uuid,current_setting('app.t4_revision')::uuid,'12345678-1234-4234-8234-123456789abc');
 RAISE EXCEPTION 'other learner read';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $other$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $author$
BEGIN
 BEGIN PERFORM public.shared_teaching_private_study_answer_read_self_api_v1(current_setting('app.private_e_b')::uuid,
 '31111111-1111-4111-8111-111111111111',current_setting('app.t4_snapshot')::uuid,current_setting('app.t4_revision')::uuid,'12345678-1234-4234-8234-123456789abc');
 RAISE EXCEPTION 'author read learner private work';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $author$;
RESET ROLE;
DO $history$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_course_private_study_answer_revisions)<>2
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_answer_revisions WHERE revision_no=1 AND body_text=E'Observed א.\nMy finding.')
 THEN RAISE EXCEPTION 'original not retained'; END IF;
 BEGIN UPDATE atlas.teaching_course_private_study_answer_revisions SET body_text='changed';RAISE EXCEPTION 'mutable original';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
END $history$;

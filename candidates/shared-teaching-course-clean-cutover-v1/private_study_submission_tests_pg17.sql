-- Runs after M3.17C original answer revisions on B's E2.
DO $acl$
BEGIN
 IF has_table_privilege('authenticated','atlas.teaching_course_private_answer_submissions','SELECT')
 OR has_table_privilege('service_role','atlas.teaching_course_private_answer_review_events','INSERT')
 OR has_function_privilege('anon','public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'submission custody ACL'; END IF;
 PERFORM set_config('app.t4_original_answer',(SELECT answer_revision_id::text FROM atlas.teaching_course_private_study_answer_revisions WHERE revision_no=1),true);
 PERFORM set_config('app.t4_private_answer',(SELECT answer_revision_id::text FROM atlas.teaching_course_private_study_answer_revisions WHERE revision_no=2),true);
END $acl$;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $other$
BEGIN
 BEGIN PERFORM public.shared_teaching_private_answer_submit_self_api_v1(current_setting('app.t4_original_answer')::uuid,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',gen_random_uuid());
 RAISE EXCEPTION 'other learner submitted answer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $other$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $submit$
DECLARE a uuid:=current_setting('app.t4_original_answer')::uuid;t uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';req uuid:='12345678-1234-4234-8234-123456789010';j jsonb;
BEGIN
 BEGIN PERFORM public.shared_teaching_private_answer_submit_self_api_v1(a,'f9999999-9999-4999-8999-999999999991',gen_random_uuid());
 RAISE EXCEPTION 'unrelated recipient'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 j:=public.shared_teaching_private_answer_review_target_self_api_v1(a);
 IF j->>'reviewerPersonId'<>t::text OR j->'submissionId'<>'null'::jsonb THEN RAISE EXCEPTION 'own target resolution'; END IF;
 j:=public.shared_teaching_private_answer_submit_self_api_v1(a,t,req);
 IF j->>'answerRevisionId'<>a::text OR j->>'notebookDisclosed'<>'false' OR j<>public.shared_teaching_private_answer_submit_self_api_v1(a,t,req)
 THEN RAISE EXCEPTION 'selected submission receipt'; END IF;
 PERFORM set_config('app.t4_submission',j->>'submissionId',true);
 BEGIN PERFORM public.shared_teaching_private_answer_submit_self_api_v1(current_setting('app.t4_private_answer')::uuid,t,req);
 RAISE EXCEPTION 'changed revision retry'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM public.shared_teaching_private_answer_review_event_self_api_v1((j->>'submissionId')::uuid,gen_random_uuid(),'accept_review',NULL);
 RAISE EXCEPTION 'learner impersonated reviewer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $submit$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $review$
DECLARE s uuid:=current_setting('app.t4_submission')::uuid; j jsonb;req uuid:='12345678-1234-4234-8234-123456789011';f uuid:='12345678-1234-4234-8234-123456789012';
BEGIN
 j:=public.shared_teaching_private_answer_review_inbox_self_api_v1('11111111-1111-4111-8111-111111111111',NULL);
 IF jsonb_array_length(j->'items')<>1 OR j->'items'->0->>'submissionId'<>s::text OR j->'items'->0 ? 'text' THEN RAISE EXCEPTION 'bounded inbox'; END IF;
 j:=public.shared_teaching_private_answer_submission_read_self_api_v1(s,'reviewer');
 IF j->>'state'<>'submitted' OR j->'text'<>'null'::jsonb OR j->'feedback'<>'null'::jsonb THEN RAISE EXCEPTION 'unaccepted reviewer saw answer'; END IF;
 BEGIN PERFORM public.shared_teaching_private_answer_review_event_self_api_v1(s,f,'feedback','Too soon');
 RAISE EXCEPTION 'feedback before acceptance'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 j:=public.shared_teaching_private_answer_review_event_self_api_v1(s,req,'accept_review',NULL);
 IF j<>public.shared_teaching_private_answer_review_event_self_api_v1(s,req,'accept_review',NULL) THEN RAISE EXCEPTION 'acceptance replay'; END IF;
 j:=public.shared_teaching_private_answer_submission_read_self_api_v1(s,'reviewer');
 IF j->>'state'<>'accepted' OR j->>'text' IS DISTINCT FROM E'Observed א.\nMy finding.' OR j->>'revisionNumber'<>'1'
 THEN RAISE EXCEPTION 'wrong selected answer'; END IF;
 j:=public.shared_teaching_private_answer_review_event_self_api_v1(s,f,'feedback',E'Compare the record.\nThen refine.');
 IF j<>public.shared_teaching_private_answer_review_event_self_api_v1(s,f,'feedback',E'Compare the record.\nThen refine.') THEN RAISE EXCEPTION 'feedback replay'; END IF;
 BEGIN PERFORM public.shared_teaching_private_answer_review_event_self_api_v1(s,f,'feedback','Changed');
 RAISE EXCEPTION 'feedback mutated'; EXCEPTION WHEN unique_violation THEN NULL; END;
END $review$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999991","session_id":"59999999-9999-4999-8999-999999999991"}';
DO $outsider$
BEGIN
 BEGIN PERFORM public.shared_teaching_private_answer_submission_read_self_api_v1(current_setting('app.t4_submission')::uuid,'reviewer');
 RAISE EXCEPTION 'outsider received selected answer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $outsider$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"d9999999-9999-4999-8999-999999999992","session_id":"59999999-9999-4999-8999-999999999992"}';
DO $learner$
DECLARE s uuid:=current_setting('app.t4_submission')::uuid;j jsonb;
BEGIN
 j:=public.shared_teaching_private_answer_submission_read_self_api_v1(s,'learner');
 IF j->>'state'<>'feedback' OR j->'feedback'->>'text' IS DISTINCT FROM E'Compare the record.\nThen refine.' THEN RAISE EXCEPTION 'learner feedback unavailable'; END IF;
 PERFORM public.shared_teaching_private_answer_review_event_self_api_v1(s,gen_random_uuid(),'withdraw',NULL);
 j:=public.shared_teaching_private_answer_submission_read_self_api_v1(s,'learner');
 IF j->>'state'<>'withdrawn' OR j->'feedback'->>'text' IS DISTINCT FROM E'Compare the record.\nThen refine.' THEN RAISE EXCEPTION 'withdrawal destroyed learner history'; END IF;
END $learner$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $withdrawn$
BEGIN
 IF jsonb_array_length(public.shared_teaching_private_answer_review_inbox_self_api_v1('11111111-1111-4111-8111-111111111111',NULL)->'items')<>0 THEN RAISE EXCEPTION 'withdrawn queue entry';END IF;
 BEGIN PERFORM public.shared_teaching_private_answer_submission_read_self_api_v1(current_setting('app.t4_submission')::uuid,'reviewer');
 RAISE EXCEPTION 'withdrawn submission disclosed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.shared_teaching_private_answer_review_event_self_api_v1(current_setting('app.t4_submission')::uuid,gen_random_uuid(),'feedback','After withdrawal');
 RAISE EXCEPTION 'withdrawn feedback write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $withdrawn$;
RESET ROLE;
DO $history$
BEGIN
 IF (SELECT count(*) FROM atlas.teaching_course_private_answer_submissions)<>1
 OR (SELECT count(*) FROM atlas.teaching_course_private_answer_review_events)<>3
 OR (SELECT count(*) FROM atlas.teaching_course_private_study_answer_revisions)<>2
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_answer_revisions WHERE revision_no=2 AND body_text='Revised finding.')
 THEN RAISE EXCEPTION 'submission or feedback changed private source'; END IF;
 BEGIN DELETE FROM atlas.teaching_course_private_answer_review_events;RAISE EXCEPTION 'mutable review event';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END $history$;

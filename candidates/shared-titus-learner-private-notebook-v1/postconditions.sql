-- Test-only GUC claims are synthetic, unsigned and cannot establish real GoTrue identity.
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ DECLARE r jsonb; BEGIN
 r:=public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
 IF jsonb_array_length(r->'notes')<>0 THEN RAISE EXCEPTION 'New learner notebook not empty';END IF;
 r:=public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,'cc000000-0000-4000-8000-000000000001'::uuid,'My fictional private observation');
 IF r->>'replay'<>'false' THEN RAISE EXCEPTION 'First insert misclassified';END IF;
 r:=public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
 IF jsonb_array_length(r->'notes')<>1 OR r->'notes'->0->>'body'<>'My fictional private observation'
 OR r->>'courseVersionId'<>'90000000-0000-4000-8000-000000000001'
 THEN RAISE EXCEPTION 'Readback or version not source-confirmed'; END IF;
 r:=public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,'cc000000-0000-4000-8000-000000000001'::uuid,'My fictional private observation');
 IF r->>'replay'<>'true' THEN RAISE EXCEPTION 'Exact replay not idempotent';END IF;
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,'cc000000-0000-4000-8000-000000000001'::uuid,'Changed original');
  RAISE EXCEPTION 'FAIL modified retry';
 EXCEPTION WHEN SQLSTATE '23505' THEN NULL;END;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000002","session_id":"20000000-0000-4000-8000-000000000002","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL peer read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL peer write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ DECLARE r jsonb; BEGIN
 r:=public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000002'::uuid);
 IF jsonb_array_length(r->'notes')<>0 THEN RAISE EXCEPTION 'Peer notes leaked';END IF;
 END $t$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000003","session_id":"20000000-0000-4000-8000-000000000003","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL teacher without enrollment read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL teacher without enrollment write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"other-atlas-client"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL wrong OAuth client read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL wrong OAuth client write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000003","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL mismatched session read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL mismatched session write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000099'::uuid);
  RAISE EXCEPTION 'FAIL missing enrollment read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
UPDATE auth.sessions SET not_after=now()-interval '1 hour' WHERE user_id='10000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL expired session read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL expired session write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 day' WHERE user_id='10000000-0000-4000-8000-000000000001';
UPDATE atlas.person_auth_credentials SET status='retired' WHERE auth_user_id='10000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL retired credential read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL retired credential write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
UPDATE atlas.person_auth_credentials SET status='active' WHERE auth_user_id='10000000-0000-4000-8000-000000000001';
UPDATE atlas.synthetic_capability SET state='paused';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL paused teaching read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL paused teaching write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
UPDATE atlas.synthetic_capability SET state='active';
UPDATE atlas.teaching_enrollments SET state='withdrawn',withdrawn_at=now() WHERE id='bb000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL withdrawn enrollment read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL withdrawn enrollment write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
UPDATE atlas.teaching_enrollments SET state='active',withdrawn_at=NULL WHERE id='bb000000-0000-4000-8000-000000000001';
UPDATE atlas.teaching_course_offerings SET state='closed',closed_at=now() WHERE id='aa000000-0000-4000-8000-000000000001';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-4000-8000-000000000001","session_id":"20000000-0000-4000-8000-000000000001","client_id":"d0b999e7-a2e2-4bb8-91ea-482fcd44b257"}',false);
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_notes_read_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid);
  RAISE EXCEPTION 'FAIL closed offering read allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
DO $t$ BEGIN
 BEGIN
  PERFORM public.titus_learner_private_note_create_self_api_v1('bb000000-0000-4000-8000-000000000001'::uuid,gen_random_uuid(),'Blocked fictional writing');
  RAISE EXCEPTION 'FAIL closed offering write allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF (SELECT count(*) FROM titus.learner_private_course_note_events_v1)<>1 THEN RAISE EXCEPTION 'Failed denials mutated originals'; END IF;
 BEGIN DELETE FROM titus.learner_private_course_note_events_v1;RAISE EXCEPTION 'FAIL original delete';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN UPDATE titus.learner_private_course_note_events_v1 SET body_text='changed';RAISE EXCEPTION 'FAIL original mutate';EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
END $t$;
SELECT 'PASS synthetic sessions: correct author, peer, teacher, replay, session, entitlement, withdrawal, immutable original' AS result;

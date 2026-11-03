\set ON_ERROR_STOP on
-- Disposable, invented Person/auth fixtures ONLY; no GoTrue or live learner.
SELECT set_config('titus.b2b_fixture_current_person',
 '00000000-0000-4000-8000-000000000101',false);
SELECT set_config('titus.disclosure_fixture_auth_uid',
 '00000000-0000-4000-8000-000000000901',false);
SELECT set_config('titus.disclosure_fixture_session',
 '00000000-0000-4000-8000-000000000902',false);

DO $test$
DECLARE
 v_new uuid := '00000000-0000-4000-8000-000000000520';
 v_legacy uuid := '00000000-0000-4000-8000-000000000501';
 v_unverified uuid := '00000000-0000-4000-8000-000000000521';
 v_text text := 'Fictional learner teaches back the original material.';
 v_hash text;
BEGIN
 -- PREEXISTING rows must not be falsely attributed to the current Person.
 IF EXISTS (
  SELECT 1 FROM titus.formation_responses
  WHERE formation_response_id=v_legacy
    AND (submitted_by_person_entity_id IS NOT NULL
      OR original_text_sha256 IS NOT NULL)
 ) THEN RAISE EXCEPTION 'legacy original was falsely backfilled'; END IF;

 -- Signed self-responses are captured in the SAME new response row.
 -- Supplying false fields is ineffective: the trigger overwrites them.
 INSERT INTO titus.formation_responses(
   formation_response_id,formation_unit_id,teacher_id,
   raw_text,submitted_by_person_entity_id,original_text_sha256
 ) VALUES (
   v_new,
   '00000000-0000-4000-8000-000000000301',
   '00000000-0000-4000-8000-000000000401',
   v_text,
   '00000000-0000-4000-8000-000000000103',
   repeat('0',64)
 );
 v_hash:=encode(sha256(convert_to(v_text,'UTF8')),'hex');
 IF NOT EXISTS (
  SELECT 1 FROM titus.formation_responses
  WHERE formation_response_id=v_new AND raw_text=v_text
    AND submitted_by_person_entity_id='00000000-0000-4000-8000-000000000101'
    AND submitted_by_auth_user_id='00000000-0000-4000-8000-000000000901'
    AND submitted_in_session_id='00000000-0000-4000-8000-000000000902'
    AND original_text_sha256=v_hash
 ) THEN RAISE EXCEPTION 'original learner Person/session/text not captured'; END IF;

 -- A different Person cannot use an unrelated historical teacher binding.
 PERFORM set_config('titus.b2b_fixture_current_person',
 '00000000-0000-4000-8000-000000000104',false);
 BEGIN
  INSERT INTO titus.formation_responses(
   formation_response_id,formation_unit_id,teacher_id,raw_text
  ) VALUES (
   '00000000-0000-4000-8000-000000000522',
   '00000000-0000-4000-8000-000000000301',
   '00000000-0000-4000-8000-000000000401','not learner original'
  );
  RAISE EXCEPTION 'different Person wrong binding was accepted';
 EXCEPTION WHEN others THEN
  IF SQLERRM <> 'Formation submission lacks a valid signed learner binding' THEN
   RAISE;
  END IF;
 END;
 PERFORM set_config('titus.b2b_fixture_current_person',
 '00000000-0000-4000-8000-000000000101',false);

 -- Partial actor/session cannot gain a proof.
 PERFORM set_config('titus.disclosure_fixture_session','',false);
 BEGIN
  INSERT INTO titus.formation_responses(
   formation_response_id,formation_unit_id,teacher_id,raw_text
  ) VALUES (
   '00000000-0000-4000-8000-000000000523',
   '00000000-0000-4000-8000-000000000301',
   '00000000-0000-4000-8000-000000000401','partial session'
  );
  RAISE EXCEPTION 'partial session accepted';
 EXCEPTION WHEN others THEN
  IF SQLERRM <> 'Formation submission lacks a valid signed learner binding' THEN
   RAISE;
  END IF;
 END;
 PERFORM set_config('titus.disclosure_fixture_session','not-a-uuid',false);
 BEGIN
  INSERT INTO titus.formation_responses(
   formation_response_id,formation_unit_id,teacher_id,raw_text
  ) VALUES (
   '00000000-0000-4000-8000-000000000524',
   '00000000-0000-4000-8000-000000000301',
   '00000000-0000-4000-8000-000000000401','malformed session'
  );
  RAISE EXCEPTION 'malformed signed session accepted';
 EXCEPTION WHEN others THEN
  IF SQLERRM <> 'invalid signed Formation session' THEN RAISE; END IF;
 END;

 -- A privileged / non-user import with no signed session is left unverified,
 -- not retroactively attributed to the last authenticated learner.
 PERFORM set_config('titus.b2b_fixture_current_person','',false);
 PERFORM set_config('titus.disclosure_fixture_auth_uid','',false);
 PERFORM set_config('titus.disclosure_fixture_session','',false);
 INSERT INTO titus.formation_responses(
  formation_response_id,formation_unit_id,teacher_id,raw_text,
  submitted_by_person_entity_id
 ) VALUES (
  v_unverified,
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000401',
  'Fictional unverified import',
  '00000000-0000-4000-8000-000000000103'
 );
 IF NOT EXISTS (
  SELECT 1 FROM titus.formation_responses WHERE formation_response_id=v_unverified
  AND submitted_by_person_entity_id IS NULL
  AND submitted_by_auth_user_id IS NULL
  AND submitted_in_session_id IS NULL
  AND original_text_sha256 IS NULL
 ) THEN RAISE EXCEPTION 'unverified import was falsely signed'; END IF;

 -- Both new and historical raw originals resist mutation.
 BEGIN
  UPDATE titus.formation_responses SET raw_text='overwritten'
  WHERE formation_response_id=v_new;
  RAISE EXCEPTION 'signed original overwritten';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'Formation original source and attribution are immutable' THEN
   RAISE;
  END IF;
 END;
 BEGIN
  UPDATE titus.formation_responses SET raw_text='overwritten'
  WHERE formation_response_id=v_legacy;
  RAISE EXCEPTION 'legacy original overwritten';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'Formation original source and attribution are immutable' THEN
   RAISE;
  END IF;
 END;
 BEGIN
  UPDATE titus.formation_responses SET
    submitted_by_person_entity_id='00000000-0000-4000-8000-000000000103'
  WHERE formation_response_id=v_new;
  RAISE EXCEPTION 'submitted Person attribution overwritten';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'Formation original source and attribution are immutable' THEN
   RAISE;
  END IF;
 END;
 BEGIN
  UPDATE titus.formation_responses SET
    formation_unit_id='00000000-0000-4000-8000-000000000302'
  WHERE formation_response_id=v_new;
  RAISE EXCEPTION 'original Unit rewritten';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'Formation original source and attribution are immutable' THEN
   RAISE;
  END IF;
 END;
 BEGIN
  DELETE FROM titus.formation_responses WHERE formation_response_id=v_new;
  RAISE EXCEPTION 'signed original deleted';
 EXCEPTION WHEN others THEN
  IF SQLERRM<>'original Formation responses cannot be deleted' THEN
   RAISE;
  END IF;
 END;

 -- Existing non-original response review metadata can still change.
 UPDATE titus.formation_responses
 SET response_status='reviewed'
 WHERE formation_response_id=v_new;
 IF NOT EXISTS (
  SELECT 1 FROM titus.formation_responses
  WHERE formation_response_id=v_new
    AND response_status='reviewed'
    AND original_text_sha256=v_hash
    AND raw_text=v_text
 ) THEN RAISE EXCEPTION 'ordinary response status update was broken'; END IF;

 -- Even after a real-looking original receipt, reviewing is still CLOSED.
 IF titus.formation_review_source_issuance_verified_v1(v_new) IS DISTINCT FROM false
  OR titus.formation_response_work_authority_gate_v1() IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'original attribution opened a reviewer gate'; END IF;

 IF has_function_privilege('anon',
   'titus.capture_formation_response_original_v1()','EXECUTE')
  OR has_function_privilege('authenticated',
   'titus.capture_formation_response_original_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'original trigger function got browser EXECUTE'; END IF;

 IF EXISTS (
  SELECT 1 FROM pg_proc
  WHERE oid='titus.capture_formation_response_original_v1()'::regprocedure
    AND prosecdef
 ) THEN RAISE EXCEPTION 'provenance trigger became SECURITY DEFINER'; END IF;
END;
$test$;
SELECT 'PASS: first-draft original authorship, immutable text, legacy unverified and reviewer gates still closed' AS verdict;

DO $validate$
DECLARE rec record;
BEGIN
 FOR rec IN SELECT p.oid, p.proname
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN (
 'service_person_email_recovery_candidates_v1','service_begin_person_email_recovery_v1','service_verify_person_email_recovery_v1','service_approve_person_email_recovery_v1','service_prepare_person_email_recovery_v1','service_finish_person_email_recovery_v1','service_reject_person_email_recovery_v1'
 ) LOOP
 IF has_function_privilege('anon',rec.oid,'EXECUTE')
    OR has_function_privilege('authenticated',rec.oid,'EXECUTE')
    OR NOT has_function_privilege('service_role',rec.oid,'EXECUTE') THEN
  RAISE EXCEPTION 'Recovery public membrane role error: %',rec.proname;
 END IF;
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=rec.oid) THEN
  RAISE EXCEPTION 'Recovery delegation is missing its server-only custody: %',rec.proname;
 END IF;
 END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p
    WHERE p.oid='atlas.service_person_email_recovery_reviewer_v1(uuid,uuid)'::regprocedure
      AND pg_get_functiondef(p.oid) LIKE '%institutional_person_records%')
    OR NOT EXISTS (SELECT 1 FROM pg_proc p
      WHERE p.oid='atlas.service_person_email_recovery_candidates_v1(uuid)'::regprocedure
      AND pg_get_functiondef(p.oid) LIKE '%institutional_person_records%') THEN
    RAISE EXCEPTION 'Institutional Person evidence, not legacy seat membership, must govern recovery eligibility.';
  END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('service_person_email_recovery_candidates_v1','service_begin_person_email_recovery_v1','service_verify_person_email_recovery_v1','service_approve_person_email_recovery_v1','service_prepare_person_email_recovery_v1','service_finish_person_email_recovery_v1','service_reject_person_email_recovery_v1'))<>7 THEN
 RAISE EXCEPTION 'Incomplete recovery service membrane';
 END IF;
END $validate$;
-- Source candidate postconditions; run ONLY inside disposable PostgreSQL 17
-- AFTER applying candidate.sql to production-shaped, already synthetic schema.
-- Structural proof is NOT signed HTTP acceptance or permission to release.
DO $checks$
DECLARE v_rls boolean;v_force boolean;
BEGIN
 IF to_regclass('titus.learner_private_course_note_events_v1') IS NULL THEN
   RAISE EXCEPTION 'Missing private note table'; END IF;
 SELECT relrowsecurity,relforcerowsecurity INTO v_rls,v_force
 FROM pg_catalog.pg_class
 WHERE oid='titus.learner_private_course_note_events_v1'::regclass;
 IF v_rls IS NOT TRUE OR v_force IS NOT TRUE THEN
   RAISE EXCEPTION 'Private notes require RLS and FORCE RLS'; END IF;

 IF pg_catalog.has_table_privilege('anon','titus.learner_private_course_note_events_v1','SELECT')
    OR pg_catalog.has_table_privilege('authenticated','titus.learner_private_course_note_events_v1','SELECT')
    OR pg_catalog.has_table_privilege('service_role','titus.learner_private_course_note_events_v1','SELECT')
    OR pg_catalog.has_table_privilege('authenticated','titus.learner_private_course_note_events_v1','INSERT')
 THEN RAISE EXCEPTION 'Direct private note table permissions leaked'; END IF;

 IF pg_catalog.has_function_privilege('anon',
    'public.titus_learner_private_notes_read_self_api_v1(uuid)','EXECUTE')
    OR pg_catalog.has_function_privilege('anon',
    'public.titus_learner_private_note_create_self_api_v1(uuid,uuid,text)','EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',
    'public.titus_learner_private_notes_read_self_api_v1(uuid)','EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',
    'public.titus_learner_private_note_create_self_api_v1(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous/service function access leaked'; END IF;

 IF NOT pg_catalog.has_function_privilege('authenticated',
    'public.titus_learner_private_notes_read_self_api_v1(uuid)','EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated',
    'public.titus_learner_private_note_create_self_api_v1(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Only signed learner transports should execute'; END IF;

 IF pg_catalog.has_function_privilege('authenticated',
   'titus.learner_private_note_authority_self_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Private guard must not be directly executable'; END IF;
 IF NOT EXISTS(
 SELECT 1 FROM pg_catalog.pg_trigger
 WHERE tgrelid='titus.learner_private_course_note_events_v1'::regclass
   AND tgname='learner_private_notes_immutable_v1' AND NOT tgisinternal
 ) THEN RAISE EXCEPTION 'Missing immutability trigger'; END IF;

 IF NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_constraint
   WHERE conrelid='titus.learner_private_course_note_events_v1'::regclass
    AND conname='learner_private_note_idempotency_v1'
 ) THEN RAISE EXCEPTION 'Scoped idempotency constraint missing'; END IF;
END;
$checks$;

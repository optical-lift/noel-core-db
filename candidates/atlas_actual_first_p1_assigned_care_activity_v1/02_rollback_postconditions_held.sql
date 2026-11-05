-- P1 HELD structural/ACL postconditions for disposable PG clone.
-- Read/inspection only after 01 is applied in a ROLLBACK transaction.
-- Neither these checks nor a passing source test establish signed acceptance.
DO $p1$
DECLARE
  v_private oid:=pg_catalog.to_regprocedure(
    'atlas.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)');
  v_public oid:=pg_catalog.to_regprocedure(
    'public.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)');
BEGIN
  IF pg_catalog.to_regclass('atlas.assigned_care_activity_recognition_links_v1') IS NULL
    OR v_private IS NULL OR v_public IS NULL
    OR pg_catalog.to_regprocedure(
       'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)') IS NULL
    OR pg_catalog.to_regprocedure(
       'atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)') IS NULL
  THEN
    RAISE EXCEPTION 'P1 needs existing manual activity and typed physical Result source';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas'
      AND c.relname='assigned_care_activity_recognition_links_v1'
      AND c.relrowsecurity
  ) THEN RAISE EXCEPTION 'P1 provenance links require RLS'; END IF;
  IF pg_catalog.has_table_privilege(
       'anon','atlas.assigned_care_activity_recognition_links_v1','SELECT')
    OR pg_catalog.has_table_privilege(
       'authenticated','atlas.assigned_care_activity_recognition_links_v1','SELECT')
    OR pg_catalog.has_table_privilege(
       'service_role','atlas.assigned_care_activity_recognition_links_v1','SELECT')
  THEN RAISE EXCEPTION 'P1 evidence link table is not source private'; END IF;
  IF pg_catalog.has_function_privilege('anon',v_public,'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',v_public,'EXECUTE')
    OR NOT pg_catalog.has_function_privilege('authenticated',v_public,'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated',v_private,'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',v_private,'EXECUTE')
  THEN RAISE EXCEPTION 'P1 signed entrypoint privileges are incorrect'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid='atlas.assigned_care_activity_recognition_links_v1'::regclass
      AND t.tgname='assigned_care_activity_recognition_append_only_v1'
      AND NOT t.tgisinternal
  ) THEN RAISE EXCEPTION 'P1 evidence links need append-only trigger'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_constraint c
    WHERE c.conrelid='atlas.assigned_care_activity_recognition_links_v1'::regclass
      AND c.contype='u'
      AND pg_catalog.pg_get_constraintdef(c.oid) LIKE '%activity_log_id%'
  ) THEN RAISE EXCEPTION 'One source activity must have at most one Actual link'; END IF;
  RAISE NOTICE 'P1 structural, RLS and ACL postconditions passed in disposable clone; SIGNED TESTS OUTSTANDING';
END;
$p1$;

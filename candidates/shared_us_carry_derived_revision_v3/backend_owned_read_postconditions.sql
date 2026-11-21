-- HELD owner-scoped backend read: disposable role-level acceptance only.
-- Requires synthetic fixture from derived_revision_http_fixture.sql (4 events).
BEGIN;
DO $grants$
DECLARE v_sig text:='us.carry_read_owned_history_v3(uuid,uuid,bigint,integer)';
BEGIN
 IF pg_catalog.to_regprocedure(v_sig) IS NULL
  OR NOT pg_catalog.has_function_privilege('us_carry_backend',v_sig,'EXECUTE')
  OR pg_catalog.has_function_privilege('anon',v_sig,'EXECUTE')
  OR pg_catalog.has_function_privilege('authenticated',v_sig,'EXECUTE')
  OR pg_catalog.has_function_privilege('service_role',v_sig,'EXECUTE')
 THEN RAISE EXCEPTION 'Isolated backend reader EXECUTE grant is wrong'; END IF;
 IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles
   WHERE rolname='us_carry_backend' AND
     (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolinherit OR rolcanlogin))
 THEN RAISE EXCEPTION 'Backend role is privileged, inheriting or a login'; END IF;
 IF pg_catalog.pg_has_role('us_carry_backend','service_role','MEMBER')
 THEN RAISE EXCEPTION 'Backend role can assume service_role'; END IF;
 IF pg_catalog.has_table_privilege('us_carry_backend','us.carry_case_events_v1','SELECT')
 OR pg_catalog.has_table_privilege('us_carry_backend','us.carry_case_streams_v1','SELECT')
 OR pg_catalog.has_table_privilege('us_carry_backend','us.financial_expectation_lines','SELECT')
 OR pg_catalog.has_table_privilege('us_carry_backend','us.financial_expectation_revisions','INSERT')
 OR pg_catalog.has_table_privilege('us_carry_backend','us.financial_expectation_lines','INSERT')
 OR pg_catalog.has_function_privilege('us_carry_backend',
     'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 OR pg_catalog.has_function_privilege('us_carry_backend',
     'us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint,text)','EXECUTE')
 OR pg_catalog.has_function_privilege('us_carry_backend',
     'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'Dedicated backend role inherited broad legacy authority'; END IF;
END $grants$;
SET LOCAL ROLE us_carry_backend;
DO $proof$
DECLARE v jsonb;
BEGIN
 SELECT us.carry_read_owned_history_v3(
  'aaaaaaaa-2222-4222-8222-222222222222',
  'dddddddd-2222-4222-8222-222222222222',0,2) INTO v;
 IF (v->>'next_after_sequence')::bigint<>2
  OR v->>'has_more'<>'true'
  OR jsonb_array_length(v->'events')<>2
  OR v->'events'->0->>'event_type'<>'CASE_OPENED'
  OR v->'events'->1->>'event_type'<>'REVISION_SEALED'
  OR v ? 'owner_auth_user_id'
 THEN RAISE EXCEPTION 'Owned bounded event page mismatch: %',v; END IF;
 SELECT us.carry_read_owned_history_v3(
  'aaaaaaaa-2222-4222-8222-222222222222',
  'dddddddd-2222-4222-8222-222222222222',2,2) INTO v;
 IF (v->>'next_after_sequence')::bigint<>4
  OR v->>'has_more'<>'false'
  OR jsonb_array_length(v->'events')<>2
  OR v->'events'->0->>'event_type'<>'BASELINE_IMPORTED'
  OR v->'events'->1->>'event_type'<>'FORECAST_LINE_PROPOSED'
 THEN RAISE EXCEPTION 'Second owned history page mismatch: %',v; END IF;
 BEGIN
  PERFORM us.carry_read_owned_history_v3(
   'bbbbbbbb-2222-4222-8222-222222222222',
   'dddddddd-2222-4222-8222-222222222222',0,2);
  RAISE EXCEPTION 'Outsider read owned stream';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_owned_history_v3(
   'aaaaaaaa-2222-4222-8222-222222222222',
   'ffffffff-2222-4222-8222-222222222222',0,2);
  RAISE EXCEPTION 'Unknown stream was exposed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM us.carry_read_owned_history_v3(
   'aaaaaaaa-2222-4222-8222-222222222222',
   'dddddddd-2222-4222-8222-222222222222',0,51);
  RAISE EXCEPTION 'Unbounded page accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  PERFORM count(*) FROM us.carry_case_events_v1;
  RAISE EXCEPTION 'Backend role read raw event table';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM * FROM us.carry_adopt_derived_revision_v3(
   'aaaaaaaa-2222-4222-8222-222222222222',
   'dddddddd-2222-4222-8222-222222222222',
   'forged-adoption-01',4,repeat('0',64));
  RAISE EXCEPTION 'Backend role reached adoption function';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $proof$;
ROLLBACK;

-- HELD v3 complete source-permission postconditions. Disposable test only.
-- Run after finance + Carry v1 + dated v2 + v3 A/B/C/D source candidates.
-- NEVER run against production until independent governed release approval.
BEGIN;
DO $test$
DECLARE
 v_old text:='us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)';
 v_ordinary text:='us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)';
 v_core text:='us.carry_candidate_core_v3(uuid,uuid,bigint)';
 v_review text:='us.carry_review_derived_revision_v3(uuid,uuid,bigint)';
 v_adopt text:='us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint,text)';
BEGIN
 IF pg_catalog.has_table_privilege('service_role',
   'us.financial_expectation_revisions','INSERT') OR
    pg_catalog.has_table_privilege('service_role',
   'us.financial_expectation_lines','INSERT') THEN
   RAISE EXCEPTION 'Unrestricted revision/line INSERT remains available'; END IF;
 IF pg_catalog.has_function_privilege('service_role',v_old,'EXECUTE') THEN
   RAISE EXCEPTION 'Legacy unrestricted sealing still callable'; END IF;
 IF pg_catalog.to_regprocedure(v_ordinary) IS NULL OR
    pg_catalog.to_regprocedure(v_review) IS NULL OR
    pg_catalog.to_regprocedure(v_core) IS NULL OR
    pg_catalog.to_regprocedure(v_adopt) IS NULL THEN
   RAISE EXCEPTION 'Missing narrowed v3 ordinary/review/adopt function'; END IF;
 IF NOT pg_catalog.has_function_privilege('service_role',v_ordinary,'EXECUTE')
   OR NOT pg_catalog.has_function_privilege('service_role',v_review,'EXECUTE')
   OR NOT pg_catalog.has_function_privilege('service_role',v_adopt,'EXECUTE') THEN
   RAISE EXCEPTION 'Restricted Us service role lacks one v3 operation'; END IF;
 IF pg_catalog.has_function_privilege('service_role',v_core,'EXECUTE') THEN
   RAISE EXCEPTION 'Privileged source reconstruction core callable directly'; END IF;

 IF pg_catalog.has_function_privilege('anon',v_adopt,'EXECUTE') OR
    pg_catalog.has_function_privilege('authenticated',v_adopt,'EXECUTE') OR
    pg_catalog.has_function_privilege('anon',v_review,'EXECUTE') OR
    pg_catalog.has_function_privilege('authenticated',v_review,'EXECUTE') OR
    pg_catalog.has_function_privilege('anon',v_ordinary,'EXECUTE') OR
    pg_catalog.has_function_privilege('authenticated',v_ordinary,'EXECUTE') OR
    pg_catalog.has_function_privilege('anon',v_core,'EXECUTE') OR
    pg_catalog.has_function_privilege('authenticated',v_core,'EXECUTE') THEN
   RAISE EXCEPTION 'Private Carry v3 endpoint is directly client-callable'; END IF;

 IF pg_catalog.has_table_privilege('anon','us.carry_case_events_v1','SELECT') OR
    pg_catalog.has_table_privilege('authenticated','us.carry_case_events_v1','SELECT') OR
    pg_catalog.has_table_privilege('anon','us.financial_expectation_lines','SELECT') OR
    pg_catalog.has_table_privilege('authenticated','us.financial_expectation_lines','SELECT') THEN
   RAISE EXCEPTION 'Private Carry events/forecast directly readable by clients'; END IF;
END
$test$;
ROLLBACK;

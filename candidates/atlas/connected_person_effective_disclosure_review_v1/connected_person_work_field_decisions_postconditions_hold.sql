-- Run ONLY after held Work field decision SQL on disposable full-schema clone.
-- Structural verification, NOT a live signed governor/worker privacy result.
BEGIN;
DO $verify$
DECLARE
 v_table oid:=to_regclass(
  'atlas.connected_person_work_field_decision_events_v1');
 v_writer oid:=to_regprocedure(
  'atlas.governor_decide_connected_person_work_field_self_api_v1(uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)');
 v_writer_public oid:=to_regprocedure(
  'public.governor_decide_connected_person_work_field_self_api_v1(uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)');
 v_reader oid:=to_regprocedure(
  'atlas.connected_person_work_approved_fields_self_api_v1(uuid,uuid)');
 v_reader_public oid:=to_regprocedure(
  'public.connected_person_work_approved_fields_self_api_v1(uuid,uuid)');
 v_source oid:=to_regprocedure(
  'atlas.connected_person_work_field_source_eligible_v1(uuid,uuid,uuid)');
 v_field oid:=to_regprocedure(
  'atlas.connected_person_work_field_currently_approved_v1(uuid,uuid,uuid,text)');
 v_writer_code text;
 v_reader_code text;
BEGIN
 IF v_table IS NULL OR v_writer IS NULL OR v_writer_public IS NULL
   OR v_reader IS NULL OR v_reader_public IS NULL
   OR v_source IS NULL OR v_field IS NULL
 THEN
  RAISE EXCEPTION 'Native connected Person exact Work field decision source absent';
 END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table)
 OR has_table_privilege('authenticated',v_table,'SELECT')
 OR has_table_privilege('authenticated',v_table,'INSERT')
 OR has_table_privilege('authenticated',v_table,'UPDATE')
 OR has_table_privilege('authenticated',v_table,'DELETE')
 OR has_table_privilege('anon',v_table,'SELECT')
 THEN
  RAISE EXCEPTION 'Native Person exact Work field event table directly accessible';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_trigger t
  WHERE t.tgrelid=v_table AND t.tgname=
    'connected_person_work_field_decisions_append_only_v1'
  AND t.tgenabled IN ('O','A')
 ) THEN
  RAISE EXCEPTION 'Work field source receipts are not append-only';
 END IF;
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_writer)
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_writer_public)
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_reader)
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_reader_public)
 OR has_function_privilege('authenticated',v_writer,'EXECUTE')
 OR has_function_privilege('anon',v_writer,'EXECUTE')
 OR has_function_privilege('authenticated',v_reader,'EXECUTE')
 OR has_function_privilege('anon',v_reader,'EXECUTE')
 OR has_function_privilege('authenticated',v_field,'EXECUTE')
 OR has_function_privilege('authenticated',v_source,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_writer_public,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_reader_public,'EXECUTE')
 OR has_function_privilege('anon',v_writer_public,'EXECUTE')
 OR has_function_privilege('anon',v_reader_public,'EXECUTE')
 THEN
  RAISE EXCEPTION 'Native Work field RPC write/read privacy ACL envelope failed';
 END IF;
 v_writer_code:=pg_get_functiondef(v_writer);
 v_reader_code:=pg_get_functiondef(v_reader);
 IF v_writer_code NOT LIKE '%reality_access_self_api_v1%'
 OR v_writer_code NOT LIKE '%principal_has_ledger_authority_v1%'
 OR v_writer_code NOT LIKE '%connected_person_work_field_source_eligible_v1%'
 OR v_writer_code NOT LIKE '%p_expected_value_sha256%'
 OR v_writer_code NOT LIKE '%v_hash IS DISTINCT FROM p_expected_value_sha256%'
 OR v_writer_code NOT LIKE '%pg_advisory_xact_lock%'
 OR v_writer_code NOT LIKE '%INSERT INTO atlas.connected_person_work_field_decision_events_v1%'
 OR v_writer_code LIKE '%UPDATE atlas.connected_person_work_field_decision_events_v1%'
 OR v_reader_code NOT LIKE '%connected_person_work_field_source_eligible_v1%'
 OR v_reader_code NOT LIKE '%approved_value_sha256%'
 OR v_reader_code NOT LIKE '%sourceFieldDecisionsEnforced%'
 OR v_reader_code NOT LIKE '%not_found%'
 THEN
  RAISE EXCEPTION 'Native Work field writer/reader omitted exact source approval check';
 END IF;
 IF pg_get_functiondef(v_field) NOT LIKE '%pg_catalog.sha256%'
 OR pg_get_functiondef(v_field) NOT LIKE '%connected_person_work_field_source_eligible_v1%'
 OR pg_get_functiondef(v_source) NOT LIKE '%person_has_native_ledger_connection_v1%'
 OR pg_get_functiondef(v_source) NOT LIKE '%company_work_native_ledger_relevance%'
 OR pg_get_functiondef(v_source) NOT LIKE '%company_work_native_ledger_exact_source_v1%'
 THEN
  RAISE EXCEPTION 'Approved Work field helper lost exact source or content requirements';
 END IF;
END;
$verify$;
ROLLBACK;

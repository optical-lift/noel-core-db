-- Universal Company Decision: structural/ACL checks for future disposable clone.
-- No source execution, no domain admission test, no signed actor proof here.
DO $structure$
BEGIN
 IF pg_catalog.to_regclass('atlas.uni_ops_governed_source_cases_v1') IS NULL
 OR pg_catalog.to_regclass('atlas.uni_ops_governed_case_decision_events_v1') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)') IS NULL
 THEN RAISE EXCEPTION 'Company-neutral source decision case/writer/reader absent'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.uni_ops_governed_source_cases_v1'::regclass
    AND t.tgname='uni_ops_governed_source_case_immutable_v1'
    AND t.tgenabled<>'D'
 ) OR NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.uni_ops_governed_case_decision_events_v1'::regclass
    AND t.tgname='uni_ops_governed_case_decision_immutable_v1'
    AND t.tgenabled<>'D'
 ) THEN RAISE EXCEPTION 'Original source case/decision append-only guards missing'; END IF;

 IF NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_class c
  WHERE c.oid='atlas.uni_ops_governed_source_cases_v1'::regclass
    AND c.relrowsecurity AND c.relforcerowsecurity
 ) OR NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_class c
  WHERE c.oid='atlas.uni_ops_governed_case_decision_events_v1'::regclass
    AND c.relrowsecurity AND c.relforcerowsecurity
 ) THEN RAISE EXCEPTION 'Universal case private RLS and FORCE RLS absent'; END IF;

 IF pg_catalog.has_function_privilege('anon',
   'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)'::regprocedure,'EXECUTE')
 OR pg_catalog.has_function_privilege('authenticated',
   'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)'::regprocedure,'EXECUTE')
 OR pg_catalog.has_function_privilege('service_role',
   'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)'::regprocedure,'EXECUTE')
 OR pg_catalog.has_table_privilege('service_role',
    'atlas.uni_ops_governed_source_cases_v1','INSERT')
 OR pg_catalog.has_table_privilege('authenticated',
    'atlas.uni_ops_governed_case_decision_events_v1','SELECT')
 THEN RAISE EXCEPTION 'Private governing source/decision was exposed'; END IF;

 IF position('company_work_native_ledger_owner_self_v1' IN
   pg_catalog.pg_get_functiondef(
    'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Company governing Person/source proof removed'; END IF;

 RAISE NOTICE 'Source contract structurally present only; no first-party source-adapter proof or human signed acceptance run';
END;
$structure$;

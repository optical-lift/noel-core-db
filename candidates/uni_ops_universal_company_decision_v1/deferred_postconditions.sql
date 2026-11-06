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

 IF pg_catalog.to_regclass(
    'atlas.uni_ops_p3_owner_attention_decision_events_v1'
  ) IS NOT NULL THEN
   RAISE EXCEPTION 'Parallel farm-local and Company-neutral governor histories forbidden';
 END IF;


 IF pg_catalog.to_regclass(
  'atlas.uni_ops_farm_company_source_links_v1') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_farm_current_attention_attestation_self_held_v1(uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(uuid,uuid,uuid,text,text,uuid,uuid)') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(uuid,uuid,uuid,text,text,uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'Verified native Farm→Company case/decision/disclosure sources absent'; END IF;

 IF NOT EXISTS (
   SELECT 1 FROM pg_catalog.pg_trigger t
   WHERE t.tgrelid='atlas.uni_ops_farm_company_source_links_v1'::regclass
     AND t.tgname='uni_ops_farm_company_source_link_immutable_v1'
     AND t.tgenabled<>'D'
 ) THEN RAISE EXCEPTION 'Farm source/case immutable link lost'; END IF;

 IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint c
    JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
    WHERE t.oid='atlas.subject_disclosure_decision_events_v1'::regclass
      AND c.conname='subject_disclosure_supported_subject_v1'
      AND pg_catalog.pg_get_constraintdef(c.oid) NOT LIKE
        '%farm_operations%'
 ) THEN RAISE EXCEPTION 'Bounded native Subject disclosure source not admitted'; END IF;

 IF pg_catalog.has_function_privilege('authenticated',
    'atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(uuid,uuid)'::regprocedure,
    'EXECUTE')
 OR pg_catalog.has_function_privilege('service_role',
    'atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(uuid,uuid,uuid,text,text,uuid,text)'::regprocedure,
    'EXECUTE')
 OR pg_catalog.has_table_privilege('authenticated',
    'atlas.uni_ops_farm_company_source_links_v1','SELECT')
 THEN RAISE EXCEPTION 'Sensitive Farm/Company adapter exposed to API role'; END IF;

 IF position('uni_ops_company_governor_decide_source_case_self_held_v1' IN
  pg_catalog.pg_get_functiondef(
    'atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(uuid,uuid,uuid,text,text,uuid,uuid)'::regprocedure))=0
 THEN RAISE EXCEPTION 'Farm source wrapper no longer uses ONE company governor'; END IF;

 RAISE NOTICE 'Source contract structurally present only; no first-party source-adapter proof or human signed acceptance run';
END;
$structure$;

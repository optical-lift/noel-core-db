-- UNI-OPS-01 / ATLAS SOURCE-ONLY release-access GATE / HELD.
-- One known governor case UUID -> 17 non-Subject safe receipt fields.
-- Source-owned, no application route, Company decision writer, admission
-- operation, Work issuance, allocation, employee, or Principal Clock.
--
-- DO NOT APPLY THIS FILE TO PRODUCTION AS-IS OR BY DIRECT SQL.
-- Future release requires the canonical noel-core-db migration-source
-- generator, exact-version owner review, separately gated production
-- workflow, protected live custody, and real signed browser acceptance.
--
-- Exact prerequisite chain: source-backed Farm custody + P3 14/15,
-- one universal Company case and immutable decision history,
-- signed native Subject disclosure, farm->Company source adapter,
-- private one-case governor receipt, and DEFAULT-CLOSED public wrapper.
-- Never replay the old nine-source TEST-ONLY composite as a migration.
--
-- Verified positive and negative signed local GoTrue/PostgREST source:
-- protected run #42329379744, issue #2592 (DISPOSABLE PG17 ONLY).
-- Underlying private source and wrapper remain separately held PRs.
BEGIN;

DO $checked_company_receipt_release_gate$
DECLARE
  v_public oid;
  v_private oid;
  v_def text;
BEGIN
  v_public := pg_catalog.to_regprocedure(
    'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)'
  );
  v_private := pg_catalog.to_regprocedure(
    'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)'
  );
  IF v_public IS NULL OR v_private IS NULL THEN
    RAISE EXCEPTION
      'Company receipt source and default-closed transport must be live first'
      USING ERRCODE='42501';
  END IF;

  -- Live structural dependencies MUST already have their own exact
  -- migration receipts; this grant file does not install them or silently
  -- authorize one-time P3/Company source cutovers.
  IF pg_catalog.to_regclass('atlas.farm_crop_ledger_custody_v1')
       IS NULL
     OR pg_catalog.to_regclass('atlas.uni_ops_governed_source_cases_v1')
       IS NULL
     OR pg_catalog.to_regclass(
       'atlas.uni_ops_governed_case_decision_events_v1') IS NULL
     OR pg_catalog.to_regclass(
       'atlas.uni_ops_farm_company_source_links_v1') IS NULL
     OR pg_catalog.to_regprocedure(
       'atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(uuid,uuid)'
       ) IS NULL
     OR pg_catalog.to_regclass(
       'atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NOT NULL
  THEN
    RAISE EXCEPTION
      'One canonical source and no parallel Company governor required'
      USING ERRCODE='42501';
  END IF;

  -- SECURITY DEFINER executes under the source-defined owner; it is
  -- safe ONLY where current authenticated Person, exact Company Ledger
  -- governor, and known case are independently rechecked by the reader.
  IF NOT EXISTS(
      SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE p.oid=v_public AND n.nspname='public'
        AND p.prosecdef AND p.provolatile='s'
  ) OR NOT EXISTS(
      SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE p.oid=v_private AND n.nspname='atlas'
        AND p.prosecdef AND p.provolatile='s'
  )
  THEN
    RAISE EXCEPTION 'Reviewed stable owner-checked receipt contract changed'
      USING ERRCODE='42501';
  END IF;

  v_def := pg_catalog.pg_get_functiondef(v_public);
  IF pg_catalog.position('auth.uid() IS NULL' IN v_def)=0
     OR pg_catalog.position('atlas.current_person_id_v1()' IN v_def)=0
     OR pg_catalog.position(
       'atlas.uni_ops_company_governed_case_receipt_self_held_v1' IN v_def)=0
     OR pg_catalog.position(
       'realSourceSubjectDisclosureWasNotGrantedByThisReader' IN v_def)=0
     OR pg_catalog.position(
       'permissionToCreateOriginalWork' IN v_def)=0
     OR pg_catalog.position(
       'permissionToAutoCreateNextWork' IN v_def)=0
  THEN
    RAISE EXCEPTION 'Known governor/private receipt membrane changed'
      USING ERRCODE='42501';
  END IF;

  -- This is a separate grant step, not an implicit availability claim.
  -- Refuse if any API role already has execution or if the private
  -- Company writer/reader was accidentally made callable.
  IF pg_catalog.has_function_privilege(
       'authenticated',v_public,'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'anon',v_public,'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'service_role',v_public,'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'authenticated',v_private,'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'service_role',v_private,'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)',
       'EXECUTE'
     )
  THEN
    RAISE EXCEPTION 'Unexpected Company API role exposure before release'
      USING ERRCODE='42501';
  END IF;
END;
$checked_company_receipt_release_gate$;

-- The only access change, if a SEPARATELY approved versioned migration
-- eventually executes this source: this exact read-only known-case
-- function is callable by signed-in users, but the governed function
-- independently denies non-governors / missing or revoked case authority.
GRANT EXECUTE ON FUNCTION
  public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)
  TO authenticated;

DO $verify_exact_authenticated_only_receipt_gate$
BEGIN
  IF NOT pg_catalog.has_function_privilege(
       'authenticated',
       'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
       'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'anon',
       'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
       'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'service_role',
       'public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)',
       'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'atlas.uni_ops_company_governed_case_receipt_self_held_v1(uuid)',
       'EXECUTE')
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'atlas.uni_ops_company_governor_decide_source_case_self_held_v1(uuid,text,text,uuid,uuid)',
       'EXECUTE')
  THEN
    RAISE EXCEPTION 'Known-case receipt access exceeded approved scope'
      USING ERRCODE='42501';
  END IF;
END;
$verify_exact_authenticated_only_receipt_gate$;

-- Request local Data API schema-cache refresh after an authorized release.
NOTIFY pgrst, 'reload schema';
COMMIT;

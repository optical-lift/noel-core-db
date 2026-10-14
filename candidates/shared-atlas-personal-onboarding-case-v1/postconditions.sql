-- Structural and unauthorized-path proof. Run on disposable production-schema
-- clone only, AFTER applying candidate.sql. No individual account rows are
-- embedded here; live backfill is an independent authorized data transaction.

DO $proof$
DECLARE v_failed boolean;
BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM pg_constraint WHERE conrelid='atlas.implementation_cases'::regclass
   AND conname='implementation_cases_exact_origin_v1'
 ) THEN RAISE EXCEPTION 'Missing mutually exclusive real case origin constraint'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_indexes WHERE schemaname='atlas' AND tablename='implementation_cases'
   AND indexname='implementation_personal_case_per_person_uq'
 ) THEN RAISE EXCEPTION 'Missing exact one-person-one-personal-case uniqueness'; END IF;
 IF (SELECT is_nullable FROM information_schema.columns
      WHERE table_schema='atlas' AND table_name='implementation_cases'
      AND column_name='implementation_purchase_id') <> 'YES' THEN
  RAISE EXCEPTION 'Personal case still requires fake Stripe purchase';
 END IF;
 IF (SELECT column_default FROM information_schema.columns
      WHERE table_schema='atlas' AND table_name='implementation_cases'
      AND column_name='case_origin') NOT LIKE '%paid_institutional%' THEN
  RAISE EXCEPTION 'Existing commercial cases lost historical default';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.implementation_cases c
           WHERE (c.case_origin='paid_institutional' AND c.implementation_purchase_id IS NULL)
             OR (c.case_origin='personal_atlas' AND
                 (c.implementation_purchase_id IS NOT NULL OR c.personal_subject_person_entity_id IS NULL))) THEN
  RAISE EXCEPTION 'One or more case-origin rows violate exact provenance';
 END IF;
 -- Reject a synthetic non-purchased case without an actual verified Person.
 v_failed:=false;
 BEGIN
  INSERT INTO atlas.implementation_cases(
    case_origin,implementation_purchase_id,personal_subject_person_entity_id,state
  ) VALUES ('personal_atlas',null,null,'in_implementation');
 EXCEPTION WHEN check_violation THEN v_failed:=true;
 END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Anonymous ungrounded personal case admitted'; END IF;

 -- Any authenticated bearer without practitioner role must not view the desk.
 IF has_table_privilege('anon','atlas.implementation_cases','SELECT')
 OR has_table_privilege('authenticated','atlas.implementation_cases','SELECT')
 OR has_table_privilege('authenticated','atlas.implementation_cases','INSERT') THEN
  RAISE EXCEPTION 'Raw Implementation Case table privilege leaked to client';
 END IF;
 IF has_function_privilege('anon','public.implementation_workbench_self_api_v2()','EXECUTE')
 OR has_function_privilege('anon','public.ensure_personal_implementation_case_self_api_v1()','EXECUTE')
 OR has_function_privilege('authenticated','atlas.admit_existing_person_identity_self_v1()','EXECUTE') THEN
  RAISE EXCEPTION 'Direct or anonymous admission/Workbench authority leak';
 END IF;

 PERFORM set_config('request.jwt.claim.sub','',true);
 v_failed:=false;
 BEGIN
  PERFORM atlas.ensure_personal_implementation_case_self_v1();
 EXCEPTION WHEN insufficient_privilege THEN v_failed:=true;
 END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Anonymous human created a personal case'; END IF;

 IF pg_get_functiondef('atlas.record_stripe_implementation_purchase_v1(text,text,text,text,text,integer,integer,timestamp with time zone,timestamp with time zone,jsonb)'::regprocedure)
    NOT LIKE '%Valid Stripe Checkout Session id required%' THEN
  RAISE EXCEPTION 'Paid provider writer no longer enforces receipt identity';
 END IF;
 IF pg_get_functiondef('atlas.begin_personal_atlas_self_api_v1(text,text)'::regprocedure)
    NOT LIKE '%ensure_personal_implementation_case_self_v1%' OR
    pg_get_functiondef('atlas.begin_personal_atlas_self_api_v1(text,text)'::regprocedure)
    NOT LIKE '%admit_existing_person_identity_self_v1%' THEN
  RAISE EXCEPTION 'Actual personal admission command is not case/identity integrated';
 END IF;
 IF pg_get_functiondef('atlas.implementation_workbench_self_api_v1()'::regprocedure)
    NOT LIKE '%join atlas.implementation_purchases p%' THEN
  RAISE EXCEPTION 'Released V1 paid-only Workbench contract unexpectedly changed';
 END IF;
 IF pg_get_functiondef('atlas.implementation_workbench_self_api_v2()'::regprocedure)
    NOT LIKE '%LEFT JOIN atlas.implementation_purchases%' THEN
  RAISE EXCEPTION 'Versioned desk does not admit noncommercial personal cases';
 END IF;
END;
$proof$;
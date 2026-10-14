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
 -- Existing canonical Person UUIDs are authoritative even where a previously
 -- governed stable-key family differs from the old legacy Atlas namespace.
 IF pg_get_functiondef('atlas.admit_existing_person_identity_self_v1()'::regprocedure)
    LIKE '%v_entity.stable_key<>%' THEN
   RAISE EXCEPTION 'Existing canonical Person incorrectly tied to legacy stable-key prefix';
 END IF;
 IF pg_get_functiondef('atlas.ensure_personal_implementation_case_self_v1()'::regprocedure)
    NOT LIKE '%Verified active Atlas credential required%' THEN
   RAISE EXCEPTION 'Case self-writer does not recheck verified active Auth state';
 END IF;
 IF pg_get_functiondef('atlas.implementation_workbench_self_api_v2()'::regprocedure)
    NOT LIKE '%c.state NOT IN (''closed'',''cancelled'')%' THEN
   RAISE EXCEPTION 'Paid closed cases lost current active queue boundary';
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

-- This second section uses ONLY fixture identities from the disposable clone.
-- It tests the actual new and existing enrollment command, not mere DDL shape.
DO $two_humans$
DECLARE
  u1 uuid := '10000000-0000-4000-8000-000000000001';
  u2 uuid := '10000000-0000-4000-8000-000000000002';
  u3 uuid := '10000000-0000-4000-8000-000000000003';
  result jsonb;
  principal_a uuid;
  principal_b uuid;
  person_a uuid;
  person_b uuid;
  case_a uuid;
  case_b uuid;
  denied boolean;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',u1::text,true);
  result:=atlas.begin_personal_atlas_self_api_v1('Clone New User','America/Chicago');
  IF result->>'ok'<>'true' OR result->>'alreadyEstablished'<>'false' THEN
    RAISE EXCEPTION 'Fresh entitled personal signup did not establish Principal';
  END IF;
  SELECT id,person_id INTO STRICT principal_a,person_a FROM atlas.principals WHERE user_id=u1;
  IF NOT EXISTS(SELECT 1 FROM reality.auth_person_bindings b
     JOIN atlas.person_auth_credentials c ON c.id=b.id
     WHERE b.auth_user_id=u1 AND b.person_entity_id=person_a
       AND b.binding_state='active' AND b.retired_at IS NULL
       AND c.auth_user_id=u1 AND c.person_id=person_a)
     OR NOT EXISTS(SELECT 1 FROM personal.atlases pa
       WHERE pa.person_entity_id=person_a AND pa.native AND pa.atlas_state='active')
  THEN RAISE EXCEPTION 'Fresh user failed exact canonical Person/credential/native Atlas admission'; END IF;
  SELECT id INTO STRICT case_a FROM atlas.implementation_cases
    WHERE case_origin='personal_atlas' AND personal_subject_person_entity_id=person_a;
  IF NOT EXISTS(SELECT 1 FROM atlas.implementation_cases
    WHERE id=case_a AND implementation_purchase_id IS NULL AND state='in_implementation')
  THEN RAISE EXCEPTION 'Fresh Personal Atlas case used a purchase or wrong state'; END IF;
  result:=atlas.begin_personal_atlas_self_api_v1('Clone New User','America/Chicago');
  IF result->>'alreadyEstablished'<>'true' THEN
    RAISE EXCEPTION 'Repeated fresh signup did not take established path'; END IF;
  result:=atlas.ensure_personal_implementation_case_self_v1();
  IF result->>'created'<>'false'
     OR result->>'implementationCaseId'<>case_a::text THEN
    RAISE EXCEPTION 'Repeated admission duplicated original personal case'; END IF;

  PERFORM set_config('request.jwt.claim.sub',u2::text,true);
  SELECT id,person_id INTO STRICT principal_b,person_b FROM atlas.principals WHERE user_id=u2;
  IF EXISTS(SELECT 1 FROM reality.auth_person_bindings
            WHERE auth_user_id=u2 AND binding_state='active')
  THEN RAISE EXCEPTION 'Existing fixture was already canonical before admission'; END IF;
  result:=atlas.begin_personal_atlas_self_api_v1('Clone Existing User','America/Chicago');
  IF result->>'alreadyEstablished'<>'true' THEN
    RAISE EXCEPTION 'Existing established Principal not admitted idempotently'; END IF;
  IF (SELECT person_id FROM atlas.principals WHERE id=principal_b)<>person_b
     OR NOT EXISTS(SELECT 1 FROM reality.auth_person_bindings b
          WHERE b.auth_user_id=u2 AND b.person_entity_id=person_b
            AND b.binding_state='active' AND b.retired_at IS NULL)
  THEN RAISE EXCEPTION 'Existing Person was replaced rather than canonically admitted'; END IF;
  SELECT id INTO STRICT case_b FROM atlas.implementation_cases
    WHERE case_origin='personal_atlas' AND personal_subject_person_entity_id=person_b;
  result:=atlas.begin_personal_atlas_self_api_v1('Clone Existing User','America/Chicago');
  IF (SELECT count(*) FROM atlas.implementation_cases
     WHERE case_origin='personal_atlas' AND personal_subject_person_entity_id=person_b)<>1
  THEN RAISE EXCEPTION 'Existing user repeat created duplicate personal case'; END IF;
  IF case_a=case_b OR person_a=person_b OR principal_a=principal_b THEN
    RAISE EXCEPTION 'Two independent People were collapsed into one implementation case'; END IF;

  -- A normal Personal Atlas user remains forbidden from practitioner-only desk.
  result:=atlas.implementation_workbench_self_api_v2();
  IF result->>'ok'<>'false' OR result->>'code'<>'practitioner_authority_required'
  THEN RAISE EXCEPTION 'Normal person gained practitioner Workbench rights'; END IF;
  result:=atlas.implementation_case_self_api_v2(case_b);
  IF result->>'ok'<>'false' THEN
    RAISE EXCEPTION 'Normal person read practitioner-only case details'; END IF;

  -- A verified user WITHOUT purchase/invitation/entitlement cannot enroll.
  PERFORM set_config('request.jwt.claim.sub',u3::text,true);
  denied:=false;
  BEGIN
    PERFORM atlas.begin_personal_atlas_self_api_v1('Clone Unentitled','America/Chicago');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied OR EXISTS(SELECT 1 FROM atlas.principals WHERE user_id=u3) THEN
    RAISE EXCEPTION 'Unentitled person enrolled without an Atlas access basis'; END IF;
  denied:=false;
  BEGIN
    PERFORM atlas.ensure_personal_implementation_case_self_v1();
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'Unentitled user created an Implementation Case'; END IF;

  IF (SELECT count(*) FROM atlas.implementation_cases WHERE case_origin='personal_atlas')<>2
    OR (SELECT count(*) FROM atlas.implementation_purchases)<>0
    OR (SELECT count(*) FROM atlas.ledger_entitlements)<>0
  THEN RAISE EXCEPTION 'Fixture did not preserve two personal cases with zero fake commercial records'; END IF;

  PERFORM set_config('request.jwt.claim.sub','',true);
END;
$two_humans$;

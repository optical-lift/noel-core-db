-- Disposable clone postconditions: no alternate human type can govern
-- Foundry reviewer discovery; real Ledger relationship is the only positive.
DO $audit$
DECLARE v_source text;
BEGIN
  IF to_regprocedure('atlas.persons_share_active_native_ledger_v1(uuid,uuid)') IS NULL
  THEN RAISE EXCEPTION 'Missing canonical native-Ledger relationship proof'; END IF;
  IF has_function_privilege('authenticated',
     'atlas.persons_share_active_native_ledger_v1(uuid,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('anon',
     'atlas.persons_share_active_native_ledger_v1(uuid,uuid)'::regprocedure,'EXECUTE')
   OR has_function_privilege('service_role',
     'atlas.persons_share_active_native_ledger_v1(uuid,uuid)'::regprocedure,'EXECUTE')
  THEN RAISE EXCEPTION 'Relationship proof must not be an enumeratable public API'; END IF;
  SELECT pg_get_functiondef('atlas.list_foundry_source_custody_reviewers_self_api_v1(text)'::regprocedure)
  INTO v_source;
  IF v_source ILIKE '%organization_memberships%' OR
     v_source NOT ILIKE '%persons_share_active_native_ledger_v1%' OR
     v_source NOT ILIKE '%foundry_current_signed_principal_v1%'
  THEN RAISE EXCEPTION 'Foundry reviewer list still has alternative membership authority'; END IF;
  SELECT pg_get_functiondef('atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)'::regprocedure)
  INTO v_source;
  IF v_source ILIKE '%organization_memberships%' OR
     v_source NOT ILIKE '%persons_share_active_native_ledger_v1%' OR
     v_source NOT ILIKE '%foundry_current_signed_principal_v1%'
  THEN RAISE EXCEPTION 'Foundry source-case writer has alternative membership authority'; END IF;
  IF atlas.persons_share_active_native_ledger_v1(null::uuid,null::uuid)
     OR atlas.persons_share_active_native_ledger_v1(
        '00000000-0000-0000-0000-000000000000',
        '00000000-0000-0000-0000-000000000000')
  THEN RAISE EXCEPTION 'Invalid person identity must never connect'; END IF;
  IF has_function_privilege('anon',
   'public.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)'::regprocedure,'EXECUTE')
  THEN RAISE EXCEPTION 'Anonymous source review request exposed'; END IF;
END
$audit$;

-- Reviewer and owner share active native Ledger participation with no
-- employee/consultant/org membership. A disconnected signed Principal does not.
DO $truth$
DECLARE v_owner uuid;
        v_reviewer uuid;
        v_stranger uuid;
BEGIN
 SELECT person_id INTO v_owner FROM atlas.principals
   WHERE user_id='f1900000-0000-4000-8000-000000000001';
 SELECT person_id INTO v_reviewer FROM atlas.principals
   WHERE user_id='f1900000-0000-4000-8000-000000000002';
 SELECT person_id INTO v_stranger FROM atlas.principals
   WHERE user_id='f1900000-0000-4000-8000-000000000004';
 IF v_owner IS NULL OR v_reviewer IS NULL OR v_stranger IS NULL
 THEN RAISE EXCEPTION 'Required signed fixture Persons missing'; END IF;
 IF NOT atlas.persons_share_active_native_ledger_v1(v_owner,v_reviewer)
 THEN RAISE EXCEPTION 'Native Ledger reviewer relationship missing'; END IF;
 IF atlas.persons_share_active_native_ledger_v1(v_owner,v_stranger)
 THEN RAISE EXCEPTION 'Disconnected signed Principal gained relationship'; END IF;
 IF NOT atlas.persons_share_active_native_ledger_v1(
  v_owner,'f1900000-0000-4000-8000-000000000405'::uuid)
 THEN RAISE EXCEPTION 'Accountless recognized Person lost Ledger relation'; END IF;
 IF EXISTS (
  SELECT 1 FROM atlas.organization_memberships m
  WHERE m.user_id IN (
   'f1900000-0000-4000-8000-000000000001',
   'f1900000-0000-4000-8000-000000000002',
   'f1900000-0000-4000-8000-000000000004'))
 THEN RAISE EXCEPTION 'Test must not hide reliance on a legacy membership'; END IF;
END
$truth$;

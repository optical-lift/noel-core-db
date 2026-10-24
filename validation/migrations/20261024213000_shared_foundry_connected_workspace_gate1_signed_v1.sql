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

-- Fake owner and reviewer have shared canonical Ledger participation even
-- though no organization membership row exists; outsider does not.
DO $truth$
BEGIN
 IF NOT atlas.persons_share_active_native_ledger_v1(
   'f1900000-0000-4000-8000-000000000401',
   'f1900000-0000-4000-8000-000000000402')
 THEN RAISE EXCEPTION 'Native Ledger relation missing for signed reviewer'; END IF;
 IF atlas.persons_share_active_native_ledger_v1(
   'f1900000-0000-4000-8000-000000000401',
   'f1900000-0000-4000-8000-000000000403')
 THEN RAISE EXCEPTION 'Disconnected signed outsider admitted'; END IF;
 IF NOT atlas.persons_share_active_native_ledger_v1(
   'f1900000-0000-4000-8000-000000000401',
   'f1900000-0000-4000-8000-000000000405')
 THEN RAISE EXCEPTION 'Accountless canonical Person lost native Ledger relation'; END IF;
 IF EXISTS (
  SELECT 1 FROM atlas.organization_memberships m
  WHERE m.user_id IN (
   'f1900000-0000-4000-8000-000000000001',
   'f1900000-0000-4000-8000-000000000002',
   'f1900000-0000-4000-8000-000000000004'))
 THEN RAISE EXCEPTION 'Test must not hide reliance on a legacy membership'; END IF;
END
$truth$;

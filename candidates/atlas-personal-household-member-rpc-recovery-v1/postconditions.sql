-- Non-mutating postconditions for the disposable schema clone.
DO $verify$
DECLARE
  v_reader oid := to_regprocedure('atlas.personal_household_members_self_api_v1()');
  v_writer oid := to_regprocedure('atlas.personal_household_upsert_member_self_api_v1(jsonb)');
  v_public_reader oid := to_regprocedure('public.personal_household_members_self_api_v1()');
  v_public_writer oid := to_regprocedure('public.personal_household_upsert_member_self_api_v1(jsonb)');
BEGIN
  IF v_reader IS NULL OR v_writer IS NULL OR v_public_reader IS NULL OR v_public_writer IS NULL
    THEN RAISE EXCEPTION 'Personal Household RPC pair missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='atlas'
    AND tablename='household_members'
    AND indexname='household_members_personal_atlas_request_key_uidx')
    THEN RAISE EXCEPTION 'Household per-intent idempotency index missing'; END IF;
  IF NOT has_function_privilege('authenticated',v_public_reader,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_public_writer,'EXECUTE')
    OR has_function_privilege('anon',v_public_reader,'EXECUTE')
    OR has_function_privilege('anon',v_public_writer,'EXECUTE')
    THEN RAISE EXCEPTION 'Household public wrapper grants incorrect'; END IF;
END;
$verify$;

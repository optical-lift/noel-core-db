-- Offline disposable-clone postconditions; zero real-person mutations.
DO $audit$
DECLARE
 v_writer text;
 v_reader text;
BEGIN
 IF to_regprocedure('atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)') IS NULL
   OR to_regprocedure('atlas.list_foundry_reality_inputs_self_api_v1(text)') IS NULL
   OR to_regprocedure('public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)') IS NULL
   OR to_regprocedure('public.list_foundry_reality_inputs_self_api_v1(text)') IS NULL
 THEN RAISE EXCEPTION 'Missing Foundry evidence intake or reader'; END IF;
 IF has_function_privilege('anon','public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)','EXECUTE')
   OR has_function_privilege('anon','public.list_foundry_reality_inputs_self_api_v1(text)','EXECUTE')
   OR has_function_privilege('service_role','public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)','EXECUTE')
   OR has_function_privilege('service_role','public.list_foundry_reality_inputs_self_api_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'Public/anon/service access to Foundry human intake must be denied'; END IF;
 IF NOT has_function_privilege('authenticated','public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.list_foundry_reality_inputs_self_api_v1(text)','EXECUTE')
 THEN RAISE EXCEPTION 'Signed human transport grants missing'; END IF;

 SELECT pg_get_functiondef('atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)'::regprocedure)
 INTO v_writer;
 SELECT pg_get_functiondef('atlas.list_foundry_reality_inputs_self_api_v1(text)'::regprocedure)
 INTO v_reader;
 IF v_writer NOT ILIKE '%foundry_current_signed_principal_v1%'
   OR v_reader NOT ILIKE '%foundry_current_signed_principal_v1%'
   OR v_writer NOT ILIKE '%owner_principal_id=v_actor%'
   OR v_reader NOT ILIKE '%owner_principal_id=v_actor%'
   OR v_writer NOT ILIKE '%foundry.append_event%'
   OR v_writer NOT ILIKE '%segment_status%'
   OR v_writer NOT ILIKE '%canonical_mutation%'
   OR v_writer NOT ILIKE '%p_request_id%'
 THEN RAISE EXCEPTION 'Foundry owner/signed append/idempotency/unknown-state contract missing'; END IF;
 IF (SELECT count(*) FROM foundry.workspace_authority_registry_v1)<0
 THEN RAISE EXCEPTION 'Impossible baseline'; END IF;
END
$audit$;

-- Executing through the caller's role must fail outside an active signed
-- Principal's owned workspace. No fixture creates auth users in production.
DO $audit$
BEGIN
 BEGIN
  PERFORM atlas.capture_foundry_reality_input_self_api_v1(
    'foundry-does-not-exist',
    '2e26a41e-2918-414b-a029-a6e791520000',
    'Thursday is a recurring event.',
    '[{"text":"Thursday is a recurring event.","kind":"recurrence"}]'::jsonb,
    'operator_statement',null);
  RAISE EXCEPTION 'Unsigned write unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  PERFORM atlas.list_foundry_reality_inputs_self_api_v1('foundry-does-not-exist');
  RAISE EXCEPTION 'Unsigned read unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END
$audit$;

-- Postconditions for SOURCE CANDIDATE ONLY.
-- Run after candidate on protected disposable full-schema clone.
-- This is structural assurance, NOT a substitute for independent signed tests.
BEGIN;
DO $verify$
DECLARE v_internal oid;v_bridge oid;
BEGIN
  v_internal:=to_regprocedure('atlas.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)');
  v_bridge:=to_regprocedure('public.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)');
  IF v_internal IS NULL OR v_bridge IS NULL THEN
    RAISE EXCEPTION 'Governor-only disclosure review endpoints missing';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_internal)
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_bridge) THEN
    RAISE EXCEPTION 'Reviewed read membranes must maintain source checks';
  END IF;
  IF has_function_privilege('anon',v_internal,'EXECUTE')
    OR has_function_privilege('authenticated',v_internal,'EXECUTE')
    OR has_function_privilege('anon',v_bridge,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_bridge,'EXECUTE') THEN
    RAISE EXCEPTION 'Governor review API grants are wrong';
  END IF;
END;
$verify$;
ROLLBACK;

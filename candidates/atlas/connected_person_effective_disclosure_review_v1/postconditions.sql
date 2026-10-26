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
  -- Protected clone must prove the governor endpoint checks real Auth sessions
  -- through the canonical Person membrane, not merely a parseable JWT.
  IF pg_get_functiondef(v_internal) NOT LIKE '%atlas.reality_access_self_api_v1()%'
     OR pg_get_functiondef(v_internal) NOT LIKE '%subject_person.identity_state=%'
     OR pg_get_functiondef(v_internal) NOT LIKE '%principal_has_ledger_authority_v1%'
  THEN
    RAISE EXCEPTION 'Governor read guard lost signed-session or canonical Person check';
  END IF;
  -- The preliminary Work field preview is for the verified root governor,
  -- not a new recipient grant, audit certificate, or general institutional read.
  IF pg_get_functiondef(v_internal) NOT LIKE '%preliminaryWorkFieldReview%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%workFieldsRequireSeparateDecisions%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%candidateIsNotAnEffectiveDisclosureGrant%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%a.assignee_canonical_person_id=p_person_entity_id%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%rel.ledger_id=p_ledger_id%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%company_work_native_ledger_exact_source_v1%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%LIMIT 51%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%mayCertifyNonDisclosure%'
    OR pg_get_functiondef(v_internal) NOT LIKE '%verification_incomplete%'
  THEN
    RAISE EXCEPTION 'Governor preview has lost bounded exact Work source or noncertification safeguards';
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

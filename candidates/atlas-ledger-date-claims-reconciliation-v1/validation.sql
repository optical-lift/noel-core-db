-- Clone-only postconditions after applying candidate.sql.
-- NO source facts are added; no real identities are embedded in this test.
DO $checks$
DECLARE
  v_internal oid := to_regprocedure(
    'atlas.ledger_occurrence_date_evidence_self_api_v1(uuid,date,date,text,integer)');
  v_public oid := to_regprocedure(
    'public.ledger_occurrence_date_evidence_self_api_v1(uuid,date,date,text,integer)');
  v_is_protected boolean;
BEGIN
  IF v_internal IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Atlas date evidence function and public delegate are required';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_proc WHERE oid=v_internal
      AND prosecdef AND provolatile='s'
  ) THEN
    RAISE EXCEPTION 'Internal reader must be STABLE SECURITY DEFINER';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM pg_proc WHERE oid=v_public
      AND NOT prosecdef AND provolatile='s'
  ) THEN
    RAISE EXCEPTION 'Public delegate must be unprivileged STABLE SQL';
  END IF;

  IF has_function_privilege('anon',v_internal,'EXECUTE')
     OR has_function_privilege('anon',v_public,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_internal,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Date evidence reader must only expose authenticated EXECUTE';
  END IF;

  IF to_regclass('atlas.calendar_events') IS NOT NULL
     OR to_regclass('atlas.temporal_contributions') IS NOT NULL THEN
    RAISE EXCEPTION 'No catch-all calendar/events persistence may be introduced';
  END IF;

  -- In a clone without signed Auth transport, unauthenticated calls are denied.
  v_is_protected := false;
  BEGIN
    PERFORM atlas.ledger_occurrence_date_evidence_self_api_v1(
      NULL::uuid,date '2030-01-01',date '2030-01-01','UTC',1);
  EXCEPTION WHEN insufficient_privilege THEN
    v_is_protected := true;
  END;
  IF NOT v_is_protected THEN
    RAISE EXCEPTION 'Unauthenticated date evidence read did not fail closed';
  END IF;
END
$checks$;

SELECT jsonb_build_object(
  'contractVersion','ledger_occurrence_date_evidence_clone_postconditions_v1',
  'status','structural_pass',
  'authenticatedInternalExecute',
    has_function_privilege('authenticated',
      'atlas.ledger_occurrence_date_evidence_self_api_v1(uuid,date,date,text,integer)',
      'EXECUTE'),
  'anonymousPublicExecute',
    has_function_privilege('anon',
      'public.ledger_occurrence_date_evidence_self_api_v1(uuid,date,date,text,integer)',
      'EXECUTE'),
  'requiresSeparateSignedSessionFixture',true,
  'completePersonWideDateEncounterImplemented',false
) AS acceptance_receipt;

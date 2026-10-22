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


-- Runtime authorization and identity proof inside the disposable clone only.
-- Simulated request claims, not a signed GoTrue/PostgREST integration test.
-- Source fixture has two different same-date Occurrences, one source-title/time
-- disagreement, and a later canonical date with earlier overlay assertion.
BEGIN;
SET LOCAL ROLE authenticated;
DO $temporal_proof$
DECLARE
  v_read jsonb;
  v_november jsonb;
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_denied boolean := false;
  v_invalid_window boolean := false;
  v_ledger constant uuid := 'f5210000-0000-4000-8000-000000000014';
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
    'f5210000-0000-4000-8000-000000000401',true);
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object(
      'sub','f5210000-0000-4000-8000-000000000401',
      'role','authenticated',
      'session_id','f5210000-0000-4000-8000-000000000411'
    )::text,true);

  v_read := atlas.ledger_occurrence_date_evidence_self_api_v1(
    v_ledger,date '2030-10-30',date '2030-10-30','America/Chicago',20);

  IF v_read->>'contractVersion' <> 'ledger_occurrence_date_evidence_v1'
     OR jsonb_array_length(v_read->'occurrences') <> 3
     OR (v_read#>>'{coverage,eligibleOccurrenceCount}')::int <> 3
     OR v_read#>>'{coverage,wholeTemporalFieldComplete}' <> 'false' THEN
    RAISE EXCEPTION 'Ledger date evidence identity/coverage mismatch: %',v_read;
  END IF;

  SELECT value INTO v_a FROM jsonb_array_elements(v_read->'occurrences') a(value)
    WHERE value#>>'{sourceRef,id}'='f5210000-0000-4000-8000-000000000101';
  SELECT value INTO v_b FROM jsonb_array_elements(v_read->'occurrences') a(value)
    WHERE value#>>'{sourceRef,id}'='f5210000-0000-4000-8000-000000000102';
  SELECT value INTO v_c FROM jsonb_array_elements(v_read->'occurrences') a(value)
    WHERE value#>>'{sourceRef,id}'='f5210000-0000-4000-8000-000000000103';

  IF position('Synthetic Restricted Owner Planning' in v_read::text) > 0 THEN
    RAISE EXCEPTION 'Owner-only operational source leaked into shared date evidence';
  END IF;
  IF v_a IS NULL OR v_b IS NULL OR v_c IS NULL
     OR jsonb_array_length(v_a->'communityEventAssertions') <> 1
     OR jsonb_array_length(v_b->'communityEventAssertions') <> 1
     OR jsonb_array_length(v_c->'communityEventAssertions') <> 1 THEN
    RAISE EXCEPTION 'Unrelated same-day subjects were collapsed or lost';
  END IF;

  IF v_a#>>'{communityEventAssertions,0,differenceCandidates,title}' <> 'true'
     OR v_a#>>'{communityEventAssertions,0,differenceCandidates,startLocalTime}' <> 'true'
     OR v_a#>>'{communityEventAssertions,0,differenceCandidates,sourceStatus}' <> 'true'
     OR v_a#>>'{communityEventAssertions,0,differenceCandidates,endLocalTime}' <> 'false'
     OR v_a#>>'{communityEventAssertions,0,disposition}' <> 'not_adjudicated' THEN
    RAISE EXCEPTION 'Different source claims must remain visible but not adjudicated';
  END IF;

  IF v_b#>>'{communityEventAssertions,0,differenceCandidates,title}' <> 'false'
     OR v_b#>>'{communityEventAssertions,0,differenceCandidates,startLocalTime}' <> 'false'
     OR v_b#>>'{communityEventAssertions,0,differenceCandidates,sourceStatus}' <> 'false' THEN
    RAISE EXCEPTION 'Matching independent Event was incorrectly marked divergent';
  END IF;

  IF v_c#>>'{canonicalAssertion,civilDate}' <> '2030-11-01'
     OR v_c#>>'{communityEventAssertions,0,eventDate}' <> '2030-10-30'
     OR v_c#>>'{communityEventAssertions,0,differenceCandidates,date}' <> 'true'
     OR v_c#>'{communityEventAssertions,0,differenceCandidates,endLocalTime}' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'Source-local date and unknown canonical end-time wrongly handled';
  END IF;

  v_november := atlas.ledger_occurrence_date_evidence_self_api_v1(
    v_ledger,date '2030-11-01',date '2030-11-01','America/Chicago',20);
  IF jsonb_array_length(v_november->'occurrences') <> 1 OR
     v_november#>>'{occurrences,0,sourceRef,id}' <>
       'f5210000-0000-4000-8000-000000000103' THEN
    RAISE EXCEPTION 'November day must admit only canonical November source';
  END IF;

  BEGIN
    PERFORM atlas.ledger_occurrence_date_evidence_self_api_v1(
      v_ledger,date '2030-10-01',date '2030-12-01','America/Chicago',20);
  EXCEPTION WHEN invalid_parameter_value THEN
    v_invalid_window:=true;
  END;
  IF NOT v_invalid_window THEN
    RAISE EXCEPTION 'Unbounded multi-month scan was accepted';
  END IF;

  -- Outsider has legitimate synthetic Auth session and personal Atlas,
  -- but has no native connection to this Ledger. Even the Event titles
  -- and row count must never be disclosed.
  PERFORM set_config('request.jwt.claim.sub',
    'f5210000-0000-4000-8000-000000000402',true);
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object(
      'sub','f5210000-0000-4000-8000-000000000402',
      'role','authenticated',
      'session_id','f5210000-0000-4000-8000-000000000412'
    )::text,true);
  BEGIN
    PERFORM atlas.ledger_occurrence_date_evidence_self_api_v1(
      v_ledger,date '2030-10-30',date '2030-10-30','America/Chicago',20);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied:=true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Unconnected authenticated Person read Ledger Event claims';
  END IF;
END
$temporal_proof$;
ROLLBACK;

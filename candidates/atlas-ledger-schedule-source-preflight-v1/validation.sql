-- Clone postconditions only. Fixture is synthetic and never used in production.
DO $structural$
DECLARE
  v_api oid := to_regprocedure(
    'atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(uuid,uuid,uuid,timestamptz,timestamptz)');
  v_public oid := to_regprocedure(
    'public.ledger_occurrence_schedule_correction_preflight_self_api_v1(uuid,uuid,uuid,timestamptz,timestamptz)');
BEGIN
  IF v_api IS NULL OR v_public IS NULL THEN
    RAISE EXCEPTION 'Missing schedule preflight and API delegate';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_proc WHERE oid=v_api
    AND prosecdef AND provolatile='s'
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE oid=v_public
    AND NOT prosecdef AND provolatile='s'
  ) THEN
    RAISE EXCEPTION 'Correct STABLE / source-guarded privilege seams required';
  END IF;
  IF has_function_privilege('anon',v_api,'EXECUTE')
     OR has_function_privilege('anon',v_public,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_api,'EXECUTE')
     OR NOT has_function_privilege('authenticated',v_public,'EXECUTE') THEN
    RAISE EXCEPTION 'Untrusted roles must not invoke preflight';
  END IF;
  IF to_regclass('atlas.calendar_events') IS NOT NULL THEN
    RAISE EXCEPTION 'Do not create a universal mutable calendar table';
  END IF;
END
$structural$;

BEGIN;
SET LOCAL ROLE authenticated;
DO $proof$
DECLARE
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_member constant uuid := 'f5210000-0000-4000-8000-000000000401';
  v_outsider constant uuid := 'f5210000-0000-4000-8000-000000000402';
  v_ledger constant uuid := 'f5210000-0000-4000-8000-000000000014';
  v_org constant uuid := 'f5210000-0000-4000-8000-000000000010';
  v_a_id constant uuid := 'f5210000-0000-4000-8000-000000000101';
  v_b_id constant uuid := 'f5210000-0000-4000-8000-000000000102';
  v_c_id constant uuid := 'f5210000-0000-4000-8000-000000000103';
  v_denied boolean := false;
  v_invalid boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_member,'role','authenticated',
    'session_id','f5210000-0000-4000-8000-000000000411'
  )::text,true);

  v_a := public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
    v_org,v_ledger,v_a_id,NULL,NULL);
  IF v_a->>'contractVersion' <> 'ledger_occurrence_schedule_preflight_v1'
     OR v_a#>>'{scope,occurrenceId}' <> v_a_id::text
     OR v_a#>>'{canonicalSource,ref,id}' <> v_a_id::text
     OR v_a#>>'{operationalSource,title}' <> 'Synthetic Bonfire Evening'
     OR v_a#>>'{sourceComparisons,title}' <> 'true'
     OR v_a#>>'{sourceComparisons,startLocalTime}' <> 'true'
     OR v_a#>>'{sourceComparisons,sourceStatus}' <> 'true'
     OR v_a#>>'{sourceComparisons,endLocalTime}' <> 'false'
     OR v_a->>'approvedToCommit' <> 'false'
     OR v_a->>'readOnly' <> 'true' THEN
    RAISE EXCEPTION 'First Event source identity/conflict/blocked contract mismatch: %',v_a;
  END IF;
  IF v_a#>>'{dependentSourceImpact,evaluation}' <> 'not_authorized'
     OR v_a#>'{dependentSourceImpact,activeResourceClaimCount}' <> 'null'::jsonb
     OR v_a#>>'{coverage,communicationImpactComplete}' <> 'false'
     OR v_a->'commitBlockedReasons' @> '["source_owned_schedule_writer_not_released"]'::jsonb IS NOT TRUE THEN
    RAISE EXCEPTION 'Non-root participant learned source claim counts or bypassed write lock';
  END IF;
  IF v_a::text LIKE '%Synthetic Restricted Owner Planning%' THEN
    RAISE EXCEPTION 'Owner-only source leaked through shared Event preflight';
  END IF;

  v_b := atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
    v_org,v_ledger,v_b_id,
    '2030-10-30 13:00+00'::timestamptz,
    '2030-10-30 14:00+00'::timestamptz);
  IF v_b#>>'{sourceComparisons,startLocalTime}' <> 'false'
     OR v_b#>>'{proposedInterval,changesCanonicalInterval}' <> 'false'
     OR v_b#>>'{scope,occurrenceId}' <> v_b_id::text
     OR v_b#>>'{operationalSource,title}' <> 'Synthetic Early Movement' THEN
    RAISE EXCEPTION 'Independent same-day occurrence was conflated';
  END IF;

  v_c := atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
    v_org,v_ledger,v_c_id,
    '2030-10-30 16:00+00'::timestamptz,
    '2030-10-30 17:00+00'::timestamptz);
  IF v_c#>>'{sourceComparisons,date}' <> 'true'
     OR v_c#>'{sourceComparisons,endLocalTime}' <> 'null'::jsonb
     OR v_c#>>'{proposedInterval,changesCanonicalInterval}' <> 'true' THEN
    RAISE EXCEPTION 'Source-local day drift or unknown canonical end misrepresented';
  END IF;

  BEGIN
    PERFORM public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
      v_org,v_ledger,v_a_id,now(),now()-interval '1 hour');
  EXCEPTION WHEN invalid_parameter_value THEN v_invalid:=true;
  END;
  IF NOT v_invalid THEN
    RAISE EXCEPTION 'Invalid proposed interval must be rejected';
  END IF;

  v_denied:=false;
  BEGIN
    PERFORM public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
      'f5210000-0000-4000-8000-000000000011'::uuid,
      v_ledger,v_a_id,NULL,NULL);
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Unrelated Organization must be denied';
  END IF;

  -- Valid signed-style Auth claims but no Ledger seat.
  PERFORM set_config('request.jwt.claim.sub',v_outsider::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object(
    'sub',v_outsider,'role','authenticated',
    'session_id','f5210000-0000-4000-8000-000000000412',
    'user_metadata',jsonb_build_object('is_owner',true)
  )::text,true);
  v_denied:=false;
  BEGIN
    PERFORM public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
      v_org,v_ledger,v_a_id,NULL,NULL);
  EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Authenticated outsider with forged metadata read schedule preflight';
  END IF;
END
$proof$;
ROLLBACK;

SELECT jsonb_build_object(
  'contractVersion','atlas_ledger_occurrence_schedule_preflight_clone_proof_v1',
  'structuralPass',true,
  'syntheticSeatAndOutsiderProof',true,
  'actualSignedTransportProofPending',true,
  'sourceOwnedCorrectionWriterReleased',false,
  'noProductionFactsMutated',true
) AS acceptance_receipt;

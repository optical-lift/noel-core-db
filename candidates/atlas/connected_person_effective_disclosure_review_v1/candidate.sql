-- REVIEW-ONLY SOURCE CANDIDATE. DO NOT GENERATE/RELEASE WITHOUT GOVERNED PROOF.
-- Atlas Proper / Noel #2255; Atlas notebook #437.
-- A native Ledger Seat is participation, not information authority.
-- No global grant table, no automatic rights, no crop data, no app deployment.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.connected_person_effective_disclosure_review_self_api_v1(
  p_ledger_id uuid,
  p_person_entity_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $review$
DECLARE
  v_principal_id uuid;
  v_seat_id uuid;
  v_as_of timestamptz := statement_timestamp();
BEGIN
  -- Denied, missing, inactive, cross-Ledger and invalid targets have exactly
  -- the same response. Neither a native Seat nor a farm role grants data.
  IF auth.uid() IS NULL
     OR p_ledger_id IS NULL
     OR p_person_entity_id IS NULL
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  v_principal_id := atlas.current_principal_id_v1();
  IF v_principal_id IS NULL
     OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
       v_principal_id,p_ledger_id),false)
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  SELECT s.id INTO v_seat_id
  FROM ledger.seats s
  JOIN ledger.ledgers l ON l.id=s.ledger_id
    AND l.ledger_state='active' AND l.retired_at IS NULL
  WHERE s.ledger_id=p_ledger_id
    AND s.person_entity_id=p_person_entity_id
    AND s.seat_state='active' AND s.ended_at IS NULL
  LIMIT 1;

  IF v_seat_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  -- This is a Governor-only *incomplete* inventory shell. Until source
  -- enforcement, all actual access questions explicitly remain unresolved.
  -- Never make an absence of collected evidence look like absence of access.
  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','connected_person_effective_disclosure_review_v1',
    'readOnly',true,
    'asOf',v_as_of,
    'ledgerId',p_ledger_id,
    'personId',p_person_entity_id,
    'seatId',v_seat_id,
    'governorPrincipalId',v_principal_id,
    'verificationStatus','verification_incomplete',
    'mayCertifyNonDisclosure',false,
    'approvedAndProposed',jsonb_build_object(
      'status','source_contract_not_released',
      'currentDecisionInventoryVerified',false,
      'exclusionsVerified',false
    ),
    'effectiveExposure',jsonb_build_object(
      'status','not_yet_verified',
      'actualReadableRecords',NULL,
      'actualReadableFields',NULL,
      'actualWritableOperations',NULL,
      'historicalDepth',NULL,
      'revocationVerified',false
    ),
    'auditCoverage',jsonb_build_object(
      'legacyElevatedReaders','open',
      'directTableRls','open',
      'postgrestReachability','open',
      'signedPersonAndOutsider','open',
      'mediaAndCaches','open',
      'searchTodayIndexAndExports','open',
      'notebookSignedPreview','open'
    ),
    'sourceCoverage',jsonb_build_object(
      'sourceAdaptersReported',0,
      'verificationCompleteness','unknown',
      'sourceSpecificReviewRequired',true
    ),
    'authorityBoundary','native_ledger_root_governor_only',
    'targetSeatIsNotDisclosurePermission',true
  );
END;
$review$;

REVOKE ALL ON FUNCTION
  atlas.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.connected_person_effective_disclosure_review_self_api_v1(
  p_ledger_id uuid,p_person_entity_id uuid
) RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $bridge$
  SELECT atlas.connected_person_effective_disclosure_review_self_api_v1(
    p_ledger_id,p_person_entity_id
  );
$bridge$;

REVOKE ALL ON FUNCTION
  public.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
  public.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)
  TO authenticated;
COMMIT;

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
  v_actor_access jsonb;
  v_seat_id uuid;
  v_as_of timestamptz := statement_timestamp();
  v_work_review jsonb := '[]'::jsonb;
  v_work_candidate_count integer := 0;
BEGIN
  -- Denied, missing, inactive, cross-Ledger and invalid targets have exactly
  -- the same response. Neither a native Seat nor a farm role grants data.
  IF auth.uid() IS NULL
     OR p_ledger_id IS NULL
     OR p_person_entity_id IS NULL
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  -- Reuse the live session + canonical Person membrane. An unexpired JWT
  -- whose GoTrue session has been revoked is NOT a valid governor sign-in.
  v_actor_access := atlas.reality_access_self_api_v1();
  IF (v_actor_access->>'state') NOT IN ('ready','personal_atlas_required')
     OR (v_actor_access->'person'->>'id')
        IS DISTINCT FROM atlas.current_person_id_v1()::text
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
  JOIN reality.entities subject_person
    ON subject_person.id=s.person_entity_id
    AND subject_person.entity_kind='person'
    AND subject_person.identity_state='canonical'
  WHERE s.ledger_id=p_ledger_id
    AND s.person_entity_id=p_person_entity_id
    AND s.seat_state='active' AND s.ended_at IS NULL
  LIMIT 1;

  IF v_seat_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  -- Preliminary *governor-only* inputs for exact Work field decisions.
  -- This is NOT a proof of recipient access or a permission grant. In
  -- particular, displaying original instructions to the governor does
  -- not admit those instructions to the connected Person.
  --
  -- Bound reads to Work actually allocated to the target Person and
  -- attributed to this SAME native Ledger. Read no crop/bed/zone/history
  -- tables, attachments, media, farm snapshot, or full organization Work.
  -- Include completed originals for a future historical field decision.
  WITH governed_work AS MATERIALIZED (
    SELECT a.id AS allocation_id,w.id AS work_item_id,
      w.title,w.instructions,w.work_state,a.state AS allocation_state,
      a.allocated_at,
      title_dec.id AS title_field_decision_id,
      instructions_dec.id AS instructions_field_decision_id,
      CASE
        WHEN title_dec.id IS NULL THEN 'not_evaluated'
        WHEN title_dec.decision='deny' THEN 'denied'
        WHEN title_dec.valid_until<=v_as_of THEN 'expired'
        WHEN title_dec.approved_value_sha256 IS DISTINCT FROM
          pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
            w.title,'UTF8')),'hex') THEN 'source_changed'
        ELSE 'approved'
      END AS title_field_decision_status,
      CASE
        WHEN instructions_dec.id IS NULL THEN 'not_evaluated'
        WHEN instructions_dec.decision='deny' THEN 'denied'
        WHEN instructions_dec.valid_until<=v_as_of THEN 'expired'
        WHEN instructions_dec.approved_value_sha256 IS DISTINCT FROM
          pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
            w.instructions,'UTF8')),'hex') THEN 'source_changed'
        ELSE 'approved'
      END AS instructions_field_decision_status
    FROM atlas.work_allocations a
    JOIN atlas.work_items w ON w.id=a.work_item_id
      AND w.organization_id=a.organization_id
    LEFT JOIN LATERAL (
      SELECT e.id,e.decision,e.valid_until,e.approved_value_sha256
      FROM atlas.connected_person_work_field_decision_events_v1 e
      WHERE e.ledger_id=p_ledger_id AND e.organization_id=w.organization_id
        AND e.work_item_id=w.id
        AND e.recipient_person_entity_id=p_person_entity_id
        AND e.field_key='title'
      ORDER BY e.decided_at DESC,e.id DESC LIMIT 1
    ) title_dec ON true
    LEFT JOIN LATERAL (
      SELECT e.id,e.decision,e.valid_until,e.approved_value_sha256
      FROM atlas.connected_person_work_field_decision_events_v1 e
      WHERE e.ledger_id=p_ledger_id AND e.organization_id=w.organization_id
        AND e.work_item_id=w.id
        AND e.recipient_person_entity_id=p_person_entity_id
        AND e.field_key='instructions'
      ORDER BY e.decided_at DESC,e.id DESC LIMIT 1
    ) instructions_dec ON true
    WHERE a.assignee_canonical_person_id=p_person_entity_id
      AND a.assignee_membership_id IS NULL
      AND a.allocation_role='responsible'
      AND a.state IN ('active','completed')
      AND w.work_state IN ('open','completed')
      AND a.establishment_basis_kind IN
        ('person_connection_receiver_uptake',
         'delegated_under_standing_scope',
         'ledger_connection_direct_assignment')
      AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
      AND EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
        WHERE rel.organization_id=w.organization_id
          AND rel.work_item_id=w.id
          AND rel.ledger_id=p_ledger_id
          AND rel.attribution_state='active'
          AND (
            rel.evidence_kind IN ('owner_attested','participant_attested')
            OR (rel.evidence_kind='source_verified' AND EXISTS (
              SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
                w.id,p_ledger_id) proof
              WHERE proof.source_schema=rel.source_schema
                AND proof.source_table=rel.source_table
                AND proof.source_id=rel.source_id
            ))
          )
      )
    ORDER BY a.id
    LIMIT 51
  ), numbered AS (
    SELECT *,row_number() OVER (ORDER BY allocation_id) AS rn
    FROM governed_work
  )
  SELECT
    COALESCE(jsonb_agg(jsonb_build_object(
      'workItemId',work_item_id,
      'allocationId',allocation_id,
      'workState',work_state,
      'allocationState',allocation_state,
      'titleCandidate',title,
      'instructionsCandidate',instructions,
      'titleCandidateSha256',CASE WHEN title IS NULL THEN NULL
        ELSE pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
          title,'UTF8')),'hex') END,
      'instructionsCandidateSha256',CASE WHEN instructions IS NULL THEN NULL
        ELSE pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
          instructions,'UTF8')),'hex') END,
      'titleFieldDecisionStatus',title_field_decision_status,
      'instructionsFieldDecisionStatus',instructions_field_decision_status,
      'titleFieldDecisionId',title_field_decision_id,
      'instructionsFieldDecisionId',instructions_field_decision_id,
      'candidateIsNotAnEffectiveDisclosureGrant',true
    ) ORDER BY allocation_id) FILTER (WHERE rn<=50),'[]'::jsonb),
    COUNT(*)::integer
  INTO v_work_review,v_work_candidate_count
  FROM numbered;

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
    'preliminaryWorkFieldReview',jsonb_build_object(
      'status','governor_review_inputs_only',
      'notAnActualAccessInventory',true,
      'workFieldsRequireSeparateDecisions',true,
      'presentedCandidateCount',jsonb_array_length(v_work_review),
      'hasMoreCandidateWork',v_work_candidate_count>50,
      'items',v_work_review
    ),
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

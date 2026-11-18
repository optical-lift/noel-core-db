-- U2F 06 HELD SOURCE CANDIDATE. NOT A MIGRATION OR PRODUCTION INSTALL.
-- Two private SECURITY DEFINER lifecycle operations and one private
-- SECURITY INVOKER read. Disposable fictional PostgreSQL 17 tests ONLY.
-- Requires a real, current authenticated human representing exactly the
-- original root Principal to reaffirm one existing root in one native Ledger.
-- Does not adjudicate original authority, empower a nonhuman carrier,
-- activate any U2F command, replace the old authority evaluator or authorize
-- legacy table retirement. No browser/agent/service_role EXECUTE is granted.
--
-- Original source: atlas.principal_ledger_authorities
-- Native participation: ledger.ledgers / ledger.seats
-- One native candidate: ledger.seat_responsibilities
-- Explicit audit: ledger.actions
--
-- This is a ONE-TIME historical cutover candidate. Native seat-responsibilities
-- UNIQUE(seat_id,responsibility_key) forbids re-granting the same key after
-- revocation. Do not delete or rewrite old evidence to permit another grant.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '20s';

CREATE FUNCTION atlas.uni_ops_u2f_root_reaffirm_held_v1(
  p_original_root_id uuid,
  p_native_ledger_id uuid,
  p_explicit_attestation text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $u2f_reaffirm$
DECLARE
  v_actor uuid := auth.uid();
  v_session_claim text;
  v_original atlas.principal_ledger_authorities%ROWTYPE;
  v_principal atlas.principals%ROWTYPE;
  v_seat ledger.seats%ROWTYPE;
  v_action_id uuid;
  v_native_responsibility_id uuid;
BEGIN
  -- This is a source-only guard. In a real signed HTTP request GoTrue must
  -- authenticate the JWT; the candidate additionally requires its exact
  -- session_id still exists for the same Person's auth.user in auth.sessions.
  -- A made-up request.jwt claim in a privileged SQL session is NOT signed auth.
  v_session_claim := NULLIF(pg_catalog.btrim(auth.jwt()->>'session_id'),'');
  IF v_actor IS NULL OR v_session_claim IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions ss
    WHERE ss.id=v_session_claim::uuid AND ss.user_id=v_actor
      AND (ss.not_after IS NULL OR ss.not_after>pg_catalog.now())
  ) THEN
    RAISE EXCEPTION 'Current signed session required'
      USING ERRCODE='42501';
  END IF;
  IF v_actor IS NULL
     OR p_original_root_id IS NULL OR p_native_ledger_id IS NULL
     OR p_explicit_attestation IS DISTINCT FROM 'I reaffirm this exact Ledger authority'
  THEN
    RAISE EXCEPTION 'Exact signed human reaffirmation required'
      USING ERRCODE='42501';
  END IF;

  -- Lock original and seat; a historic owner/role label or any Ledger seat
  -- alone cannot create the candidate.
  SELECT * INTO v_original
  FROM atlas.principal_ledger_authorities r
  WHERE r.id=p_original_root_id AND r.ledger_id=p_native_ledger_id
    AND r.authority_kind='root_governing'
    AND r.status='active' AND r.ended_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Current exact source root required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_principal FROM atlas.principals p
  WHERE p.id=v_original.principal_id
    AND p.user_id=v_actor AND p.status='active'
    AND p.person_id IS NOT NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Signed source Principal/Person mismatch' USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atlas.ledgers legacy
    JOIN ledger.ledgers native ON native.id=legacy.id
    WHERE legacy.id=p_native_ledger_id AND legacy.status='active'
      AND native.ledger_state='active' AND native.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Exact active native Ledger source missing' USING ERRCODE='42501';
  END IF;

  SELECT s.* INTO v_seat
  FROM ledger.seats s
  WHERE s.ledger_id=p_native_ledger_id
    AND s.person_entity_id=v_principal.person_id
    AND s.seat_state='active'
    AND s.began_at<=pg_catalog.now()
    AND (s.ended_at IS NULL OR s.ended_at>pg_catalog.now())
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Current exact native Person Seat required' USING ERRCODE='42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM ledger.seat_responsibilities sr
    WHERE sr.seat_id=v_seat.id
      AND sr.responsibility_key='ledger_governing_root_v1'
  ) THEN
    RAISE EXCEPTION 'Root already recorded or historically ended; no overwrite/regrant'
      USING ERRCODE='23505';
  END IF;

  -- No backdating. This signed human action is NOT independent adjudication
  -- of the historical auto-backfill; its source evidence remains in the old
  -- record until a separate governed cutover.
  INSERT INTO ledger.actions(
    ledger_id,action_kind,performed_by_entity_id,occurred_at,
    payload,provenance,idempotency_key
  )
  VALUES (
    p_native_ledger_id,'u2f_root_source_reaffirmation_held_v1',
    v_principal.person_id,pg_catalog.now(),
    pg_catalog.jsonb_build_object('explicitAttestation',p_explicit_attestation,
      'adjudicationStatus','pending_independent_source_review'),
    pg_catalog.jsonb_build_object(
      'originalRootReceiptId',v_original.id,
      'source','atlas.principal_ledger_authorities',
      'principalId',v_principal.id,
      'signedUserId',v_actor),
    'u2f:root:reaffirm:'||v_original.id::text
  )
  RETURNING id INTO v_action_id;

  INSERT INTO ledger.seat_responsibilities(
    seat_id,responsibility_key,title,responsibility_state,scope,began_at
  )
  VALUES (
    v_seat.id,'ledger_governing_root_v1','Governing-root reaffirmation (HELD)',
    'active',
    pg_catalog.jsonb_build_object(
      'sourceKind','historical_root_reaffirmation_held',
      'originalRootReceiptId',v_original.id,
      'nativeLedgerId',p_native_ledger_id,
      'principalId',v_principal.id,
      'signedPersonId',v_principal.person_id,
      'auditActionId',v_action_id,
      'originalBasisFingerprint',pg_catalog.md5(v_original.basis),
      'independentSourceAdjudication',false,
      'candidateDoesNotAuthorizeWork',true
    ),pg_catalog.now()
  )
  RETURNING id INTO v_native_responsibility_id;

  RETURN pg_catalog.jsonb_build_object(
    'candidateRecorded',true,
    'nativeResponsibilityId',v_native_responsibility_id,
    'independentSourceAdjudication',false,
    'governingRootVerified',false,
    'delegatedWorkAuthorized',false,
    'legacyRootRetirementAuthorized',false,
    'sourceOnly',true
  );
END
$u2f_reaffirm$;

CREATE FUNCTION atlas.uni_ops_u2f_root_revoke_held_v1(
  p_native_responsibility_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $u2f_revoke$
DECLARE
  v_actor uuid := auth.uid();
  v_session_claim text;
  v_resp ledger.seat_responsibilities%ROWTYPE;
  v_seat ledger.seats%ROWTYPE;
  v_original atlas.principal_ledger_authorities%ROWTYPE;
  v_principal atlas.principals%ROWTYPE;
BEGIN
  -- This is a source-only guard. In a real signed HTTP request GoTrue must
  -- authenticate the JWT; the candidate additionally requires its exact
  -- session_id still exists for the same Person's auth.user in auth.sessions.
  -- A made-up request.jwt claim in a privileged SQL session is NOT signed auth.
  v_session_claim := NULLIF(pg_catalog.btrim(auth.jwt()->>'session_id'),'');
  IF v_actor IS NULL OR v_session_claim IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions ss
    WHERE ss.id=v_session_claim::uuid AND ss.user_id=v_actor
      AND (ss.not_after IS NULL OR ss.not_after>pg_catalog.now())
  ) THEN
    RAISE EXCEPTION 'Current signed session required'
      USING ERRCODE='42501';
  END IF;
  IF v_actor IS NULL OR p_native_responsibility_id IS NULL
     OR pg_catalog.length(pg_catalog.btrim(COALESCE(p_reason,'')))<4
  THEN
    RAISE EXCEPTION 'Signed Person and nonblank revocation reason required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_resp FROM ledger.seat_responsibilities sr
  WHERE sr.id=p_native_responsibility_id
    AND sr.responsibility_key='ledger_governing_root_v1'
    AND sr.scope->>'sourceKind'='historical_root_reaffirmation_held'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exact native historical responsibility required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_seat FROM ledger.seats s WHERE s.id=v_resp.seat_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original native seat missing' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_original
  FROM atlas.principal_ledger_authorities r
  WHERE r.id=(v_resp.scope->>'originalRootReceiptId')::uuid
    AND r.ledger_id=v_seat.ledger_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Exact historical root receipt missing'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_principal FROM atlas.principals p
  WHERE p.id=v_original.principal_id AND p.status='active'
    AND p.user_id=v_actor AND p.person_id=v_seat.person_entity_id
    AND p.id=(v_resp.scope->>'principalId')::uuid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only original signed Principal may revoke this candidate'
      USING ERRCODE='42501';
  END IF;

  IF v_resp.responsibility_state='ended' THEN
    RETURN pg_catalog.jsonb_build_object(
      'revoked',true,'replayed',true,
      'governingRootVerified',false,'delegatedWorkAuthorized',false,
      'sourceOnly',true
    );
  END IF;
  IF v_resp.responsibility_state<>'active' OR v_resp.ended_at IS NOT NULL THEN
    RAISE EXCEPTION 'Root candidate state incompatible with revocation'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO ledger.actions(
    ledger_id,action_kind,performed_by_entity_id,occurred_at,
    payload,provenance,idempotency_key
  )
  VALUES (
    v_seat.ledger_id,'u2f_root_source_reaffirmation_revoked_held_v1',
    v_principal.person_id,pg_catalog.now(),
    pg_catalog.jsonb_build_object(
      'nativeResponsibilityId',v_resp.id,
      'reason',pg_catalog.btrim(p_reason)),
    pg_catalog.jsonb_build_object(
      'originalRootReceiptId',v_original.id,
      'sourceAdmissionActionId',v_resp.scope->>'auditActionId',
      'signedUserId',v_actor),
    'u2f:root:revoke:'||v_resp.id::text
  );

  UPDATE ledger.seat_responsibilities
    SET responsibility_state='ended',ended_at=pg_catalog.now(),updated_at=pg_catalog.now()
  WHERE id=v_resp.id;

  RETURN pg_catalog.jsonb_build_object(
    'revoked',true,'replayed',false,
    'governingRootVerified',false,'delegatedWorkAuthorized',false,
    'sourceOnly',true
  );
END
$u2f_revoke$;

CREATE FUNCTION atlas.uni_ops_u2f_root_candidate_current_held_v1(
  p_original_root_id uuid,p_native_ledger_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path TO ''
AS $u2f_current$
DECLARE
  v_candidate_current boolean := false;
BEGIN
  IF p_original_root_id IS NOT NULL AND p_native_ledger_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1
      FROM atlas.principal_ledger_authorities r
      JOIN atlas.principals p ON p.id=r.principal_id
        AND p.status='active' AND p.person_id IS NOT NULL
      JOIN atlas.ledgers old_l ON old_l.id=r.ledger_id
        AND old_l.status='active'
      JOIN ledger.ledgers native_l ON native_l.id=r.ledger_id
        AND native_l.ledger_state='active' AND native_l.retired_at IS NULL
      JOIN ledger.seats s ON s.ledger_id=native_l.id
        AND s.person_entity_id=p.person_id
        AND s.seat_state='active'
        AND s.began_at<=pg_catalog.now()
        AND (s.ended_at IS NULL OR s.ended_at>pg_catalog.now())
      JOIN ledger.seat_responsibilities sr ON sr.seat_id=s.id
        AND sr.responsibility_key='ledger_governing_root_v1'
        AND sr.responsibility_state='active'
        AND sr.began_at<=pg_catalog.now()
        AND (sr.ended_at IS NULL OR sr.ended_at>pg_catalog.now())
      JOIN ledger.actions act ON act.id=(sr.scope->>'auditActionId')::uuid
        AND act.ledger_id=native_l.id
        AND act.action_kind='u2f_root_source_reaffirmation_held_v1'
        AND act.performed_by_entity_id=p.person_id
        AND act.provenance->>'originalRootReceiptId'=r.id::text
        AND act.provenance->>'principalId'=p.id::text
      WHERE r.id=p_original_root_id AND r.ledger_id=p_native_ledger_id
        AND r.authority_kind='root_governing'
        AND r.status='active' AND r.ended_at IS NULL
        AND sr.scope->>'originalRootReceiptId'=r.id::text
        AND sr.scope->>'nativeLedgerId'=native_l.id::text
        AND sr.scope->>'principalId'=p.id::text
        AND sr.scope->>'signedPersonId'=p.person_id::text
        AND sr.scope->>'originalBasisFingerprint'=pg_catalog.md5(r.basis)
        AND sr.scope->>'independentSourceAdjudication'='false'
    ) INTO v_candidate_current;
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'candidateSourceCurrent',v_candidate_current,
    'independentSourceAdjudication',false,
    'governingRootVerified',false,
    'delegatedWorkAuthorized',false,
    'originalWorkCreated',false,
    'legacyRootRetirementAuthorized',false,
    'sourceOnly',true
  );
END
$u2f_current$;

-- A later independent release must review SECURITY DEFINER owner/search_path,
-- all direct DML access, immutable historical provenance, and exact signed
-- actor enforcement before exposing even a scoped human RPC.
REVOKE ALL ON FUNCTION
 atlas.uni_ops_u2f_root_reaffirm_held_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_u2f_root_revoke_held_v1(uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_u2f_root_candidate_current_held_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

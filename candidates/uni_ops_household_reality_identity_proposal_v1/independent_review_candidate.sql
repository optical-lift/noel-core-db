-- UNI-OPS-01 U5: INDEPENDENT native Household->Reality identity review candidate.
-- HELD SOURCE: depends on proposal candidate.sql; do not deploy or merge.
-- A review responsibility must be separately source-issued in Reality;
-- this file does not create any responsibility, role, grant or identity.
BEGIN;

CREATE TABLE atlas.uni_ops_household_reality_identity_reviews_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  proposal_id uuid NOT NULL REFERENCES
    atlas.uni_ops_household_reality_identity_proposals_v1(id) ON DELETE RESTRICT,
  event_kind text NOT NULL CHECK
    (event_kind IN ('approved','rejected','revoked')),
  source_action_id uuid NOT NULL UNIQUE,
  reviewed_source_evidence_id uuid REFERENCES
    atlas.evidence_records(id) ON DELETE RESTRICT,
  reviewed_evidence_sha256 text NOT NULL
    CHECK (reviewed_evidence_sha256 ~ '^[0-9a-f]{64}
  reviewer_principal_id uuid NOT NULL REFERENCES
    atlas.principals(id) ON DELETE RESTRICT,
  reviewer_person_entity_id uuid NOT NULL REFERENCES
    reality.entities(id) ON DELETE RESTRICT,
  reviewer_responsibility_relation_id uuid NOT NULL REFERENCES
    reality.responsibility_relations(id) ON DELETE RESTRICT,
  prior_review_event_id uuid REFERENCES
    atlas.uni_ops_household_reality_identity_reviews_v1(id)
    ON DELETE RESTRICT,
  decision_basis text NOT NULL
    CHECK (length(btrim(decision_basis)) BETWEEN 20 AND 4000),
  decided_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uni_ops_identity_approve_evidence_v1 CHECK (
    event_kind <> 'approved' OR reviewed_source_evidence_id IS NOT NULL
  ),
  CONSTRAINT uni_ops_identity_disclosure_receipts_v1 CHECK (
    (event_kind='approved'
      AND identity_disclosure_event_id IS NOT NULL
      AND condition_disclosure_event_id IS NOT NULL)
    OR
    (event_kind<>'approved'
      AND identity_disclosure_event_id IS NULL
      AND condition_disclosure_event_id IS NULL)
  ),
  CONSTRAINT uni_ops_identity_revoke_prior_v1 CHECK (
    (event_kind='revoked')=(prior_review_event_id IS NOT NULL)
  )
);
CREATE INDEX uni_ops_household_review_by_proposal_v1
  ON atlas.uni_ops_household_reality_identity_reviews_v1
  (proposal_id,event_sequence DESC);

ALTER TABLE atlas.uni_ops_household_reality_identity_reviews_v1
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.uni_ops_household_reality_identity_reviews_v1
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_household_reality_review_immutable_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $guard$
BEGIN
  RAISE EXCEPTION 'Household Reality review events are immutable'
    USING ERRCODE='42501';
END;
$guard$;
CREATE TRIGGER uni_ops_household_reality_review_history_v1
BEFORE UPDATE OR DELETE ON atlas.uni_ops_household_reality_identity_reviews_v1
FOR EACH ROW EXECUTE FUNCTION
  atlas.uni_ops_household_reality_review_immutable_guard_v1();

CREATE FUNCTION atlas.uni_ops_review_household_reality_identity_internal_v1(
  p_proposal_id uuid,
  p_event_kind text,
  p_reviewed_source_evidence_id uuid,
  p_reviewed_evidence_sha256 text,
  p_decision_basis text,
  p_source_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE
  v_principal_id uuid;
  v_person_entity_id uuid;
  v_relation_id uuid;
  v_proposal atlas.uni_ops_household_reality_identity_proposals_v1%ROWTYPE;
  v_latest atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_existing atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_event atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_governor_person_id uuid;
  v_identity_disclosure_event_id uuid;
  v_condition_disclosure_event_id uuid;
BEGIN
  IF p_proposal_id IS NULL OR p_source_action_id IS NULL
     OR p_event_kind IS NULL
     OR p_event_kind NOT IN ('approved','rejected','revoked')
     OR coalesce(p_reviewed_evidence_sha256,'') !~ '^[0-9a-f]{64}$'
     OR length(btrim(coalesce(p_decision_basis,''))) NOT BETWEEN 20 AND 4000
  THEN
    RAISE EXCEPTION 'Exact evidence, review action and decision basis required'
      USING ERRCODE='42501';
  END IF;

  -- True current session, not a cached JWT role or caller-provided reviewer.
  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL OR
     v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Signed independent reviewer Principal required'
      USING ERRCODE='42501';
  END IF;
  v_person_entity_id:=atlas.current_person_id_v1();
  IF v_person_entity_id IS NULL THEN
    RAISE EXCEPTION 'Canonical independent reviewer Person required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_proposal
  FROM atlas.uni_ops_household_reality_identity_proposals_v1 p
  WHERE p.id=p_proposal_id AND p.proposal_state='proposed_unreviewed';

  IF v_proposal.id IS NULL THEN
    RAISE EXCEPTION 'Original Household source proposal unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Explicitly source-issued right for this exact typed cross-domain review.
  -- No general identity steward, household governor, company membership, or
  -- self-declared metadata supplies this permission.
  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_entity_id,
    'uni_ops_native_household_identity_adjudication',
    CASE WHEN p_event_kind='revoked'
      THEN 'household_native_identity.revoke'
      ELSE 'household_native_identity.adjudicate'
    END,
    'domain',NULL,'reality.household_native_identity',
    '{"nativeSource":"household_kernel_instance","decisionScope":"identity_only"}'::jsonb
  );
  IF v_relation_id IS NULL THEN
    RAISE EXCEPTION 'Independently issued typed Reality identity responsibility required'
      USING ERRCODE='42501';
  END IF;

  -- A review responsibility is NOT automatically a right to read original
  -- Household evidence. Approval needs distinct current identity AND
  -- condition disclosures to this reviewer's signed canonical Person.
  -- Protective revocation remains possible after information withdrawal.
  IF p_event_kind='approved' THEN
    IF coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_identity'
      )->>'currentlyAuthorized')::boolean,false)=false
      OR coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_condition'
      )->>'currentlyAuthorized')::boolean,false)=false
    THEN
      RAISE EXCEPTION 'Both current original Household information disclosures required'
        USING ERRCODE='42501';
    END IF;
  ELSIF p_event_kind='rejected' THEN
    IF coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_identity'
      )->>'currentlyAuthorized')::boolean,false)=false
    THEN
      RAISE EXCEPTION 'Current Household identity disclosure required for rejection'
        USING ERRCODE='42501';
    END IF;
  END IF;

  -- An independent reviewer cannot be the proposing Principal or the
  -- current Household governor, even if they also carry a review relation.
  SELECT principal.person_id INTO v_governor_person_id
  FROM atlas.households h
  JOIN atlas.principals principal ON principal.id=h.principal_id
  JOIN atlas.household_kernel_instances k ON k.household_id=h.id
  JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
    AND d.version=k.kernel_version
    AND d.scope_kind='household' AND d.active=true
  WHERE h.id=v_proposal.household_id
    AND k.id=v_proposal.kernel_instance_id
    AND h.status='active' AND k.state='active'
    AND principal.status='active'
    AND h.principal_id=v_proposal.proposed_by_principal_id;

  IF v_governor_person_id IS NULL
     OR v_principal_id=v_proposal.proposed_by_principal_id
     OR v_person_entity_id=v_governor_person_id
  THEN
    RAISE EXCEPTION 'Original active source and distinct independent reviewer required'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.id=v_proposal.candidate_reality_entity_id
      AND e.identity_state='canonical'
      AND e.entity_kind=v_proposal.candidate_entity_kind
  ) THEN
    RAISE EXCEPTION 'Original canonical Reality candidate is no longer current'
      USING ERRCODE='42501';
  END IF;

  IF p_reviewed_evidence_sha256<>v_proposal.claimed_evidence_sha256 THEN
    RAISE EXCEPTION 'Changed evidence requires a new governor proposal'
      USING ERRCODE='23505';
  END IF;

  -- Serializes concurrent decisions on the same native kernel OR Reality
  -- candidate. Locks are on distinct namespaces, taken in fixed order.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('UNI_OPS_HK:'||v_proposal.kernel_instance_id::text,0));
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('UNI_OPS_RE:'||v_proposal.candidate_reality_entity_id::text,0));

  -- Current signed authority is checked before any idempotent replay.
  SELECT * INTO v_existing
  FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
  WHERE e.source_action_id=p_source_action_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.proposal_id IS DISTINCT FROM p_proposal_id
       OR v_existing.event_kind IS DISTINCT FROM p_event_kind
       OR v_existing.reviewed_source_evidence_id IS DISTINCT FROM p_reviewed_source_evidence_id
       OR v_existing.reviewed_evidence_sha256 IS DISTINCT FROM p_reviewed_evidence_sha256
       OR v_existing.reviewer_principal_id IS DISTINCT FROM v_principal_id
       OR v_existing.reviewer_person_entity_id IS DISTINCT FROM v_person_entity_id
       OR v_existing.reviewer_responsibility_relation_id IS DISTINCT FROM v_relation_id
       OR v_existing.decision_basis IS DISTINCT FROM btrim(p_decision_basis)
    THEN
      RAISE EXCEPTION 'Review action replay conflicts with original evidence'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'contractVersion','uni_ops_household_reality_review_candidate_v1',
      'reviewEventId',v_existing.id,'eventKind',v_existing.event_kind,
      'idempotentReplay',true,'scope','identity_review_only_not_work_admission',
      'policyExecutable',false,'workCreated',false,'successorWorkCreated',false
    );
  END IF;

  SELECT * INTO v_latest
  FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
  WHERE e.proposal_id=p_proposal_id
  ORDER BY e.event_sequence DESC LIMIT 1;

  IF p_event_kind='revoked' THEN
    IF v_latest.id IS NULL OR v_latest.event_kind<>'approved' THEN
      RAISE EXCEPTION 'Revocation must supersede current approved identity review'
        USING ERRCODE='42501';
    END IF;
  ELSIF v_latest.id IS NOT NULL THEN
    RAISE EXCEPTION 'Previously reviewed proposal requires a NEW source proposal'
      USING ERRCODE='23505';
  END IF;

  -- The reviewer must point to a real, exact native-source evidence record,
  -- rather than creating a positive decision solely from the governor hash.
  -- This still does not cryptographically verify source contents.
  IF p_event_kind='approved' THEN
    IF p_reviewed_source_evidence_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM atlas.evidence_records ev
         WHERE ev.id=p_reviewed_source_evidence_id
           AND ev.scope_kind='household'
           AND ev.scope_id=v_proposal.household_id
           AND ev.subject_domain='household'
           AND ev.subject_kind='household_kernel_instance'
           AND ev.subject_id=v_proposal.kernel_instance_id::text
           AND ev.actor_user_id IS NOT NULL
           AND ev.observed_at IS NOT NULL
           AND ev.effective_until IS NULL
       )
    THEN
      RAISE EXCEPTION 'Existing exact original Household source evidence required'
        USING ERRCODE='42501';
    END IF;

    -- A simultaneous approved alternative for this native instance or
    -- this canonical entity is a conflict, never silently a second binding.
    IF EXISTS (
      SELECT 1
      FROM atlas.uni_ops_household_reality_identity_proposals_v1 other
      JOIN LATERAL (
        SELECT event_kind
        FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
        WHERE e.proposal_id=other.id
        ORDER BY e.event_sequence DESC LIMIT 1
      ) last_e ON true
      WHERE other.id<>v_proposal.id AND last_e.event_kind='approved'
        AND (
          other.kernel_instance_id=v_proposal.kernel_instance_id
          OR other.candidate_reality_entity_id=v_proposal.candidate_reality_entity_id
        )
    ) THEN
      RAISE EXCEPTION 'Conflicting active native or canonical identity review'
        USING ERRCODE='23505';
    END IF;
  ELSIF p_reviewed_source_evidence_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only approval may attach an independent source evidence ID'
      USING ERRCODE='22023';
  END IF;

  -- Bind an approval to the EXACT original authorizations it used.
  -- Any later withdrawal/re-grant generates new event IDs and cannot
  -- silently resurrect an old independent identity approval.
  IF p_event_kind='approved' THEN
    SELECT ev.id INTO v_identity_disclosure_event_id
    FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
    WHERE ev.household_id=v_proposal.household_id
      AND ev.kernel_instance_id=v_proposal.kernel_instance_id
      AND ev.target_person_entity_id=v_person_entity_id
      AND ev.decided_by_principal_id=v_proposal.proposed_by_principal_id
      AND ev.disclosure_class='subject_identity'
      AND ev.decision_kind='authorize'
      AND ev.event_sequence=(
        SELECT max(last_identity.event_sequence)
        FROM atlas.uni_ops_household_disclosure_decision_events_v1 last_identity
        WHERE last_identity.household_id=v_proposal.household_id
          AND last_identity.kernel_instance_id=v_proposal.kernel_instance_id
          AND last_identity.target_person_entity_id=v_person_entity_id
          AND last_identity.disclosure_class='subject_identity'
      );
    SELECT ev.id INTO v_condition_disclosure_event_id
    FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
    WHERE ev.household_id=v_proposal.household_id
      AND ev.kernel_instance_id=v_proposal.kernel_instance_id
      AND ev.target_person_entity_id=v_person_entity_id
      AND ev.decided_by_principal_id=v_proposal.proposed_by_principal_id
      AND ev.disclosure_class='subject_condition'
      AND ev.decision_kind='authorize'
      AND ev.event_sequence=(
        SELECT max(last_condition.event_sequence)
        FROM atlas.uni_ops_household_disclosure_decision_events_v1 last_condition
        WHERE last_condition.household_id=v_proposal.household_id
          AND last_condition.kernel_instance_id=v_proposal.kernel_instance_id
          AND last_condition.target_person_entity_id=v_person_entity_id
          AND last_condition.disclosure_class='subject_condition'
      );
    IF v_identity_disclosure_event_id IS NULL
       OR v_condition_disclosure_event_id IS NULL
    THEN
      RAISE EXCEPTION 'Exact current source disclosure receipts required'
        USING ERRCODE='42501';
    END IF;
  END IF;

  INSERT INTO atlas.uni_ops_household_reality_identity_reviews_v1 (
    proposal_id,event_kind,source_action_id,reviewed_source_evidence_id,
    reviewed_evidence_sha256,identity_disclosure_event_id,
    condition_disclosure_event_id,reviewer_principal_id,reviewer_person_entity_id,
    reviewer_responsibility_relation_id,prior_review_event_id,decision_basis
  ) VALUES (
    p_proposal_id,p_event_kind,p_source_action_id,p_reviewed_source_evidence_id,
    p_reviewed_evidence_sha256,v_identity_disclosure_event_id,
    v_condition_disclosure_event_id,v_principal_id,v_person_entity_id,
    v_relation_id,CASE WHEN p_event_kind='revoked' THEN v_latest.id ELSE NULL END,
    btrim(p_decision_basis)
  ) RETURNING * INTO v_event;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_reality_review_candidate_v1',
    'reviewEventId',v_event.id,'eventKind',v_event.event_kind,
    'proposalId',p_proposal_id,
    'idempotentReplay',false,
    'independentHumanReviewRecorded',true,
    'evidenceRecordReferenced',p_event_kind='approved',
    'sourceArtifactCryptographicallyVerified',false,
    'scope','identity_review_only_not_work_admission',
    'nativeNeedMapped',false,'domainAdmitted',false,
    'policyAdoptable',false,'policyExecutable',false,
    'workCreated',false,'clockAdmitted',false,'successorWorkCreated',false
  );
END;
$review$;

REVOKE ALL ON FUNCTION
  atlas.uni_ops_review_household_reality_identity_internal_v1(
    uuid,text,uuid,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_reality_review_immutable_guard_v1()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
),
  identity_disclosure_event_id uuid REFERENCES
    atlas.uni_ops_household_disclosure_decision_events_v1(id) ON DELETE RESTRICT,
  condition_disclosure_event_id uuid REFERENCES
    atlas.uni_ops_household_disclosure_decision_events_v1(id) ON DELETE RESTRICT,
  reviewer_principal_id uuid NOT NULL REFERENCES
    atlas.principals(id) ON DELETE RESTRICT,
  reviewer_person_entity_id uuid NOT NULL REFERENCES
    reality.entities(id) ON DELETE RESTRICT,
  reviewer_responsibility_relation_id uuid NOT NULL REFERENCES
    reality.responsibility_relations(id) ON DELETE RESTRICT,
  prior_review_event_id uuid REFERENCES
    atlas.uni_ops_household_reality_identity_reviews_v1(id)
    ON DELETE RESTRICT,
  decision_basis text NOT NULL
    CHECK (length(btrim(decision_basis)) BETWEEN 20 AND 4000),
  decided_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uni_ops_identity_approve_evidence_v1 CHECK (
    event_kind <> 'approved' OR reviewed_source_evidence_id IS NOT NULL
  ),
  CONSTRAINT uni_ops_identity_revoke_prior_v1 CHECK (
    (event_kind='revoked')=(prior_review_event_id IS NOT NULL)
  )
);
CREATE INDEX uni_ops_household_review_by_proposal_v1
  ON atlas.uni_ops_household_reality_identity_reviews_v1
  (proposal_id,event_sequence DESC);

ALTER TABLE atlas.uni_ops_household_reality_identity_reviews_v1
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.uni_ops_household_reality_identity_reviews_v1
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.uni_ops_household_reality_review_immutable_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $guard$
BEGIN
  RAISE EXCEPTION 'Household Reality review events are immutable'
    USING ERRCODE='42501';
END;
$guard$;
CREATE TRIGGER uni_ops_household_reality_review_history_v1
BEFORE UPDATE OR DELETE ON atlas.uni_ops_household_reality_identity_reviews_v1
FOR EACH ROW EXECUTE FUNCTION
  atlas.uni_ops_household_reality_review_immutable_guard_v1();

CREATE FUNCTION atlas.uni_ops_review_household_reality_identity_internal_v1(
  p_proposal_id uuid,
  p_event_kind text,
  p_reviewed_source_evidence_id uuid,
  p_reviewed_evidence_sha256 text,
  p_decision_basis text,
  p_source_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $review$
DECLARE
  v_principal_id uuid;
  v_person_entity_id uuid;
  v_relation_id uuid;
  v_proposal atlas.uni_ops_household_reality_identity_proposals_v1%ROWTYPE;
  v_latest atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_existing atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_event atlas.uni_ops_household_reality_identity_reviews_v1%ROWTYPE;
  v_governor_person_id uuid;
BEGIN
  IF p_proposal_id IS NULL OR p_source_action_id IS NULL
     OR p_event_kind IS NULL
     OR p_event_kind NOT IN ('approved','rejected','revoked')
     OR coalesce(p_reviewed_evidence_sha256,'') !~ '^[0-9a-f]{64}$'
     OR length(btrim(coalesce(p_decision_basis,''))) NOT BETWEEN 20 AND 4000
  THEN
    RAISE EXCEPTION 'Exact evidence, review action and decision basis required'
      USING ERRCODE='42501';
  END IF;

  -- True current session, not a cached JWT role or caller-provided reviewer.
  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL OR
     v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Signed independent reviewer Principal required'
      USING ERRCODE='42501';
  END IF;
  v_person_entity_id:=atlas.current_person_id_v1();
  IF v_person_entity_id IS NULL THEN
    RAISE EXCEPTION 'Canonical independent reviewer Person required'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_proposal
  FROM atlas.uni_ops_household_reality_identity_proposals_v1 p
  WHERE p.id=p_proposal_id AND p.proposal_state='proposed_unreviewed';

  IF v_proposal.id IS NULL THEN
    RAISE EXCEPTION 'Original Household source proposal unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Explicitly source-issued right for this exact typed cross-domain review.
  -- No general identity steward, household governor, company membership, or
  -- self-declared metadata supplies this permission.
  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_entity_id,
    'uni_ops_native_household_identity_adjudication',
    CASE WHEN p_event_kind='revoked'
      THEN 'household_native_identity.revoke'
      ELSE 'household_native_identity.adjudicate'
    END,
    'domain',NULL,'reality.household_native_identity',
    '{"nativeSource":"household_kernel_instance","decisionScope":"identity_only"}'::jsonb
  );
  IF v_relation_id IS NULL THEN
    RAISE EXCEPTION 'Independently issued typed Reality identity responsibility required'
      USING ERRCODE='42501';
  END IF;

  -- A review responsibility is NOT automatically a right to read original
  -- Household evidence. Approval needs distinct current identity AND
  -- condition disclosures to this reviewer's signed canonical Person.
  -- Protective revocation remains possible after information withdrawal.
  IF p_event_kind='approved' THEN
    IF coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_identity'
      )->>'currentlyAuthorized')::boolean,false)=false
      OR coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_condition'
      )->>'currentlyAuthorized')::boolean,false)=false
    THEN
      RAISE EXCEPTION 'Both current original Household information disclosures required'
        USING ERRCODE='42501';
    END IF;
  ELSIF p_event_kind='rejected' THEN
    IF coalesce((
      atlas.uni_ops_household_disclosure_current_self_internal_v1(
        v_proposal.household_id,v_proposal.kernel_instance_id,'subject_identity'
      )->>'currentlyAuthorized')::boolean,false)=false
    THEN
      RAISE EXCEPTION 'Current Household identity disclosure required for rejection'
        USING ERRCODE='42501';
    END IF;
  END IF;

  -- An independent reviewer cannot be the proposing Principal or the
  -- current Household governor, even if they also carry a review relation.
  SELECT principal.person_id INTO v_governor_person_id
  FROM atlas.households h
  JOIN atlas.principals principal ON principal.id=h.principal_id
  JOIN atlas.household_kernel_instances k ON k.household_id=h.id
  JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
    AND d.version=k.kernel_version
    AND d.scope_kind='household' AND d.active=true
  WHERE h.id=v_proposal.household_id
    AND k.id=v_proposal.kernel_instance_id
    AND h.status='active' AND k.state='active'
    AND principal.status='active'
    AND h.principal_id=v_proposal.proposed_by_principal_id;

  IF v_governor_person_id IS NULL
     OR v_principal_id=v_proposal.proposed_by_principal_id
     OR v_person_entity_id=v_governor_person_id
  THEN
    RAISE EXCEPTION 'Original active source and distinct independent reviewer required'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.id=v_proposal.candidate_reality_entity_id
      AND e.identity_state='canonical'
      AND e.entity_kind=v_proposal.candidate_entity_kind
  ) THEN
    RAISE EXCEPTION 'Original canonical Reality candidate is no longer current'
      USING ERRCODE='42501';
  END IF;

  IF p_reviewed_evidence_sha256<>v_proposal.claimed_evidence_sha256 THEN
    RAISE EXCEPTION 'Changed evidence requires a new governor proposal'
      USING ERRCODE='23505';
  END IF;

  -- Serializes concurrent decisions on the same native kernel OR Reality
  -- candidate. Locks are on distinct namespaces, taken in fixed order.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('UNI_OPS_HK:'||v_proposal.kernel_instance_id::text,0));
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('UNI_OPS_RE:'||v_proposal.candidate_reality_entity_id::text,0));

  -- Current signed authority is checked before any idempotent replay.
  SELECT * INTO v_existing
  FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
  WHERE e.source_action_id=p_source_action_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.proposal_id IS DISTINCT FROM p_proposal_id
       OR v_existing.event_kind IS DISTINCT FROM p_event_kind
       OR v_existing.reviewed_source_evidence_id IS DISTINCT FROM p_reviewed_source_evidence_id
       OR v_existing.reviewed_evidence_sha256 IS DISTINCT FROM p_reviewed_evidence_sha256
       OR v_existing.reviewer_principal_id IS DISTINCT FROM v_principal_id
       OR v_existing.reviewer_person_entity_id IS DISTINCT FROM v_person_entity_id
       OR v_existing.reviewer_responsibility_relation_id IS DISTINCT FROM v_relation_id
       OR v_existing.decision_basis IS DISTINCT FROM btrim(p_decision_basis)
    THEN
      RAISE EXCEPTION 'Review action replay conflicts with original evidence'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'contractVersion','uni_ops_household_reality_review_candidate_v1',
      'reviewEventId',v_existing.id,'eventKind',v_existing.event_kind,
      'idempotentReplay',true,'scope','identity_review_only_not_work_admission',
      'policyExecutable',false,'workCreated',false,'successorWorkCreated',false
    );
  END IF;

  SELECT * INTO v_latest
  FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
  WHERE e.proposal_id=p_proposal_id
  ORDER BY e.event_sequence DESC LIMIT 1;

  IF p_event_kind='revoked' THEN
    IF v_latest.id IS NULL OR v_latest.event_kind<>'approved' THEN
      RAISE EXCEPTION 'Revocation must supersede current approved identity review'
        USING ERRCODE='42501';
    END IF;
  ELSIF v_latest.id IS NOT NULL THEN
    RAISE EXCEPTION 'Previously reviewed proposal requires a NEW source proposal'
      USING ERRCODE='23505';
  END IF;

  -- The reviewer must point to a real, exact native-source evidence record,
  -- rather than creating a positive decision solely from the governor hash.
  -- This still does not cryptographically verify source contents.
  IF p_event_kind='approved' THEN
    IF p_reviewed_source_evidence_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM atlas.evidence_records ev
         WHERE ev.id=p_reviewed_source_evidence_id
           AND ev.scope_kind='household'
           AND ev.scope_id=v_proposal.household_id
           AND ev.subject_domain='household'
           AND ev.subject_kind='household_kernel_instance'
           AND ev.subject_id=v_proposal.kernel_instance_id::text
           AND ev.actor_user_id IS NOT NULL
           AND ev.observed_at IS NOT NULL
           AND ev.effective_until IS NULL
       )
    THEN
      RAISE EXCEPTION 'Existing exact original Household source evidence required'
        USING ERRCODE='42501';
    END IF;

    -- A simultaneous approved alternative for this native instance or
    -- this canonical entity is a conflict, never silently a second binding.
    IF EXISTS (
      SELECT 1
      FROM atlas.uni_ops_household_reality_identity_proposals_v1 other
      JOIN LATERAL (
        SELECT event_kind
        FROM atlas.uni_ops_household_reality_identity_reviews_v1 e
        WHERE e.proposal_id=other.id
        ORDER BY e.event_sequence DESC LIMIT 1
      ) last_e ON true
      WHERE other.id<>v_proposal.id AND last_e.event_kind='approved'
        AND (
          other.kernel_instance_id=v_proposal.kernel_instance_id
          OR other.candidate_reality_entity_id=v_proposal.candidate_reality_entity_id
        )
    ) THEN
      RAISE EXCEPTION 'Conflicting active native or canonical identity review'
        USING ERRCODE='23505';
    END IF;
  ELSIF p_reviewed_source_evidence_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only approval may attach an independent source evidence ID'
      USING ERRCODE='22023';
  END IF;

  INSERT INTO atlas.uni_ops_household_reality_identity_reviews_v1 (
    proposal_id,event_kind,source_action_id,reviewed_source_evidence_id,
    reviewed_evidence_sha256,reviewer_principal_id,reviewer_person_entity_id,
    reviewer_responsibility_relation_id,prior_review_event_id,decision_basis
  ) VALUES (
    p_proposal_id,p_event_kind,p_source_action_id,p_reviewed_source_evidence_id,
    p_reviewed_evidence_sha256,v_principal_id,v_person_entity_id,
    v_relation_id,CASE WHEN p_event_kind='revoked' THEN v_latest.id ELSE NULL END,
    btrim(p_decision_basis)
  ) RETURNING * INTO v_event;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_reality_review_candidate_v1',
    'reviewEventId',v_event.id,'eventKind',v_event.event_kind,
    'proposalId',p_proposal_id,
    'idempotentReplay',false,
    'independentHumanReviewRecorded',true,
    'evidenceRecordReferenced',p_event_kind='approved',
    'sourceArtifactCryptographicallyVerified',false,
    'scope','identity_review_only_not_work_admission',
    'nativeNeedMapped',false,'domainAdmitted',false,
    'policyAdoptable',false,'policyExecutable',false,
    'workCreated',false,'clockAdmitted',false,'successorWorkCreated',false
  );
END;
$review$;

REVOKE ALL ON FUNCTION
  atlas.uni_ops_review_household_reality_identity_internal_v1(
    uuid,text,uuid,text,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_reality_review_immutable_guard_v1()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

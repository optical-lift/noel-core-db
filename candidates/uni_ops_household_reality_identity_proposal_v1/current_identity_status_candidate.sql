-- UNI-OPS-01 U5: CURRENT independently reviewed identity STATUS ONLY.
-- HELD; apply only after candidate.sql and independent_review_candidate.sql
-- in a disposable clone until shared migration/source authority is approved.
-- No public SELECT or integration into Common Rulebook/Work.
BEGIN;
CREATE FUNCTION atlas.uni_ops_resolve_household_reality_identity_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_reality_entity_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $resolver$
DECLARE
  v_principal_id uuid;
  v_governor_person_id uuid;
  v_total_current integer:=0;
  v_matching_current integer:=0;
  v_decision_id uuid;
  v_reviewed_evidence_id uuid;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
     OR p_reality_entity_id IS NULL
  THEN
    RAISE EXCEPTION 'Exact native/canonical Subject identifiers required'
      USING ERRCODE='42501';
  END IF;

  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL
     OR v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Current signed first-party Principal required'
      USING ERRCODE='42501';
  END IF;
  v_governor_person_id:=atlas.require_household_governor_self_v1(
    p_household_id);
  IF v_governor_person_id IS NULL THEN
    RAISE EXCEPTION 'Current native Household governor required'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.household_kernel_instances k
    JOIN atlas.households h ON h.id=k.household_id
    JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
      AND d.version=k.kernel_version
      AND d.scope_kind='household' AND d.active=true
    WHERE k.id=p_kernel_instance_id AND k.household_id=p_household_id
      AND k.state='active' AND h.status='active'
      AND h.principal_id=v_principal_id
  ) THEN
    RAISE EXCEPTION 'Current original native Household Subject unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Only ACTIVE most-recent review events count; later revocation closes
  -- positive status. Reviewer's current responsibility must still be active.
  -- This is deliberately conservative on responsibility withdrawal.
  WITH latest AS (
    SELECT p.id AS proposal_id,
      p.household_id,p.kernel_instance_id,p.candidate_reality_entity_id,
      p.candidate_entity_kind,p.proposed_by_principal_id,
      p.claimed_evidence_sha256,
      ev.id AS review_event_id, ev.event_kind,ev.reviewed_source_evidence_id,
      ev.reviewed_evidence_sha256,ev.reviewer_person_entity_id,
      ev.identity_disclosure_event_id,ev.condition_disclosure_event_id,
      ev.reviewer_responsibility_relation_id
    FROM atlas.uni_ops_household_reality_identity_proposals_v1 p
    JOIN LATERAL (
      SELECT r.* FROM atlas.uni_ops_household_reality_identity_reviews_v1 r
      WHERE r.proposal_id=p.id
      ORDER BY r.event_sequence DESC LIMIT 1
    ) ev ON true
    WHERE ev.event_kind='approved'
  ), active_verified AS (
    SELECT l.*
    FROM latest l
    JOIN atlas.household_kernel_instances k ON k.id=l.kernel_instance_id
      AND k.household_id=l.household_id AND k.state='active'
    JOIN atlas.households h ON h.id=l.household_id AND h.status='active'
      AND h.principal_id=l.proposed_by_principal_id
    JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
      AND d.version=k.kernel_version AND d.scope_kind='household'
      AND d.active=true
    JOIN reality.entities e ON e.id=l.candidate_reality_entity_id
      AND e.entity_kind=l.candidate_entity_kind
      AND e.identity_state='canonical'
    JOIN atlas.evidence_records source_ev
      ON source_ev.id=l.reviewed_source_evidence_id
      AND source_ev.scope_kind='household'
      AND source_ev.scope_id=l.household_id
      AND source_ev.subject_domain='household'
      AND source_ev.subject_kind='household_kernel_instance'
      AND source_ev.subject_id=l.kernel_instance_id::text
      AND source_ev.effective_until IS NULL
      AND source_ev.actor_user_id IS NOT NULL
      AND source_ev.observed_at IS NOT NULL
    JOIN reality.responsibility_relations rr
      ON rr.id=l.reviewer_responsibility_relation_id
      AND rr.carrier_person_entity_id=l.reviewer_person_entity_id
      AND rr.responsibility_key='uni_ops_native_household_identity_adjudication'
      AND rr.jurisdiction_kind='domain'
      AND rr.jurisdiction_domain='reality.household_native_identity'
      AND rr.scope @> '{"nativeSource":"household_kernel_instance","decisionScope":"identity_only"}'::jsonb
      AND 'household_native_identity.adjudicate'=ANY(rr.permitted_operations)
      AND rr.relation_state='active' AND rr.ended_at IS NULL
      AND rr.began_at<=now()
    -- Disclosure is actor-specific, class-specific and independently current.
    -- Withdrawing either class immediately removes this positive source status.
    JOIN LATERAL (
      SELECT ev.id,ev.decision_kind
      FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
      WHERE ev.household_id=l.household_id
        AND ev.kernel_instance_id=l.kernel_instance_id
        AND ev.target_person_entity_id=l.reviewer_person_entity_id
        AND ev.decided_by_principal_id=l.proposed_by_principal_id
        AND ev.disclosure_class='subject_identity'
      ORDER BY ev.event_sequence DESC LIMIT 1
    ) identity_release ON identity_release.decision_kind='authorize'
      AND identity_release.id=l.identity_disclosure_event_id
    JOIN LATERAL (
      SELECT ev.id,ev.decision_kind
      FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
      WHERE ev.household_id=l.household_id
        AND ev.kernel_instance_id=l.kernel_instance_id
        AND ev.target_person_entity_id=l.reviewer_person_entity_id
        AND ev.decided_by_principal_id=l.proposed_by_principal_id
        AND ev.disclosure_class='subject_condition'
      ORDER BY ev.event_sequence DESC LIMIT 1
    ) condition_release ON condition_release.decision_kind='authorize'
      AND condition_release.id=l.condition_disclosure_event_id
    WHERE l.reviewed_evidence_sha256=l.claimed_evidence_sha256
      AND l.reviewer_person_entity_id<>(
        SELECT proposer.person_id
        FROM atlas.principals proposer
        WHERE proposer.id=l.proposed_by_principal_id)
  )
  SELECT
    COUNT(*) FILTER (WHERE kernel_instance_id=p_kernel_instance_id
                       OR candidate_reality_entity_id=p_reality_entity_id),
    COUNT(*) FILTER (WHERE kernel_instance_id=p_kernel_instance_id
                       AND candidate_reality_entity_id=p_reality_entity_id),
    (array_agg(review_event_id ORDER BY review_event_id)
      FILTER (WHERE kernel_instance_id=p_kernel_instance_id
                AND candidate_reality_entity_id=p_reality_entity_id))[1],
    (array_agg(reviewed_source_evidence_id ORDER BY reviewed_source_evidence_id)
      FILTER (WHERE kernel_instance_id=p_kernel_instance_id
                AND candidate_reality_entity_id=p_reality_entity_id))[1]
  INTO v_total_current,v_matching_current,v_decision_id,v_reviewed_evidence_id
  FROM active_verified;

  -- One exact pair and no competing active source or canonical candidates.
  -- A past approval is NOT a current binding after revocation/conflict.
  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_reality_identity_status_v1',
    'state',CASE
      WHEN v_matching_current=1 AND v_total_current=1
      THEN 'independent_identity_review_current_only'
      ELSE 'identity_binding_absent_stale_or_conflicted'
    END,
    'nativeSourceCurrentlyGoverned',true,
    'independentReviewCurrentForExactPair',
      v_matching_current=1 AND v_total_current=1,
    'reviewEventId',CASE WHEN v_matching_current=1 AND v_total_current=1
      THEN v_decision_id ELSE NULL END,
    'evidenceRecordId',CASE WHEN v_matching_current=1 AND v_total_current=1
      THEN v_reviewed_evidence_id ELSE NULL END,
    'currentIdentityDisclosureAuthorized',false,
    'currentConditionDisclosureAuthorized',false,
    'nativeNeedMapped',false,'commonRequirementAdmitted',false,
    'foundryIndependentReviewApproved',false,'domainAdmitted',false,
    'policyAdoptable',false,'policyExecutable',false,
    'workCreated',false,'clockAdmitted',false,'successorWorkCreated',false
  );
END;
$resolver$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_resolve_household_reality_identity_internal_v1(
    uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- UNI-OPS-01 U5: PRIVACY-BOUNDED reviewer inbox candidate, HELD.
-- No PUBLIC/GoTrue REST wrapper, no evidence contents or Person roster.
-- An identity-review responsibility by itself is NOT information disclosure.
BEGIN;
CREATE FUNCTION atlas.uni_ops_household_identity_review_queue_internal_v1(
  p_limit integer,
  p_before_created_at timestamptz,
  p_before_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $queue$
DECLARE
  v_principal_id uuid;
  v_reviewer_person_entity_id uuid;
  v_relation_id uuid;
  v_items jsonb;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 20
     OR ((p_before_created_at IS NULL)<>(p_before_id IS NULL))
  THEN
    RAISE EXCEPTION 'Bounded queue page and complete optional cursor required'
      USING ERRCODE='42501';
  END IF;
  v_principal_id:=atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL OR
     v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Current signed independent reviewer required'
      USING ERRCODE='42501';
  END IF;
  v_reviewer_person_entity_id:=atlas.current_person_id_v1();
  IF v_reviewer_person_entity_id IS NULL THEN
    RAISE EXCEPTION 'Current canonical reviewer Person required'
      USING ERRCODE='42501';
  END IF;
  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_reviewer_person_entity_id,
    'uni_ops_native_household_identity_adjudication',
    'household_native_identity.adjudicate',
    'domain',NULL,'reality.household_native_identity',
    '{"nativeSource":"household_kernel_instance","decisionScope":"identity_only"}'::jsonb
  );
  IF v_relation_id IS NULL THEN
    RAISE EXCEPTION 'Separately issued independent review responsibility required'
      USING ERRCODE='42501';
  END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'proposalId',q.id,
      'householdId',q.household_id,
      'kernelInstanceId',q.kernel_instance_id,
      'candidateRealityEntityId',q.candidate_reality_entity_id,
      'candidateEntityKind',q.candidate_entity_kind,
      'claimedEvidenceSha256',q.claimed_evidence_sha256,
      'proposedAt',q.created_at
    ) ORDER BY q.created_at DESC,q.id DESC
  ),'[]'::jsonb) INTO v_items
  FROM (
    SELECT p.id,p.household_id,p.kernel_instance_id,
      p.candidate_reality_entity_id,p.candidate_entity_kind,
      p.claimed_evidence_sha256,p.created_at
    FROM atlas.uni_ops_household_reality_identity_proposals_v1 p
    JOIN atlas.households h ON h.id=p.household_id
      AND h.status='active' AND h.principal_id=p.proposed_by_principal_id
    JOIN atlas.principals governor ON governor.id=h.principal_id
      AND governor.status='active'
      AND governor.person_id<>v_reviewer_person_entity_id
    JOIN atlas.household_kernel_instances k ON k.id=p.kernel_instance_id
      AND k.household_id=p.household_id AND k.state='active'
    JOIN atlas.world_kernel_definitions d ON d.kernel_key=k.kernel_key
      AND d.version=k.kernel_version AND d.scope_kind='household'
      AND d.active=true
    JOIN reality.entities ent ON ent.id=p.candidate_reality_entity_id
      AND ent.entity_kind=p.candidate_entity_kind
      AND ent.identity_state='canonical'
    JOIN LATERAL (
      SELECT ev.decision_kind
      FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
      WHERE ev.household_id=p.household_id
        AND ev.kernel_instance_id=p.kernel_instance_id
        AND ev.target_person_entity_id=v_reviewer_person_entity_id
        AND ev.decided_by_principal_id=p.proposed_by_principal_id
        AND ev.disclosure_class='subject_identity'
      ORDER BY ev.event_sequence DESC LIMIT 1
    ) d_identity ON d_identity.decision_kind='authorize'
    JOIN LATERAL (
      SELECT ev.decision_kind
      FROM atlas.uni_ops_household_disclosure_decision_events_v1 ev
      WHERE ev.household_id=p.household_id
        AND ev.kernel_instance_id=p.kernel_instance_id
        AND ev.target_person_entity_id=v_reviewer_person_entity_id
        AND ev.decided_by_principal_id=p.proposed_by_principal_id
        AND ev.disclosure_class='subject_condition'
      ORDER BY ev.event_sequence DESC LIMIT 1
    ) d_condition ON d_condition.decision_kind='authorize'
    WHERE p.proposal_state='proposed_unreviewed'
      AND p.proposed_by_principal_id<>v_principal_id
      AND NOT EXISTS (
        SELECT 1 FROM atlas.uni_ops_household_reality_identity_reviews_v1 ev
        WHERE ev.proposal_id=p.id
      )
      AND (
        p_before_created_at IS NULL
        OR (p.created_at,p.id)<(p_before_created_at,p_before_id)
      )
    ORDER BY p.created_at DESC,p.id DESC
    LIMIT p_limit
  ) q;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_identity_review_queue_private_v1',
    'items',v_items,
    'boundedPageSize',p_limit,
    'fullRosterReturned',false,
    'sourceEvidenceContentsReturned',false,
    'actualEvidenceDisclosed',false,
    'policyAdoptable',false,
    'workCreated',false
  );
END;
$queue$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_identity_review_queue_internal_v1(
    integer,timestamptz,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

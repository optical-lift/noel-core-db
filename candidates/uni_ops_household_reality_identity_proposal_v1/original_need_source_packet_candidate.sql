-- UNI-OPS-01 U5: exact original Household Need receipt and typed source packet.
-- HELD, private, read-only. NOT an atlas.work_requirements row or new
-- Requirement registry. Depends on existing held native #2559 verifier and
-- the private Household identity-status source in this draft.
BEGIN;
CREATE FUNCTION atlas.uni_ops_original_household_need_receipt_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_need_occurrence_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $need$
DECLARE
  v_native jsonb;
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_has_original_source boolean;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
     OR p_need_occurrence_id IS NULL
  THEN
    RAISE EXCEPTION 'Exact native Household and Need source required'
      USING ERRCODE='42501';
  END IF;

  -- ONLY the existing native source verifier can establish the Household
  -- governor and current original condition/open Need preconditions.
  v_native:=atlas.universal_rulebook_household_native_evidence_internal_v1(
    p_household_id,p_kernel_instance_id);
  IF (v_native->>'contractVersion') IS DISTINCT FROM
     'universal_typed_native_evidence_v1'
  THEN
    RAISE EXCEPTION 'Original native Household adapter required'
      USING ERRCODE='42501';
  END IF;

  v_has_original_source:=coalesce(
      (v_native->>'nativeSubjectVerified')::boolean,false)
    AND coalesce((v_native->>'currentObservationSourceVerified')::boolean,false)
    AND coalesce((v_native->>'openNeedSourceVerified')::boolean,false);

  IF v_has_original_source THEN
    -- Strictly one *named* native Need already opened by the same current
    -- original firsthand non-clock-inferred observation, not any rhythm or
    -- work item and not an inferred need based on a generic label.
    SELECT n.* INTO v_need
    FROM atlas.household_need_occurrences_v1 n
    JOIN atlas.care_current_state c
      ON c.last_observation_id=n.opened_by_observation_id
      AND c.scope_kind='household'
      AND c.scope_id=n.household_id
      AND c.subject_domain='household'
      AND c.subject_kind='household_kernel_instance'
      AND c.subject_id=n.instance_id::text
    JOIN atlas.care_observation_events o
      ON o.id=n.opened_by_observation_id
      AND o.scope_kind='household'
      AND o.scope_id=n.household_id
      AND o.subject_domain=c.subject_domain
      AND o.subject_kind=c.subject_kind
      AND o.subject_id=c.subject_id
      AND o.condition_state=c.condition_state
      AND o.observed_by_user_id IS NOT NULL
      AND o.inferred_from_clock=false
      AND o.observed_at<=now()
    WHERE n.id=p_need_occurrence_id
      AND n.household_id=p_household_id
      AND n.instance_id=p_kernel_instance_id
      AND n.state='open'
      AND length(btrim(n.need_key)) BETWEEN 2 AND 100;
  END IF;

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_original_need_receipt_v1',
    'state',CASE WHEN v_need.id IS NOT NULL
      THEN 'exact_original_native_need_verified_only'
      ELSE 'native_need_unobserved_or_not_current'
    END,
    'currentOriginalNeedVerified',v_need.id IS NOT NULL,
    'householdId',p_household_id,
    'nativeKernelInstanceId',p_kernel_instance_id,
    'originalNeedId',v_need.id,
    'originalObservationId',v_need.opened_by_observation_id,
    'originalNeedKey',CASE WHEN v_need.id IS NOT NULL
      THEN v_need.need_key ELSE NULL END,
    'nativeNeedAlreadyLinkedToWork',CASE WHEN v_need.id IS NOT NULL
      THEN v_need.current_work_item_id IS NOT NULL ELSE false END,
    'commonRequirementCreated',false,
    'foundryInstructionCreated',false,
    'policyAdoptable',false,
    'workCreated',false,'successorWorkCreated',false
  );
END;
$need$;

CREATE FUNCTION atlas.uni_ops_household_typed_requirement_source_packet_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_reality_entity_id uuid,
  p_need_occurrence_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $packet$
DECLARE
  v_need jsonb;
  v_identity jsonb;
  v_need_current boolean;
  v_identity_current boolean;
BEGIN
  -- Exact signed governor source is enforced by BOTH internal readers.
  -- The pair of receipts is not a cross-domain Work Requirement approval.
  v_need:=atlas.uni_ops_original_household_need_receipt_internal_v1(
    p_household_id,p_kernel_instance_id,p_need_occurrence_id);
  v_identity:=atlas.uni_ops_resolve_household_reality_identity_internal_v1(
    p_household_id,p_kernel_instance_id,p_reality_entity_id);
  IF (v_need->>'contractVersion') IS DISTINCT FROM
       'uni_ops_household_original_need_receipt_v1'
     OR (v_identity->>'contractVersion') IS DISTINCT FROM
       'uni_ops_household_reality_identity_status_v1'
  THEN
    RAISE EXCEPTION 'Exact source receipt contracts required'
      USING ERRCODE='42501';
  END IF;
  v_need_current:=coalesce(
    (v_need->>'currentOriginalNeedVerified')::boolean,false);
  v_identity_current:=coalesce(
    (v_identity->>'independentReviewCurrentForExactPair')::boolean,false);

  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_typed_requirement_source_packet_v1',
    'state','source_packet_only_not_canonical_requirement_admission',
    'nativeSourceKind','household_kernel_instance',
    'nativeHouseholdId',p_household_id,
    'nativeKernelInstanceId',p_kernel_instance_id,
    'canonicalRealityCandidateId',p_reality_entity_id,
    'originalNativeNeedId',CASE WHEN v_need_current
      THEN p_need_occurrence_id ELSE NULL END,
    'originalObservationId',CASE WHEN v_need_current
      THEN v_need->>'originalObservationId' ELSE NULL END,
    'nativeNeedKey',CASE WHEN v_need_current
      THEN v_need->>'originalNeedKey' ELSE NULL END,
    'currentOriginalNeedVerified',v_need_current,
    'independentCurrentIdentityVerified',v_identity_current,
    'sourcePacketFullyObserved',v_need_current AND v_identity_current,
    'nativeNeedAlreadyLinkedToWork',
      coalesce((v_need->>'nativeNeedAlreadyLinkedToWork')::boolean,false),
    'canonicalCommonWorkRequirementId',NULL,
    'typedRequirementRepresentationAdmitted',false,
    'currentWorkerIdentityDisclosureVerified',false,
    'currentWorkerConditionDisclosureVerified',false,
    'independentFoundryReviewVerified',false,
    'oneRulebookArbiterAuthorized',false,
    'originalWorkIssued',false,'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$packet$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_original_household_need_receipt_internal_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_typed_requirement_source_packet_internal_v1(
    uuid,uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

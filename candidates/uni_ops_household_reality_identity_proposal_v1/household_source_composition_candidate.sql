-- UNI-OPS-01 U5: Household READ-ONLY typed identity+source composition.
-- HELD, no domain admission. Depends on source PR #2559 native verifier
-- and the private source proposal/review/status candidates in this draft.
-- Do not recreate the native Household evidence law.
BEGIN;
CREATE FUNCTION atlas.uni_ops_household_source_composition_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_reality_entity_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $compose$
DECLARE
  v_native jsonb;
  v_identity jsonb;
  v_native_subject boolean;
  v_original_observation boolean;
  v_original_need boolean;
  v_current_identity_review boolean;
BEGIN
  -- The original source adapter checks the real current signed Principal,
  -- exact independent governor and source-authored observation/Need.
  -- No parallel verification engine and no generic company Ledger coercion.
  v_native:=atlas.universal_rulebook_household_native_evidence_internal_v1(
    p_household_id,p_kernel_instance_id);
  IF (v_native->>'contractVersion') IS DISTINCT FROM
     'universal_typed_native_evidence_v1'
  THEN
    RAISE EXCEPTION 'Expected exact original native Household source contract'
      USING ERRCODE='42501';
  END IF;

  -- The identity decision is distinct from the source Subject, current
  -- observation, Need, disclosure, Foundry and Work writer.
  v_identity:=atlas.uni_ops_resolve_household_reality_identity_internal_v1(
    p_household_id,p_kernel_instance_id,p_reality_entity_id);
  IF (v_identity->>'contractVersion') IS DISTINCT FROM
     'uni_ops_household_reality_identity_status_v1'
  THEN
    RAISE EXCEPTION 'Expected exact typed independent identity review contract'
      USING ERRCODE='42501';
  END IF;

  v_native_subject:=coalesce(
    (v_native->>'nativeSubjectVerified')::boolean,false);
  v_original_observation:=coalesce(
    (v_native->>'currentObservationSourceVerified')::boolean,false);
  v_original_need:=coalesce(
    (v_native->>'openNeedSourceVerified')::boolean,false);
  v_current_identity_review:=coalesce(
    (v_identity->>'independentReviewCurrentForExactPair')::boolean,false);

  -- These are independent original facts, not an executable combined law.
  -- NOTE: native Need evidence is not an original common Work Requirement.
  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_source_composition_held_v1',
    'state','native_and_identity_receipts_only_not_rulebook_admission',
    'nativeSubjectVerified',v_native_subject,
    'originalObservedConditionVerified',v_original_observation,
    'originalOpenNeedVerified',v_original_need,
    'independentIdentityReviewCurrent',v_current_identity_review,
    'sourceEvidenceFullySatisfied',
      v_native_subject AND v_original_observation
        AND v_original_need AND v_current_identity_review,
    'identityDisclosureToWorkerVerified',false,
    'conditionDisclosureToWorkerVerified',false,
    'originalNeedToCommonRequirementAdmitted',false,
    'independentFoundryReviewVerified',false,
    'jurisdictionResolverApproved',false,
    'domainAdmissionAuthorized',false,
    'policyAdoptable',false,
    'policyExecutable',false,
    'workCreated',false,
    'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$compose$;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_source_composition_internal_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

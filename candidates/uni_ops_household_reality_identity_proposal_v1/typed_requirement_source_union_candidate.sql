-- UNI-OPS-01 U5/U1: one TYPED common Requirement-source envelope.
-- HELD, PRIVATE, READ-ONLY. This is NOT a Requirement table, new Work
-- issuer, jurisdiction grant, Rulebook arbiter, or Company Ledger adapter.
-- It composes rather than replaces the original source-owned preflights.
-- Requires separate held universal common #2555 and typed native #2559.
BEGIN;
CREATE FUNCTION atlas.uni_ops_typed_requirement_source_union_internal_v1(
  p_source_family text,
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_reality_entity_id uuid,
  p_native_need_occurrence_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_requirement_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $source_union$
DECLARE
  v_source jsonb;
  v_original_present boolean := false;
  v_subject_current boolean := false;
  v_source_state text;
BEGIN
  -- Distinct source families MUST stay distinct; no lossy "any UUID"
  -- branch or implicit Company compatibility ledger for a Household.
  IF p_source_family='household_native_need' THEN
    IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
       OR p_reality_entity_id IS NULL OR p_native_need_occurrence_id IS NULL
       OR p_organization_id IS NOT NULL OR p_ledger_id IS NOT NULL
       OR p_work_requirement_id IS NOT NULL
    THEN
      RAISE EXCEPTION 'Exact exclusive Household original source required'
        USING ERRCODE='42501';
    END IF;

    v_source:=atlas.uni_ops_household_typed_requirement_source_packet_internal_v1(
      p_household_id,p_kernel_instance_id,p_reality_entity_id,
      p_native_need_occurrence_id
    );
    IF (v_source->>'contractVersion') IS DISTINCT FROM
       'uni_ops_household_typed_requirement_source_packet_v1'
    THEN
      RAISE EXCEPTION 'Original Household Need packet contract unavailable'
        USING ERRCODE='42501';
    END IF;

    v_original_present:=coalesce(
      (v_source->>'currentOriginalNeedVerified')::boolean,false);
    v_subject_current:=coalesce(
      (v_source->>'independentCurrentIdentityVerified')::boolean,false);
    v_source_state:='typed_household_need_original_only';
    RETURN jsonb_build_object(
      'contractVersion','uni_ops_typed_requirement_source_union_held_v1',
      'sourceFamily','household_native_need',
      'state',v_source_state,
      'jurisdictionKind','household',
      'jurisdictionNativeId',p_household_id,
      'nativeSubjectKind','household_kernel_instance',
      'nativeSubjectId',p_kernel_instance_id,
      'originalRequirementSourceTable','atlas.household_need_occurrences_v1',
      'originalRequirementSourceId',
        CASE WHEN v_original_present THEN p_native_need_occurrence_id ELSE NULL END,
      'originalNeedKey',
        CASE WHEN v_original_present THEN v_source->>'nativeNeedKey' ELSE NULL END,
      'canonicalRealitySubjectId',p_reality_entity_id,
      'nativeOriginalNeedCurrent',v_original_present,
      'independentIdentityReviewCurrent',v_subject_current,
      'sourceEvidenceTogetherCurrent',v_original_present AND v_subject_current,
      'canonicalWorkRequirementId',NULL,
      'organizationLedgerRequired',false,
      'companyWorkRequirementRowCreated',false,
      'nativeNeedChanged',false,
      'policyAdoptable',false,
      'policyExecutable',false,
      'jurisdictionAdmissionAuthorized',false,
      'workCreated',false,'clockAdmitted',false,
      'successorWorkCreated',false
    );

  ELSIF p_source_family='company_work_requirement' THEN
    IF p_organization_id IS NULL OR p_ledger_id IS NULL
       OR p_work_requirement_id IS NULL
       OR p_household_id IS NOT NULL OR p_kernel_instance_id IS NOT NULL
       OR p_reality_entity_id IS NOT NULL
       OR p_native_need_occurrence_id IS NOT NULL
    THEN
      RAISE EXCEPTION 'Exact exclusive Company Requirement and governing Ledger required'
        USING ERRCODE='42501';
    END IF;

    -- Existing single common source law remains unchanged. Its signed
    -- native Ledger owner, current disclosures and Requirement -> Reality
    -- reference checks are NOT copied or weakened by this envelope.
    v_source:=atlas.universal_rulebook_common_source_preflight_internal_v1(
      p_organization_id,p_ledger_id,p_work_requirement_id);
    IF (v_source->>'state') IS DISTINCT FROM
       'common_checks_only_not_admitted'
    THEN
      RAISE EXCEPTION 'Original governed Organization Requirement preflight unavailable'
        USING ERRCODE='42501';
    END IF;
    RETURN jsonb_build_object(
      'contractVersion','uni_ops_typed_requirement_source_union_held_v1',
      'sourceFamily','company_work_requirement',
      'state','typed_company_original_requirement_common_checks_only',
      'jurisdictionKind','organization',
      'jurisdictionNativeId',p_organization_id,
      'governingNativeLedgerId',p_ledger_id,
      'originalRequirementSourceTable','atlas.work_requirements',
      'originalRequirementSourceId',p_work_requirement_id,
      'originalNeedKey',v_source->>'needKey',
      'canonicalRealitySubjectId',v_source->>'subjectEntityId',
      'sourceEvidenceTogetherCurrent',true,
      'nativeCompanyCommonPreflightPassed',true,
      'nativeHouseholdSourceClaimed',false,
      'companyWorkRequirementRowCreated',false,
      'policyAdoptable',false,
      'policyExecutable',false,
      'jurisdictionAdmissionAuthorized',false,
      'workCreated',false,'clockAdmitted',false,
      'successorWorkCreated',false
    );
  ELSE
    RAISE EXCEPTION 'Unsupported typed original Requirement source family'
      USING ERRCODE='42501';
  END IF;
END;
$source_union$;

-- Does not surface via PostgREST, authenticated roles or service_role.
REVOKE ALL ON FUNCTION
  atlas.uni_ops_typed_requirement_source_union_internal_v1(
    text,uuid,uuid,uuid,uuid,uuid,uuid,uuid
  ) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

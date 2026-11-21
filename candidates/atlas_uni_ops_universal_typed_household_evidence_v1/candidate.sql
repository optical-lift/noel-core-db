-- UNI-OPS-01 U5: one TYPED nonfarm source verifier, for universal admission.
-- HELD SOURCE ONLY. Not a migration, a Rulebook, a new identity registry,
-- a synthetic company Ledger, a Household Work writer or a public grant.
-- Does not expand the separately signed U1A exact-spatial authorization.
BEGIN;

CREATE FUNCTION atlas.universal_rulebook_household_native_evidence_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $household_source$
DECLARE
  v_principal_id uuid;
  v_governor_person_id uuid;
  v_kernel atlas.household_kernel_instances%ROWTYPE;
  v_current_observation_id uuid;
  v_observation_verified boolean := false;
  v_open_need_verified boolean := false;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL THEN
    RAISE EXCEPTION 'Exact independent Household source required'
      USING ERRCODE='42501';
  END IF;

  -- Same universal first-party current signed Principal law, but a
  -- Household governor is not an Organization Ledger root by impersonation.
  v_principal_id := atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL
     OR v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1() THEN
    RAISE EXCEPTION 'Current signed Household principal unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Reuse ORIGINAL Household jurisdiction, not a copied company root Seat.
  v_governor_person_id := atlas.require_household_governor_self_v1(
    p_household_id);
  IF v_governor_person_id IS NULL THEN
    RAISE EXCEPTION 'Native Household governor unavailable'
      USING ERRCODE='42501';
  END IF;

  SELECT i.* INTO v_kernel
  FROM atlas.household_kernel_instances i
  JOIN atlas.households h ON h.id=i.household_id
  JOIN atlas.world_kernel_definitions d
    ON d.kernel_key=i.kernel_key AND d.version=i.kernel_version
   AND d.scope_kind='household' AND d.active=true
  WHERE i.id=p_kernel_instance_id
    AND i.household_id=p_household_id
    AND i.state='active'
    AND h.status='active'
    AND nullif(btrim(i.kernel_key),'') IS NOT NULL
    AND i.kernel_version>0;

  IF v_kernel.id IS NULL THEN
    RAISE EXCEPTION 'Exact active native Household Subject unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Do not infer a condition from elapsed time, desired configuration,
  -- a recurring Rhythm or merely having an active Household Subject.
  -- Only a matching CURRENT observed condition with its actual original
  -- non-clock-inferred observation may qualify as native source evidence.
  SELECT c.last_observation_id INTO v_current_observation_id
  FROM atlas.care_current_state c
  WHERE c.scope_kind='household'
    AND c.scope_id=p_household_id
    AND c.subject_domain='household'
    AND c.subject_kind='household_kernel_instance'
    AND c.subject_id=v_kernel.id::text
    AND nullif(btrim(c.condition_state),'') IS NOT NULL
  LIMIT 1;

  IF v_current_observation_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM atlas.care_observation_events o
      JOIN atlas.care_current_state c ON c.last_observation_id=o.id
      WHERE o.id=v_current_observation_id
        AND o.scope_kind='household'
        AND o.scope_id=p_household_id
        AND o.subject_domain='household'
        AND o.subject_kind='household_kernel_instance'
        AND o.subject_id=v_kernel.id::text
        AND o.inferred_from_clock=false
        AND o.observed_by_user_id IS NOT NULL
        AND o.observed_at<=now()
        AND nullif(btrim(o.condition_state),'') IS NOT NULL
        AND c.scope_kind=o.scope_kind
        AND c.scope_id=o.scope_id
        AND c.subject_domain=o.subject_domain
        AND c.subject_kind=o.subject_kind
        AND c.subject_id=o.subject_id
        AND c.condition_state=o.condition_state
    ) INTO v_observation_verified;
  END IF;

  IF v_observation_verified THEN
    SELECT EXISTS(
      SELECT 1 FROM atlas.household_need_occurrences_v1 n
      WHERE n.household_id=p_household_id
        AND n.instance_id=v_kernel.id
        AND n.state='open'
        AND n.opened_by_observation_id=v_current_observation_id
    ) INTO v_open_need_verified;
  END IF;

  -- This result is only a TYPED NATIVE source receipt. Not a canonical
  -- Reality identity, not a common Company Ledger root, no independently
  -- verified Foundry statement, no Rulebook and no automatic successor.
  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','universal_typed_native_evidence_v1',
    'custodyKind','household',
    'nativeSubjectKind','household_kernel_instance',
    'householdId',p_household_id,
    'nativeSubjectId',v_kernel.id,
    'nativeKernelKey',v_kernel.kernel_key,
    'state','native_subject_only_not_canonical',
    'nativeSubjectVerified',true,
    'currentObservationSourceVerified',v_observation_verified,
    'openNeedSourceVerified',v_open_need_verified,
    'canonicalRealityBindingVerified',false,
    'commonRequirementVerified',false,
    'independentFoundryReviewVerified',false,
    'domainAdmissionAuthorized',false,
    'policyAdoptable',false,
    'policyExecutable',false,
    'workCreated',false,
    'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$household_source$;

-- Keep direct API, non-Household subjects and arbitrary caller roles closed.
REVOKE ALL ON FUNCTION
  atlas.universal_rulebook_household_native_evidence_internal_v1(
    uuid,uuid
  ) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

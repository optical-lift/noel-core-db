-- UNI-OPS-01 U5: Household native Subject -> Reality IDENTITY PROPOSAL ONLY.
-- HELD CANDIDATE, NOT A MIGRATION OR APPROVED IDENTITY ADJUDICATION.
-- New private append-only proposal evidence carrier, not an identity registry;
-- canonical identity continues to be owned by reality.entities.
-- Do not merge/apply without separately authorized structural review.
BEGIN;

CREATE TABLE atlas.uni_ops_household_reality_identity_proposals_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
  kernel_instance_id uuid NOT NULL REFERENCES atlas.household_kernel_instances(id) ON DELETE RESTRICT,
  candidate_reality_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  candidate_entity_kind text NOT NULL CHECK (length(btrim(candidate_entity_kind)) BETWEEN 1 AND 120),
  proposed_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
  source_action_id uuid NOT NULL,
  claimed_evidence_sha256 text NOT NULL
    CHECK (claimed_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  source_kind text NOT NULL DEFAULT 'household_kernel_instance'
    CHECK (source_kind = 'household_kernel_instance'),
  proposal_state text NOT NULL DEFAULT 'proposed_unreviewed'
    CHECK (proposal_state = 'proposed_unreviewed'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uni_ops_household_identity_action_once_v1 UNIQUE(household_id,source_action_id)
);

ALTER TABLE atlas.uni_ops_household_reality_identity_proposals_v1
  ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.uni_ops_household_reality_identity_proposals_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- No mutation of source history; corrections require separately reviewed,
-- newly signed evidence, not an UPDATE which erases the earlier assertion.
CREATE FUNCTION atlas.uni_ops_household_reality_proposal_immutable_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $guard$
BEGIN
  RAISE EXCEPTION 'Household identity proposal history is immutable'
    USING ERRCODE='42501';
END;
$guard$;

CREATE TRIGGER uni_ops_household_reality_proposal_history_v1
BEFORE UPDATE OR DELETE ON atlas.uni_ops_household_reality_identity_proposals_v1
FOR EACH ROW EXECUTE FUNCTION
  atlas.uni_ops_household_reality_proposal_immutable_guard_v1();

CREATE FUNCTION atlas.uni_ops_propose_household_reality_identity_internal_v1(
  p_household_id uuid,
  p_kernel_instance_id uuid,
  p_candidate_reality_entity_id uuid,
  p_source_action_id uuid,
  p_claimed_evidence_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $proposal$
DECLARE
  v_principal_id uuid;
  v_governor_person_id uuid;
  v_candidate_kind text;
  v_existing atlas.uni_ops_household_reality_identity_proposals_v1%ROWTYPE;
BEGIN
  IF p_household_id IS NULL OR p_kernel_instance_id IS NULL
     OR p_candidate_reality_entity_id IS NULL OR p_source_action_id IS NULL
     OR coalesce(p_claimed_evidence_sha256,'') !~ '^[0-9a-f]{64}$'
  THEN
    RAISE EXCEPTION 'Exact native Subject, candidate and evidence fingerprint required'
      USING ERRCODE='42501';
  END IF;

  -- Current signed first-party principal, never owner metadata or service key.
  v_principal_id := atlas.foundry_current_signed_principal_v1();
  IF v_principal_id IS NULL
     OR v_principal_id IS DISTINCT FROM atlas.current_principal_id_v1()
  THEN
    RAISE EXCEPTION 'Current signed Principal unavailable'
      USING ERRCODE='42501';
  END IF;

  -- An Organization Ledger owner is not a Household governor.
  v_governor_person_id := atlas.require_household_governor_self_v1(p_household_id);
  IF v_governor_person_id IS NULL THEN
    RAISE EXCEPTION 'Current signed Household governor unavailable'
      USING ERRCODE='42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atlas.household_kernel_instances i
    JOIN atlas.households h ON h.id=i.household_id
    JOIN atlas.world_kernel_definitions d
      ON d.kernel_key=i.kernel_key
     AND d.version=i.kernel_version
     AND d.scope_kind='household' AND d.active=true
    WHERE i.id=p_kernel_instance_id AND i.household_id=p_household_id
      AND i.state='active' AND h.status='active'
  ) THEN
    RAISE EXCEPTION 'Active native Household Subject unavailable'
      USING ERRCODE='42501';
  END IF;

  SELECT e.entity_kind INTO v_candidate_kind
  FROM reality.entities e
  WHERE e.id=p_candidate_reality_entity_id AND e.identity_state='canonical'
    AND length(btrim(e.entity_kind)) BETWEEN 1 AND 120;

  IF v_candidate_kind IS NULL THEN
    RAISE EXCEPTION 'Exact existing canonical Reality candidate unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Idempotent action IDs cannot be used to swap the candidate, evidence,
  -- governor, kernel or Household on replay. No auto-resolution on conflict.
  INSERT INTO atlas.uni_ops_household_reality_identity_proposals_v1 (
    household_id,kernel_instance_id,candidate_reality_entity_id,
    candidate_entity_kind,proposed_by_principal_id,source_action_id,
    claimed_evidence_sha256
  ) VALUES (
    p_household_id,p_kernel_instance_id,p_candidate_reality_entity_id,
    v_candidate_kind,v_principal_id,p_source_action_id,
    p_claimed_evidence_sha256
  )
  ON CONFLICT (household_id,source_action_id) DO NOTHING
  RETURNING * INTO v_existing;

  IF v_existing.id IS NULL THEN
    SELECT * INTO v_existing
    FROM atlas.uni_ops_household_reality_identity_proposals_v1 p
    WHERE p.household_id=p_household_id
      AND p.source_action_id=p_source_action_id;

    IF v_existing.id IS NULL
       OR v_existing.kernel_instance_id IS DISTINCT FROM p_kernel_instance_id
       OR v_existing.candidate_reality_entity_id IS DISTINCT FROM p_candidate_reality_entity_id
       OR v_existing.candidate_entity_kind IS DISTINCT FROM v_candidate_kind
       OR v_existing.proposed_by_principal_id IS DISTINCT FROM v_principal_id
       OR v_existing.claimed_evidence_sha256 IS DISTINCT FROM p_claimed_evidence_sha256
    THEN
      RAISE EXCEPTION 'Identity proposal action replay conflict'
        USING ERRCODE='23505';
    END IF;
  END IF;

  -- No claim that a hash equals independently reviewed original evidence;
  -- it is an ASSERTED fingerprint and a review input only.
  RETURN jsonb_build_object(
    'contractVersion','uni_ops_household_reality_identity_proposal_v1',
    'state','source_identity_proposal_only_not_adjudicated',
    'proposalId',v_existing.id,
    'nativeHouseholdId',p_household_id,
    'nativeKernelInstanceId',p_kernel_instance_id,
    'candidateRealityEntityId',p_candidate_reality_entity_id,
    'nativeGovernorVerified',true,
    'candidateExistsCanonical',true,
    'evidenceIndependentlyVerified',false,
    'canonicalIdentityBindingApproved',false,
    'nativeNeedMapped',false,
    'foundryIndependentReviewApproved',false,
    'domainAdmitted',false,
    'policyAdoptable',false,
    'policyExecutable',false,
    'workCreated',false,
    'clockAdmitted',false,
    'successorWorkCreated',false
  );
END;
$proposal$;

-- Unexposed private carrier, with no review/adjudication or release writer.
REVOKE ALL ON FUNCTION
  atlas.uni_ops_propose_household_reality_identity_internal_v1(
    uuid,uuid,uuid,uuid,text
  ) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION
  atlas.uni_ops_household_reality_proposal_immutable_guard_v1()
  FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

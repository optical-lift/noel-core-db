-- SOURCE ONLY. Shared signed/native Ledger activation PREVIEW, deliberately read-only.
-- No Ledger, Person, Reality identity, onboarding, role, or entitlement writes.
-- Native activation remains held until the source-owned operating-model/runtime
-- proof and signed creation command exist. Application clients receive blocker
-- codes only, not cross-subject source records.
BEGIN;

CREATE FUNCTION atlas.native_ledger_activation_preflight_self_api_v1(
  p_implementation_case_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $preflight$
DECLARE
  v_uid uuid := auth.uid();
  v_implementation atlas.implementation_cases%ROWTYPE;
  v_native ledger.onboarding_cases%ROWTYPE;
  v_practitioner_person uuid;
  v_person_count bigint := 0;
  v_native_count bigint := 0;
  v_blockers jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL
     OR NOT atlas.implementation_practitioner_authorized_self_v1()
  THEN
    RETURN jsonb_build_object(
      'ok',false,'code','practitioner_authority_required'
    );
  END IF;

  -- A practitioner can see this preview ONLY for the exact case assigned to
  -- their signed credential. The missing/foreign case result is identical.
  IF p_implementation_case_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.implementation_case_participants p
    WHERE p.implementation_case_id=p_implementation_case_id
      AND p.relationship_kind='practitioner'
      AND p.human_user_id=v_uid AND p.active
      AND p.ended_at IS NULL
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','case_unavailable');
  END IF;

  SELECT * INTO v_implementation
  FROM atlas.implementation_cases c WHERE c.id=p_implementation_case_id;
  IF v_implementation.id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','case_unavailable');
  END IF;
  IF v_implementation.case_origin<>'paid_institutional' THEN
    RETURN jsonb_build_object('ok',false,'code','not_institutional_case');
  END IF;

  IF v_implementation.state IN ('closed','cancelled') THEN
    v_blockers:=v_blockers||jsonb_build_array('implementation_not_open');
  END IF;
  IF v_implementation.implementation_purchase_id IS NULL THEN
    v_blockers:=v_blockers||jsonb_build_array('institutional_source_unavailable');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM atlas.implementation_case_participants p
    WHERE p.implementation_case_id=p_implementation_case_id
      AND p.relationship_kind='setup_sponsor'
      AND p.active AND p.ended_at IS NULL AND p.verified_at IS NOT NULL
  ) THEN
    v_blockers:=v_blockers||jsonb_build_array('verified_sponsor_missing');
  END IF;

  SELECT count(DISTINCT b.person_entity_id), min(b.person_entity_id)
    INTO v_person_count,v_practitioner_person
  FROM reality.auth_person_bindings b
  JOIN reality.entities e ON e.id=b.person_entity_id
  WHERE b.auth_user_id=v_uid
    AND b.binding_state='active' AND b.retired_at IS NULL
    AND e.entity_kind='person' AND e.identity_state='canonical';

  IF v_person_count<>1 THEN
    v_blockers:=v_blockers||jsonb_build_array('canonical_practitioner_person_unresolved');
  END IF;

  -- This link cannot be deduced from commercial binding or display text.
  -- The future source-owned adjudication may store the immutable source case
  -- identifier in native onboarding_basis; only the private Ledger authority
  -- can write that record.
  SELECT count(*) INTO v_native_count
  FROM ledger.onboarding_cases n
  WHERE n.case_kind='practitioner_onboarding'
    AND n.onboarding_basis->>'implementationCaseId'
        =p_implementation_case_id::text;

  IF v_native_count<>1 THEN
    v_blockers:=v_blockers||jsonb_build_array(
      CASE WHEN v_native_count=0
        THEN 'native_onboarding_not_admitted'
        ELSE 'native_onboarding_ambiguous' END
    );
  ELSE
    SELECT * INTO v_native
    FROM ledger.onboarding_cases n
    WHERE n.case_kind='practitioner_onboarding'
      AND n.onboarding_basis->>'implementationCaseId'
          =p_implementation_case_id::text
    LIMIT 1;

    IF v_person_count<>1
       OR v_native.practitioner_person_entity_id IS DISTINCT FROM
          v_practitioner_person
    THEN
      v_blockers:=v_blockers||jsonb_build_array(
        'native_practitioner_authority_mismatch'
      );
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM reality.entities e
      WHERE e.id=v_native.subject_entity_id
        AND e.identity_state='canonical'
        AND e.entity_kind IN ('business','institution')
    ) THEN
      v_blockers:=v_blockers||jsonb_build_array(
        'canonical_institutional_subject_unresolved'
      );
    END IF;
    IF v_native.onboarding_state<>'ready_to_activate' THEN
      v_blockers:=v_blockers||jsonb_build_array('native_case_not_ready');
    END IF;
  END IF;

  -- The existing implementation pages have NOT established a governed
  -- operating model or a source-owned runtime proof. Do not imply that the
  -- presence of a ready native case or a purchased entitlement fills this.
  v_blockers:=v_blockers||jsonb_build_array(
    'governed_operating_model_not_verified',
    'runtime_proof_not_verified',
    'signed_native_activation_command_not_released'
  );

  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','native_ledger_activation_preflight_v1',
    'implementationCaseId',p_implementation_case_id,
    'canActivate',false,
    'nativeOnboardingAdmissionState',
      CASE WHEN v_native_count=0 THEN 'not_admitted'
           WHEN v_native_count=1 THEN 'linked'
           ELSE 'ambiguous' END,
    'blockers',v_blockers
  );
END;
$preflight$;

-- Keep the private implementation inaccessible as a direct client entry.
REVOKE ALL ON FUNCTION
  atlas.native_ledger_activation_preflight_self_api_v1(uuid)
  FROM PUBLIC,anon,authenticated;

-- The signed browser uses the existing public -> governed-private RPC pattern.
CREATE FUNCTION public.native_ledger_activation_preflight_self_api_v1(
  p_implementation_case_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = 'pg_catalog'
AS $wrapper$
  SELECT atlas.native_ledger_activation_preflight_self_api_v1(
    p_implementation_case_id
  );
$wrapper$;

REVOKE ALL ON FUNCTION
  public.native_ledger_activation_preflight_self_api_v1(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
  public.native_ledger_activation_preflight_self_api_v1(uuid)
  TO authenticated;

COMMIT;

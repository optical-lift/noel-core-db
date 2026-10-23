BEGIN;

-- Source-only classification, not an authorization to retire or migrate access.
-- Person/Principal are preserved; account replacement requires a separate
-- recipient-consented and provider-revoked transaction.
CREATE OR REPLACE FUNCTION atlas.existing_person_auth_transition_readiness_self_v1(
  p_organization_id uuid, p_person_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE
  v_actor uuid;
  v_active_cred integer;
  v_active_reality integer;
  v_active_principals integer;
  v_active_grants integer;
  v_active_memberships integer;
  v_old_accounts integer;
  v_revoked_legacy_blockers integer;
  v_active_old_sessions integer;
  v_case_state text;
  v_result text;
BEGIN
  v_actor:=atlas.existing_person_claim_signed_actor_v1();
  PERFORM atlas.existing_person_claim_steward_self_v1(
    p_organization_id,p_person_id
  );
  -- Inventory is deliberately keyed ONLY by canonical Person, not by email.
  SELECT count(*)::integer INTO v_active_cred
  FROM atlas.person_auth_credentials c
  WHERE c.person_id=p_person_id AND c.status='active'
    AND c.retired_at IS NULL;
  SELECT count(*)::integer INTO v_active_reality
  FROM reality.auth_person_bindings b
  WHERE b.person_entity_id=p_person_id AND b.binding_state='active'
    AND b.retired_at IS NULL;
  SELECT count(*)::integer INTO v_active_principals
  FROM atlas.principals p WHERE p.person_id=p_person_id AND p.status='active';
  SELECT count(*)::integer INTO v_active_grants
  FROM atlas.principals p
  JOIN atlas.principal_ledger_authorities a ON a.principal_id=p.id
  WHERE p.person_id=p_person_id AND p.status='active' AND a.status='active';
  SELECT count(*)::integer INTO v_active_memberships
  FROM atlas.organization_memberships m
  WHERE m.person_id=p_person_id AND m.active=true;
  SELECT count(*)::integer INTO v_old_accounts
  FROM atlas.person_auth_credentials c
  WHERE c.person_id=p_person_id;
  SELECT count(*)::integer INTO v_revoked_legacy_blockers
  FROM atlas.person_auth_credentials c
  JOIN auth.users u ON u.id=c.auth_user_id
  WHERE c.person_id=p_person_id AND c.status='retired'
    AND u.deleted_at IS NULL
    AND (u.banned_until IS NULL OR u.banned_until<=now());
  SELECT count(*)::integer INTO v_active_old_sessions
  FROM atlas.person_auth_credentials c
  JOIN auth.sessions s ON s.user_id=c.auth_user_id
  WHERE c.person_id=p_person_id AND c.status='retired'
    AND (s.not_after IS NULL OR s.not_after>now());
  SELECT case_state INTO v_case_state
  FROM atlas.existing_person_auth_claim_cases
  WHERE person_entity_id=p_person_id
    AND case_state IN ('prepared','accepted','approved')
  LIMIT 1;
  v_result:=CASE
    WHEN v_active_cred>1 OR v_active_reality>1
      OR v_active_cred<>v_active_reality
      OR EXISTS (
        SELECT 1 FROM atlas.person_auth_credentials c
        JOIN reality.auth_person_bindings b ON b.person_entity_id=c.person_id
        WHERE c.person_id=p_person_id AND c.status='active'
          AND c.retired_at IS NULL AND b.binding_state='active'
          AND b.retired_at IS NULL
          AND (c.auth_user_id<>b.auth_user_id OR c.id<>b.id)
      ) THEN 'identity_conflict'
    WHEN v_revoked_legacy_blockers>0 OR v_active_old_sessions>0
      THEN 'retired_access_needs_revocation'
    WHEN v_case_state IS NOT NULL THEN 'claim_in_progress'
    WHEN v_active_grants>0 OR v_active_memberships>0
      THEN 'requires_explicit_authority_transfer_review'
    WHEN v_active_cred>0 OR v_active_principals>0
      THEN 'requires_old_credential_retirement'
    ELSE 'ready_for_existing_person_claim'
  END;
  RETURN jsonb_build_object(
    'ok',true,
    'personId',p_person_id,
    'state',v_result,
    'activeCredentialExists',v_active_cred>0,
    'activeRealityBindingExists',v_active_reality>0,
    'activePrincipalExists',v_active_principals>0,
    'principalHasLedgerAuthority',v_active_grants>0,
    'institutionalMembershipAuthorityExists',v_active_memberships>0,
    'retiredAccountCanSignIn',v_revoked_legacy_blockers>0,
    'retiredAccountHasLiveSession',v_active_old_sessions>0,
    'hasPriorCredentials',v_old_accounts>0,
    'claimInProgress',v_case_state IS NOT NULL,
    'canPrepareRegularClaim',v_result='ready_for_existing_person_claim',
    'doesNotTransferAuthority',true,
    'doesNotRetireAuth',true
  );
END
$fn$;

CREATE OR REPLACE FUNCTION public.existing_person_auth_transition_readiness_self_api_v1(
 p_organization_id uuid,p_person_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$
 SELECT atlas.existing_person_auth_transition_readiness_self_v1(
   p_organization_id,p_person_id
 )
$fn$;

REVOKE ALL ON FUNCTION
 atlas.existing_person_auth_transition_readiness_self_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 atlas.existing_person_auth_transition_readiness_self_v1(uuid,uuid)
 TO authenticated;
REVOKE ALL ON FUNCTION
 public.existing_person_auth_transition_readiness_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.existing_person_auth_transition_readiness_self_api_v1(uuid,uuid)
 TO authenticated;

COMMIT;

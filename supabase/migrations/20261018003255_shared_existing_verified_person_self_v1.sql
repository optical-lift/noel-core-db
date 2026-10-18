-- Shared identity bridge v1: safely admit existing verified human identity.
-- No UID, Person, email, seat, membership, Principal, or purchasing arguments.
-- Do not import all legacy users: each human's own verified session is required.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.admit_existing_verified_person_self_api_v1()
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $body$
DECLARE
  v_uid uuid := auth.uid();
  v_legacy atlas.person_auth_credentials%ROWTYPE;
  v_person atlas.people%ROWTYPE;
  v_entity reality.entities%ROWTYPE;
  v_binding reality.auth_person_bindings%ROWTYPE;
  v_count integer;
  v_eligible boolean;
  v_principal atlas.principals%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';
  END IF;
  -- Do not trust a passed email or client-controlled user metadata.
  PERFORM 1 FROM auth.users u
    WHERE u.id=v_uid AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
      AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until <= now());
  IF NOT FOUND THEN
    RAISE EXCEPTION 'A verified human Auth session is required'
      USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.existing_verified_person_admission:'||v_uid::text,0));

  -- One active legacy credential must identify precisely one existing Person.
  SELECT count(*)::integer INTO v_count
    FROM atlas.person_auth_credentials c
    WHERE c.auth_user_id=v_uid
      AND c.credential_kind='supabase_auth_user'
      AND c.status='active' AND c.retired_at IS NULL;
  IF v_count=0 THEN
    RETURN jsonb_build_object('ok',true,'state','not_applicable');
  END IF;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Multiple active Person credentials require identity review'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO STRICT v_legacy FROM atlas.person_auth_credentials c
    WHERE c.auth_user_id=v_uid
      AND c.credential_kind='supabase_auth_user'
      AND c.status='active' AND c.retired_at IS NULL;
  SELECT * INTO v_person FROM atlas.people p
    WHERE p.id=v_legacy.person_id AND p.status='active';
  IF v_person.id IS NULL OR nullif(btrim(v_person.display_name),'') IS NULL THEN
    RAISE EXCEPTION 'Existing active Person identity required'
      USING ERRCODE='23514';
  END IF;

  -- A recognized Personal Atlas Principal takes the existing, stricter
  -- Principal-specific admission function, not the employee-only path.
  SELECT * INTO v_principal FROM atlas.principals p
    WHERE p.user_id=v_uid AND p.status='active';
  IF v_principal.id IS NOT NULL THEN
    IF v_principal.person_id IS DISTINCT FROM v_person.id THEN
      RAISE EXCEPTION 'Principal/Person identity conflict'
        USING ERRCODE='23514';
    END IF;
    PERFORM atlas.admit_existing_person_identity_self_v1();
    RETURN jsonb_build_object('ok',true,'state','admitted',
      'identityPath','existing_principal');
  END IF;

  -- An employee without a Principal is admitted ONLY if an existing
  -- active institutional credential, membership, seat and Person agree.
  SELECT EXISTS (
    SELECT 1
    FROM atlas.organization_member_credentials oc
    JOIN atlas.organization_memberships m
      ON m.id=oc.organization_membership_id AND m.organization_id=oc.organization_id
    JOIN atlas.organization_employee_seats s
      ON s.id=oc.employee_seat_id AND s.organization_membership_id=m.id
         AND s.organization_id=m.organization_id
    JOIN atlas.organizations o ON o.id=m.organization_id
    WHERE oc.auth_user_id=v_uid AND oc.credential_kind='auth_user'
      AND oc.status='active' AND (oc.expires_at IS NULL OR oc.expires_at>now())
      AND m.person_id=v_legacy.person_id
      AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
      AND s.status='active' AND s.seat_class='employee'
      AND o.status='active'
  ) INTO v_eligible;
  IF NOT v_eligible THEN
    RETURN jsonb_build_object('ok',true,'state','not_applicable');
  END IF;

  -- No email/name heuristics, different UUIDs, or second Person objects.
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.auth_user_id=v_uid AND b.binding_state='active'
      AND b.retired_at IS NULL
      AND (b.person_entity_id<>v_legacy.person_id OR b.id<>v_legacy.id)
  ) THEN
    RAISE EXCEPTION 'Existing canonical Auth/Person binding conflicts'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.id=v_legacy.id
      AND (b.auth_user_id<>v_uid OR b.person_entity_id<>v_legacy.person_id)
  ) THEN
    RAISE EXCEPTION 'Legacy credential binding ID collision'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.person_entity_id=v_legacy.person_id
      AND b.auth_user_id<>v_uid AND b.binding_state='active'
      AND b.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Person is bound to a different active Auth user'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.stable_key='legacy-atlas-person:'||v_legacy.person_id::text
      AND e.id<>v_legacy.person_id
  ) THEN
    RAISE EXCEPTION 'Canonical Person stable-key collision'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_entity FROM reality.entities e WHERE e.id=v_legacy.person_id;
  IF v_entity.id IS NOT NULL
    AND (v_entity.entity_kind<>'person' OR v_entity.identity_state<>'canonical') THEN
    RAISE EXCEPTION 'Existing identity is not a canonical Person'
      USING ERRCODE='23514';
  END IF;

  IF v_entity.id IS NULL THEN
    INSERT INTO reality.entities(
      id,stable_key,entity_kind,display_name,identity_state,metadata
    ) VALUES(
      v_legacy.person_id,
      'legacy-atlas-person:'||v_legacy.person_id::text,
      'person',v_person.display_name,'canonical',
      jsonb_build_object('admissionState','existing_verified_employee',
        'source','atlas.person_auth_credentials',
        'admissionContract','shared_existing_verified_person_self_v1')
    );
  END IF;

  SELECT * INTO v_binding FROM reality.auth_person_bindings b
    WHERE b.auth_user_id=v_uid AND b.binding_state='active' AND b.retired_at IS NULL;
  IF v_binding.id IS NULL THEN
    INSERT INTO reality.auth_person_bindings(
      id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at
    ) VALUES (
      v_legacy.id,v_uid,v_legacy.person_id,'active',
      jsonb_build_object('admissionState','existing_verified_employee',
        'source','atlas.person_auth_credentials',
        'legacyCredentialId',v_legacy.id,
        'legacyProvenance',v_legacy.provenance,
        'contract','shared_existing_verified_person_self_v1'),
      v_legacy.bound_at
    );
  END IF;

  -- The existing auth-binding trigger may create a native Personal Atlas
  -- identity container; this function creates NO Principal, purchase, grant,
  -- authority, institutional seat or new Auth user.
  RETURN jsonb_build_object('ok',true,'state','admitted',
    'identityPath','existing_employee');
END;
$body$;

REVOKE ALL ON FUNCTION atlas.admit_existing_verified_person_self_api_v1()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.admit_existing_verified_person_self_api_v1()
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admit_existing_verified_person_self_api_v1()
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $body$
  SELECT atlas.admit_existing_verified_person_self_api_v1();
$body$;
REVOKE ALL ON FUNCTION public.admit_existing_verified_person_self_api_v1()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_existing_verified_person_self_api_v1()
  TO authenticated;
COMMIT;

-- Atlas multi-email identity registry. SOURCE-ONLY; do not run on production.
-- Genuine Supabase email OTP uses the ONE current verified auth.users.email.
-- All secondary aliases are non-login until a separately released broker.
BEGIN;

CREATE TABLE atlas.person_sign_in_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id uuid NOT NULL REFERENCES atlas.people(id),
  auth_user_id uuid NOT NULL REFERENCES auth.users(id),
  normalized_email text NOT NULL CHECK (
    normalized_email=lower(btrim(normalized_email))
    AND length(normalized_email) BETWEEN 3 AND 320
    AND normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  ),
  verification_state text NOT NULL CHECK
    (verification_state IN ('pending','verified','retired','disputed')),
  sign_in_transport text NOT NULL DEFAULT 'none' CHECK
    (sign_in_transport IN ('none','primary_auth','approved_alias_broker')),
  preferred boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  verified_proof_receipt text,
  identity_case_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(person_id,normalized_email),
  CHECK (NOT preferred OR verification_state='verified'),
  CHECK (verification_state='verified' OR sign_in_transport='none'),
  CHECK (sign_in_transport<>'primary_auth' OR preferred),
  CHECK (sign_in_transport<>'approved_alias_broker') -- future broker NOT released
);

-- A verified email may not be claimed for two canonical people.
CREATE UNIQUE INDEX person_sign_in_verified_address_unique_v1
  ON atlas.person_sign_in_emails(normalized_email)
  WHERE verification_state='verified';
CREATE UNIQUE INDEX person_sign_in_one_preferred_v1
  ON atlas.person_sign_in_emails(person_id)
  WHERE preferred;
CREATE UNIQUE INDEX person_sign_in_one_native_primary_v1
  ON atlas.person_sign_in_emails(auth_user_id)
  WHERE sign_in_transport='primary_auth';

ALTER TABLE atlas.person_sign_in_emails ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.person_sign_in_emails FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.person_sign_in_emails_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_email text;
  v_confirmed boolean;
  v_person uuid;
  v_count integer;
  v_items jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Verified Atlas Auth required.' USING errcode='42501';
  END IF;
  SELECT lower(u.email),u.email_confirmed_at IS NOT NULL
    INTO v_email,v_confirmed
  FROM auth.users u WHERE u.id=v_user AND u.deleted_at IS NULL;
  IF v_email IS NULL OR NOT v_confirmed THEN
    RAISE EXCEPTION 'Verified Atlas email is required.' USING errcode='42501';
  END IF;
  SELECT count(*) INTO v_count
  FROM atlas.person_auth_credentials c
  JOIN atlas.people p ON p.id=c.person_id AND p.status='active'
  WHERE c.auth_user_id=v_user AND c.status='active'
    AND c.credential_kind='supabase_auth_user' AND c.retired_at IS NULL;
  SELECT c.person_id INTO v_person
  FROM atlas.person_auth_credentials c
  WHERE c.auth_user_id=v_user AND c.status='active'
    AND c.credential_kind='supabase_auth_user' AND c.retired_at IS NULL
  LIMIT 1;
  IF v_count<>1 THEN
    RETURN jsonb_build_object('ok',false,'reason','person_binding_not_unique');
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'email',a.normalized_email,'verificationState',a.verification_state,
    'signInTransport',a.sign_in_transport,'preferred',a.preferred,
    'brokerReleaseVerified',false
  ) ORDER BY a.preferred DESC,a.created_at),'[]'::jsonb)
  INTO v_items FROM atlas.person_sign_in_emails a
  WHERE a.person_id=v_person AND a.auth_user_id=v_user;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','person_sign_in_emails_self_v1',
    'personId',v_person,'authUserId',v_user,'emails',v_items,
    'truthBoundary',jsonb_build_object(
      'emailNotPerson',true,'aliasNotNativeOtp',true,
      'preferredDoesNotCreatePrincipal',true));
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.reconcile_person_native_sign_in_email_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_email text;
  v_confirmed boolean;
  v_person uuid;
  v_count integer;
  v_prior atlas.person_sign_in_emails%rowtype;
  v_result atlas.person_sign_in_emails%rowtype;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING errcode='42501';
  END IF;
  SELECT lower(u.email),u.email_confirmed_at IS NOT NULL
    INTO v_email,v_confirmed
    FROM auth.users u WHERE u.id=v_user AND u.deleted_at IS NULL;
  IF v_email IS NULL OR NOT v_confirmed THEN
    RAISE EXCEPTION 'Confirmed Auth email required.' USING errcode='42501';
  END IF;
  SELECT count(*) INTO v_count
  FROM atlas.person_auth_credentials c
  JOIN atlas.people p ON p.id=c.person_id AND p.status='active'
  WHERE c.auth_user_id=v_user AND c.credential_kind='supabase_auth_user'
    AND c.status='active' AND c.retired_at IS NULL;
  SELECT c.person_id INTO v_person
  FROM atlas.person_auth_credentials c
  WHERE c.auth_user_id=v_user AND c.credential_kind='supabase_auth_user'
    AND c.status='active' AND c.retired_at IS NULL
  LIMIT 1;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Unique existing Person credential required.' USING errcode='23514';
  END IF;
  PERFORM 1 FROM atlas.people p WHERE p.id=v_person FOR UPDATE;
  SELECT * INTO v_prior FROM atlas.person_sign_in_emails a
  WHERE a.person_id=v_person AND a.normalized_email=v_email FOR UPDATE;
  IF v_prior.id IS NOT NULL AND (v_prior.verification_state='disputed'
      OR v_prior.auth_user_id<>v_user) THEN
    RAISE EXCEPTION 'Email identity requires independent review.' USING errcode='42501';
  END IF;
  IF EXISTS (SELECT 1 FROM atlas.person_sign_in_emails a
     WHERE a.normalized_email=v_email AND a.person_id<>v_person AND a.verification_state='verified') THEN
    RAISE EXCEPTION 'Email belongs to a different verified Person.' USING errcode='23505';
  END IF;
  -- Auth is authoritative: existing primary becomes historical when confirmed
  -- Auth email changes, but historical Person provenance remains readable.
  UPDATE atlas.person_sign_in_emails a
    SET preferred=false,sign_in_transport='none',
      verification_state=CASE WHEN a.sign_in_transport='primary_auth'
        THEN 'retired' ELSE a.verification_state END,
      updated_at=now()
  WHERE a.person_id=v_person AND a.auth_user_id=v_user
    AND (a.preferred OR a.sign_in_transport='primary_auth')
    AND a.normalized_email<>v_email;
  INSERT INTO atlas.person_sign_in_emails(
    person_id,auth_user_id,normalized_email,verification_state,
    sign_in_transport,preferred,verified_at,verified_proof_receipt
  )
  VALUES (v_person,v_user,v_email,'verified','primary_auth',true,
    now(),'supabase_auth_confirmed_self_v1')
  ON CONFLICT (person_id,normalized_email) DO UPDATE
    SET verification_state='verified',sign_in_transport='primary_auth',
        preferred=true,verified_at=coalesce(atlas.person_sign_in_emails.verified_at,now()),
        updated_at=now()
  RETURNING * INTO v_result;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','person_sign_in_native_reconcile_v1',
    'personId',v_person,'authUserId',v_user,
    'preferredEmail',v_result.normalized_email,
    'nativeOtpReady',true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.person_sign_in_emails_self_api_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.person_sign_in_emails_self_api_v1();
$function$;
CREATE OR REPLACE FUNCTION public.reconcile_person_native_sign_in_email_self_api_v1()
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
  SELECT atlas.reconcile_person_native_sign_in_email_self_api_v1();
$function$;

REVOKE ALL ON FUNCTION atlas.person_sign_in_emails_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.reconcile_person_native_sign_in_email_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.person_sign_in_emails_self_api_v1() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.reconcile_person_native_sign_in_email_self_api_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.person_sign_in_emails_self_api_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_person_native_sign_in_email_self_api_v1() TO authenticated;

COMMIT;

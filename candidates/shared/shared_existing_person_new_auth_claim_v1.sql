BEGIN;

-- SOURCE-ONLY SHARED CANDIDATE. Not a numbered migration. Never paste into
-- production SQL. Must pass protected schema clone, signed Auth tests,
-- shared identity/privacy review and owner-controlled migration release.
-- Scope: attach a genuinely new, already authenticated Auth user to an
-- existing canonical Reality Person with NO competing active Auth authority.
-- This does NOT deliver invitations, transfer Principals, or retire accounts.

CREATE TABLE atlas.existing_person_auth_claim_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id),
  person_entity_id uuid NOT NULL REFERENCES reality.entities(id),
  proposed_email text NOT NULL
    CHECK (proposed_email=lower(btrim(proposed_email))
      AND proposed_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
      AND length(proposed_email)<=320),
  case_state text NOT NULL DEFAULT 'prepared'
    CHECK (case_state IN ('prepared','accepted','approved','completed',
                         'conflicted','rejected','expired')),
  prepared_by_user_id uuid NOT NULL REFERENCES auth.users(id),
  preparation_basis text NOT NULL
    CHECK (length(btrim(preparation_basis)) BETWEEN 40 AND 1800),
  claimant_auth_user_id uuid REFERENCES auth.users(id),
  claimant_accepted_at timestamptz,
  reviewed_by_user_id uuid REFERENCES auth.users(id),
  review_method text CHECK (review_method IN
    ('verified_in_person','verified_video_call')),
  review_basis text CHECK (review_basis IS NULL OR
    length(btrim(review_basis)) BETWEEN 40 AND 1800),
  reviewed_at timestamptz,
  conflict_reason text,
  completed_binding_id uuid REFERENCES reality.auth_person_bindings(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now()+interval '7 days'),
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (claimant_accepted_at IS NULL OR claimant_auth_user_id IS NOT NULL),
  CHECK (reviewed_at IS NULL OR (
    reviewed_by_user_id IS NOT NULL AND review_method IS NOT NULL
    AND review_basis IS NOT NULL)),
  CHECK (completed_at IS NULL OR completed_binding_id IS NOT NULL)
);

-- One unresolved claimant association per Person. No duplicate authority.
CREATE UNIQUE INDEX existing_person_auth_claim_one_pending_v1
ON atlas.existing_person_auth_claim_cases(person_entity_id)
WHERE case_state IN ('prepared','accepted','approved');

-- Current legacy credential table previously allowed several active
-- credentials for one Person; live preflight found none duplicated.
-- Review preconditions again in protected clone before release.
CREATE UNIQUE INDEX person_auth_one_active_person_shared_v1
ON atlas.person_auth_credentials(person_id)
WHERE status='active' AND retired_at IS NULL;

REVOKE ALL ON TABLE atlas.existing_person_auth_claim_cases
  FROM PUBLIC, anon, authenticated;

-- Reuse the existing signed institution identity-steward authority.
-- This authority DOES NOT come from holding an email address or knowing a UUID.
CREATE FUNCTION atlas.existing_person_claim_steward_self_v1(
  p_organization_id uuid, p_person_id uuid
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  PERFORM atlas.require_identity_steward_v1(p_organization_id);
  IF atlas.current_person_id_v1() IS NULL
    OR NOT EXISTS (SELECT 1 FROM atlas.principals p
      WHERE p.user_id=auth.uid() AND p.status='active')
    OR NOT EXISTS (SELECT 1 FROM atlas.institutional_person_records r
      WHERE r.organization_id=p_organization_id
        AND r.person_id=p_person_id AND r.status='active')
    OR NOT EXISTS (SELECT 1 FROM atlas.people p
      WHERE p.id=p_person_id AND p.status='active')
    OR NOT EXISTS (SELECT 1 FROM reality.entities e
      WHERE e.id=p_person_id AND e.entity_kind='person'
        AND e.identity_state='canonical')
  THEN
    RAISE EXCEPTION 'Authorized steward and exact existing canonical Person required'
      USING errcode='42501';
  END IF;
END
$fn$;

-- Require a fresh provider-backed, confirmed non-anonymous human session.
-- A stale JWT from a signed-out session cannot perform identity transitions.
CREATE FUNCTION atlas.existing_person_claim_signed_actor_v1()
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT EXISTS (
   SELECT 1 FROM auth.users u
   JOIN auth.sessions s ON s.user_id=u.id
   WHERE u.id=v_user AND u.deleted_at IS NULL
     AND u.email_confirmed_at IS NOT NULL
     AND NOT coalesce(u.is_anonymous,false)
     AND (u.banned_until IS NULL OR u.banned_until<=now())
     AND s.id::text=auth.jwt()->>'session_id'
     AND (s.not_after IS NULL OR s.not_after>now())
 ) THEN
   RAISE EXCEPTION 'Fresh verified Auth session required'
     USING errcode='42501';
 END IF;
 RETURN v_user;
END
$fn$;

CREATE FUNCTION atlas.prepare_existing_person_auth_claim_self_v1(
 p_organization_id uuid,p_person_id uuid,p_email text,p_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid; v_email text:=lower(btrim(coalesce(p_email,'')));
 v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 PERFORM atlas.existing_person_claim_steward_self_v1(
   p_organization_id,p_person_id);
 IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
   OR length(v_email)>320
   OR length(btrim(coalesce(p_basis,''))) NOT BETWEEN 40 AND 1800
 THEN RAISE EXCEPTION 'Valid proposed email and source basis required'
   USING errcode='22023'; END IF;

 PERFORM 1 FROM atlas.people WHERE id=p_person_id FOR UPDATE;
 -- Do not silently transfer, revive, or erase a competing active identity.
 IF EXISTS (SELECT 1 FROM atlas.person_auth_credentials
   WHERE person_id=p_person_id AND status='active' AND retired_at IS NULL)
 OR EXISTS (SELECT 1 FROM reality.auth_person_bindings
   WHERE person_entity_id=p_person_id AND binding_state='active'
     AND retired_at IS NULL)
 OR EXISTS (SELECT 1 FROM atlas.principals
   WHERE person_id=p_person_id AND status='active')
 THEN RAISE EXCEPTION 'Existing Auth or Principal authority needs separate retirement review'
   USING errcode='23514'; END IF;

 UPDATE atlas.existing_person_auth_claim_cases
 SET case_state='expired',updated_at=now()
 WHERE person_entity_id=p_person_id
   AND case_state IN ('prepared','accepted','approved') AND expires_at<=now();

 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE person_entity_id=p_person_id AND
   case_state IN ('prepared','accepted','approved')
 FOR UPDATE;
 IF v_case.id IS NOT NULL THEN
   IF v_case.proposed_email<>v_email
     OR v_case.organization_id<>p_organization_id THEN
     RAISE EXCEPTION 'Another pending claim requires review'
       USING errcode='23505';
   END IF;
   RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
     'caseState',v_case.case_state,'idempotentReplay',true);
 END IF;

 INSERT INTO atlas.existing_person_auth_claim_cases(
   organization_id,person_entity_id,proposed_email,prepared_by_user_id,
   preparation_basis
 ) VALUES(p_organization_id,p_person_id,v_email,v_actor,btrim(p_basis))
 RETURNING * INTO v_case;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'caseState',v_case.case_state,'idempotentReplay',false);
END
$fn$;

-- The case identifier can be provided out of band for signed-claim testing.
-- Delivery, claim-email sending, and account creation belong to Build 2.
CREATE FUNCTION atlas.accept_existing_person_auth_claim_self_v1(
 p_case_id uuid,p_explicit_acceptance boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_email text;
 v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 IF p_explicit_acceptance IS DISTINCT FROM true THEN
   RAISE EXCEPTION 'Explicit recipient acceptance required'
     USING errcode='42501'; END IF;
 SELECT lower(u.email) INTO v_email FROM auth.users u WHERE u.id=v_actor;
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
   WHERE id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL OR v_case.expires_at<=now()
   OR v_case.proposed_email<>v_email
   OR v_case.prepared_by_user_id=v_actor
 THEN RAISE EXCEPTION 'No eligible claim for this verified recipient'
   USING errcode='42501'; END IF;
 IF v_case.case_state IN ('accepted','approved','completed')
   AND v_case.claimant_auth_user_id=v_actor THEN
   RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
     'state',v_case.case_state,'idempotentReplay',true);
 END IF;
 IF v_case.case_state<>'prepared'
   OR EXISTS (SELECT 1 FROM atlas.person_auth_credentials
      WHERE auth_user_id=v_actor)
   OR EXISTS (SELECT 1 FROM reality.auth_person_bindings
      WHERE auth_user_id=v_actor)
   OR EXISTS (SELECT 1 FROM atlas.principals WHERE user_id=v_actor)
 THEN RAISE EXCEPTION 'Authenticated claimant conflicts with existing identity'
   USING errcode='23514'; END IF;
 UPDATE atlas.existing_person_auth_claim_cases
 SET case_state='accepted',claimant_auth_user_id=v_actor,
   claimant_accepted_at=now(),updated_at=now()
 WHERE id=v_case.id;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,'state','accepted',
   'idempotentReplay',false);
END
$fn$;

CREATE FUNCTION atlas.approve_existing_person_auth_claim_self_v1(
 p_case_id uuid,p_method text,p_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL THEN
   RAISE EXCEPTION 'Identity case not found' USING errcode='P0002'; END IF;
 PERFORM atlas.existing_person_claim_steward_self_v1(
   v_case.organization_id,v_case.person_entity_id);
 IF v_actor=v_case.claimant_auth_user_id OR
    v_case.expires_at<=now() OR
    p_method NOT IN ('verified_in_person','verified_video_call') OR
    length(btrim(coalesce(p_basis,''))) NOT BETWEEN 40 AND 1800 THEN
   RAISE EXCEPTION 'Independent identity review required'
     USING errcode='42501'; END IF;
 IF v_case.case_state='approved' THEN
   RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
     'state','approved','idempotentReplay',true);
 END IF;
 IF v_case.case_state<>'accepted' OR
   v_case.claimant_accepted_at IS NULL THEN
   RAISE EXCEPTION 'Recipient has not accepted the identity association'
     USING errcode='42501'; END IF;
 UPDATE atlas.existing_person_auth_claim_cases
 SET case_state='approved',reviewed_by_user_id=v_actor,
 review_method=p_method,review_basis=btrim(p_basis),
 reviewed_at=now(),updated_at=now() WHERE id=v_case.id;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
  'state','approved','idempotentReplay',false);
END
$fn$;

CREATE FUNCTION atlas.finish_existing_person_auth_claim_self_v1(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_email text;v_case atlas.existing_person_auth_claim_cases%rowtype;
 v_cred uuid:=gen_random_uuid();
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_actor FOR UPDATE;
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL OR v_case.claimant_auth_user_id<>v_actor
  OR v_case.proposed_email<>v_email OR v_case.expires_at<=now() THEN
  RAISE EXCEPTION 'Verified claimant and live claim required'
    USING errcode='42501'; END IF;
 IF v_case.case_state='completed' THEN
  RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'state','completed','idempotentReplay',true); END IF;
 IF v_case.case_state<>'approved' OR v_case.reviewed_at IS NULL
   OR v_case.reviewed_by_user_id=v_actor THEN
  RAISE EXCEPTION 'Authorized independent approval required'
    USING errcode='42501'; END IF;

 PERFORM 1 FROM atlas.people WHERE id=v_case.person_entity_id
  AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original Person no longer active'
  USING errcode='23514'; END IF;
 PERFORM 1 FROM reality.entities WHERE id=v_case.person_entity_id
  AND entity_kind='person' AND identity_state='canonical' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Canonical Person no longer admissible'
  USING errcode='23514'; END IF;
 PERFORM atlas.existing_person_claim_steward_self_v1(
  v_case.organization_id,v_case.person_entity_id);

 -- No Auth, Principal, or institutional authority may be reassigned by
 -- a mere email match. Existing active credentials need a separate
 -- provider-revocation + explicit migration process before THIS can run.
 IF EXISTS (SELECT 1 FROM atlas.person_auth_credentials
   WHERE person_id=v_case.person_entity_id
     AND status='active' AND retired_at IS NULL)
 OR EXISTS (SELECT 1 FROM reality.auth_person_bindings
   WHERE person_entity_id=v_case.person_entity_id
     AND binding_state='active' AND retired_at IS NULL)
 OR EXISTS (SELECT 1 FROM atlas.principals
   WHERE person_id=v_case.person_entity_id AND status='active')
 OR EXISTS (SELECT 1 FROM atlas.person_auth_credentials
   WHERE auth_user_id=v_actor)
 OR EXISTS (SELECT 1 FROM reality.auth_person_bindings
   WHERE auth_user_id=v_actor)
 OR EXISTS (SELECT 1 FROM atlas.principals
   WHERE user_id=v_actor)
 OR EXISTS (SELECT 1 FROM atlas.organization_memberships
   WHERE user_id=v_actor AND active)
 OR EXISTS (SELECT 1 FROM atlas.person_sign_in_emails
   WHERE normalized_email=v_email AND auth_user_id<>v_actor)
 THEN
  UPDATE atlas.existing_person_auth_claim_cases
  SET case_state='conflicted',
    conflict_reason='existing_identity_or_authority',
    updated_at=now() WHERE id=v_case.id;
  RETURN jsonb_build_object('ok',false,'caseId',v_case.id,
     'state','conflicted','reason','identity_review_required');
 END IF;

 -- Historical decommissioned credentials remain evidence. A retired
 -- legacy account must not still be a valid sign-in or owner/membership.
 IF EXISTS (
  SELECT 1 FROM atlas.person_auth_credentials old
   JOIN auth.users u ON u.id=old.auth_user_id
   WHERE old.person_id=v_case.person_entity_id
     AND old.auth_user_id<>v_actor
     AND ((u.deleted_at IS NULL
       AND (u.banned_until IS NULL OR u.banned_until<=now()))
       OR EXISTS(SELECT 1 FROM auth.sessions s
         WHERE s.user_id=old.auth_user_id
           AND (s.not_after IS NULL OR s.not_after>now()))
       OR EXISTS(SELECT 1 FROM atlas.organization_memberships m
         WHERE m.user_id=old.auth_user_id AND m.active))
 ) THEN
   UPDATE atlas.existing_person_auth_claim_cases
    SET case_state='conflicted',conflict_reason='legacy_access_not_decommissioned',
        updated_at=now() WHERE id=v_case.id;
   RETURN jsonb_build_object('ok',false,'caseId',v_case.id,
      'state','conflicted','reason','legacy_access_review_required');
 END IF;

 INSERT INTO atlas.person_auth_credentials
 (id,person_id,credential_kind,auth_user_id,status,bound_at,provenance)
 VALUES(v_cred,v_case.person_entity_id,'supabase_auth_user',
   v_actor,'active',now(),jsonb_build_object(
     'source','existing_person_new_auth_claim_v1',
     'caseId',v_case.id,'operator',v_case.prepared_by_user_id,
     'recipientAcceptanceAt',v_case.claimant_accepted_at,
     'reviewer',v_case.reviewed_by_user_id,
     'reviewMethod',v_case.review_method));
 INSERT INTO reality.auth_person_bindings
 (id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at)
 VALUES(v_cred,v_actor,v_case.person_entity_id,'active',
   jsonb_build_object('source','existing_person_new_auth_claim_v1',
     'caseId',v_case.id,'recipientAccepted',true,
     'independentReview',true),now());
 INSERT INTO atlas.person_sign_in_emails
 (person_id,auth_user_id,normalized_email,verification_state,
  sign_in_transport,preferred,verified_at,verified_proof_receipt,identity_case_id)
 VALUES(v_case.person_entity_id,v_actor,v_email,'verified','primary_auth',
    true,now(),'verified-auth-session:existing-person-claim:'||v_case.id::text,
    NULL);
 UPDATE atlas.existing_person_auth_claim_cases
  SET case_state='completed',completed_binding_id=v_cred,
     completed_at=now(),updated_at=now() WHERE id=v_case.id;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'state','completed','idempotentReplay',false,
   'personId',v_case.person_entity_id);
END
$fn$;

-- Expose only signed-in wrappers. Private claim table stays outside Data API.
CREATE FUNCTION public.prepare_existing_person_auth_claim_self_api_v1(
 p_organization_id uuid,p_person_id uuid,p_email text,p_basis text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.prepare_existing_person_auth_claim_self_v1(
 p_organization_id,p_person_id,p_email,p_basis) $fn$;
CREATE FUNCTION public.accept_existing_person_auth_claim_self_api_v1(
 p_case_id uuid,p_explicit_acceptance boolean
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.accept_existing_person_auth_claim_self_v1(
 p_case_id,p_explicit_acceptance) $fn$;
CREATE FUNCTION public.approve_existing_person_auth_claim_self_api_v1(
 p_case_id uuid,p_method text,p_basis text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.approve_existing_person_auth_claim_self_v1(
 p_case_id,p_method,p_basis) $fn$;
CREATE FUNCTION public.finish_existing_person_auth_claim_self_api_v1(
 p_case_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.finish_existing_person_auth_claim_self_v1(p_case_id) $fn$;

REVOKE ALL ON FUNCTION atlas.existing_person_claim_steward_self_v1(uuid,uuid),
 atlas.existing_person_claim_signed_actor_v1(),
 atlas.prepare_existing_person_auth_claim_self_v1(uuid,uuid,text,text),
 atlas.accept_existing_person_auth_claim_self_v1(uuid,boolean),
 atlas.approve_existing_person_auth_claim_self_v1(uuid,text,text),
 atlas.finish_existing_person_auth_claim_self_v1(uuid)
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION atlas.existing_person_claim_steward_self_v1(uuid,uuid),
 atlas.existing_person_claim_signed_actor_v1(),
 atlas.prepare_existing_person_auth_claim_self_v1(uuid,uuid,text,text),
 atlas.accept_existing_person_auth_claim_self_v1(uuid,boolean),
 atlas.approve_existing_person_auth_claim_self_v1(uuid,text,text),
 atlas.finish_existing_person_auth_claim_self_v1(uuid) TO authenticated;
REVOKE ALL ON FUNCTION
 public.prepare_existing_person_auth_claim_self_api_v1(uuid,uuid,text,text),
 public.accept_existing_person_auth_claim_self_api_v1(uuid,boolean),
 public.approve_existing_person_auth_claim_self_api_v1(uuid,text,text),
 public.finish_existing_person_auth_claim_self_api_v1(uuid)
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
 public.prepare_existing_person_auth_claim_self_api_v1(uuid,uuid,text,text),
 public.accept_existing_person_auth_claim_self_api_v1(uuid,boolean),
 public.approve_existing_person_auth_claim_self_api_v1(uuid,text,text),
 public.finish_existing_person_auth_claim_self_api_v1(uuid)
 TO authenticated;

COMMIT;
BEGIN;

-- Governed account replacement: this migration defines the DB source authority.
-- Provider revocation runs only on the trusted server after verified claimant,
-- original account consent, and independent steward review.
ALTER TABLE atlas.existing_person_auth_claim_cases
 ADD COLUMN IF NOT EXISTS replaces_auth_user_id uuid REFERENCES auth.users(id),
 ADD COLUMN IF NOT EXISTS replaces_credential_id uuid REFERENCES atlas.person_auth_credentials(id),
 ADD COLUMN IF NOT EXISTS old_account_consented_at timestamptz,
 ADD COLUMN IF NOT EXISTS old_account_consented_session_id uuid,
 ADD COLUMN IF NOT EXISTS replacement_principal_id uuid REFERENCES atlas.principals(id);

ALTER TABLE atlas.existing_person_auth_claim_cases
 ADD CONSTRAINT existing_person_claim_replacement_old_consent_v1
 CHECK (old_account_consented_at IS NULL OR
  (replaces_auth_user_id IS NOT NULL AND old_account_consented_session_id IS NOT NULL));

-- Old account is a separate actor from the claimant. Do not use an email to
-- locate old Person; exact existing credential + Reality binding are required.
CREATE FUNCTION atlas.prepare_existing_person_auth_replacement_self_v1(
 p_organization_id uuid,p_person_id uuid,p_new_email text,p_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_email text:=lower(btrim(coalesce(p_new_email,'')));
 v_legacy atlas.person_auth_credentials%rowtype;
 v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 PERFORM atlas.existing_person_claim_steward_self_v1(p_organization_id,p_person_id);
 IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    OR length(v_email)>320
    OR length(btrim(coalesce(p_basis,''))) NOT BETWEEN 40 AND 1800
 THEN RAISE EXCEPTION 'Verified email and identity evidence required'
  USING errcode='22023'; END IF;
 PERFORM 1 FROM atlas.people WHERE id=p_person_id AND status='active' FOR UPDATE;
 SELECT * INTO v_legacy FROM atlas.person_auth_credentials
 WHERE person_id=p_person_id AND status='active' AND retired_at IS NULL
 FOR UPDATE;
 IF v_legacy.id IS NULL
  OR NOT EXISTS(SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.id=v_legacy.id AND b.person_entity_id=p_person_id
      AND b.auth_user_id=v_legacy.auth_user_id
      AND b.binding_state='active' AND b.retired_at IS NULL)
  OR (SELECT count(*) FROM reality.auth_person_bindings b
    WHERE b.person_entity_id=p_person_id AND b.binding_state='active'
      AND b.retired_at IS NULL)<>1
  OR (SELECT count(*) FROM atlas.person_auth_credentials c
    WHERE c.person_id=p_person_id AND c.status='active'
      AND c.retired_at IS NULL)<>1
 THEN RAISE EXCEPTION 'One exact existing active Person credential required'
   USING errcode='23514'; END IF;
 IF EXISTS (SELECT 1 FROM atlas.principal_ledger_authorities a
     JOIN atlas.principals p ON p.id=a.principal_id
     WHERE p.person_id=p_person_id AND a.status='active')
   OR EXISTS (SELECT 1 FROM atlas.organization_memberships m
     WHERE m.user_id=v_legacy.auth_user_id AND m.active)
   OR EXISTS (SELECT 1 FROM atlas.principals p
     WHERE p.person_id=p_person_id AND p.status='active'
       AND p.user_id<>v_legacy.auth_user_id)
 THEN RAISE EXCEPTION 'Account has delegated or conflicting authority; separate governance required'
   USING errcode='42501'; END IF;
 IF v_actor=v_legacy.auth_user_id THEN
   RAISE EXCEPTION 'Independent source steward must prepare a replacement'
     USING errcode='42501'; END IF;
 IF EXISTS (SELECT 1 FROM auth.users u
   WHERE u.id=v_legacy.auth_user_id AND lower(u.email)=v_email)
 THEN RAISE EXCEPTION 'New verified Auth must have a different email'
   USING errcode='22023'; END IF;
 UPDATE atlas.existing_person_auth_claim_cases
  SET case_state='expired',updated_at=now()
  WHERE person_entity_id=p_person_id
    AND case_state IN ('prepared','accepted','approved') AND expires_at<=now();
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE person_entity_id=p_person_id
   AND case_state IN ('prepared','accepted','approved') FOR UPDATE;
 IF v_case.id IS NOT NULL THEN
  IF v_case.organization_id<>p_organization_id OR v_case.proposed_email<>v_email
    OR v_case.replaces_auth_user_id IS DISTINCT FROM v_legacy.auth_user_id
  THEN RAISE EXCEPTION 'Another identity claim is pending adjudication'
    USING errcode='23505'; END IF;
  RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
    'caseState',v_case.case_state,'idempotentReplay',true);
 END IF;
 INSERT INTO atlas.existing_person_auth_claim_cases(
  organization_id,person_entity_id,proposed_email,prepared_by_user_id,
  preparation_basis,replaces_auth_user_id,replaces_credential_id)
 VALUES(p_organization_id,p_person_id,v_email,v_actor,btrim(p_basis),
  v_legacy.auth_user_id,v_legacy.id)
 RETURNING * INTO v_case;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'caseState','prepared','requiresOldAccountConsent',true,
   'requiresProviderRevocation',true,'idempotentReplay',false);
END
$fn$;


CREATE FUNCTION atlas.inspect_existing_person_auth_replacement_old_self_v1(
 p_case_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases WHERE id=p_case_id;
 IF v_case.id IS NULL OR v_case.replaces_auth_user_id<>v_actor
 THEN RAISE EXCEPTION 'No replacement for this original account'
   USING errcode='42501'; END IF;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
    'intendedPersonName',(SELECT display_name FROM atlas.people
       WHERE id=v_case.person_entity_id),
    'proposedEmail',v_case.proposed_email,
    'caseState',v_case.case_state,
    'oldAccountConsented',v_case.old_account_consented_at IS NOT NULL,
    'expiresAt',v_case.expires_at);
END
$fn$;

CREATE FUNCTION atlas.consent_existing_person_auth_replacement_old_self_v1(
 p_case_id uuid,p_explicit_retirement_consent boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 IF p_explicit_retirement_consent IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Old account holder must explicitly consent'
    USING errcode='42501'; END IF;
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL OR v_case.replaces_auth_user_id<>v_actor
   OR v_case.expires_at<=now()
   OR v_case.case_state NOT IN ('prepared','accepted','approved')
 THEN RAISE EXCEPTION 'Old account is not authorized for this replacement'
   USING errcode='42501'; END IF;
 IF v_case.old_account_consented_at IS NOT NULL THEN
  RETURN jsonb_build_object('ok',true,'state','old_account_consented',
   'idempotentReplay',true); END IF;
 UPDATE atlas.existing_person_auth_claim_cases
  SET old_account_consented_at=now(),
    old_account_consented_session_id=(auth.jwt()->>'session_id')::uuid,
    updated_at=now()
  WHERE id=v_case.id;
 RETURN jsonb_build_object('ok',true,'state','old_account_consented',
  'idempotentReplay',false);
END
$fn$;

CREATE FUNCTION atlas.plan_existing_person_auth_replacement_self_v1(
 p_case_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_case atlas.existing_person_auth_claim_cases%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases WHERE id=p_case_id;
 IF v_case.id IS NULL OR v_case.case_state<>'approved'
  OR v_case.claimant_auth_user_id<>v_actor
  OR v_case.replaces_auth_user_id IS NULL
  OR v_case.old_account_consented_at IS NULL
  OR v_case.reviewed_at IS NULL OR v_case.reviewed_by_user_id=v_actor
  OR v_case.reviewed_by_user_id=v_case.replaces_auth_user_id
  OR v_case.expires_at<=now()
  OR EXISTS (SELECT 1 FROM atlas.person_auth_credentials
     WHERE auth_user_id=v_actor)
  OR EXISTS (SELECT 1 FROM reality.auth_person_bindings WHERE auth_user_id=v_actor)
  OR NOT atlas.existing_person_claim_actor_steward_v1(
      v_case.organization_id,v_case.person_entity_id,v_case.prepared_by_user_id)
  OR NOT atlas.existing_person_claim_actor_steward_v1(
      v_case.organization_id,v_case.person_entity_id,v_case.reviewed_by_user_id)
 THEN RAISE EXCEPTION 'Recipient, old account, and reviewer proof required'
   USING errcode='42501'; END IF;
 -- Never disable an old Auth credential based on a stale plan: confirm
 -- the claimant's CURRENT verified mailbox, exact old binding, Principal
 -- ownership, and lack of separately delegated authorization right now.
 IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id=v_actor
       AND lower(u.email)=v_case.proposed_email)
    OR NOT EXISTS (SELECT 1 FROM atlas.people p
       JOIN reality.entities e ON e.id=p.id
       WHERE p.id=v_case.person_entity_id AND p.status='active'
         AND e.entity_kind='person' AND e.identity_state='canonical')
    OR NOT EXISTS (SELECT 1 FROM atlas.person_auth_credentials c
       JOIN reality.auth_person_bindings b ON b.id=c.id
       WHERE c.id=v_case.replaces_credential_id
         AND c.person_id=v_case.person_entity_id
         AND c.auth_user_id=v_case.replaces_auth_user_id
         AND c.status='active' AND c.retired_at IS NULL
         AND b.binding_state='active' AND b.retired_at IS NULL
         AND b.person_entity_id=c.person_id AND b.auth_user_id=c.auth_user_id)
    OR EXISTS (SELECT 1 FROM atlas.principal_ledger_authorities a
       JOIN atlas.principals p ON p.id=a.principal_id
       WHERE p.person_id=v_case.person_entity_id AND a.status='active')
    OR EXISTS (SELECT 1 FROM atlas.organization_memberships m
       WHERE m.user_id=v_case.replaces_auth_user_id AND m.active)
    OR EXISTS (SELECT 1 FROM atlas.principals p
       WHERE p.person_id=v_case.person_entity_id AND p.status='active'
         AND p.user_id<>v_case.replaces_auth_user_id)
    OR EXISTS (SELECT 1 FROM atlas.principals p WHERE p.user_id=v_actor)
    OR EXISTS (SELECT 1 FROM atlas.organization_memberships m
       WHERE m.user_id=v_actor AND m.active)
 THEN RAISE EXCEPTION 'Replacement conditions changed; old Auth may not be disabled'
    USING errcode='42501'; END IF;
 -- Sensitive old Auth identifier is disclosed only to the signed,
 -- independently approved new recipient for one server-only action.
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,
   'oldAuthUserId',v_case.replaces_auth_user_id,
   'personId',v_case.person_entity_id,'providerBanRequired',true);
END
$fn$;

CREATE FUNCTION atlas.finish_existing_person_auth_replacement_self_v1(
 p_case_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_actor uuid;v_email text;v_case atlas.existing_person_auth_claim_cases%rowtype;
 v_old atlas.person_auth_credentials%rowtype;
 v_new_id uuid:=gen_random_uuid();v_principal uuid;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_actor FOR UPDATE;
 SELECT * INTO v_case FROM atlas.existing_person_auth_claim_cases
 WHERE id=p_case_id FOR UPDATE;
 IF v_case.id IS NULL OR v_case.claimant_auth_user_id<>v_actor
   OR v_case.proposed_email<>v_email OR v_case.replaces_auth_user_id IS NULL
 THEN RAISE EXCEPTION 'Exact verified recipient replacement required'
   USING errcode='42501'; END IF;
 IF v_case.case_state='completed' THEN
  RETURN jsonb_build_object('ok',true,'caseId',v_case.id,'state','completed',
    'idempotentReplay',true,'personId',v_case.person_entity_id);
 END IF;
 IF v_case.case_state<>'approved' OR v_case.reviewed_at IS NULL
  OR v_case.old_account_consented_at IS NULL OR v_case.expires_at<=now()
  OR v_case.reviewed_by_user_id IN (v_actor,v_case.replaces_auth_user_id)
  OR NOT atlas.existing_person_claim_actor_steward_v1(
    v_case.organization_id,v_case.person_entity_id,v_case.prepared_by_user_id)
  OR NOT atlas.existing_person_claim_actor_steward_v1(
    v_case.organization_id,v_case.person_entity_id,v_case.reviewed_by_user_id)
 THEN RAISE EXCEPTION 'Independent approved replacement receipts required'
   USING errcode='42501'; END IF;
 PERFORM 1 FROM atlas.people p WHERE p.id=v_case.person_entity_id
   AND p.status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Person is not active' USING errcode='42501'; END IF;
 PERFORM 1 FROM reality.entities e WHERE e.id=v_case.person_entity_id
   AND e.entity_kind='person' AND e.identity_state='canonical' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Person is not canonical' USING errcode='42501'; END IF;
 SELECT * INTO v_old FROM atlas.person_auth_credentials
 WHERE id=v_case.replaces_credential_id
   AND person_id=v_case.person_entity_id
   AND auth_user_id=v_case.replaces_auth_user_id
   AND status='active' AND retired_at IS NULL FOR UPDATE;
 IF v_old.id IS NULL
  OR NOT EXISTS(SELECT 1 FROM reality.auth_person_bindings b
     WHERE b.id=v_old.id AND b.person_entity_id=v_case.person_entity_id
       AND b.auth_user_id=v_old.auth_user_id AND b.binding_state='active'
       AND b.retired_at IS NULL)
  OR (SELECT count(*) FROM reality.auth_person_bindings b
       WHERE b.person_entity_id=v_case.person_entity_id
         AND b.binding_state='active' AND b.retired_at IS NULL)<>1
  OR EXISTS(SELECT 1 FROM atlas.person_auth_credentials
       WHERE auth_user_id=v_actor)
  OR EXISTS(SELECT 1 FROM reality.auth_person_bindings
       WHERE auth_user_id=v_actor)
  OR EXISTS(SELECT 1 FROM atlas.principals WHERE user_id=v_actor)
  OR EXISTS(SELECT 1 FROM atlas.organization_memberships
       WHERE user_id=v_actor AND active)
  OR EXISTS(SELECT 1 FROM atlas.principal_ledger_authorities a
       JOIN atlas.principals p ON p.id=a.principal_id
       WHERE p.person_id=v_case.person_entity_id AND a.status='active')
  OR EXISTS(SELECT 1 FROM atlas.organization_memberships
       WHERE user_id=v_old.auth_user_id AND active)
  OR EXISTS(SELECT 1 FROM atlas.person_sign_in_emails
       WHERE normalized_email=v_email AND auth_user_id<>v_actor)
 THEN RAISE EXCEPTION 'Existing conflicting identity or delegated authority'
   USING errcode='42501'; END IF;
 -- The trusted Auth service must already have banned the old user; never
 -- perform Auth account bans from a caller-supplied UUID through Data API.
 IF NOT EXISTS(SELECT 1 FROM auth.users u
   WHERE u.id=v_old.auth_user_id AND u.deleted_at IS NULL
    AND u.banned_until>now()+interval '365 days')
 THEN RAISE EXCEPTION 'Provider disabled-account receipt not established'
   USING errcode='42501'; END IF;
 SELECT p.id INTO v_principal FROM atlas.principals p
 WHERE p.person_id=v_case.person_entity_id AND p.status='active' FOR UPDATE;
 IF (SELECT count(*) FROM atlas.principals p
       WHERE p.person_id=v_case.person_entity_id AND p.status='active')>1
  OR (v_principal IS NOT NULL AND NOT EXISTS(SELECT 1 FROM atlas.principals p
       WHERE p.id=v_principal AND p.user_id=v_old.auth_user_id))
 THEN RAISE EXCEPTION 'Principal custody conflict' USING errcode='42501'; END IF;

 -- Auth session/refresh-token revocation, old credential retirement, and
 -- new canonical binding must succeed in one database transaction.
 DELETE FROM auth.sessions WHERE user_id=v_old.auth_user_id;
 UPDATE atlas.person_auth_credentials
 SET status='retired',retired_at=now(),updated_at=now(),
     provenance=provenance || jsonb_build_object(
      'retiredForCase',v_case.id,'replacedByAuthUserId',v_actor)
 WHERE id=v_old.id;
 UPDATE reality.auth_person_bindings
 SET binding_state='retired',retired_at=now(),updated_at=now()
 WHERE id=v_old.id;
 UPDATE atlas.person_sign_in_emails
 SET preferred=false,verification_state='retired',
     sign_in_transport='none',updated_at=now()
 WHERE person_id=v_case.person_entity_id AND auth_user_id=v_old.auth_user_id;
 INSERT INTO atlas.person_auth_credentials
 (id,person_id,credential_kind,auth_user_id,status,bound_at,provenance)
 VALUES(v_new_id,v_case.person_entity_id,'supabase_auth_user',
   v_actor,'active',now(),
   jsonb_build_object('source','existing_person_auth_replacement_v1',
    'caseId',v_case.id,'priorCredentialId',v_old.id,
    'oldAccountConsentAt',v_case.old_account_consented_at,
    'reviewer',v_case.reviewed_by_user_id));
 INSERT INTO reality.auth_person_bindings
 (id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at)
 VALUES(v_new_id,v_actor,v_case.person_entity_id,'active',
   jsonb_build_object('source','existing_person_auth_replacement_v1',
     'caseId',v_case.id,'oldCredentialRetired',true),now());
 -- Retain the Principal id and original historical references. Re-associate
 -- an original PERSONAL Principal only when no delegated rights exist.
 IF v_principal IS NOT NULL THEN
   UPDATE atlas.principals
   SET user_id=v_actor,updated_at=now(),
     metadata=metadata || jsonb_build_object(
       'identityAuthReboundFrom',v_old.auth_user_id,
       'identityAuthReboundCase',v_case.id)
   WHERE id=v_principal;
 END IF;
 INSERT INTO atlas.person_sign_in_emails(
  person_id,auth_user_id,normalized_email,verification_state,
  sign_in_transport,preferred,verified_at,verified_proof_receipt)
 VALUES(v_case.person_entity_id,v_actor,v_email,'verified',
  'primary_auth',true,now(),'verified-auth-session:replacement:'||v_case.id::text);
 UPDATE atlas.existing_person_auth_claim_cases
 SET case_state='completed',completed_binding_id=v_new_id,completed_at=now(),
   replacement_principal_id=v_principal,updated_at=now() WHERE id=v_case.id;
 RETURN jsonb_build_object('ok',true,'caseId',v_case.id,'state','completed',
   'idempotentReplay',false,'personId',v_case.person_entity_id);
END
$fn$;

CREATE FUNCTION public.inspect_existing_person_auth_replacement_old_self_api_v1(
 p_case_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.inspect_existing_person_auth_replacement_old_self_v1(p_case_id) $fn$;
CREATE FUNCTION public.prepare_existing_person_auth_replacement_self_api_v1(
 p_organization_id uuid,p_person_id uuid,p_new_email text,p_basis text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.prepare_existing_person_auth_replacement_self_v1(
 p_organization_id,p_person_id,p_new_email,p_basis) $fn$;
CREATE FUNCTION public.consent_existing_person_auth_replacement_old_self_api_v1(
 p_case_id uuid,p_explicit_retirement_consent boolean)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.consent_existing_person_auth_replacement_old_self_v1(
 p_case_id,p_explicit_retirement_consent) $fn$;
CREATE FUNCTION public.plan_existing_person_auth_replacement_self_api_v1(
 p_case_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.plan_existing_person_auth_replacement_self_v1(
 p_case_id) $fn$;
CREATE FUNCTION public.finish_existing_person_auth_replacement_self_api_v1(
 p_case_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $fn$ SELECT atlas.finish_existing_person_auth_replacement_self_v1(
 p_case_id) $fn$;

REVOKE ALL ON FUNCTION
 atlas.inspect_existing_person_auth_replacement_old_self_v1(uuid),
 atlas.prepare_existing_person_auth_replacement_self_v1(uuid,uuid,text,text),
 atlas.consent_existing_person_auth_replacement_old_self_v1(uuid,boolean),
 atlas.plan_existing_person_auth_replacement_self_v1(uuid),
 atlas.finish_existing_person_auth_replacement_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 atlas.inspect_existing_person_auth_replacement_old_self_v1(uuid),
 atlas.prepare_existing_person_auth_replacement_self_v1(uuid,uuid,text,text),
 atlas.consent_existing_person_auth_replacement_old_self_v1(uuid,boolean),
 atlas.plan_existing_person_auth_replacement_self_v1(uuid),
 atlas.finish_existing_person_auth_replacement_self_v1(uuid)
 TO authenticated;
REVOKE ALL ON FUNCTION
 public.inspect_existing_person_auth_replacement_old_self_api_v1(uuid),
 public.prepare_existing_person_auth_replacement_self_api_v1(uuid,uuid,text,text),
 public.consent_existing_person_auth_replacement_old_self_api_v1(uuid,boolean),
 public.plan_existing_person_auth_replacement_self_api_v1(uuid),
 public.finish_existing_person_auth_replacement_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.inspect_existing_person_auth_replacement_old_self_api_v1(uuid),
 public.prepare_existing_person_auth_replacement_self_api_v1(uuid,uuid,text,text),
 public.consent_existing_person_auth_replacement_old_self_api_v1(uuid,boolean),
 public.plan_existing_person_auth_replacement_self_api_v1(uuid),
 public.finish_existing_person_auth_replacement_self_api_v1(uuid)
 TO authenticated;


-- A decommissioned historic Auth user is never a fresh user. The legacy
-- compatibility constructor may run from a Principal trigger and must not
-- create a second Reality/Atlas Person for an accidentally re-enabled login.
CREATE OR REPLACE FUNCTION atlas.ensure_person_for_auth_user_v1(
 p_user_id uuid,p_display_name text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $fn$
DECLARE v_person_id uuid; v_display_name text:=nullif(btrim(coalesce(p_display_name,'')),'');
BEGIN
 IF p_user_id IS NULL THEN
  RAISE EXCEPTION 'Authentication credential id required' USING errcode='22023'; END IF;
 PERFORM 1 FROM auth.users u WHERE u.id=p_user_id FOR UPDATE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Authentication credential does not exist' USING errcode='23503'; END IF;
 SELECT c.person_id INTO v_person_id
 FROM atlas.person_auth_credentials c
 WHERE c.auth_user_id=p_user_id AND c.status='active' LIMIT 1;
 IF v_person_id IS NOT NULL THEN
  IF v_display_name IS NOT NULL THEN
   UPDATE atlas.people p
    SET display_name=coalesce(p.display_name,v_display_name),
        updated_at=CASE WHEN p.display_name IS NULL THEN now()
                        ELSE p.updated_at END
    WHERE p.id=v_person_id;
  END IF;
  RETURN v_person_id;
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.person_auth_credentials c
   WHERE c.auth_user_id=p_user_id AND c.status='retired')
 THEN
  RAISE EXCEPTION 'Retired Auth credential cannot establish a new Person'
    USING errcode='42501';
 END IF;
 INSERT INTO atlas.people(display_name,status,metadata)
 VALUES(v_display_name,'active',
   jsonb_build_object('establishmentBasis','existing_auth_credential_compatibility'))
 RETURNING id INTO v_person_id;
 INSERT INTO atlas.person_auth_credentials(
  person_id,credential_kind,auth_user_id,status,provenance)
 VALUES(v_person_id,'supabase_auth_user',p_user_id,'active',
   jsonb_build_object('basis','compatibility_binding'));
 RETURN v_person_id;
END
$fn$;

COMMIT;

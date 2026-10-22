-- SOURCE CANDIDATE ONLY. A protected release must validate this on a schema clone.
-- Service-only identity ceremony; clients NEVER call these functions directly.
BEGIN;
CREATE TABLE atlas.person_email_recovery_cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 person_id uuid NOT NULL REFERENCES atlas.people(id),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 destination_email text NOT NULL CHECK (length(destination_email) BETWEEN 5 AND 320),
 prior_auth_email text NOT NULL,
 challenge_sha256 text NOT NULL CHECK(challenge_sha256 ~ '^[0-9a-f]{64}$'),
 challenge_expires_at timestamptz NOT NULL,
 case_expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 mailbox_verified_at timestamptz,
 initiated_by_user_id uuid NOT NULL REFERENCES auth.users(id),
 claim_basis text NOT NULL CHECK(length(btrim(claim_basis)) BETWEEN 30 AND 1800),
 reviewed_by_user_id uuid REFERENCES auth.users(id),
 reviewer_basis text,
 reviewer_method text,
 reviewed_at timestamptz,
 case_state text NOT NULL DEFAULT 'pending_mailbox' CHECK(case_state IN
  ('pending_mailbox','mailbox_verified','approved','promoting','completed','conflicted','expired','rejected')),
 completed_at timestamptz,
 failure_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (reviewed_at IS NULL OR (mailbox_verified_at IS NOT NULL AND
        reviewer_basis IS NOT NULL AND reviewer_method IS NOT NULL))
);
CREATE UNIQUE INDEX person_email_recovery_one_live_case_v1
 ON atlas.person_email_recovery_cases(person_id)
 WHERE case_state IN ('pending_mailbox','mailbox_verified','approved','promoting');
CREATE INDEX person_email_recovery_destination_v1
 ON atlas.person_email_recovery_cases(destination_email,created_at DESC);
ALTER TABLE atlas.person_email_recovery_cases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.person_email_recovery_cases FROM PUBLIC,anon,authenticated;

CREATE TABLE atlas.person_email_recovery_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 case_id uuid NOT NULL REFERENCES atlas.person_email_recovery_cases(id),
 event_kind text NOT NULL,
 actor_user_id uuid,
 details jsonb NOT NULL DEFAULT '{}'::jsonb,
 recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE atlas.person_email_recovery_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.person_email_recovery_events FROM PUBLIC,anon,authenticated;

-- All service entry points require the protected Edge worker service credential.
-- The Edge worker MUST first authenticate a real user JWT before passing actor id.
CREATE OR REPLACE FUNCTION atlas.service_person_email_recovery_reviewer_v1(
 p_actor uuid,p_person uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog' AS $fn$
 SELECT p_actor IS NOT NULL AND p_person IS NOT NULL AND
  EXISTS (SELECT 1 FROM atlas.principals pr
          WHERE pr.user_id=p_actor AND pr.status='active') AND
  EXISTS (
    SELECT 1 FROM atlas.organization_memberships owner
    JOIN atlas.organization_memberships subject
      ON subject.organization_id=owner.organization_id
    WHERE owner.user_id=p_actor AND owner.active AND owner.role='owner'
      AND subject.person_id=p_person AND subject.active
      AND owner.person_id IS DISTINCT FROM p_person
  );
$fn$;

CREATE OR REPLACE FUNCTION atlas.service_person_email_recovery_candidates_v1(
 p_actor uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog' AS $fn$
 SELECT jsonb_build_object('ok',true,'contractVersion','person_email_recovery_candidates_v1',
  'people',coalesce(jsonb_agg(jsonb_build_object(
   'personId',p.id,'displayName',p.display_name,'organizationName',p.organization_name,
   'hasLegacyCredential',true) ORDER BY p.display_name,p.organization_name),'[]'::jsonb))
 FROM (
   SELECT DISTINCT ON (p.id,o.id) p.id,p.display_name,o.name as organization_name
   FROM atlas.people p
   JOIN atlas.organization_memberships subj ON subj.person_id=p.id AND subj.active
   JOIN atlas.organizations o ON o.id=subj.organization_id AND o.status='active'
   JOIN atlas.organization_memberships owner ON owner.organization_id=o.id
     AND owner.user_id=p_actor AND owner.active AND owner.role='owner'
   JOIN atlas.person_auth_credentials c ON c.person_id=p.id
     AND c.status='active' AND c.retired_at IS NULL
     AND c.credential_kind='supabase_auth_user'
   WHERE p.status='active' AND
    EXISTS (SELECT 1 FROM atlas.principals pr WHERE pr.user_id=p_actor AND pr.status='active')
     AND NOT EXISTS(SELECT 1 FROM atlas.principals old
       WHERE old.person_id=p.id AND old.status='active')
   ORDER BY p.id,o.id
   LIMIT 100
 ) p;
$fn$;

CREATE OR REPLACE FUNCTION atlas.service_begin_person_email_recovery_v1(
 p_actor uuid,p_person uuid,p_destination text,p_challenge_hash text,p_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
DECLARE v_user uuid;v_count int;v_case uuid;v_email text:=lower(btrim(p_destination));v_old text;
BEGIN
 IF NOT atlas.service_person_email_recovery_reviewer_v1(p_actor,p_person) THEN
  RAISE EXCEPTION 'Verified owner/reviewer relation required' USING errcode='42501';
 END IF;
 IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
 OR length(v_email)>320 OR p_challenge_hash !~ '^[0-9a-f]{64}$'
 OR length(btrim(coalesce(p_basis,''))) NOT BETWEEN 30 AND 1800 THEN
   RAISE EXCEPTION 'Recovery input invalid' USING errcode='22023';
 END IF;
 SELECT count(*) INTO v_count FROM atlas.person_auth_credentials c
 WHERE c.person_id=p_person AND c.credential_kind='supabase_auth_user'
 AND c.status='active' AND c.retired_at IS NULL;
 SELECT c.auth_user_id INTO v_user FROM atlas.person_auth_credentials c
 WHERE c.person_id=p_person AND c.credential_kind='supabase_auth_user'
 AND c.status='active' AND c.retired_at IS NULL LIMIT 1;
 SELECT lower(u.email) INTO v_old FROM auth.users u WHERE u.id=v_user
  AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL;
 IF v_old IS NULL OR v_old=v_email THEN
   RAISE EXCEPTION 'Previous verified Auth credential required' USING errcode='42501';
 END IF;
 IF v_count<>1 OR EXISTS(SELECT 1 FROM atlas.principals pr
   WHERE pr.person_id=p_person AND pr.status='active') THEN
   RAISE EXCEPTION 'Principal/credential continuity requires separate review' USING errcode='42501';
 END IF;
 IF EXISTS(SELECT 1 FROM auth.users u WHERE lower(u.email)=v_email
    OR lower(u.email_change)=v_email)
 OR EXISTS(SELECT 1 FROM atlas.person_sign_in_emails e
  WHERE e.normalized_email=v_email AND e.verification_state='verified'
   AND e.person_id<>p_person) THEN
   RAISE EXCEPTION 'Recovery address conflicts with another account' USING errcode='23505';
 END IF;
 IF (SELECT count(*) FROM atlas.person_email_recovery_cases r WHERE r.person_id=p_person
 AND r.created_at>now()-interval '1 day')>=3 THEN
    RAISE EXCEPTION 'Recovery frequency exceeded' USING errcode='22023';
 END IF;
 UPDATE atlas.person_email_recovery_cases SET case_state='expired',updated_at=now()
  WHERE person_id=p_person AND
   ((case_state='pending_mailbox' AND challenge_expires_at<=now()) OR
    (case_state IN ('mailbox_verified','approved') AND case_expires_at<=now()));
 INSERT INTO atlas.person_email_recovery_cases(
 person_id,auth_user_id,destination_email,prior_auth_email,challenge_sha256,
 challenge_expires_at,initiated_by_user_id,claim_basis)
 VALUES(p_person,v_user,v_email,v_old,p_challenge_hash,now()+interval '15 minutes',p_actor,btrim(p_basis))
 RETURNING id INTO v_case;
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind,actor_user_id)
 VALUES(v_case,'initiated',p_actor);
 RETURN jsonb_build_object('ok',true,'contractVersion','person_email_recovery_started_v1',
 'caseId',v_case,'expiresInSeconds',900);
END;$fn$;

CREATE OR REPLACE FUNCTION atlas.service_verify_person_email_recovery_v1(
 p_case uuid,p_code_hash text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
DECLARE r atlas.person_email_recovery_cases%rowtype;
BEGIN
 SELECT * INTO r FROM atlas.person_email_recovery_cases WHERE id=p_case FOR UPDATE;
 IF r.id IS NULL OR r.case_state NOT IN ('pending_mailbox','mailbox_verified')
   OR r.challenge_expires_at<=now() OR r.attempts>=5 THEN
  RETURN jsonb_build_object('ok',false,'reason','not_admissible');
 END IF;
 IF r.case_state='mailbox_verified' THEN
  RETURN jsonb_build_object('ok',false,'reason','already_consumed');
 END IF;
 IF p_code_hash IS DISTINCT FROM r.challenge_sha256 THEN
  UPDATE atlas.person_email_recovery_cases SET attempts=attempts+1,
  case_state=CASE WHEN attempts>=4 THEN 'rejected' ELSE case_state END,
  updated_at=now() WHERE id=p_case;
  RETURN jsonb_build_object('ok',false,'reason','incorrect_or_expired');
 END IF;
 UPDATE atlas.person_email_recovery_cases SET mailbox_verified_at=now(),
   case_state='mailbox_verified',updated_at=now() WHERE id=p_case;
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind)
 VALUES(p_case,'mailbox_verified');
 RETURN jsonb_build_object('ok',true,'mailboxVerified',true);
END;$fn$;

CREATE OR REPLACE FUNCTION atlas.service_approve_person_email_recovery_v1(
 p_case uuid,p_reviewer uuid,p_method text,p_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
DECLARE r atlas.person_email_recovery_cases%rowtype;
BEGIN
 SELECT * INTO r FROM atlas.person_email_recovery_cases WHERE id=p_case FOR UPDATE;
 IF r.id IS NULL OR r.case_state<>'mailbox_verified'
  OR r.case_expires_at<=now()
  OR NOT atlas.service_person_email_recovery_reviewer_v1(p_reviewer,r.person_id)
  OR p_method NOT IN ('verified_in_person','verified_video_call')
  OR length(btrim(coalesce(p_basis,''))) NOT BETWEEN 40 AND 1800 THEN
  RAISE EXCEPTION 'Independent identity review not established' USING errcode='42501';
 END IF;
 UPDATE atlas.person_email_recovery_cases SET reviewed_by_user_id=p_reviewer,
 reviewed_at=now(),reviewer_method=p_method,reviewer_basis=btrim(p_basis),
 case_state='approved',updated_at=now() WHERE id=p_case;
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind,actor_user_id,
 details) VALUES(p_case,'identity_reviewed',p_reviewer,
 jsonb_build_object('method',p_method));
 RETURN jsonb_build_object('ok',true,'approved',true);
END;$fn$;

CREATE OR REPLACE FUNCTION atlas.service_prepare_person_email_recovery_v1(
 p_case uuid,p_reviewer uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
DECLARE r atlas.person_email_recovery_cases%rowtype;
BEGIN
 SELECT * INTO r FROM atlas.person_email_recovery_cases WHERE id=p_case FOR UPDATE;
 IF r.id IS NOT NULL AND r.case_state='promoting'
   AND r.case_expires_at>now()
   AND atlas.service_person_email_recovery_reviewer_v1(p_reviewer,r.person_id)
   AND r.mailbox_verified_at IS NOT NULL AND r.reviewed_at IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'authUserId',r.auth_user_id,
     'personId',r.person_id,'newEmail',r.destination_email,'caseId',r.id,
     'reconcileExistingAttempt',true);
 END IF;
 IF r.id IS NULL OR r.case_state<>'approved' OR r.case_expires_at<=now()
  OR r.mailbox_verified_at IS NULL OR r.reviewed_at IS NULL
  OR NOT atlas.service_person_email_recovery_reviewer_v1(p_reviewer,r.person_id)
  OR EXISTS(SELECT 1 FROM auth.users u WHERE lower(u.email)=r.destination_email
      OR lower(u.email_change)=r.destination_email)
  OR NOT EXISTS(SELECT 1 FROM atlas.person_auth_credentials c
    WHERE c.person_id=r.person_id AND c.auth_user_id=r.auth_user_id
      AND c.status='active' AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'Protected recovery promotion not admissible' USING errcode='42501';
 END IF;
 UPDATE atlas.person_email_recovery_cases SET case_state='promoting',
 updated_at=now() WHERE id=p_case;
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind,actor_user_id)
 VALUES(p_case,'promotion_prepared',p_reviewer);
 -- SERVICE ONLY: never return the Auth identity to an untrusted browser.
 RETURN jsonb_build_object('ok',true,'authUserId',r.auth_user_id,
 'personId',r.person_id,'newEmail',r.destination_email,'caseId',r.id);
END;$fn$;

CREATE OR REPLACE FUNCTION atlas.service_finish_person_email_recovery_v1(p_case uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
DECLARE r atlas.person_email_recovery_cases%rowtype;v_ok boolean;
BEGIN
 SELECT * INTO r FROM atlas.person_email_recovery_cases WHERE id=p_case FOR UPDATE;
 IF r.case_state='completed' THEN
  RETURN jsonb_build_object('ok',true,'idempotentReplay',true);
 END IF;
 SELECT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=r.auth_user_id
 AND lower(u.email)=r.destination_email AND u.email_confirmed_at IS NOT NULL)
 INTO v_ok;
 IF r.id IS NULL OR r.case_state<>'promoting' OR NOT v_ok
   OR NOT EXISTS (SELECT 1 FROM atlas.person_auth_credentials c
     WHERE c.person_id=r.person_id AND c.auth_user_id=r.auth_user_id
       AND c.credential_kind='supabase_auth_user' AND c.status='active'
       AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'Auth Admin recovery result not verified' USING errcode='42501';
 END IF;
 INSERT INTO atlas.person_sign_in_emails(
   person_id,auth_user_id,normalized_email,verification_state,
   sign_in_transport,preferred,verified_proof_receipt)
 VALUES (r.person_id,r.auth_user_id,r.prior_auth_email,'retired','none',false,
   'recovery-history:'||r.id::text)
 ON CONFLICT(person_id,normalized_email) DO UPDATE SET
  verification_state='retired',sign_in_transport='none',
  preferred=false,updated_at=now();
 UPDATE atlas.person_email_recovery_cases SET case_state='completed',
 completed_at=now(),updated_at=now() WHERE id=p_case;
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind)
 VALUES(p_case,'auth_primary_recovered');
 RETURN jsonb_build_object('ok',true,'contractVersion','person_email_recovery_completed_v1',
 'caseId',p_case,'personId',r.person_id,'authUserId',r.auth_user_id,
 'verifiedEmail',r.destination_email);
END;$fn$;

CREATE OR REPLACE FUNCTION atlas.service_reject_person_email_recovery_v1(
 p_case uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $fn$
BEGIN
 IF p_reason NOT IN ('delivery_failed','auth_admin_failed','identity_conflict') THEN
   RAISE EXCEPTION 'Unsupported recovery failure' USING errcode='22023';
 END IF;
 UPDATE atlas.person_email_recovery_cases SET case_state='conflicted',
 failure_code=p_reason,updated_at=now() WHERE id=p_case
 AND case_state IN ('pending_mailbox','approved','promoting');
 INSERT INTO atlas.person_email_recovery_events(case_id,event_kind,details)
 VALUES(p_case,'recovery_interrupted',jsonb_build_object('reason',p_reason));
 RETURN jsonb_build_object('ok',true);
END;$fn$;

-- Private schema, service_role only. None can be called by browsers.
REVOKE ALL ON FUNCTION atlas.service_person_email_recovery_reviewer_v1(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_person_email_recovery_candidates_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_begin_person_email_recovery_v1(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_verify_person_email_recovery_v1(uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_approve_person_email_recovery_v1(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_prepare_person_email_recovery_v1(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_finish_person_email_recovery_v1(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.service_reject_person_email_recovery_v1(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.service_person_email_recovery_reviewer_v1(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_person_email_recovery_candidates_v1(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_begin_person_email_recovery_v1(uuid,uuid,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_verify_person_email_recovery_v1(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_approve_person_email_recovery_v1(uuid,uuid,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_prepare_person_email_recovery_v1(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_finish_person_email_recovery_v1(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION atlas.service_reject_person_email_recovery_v1(uuid,text) TO service_role;
COMMIT;

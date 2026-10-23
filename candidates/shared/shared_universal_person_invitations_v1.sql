BEGIN;
-- Atlas Build 2: invitation is only an offer and an auditable delivery object.
-- It must never fabricate an employment seat, membership, Person or payment.

CREATE TABLE atlas.universal_person_invitations (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references atlas.organizations(id),
 existing_person_id uuid references reality.entities(id),
 identity_claim_case_id uuid references atlas.existing_person_auth_claim_cases(id),
 intended_name text not null check(length(btrim(intended_name)) between 2 and 160),
 recipient_email text not null check (
  recipient_email=lower(btrim(recipient_email))
  and recipient_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  and length(recipient_email)<=320),
 offered_access text not null check(offered_access='complimentary_testing'),
 state text not null default 'prepared'
  check(state in ('prepared','issued','claimed','declined','not_me','revoked')),
 delivery_state text not null default 'not_sent'
  check(delivery_state in ('not_sent','manual_send_asserted','provider_confirmed')),
 token_digest text check(token_digest ~ '^[a-f0-9]{64}$'),
 complimentary_invitation_id uuid references atlas.personal_atlas_complimentary_test_invitations(id),
 expires_at timestamptz,
 issued_at timestamptz,
 claimed_by_user_id uuid references auth.users(id),
 claimed_at timestamptz,
 prepared_by_user_id uuid not null references auth.users(id),
 changed_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb,
 check((state='claimed')=(claimed_at is not null)),
 check(claimed_at is null or claimed_by_user_id is not null),
 check(state<>'issued' or (token_digest is not null and expires_at is not null))
);
CREATE UNIQUE INDEX universal_person_invitation_one_open_v1
 ON atlas.universal_person_invitations(organization_id,recipient_email)
 WHERE state in ('prepared','issued');
CREATE UNIQUE INDEX universal_person_invitation_token_unique_v1
 ON atlas.universal_person_invitations(token_digest) WHERE token_digest IS NOT NULL;
ALTER TABLE atlas.universal_person_invitations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.universal_person_invitations FROM PUBLIC,anon,authenticated;

CREATE TABLE atlas.universal_person_invitation_events(
 id uuid primary key default gen_random_uuid(),
 invitation_id uuid not null references atlas.universal_person_invitations(id),
 action text not null,
 actor_user_id uuid references auth.users(id),
 evidence jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default now()
);
CREATE INDEX universal_person_invitation_event_history_v1
 ON atlas.universal_person_invitation_events(invitation_id,occurred_at,id);
ALTER TABLE atlas.universal_person_invitation_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.universal_person_invitation_events FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.universal_person_inviter_self_v1(p_org uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $f$
 SELECT EXISTS(SELECT 1 FROM atlas.organizations o
   JOIN atlas.organization_memberships m ON m.organization_id=o.id
   WHERE o.id=p_org AND o.status='active' AND m.user_id=auth.uid()
     AND m.active AND m.role='owner')
 OR EXISTS (
   SELECT 1 FROM atlas.organizations o
   JOIN atlas.ledger_organization_participations lp
     ON lp.organization_id=o.id AND lp.status='active' AND lp.ended_at IS NULL
     AND lp.participation_kind IN ('governing','operating')
   JOIN atlas.principal_ledger_authorities a
     ON a.ledger_id=lp.ledger_id AND a.status='active'
       AND a.authority_kind='root_governing'
   JOIN atlas.principals p ON p.id=a.principal_id
   JOIN reality.auth_person_bindings b
     ON b.auth_user_id=p.user_id AND b.person_entity_id=p.person_id
      AND b.binding_state='active' AND b.retired_at IS NULL
   WHERE o.id=p_org AND o.status='active' AND p.user_id=auth.uid()
     AND p.status='active'
 )
$f$;

CREATE FUNCTION atlas.universal_person_invitation_steward_self_v1(
 p_org uuid,p_person uuid
) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
BEGIN
 PERFORM atlas.existing_person_claim_signed_actor_v1();
 IF NOT atlas.universal_person_inviter_self_v1(p_org)
  OR (p_person IS NOT NULL AND
   NOT atlas.existing_person_claim_actor_steward_v1(p_org,p_person,auth.uid()))
 THEN RAISE EXCEPTION 'Exact inviting authority required' USING errcode='42501';
 END IF;
END $f$;

CREATE FUNCTION atlas.prepare_universal_person_invitation_self_v1(
 p_organization_id uuid,p_name text,p_email text,p_existing_person_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_name text:=btrim(coalesce(p_name,''));
 v_email text:=lower(btrim(coalesce(p_email,'')));
 v_case uuid;v_existing atlas.universal_person_invitations%rowtype;
 v_old_user uuid;v_old_count int;v_id uuid;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 PERFORM atlas.universal_person_invitation_steward_self_v1(
   p_organization_id,p_existing_person_id);
 IF length(v_name) NOT BETWEEN 2 AND 160
  OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  OR length(v_email)>320 THEN
  RAISE EXCEPTION 'Valid name and recipient email required' USING errcode='22023';
 END IF;
 -- A new-Person candidate must never be made merely because the caller
 -- omitted the UUID for someone whose verified sign-in is already attached
 -- to a canonical Person. An email match is a STOP for review, never proof
 -- that this proposed name is the same human.
 -- Prior Atlas mailbox evidence is an ambiguity signal, NOT identity
 -- authority. A new-Person candidate stops; an operator must select/review
 -- the Person explicitly rather than silently creating a duplicate.
 IF p_existing_person_id IS NULL AND EXISTS (
   SELECT 1 FROM atlas.person_sign_in_emails m
   JOIN reality.entities e ON e.id=m.person_id
    AND e.entity_kind='person' AND e.identity_state='canonical'
   WHERE m.normalized_email=v_email
 ) THEN RAISE EXCEPTION
   'Email already appears on a known canonical Person; identity review required'
   USING errcode='23514'; END IF;
 IF p_existing_person_id IS NULL AND EXISTS(
    SELECT 1 FROM auth.users u
    JOIN reality.auth_person_bindings b
      ON b.auth_user_id=u.id AND b.binding_state='active'
       AND b.retired_at IS NULL
    JOIN reality.entities e ON e.id=b.person_entity_id
      AND e.entity_kind='person' AND e.identity_state='canonical'
    WHERE lower(u.email)=v_email AND u.email_confirmed_at IS NOT NULL
 ) THEN RAISE EXCEPTION
   'Verified login already has a canonical Person; select an authorized Person or request identity review'
   USING errcode='23514'; END IF;
 IF p_existing_person_id IS NOT NULL THEN
  PERFORM 1 FROM reality.entities e
   JOIN atlas.people p ON p.id=e.id AND p.status='active'
   WHERE e.id=p_existing_person_id AND e.entity_kind='person'
      AND e.identity_state='canonical' FOR UPDATE OF e;
  IF NOT FOUND THEN RAISE EXCEPTION 'Existing canonical Person required'
     USING errcode='23514'; END IF;
  SELECT count(*),min(b.auth_user_id) INTO v_old_count,v_old_user
   FROM reality.auth_person_bindings b
   WHERE b.person_entity_id=p_existing_person_id
    AND b.binding_state='active' AND b.retired_at IS NULL;
  IF v_old_count>1 THEN RAISE EXCEPTION 'Competing Person bindings' USING errcode='23514'; END IF;
  IF v_old_count=1 AND NOT EXISTS(
   SELECT 1 FROM auth.users u WHERE u.id=v_old_user
    AND u.email_confirmed_at IS NOT NULL AND lower(u.email)=v_email
  ) THEN RAISE EXCEPTION 'Active Person login requires Build 1 replacement, not invitation'
   USING errcode='42501'; END IF;
 END IF;
 SELECT * INTO v_existing FROM atlas.universal_person_invitations
 WHERE organization_id=p_organization_id AND recipient_email=v_email
   AND state IN ('prepared','issued') FOR UPDATE;
 IF v_existing.id IS NOT NULL THEN
  IF v_existing.existing_person_id IS DISTINCT FROM p_existing_person_id
    OR v_existing.intended_name<>v_name THEN
    RAISE EXCEPTION 'Another pending invitation requires review' USING errcode='23505';
  END IF;
  RETURN jsonb_build_object('ok',true,'invitationId',v_existing.id,
    'state',v_existing.state,'idempotentReplay',true);
 END IF;
 IF p_existing_person_id IS NOT NULL AND v_old_count=0 THEN
  SELECT (atlas.prepare_existing_person_auth_claim_self_v1(
    p_organization_id,p_existing_person_id,v_email,
    'Universal invitation preparation by a verified steward for one exact canonical Person; requires explicit recipient consent.')->>'caseId')::uuid
    INTO v_case;
 END IF;
 INSERT INTO atlas.universal_person_invitations(
   organization_id,existing_person_id,identity_claim_case_id,
   intended_name,recipient_email,offered_access,prepared_by_user_id
 ) VALUES(p_organization_id,p_existing_person_id,v_case,
   v_name,v_email,'complimentary_testing',v_actor) RETURNING id INTO v_id;
 INSERT INTO atlas.universal_person_invitation_events(invitation_id,action,actor_user_id)
 VALUES(v_id,'prepared',v_actor);
 RETURN jsonb_build_object('ok',true,'invitationId',v_id,
  'state','prepared','idempotentReplay',false);
END $f$;

-- Link code is issued ONCE into the response; only SHA-256 is stored.
-- Reissuing revokes the previous unused code and rotates its digest.
CREATE FUNCTION atlas.issue_universal_person_invitation_self_v1(p_invitation_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_i atlas.universal_person_invitations%rowtype;
 v_code text;v_digest text;v_free uuid;v_exp timestamptz:=now()+interval '7 days';
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_i FROM atlas.universal_person_invitations
  WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL THEN RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 PERFORM atlas.universal_person_invitation_steward_self_v1(
  v_i.organization_id,v_i.existing_person_id);
 IF v_i.state NOT IN ('prepared','issued') THEN
  RAISE EXCEPTION 'Cannot issue a finalized invitation' USING errcode='42501'; END IF;
 IF v_i.complimentary_invitation_id IS NOT NULL THEN
  UPDATE atlas.personal_atlas_complimentary_test_invitations
   SET state='revoked'
  WHERE id=v_i.complimentary_invitation_id
   AND claimed_by_user_id IS NULL AND state='issued';
  IF NOT FOUND THEN RAISE EXCEPTION 'Existing entitlement already used; cannot reissue'
    USING errcode='42501'; END IF;
 END IF;
 v_code:=encode(extensions.gen_random_bytes(32),'hex');
 v_digest:=encode(extensions.digest(v_code,'sha256'),'hex');
 INSERT INTO atlas.personal_atlas_complimentary_test_invitations(
   email,code_digest,state,expires_at
 ) VALUES(v_i.recipient_email,v_digest,'issued',v_exp)
 RETURNING id INTO v_free;
 UPDATE atlas.universal_person_invitations SET state='issued',
  token_digest=v_digest,complimentary_invitation_id=v_free,
  expires_at=v_exp,issued_at=now(),delivery_state='not_sent',changed_at=now()
 WHERE id=v_i.id;
 INSERT INTO atlas.universal_person_invitation_events(invitation_id,action,actor_user_id,
  evidence) VALUES(v_i.id,'link_issued',v_actor,jsonb_build_object(
    'expiresAt',v_exp,'deliveryConfirmed',false));
 RETURN jsonb_build_object('ok',true,'invitationId',v_i.id,
  'status','issued','expiresAt',v_exp,'linkCode',v_code,
  'deliveryState','not_sent','createsStripeObligation',false);
END $f$;

CREATE FUNCTION atlas.inspect_universal_person_invitation_self_v1(
 p_invitation_id uuid,p_code text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_i atlas.universal_person_invitations%rowtype;
 v_email text;v_current uuid;v_identity text;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT lower(u.email) INTO v_email FROM auth.users u WHERE u.id=v_actor;
 SELECT * INTO v_i FROM atlas.universal_person_invitations WHERE id=p_invitation_id;
 IF v_i.id IS NULL OR v_email<>v_i.recipient_email
  OR v_i.token_digest IS NULL
  OR length(coalesce(p_code,'')) NOT BETWEEN 20 AND 128
  OR v_i.token_digest<>encode(extensions.digest(p_code,'sha256'),'hex')
 THEN RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 v_current:=atlas.current_person_id_v1();
 v_identity:=CASE
  WHEN v_i.existing_person_id IS NULL AND
      (v_current IS NOT NULL OR EXISTS (
        SELECT 1 FROM atlas.person_sign_in_emails m
        JOIN reality.entities e ON e.id=m.person_id
        WHERE m.normalized_email=v_email AND e.entity_kind='person'
          AND e.identity_state='canonical'))
    THEN 'identity_review_required'
  WHEN v_i.existing_person_id IS NULL THEN 'new_person_candidate'
  WHEN v_current=v_i.existing_person_id THEN 'already_canonical'
  WHEN v_current IS NOT NULL THEN 'identity_conflict'
  WHEN v_i.identity_claim_case_id IS NOT NULL THEN 'identity_claim_required'
  ELSE 'identity_review_required' END;
 RETURN jsonb_build_object('ok',true,'invitationId',v_i.id,
 'name',v_i.intended_name,'status',CASE WHEN v_i.state='issued'
   AND v_i.expires_at<=now() THEN 'expired' ELSE v_i.state END,
 'identityState',v_identity,'identityClaimCaseId',v_i.identity_claim_case_id,
 'offeredAccess',v_i.offered_access,'expiresAt',v_i.expires_at,
 'deliveryState',v_i.delivery_state,'createsBilling',false);
END $f$;

CREATE FUNCTION atlas.claim_universal_person_invitation_self_v1(
 p_invitation_id uuid,p_code text,p_accept boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_email text;v_i atlas.universal_person_invitations%rowtype;
 v_current uuid;v_redeem jsonb;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_actor;
 IF p_accept IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Explicit recipient acceptance required' USING errcode='42501'; END IF;
 SELECT * INTO v_i FROM atlas.universal_person_invitations
 WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL OR v_i.recipient_email<>v_email
  OR v_i.token_digest IS NULL
  OR length(coalesce(p_code,'')) NOT BETWEEN 20 AND 128
  OR v_i.token_digest<>encode(extensions.digest(p_code,'sha256'),'hex')
 THEN RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 IF v_i.state='claimed' AND v_i.claimed_by_user_id=v_actor THEN
  RETURN jsonb_build_object('ok',true,'state','claimed','idempotentReplay',true);
 END IF;
 IF v_i.state<>'issued' OR v_i.expires_at<=now() THEN
  RAISE EXCEPTION 'Invitation expired or revoked' USING errcode='42501'; END IF;
 v_current:=atlas.current_person_id_v1();
 IF v_i.existing_person_id IS NULL AND (
    v_current IS NOT NULL OR EXISTS (
      SELECT 1 FROM atlas.person_sign_in_emails m
      JOIN reality.entities e ON e.id=m.person_id
      WHERE m.normalized_email=v_email AND e.entity_kind='person'
        AND e.identity_state='canonical')
   ) THEN
   RETURN jsonb_build_object('ok',false,'state','identity_review_required');
 END IF;
 IF v_i.existing_person_id IS NOT NULL AND
  v_current IS DISTINCT FROM v_i.existing_person_id THEN
  RETURN jsonb_build_object('ok',false,'state','identity_claim_required',
    'identityClaimCaseId',v_i.identity_claim_case_id);
 END IF;
 -- Only the existing complimentary entitlement writer can establish
 -- new access. If this verified account already owns a genuine active access
 -- basis (paid or previously granted), accept WITHOUT creating a duplicate
 -- grant; retire this unused code so it cannot be separately redeemed.
 IF coalesce((atlas.personal_atlas_access_status_self_api_v1()->>'eligible')::boolean,false)
 THEN
  UPDATE atlas.personal_atlas_complimentary_test_invitations
    SET state='revoked'
  WHERE id=v_i.complimentary_invitation_id AND claimed_by_user_id IS NULL;
 ELSE
  v_redeem:=public.redeem_personal_atlas_complimentary_test_self_api_v1(p_code);
  IF v_redeem->>'ok' IS DISTINCT FROM 'true'
    OR v_redeem->>'accessKind'<>'complimentary_testing' THEN
   RAISE EXCEPTION 'Complimentary entitlement unavailable' USING errcode='42501';
  END IF;
 END IF;
 UPDATE atlas.universal_person_invitations SET state='claimed',
   claimed_by_user_id=v_actor,claimed_at=now(),changed_at=now()
   WHERE id=v_i.id;
 INSERT INTO atlas.universal_person_invitation_events(invitation_id,action,
  actor_user_id,evidence) VALUES(v_i.id,'claimed',v_actor,
    jsonb_build_object('verifiedEmail',true,
      'existingPersonPreserved',v_i.existing_person_id IS NOT NULL,
      'billingCreated',false));
 RETURN jsonb_build_object('ok',true,'state','claimed',
   'existingPersonId',v_i.existing_person_id,
   'next','normal_personal_atlas_entry','createsStripeObligation',false);
END $f$;

CREATE FUNCTION atlas.transition_universal_person_invitation_self_v1(
 p_invitation_id uuid,p_action text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_i atlas.universal_person_invitations%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_i FROM atlas.universal_person_invitations
 WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL THEN RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 PERFORM atlas.universal_person_invitation_steward_self_v1(
  v_i.organization_id,v_i.existing_person_id);
 IF p_action='revoke' AND v_i.state IN ('prepared','issued') THEN
   UPDATE atlas.universal_person_invitations
    SET state='revoked',changed_at=now() WHERE id=v_i.id;
   IF v_i.complimentary_invitation_id IS NOT NULL THEN
    UPDATE atlas.personal_atlas_complimentary_test_invitations SET state='revoked'
      WHERE id=v_i.complimentary_invitation_id
        AND claimed_by_user_id IS NULL;
   END IF;
 ELSIF p_action='assert_manual_send' AND v_i.state='issued'
    AND v_i.expires_at>now() THEN
    UPDATE atlas.universal_person_invitations
    SET delivery_state='manual_send_asserted',changed_at=now() WHERE id=v_i.id;
 ELSE
   RAISE EXCEPTION 'Unsupported invitation transition' USING errcode='42501';
 END IF;
 INSERT INTO atlas.universal_person_invitation_events(invitation_id,action,
  actor_user_id,evidence) VALUES(v_i.id,p_action,v_actor,
    jsonb_build_object('providerConfirmed',false));
 RETURN jsonb_build_object('ok',true,'state',case when p_action='revoke'
   then 'revoked' else 'issued' end,'deliveryState',case
   when p_action='assert_manual_send' then 'manual_send_asserted'
   else v_i.delivery_state end);
END $f$;

CREATE FUNCTION atlas.decline_universal_person_invitation_self_v1(
 p_invitation_id uuid,p_code text,p_not_me boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_email text;v_i atlas.universal_person_invitations%rowtype;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_actor;
 SELECT * INTO v_i FROM atlas.universal_person_invitations
 WHERE id=p_invitation_id FOR UPDATE;
 IF v_i.id IS NULL OR v_i.recipient_email<>v_email
 OR v_i.state<>'issued' OR v_i.expires_at<=now()
 OR v_i.token_digest IS NULL
 OR length(coalesce(p_code,'')) NOT BETWEEN 20 AND 128
 OR v_i.token_digest<>encode(extensions.digest(coalesce(p_code,''),'sha256'),'hex')
 THEN RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 UPDATE atlas.universal_person_invitations SET
  state=CASE WHEN p_not_me THEN 'not_me' ELSE 'declined' END,
  changed_at=now() WHERE id=v_i.id;
 UPDATE atlas.personal_atlas_complimentary_test_invitations SET state='revoked'
  WHERE id=v_i.complimentary_invitation_id AND claimed_by_user_id IS NULL;
 INSERT INTO atlas.universal_person_invitation_events(invitation_id,action,
  actor_user_id) VALUES(v_i.id,
   CASE WHEN p_not_me THEN 'reported_not_me' ELSE 'declined' END,v_actor);
 RETURN jsonb_build_object('ok',true,'state',
   CASE WHEN p_not_me THEN 'not_me' ELSE 'declined' END,
   'noExistingPersonChanged',true);
END $f$;

CREATE FUNCTION atlas.list_universal_person_invitations_self_v1(p_org uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_items jsonb;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 PERFORM atlas.universal_person_invitation_steward_self_v1(p_org,NULL);
 SELECT coalesce(jsonb_agg(x.item ORDER BY x.created_at DESC),'[]'::jsonb)
 INTO v_items FROM (
  SELECT i.created_at,jsonb_build_object(
    'invitationId',i.id,'personId',i.existing_person_id,
    'name',i.intended_name,'email',i.recipient_email,
    'status',CASE WHEN i.state='issued' AND i.expires_at<=now()
       THEN 'expired' ELSE i.state END,
    'deliveryState',i.delivery_state,'expiresAt',i.expires_at,
    'identityClaimCaseId',i.identity_claim_case_id,
    'claimed',i.claimed_at IS NOT NULL) AS item
   FROM atlas.universal_person_invitations i WHERE i.organization_id=p_org
   ORDER BY i.created_at DESC LIMIT 100
 ) x;
 RETURN jsonb_build_object('ok',true,'items',v_items,'limit',100);
END $f$;


CREATE FUNCTION atlas.universal_person_invitation_history_self_v1(p_invitation_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $f$
DECLARE v_actor uuid;v_invite atlas.universal_person_invitations%rowtype;
 v_events jsonb;
BEGIN
 v_actor:=atlas.existing_person_claim_signed_actor_v1();
 SELECT * INTO v_invite FROM atlas.universal_person_invitations
 WHERE id=p_invitation_id;
 IF v_invite.id IS NULL THEN
  RAISE EXCEPTION 'Invitation unavailable' USING errcode='42501'; END IF;
 PERFORM atlas.universal_person_invitation_steward_self_v1(
   v_invite.organization_id,v_invite.existing_person_id);
 SELECT coalesce(jsonb_agg(x.data ORDER BY x.occurred_at DESC),'[]'::jsonb)
 INTO v_events FROM (
  SELECT e.occurred_at,jsonb_build_object(
   'action',e.action,'actorAuthUserId',e.actor_user_id,
   'occurredAt',e.occurred_at,'evidence',e.evidence) data
  FROM atlas.universal_person_invitation_events e
  WHERE e.invitation_id=p_invitation_id
  ORDER BY e.occurred_at DESC,e.id DESC LIMIT 75
 ) x;
 RETURN jsonb_build_object('ok',true,'invitationId',v_invite.id,
  'events',v_events,'limit',75);
END $f$;

-- Signed public RPCs are invokers; private schema retains guarded source.
CREATE FUNCTION public.prepare_universal_person_invitation_self_api_v1(
 p_organization_id uuid,p_name text,p_email text,p_existing_person_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.prepare_universal_person_invitation_self_v1(
 p_organization_id,p_name,p_email,p_existing_person_id) $f$;
CREATE FUNCTION public.issue_universal_person_invitation_self_api_v1(p_invitation_id uuid)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.issue_universal_person_invitation_self_v1(p_invitation_id) $f$;
CREATE FUNCTION public.inspect_universal_person_invitation_self_api_v1(p_invitation_id uuid,p_code text)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.inspect_universal_person_invitation_self_v1(p_invitation_id,p_code) $f$;
CREATE FUNCTION public.claim_universal_person_invitation_self_api_v1(p_invitation_id uuid,p_code text,p_accept boolean)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.claim_universal_person_invitation_self_v1(p_invitation_id,p_code,p_accept) $f$;
CREATE FUNCTION public.decline_universal_person_invitation_self_api_v1(p_invitation_id uuid,p_code text,p_not_me boolean DEFAULT false)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.decline_universal_person_invitation_self_v1(p_invitation_id,p_code,p_not_me) $f$;
CREATE FUNCTION public.transition_universal_person_invitation_self_api_v1(p_invitation_id uuid,p_action text)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.transition_universal_person_invitation_self_v1(p_invitation_id,p_action) $f$;
CREATE FUNCTION public.universal_person_invitation_history_self_api_v1(p_invitation_id uuid)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.universal_person_invitation_history_self_v1(p_invitation_id) $f$;
CREATE FUNCTION public.list_universal_person_invitations_self_api_v1(p_org uuid)
 RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
 AS $f$ SELECT atlas.list_universal_person_invitations_self_v1(p_org) $f$;

REVOKE ALL ON FUNCTION atlas.universal_person_inviter_self_v1(uuid),
 atlas.universal_person_invitation_steward_self_v1(uuid,uuid),
 atlas.prepare_universal_person_invitation_self_v1(uuid,text,text,uuid),
 atlas.issue_universal_person_invitation_self_v1(uuid),
 atlas.inspect_universal_person_invitation_self_v1(uuid,text),
 atlas.claim_universal_person_invitation_self_v1(uuid,text,boolean),
 atlas.decline_universal_person_invitation_self_v1(uuid,text,boolean),
 atlas.transition_universal_person_invitation_self_v1(uuid,text),
 atlas.universal_person_invitation_history_self_v1(uuid),
 atlas.list_universal_person_invitations_self_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION atlas.universal_person_inviter_self_v1(uuid),
 atlas.universal_person_invitation_steward_self_v1(uuid,uuid),
 atlas.prepare_universal_person_invitation_self_v1(uuid,text,text,uuid),
 atlas.issue_universal_person_invitation_self_v1(uuid),
 atlas.inspect_universal_person_invitation_self_v1(uuid,text),
 atlas.claim_universal_person_invitation_self_v1(uuid,text,boolean),
 atlas.decline_universal_person_invitation_self_v1(uuid,text,boolean),
 atlas.transition_universal_person_invitation_self_v1(uuid,text),
 atlas.universal_person_invitation_history_self_v1(uuid),
 atlas.list_universal_person_invitations_self_v1(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.prepare_universal_person_invitation_self_api_v1(uuid,text,text,uuid),
 public.issue_universal_person_invitation_self_api_v1(uuid),
 public.inspect_universal_person_invitation_self_api_v1(uuid,text),
 public.claim_universal_person_invitation_self_api_v1(uuid,text,boolean),
 public.decline_universal_person_invitation_self_api_v1(uuid,text,boolean),
 public.transition_universal_person_invitation_self_api_v1(uuid,text),
 public.universal_person_invitation_history_self_api_v1(uuid),
 public.list_universal_person_invitations_self_api_v1(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_universal_person_invitation_self_api_v1(uuid,text,text,uuid),
 public.issue_universal_person_invitation_self_api_v1(uuid),
 public.inspect_universal_person_invitation_self_api_v1(uuid,text),
 public.claim_universal_person_invitation_self_api_v1(uuid,text,boolean),
 public.decline_universal_person_invitation_self_api_v1(uuid,text,boolean),
 public.transition_universal_person_invitation_self_api_v1(uuid,text),
 public.universal_person_invitation_history_self_api_v1(uuid),
 public.list_universal_person_invitations_self_api_v1(uuid) TO authenticated;
COMMIT;
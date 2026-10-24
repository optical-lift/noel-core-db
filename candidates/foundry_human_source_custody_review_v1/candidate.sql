-- SOURCE ONLY: human scope-of-source custody case, not an AI credential.
-- Depends on Foundry Gate 2 pending-workspace registry and signed owner RPCs.
-- Always keep workspace_authority_registry_v1.custody_review_state pending;
-- an independent human record DOES NOT grant AI-carrier access.
BEGIN;

CREATE TABLE foundry.source_custody_review_cases_v1 (
  case_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id text NOT NULL REFERENCES foundry.workspace_authority_registry_v1(workspace_id),
  request_id uuid NOT NULL,
  owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  reviewer_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  claim_basis_kind text NOT NULL CHECK (claim_basis_kind IN (
    'first_party','public_source','subject_authorization','custodian_authorization'
  )),
  source_refs text[] NOT NULL CHECK(cardinality(source_refs) BETWEEN 1 AND 12),
  permitted_human_actions text[] NOT NULL CHECK(cardinality(permitted_human_actions) BETWEEN 1 AND 4),
  scope_description text NOT NULL CHECK(length(btrim(scope_description)) BETWEEN 15 AND 2000),
  claimed_authority_basis text NOT NULL CHECK(length(btrim(claimed_authority_basis)) BETWEEN 20 AND 3000),
  review_state text NOT NULL DEFAULT 'pending' CHECK (
    review_state IN ('pending','approved','rejected','revoked')
  ),
  review_basis text,
  reviewed_at timestamptz,
  revoked_at timestamptz,
  revoked_by_principal_id uuid REFERENCES atlas.principals(id),
  revoke_reason text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_principal_id,request_id),
  CHECK(owner_principal_id<>reviewer_principal_id),
  CHECK(review_state<>'approved' OR (reviewed_at IS NOT NULL AND length(btrim(review_basis)) >= 25)),
  CHECK(review_state<>'revoked' OR (revoked_at IS NOT NULL AND revoked_by_principal_id IS NOT NULL)),
  CHECK(permitted_human_actions <@ ARRAY['catalog','preserve','transcribe','analyze']::text[]),
  CHECK(NOT ('agent_access' = ANY(permitted_human_actions))),
  CHECK(expires_at IS NULL OR expires_at>created_at)
);
CREATE INDEX source_custody_review_cases_workspace_owner_v1
  ON foundry.source_custody_review_cases_v1(workspace_id,owner_principal_id);
CREATE INDEX source_custody_review_cases_reviewer_pending_v1
  ON foundry.source_custody_review_cases_v1(reviewer_principal_id,review_state);

ALTER TABLE foundry.source_custody_review_cases_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON foundry.source_custody_review_cases_v1
  FROM PUBLIC,anon,authenticated,service_role;

-- All review operations use genuine signed session and present non-anonymous
-- Atlas Principal, never client-selected identities or user_metadata.
CREATE OR REPLACE FUNCTION atlas.foundry_current_signed_principal_v1()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','pg_temp'
AS $fn$
DECLARE v_user uuid:=auth.uid();
        v_session uuid;
        v_principal uuid;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id=v_user AND u.is_anonymous=false
    AND (u.banned_until IS NULL OR u.banned_until<=now())
  ) THEN
    RAISE EXCEPTION 'Active non-anonymous Atlas sign-in required' USING ERRCODE='42501';
  END IF;
  BEGIN
    v_session:=NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid signed session' USING ERRCODE='42501';
  END;
  IF v_session IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    WHERE s.id=v_session AND s.user_id=v_user
    AND (s.not_after IS NULL OR s.not_after>now())
  ) THEN
    RAISE EXCEPTION 'Revoked or missing signed session' USING ERRCODE='42501';
  END IF;
  SELECT p.id INTO v_principal FROM atlas.principals p
    WHERE p.user_id=v_user AND p.status='active';
  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Active Atlas Principal required' USING ERRCODE='42501';
  END IF;
  RETURN v_principal;
END
$fn$;
REVOKE ALL ON FUNCTION atlas.foundry_current_signed_principal_v1()
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.foundry_current_signed_principal_v1()
  TO authenticated;

CREATE OR REPLACE FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(
  p_workspace_id text,
  p_request_id uuid,
  p_reviewer_principal_id uuid,
  p_claim_basis_kind text,
  p_source_refs text[],
  p_permitted_human_actions text[],
  p_scope_description text,
  p_claimed_authority_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_ws foundry.workspace_authority_registry_v1%rowtype;
        v_existing foundry.source_custody_review_cases_v1%rowtype;
        v_case_id uuid;
        v_seq bigint;
        v_source text;
BEGIN
  IF p_request_id IS NULL OR p_reviewer_principal_id IS NULL
     OR NULLIF(btrim(p_workspace_id),'') IS NULL THEN
    RAISE EXCEPTION 'Workspace, stable request, and human reviewer required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_ws FROM foundry.workspace_authority_registry_v1
   WHERE workspace_id=p_workspace_id AND owner_principal_id=v_actor
   FOR UPDATE;
  IF NOT FOUND OR v_ws.custody_review_state<>'pending'
    OR v_ws.revoked_at IS NOT NULL OR v_ws.suspended_at IS NOT NULL THEN
    RAISE EXCEPTION 'Workspace inaccessible or not in pending human custody' USING ERRCODE='42501';
  END IF;
  IF p_reviewer_principal_id=v_actor OR NOT EXISTS (
    SELECT 1 FROM atlas.principals p
    WHERE p.id=p_reviewer_principal_id AND p.status='active'
      AND p.user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A distinct active human reviewer is required' USING ERRCODE='22023';
  END IF;
  -- Reviewer must be an existing verified connection to this operator.
  -- Never trust an arbitrary UUID or merely client-rendered picker selection.
  IF NOT EXISTS (
    SELECT 1
    FROM atlas.principals reviewer
    JOIN auth.users reviewer_user ON reviewer_user.id=reviewer.user_id
      AND reviewer_user.is_anonymous=false
      AND (reviewer_user.banned_until IS NULL OR reviewer_user.banned_until<=now())
    JOIN atlas.organization_memberships rmember ON rmember.user_id=reviewer.user_id
      AND rmember.active
      AND (rmember.eligibility_begins_on IS NULL
           OR rmember.eligibility_begins_on<=current_date)
      AND (rmember.eligibility_ends_on IS NULL
           OR rmember.eligibility_ends_on>=current_date)
    JOIN atlas.organization_memberships omember
      ON omember.organization_id=rmember.organization_id
      AND omember.active
      AND (omember.eligibility_begins_on IS NULL
           OR omember.eligibility_begins_on<=current_date)
      AND (omember.eligibility_ends_on IS NULL
           OR omember.eligibility_ends_on>=current_date)
    JOIN atlas.principals operator ON operator.user_id=omember.user_id
      AND operator.id=v_actor
    WHERE reviewer.id=p_reviewer_principal_id
  ) THEN
    RAISE EXCEPTION 'Reviewer is not an active verified connected Principal'
      USING ERRCODE='42501';
  END IF;
  IF p_claim_basis_kind IS NULL OR p_claim_basis_kind NOT IN (
      'first_party','public_source','subject_authorization','custodian_authorization')
     OR coalesce(cardinality(p_source_refs),0) NOT BETWEEN 1 AND 12
     OR coalesce(cardinality(p_permitted_human_actions),0) NOT BETWEEN 1 AND 4
     OR p_permitted_human_actions <@ ARRAY['catalog','preserve','transcribe','analyze']::text[] IS NOT TRUE
     OR NULLIF(btrim(p_scope_description),'') IS NULL
     OR length(btrim(p_scope_description)) NOT BETWEEN 15 AND 2000
     OR NULLIF(btrim(p_claimed_authority_basis),'') IS NULL
     OR length(btrim(p_claimed_authority_basis)) NOT BETWEEN 20 AND 3000
  THEN RAISE EXCEPTION 'Precise source scope and basis required' USING ERRCODE='22023'; END IF;
  FOREACH v_source IN ARRAY p_source_refs LOOP
    IF v_source IS NULL OR length(btrim(v_source)) NOT BETWEEN 3 AND 300
    THEN RAISE EXCEPTION 'Every source reference must be bounded and nonempty' USING ERRCODE='22023'; END IF;
  END LOOP;

  -- Serializes retries and Foundry sequence against existing append_event lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
  SELECT * INTO v_existing FROM foundry.source_custody_review_cases_v1
    WHERE owner_principal_id=v_actor AND request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.workspace_id IS DISTINCT FROM p_workspace_id
      OR v_existing.reviewer_principal_id IS DISTINCT FROM p_reviewer_principal_id
      OR v_existing.claim_basis_kind IS DISTINCT FROM p_claim_basis_kind
      OR v_existing.source_refs IS DISTINCT FROM p_source_refs
      OR v_existing.permitted_human_actions IS DISTINCT FROM p_permitted_human_actions
      OR v_existing.scope_description IS DISTINCT FROM btrim(p_scope_description)
      OR v_existing.claimed_authority_basis IS DISTINCT FROM btrim(p_claimed_authority_basis)
    THEN RAISE EXCEPTION 'Changed payload for previously used source-custody request' USING ERRCODE='22023'; END IF;
    RETURN jsonb_build_object('ok',true,'caseId',v_existing.case_id,
      'reviewState',v_existing.review_state,'replayed',true,'aiCarrierAccess',false);
  END IF;
  INSERT INTO foundry.source_custody_review_cases_v1(
    workspace_id,request_id,owner_principal_id,reviewer_principal_id,
    claim_basis_kind,source_refs,permitted_human_actions,
    scope_description,claimed_authority_basis
  ) VALUES(
    p_workspace_id,p_request_id,v_actor,p_reviewer_principal_id,
    p_claim_basis_kind,p_source_refs,p_permitted_human_actions,
    btrim(p_scope_description),btrim(p_claimed_authority_basis)
  ) RETURNING case_id INTO v_case_id;

  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=p_workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',p_workspace_id,'event_type','SOURCE_CUSTODY_REVIEW_REQUESTED',
    'sequence',v_seq,'payload',jsonb_build_object(
      'case_id',v_case_id,'scope_description',btrim(p_scope_description),
      'source_refs',to_jsonb(p_source_refs),'permitted_human_actions',to_jsonb(p_permitted_human_actions),
      'claimed_authority_basis',btrim(p_claimed_authority_basis),'claim_basis_kind',p_claim_basis_kind,'review_state','pending',
      'ai_carrier_access',false),
    'basis_refs',to_jsonb(p_source_refs),
    'authority','authenticated_owner_attestation_unreviewed',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',v_case_id,
    'reviewState','pending','replayed',false,'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(
 text,uuid,uuid,text,text[],text[],text,text
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(
 text,uuid,uuid,text,text[],text[],text,text
) TO authenticated;

CREATE OR REPLACE FUNCTION atlas.inspect_foundry_source_custody_review_self_api_v1(
  p_case_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_case foundry.source_custody_review_cases_v1%rowtype;
BEGIN
  SELECT * INTO v_case FROM foundry.source_custody_review_cases_v1
  WHERE case_id=p_case_id
    AND (owner_principal_id=v_actor OR reviewer_principal_id=v_actor);
  IF NOT FOUND THEN RAISE EXCEPTION 'Custody review inaccessible' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('ok',true,'caseId',v_case.case_id,
    'workspaceId',v_case.workspace_id,'ownerPrincipalId',v_case.owner_principal_id,
    'reviewerPrincipalId',v_case.reviewer_principal_id,
    'claimBasisKind',v_case.claim_basis_kind,'sourceRefs',to_jsonb(v_case.source_refs),
    'humanActions',to_jsonb(v_case.permitted_human_actions),
    'scopeDescription',v_case.scope_description,
    'claimedAuthorityBasis',v_case.claimed_authority_basis,
    'reviewState',v_case.review_state,'reviewBasis',v_case.review_basis,
    'reviewedAt',v_case.reviewed_at,'revokedAt',v_case.revoked_at,
    'expiresAt',v_case.expires_at,'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.inspect_foundry_source_custody_review_self_api_v1(uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.inspect_foundry_source_custody_review_self_api_v1(uuid)
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(
  p_case_id uuid,p_decision text,p_review_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_case foundry.source_custody_review_cases_v1%rowtype;
        v_seq bigint;
        v_new_state text;
BEGIN
  IF p_decision NOT IN ('approve','reject') OR p_decision IS NULL
     OR NULLIF(btrim(p_review_basis),'') IS NULL
     OR length(btrim(p_review_basis)) NOT BETWEEN 25 AND 2500 THEN
    RAISE EXCEPTION 'Human review decision and explicit independent basis required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_case FROM foundry.source_custody_review_cases_v1
    WHERE case_id=p_case_id FOR UPDATE;
  IF NOT FOUND OR v_case.reviewer_principal_id IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Only the designated independent reviewer may decide' USING ERRCODE='42501';
  END IF;
  IF v_case.review_state<>'pending' THEN
    RAISE EXCEPTION 'Custody review decision already recorded' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM foundry.workspace_authority_registry_v1 w
    WHERE w.workspace_id=v_case.workspace_id AND w.owner_principal_id=v_case.owner_principal_id
      AND w.custody_review_state='pending' AND w.revoked_at IS NULL AND w.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Owner workspace no longer eligible for custody review' USING ERRCODE='42501';
  END IF;
  v_new_state:=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END;
  UPDATE foundry.source_custody_review_cases_v1 SET
    review_state=v_new_state,review_basis=btrim(p_review_basis),
    reviewed_at=now()
  WHERE case_id=p_case_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_case.workspace_id,0));
  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=v_case.workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',v_case.workspace_id,
    'event_type',CASE WHEN v_new_state='approved'
       THEN 'SOURCE_CUSTODY_HUMAN_REVIEW_APPROVED'
       ELSE 'SOURCE_CUSTODY_HUMAN_REVIEW_REJECTED' END,
    'sequence',v_seq,
    'payload',jsonb_build_object('case_id',p_case_id,'review_state',v_new_state,
      'reviewer_principal_id',v_actor,'review_basis',btrim(p_review_basis),
      'ai_carrier_access',false),
    'basis_refs',to_jsonb(v_case.source_refs),
    'authority','independent_human_source_scope_review_only',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
    'reviewState',v_new_state,'aiCarrierAccess',false,
    'workspaceCustodyState','pending');
END
$fn$;
REVOKE ALL ON FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)
 TO authenticated;

CREATE OR REPLACE FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(
  p_case_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_case foundry.source_custody_review_cases_v1%rowtype;
        v_seq bigint;
BEGIN
  IF NULLIF(btrim(p_reason),'') IS NULL OR length(btrim(p_reason)) NOT BETWEEN 15 AND 1500
  THEN RAISE EXCEPTION 'Revocation reason required' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_case FROM foundry.source_custody_review_cases_v1
   WHERE case_id=p_case_id FOR UPDATE;
  IF NOT FOUND OR v_actor NOT IN (v_case.owner_principal_id,v_case.reviewer_principal_id)
  THEN RAISE EXCEPTION 'Custody case inaccessible' USING ERRCODE='42501'; END IF;
  IF v_case.review_state='revoked' THEN
    RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
      'reviewState','revoked','replayed',true,'aiCarrierAccess',false);
  END IF;
  IF v_case.review_state NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'Rejected review cannot be revoked' USING ERRCODE='22023';
  END IF;
  UPDATE foundry.source_custody_review_cases_v1
    SET review_state='revoked',revoked_at=now(),
        revoked_by_principal_id=v_actor,revoke_reason=btrim(p_reason)
    WHERE case_id=p_case_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_case.workspace_id,0));
  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=v_case.workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',v_case.workspace_id,'event_type','SOURCE_CUSTODY_HUMAN_REVIEW_REVOKED',
    'sequence',v_seq,'payload',jsonb_build_object(
      'case_id',p_case_id,'revoked_by_principal_id',v_actor,
      'reason',btrim(p_reason),'ai_carrier_access',false),
    'basis_refs',to_jsonb(v_case.source_refs),
    'authority','human_source_scope_review_revocation',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
    'reviewState','revoked','replayed',false,'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text)
 TO authenticated;

-- PostgREST exposes only public schemas. Invoker wrappers preserve session
-- identity; all real authorization lives in private Atlas functions above.
CREATE OR REPLACE FUNCTION public.request_foundry_source_custody_review_self_api_v1(
  p_workspace_id text,p_request_id uuid,p_reviewer_principal_id uuid,
  p_claim_basis_kind text,p_source_refs text[],p_permitted_human_actions text[],
  p_scope_description text,p_claimed_authority_basis text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.request_foundry_source_custody_review_self_api_v1(
  p_workspace_id,p_request_id,p_reviewer_principal_id,p_claim_basis_kind,
  p_source_refs,p_permitted_human_actions,p_scope_description,p_claimed_authority_basis);
$bridge$;
REVOKE ALL ON FUNCTION public.request_foundry_source_custody_review_self_api_v1(
 text,uuid,uuid,text,text[],text[],text,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.request_foundry_source_custody_review_self_api_v1(
 text,uuid,uuid,text,text[],text[],text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.inspect_foundry_source_custody_review_self_api_v1(p_case_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.inspect_foundry_source_custody_review_self_api_v1(p_case_id);
$bridge$;
REVOKE ALL ON FUNCTION public.inspect_foundry_source_custody_review_self_api_v1(uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.inspect_foundry_source_custody_review_self_api_v1(uuid)
 TO authenticated;

CREATE OR REPLACE FUNCTION public.decide_foundry_source_custody_review_self_api_v1(
 p_case_id uuid,p_decision text,p_review_basis text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.decide_foundry_source_custody_review_self_api_v1(
 p_case_id,p_decision,p_review_basis);
$bridge$;
REVOKE ALL ON FUNCTION public.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)
 TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_foundry_source_custody_review_self_api_v1(
 p_case_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.revoke_foundry_source_custody_review_self_api_v1(p_case_id,p_reason);
$bridge$;
REVOKE ALL ON FUNCTION public.revoke_foundry_source_custody_review_self_api_v1(uuid,text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.revoke_foundry_source_custody_review_self_api_v1(uuid,text)
 TO authenticated;

-- IMPORTANT: do not UPDATE workspace_authority_registry_v1 to "reviewed".
-- Nothing in this migration registers a Foundry delegated-agent command.

-- A reviewer is selected from existing connected, active human Principals.
-- No global Auth-user directory and no new identity/seat type. The requesting
-- owner must currently share an active Atlas organization membership.
CREATE OR REPLACE FUNCTION atlas.list_foundry_source_custody_reviewers_self_api_v1(
  p_workspace_id text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_uid uuid;
        v_items jsonb;
BEGIN
  SELECT p.user_id INTO v_uid FROM atlas.principals p WHERE p.id=v_actor;
  IF NOT EXISTS (
    SELECT 1 FROM foundry.workspace_authority_registry_v1 w
    WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor
      AND w.custody_review_state='pending'
      AND w.revoked_at IS NULL AND w.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Workspace inaccessible for human custody review'
      USING ERRCODE='42501';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'principalId',r.id,'displayName',r.name
  ) ORDER BY r.name,r.id),'[]'::jsonb) INTO v_items
  FROM (
    SELECT DISTINCT p.id,p.name
    FROM atlas.organization_memberships own
    JOIN atlas.organization_memberships connected
      ON connected.organization_id=own.organization_id
      AND connected.active
      AND (connected.eligibility_begins_on IS NULL
           OR connected.eligibility_begins_on<=current_date)
      AND (connected.eligibility_ends_on IS NULL
           OR connected.eligibility_ends_on>=current_date)
    JOIN atlas.principals p ON p.user_id=connected.user_id
      AND p.status='active' AND p.id<>v_actor
    JOIN auth.users au ON au.id=p.user_id
      AND au.is_anonymous=false
      AND (au.banned_until IS NULL OR au.banned_until<=now())
    WHERE own.user_id=v_uid AND own.active
      AND (own.eligibility_begins_on IS NULL
           OR own.eligibility_begins_on<=current_date)
      AND (own.eligibility_ends_on IS NULL
           OR own.eligibility_ends_on>=current_date)
  ) r;
  RETURN jsonb_build_object('ok',true,'workspaceId',p_workspace_id,
    'reviewers',v_items,'selectionBasis','active_shared_atlas_connection',
    'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.list_foundry_source_custody_reviewers_self_api_v1(text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_source_custody_reviewers_self_api_v1(text)
 TO authenticated;

CREATE OR REPLACE FUNCTION public.list_foundry_source_custody_reviewers_self_api_v1(
 p_workspace_id text
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.list_foundry_source_custody_reviewers_self_api_v1(p_workspace_id);
$bridge$;
REVOKE ALL ON FUNCTION public.list_foundry_source_custody_reviewers_self_api_v1(text)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.list_foundry_source_custody_reviewers_self_api_v1(text)
 TO authenticated;

-- A person who was designated as reviewer can find their assigned pending
-- cases without anyone sharing a raw UUID. Only their own active Principal
-- and real signed GoTrue session can query this inbox.
CREATE OR REPLACE FUNCTION atlas.list_foundry_source_custody_reviews_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_cases jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'caseId',r.case_id,
    'workspaceId',r.workspace_id,
    'reviewState',r.review_state,
    'myRole',CASE WHEN r.reviewer_principal_id=v_actor
      THEN 'reviewer' ELSE 'owner' END,
    'provisionalSubjectLabel',w.provisional_subject_label,
    'ownerName',own.name,
    'createdAt',r.created_at
  ) ORDER BY r.created_at DESC,r.case_id),'[]'::jsonb) INTO v_cases
  FROM (
    SELECT *
    FROM foundry.source_custody_review_cases_v1 c
    WHERE c.owner_principal_id=v_actor OR c.reviewer_principal_id=v_actor
    ORDER BY c.created_at DESC,c.case_id
    LIMIT 80
  ) r
  JOIN foundry.workspace_authority_registry_v1 w ON w.workspace_id=r.workspace_id
  JOIN atlas.principals own ON own.id=r.owner_principal_id;
  RETURN jsonb_build_object('ok',true,'items',v_cases,
    'contractVersion','foundry_source_custody_human_inbox_v1',
    'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.list_foundry_source_custody_reviews_self_api_v1()
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_source_custody_reviews_self_api_v1()
 TO authenticated;

CREATE OR REPLACE FUNCTION public.list_foundry_source_custody_reviews_self_api_v1()
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.list_foundry_source_custody_reviews_self_api_v1();
$bridge$;
REVOKE ALL ON FUNCTION public.list_foundry_source_custody_reviews_self_api_v1()
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.list_foundry_source_custody_reviews_self_api_v1()
 TO authenticated;

-- Owner Index projection for a signed person's own new Foundry workspaces.
-- No historical workspace backfill and no global workspace enumeration.
CREATE OR REPLACE FUNCTION atlas.list_foundry_owned_workspaces_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_items jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'workspaceId',w.workspace_id,
    'provisionalSubjectLabel',w.provisional_subject_label,
    'provisionalField',w.provisional_field,
    'custodyReviewState',w.custody_review_state,
    'subjectIdentityState',w.subject_identity_state,
    'createdAt',w.created_at
  ) ORDER BY w.created_at DESC,w.workspace_id),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT * FROM foundry.workspace_authority_registry_v1
    WHERE owner_principal_id=v_actor
    ORDER BY created_at DESC,workspace_id
    LIMIT 80
  ) w;
  RETURN jsonb_build_object(
    'ok',true,'items',v_items,
    'contractVersion','foundry_owned_workspace_index_v1',
    'aiCarrierAccess',false,'canonicalAtlasMutation',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.list_foundry_owned_workspaces_self_api_v1()
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.list_foundry_owned_workspaces_self_api_v1()
 TO authenticated;

CREATE OR REPLACE FUNCTION public.list_foundry_owned_workspaces_self_api_v1()
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $bridge$
 SELECT atlas.list_foundry_owned_workspaces_self_api_v1();
$bridge$;
REVOKE ALL ON FUNCTION public.list_foundry_owned_workspaces_self_api_v1()
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.list_foundry_owned_workspaces_self_api_v1()
 TO authenticated;
COMMIT;

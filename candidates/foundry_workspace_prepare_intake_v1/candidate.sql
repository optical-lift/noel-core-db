-- SOURCE-ONLY: protected Foundry workspace preparation (no subject authority).
-- Depends on private workspace_authority_registry_v1 (PR #2093).
-- Not a production migration; test on disposable schema clone first.
-- Does NOT activate carrier delegation, external-subject custody, or Atlas Reality.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  p_request_id uuid,
  p_subject_label text,
  p_provisional_field text,
  p_custody_scope_kind text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE
  v_actor_user_id uuid := auth.uid();
  v_owner atlas.principals%rowtype;
  v_auth_user auth.users%rowtype;
  v_session_id uuid;
  v_label text := NULLIF(BTRIM(p_subject_label),'');
  v_field text := NULLIF(BTRIM(p_provisional_field),'');
  v_existing foundry.workspace_authority_registry_v1%rowtype;
  v_workspace_id text;
  v_event_id text;
  v_append jsonb;
BEGIN
  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'verified Atlas sign-in required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_auth_user FROM auth.users WHERE id=v_actor_user_id;
  IF NOT FOUND OR v_auth_user.is_anonymous
     OR (v_auth_user.banned_until IS NOT NULL AND v_auth_user.banned_until>now())
  THEN
    RAISE EXCEPTION 'active non-anonymous verified Atlas authentication required' USING ERRCODE='42501';
  END IF;

  -- A genuine signed JWT must reference an active GoTrue session, and
  -- deleting that session must revoke this operation immediately even
  -- while the JWT itself has not yet expired.
  BEGIN
    v_session_id := NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'valid GoTrue signed session required' USING ERRCODE='42501';
  END;
  IF v_session_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions sess
    WHERE sess.id=v_session_id
      AND sess.user_id=v_actor_user_id
      AND (sess.not_after IS NULL OR sess.not_after>now())
  ) THEN
    RAISE EXCEPTION 'active GoTrue session required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_owner FROM atlas.principals
    WHERE user_id=v_actor_user_id AND status='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active Atlas Principal required' USING ERRCODE='42501';
  END IF;

  IF p_request_id IS NULL THEN RAISE EXCEPTION 'stable request ID required'; END IF;
  IF v_label IS NULL OR length(v_label)>500 THEN
    RAISE EXCEPTION 'provisional subject label required within bounds';
  END IF;
  IF v_field IS NULL OR length(v_field)>2000 THEN
    RAISE EXCEPTION 'provisional field required within bounds';
  END IF;
  IF p_custody_scope_kind NOT IN ('verified_self','documented_external')
    OR p_custody_scope_kind IS NULL THEN
    RAISE EXCEPTION 'invalid requested source-custody classification';
  END IF;

  -- Serialize one human's same idempotent preparation request. A client
  -- can choose the request ID, never the owner Principal or workspace ID.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'foundry-prepare:'||v_owner.id::text||':'||p_request_id::text, 0
  ));

  SELECT * INTO v_existing FROM foundry.workspace_authority_registry_v1
    WHERE owner_principal_id=v_owner.id
      AND creation_request_id=p_request_id
    FOR UPDATE;
  IF FOUND THEN
    IF v_existing.provisional_subject_label IS DISTINCT FROM v_label
       OR v_existing.provisional_field IS DISTINCT FROM v_field
       OR v_existing.custody_scope_kind IS DISTINCT FROM p_custody_scope_kind THEN
      RAISE EXCEPTION 'request ID already used for different Foundry preparation';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'replayed',true,
      'workspaceId',v_existing.workspace_id,
      'custodyReviewState',v_existing.custody_review_state,
      'subjectIdentityState',v_existing.subject_identity_state,
      'canonicalAtlasMutation',false
    );
  END IF;

  v_workspace_id := 'foundry-' || gen_random_uuid()::text;
  v_event_id := 'foundry-event-' || gen_random_uuid()::text;

  INSERT INTO foundry.workspace_authority_registry_v1(
    workspace_id,creation_request_id,owner_principal_id,
    provisional_subject_label,provisional_field,
    subject_identity_state,custody_scope_kind,custody_review_state,
    custody_basis_refs,created_by_principal_id
  ) VALUES(
    v_workspace_id,p_request_id,v_owner.id,
    v_label,v_field,'unresolved',p_custody_scope_kind,
    'pending','{}'::text[],v_owner.id
  );

  -- Append and registry INSERT run in the same transaction.
  -- This is a provisional operator claim, NOT verified testimony or
  -- permission to access or act on the subject's private records.
  v_append := foundry.append_event(jsonb_build_object(
    'event_id',v_event_id,
    'workspace_id',v_workspace_id,
    'event_type','WORKSPACE_CREATED',
    'sequence',1,
    'payload',jsonb_build_object(
      'status','DISCOVERY',
      'owner_principal_id',v_owner.id,
      'provisional_subject',jsonb_build_object(
        'label',v_label,'subject_ref',NULL,'subject_kind',NULL
      ),
      'provisional_field',v_field,
      'boundary_status','UNRESOLVED',
      'custody_review_state','pending',
      'subject_identity_state','unresolved'
    ),
    'basis_refs','[]'::jsonb,
    'authority','authenticated_owner_preparation_only',
    'actor_kind','human',
    'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
                         'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));

  IF v_append->>'status' IS DISTINCT FROM 'APPENDED' THEN
    RAISE EXCEPTION 'Foundry workspace initial event was not appended';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'replayed',false,
    'workspaceId',v_workspace_id,
    'custodyReviewState','pending',
    'subjectIdentityState','unresolved',
    'canonicalAtlasMutation',false
  );
END;
$fn$;

-- Self API authorizes only the authenticated, non-anonymous human owner
-- to create a PENDING custody container. It cannot approve third-party
-- consent, bind a canonical Person, or delegate an AI agent.
REVOKE ALL ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  uuid,text,text,text
) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  uuid,text,text,text
) TO authenticated;
COMMIT;

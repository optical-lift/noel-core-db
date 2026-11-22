-- HELD Shared Transcript Core private audiobook MP3 delivery-profile source.
-- Does not publish, transfer bytes, issue subscribers, create production or grant
-- direct access to the private delivery_profiles table. No live release here.
-- No general configuration editor: this is the source-owned, versioned first
-- private listening profile, independently reused for subsequent audiobooks.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('transcript_core.delivery_profiles') IS NULL
     OR to_regclass('transcript_core.workspace_memberships') IS NULL
     OR to_regclass('transcript_core.workspaces') IS NULL
     OR to_regclass('auth.users') IS NULL
     OR to_regclass('auth.sessions') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL
     OR to_regprocedure('auth.jwt()') IS NULL
  THEN RAISE EXCEPTION 'Native transcript source prerequisites unavailable'
       USING ERRCODE='42501'; END IF;
END $preflight$;

CREATE FUNCTION public.transcript_core_private_mp3_profile_self_api_v1(
  p_workspace_id uuid, p_establish boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $private_mp3_profile$
DECLARE
  v_user uuid; v_claims jsonb; v_session uuid; v_expiry bigint;
  v_profile transcript_core.delivery_profiles%ROWTYPE;
  v_key constant text := 'private_audiobook_mp3';
  v_version constant text := 'native_private_mp3_v1';
  v_name constant text := 'Private audiobook MP3';
  v_config jsonb := jsonb_build_object(
    'schema','transcript_core_private_mp3_delivery_profile_v1',
    'artifactRole','listening_mp3',
    'mimeType','audio/mpeg',
    'codec','libmp3lame',
    'bitrate','128k',
    'channels',1,
    'sampleRate',48000,
    'publication_approved',false
  );
BEGIN
  IF p_workspace_id IS NULL OR p_establish IS NULL THEN
    RAISE EXCEPTION 'Exact profile request required' USING ERRCODE='22023';
  END IF;
  -- This is a source operation for a current real human/editor, not an
  -- API-key/service call and not a substitute for publishing authority.
  v_user := auth.uid(); v_claims := auth.jwt();
  IF v_user IS NULL OR v_claims->>'role' IS DISTINCT FROM 'authenticated'
     OR v_claims->>'sub' IS DISTINCT FROM v_user::text
     OR v_claims->>'is_anonymous' IS DISTINCT FROM 'false'
     OR coalesce(v_claims->>'session_id','') !~
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR coalesce(v_claims->>'exp','') !~ '^[0-9]{1,12}$'
  THEN RAISE EXCEPTION 'Current signed profile editor required'
       USING ERRCODE='42501'; END IF;
  v_session := (v_claims->>'session_id')::uuid;
  v_expiry := (v_claims->>'exp')::bigint;
  IF v_expiry <= extract(epoch from clock_timestamp()) THEN
    RAISE EXCEPTION 'Current signed profile editor required'
      USING ERRCODE='42501'; END IF;

  PERFORM 1
  FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
  WHERE u.id=v_user AND s.id=v_session AND u.is_anonymous IS FALSE
    AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
    AND (s.not_after IS NULL OR s.not_after>clock_timestamp())
  FOR SHARE OF u,s;
  IF NOT FOUND THEN RAISE EXCEPTION 'Current signed profile editor required'
    USING ERRCODE='42501'; END IF;

  -- Serialize profile establishment per existing workspace, including
  -- concurrent exact retries, without creating a second profile registry.
  IF p_establish THEN
    PERFORM 1 FROM transcript_core.workspaces w WHERE w.id=p_workspace_id
      FOR UPDATE;
  ELSE
    PERFORM 1 FROM transcript_core.workspaces w WHERE w.id=p_workspace_id
      FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile workspace unavailable'
    USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM transcript_core.workspace_memberships m
    WHERE m.workspace_id=p_workspace_id AND m.user_id=v_user
    AND m.role IN ('owner','editor') FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Current profile workspace editor required'
    USING ERRCODE='42501'; END IF;

  IF p_establish THEN
    INSERT INTO transcript_core.delivery_profiles (
      workspace_id,profile_key,display_name,rule_version,configuration)
    VALUES(p_workspace_id,v_key,v_name,v_version,v_config)
    ON CONFLICT (workspace_id,profile_key,rule_version) DO NOTHING;
  END IF;
  SELECT * INTO v_profile FROM transcript_core.delivery_profiles dp
    WHERE dp.workspace_id=p_workspace_id AND dp.profile_key=v_key
    AND dp.rule_version=v_version FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Private MP3 profile not established'
    USING ERRCODE='42501'; END IF;
  IF v_profile.display_name IS DISTINCT FROM v_name
    OR v_profile.configuration IS DISTINCT FROM v_config
  THEN RAISE EXCEPTION 'Existing profile source conflicts with fixed rule'
    USING ERRCODE='23505'; END IF;

  -- A revoked/expired session cannot leave a new profile as a committed
  -- successful operation. No publication/recipient rights are implied.
  IF v_expiry<=extract(epoch from clock_timestamp()) OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s WHERE s.id=v_session AND s.user_id=v_user
      AND (s.not_after IS NULL OR s.not_after>clock_timestamp())
  ) THEN RAISE EXCEPTION 'Current signed profile editor required'
    USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object(
    'contractVersion','transcript_core_private_mp3_profile_v1',
    'workspaceId',p_workspace_id,'profileId',v_profile.id,
    'profileKey',v_key,'ruleVersion',v_version,
    'configuration',v_config,'publication_approved',false);
END $private_mp3_profile$;

REVOKE ALL ON FUNCTION
  public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION
  public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)
  TO authenticated;
COMMIT;

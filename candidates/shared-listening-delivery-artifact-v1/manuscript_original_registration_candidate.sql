-- HELD native authored-manuscript original registration (same Transcript Core
-- asset registry and existing private source bucket; no script parse job).
-- Not a production migration. This is not publication or byte verification.
-- Trusted carrier must independently verify GoTrue token, original bytes,
-- extraction/native intake and exact current private storage version.
--
-- An authored original is NOT a performance script or observed recording.
-- This new enum value is committed before use in a separate transaction.
ALTER TYPE transcript_core.asset_provenance_class ADD VALUE IF NOT EXISTS 'manuscript_source';

BEGIN;
CREATE FUNCTION transcript_core.register_verified_manuscript_original_v1(
  p_workspace_id uuid,
  p_object_id uuid,
  p_object_version text,
  p_original_sha256 text,
  p_original_byte_size bigint,
  p_original_format text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog AS $register$
DECLARE
  v_uid uuid; v_claims jsonb; v_session uuid; v_exp bigint;
  v_mime text; v_path text; v_object storage.objects%ROWTYPE;
  v_asset transcript_core.assets%ROWTYPE;
BEGIN
  IF p_workspace_id IS NULL OR p_object_id IS NULL OR p_object_version IS NULL
    OR length(p_object_version) NOT BETWEEN 1 AND 200 OR p_object_version ~ '[[:cntrl:]]'
    OR p_original_sha256 IS NULL OR p_original_sha256 !~ '^[0-9a-f]{64}$'
    OR p_original_byte_size IS NULL OR p_original_byte_size NOT BETWEEN 1 AND 8388608
    OR p_original_format NOT IN ('txt','docx')
  THEN RAISE EXCEPTION 'exact bounded authored manuscript original required' USING ERRCODE='22023'; END IF;
  v_mime:=CASE p_original_format WHEN 'txt' THEN 'text/plain'
    WHEN 'docx' THEN 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' END;
  v_path:=p_workspace_id::text||'/manuscript/'||p_original_sha256||'.'||p_original_format;
  v_uid:=auth.uid(); v_claims:=auth.jwt();
  IF v_uid IS NULL OR v_claims->>'role' IS DISTINCT FROM 'authenticated'
    OR coalesce(v_claims->>'is_anonymous','true')<>'false'
    OR coalesce(v_claims->>'session_id','') !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    OR coalesce(v_claims->>'exp','') !~ '^[0-9]{1,12}$'
  THEN RAISE EXCEPTION 'current signed manuscript session required' USING ERRCODE='42501'; END IF;
  v_session:=(v_claims->>'session_id')::uuid;
  v_exp:=(v_claims->>'exp')::bigint;
  IF v_exp<=extract(epoch from clock_timestamp()) THEN
    RAISE EXCEPTION 'current signed manuscript session required' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
    JOIN transcript_core.workspace_memberships m ON m.user_id=u.id
    WHERE u.id=v_uid AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
    AND s.id=v_session AND (s.not_after IS NULL OR s.not_after>clock_timestamp())
    AND m.workspace_id=p_workspace_id AND m.role IN ('owner','editor')
    FOR SHARE OF u,s,m;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'current workspace source editor required' USING ERRCODE='42501'; END IF;
  v_object:=transcript_core.require_verified_listening_object_v1(
    p_workspace_id,p_object_id,p_object_version,'transcript-core-script-sources',
    v_mime,p_original_byte_size);
  IF v_object.name IS DISTINCT FROM v_path THEN
    RAISE EXCEPTION 'manuscript original exact source path required' USING ERRCODE='23514'; END IF;
  INSERT INTO transcript_core.assets(workspace_id,provenance_class,storage_bucket,
    storage_path,content_hash,mime_type,byte_size)
  VALUES(p_workspace_id,'manuscript_source','transcript-core-script-sources',
    v_path,p_original_sha256,v_mime,p_original_byte_size)
  ON CONFLICT(workspace_id,storage_bucket,storage_path) DO NOTHING;
  SELECT * INTO STRICT v_asset FROM transcript_core.assets
    WHERE workspace_id=p_workspace_id AND storage_bucket='transcript-core-script-sources'
    AND storage_path=v_path FOR SHARE;
  IF v_asset.provenance_class IS DISTINCT FROM 'manuscript_source' OR
    v_asset.content_hash IS DISTINCT FROM p_original_sha256 OR
    v_asset.mime_type IS DISTINCT FROM v_mime OR
    v_asset.byte_size IS DISTINCT FROM p_original_byte_size
  THEN RAISE EXCEPTION 'existing original asset conflicts' USING ERRCODE='23505'; END IF;
  IF v_exp<=extract(epoch from clock_timestamp()) OR NOT EXISTS(
    SELECT 1 FROM auth.sessions s WHERE s.id=v_session AND s.user_id=v_uid
      AND (s.not_after IS NULL OR s.not_after>clock_timestamp()))
  THEN RAISE EXCEPTION 'current signed manuscript session required' USING ERRCODE='42501'; END IF;
  RETURN jsonb_build_object('contractVersion','transcript_core_verified_manuscript_original_v1',
    'assetId',v_asset.id,'workspaceId',p_workspace_id,'originalSha256',p_original_sha256,
    'objectId',p_object_id,'objectVersion',p_object_version,
    'sourceFormat',p_original_format,'publication_approved',false);
END $register$;
REVOKE ALL ON FUNCTION transcript_core.register_verified_manuscript_original_v1(
  uuid,uuid,text,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;

-- Exact private authored-original namespace guard. Other script source paths
-- retain their existing policy. Session and membership are source checked.
CREATE FUNCTION transcript_core.manuscript_original_storage_authorized_self_v1(
 p_bucket text,p_name text
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog AS $guard$
DECLARE v_uid uuid; c jsonb; v_session uuid; w uuid;
BEGIN
 IF p_bucket IS DISTINCT FROM 'transcript-core-script-sources' OR p_name IS NULL
   OR p_name !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/manuscript/[a-f0-9]{64}\.(txt|docx)$'
 THEN RETURN false; END IF;
 v_uid:=auth.uid(); c:=auth.jwt();
 IF v_uid IS NULL OR c->>'role' IS DISTINCT FROM 'authenticated'
  OR coalesce(c->>'is_anonymous','true')<>'false'
  OR coalesce(c->>'session_id','') !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  OR coalesce(c->>'exp','') !~ '^[0-9]{1,12}$'
 THEN RETURN false; END IF;
 IF (c->>'exp')::bigint<=extract(epoch from statement_timestamp()) THEN RETURN false; END IF;
 v_session:=(c->>'session_id')::uuid;
 w:=split_part(p_name,'/',1)::uuid;
 RETURN EXISTS(
  SELECT 1 FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
  JOIN transcript_core.workspace_memberships m ON m.user_id=u.id
  JOIN storage.buckets b ON b.id=p_bucket
  WHERE u.id=v_uid AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
    AND (u.banned_until IS NULL OR u.banned_until<=statement_timestamp())
    AND s.id=v_session AND (s.not_after IS NULL OR s.not_after>statement_timestamp())
    AND m.workspace_id=w AND m.role IN ('owner','editor') AND b.public IS FALSE);
END $guard$;
REVOKE ALL ON FUNCTION transcript_core.manuscript_original_storage_authorized_self_v1(
 text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION transcript_core.manuscript_original_storage_authorized_self_v1(
 text,text) TO authenticated;

CREATE POLICY transcript_core_manuscript_original_insert_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (
  bucket_id IS DISTINCT FROM 'transcript-core-script-sources'
  OR split_part(name,'/',2) IS DISTINCT FROM 'manuscript'
  OR transcript_core.manuscript_original_storage_authorized_self_v1(bucket_id,name));
CREATE POLICY transcript_core_manuscript_original_read_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR SELECT TO authenticated USING (
  bucket_id IS DISTINCT FROM 'transcript-core-script-sources'
  OR split_part(name,'/',2) IS DISTINCT FROM 'manuscript'
  OR transcript_core.manuscript_original_storage_authorized_self_v1(bucket_id,name));
CREATE POLICY transcript_core_manuscript_original_update_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR UPDATE TO authenticated USING (
  bucket_id IS DISTINCT FROM 'transcript-core-script-sources'
  OR split_part(name,'/',2) IS DISTINCT FROM 'manuscript')
 WITH CHECK (
  bucket_id IS DISTINCT FROM 'transcript-core-script-sources'
  OR split_part(name,'/',2) IS DISTINCT FROM 'manuscript');
CREATE POLICY transcript_core_manuscript_original_delete_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR DELETE TO authenticated USING (
  bucket_id IS DISTINCT FROM 'transcript-core-script-sources'
  OR split_part(name,'/',2) IS DISTINCT FROM 'manuscript');
COMMIT;

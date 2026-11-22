-- HELD: exact signed producer staging scope, not a byte-verification or issuance operation.
BEGIN;
CREATE FUNCTION transcript_core.listening_render_storage_authorized_self_v1(p_bucket text,p_name text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog AS $fn$
DECLARE v_uid uuid; c jsonb; v_session uuid; w uuid; p uuid;
BEGIN
 IF p_bucket IS DISTINCT FROM 'transcript-core-generated-renders' OR p_name IS NULL OR
 p_name !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/listening/[a-f0-9]{64}\.(wav|mp3)$'
 THEN RETURN false; END IF;
 v_uid:=auth.uid(); c:=auth.jwt();
 IF v_uid IS NULL OR c->>'role' IS DISTINCT FROM 'authenticated' OR
 coalesce(c->>'is_anonymous','true')<>'false' OR
 coalesce(c->>'session_id','')!~'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' OR
 coalesce(c->>'exp','')!~'^[0-9]{1,12}$'
 THEN RETURN false; END IF;
 IF (c->>'exp')::bigint<=extract(epoch from statement_timestamp()) THEN RETURN false; END IF;
 v_session:=(c->>'session_id')::uuid;
 w:=split_part(p_name,'/',1)::uuid; p:=split_part(p_name,'/',2)::uuid;
 RETURN EXISTS(
 SELECT 1 FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
 JOIN transcript_core.workspace_memberships m ON m.user_id=u.id
 JOIN transcript_core.productions pr ON pr.workspace_id=m.workspace_id
 JOIN transcript_core.production_sources ps ON ps.production_id=pr.id
 JOIN transcript_core.manuscript_revisions mr ON mr.id=ps.manuscript_revision_id
 JOIN transcript_core.manuscript_documents md ON md.id=mr.manuscript_document_id
 JOIN transcript_core.assets a ON a.id=mr.source_asset_id
 WHERE u.id=v_uid AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
 AND (u.banned_until IS NULL OR u.banned_until<=statement_timestamp())
 AND s.id=v_session AND (s.not_after IS NULL OR s.not_after>statement_timestamp())
 AND m.workspace_id=w AND m.role IN ('owner','editor') AND pr.id=p AND pr.status<>'archived'
 AND ps.script_revision_id IS NULL AND md.workspace_id=w
 AND a.workspace_id=w AND a.provenance_class='manuscript_source' AND a.storage_bucket='transcript-core-script-sources'
 AND EXISTS(SELECT 1 FROM storage.buckets b WHERE b.id=p_bucket AND b.public IS FALSE)
 );
END $fn$;
REVOKE ALL ON FUNCTION transcript_core.listening_render_storage_authorized_self_v1(text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION transcript_core.listening_render_storage_authorized_self_v1(text,text) TO authenticated;
-- Only INSERT is newly permitted, and only the exact content-addressed
-- listening path. This admits untrusted staged bytes, never a canonical asset.
CREATE POLICY transcript_core_listening_render_insert_v1 ON storage.objects
 FOR INSERT TO authenticated WITH CHECK (
 transcript_core.listening_render_storage_authorized_self_v1(bucket_id,name));
-- The earlier workspace read policy includes viewers. Restrict the new
-- listening namespace to current signed production editors/owners.
CREATE POLICY transcript_core_listening_render_read_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR SELECT TO authenticated USING (
 bucket_id IS DISTINCT FROM 'transcript-core-generated-renders' OR
 split_part(name,'/',3) IS DISTINCT FROM 'listening' OR
 transcript_core.listening_render_storage_authorized_self_v1(bucket_id,name));
-- Never permit overwrite, move into/out of, or delete these staged originals
-- through authenticated storage policies, even if another permissive rule
-- is installed later. Privileged carrier operations remain a separate gate.
CREATE POLICY transcript_core_listening_render_update_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR UPDATE TO authenticated USING (
 bucket_id IS DISTINCT FROM 'transcript-core-generated-renders' OR split_part(name,'/',3) IS DISTINCT FROM 'listening')
 WITH CHECK (
 bucket_id IS DISTINCT FROM 'transcript-core-generated-renders' OR split_part(name,'/',3) IS DISTINCT FROM 'listening');
CREATE POLICY transcript_core_listening_render_delete_guard_v1 ON storage.objects
 AS RESTRICTIVE FOR DELETE TO authenticated USING (
 bucket_id IS DISTINCT FROM 'transcript-core-generated-renders' OR split_part(name,'/',3) IS DISTINCT FROM 'listening');
COMMIT;

-- Held extension to the released listening delivery binding. No live DDL.
-- A trusted, independently verified carrier must hash the exact incoming
-- bytes, validate native extraction, media/timeline/profile/export evidence,
-- and stage immutable private objects BEFORE invoking this internal operation.
-- SQL checks current custody, identity and lineage, not the bytes themselves.
BEGIN;

CREATE FUNCTION transcript_core.require_verified_listening_object_v1(
 p_workspace uuid,p_object uuid,p_version text,p_bucket text,p_mime text,p_size bigint
) RETURNS storage.objects
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog AS $object$
DECLARE v_object storage.objects%ROWTYPE;
BEGIN
 IF p_workspace IS NULL OR p_object IS NULL OR p_version IS NULL OR
 length(p_version) NOT BETWEEN 1 AND 200 OR p_size IS NULL OR p_size<1 OR
 p_bucket NOT IN ('transcript-core-script-sources','transcript-core-generated-renders')
 THEN RAISE EXCEPTION 'exact private object evidence required' USING ERRCODE='22023'; END IF;
 PERFORM 1 FROM storage.buckets WHERE id=p_bucket AND public IS FALSE FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'private source bucket required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_object FROM storage.objects o
 WHERE o.id=p_object AND o.version=p_version AND o.bucket_id=p_bucket
 AND o.archived_at IS NULL AND coalesce(o.is_delete_marker,false)=false
 AND public.transcript_core_path_workspace(o.name)=p_workspace
 AND o.metadata->>'size'=p_size::text AND o.metadata->>'mimetype'=p_mime
 FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'verified object version or metadata changed' USING ERRCODE='23514'; END IF;
 -- Do not resolve by title or path alone, nor assume an archived version is
 -- the current carrier object. Never mutate the storage schema.
 IF (SELECT count(*) FROM storage.objects o
 WHERE o.bucket_id=v_object.bucket_id AND o.name=v_object.name
 AND o.archived_at IS NULL AND coalesce(o.is_delete_marker,false)=false)<>1
 THEN RAISE EXCEPTION 'ambiguous current storage object' USING ERRCODE='23514'; END IF;
 RETURN v_object;
END $object$;

CREATE FUNCTION transcript_core.register_verified_listening_render_v1(
 p_workspace uuid,p_object storage.objects,p_sha256 text,p_mime text,p_size bigint
) RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog AS $asset$
DECLARE v_asset transcript_core.assets%ROWTYPE;
BEGIN
 IF p_sha256 IS NULL OR p_sha256!~'^[0-9a-f]{64}$' OR p_size IS NULL OR p_size<1
 OR p_mime NOT IN ('audio/wav','audio/mpeg') OR p_object.id IS NULL OR
 p_object.bucket_id IS DISTINCT FROM 'transcript-core-generated-renders'
 OR public.transcript_core_path_workspace(p_object.name) IS DISTINCT FROM p_workspace
 THEN RAISE EXCEPTION 'exact generated asset evidence required' USING ERRCODE='22023'; END IF;
 -- Existing native asset identity; no update or new registry.
 INSERT INTO transcript_core.assets(workspace_id,provenance_class,storage_bucket,storage_path,content_hash,mime_type,byte_size)
 VALUES(p_workspace,'generated_render',p_object.bucket_id,p_object.name,p_sha256,p_mime,p_size)
 ON CONFLICT(workspace_id,storage_bucket,storage_path) DO NOTHING;
 SELECT * INTO STRICT v_asset FROM transcript_core.assets
 WHERE workspace_id=p_workspace AND storage_bucket=p_object.bucket_id AND storage_path=p_object.name FOR SHARE;
 IF v_asset.provenance_class::text IS DISTINCT FROM 'generated_render' OR
 v_asset.content_hash IS DISTINCT FROM p_sha256 OR v_asset.mime_type IS DISTINCT FROM p_mime OR
 v_asset.byte_size IS DISTINCT FROM p_size
 THEN RAISE EXCEPTION 'existing asset conflicts with verified render' USING ERRCODE='23505'; END IF;
 RETURN v_asset.id;
END $asset$;

CREATE FUNCTION transcript_core.complete_verified_listening_production_v1(
 p_production_id uuid,p_manuscript_revision_id uuid,p_master_ordinal integer,
 p_delivery_profile_id uuid,p_profile_rule_version text,p_profile_configuration jsonb,
 p_timeline_manifest jsonb,p_evidence jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog AS $complete$
DECLARE
 v_uid uuid; v_claims jsonb; v_session uuid; v_expiry bigint; v_workspace uuid;
 v_original transcript_core.assets%ROWTYPE;
 v_original_object storage.objects%ROWTYPE; v_master_object storage.objects%ROWTYPE; v_mp3_object storage.objects%ROWTYPE;
 v_master_asset uuid; v_mp3_asset uuid; v_master transcript_core.production_masters%ROWTYPE;
 v_package transcript_core.delivery_packages%ROWTYPE; v_package_ids uuid[];
 v_report jsonb; v_binding jsonb; v_k text;
BEGIN
 IF p_production_id IS NULL OR p_manuscript_revision_id IS NULL OR p_master_ordinal IS NULL OR p_master_ordinal<1 OR
 p_delivery_profile_id IS NULL OR p_profile_rule_version IS NULL OR length(p_profile_rule_version) NOT BETWEEN 1 AND 200 OR
 jsonb_typeof(p_profile_configuration) IS DISTINCT FROM 'object' OR
 jsonb_typeof(p_timeline_manifest) IS DISTINCT FROM 'object' OR p_timeline_manifest='{}'::jsonb OR
 octet_length(p_timeline_manifest::text)>1048576 OR
 jsonb_typeof(p_evidence) IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'exact completion intent required' USING ERRCODE='22023'; END IF;
 IF NOT (p_evidence ?& ARRAY['original_object_id','original_object_version','original_sha256','original_byte_size',
 'extracted_sha256','intake_receipt_sha256','master_object_id','master_object_version','master_sha256','master_byte_size',
 'mp3_object_id','mp3_object_version','mp3_sha256','mp3_byte_size','export_receipt_sha256','export_id','publication_approved'])
 OR (SELECT count(*) FROM jsonb_object_keys(p_evidence))<>17 OR
 p_evidence->'publication_approved' IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION 'exact verified production evidence required' USING ERRCODE='22023'; END IF;
 FOREACH v_k IN ARRAY ARRAY['original_object_id','master_object_id','mp3_object_id'] LOOP
  IF jsonb_typeof(p_evidence->v_k) IS DISTINCT FROM 'string' OR
  p_evidence->>v_k !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  THEN RAISE EXCEPTION 'invalid object identity' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH v_k IN ARRAY ARRAY['original_object_version','master_object_version','mp3_object_version'] LOOP
  IF jsonb_typeof(p_evidence->v_k) IS DISTINCT FROM 'string' OR
  length(p_evidence->>v_k) NOT BETWEEN 1 AND 200 OR p_evidence->>v_k ~ '[[:cntrl:]]'
  THEN RAISE EXCEPTION 'invalid object version' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH v_k IN ARRAY ARRAY['original_sha256','extracted_sha256','intake_receipt_sha256','master_sha256','mp3_sha256','export_receipt_sha256','export_id'] LOOP
  IF jsonb_typeof(p_evidence->v_k) IS DISTINCT FROM 'string' OR p_evidence->>v_k !~ '^[0-9a-f]{64}$'
  THEN RAISE EXCEPTION 'invalid source digest' USING ERRCODE='22023'; END IF;
 END LOOP;
 FOREACH v_k IN ARRAY ARRAY['original_byte_size','master_byte_size','mp3_byte_size'] LOOP
  IF jsonb_typeof(p_evidence->v_k) IS DISTINCT FROM 'number' OR
  p_evidence->>v_k !~ '^[1-9][0-9]{0,9}$'
  THEN RAISE EXCEPTION 'invalid verified byte size' USING ERRCODE='22023'; END IF;
 END LOOP;
 IF (p_evidence->>'original_byte_size')::bigint>8388608 OR
 (p_evidence->>'master_byte_size')::bigint>2147483648 OR
 (p_evidence->>'mp3_byte_size')::bigint>536870912 OR
 p_evidence->>'master_object_id'=p_evidence->>'mp3_object_id' OR
 p_evidence->>'master_sha256'=p_evidence->>'mp3_sha256'
 THEN RAISE EXCEPTION 'distinct bounded render evidence required' USING ERRCODE='22023'; END IF;

 -- Native Transcript Core authority, not a Titus license or a browser actor.
 -- The carrier must validate the real JWT before establishing these claims.
 v_uid:=auth.uid(); v_claims:=auth.jwt();
 IF v_uid IS NULL OR v_claims->>'role' IS DISTINCT FROM 'authenticated' OR
 coalesce(v_claims->>'is_anonymous','true')<>'false' OR
 coalesce(v_claims->>'session_id','')!~'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' OR
 coalesce(v_claims->>'exp','')!~'^[0-9]{1,12}$'
 THEN RAISE EXCEPTION 'current signed production session required' USING ERRCODE='42501'; END IF;
 v_session:=(v_claims->>'session_id')::uuid; v_expiry:=(v_claims->>'exp')::bigint;
 IF v_expiry<=extract(epoch from clock_timestamp())
 THEN RAISE EXCEPTION 'current signed production session required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM auth.users u WHERE u.id=v_uid AND u.deleted_at IS NULL
 AND u.email_confirmed_at IS NOT NULL AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp()) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'current signed production session required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM auth.sessions s WHERE s.id=v_session AND s.user_id=v_uid
 AND (s.not_after IS NULL OR s.not_after>clock_timestamp()) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'current signed production session required' USING ERRCODE='42501'; END IF;

 SELECT p.workspace_id INTO v_workspace FROM transcript_core.productions p WHERE p.id=p_production_id;
 IF v_workspace IS NULL THEN RAISE EXCEPTION 'production unavailable' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM transcript_core.workspace_memberships m WHERE m.workspace_id=v_workspace AND m.user_id=v_uid
 AND m.role IN ('owner','editor') FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'production unavailable' USING ERRCODE='42501'; END IF;
 -- Serialize this native production completion; retain original identities.
 PERFORM 1 FROM transcript_core.productions p WHERE p.id=p_production_id AND p.workspace_id=v_workspace
 AND p.status<>'archived' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'production unavailable' USING ERRCODE='42501'; END IF;
 SELECT a.* INTO v_original
 FROM transcript_core.production_sources ps
 JOIN transcript_core.manuscript_revisions mr ON mr.id=ps.manuscript_revision_id
 JOIN transcript_core.manuscript_documents md ON md.id=mr.manuscript_document_id
 JOIN transcript_core.assets a ON a.id=mr.source_asset_id
 WHERE ps.production_id=p_production_id AND ps.script_revision_id IS NULL
 AND mr.id=p_manuscript_revision_id AND md.workspace_id=v_workspace
 AND a.workspace_id=v_workspace AND mr.content_hash=p_evidence->>'extracted_sha256'
 AND a.content_hash=p_evidence->>'original_sha256'
 AND a.byte_size=(p_evidence->>'original_byte_size')::bigint
 AND a.provenance_class='manuscript_source' AND a.storage_bucket='transcript-core-script-sources'
 FOR SHARE OF ps,mr,md,a;
 IF NOT FOUND THEN RAISE EXCEPTION 'exact native manuscript revision required' USING ERRCODE='23514'; END IF;
 PERFORM 1 FROM transcript_core.delivery_profiles p WHERE p.id=p_delivery_profile_id AND p.workspace_id=v_workspace
 AND p.rule_version=p_profile_rule_version AND p.configuration=p_profile_configuration FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'current delivery profile mismatch' USING ERRCODE='23514'; END IF;

 v_original_object:=transcript_core.require_verified_listening_object_v1(v_workspace,
 (p_evidence->>'original_object_id')::uuid,p_evidence->>'original_object_version',
 v_original.storage_bucket,v_original.mime_type,v_original.byte_size);
 IF v_original_object.name IS DISTINCT FROM v_original.storage_path
 THEN RAISE EXCEPTION 'native original carrier mismatch' USING ERRCODE='23514'; END IF;
 v_master_object:=transcript_core.require_verified_listening_object_v1(v_workspace,
 (p_evidence->>'master_object_id')::uuid,p_evidence->>'master_object_version',
 'transcript-core-generated-renders','audio/wav',(p_evidence->>'master_byte_size')::bigint);
 v_mp3_object:=transcript_core.require_verified_listening_object_v1(v_workspace,
 (p_evidence->>'mp3_object_id')::uuid,p_evidence->>'mp3_object_version',
 'transcript-core-generated-renders','audio/mpeg',(p_evidence->>'mp3_byte_size')::bigint);
 IF v_master_object.name=v_mp3_object.name
 THEN RAISE EXCEPTION 'distinct generated renders required' USING ERRCODE='23514'; END IF;

 v_master_asset:=transcript_core.register_verified_listening_render_v1(v_workspace,v_master_object,
 p_evidence->>'master_sha256','audio/wav',(p_evidence->>'master_byte_size')::bigint);
 v_mp3_asset:=transcript_core.register_verified_listening_render_v1(v_workspace,v_mp3_object,
 p_evidence->>'mp3_sha256','audio/mpeg',(p_evidence->>'mp3_byte_size')::bigint);
 INSERT INTO transcript_core.production_masters(production_id,ordinal,audio_asset_id,timeline_manifest)
 VALUES(p_production_id,p_master_ordinal,v_master_asset,p_timeline_manifest)
 ON CONFLICT(production_id,ordinal) DO NOTHING;
 SELECT * INTO STRICT v_master FROM transcript_core.production_masters
 WHERE production_id=p_production_id AND ordinal=p_master_ordinal FOR SHARE;
 IF v_master.audio_asset_id IS DISTINCT FROM v_master_asset OR v_master.timeline_manifest IS DISTINCT FROM p_timeline_manifest
 THEN RAISE EXCEPTION 'existing production master conflicts' USING ERRCODE='23505'; END IF;

 v_report:=jsonb_build_object('contractVersion','transcript_core_verified_listening_completion_v1',
 'manuscriptRevisionId',p_manuscript_revision_id,'deliveryProfileVersion',p_profile_rule_version,
 'deliveryProfileConfiguration',p_profile_configuration,'verifiedCarrierEvidence',p_evidence,
 'publication_approved',false);
 SELECT array_agg(dp.id) INTO v_package_ids FROM (
 SELECT p.id FROM transcript_core.delivery_packages p WHERE p.production_master_id=v_master.id
 AND p.delivery_profile_id=p_delivery_profile_id FOR UPDATE
 ) dp;
 IF coalesce(cardinality(v_package_ids),0)>1
 THEN RAISE EXCEPTION 'ambiguous existing delivery package' USING ERRCODE='23505'; END IF;
 IF coalesce(cardinality(v_package_ids),0)=0 THEN
  INSERT INTO transcript_core.delivery_packages(production_master_id,delivery_profile_id,status,validation_report)
  VALUES(v_master.id,p_delivery_profile_id,'exported',v_report) RETURNING * INTO v_package;
 ELSE
  SELECT * INTO STRICT v_package FROM transcript_core.delivery_packages WHERE id=v_package_ids[1];
  IF v_package.status<>'exported' OR v_package.validation_report IS DISTINCT FROM v_report
  THEN RAISE EXCEPTION 'existing delivery package conflicts' USING ERRCODE='23505'; END IF;
 END IF;
 v_binding:=transcript_core.bind_verified_listening_delivery_artifact_v1(v_package.id,v_mp3_asset,
 p_evidence->>'mp3_sha256',(p_evidence->>'mp3_byte_size')::bigint,
 p_evidence->>'master_sha256',p_evidence->>'export_receipt_sha256');
 -- Recheck elapsed session deadline; locks above fence source revocations.
 IF v_expiry<=extract(epoch from clock_timestamp()) OR NOT EXISTS(
 SELECT 1 FROM auth.sessions s WHERE s.id=v_session AND s.user_id=v_uid
 AND (s.not_after IS NULL OR s.not_after>clock_timestamp()))
 THEN RAISE EXCEPTION 'current signed production session required' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('contractVersion','transcript_core_verified_listening_completion_v1',
 'productionId',p_production_id,'manuscriptRevisionId',p_manuscript_revision_id,
 'productionMasterId',v_master.id,'binding',v_binding,'publication_approved',false);
END $complete$;

REVOKE ALL ON FUNCTION
 transcript_core.require_verified_listening_object_v1(uuid,uuid,text,text,text,bigint),
 transcript_core.register_verified_listening_render_v1(uuid,storage.objects,text,text,bigint),
 transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
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
    OR p_original_format IS NULL OR p_original_format NOT IN ('txt','docx')
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

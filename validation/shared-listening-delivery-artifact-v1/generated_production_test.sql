BEGIN;
CREATE FUNCTION pg_temp.u(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS
 $$ SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
INSERT INTO auth.users(id,email_confirmed_at) SELECT pg_temp.u(i),now() FROM generate_series(1,3)i;
INSERT INTO auth.sessions VALUES(pg_temp.u(11),pg_temp.u(1),now()+interval '1 hour'),
 (pg_temp.u(12),pg_temp.u(2),now()+interval '1 hour'),(pg_temp.u(13),pg_temp.u(3),now()+interval '1 hour');
INSERT INTO transcript_core.workspaces VALUES(pg_temp.u(21)),(pg_temp.u(22));
INSERT INTO transcript_core.workspace_memberships VALUES(pg_temp.u(21),pg_temp.u(1),'editor'),
 (pg_temp.u(21),pg_temp.u(2),'viewer'),(pg_temp.u(22),pg_temp.u(3),'owner');
INSERT INTO storage.buckets VALUES('transcript-core-script-sources',false),('transcript-core-generated-renders',false);
INSERT INTO storage.objects(id,bucket_id,name,version,metadata) VALUES
 (pg_temp.u(31),'transcript-core-script-sources',pg_temp.u(21)::text||'/original.txt','native-v1','{"size":20,"mimetype":"text/plain"}'),
 (pg_temp.u(32),'transcript-core-generated-renders',pg_temp.u(21)::text||'/master.wav','master-v1','{"size":100,"mimetype":"audio/wav"}'),
 (pg_temp.u(33),'transcript-core-generated-renders',pg_temp.u(21)::text||'/delivery.mp3','delivery-v1','{"size":50,"mimetype":"audio/mpeg"}'),
 (pg_temp.u(34),'transcript-core-generated-renders',pg_temp.u(22)::text||'/foreign.mp3','foreign-v1','{"size":50,"mimetype":"audio/mpeg"}');
INSERT INTO transcript_core.assets(id,workspace_id,provenance_class,storage_bucket,storage_path,content_hash,mime_type,byte_size)
 VALUES(pg_temp.u(41),pg_temp.u(21),'script_source','transcript-core-script-sources',pg_temp.u(21)::text||'/original.txt',repeat('a',64),'text/plain',20);
INSERT INTO transcript_core.manuscript_documents VALUES(pg_temp.u(51),pg_temp.u(21));
INSERT INTO transcript_core.manuscript_revisions VALUES(pg_temp.u(52),pg_temp.u(51),pg_temp.u(41),repeat('b',64));
INSERT INTO transcript_core.productions(id,workspace_id) VALUES(pg_temp.u(61),pg_temp.u(21));
INSERT INTO transcript_core.production_sources VALUES(pg_temp.u(61),pg_temp.u(52),NULL);
INSERT INTO transcript_core.delivery_profiles(id,workspace_id,rule_version,configuration)
 VALUES(pg_temp.u(71),pg_temp.u(21),'fixture-v1','{"format":"mp3"}'),
 (pg_temp.u(72),pg_temp.u(22),'fixture-v1','{"format":"mp3"}');
CREATE FUNCTION pg_temp.sign(n int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('test.listening_uid',pg_temp.u(n)::text,true);
 PERFORM set_config('test.listening_claims',jsonb_build_object('role','authenticated','is_anonymous',false,
 'session_id',pg_temp.u(n+10),'exp',floor(extract(epoch from now()+interval '1 hour'))::bigint)::text,true);
END $$;
CREATE FUNCTION pg_temp.evidence() RETURNS jsonb LANGUAGE sql AS $$
SELECT jsonb_build_object(
 'original_object_id',pg_temp.u(31),'original_object_version','native-v1','original_sha256',repeat('a',64),'original_byte_size',20,
 'extracted_sha256',repeat('b',64),'intake_receipt_sha256',repeat('c',64),
 'master_object_id',pg_temp.u(32),'master_object_version','master-v1','master_sha256',repeat('d',64),'master_byte_size',100,
 'mp3_object_id',pg_temp.u(33),'mp3_object_version','delivery-v1','mp3_sha256',repeat('e',64),'mp3_byte_size',50,
 'export_receipt_sha256',repeat('f',64),'export_id',repeat('1',64),'publication_approved',false) $$;
CREATE FUNCTION pg_temp.complete(patch jsonb DEFAULT '{}',revision uuid DEFAULT pg_temp.u(52),profile uuid DEFAULT pg_temp.u(71),
 timeline jsonb DEFAULT '{"fixture":"actual synthetic timeline"}',ordinal int DEFAULT 1)
 RETURNS jsonb LANGUAGE sql AS $$
 SELECT transcript_core.complete_verified_listening_production_v1(pg_temp.u(61),revision,ordinal,profile,
 'fixture-v1','{"format":"mp3"}',timeline,pg_temp.evidence()||patch) $$;
CREATE FUNCTION pg_temp.expect_denial(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; RAISE EXCEPTION 'unexpected success: %',statement;
 EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>expected THEN RAISE; END IF; END;
END $$;
SELECT pg_temp.sign(2);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete()','42501');
SELECT pg_temp.sign(3);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete()','42501');
SELECT pg_temp.sign(1);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete(revision=>pg_temp.u(53))','23514');
SELECT pg_temp.expect_denial('SELECT pg_temp.complete(profile=>pg_temp.u(72))','23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete('{"publication_approved":true}')$$,'22023');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete('{"actor_id":"not-allowed"}')$$,'22023');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete('{"mp3_object_version":"stale"}')$$,'23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete('{"master_byte_size":101}')$$,'23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(jsonb_build_object('mp3_object_id',pg_temp.u(34),'mp3_object_version','foreign-v1'))$$,'23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(jsonb_build_object('extracted_sha256',repeat('0',64)))$$,'23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(jsonb_build_object('original_sha256',repeat('0',64)))$$,'23514');
DO $$
BEGIN
 IF (SELECT count(*) FROM transcript_core.assets)<>1 OR EXISTS(SELECT FROM transcript_core.production_masters)
 OR EXISTS(SELECT FROM transcript_core.delivery_packages) THEN RAISE EXCEPTION 'negative admission left artifacts'; END IF;
END $$;
DO $$
DECLARE first jsonb; again jsonb;
BEGIN
 first:=pg_temp.complete(); again:=pg_temp.complete();
 IF first IS DISTINCT FROM again OR first->>'publication_approved' IS DISTINCT FROM 'false' OR
 first->'binding'->>'publication_approved' IS DISTINCT FROM 'false' OR
 first->'binding'->>'artifact_sha256' IS DISTINCT FROM repeat('e',64)
 THEN RAISE EXCEPTION 'completion replay or receipt mismatch'; END IF;
END $$;
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(jsonb_build_object('mp3_sha256',repeat('0',64)))$$,'23505');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(jsonb_build_object('intake_receipt_sha256',repeat('0',64)))$$,'23505');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete(timeline=>'{"fixture":"different"}')$$,'23505');
UPDATE storage.objects SET version='replaced' WHERE id=pg_temp.u(33);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete()','23514');
SELECT pg_temp.expect_denial($$SELECT pg_temp.complete('{"mp3_object_version":"replaced"}')$$,'23505');
UPDATE storage.objects SET version='delivery-v1' WHERE id=pg_temp.u(33);
UPDATE auth.sessions SET not_after=now()-interval '1 hour' WHERE id=pg_temp.u(11);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete()','42501');
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id=pg_temp.u(11);
UPDATE transcript_core.workspace_memberships SET role='viewer' WHERE user_id=pg_temp.u(1);
SELECT pg_temp.expect_denial('SELECT pg_temp.complete()','42501');
DO $$
DECLARE r text; f text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  FOREACH f IN ARRAY ARRAY[
  'transcript_core.require_verified_listening_object_v1(uuid,uuid,text,text,text,bigint)',
  'transcript_core.register_verified_listening_render_v1(uuid,storage.objects,text,text,bigint)',
  'transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)'] LOOP
   IF has_function_privilege(r,f,'EXECUTE') OR (SELECT prosecdef FROM pg_proc WHERE oid=f::regprocedure)
   THEN RAISE EXCEPTION 'unexpected completion authority'; END IF;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM transcript_core.assets)<>3 OR (SELECT count(*) FROM transcript_core.production_masters)<>1
 OR (SELECT count(*) FROM transcript_core.delivery_packages)<>1 OR (SELECT count(*) FROM transcript_core.delivery_package_artifacts)<>1
 OR (SELECT count(*) FROM storage.objects)<>4 OR (SELECT count(*) FROM transcript_core.manuscript_revisions)<>1
 THEN RAISE EXCEPTION 'original custody or retry count mismatch'; END IF;
END $$;
ROLLBACK;
SELECT 'PASS synthetic internal completion, replay, lineage, and denied-role checks' AS result;

-- Synthetic role/RLS proof. Does not establish Storage API/TUS or signed JWT proof.
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
INSERT INTO transcript_core.assets(id,workspace_id,provenance_class,storage_bucket,storage_path,content_hash,mime_type,byte_size)
 VALUES(pg_temp.u(41),pg_temp.u(21),'script_source','transcript-core-script-sources',pg_temp.u(21)::text||'/original.txt',repeat('a',64),'text/plain',20);
INSERT INTO transcript_core.manuscript_documents VALUES(pg_temp.u(51),pg_temp.u(21));
INSERT INTO transcript_core.manuscript_revisions VALUES(pg_temp.u(52),pg_temp.u(51),pg_temp.u(41),repeat('b',64));
INSERT INTO transcript_core.productions(id,workspace_id) VALUES(pg_temp.u(61),pg_temp.u(21)),(pg_temp.u(62),pg_temp.u(21));
INSERT INTO transcript_core.production_sources VALUES(pg_temp.u(61),pg_temp.u(52),NULL);
-- Mimic preexisting broad workspace SELECT permission on generated renders
-- and exercise restrictive update/delete against a permissive fixture rule.
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;
CREATE POLICY fixture_existing_read ON storage.objects FOR SELECT TO authenticated USING (true);
CREATE POLICY fixture_future_update ON storage.objects FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY fixture_future_delete ON storage.objects FOR DELETE TO authenticated USING (true);
CREATE FUNCTION pg_temp.sign(n int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('test.listening_uid',pg_temp.u(n)::text,true);
 PERFORM set_config('test.listening_claims',jsonb_build_object('role','authenticated','is_anonymous',false,
 'session_id',pg_temp.u(n+10),'exp',floor(extract(epoch from now()+interval '1 hour'))::bigint)::text,true);
END $$;
CREATE FUNCTION pg_temp.path(p int DEFAULT 61,w int DEFAULT 21) RETURNS text LANGUAGE sql AS
 $$ SELECT pg_temp.u(w)::text||'/'||pg_temp.u(p)::text||'/listening/'||repeat('a',64)||'.wav' $$;
CREATE FUNCTION pg_temp.try_insert(p int DEFAULT 61,w int DEFAULT 21,suffix text DEFAULT '') RETURNS void LANGUAGE sql AS $$
 INSERT INTO storage.objects(id,bucket_id,name,version) VALUES(gen_random_uuid(),'transcript-core-generated-renders',
 pg_temp.path(p,w)||suffix,'v1') $$;
CREATE FUNCTION pg_temp.deny(statement text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE statement; RAISE EXCEPTION 'unexpected storage success';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $$;
-- Test under actual RLS role; auth claims in this fixture are synthetic.
SELECT pg_temp.sign(1);
SET LOCAL ROLE authenticated;
SELECT pg_temp.try_insert();
SELECT pg_temp.deny('SELECT pg_temp.try_insert(62)');
SELECT pg_temp.deny('SELECT pg_temp.try_insert(61,22)');
SELECT pg_temp.deny($$SELECT pg_temp.try_insert(61,21,'/extra')$$);
DO $$ BEGIN
 IF (SELECT count(*) FROM storage.objects)<>1 THEN RAISE EXCEPTION 'editor read mismatch'; END IF;
 UPDATE storage.objects SET version='replace';
 IF FOUND THEN RAISE EXCEPTION 'overwrite allowed'; END IF;
 DELETE FROM storage.objects;
 IF FOUND THEN RAISE EXCEPTION 'delete allowed'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.sign(2);
SET LOCAL ROLE authenticated;
SELECT pg_temp.deny('SELECT pg_temp.try_insert()');
DO $$ BEGIN IF EXISTS(SELECT FROM storage.objects) THEN RAISE EXCEPTION 'viewer read allowed'; END IF; END $$;
RESET ROLE;
SELECT pg_temp.sign(3);
SET LOCAL ROLE authenticated;
SELECT pg_temp.deny('SELECT pg_temp.try_insert()');
DO $$ BEGIN IF EXISTS(SELECT FROM storage.objects) THEN RAISE EXCEPTION 'outsider read allowed'; END IF; END $$;
RESET ROLE;
SELECT pg_temp.sign(1);
UPDATE auth.sessions SET not_after=now()-interval '1 hour' WHERE id=pg_temp.u(11);
SET LOCAL ROLE authenticated;
SELECT pg_temp.deny('SELECT pg_temp.try_insert()');
DO $$ BEGIN IF EXISTS(SELECT FROM storage.objects) THEN RAISE EXCEPTION 'expired read allowed'; END IF; END $$;
RESET ROLE;
UPDATE auth.sessions SET not_after=now()+interval '1 hour' WHERE id=pg_temp.u(11);
UPDATE transcript_core.workspace_memberships SET role='viewer' WHERE user_id=pg_temp.u(1);
SET LOCAL ROLE authenticated;
SELECT pg_temp.deny('SELECT pg_temp.try_insert()');
DO $$ BEGIN IF EXISTS(SELECT FROM storage.objects) THEN RAISE EXCEPTION 'revoked read allowed'; END IF; END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS(SELECT FROM transcript_core.production_masters) OR EXISTS(SELECT FROM transcript_core.delivery_packages)
 OR (SELECT count(*) FROM transcript_core.assets)<>1 THEN RAISE EXCEPTION 'staging admitted production'; END IF;
 IF has_function_privilege('anon','transcript_core.listening_render_storage_authorized_self_v1(text,text)','EXECUTE')
 OR has_function_privilege('service_role','transcript_core.listening_render_storage_authorized_self_v1(text,text)','EXECUTE')
 OR has_function_privilege('authenticated','transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'unexpected execution authority'; END IF;
END $$;
ROLLBACK;
SELECT 'PASS synthetic scoped generated-render staging permissions; no admission' AS result;

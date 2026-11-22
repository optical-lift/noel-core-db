-- Isolated fictional source-only proof. GUC claims are NOT signed tokens.
BEGIN;
CREATE FUNCTION pg_temp.u(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS
 $$ SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
INSERT INTO auth.users(id,email_confirmed_at)
 SELECT pg_temp.u(i),now() FROM generate_series(1,3)i;
INSERT INTO auth.sessions VALUES
 (pg_temp.u(11),pg_temp.u(1),now()+interval '1 hour'),
 (pg_temp.u(12),pg_temp.u(2),now()+interval '1 hour'),
 (pg_temp.u(13),pg_temp.u(3),now()+interval '1 hour');
INSERT INTO transcript_core.workspaces VALUES(pg_temp.u(21)),(pg_temp.u(22));
INSERT INTO transcript_core.workspace_memberships VALUES
 (pg_temp.u(21),pg_temp.u(1),'owner'),
 (pg_temp.u(21),pg_temp.u(2),'viewer'),
 (pg_temp.u(22),pg_temp.u(3),'owner');
INSERT INTO storage.buckets VALUES
 ('transcript-core-script-sources',false),
 ('transcript-core-generated-renders',false);
CREATE FUNCTION pg_temp.sign(n int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('test.listening_uid',pg_temp.u(n)::text,true);
 PERFORM set_config('test.listening_claims',jsonb_build_object('role','authenticated','is_anonymous',false,
  'session_id',pg_temp.u(n+10),
  'exp',floor(extract(epoch from now()+interval '1 hour'))::bigint)::text,true);
END $$;
CREATE FUNCTION pg_temp.manuscript_path(w int DEFAULT 21,h text DEFAULT repeat('a',64))
 RETURNS text LANGUAGE sql AS
 $$ SELECT pg_temp.u(w)::text||'/manuscript/'||h||'.txt' $$;
INSERT INTO storage.objects(id,bucket_id,name,version,metadata) VALUES
 (pg_temp.u(31),'transcript-core-script-sources',pg_temp.manuscript_path(),'original-v1','{"size":20,"mimetype":"text/plain"}'),
 (pg_temp.u(32),'transcript-core-script-sources',pg_temp.manuscript_path(22,repeat('b',64)),'foreign-v1','{"size":20,"mimetype":"text/plain"}');
CREATE FUNCTION pg_temp.register(
  p_id uuid DEFAULT pg_temp.u(31),p_version text DEFAULT 'original-v1',
  p_hash text DEFAULT repeat('a',64),p_bytes bigint DEFAULT 20,
  p_format text DEFAULT 'txt', p_workspace uuid DEFAULT pg_temp.u(21))
RETURNS jsonb LANGUAGE sql AS $$
SELECT transcript_core.register_verified_manuscript_original_v1(
 p_workspace,p_id,p_version,p_hash,p_bytes,p_format) $$;
CREATE FUNCTION pg_temp.deny(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE statement; RAISE EXCEPTION 'unexpected registration success';
 EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>expected THEN RAISE; END IF; END;
END $$;
SELECT pg_temp.sign(2);
SELECT pg_temp.deny('select pg_temp.register()','42501');
SELECT pg_temp.sign(3);
SELECT pg_temp.deny('select pg_temp.register()','42501');
SELECT pg_temp.sign(1);
SELECT pg_temp.deny($$select pg_temp.register(p_version=>'stale')$$,'23514');
SELECT pg_temp.deny($$select pg_temp.register(p_hash=>repeat('b',64))$$,'23514');
SELECT pg_temp.deny($$select pg_temp.register(p_bytes=>21)$$,'23514');
SELECT pg_temp.deny($$select pg_temp.register(p_format=>'docx')$$,'23514');
SELECT pg_temp.deny($$select pg_temp.register(p_workspace=>pg_temp.u(22))$$,'42501');
SELECT pg_temp.deny($$select pg_temp.register(p_id=>pg_temp.u(32))$$,'23514');
SELECT pg_temp.deny($$select pg_temp.register(p_hash=>'bad')$$,'22023');
SELECT pg_temp.deny($$select pg_temp.register(p_format=>'other')$$,'22023');
DO $$
DECLARE first jsonb; retry jsonb; a transcript_core.assets%ROWTYPE;
BEGIN
 first:=pg_temp.register(); retry:=pg_temp.register();
 IF first IS DISTINCT FROM retry OR first->>'publication_approved' IS DISTINCT FROM 'false'
 OR first->>'sourceFormat' IS DISTINCT FROM 'txt'
 THEN RAISE EXCEPTION 'source registration replay or publication claim'; END IF;
 SELECT * INTO STRICT a FROM transcript_core.assets WHERE id=(first->>'assetId')::uuid;
 IF a.provenance_class IS DISTINCT FROM 'manuscript_source'
 OR a.storage_bucket IS DISTINCT FROM 'transcript-core-script-sources'
 OR a.storage_path IS DISTINCT FROM pg_temp.manuscript_path()
 OR a.content_hash IS DISTINCT FROM repeat('a',64) OR a.mime_type IS DISTINCT FROM 'text/plain'
 OR a.byte_size IS DISTINCT FROM 20
 THEN RAISE EXCEPTION 'source asset is not the exact authored manuscript original'; END IF;
 IF (SELECT count(*) FROM transcript_core.assets)<>1 
 THEN RAISE EXCEPTION 'registration created unrelated content'; END IF;
END $$;
-- Signed role/permission and Storage RLS fixture:
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO authenticated;
CREATE POLICY fixture_existing_source_read ON storage.objects
 FOR SELECT TO authenticated USING (true);
CREATE POLICY fixture_existing_source_insert ON storage.objects
 FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY fixture_future_source_update ON storage.objects
 FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY fixture_future_source_delete ON storage.objects
 FOR DELETE TO authenticated USING (true);
SELECT pg_temp.sign(1);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF (SELECT count(*) FROM storage.objects)<>2
 THEN RAISE EXCEPTION 'owner should read original and broad other-source fixture'; END IF;
 UPDATE storage.objects SET version='tampered' WHERE name=pg_temp.manuscript_path();
 IF FOUND THEN RAISE EXCEPTION 'manuscript original was overwritten'; END IF;
 DELETE FROM storage.objects WHERE name=pg_temp.manuscript_path();
 IF FOUND THEN RAISE EXCEPTION 'manuscript original was deleted'; END IF;
END $$;
-- Valid owner source insert into exact content address (no canonical registration).
INSERT INTO storage.objects(id,bucket_id,name,version,metadata)
 VALUES(pg_temp.u(33),'transcript-core-script-sources',
 pg_temp.manuscript_path(21,repeat('c',64)),'uploaded-v1','{"size":20,"mimetype":"text/plain"}');
RESET ROLE;
SELECT pg_temp.sign(2);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM storage.objects WHERE name=pg_temp.manuscript_path())
 THEN RAISE EXCEPTION 'viewer read private authored original'; END IF;
END $$;
SELECT pg_temp.deny($$INSERT INTO storage.objects(id,bucket_id,name) VALUES(
 pg_temp.u(34),'transcript-core-script-sources',pg_temp.manuscript_path(21,repeat('d',64)))$$,'42501');
RESET ROLE;
SELECT pg_temp.sign(1);
UPDATE auth.sessions SET not_after=now()-interval '1 hour' WHERE id=pg_temp.u(11);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM storage.objects WHERE name=pg_temp.manuscript_path())
 THEN RAISE EXCEPTION 'expired session read private authored original'; END IF;
END $$;
RESET ROLE;
DO $$
DECLARE r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
 IF has_function_privilege(r,'transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)','EXECUTE')
 THEN RAISE EXCEPTION 'untrusted source registration execute privilege: %',r; END IF;
 END LOOP;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)'::regprocedure)
 THEN RAISE EXCEPTION 'source registration gained security definer'; END IF;
 IF (SELECT count(*) FROM transcript_core.assets)<>1 OR
 (SELECT count(*) FROM transcript_core.manuscript_revisions)<>0
 THEN RAISE EXCEPTION 'unapproved canonical manuscript created'; END IF;
END $$;
ROLLBACK;
SELECT 'PASS isolated native manuscript registration, retries, signed-shaped claims, restrictive source storage guards' AS result;

-- Additional synthetic subset of the inspected live Transcript Core and
-- Storage/Auth metadata. Claims are test-only, not cryptographic sessions.
CREATE SCHEMA auth;
CREATE SCHEMA storage;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email_confirmed_at timestamptz,deleted_at timestamptz,banned_until timestamptz);
CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid REFERENCES auth.users(id),not_after timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
 $$ SELECT nullif(current_setting('test.listening_uid',true),'')::uuid $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
 $$ SELECT coalesce(nullif(current_setting('test.listening_claims',true),'')::jsonb,'{}'::jsonb) $$;
CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean NOT NULL);
CREATE TABLE storage.objects(id uuid PRIMARY KEY,bucket_id text REFERENCES storage.buckets(id),name text NOT NULL,
 version text,metadata jsonb,archived_at timestamptz,is_delete_marker boolean);
ALTER TABLE transcript_core.assets ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE transcript_core.assets ADD UNIQUE(workspace_id,storage_bucket,storage_path);
ALTER TABLE transcript_core.productions ADD COLUMN status text NOT NULL DEFAULT 'planning';
ALTER TABLE transcript_core.production_masters ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE transcript_core.production_masters ADD COLUMN ordinal integer NOT NULL DEFAULT 1 CHECK(ordinal>0);
ALTER TABLE transcript_core.production_masters ADD COLUMN timeline_manifest jsonb NOT NULL DEFAULT '{}';
ALTER TABLE transcript_core.production_masters ADD UNIQUE(production_id,ordinal);
ALTER TABLE transcript_core.delivery_profiles ADD COLUMN rule_version text NOT NULL DEFAULT 'fixture-v1';
ALTER TABLE transcript_core.delivery_profiles ADD COLUMN configuration jsonb NOT NULL DEFAULT '{}';
ALTER TABLE transcript_core.delivery_packages ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE transcript_core.delivery_packages ADD COLUMN validation_report jsonb NOT NULL DEFAULT '{}';
CREATE TABLE transcript_core.workspace_memberships(workspace_id uuid REFERENCES transcript_core.workspaces(id),
 user_id uuid REFERENCES auth.users(id),role text NOT NULL,PRIMARY KEY(workspace_id,user_id));
CREATE TABLE transcript_core.manuscript_documents(id uuid PRIMARY KEY,workspace_id uuid REFERENCES transcript_core.workspaces(id));
CREATE TABLE transcript_core.manuscript_revisions(id uuid PRIMARY KEY,manuscript_document_id uuid REFERENCES transcript_core.manuscript_documents(id),
 source_asset_id uuid REFERENCES transcript_core.assets(id),content_hash text NOT NULL);
CREATE TABLE transcript_core.production_sources(production_id uuid PRIMARY KEY REFERENCES transcript_core.productions(id),
 manuscript_revision_id uuid REFERENCES transcript_core.manuscript_revisions(id),script_revision_id uuid,
 CHECK((manuscript_revision_id IS NOT NULL)::int+(script_revision_id IS NOT NULL)::int=1));

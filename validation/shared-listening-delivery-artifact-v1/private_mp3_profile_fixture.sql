-- Fictional PostgreSQL-only Auth/source subset for the held profile RPC.
-- NEVER real user rows, secrets, signed-JWT evidence or a production migration.
-- Existing isolated listening fixture has transcript_core.workspaces(id)
-- and roles anon/authenticated/service_role. Reuse them rather than invent a
-- second registry or test runner.
CREATE SCHEMA auth;
CREATE TABLE auth.users (
  id uuid PRIMARY KEY,
  is_anonymous boolean NOT NULL DEFAULT false,
  email_confirmed_at timestamptz,
  banned_until timestamptz,
  deleted_at timestamptz
);
CREATE TABLE auth.sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  not_after timestamptz
);
-- These are NONCRYPTOGRAPHIC GUC mocks. Only the existing protected
-- GoTrue-signed clone can prove signature/independent identity.
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE
AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),
                  '{}')::jsonb;
$$;
CREATE TABLE transcript_core.workspace_memberships (
  workspace_id uuid NOT NULL REFERENCES transcript_core.workspaces(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  role text NOT NULL CHECK (role IN ('owner','editor','viewer')),
  PRIMARY KEY(workspace_id,user_id)
);
-- Test id values only, not customer source identity.
INSERT INTO auth.users (id,email_confirmed_at) VALUES
 ('00000000-0000-0000-0000-000000001101',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001102',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001103',clock_timestamp()),
 ('00000000-0000-0000-0000-000000001104',clock_timestamp());
INSERT INTO auth.sessions (id,user_id,not_after) VALUES
 ('00000000-0000-0000-0000-000000002101',
  '00000000-0000-0000-0000-000000001101',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002102',
  '00000000-0000-0000-0000-000000001102',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002103',
  '00000000-0000-0000-0000-000000001103',clock_timestamp()+interval '1 hour'),
 ('00000000-0000-0000-0000-000000002104',
  '00000000-0000-0000-0000-000000001104',clock_timestamp()+interval '1 hour');
INSERT INTO transcript_core.workspace_memberships(workspace_id,user_id,role) VALUES
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001101','owner'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001102','editor'),
 ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000001103','viewer'),
 ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000001101','owner');
-- The real delivery_profiles table has these canonical fields and uniqueness.
-- Extend the existing simplified listening fixture rather than shadowing it.
ALTER TABLE transcript_core.delivery_profiles
  ADD COLUMN profile_key text NOT NULL DEFAULT 'fixture-default',
  ADD COLUMN display_name text NOT NULL DEFAULT 'fixture-default',
  ADD COLUMN rule_version text NOT NULL DEFAULT 'fixture-v1',
  ADD COLUMN configuration jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE transcript_core.delivery_profiles
  ADD CONSTRAINT delivery_profiles_workspace_id_profile_key_rule_version_key
  UNIQUE (workspace_id,profile_key,rule_version);
-- No client write/read privileges on the real private table.
REVOKE ALL ON transcript_core.delivery_profiles FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE transcript_core.delivery_profiles ENABLE ROW LEVEL SECURITY;

-- SCRATCH ONLY; LIVE-METADATA-MATCHED RELEVANT AUTH SUBSET, 2026-11-04.
-- Live project PostgreSQL 17.6. All type/NOT NULL/function shapes here were
-- inspected via READ-ONLY information_schema and pg_get_functiondef. This is
-- NOT a production dump or a full production-schema clone. No live data,
-- client credentials, passwords, JWT signatures or user IDs are copied.
-- request.jwt.claims below is UNVERIFIED synthetic scratch state.
CREATE SCHEMA auth;
CREATE SCHEMA titus;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT USAGE ON SCHEMA public TO authenticated,anon;
GRANT USAGE ON SCHEMA auth TO authenticated,anon;
CREATE TABLE auth.users(
  instance_id uuid,
  id uuid PRIMARY KEY,
  aud varchar,
  role varchar,
  email varchar,
  email_confirmed_at timestamptz,
  phone text UNIQUE,
  phone_confirmed_at timestamptz,
  is_anonymous boolean NOT NULL DEFAULT false,
  is_sso_user boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  banned_until timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);
CREATE TABLE auth.oauth_clients(id uuid PRIMARY KEY);
CREATE TABLE auth.sessions(
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz,
  updated_at timestamptz,
  oauth_client_id uuid REFERENCES auth.oauth_clients(id) ON DELETE CASCADE,
  not_after timestamptz,
  scopes text CHECK(char_length(scopes)<=4096)
);
-- These use exactly the live Auth helpers' claim-resolution expressions.
-- Only the fixture sets the claims, not any production client/request.
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT coalesce(
   nullif(current_setting('request.jwt.claim.sub', true), ''),
   (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
 )::uuid
$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT coalesce(
   nullif(current_setting('request.jwt.claim', true), ''),
   nullif(current_setting('request.jwt.claims', true), '')
 )::jsonb
$$;
INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES
 ('00000000-0000-4000-8000-000000000101',now(),false),
 ('00000000-0000-4000-8000-000000000102',now(),false);
INSERT INTO auth.sessions(id,user_id) VALUES
 ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000101'),
 ('00000000-0000-4000-8000-000000000202','00000000-0000-4000-8000-000000000102');

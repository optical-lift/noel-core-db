-- DISPOSABLE SCRATCH-ONLY Postgres fixture. Never deploy to Supabase.
-- This uses UNVERIFIED GUC claims, not cryptographically verified GoTrue tokens.
CREATE SCHEMA auth;
CREATE SCHEMA titus;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
GRANT USAGE ON SCHEMA public TO authenticated,anon;
CREATE TABLE auth.users(
  id uuid PRIMARY KEY,
  deleted_at timestamptz,
  email_confirmed_at timestamptz,
  phone_confirmed_at timestamptz,
  is_anonymous boolean,
  banned_until timestamptz
);
CREATE TABLE auth.sessions(
  id uuid PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id),
  not_after timestamptz
);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT NULLIF(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'sub','')::uuid
$$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT coalesce(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
INSERT INTO auth.users(id,email_confirmed_at,is_anonymous) VALUES
 ('00000000-0000-4000-8000-000000000101',now(),false),
 ('00000000-0000-4000-8000-000000000102',now(),false);
INSERT INTO auth.sessions(id,user_id) VALUES
 ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000101'),
 ('00000000-0000-4000-8000-000000000202','00000000-0000-4000-8000-000000000102');

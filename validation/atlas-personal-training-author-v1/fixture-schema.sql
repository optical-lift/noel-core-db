-- Isolated synthetic Postgres 16 fixture. NOT for Supabase production.
DO $role$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
END $role$;
CREATE SCHEMA auth;
CREATE SCHEMA atlas;
CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text);
CREATE TABLE atlas.principals(id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES auth.users(id),
 status text NOT NULL DEFAULT 'active');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
 AS $fn$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $fn$;
CREATE FUNCTION atlas.current_principal_id_v1() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path=pg_catalog,atlas,auth AS $fn$
 SELECT p.id FROM atlas.principals p WHERE p.user_id=auth.uid() AND p.status='active' LIMIT 1;
$fn$;
CREATE FUNCTION atlas.personal_atlas_access_status_self_api_v1() RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,atlas,auth AS $fn$
 SELECT jsonb_build_object('eligible',coalesce(current_setting('test.personal_access',true),'eligible')='eligible',
  'hasPrincipal',atlas.current_principal_id_v1() IS NOT NULL);
$fn$;
INSERT INTO auth.users(id,email) VALUES
 ('00000000-0000-4000-8000-000000000101','author@test.invalid'),
 ('00000000-0000-4000-8000-000000000202','outsider@test.invalid');
INSERT INTO atlas.principals(id,user_id) VALUES
 ('00000000-0000-4000-8000-000000000111','00000000-0000-4000-8000-000000000101'),
 ('00000000-0000-4000-8000-000000000222','00000000-0000-4000-8000-000000000202');
GRANT USAGE ON SCHEMA auth,public TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;

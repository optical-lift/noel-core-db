-- Isolated Postgres 16 ONLY. Synthetic schema with precisely the note SQL's
-- external dependencies. This is not the full live Supabase schema, not
-- independently issued JWT authentication, and never production user data.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA atlas;
CREATE SCHEMA auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SET search_path TO '' AS $fn$
 SELECT nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),'')::uuid;
$fn$;
CREATE TABLE atlas.test_author_principals (
 auth_user_id uuid PRIMARY KEY,
 principal_id uuid NOT NULL UNIQUE,
 eligible boolean NOT NULL DEFAULT true
);
CREATE TABLE atlas.personal_training_programs (
 id uuid PRIMARY KEY,
 owner_principal_id uuid NOT NULL,
 draft_packet jsonb NOT NULL
);
CREATE TABLE atlas.personal_training_program_versions (
 id uuid PRIMARY KEY,
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id),
 approved_packet jsonb NOT NULL
);
-- A restricted test double for the released Personal Atlas principal guard:
-- test an authenticated user id, current entitlement and owner principal.
CREATE OR REPLACE FUNCTION atlas.personal_training_author_guard_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO '' AS $fn$
DECLARE v_principal uuid;
BEGIN
 IF auth.uid() IS NULL THEN
  RAISE EXCEPTION 'Sign-in required' USING ERRCODE='42501';
 END IF;
 SELECT principal_id INTO v_principal FROM atlas.test_author_principals
 WHERE auth_user_id=auth.uid() AND eligible;
 IF v_principal IS NULL THEN
  RAISE EXCEPTION 'Established Personal Atlas required' USING ERRCODE='42501';
 END IF;
 RETURN v_principal;
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_training_author_guard_v1() FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO atlas.test_author_principals(auth_user_id,principal_id,eligible) VALUES
 ('61000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000101',true),
 ('61000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000102',true),
 ('61000000-0000-4000-8000-000000000003','61000000-0000-4000-8000-000000000103',false);

INSERT INTO atlas.personal_training_programs(id,owner_principal_id,draft_packet)
VALUES
 ('61000000-0000-4000-8000-000000000201','61000000-0000-4000-8000-000000000101',
  '{"contract":"personal_program_author_source_v2"}'),
 ('61000000-0000-4000-8000-000000000202','61000000-0000-4000-8000-000000000102',
  '{"contract":"personal_program_author_source_v2"}');

INSERT INTO atlas.personal_training_program_versions(id,program_id,approved_packet)
VALUES
 ('61000000-0000-4000-8000-000000000301','61000000-0000-4000-8000-000000000201',
  '{"contract":"personal_program_author_source_v2","components":[
   {"key":"W1-A","kind":"action","instructions":"Read the first original passage carefully.",
    "sourceExcerpt":"Original first passage."},
   {"key":"W1-B","kind":"action","instructions":"Use original second passage responsibly.",
    "sourceExcerpt":"Original second passage."}]}'),
 ('61000000-0000-4000-8000-000000000302','61000000-0000-4000-8000-000000000202',
  '{"contract":"personal_program_author_source_v2","components":[
   {"key":"other","kind":"action","instructions":"Private other person text.",
    "sourceExcerpt":"Other source."}]}');

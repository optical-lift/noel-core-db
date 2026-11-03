-- Synthetic identity helpers exclusively in disposable PostgreSQL 16.
-- These DO NOT call GoTrue; they are intentionally unsafe for production.
-- Loaded after prior B2A/B2B miniature-schema fixture and source SQL.
BEGIN;
ALTER TABLE reality.entities
  ADD COLUMN entity_kind text NOT NULL DEFAULT 'person',
  ADD COLUMN identity_state text NOT NULL DEFAULT 'canonical';
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SET search_path=pg_catalog
AS $fake$
 SELECT nullif(current_setting('titus.disclosure_fixture_auth_uid',true),'')::uuid
$fake$;
CREATE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog
AS $fake$
 SELECT jsonb_build_object(
    'session_id',current_setting('titus.disclosure_fixture_session',true))
$fake$;
COMMIT;

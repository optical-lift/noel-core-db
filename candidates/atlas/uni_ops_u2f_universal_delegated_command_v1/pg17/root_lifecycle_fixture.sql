-- Fictional standalone PostgreSQL 17 U2F 06 shape.
-- \ir native_root_custody_fixture.sql uses only fabricated fixed UUIDs.
\ir native_root_custody_fixture.sql
CREATE SCHEMA auth;
-- PostgreSQL roles are cluster-global, even when each synthetic test uses
-- its own disposable DB. Preserve no-login roles without duplicate creation.
DO $fixture_roles$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
END
$fixture_roles$;
-- This is NOT real signed GoTrue; use only for synthetic SQL contract checks.
CREATE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE SET search_path TO ''
AS $fake$
  SELECT NULLIF(pg_catalog.current_setting('request.jwt.claim.sub',true),'')::uuid;
$fake$;
-- An invented auth.jwt() and sessions table for NEGATIVE shape checks.
-- These values do not come from signed GoTrue tokens or a real user.
CREATE FUNCTION auth.jwt()
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO ''
AS $fake_jwt$
  SELECT COALESCE(NULLIF(pg_catalog.current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
$fake_jwt$;
CREATE TABLE auth.sessions (
 id uuid PRIMARY KEY, user_id uuid NOT NULL, not_after timestamptz
);
INSERT INTO auth.sessions VALUES
 ('00000000-0000-4000-8000-000000000901','00000000-0000-4000-8000-000000001201',NULL),
 ('00000000-0000-4000-8000-000000000902','00000000-0000-4000-8000-000000001202',NULL);
ALTER TABLE atlas.principals ADD COLUMN user_id uuid;
UPDATE atlas.principals SET user_id = (
 '00000000-0000-4000-8000-' || pg_catalog.lpad(
  ((pg_catalog.right(person_id::text,12))::bigint + 1000)::text,12,'0')
)::uuid;
-- For each fake Principal: native Person N+200 -> JWT N+1200.
ALTER TABLE ledger.seat_responsibilities
 ADD COLUMN title text NOT NULL DEFAULT 'Held root candidate',
 ADD COLUMN scope jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN began_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
 ADD COLUMN ended_at timestamptz,
 ADD COLUMN updated_at timestamptz NOT NULL DEFAULT pg_catalog.now();
ALTER TABLE ledger.seat_responsibilities ALTER COLUMN id SET DEFAULT pg_catalog.gen_random_uuid();
CREATE UNIQUE INDEX native_root_one_record_per_seat_key
 ON ledger.seat_responsibilities(seat_id,responsibility_key);
CREATE TABLE ledger.actions (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id),
 action_kind text NOT NULL,
 performed_by_entity_id uuid,
 occurred_at timestamptz NOT NULL,
 payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
 idempotency_key text,
 created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
 UNIQUE (ledger_id,idempotency_key)
);

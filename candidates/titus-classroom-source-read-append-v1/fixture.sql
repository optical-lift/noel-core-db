-- STRICTLY DISPOSABLE PG17 test fixture; fake identity GUCs are NOT AUTH.
-- This fixture contains no real Person data, tokens or source grants.
-- Isolated RiverSong PostgreSQL17 only. No actual Supabase users or students.
CREATE SCHEMA auth;
CREATE SCHEMA atlas;
CREATE SCHEMA reality;
CREATE SCHEMA titus;
DO $roles$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated')
  THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon')
  THEN CREATE ROLE anon NOLOGIN; END IF;
END;$roles$;
CREATE TABLE reality.entities(
  id uuid PRIMARY KEY,
  entity_kind text NOT NULL,
  identity_state text NOT NULL
);
INSERT INTO reality.entities(id,entity_kind,identity_state) VALUES
 ('00000000-0000-4000-8000-000000000201','person','canonical'),
 ('00000000-0000-4000-8000-000000000202','person','canonical'),
 ('00000000-0000-4000-8000-000000000203','person','canonical'),
 ('00000000-0000-4000-8000-000000000204','person','canonical'),
 ('00000000-0000-4000-8000-000000000205','person','retired');


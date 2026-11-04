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


-- TEST-ONLY user/session stubs. Arbitrary GUCs are NOT signed identity.
-- Actual deployment must use the existing GoTrue current-session resolvers.
CREATE FUNCTION atlas.existing_person_claim_signed_actor_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path=pg_catalog
AS $stub$
DECLARE v uuid;
BEGIN
  BEGIN v:=NULLIF(current_setting('titus.test_user',true),'')::uuid;
  EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  RETURN v;
END;$stub$;
CREATE FUNCTION titus.current_authenticated_person_entity_id_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path=pg_catalog
AS $stub$
DECLARE v uuid;
BEGIN
  BEGIN v:=NULLIF(current_setting('titus.test_person',true),'')::uuid;
  EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  RETURN v;
END;$stub$;

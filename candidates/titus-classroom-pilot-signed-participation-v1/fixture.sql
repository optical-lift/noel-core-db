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

-- Minimal private thread shape from the unreleased Titus event candidate.
CREATE TABLE titus.classroom_threads_v1(
  thread_id uuid PRIMARY KEY,
  source_kind text NOT NULL,
  course_ref text NOT NULL,
  unit_ref text NOT NULL
);
INSERT INTO titus.classroom_threads_v1 VALUES
 ('00000000-0000-4000-8000-000000000100','fixture','song','song-01'),
 ('00000000-0000-4000-8000-000000000101','fixture','song','song-02'),
 ('00000000-0000-4000-8000-000000000102','approved_edition','formation','unit-11');

-- THESE ARE DANGEROUS TEST STUBS, never part of candidate.sql / release.
-- A PostgreSQL GUC in a test CANNOT prove a current GoTrue user.
CREATE FUNCTION atlas.existing_person_claim_signed_actor_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE id uuid;
BEGIN
  BEGIN id:=nullif(current_setting('titus.test_user',true),'')::uuid;
  EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  RETURN id;
END;$$;
CREATE FUNCTION titus.current_authenticated_person_entity_id_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE id uuid;
BEGIN
  BEGIN id:=nullif(current_setting('titus.test_person',true),'')::uuid;
  EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
  RETURN id;
END;$$;

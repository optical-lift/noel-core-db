-- DISPOSABLE FIXTURE ONLY, executed AFTER B2A miniature fixture.sql.
-- These facts are invented solely for proving set/match logic, not issued
-- consent, legitimate teaching release, real Person or signed session.
BEGIN;
ALTER TABLE titus.formation_units
  ADD COLUMN review_state text NOT NULL DEFAULT 'current',
  ADD COLUMN formation_state text NOT NULL DEFAULT 'learner_ready';
CREATE TABLE titus.curriculum_versions (
  curriculum_version_id uuid PRIMARY KEY,
  program_id uuid NOT NULL REFERENCES titus.programs(program_id),
  version_status text NOT NULL
);
INSERT INTO titus.curriculum_versions
  (curriculum_version_id,program_id,version_status) VALUES
 ('00000000-0000-4000-8000-000000000602','00000000-0000-4000-8000-000000000201','frozen'),
 ('00000000-0000-4000-8000-000000000603','00000000-0000-4000-8000-000000000202','frozen'),
 ('00000000-0000-4000-8000-000000000604','00000000-0000-4000-8000-000000000201','draft');

-- This local stub is not GoTrue/PostgREST and cannot prove authentication.
-- It is installed only in a fresh, disposable Postgres test container.
CREATE OR REPLACE FUNCTION titus.current_authenticated_person_entity_id_v1()
RETURNS uuid
LANGUAGE sql STABLE
SET search_path=pg_catalog
AS $$
 SELECT nullif(current_setting('titus.b2b_fixture_current_person',true),'')::uuid;
$$;
COMMIT;

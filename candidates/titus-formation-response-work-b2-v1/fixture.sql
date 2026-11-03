-- Disposable Postgres 16 miniature schema for Build B2 structural tests.
-- NOT production-shaped and NOT a source of actual Person, rights or curriculum.
-- No production user data or credentials.
BEGIN;
CREATE SCHEMA reality;
CREATE SCHEMA titus;
DO $roles$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END;
$roles$;
CREATE TABLE reality.entities(id uuid PRIMARY KEY);
CREATE TABLE titus.programs(program_id uuid PRIMARY KEY);
CREATE TABLE titus.formation_units (
  formation_unit_id uuid PRIMARY KEY, program_id uuid NOT NULL REFERENCES titus.programs,
  teacher_id uuid NOT NULL
);
CREATE TABLE titus.formation_responses (
  formation_response_id uuid PRIMARY KEY,
  formation_unit_id uuid NOT NULL REFERENCES titus.formation_units,
  teacher_id uuid NOT NULL,
  formation_question_id uuid NULL,
  raw_text text NOT NULL,
  response_status text NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE titus.teacher_person_bindings (
  teacher_id uuid NOT NULL,
  person_entity_id uuid NOT NULL REFERENCES reality.entities,
  binding_state text NOT NULL,
  retired_at timestamptz NULL
);
INSERT INTO reality.entities(id) VALUES
 ('00000000-0000-4000-8000-000000000101'),
 ('00000000-0000-4000-8000-000000000102'),
 ('00000000-0000-4000-8000-000000000103'),
 ('00000000-0000-4000-8000-000000000104');
INSERT INTO titus.programs VALUES
 ('00000000-0000-4000-8000-000000000201'),
 ('00000000-0000-4000-8000-000000000202');
INSERT INTO titus.formation_units VALUES
 ('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000401'),
 ('00000000-0000-4000-8000-000000000302','00000000-0000-4000-8000-000000000202','00000000-0000-4000-8000-000000000402');
INSERT INTO titus.teacher_person_bindings(teacher_id,person_entity_id,binding_state) VALUES
 ('00000000-0000-4000-8000-000000000401','00000000-0000-4000-8000-000000000101','active'),
 ('00000000-0000-4000-8000-000000000402','00000000-0000-4000-8000-000000000104','active');
INSERT INTO titus.formation_responses
  (formation_response_id,formation_unit_id,teacher_id,raw_text) VALUES
 ('00000000-0000-4000-8000-000000000501','00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000401','Original learner text stays in the existing original record'),
 ('00000000-0000-4000-8000-000000000502','00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000401','Learner revision is another original response record'),
 ('00000000-0000-4000-8000-000000000503','00000000-0000-4000-8000-000000000302','00000000-0000-4000-8000-000000000402','Other unit response must be refused'),
 ('00000000-0000-4000-8000-000000000504','00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000402','Wrong historical source teacher');
COMMIT;

-- U1.12 FICTIONAL ONLY; used in network-disconnected PG17 test.
-- This is not Noel/Titus production source or a migration.
CREATE SCHEMA titus;
CREATE TABLE titus.course (
  id uuid PRIMARY KEY,
  title text NOT NULL,
  manuscript text NOT NULL,
  recorded_at timestamptz NOT NULL
);
CREATE TABLE titus.unit (
  id uuid PRIMARY KEY,
  course_id uuid NOT NULL REFERENCES titus.course(id) ON DELETE RESTRICT,
  kind text NOT NULL CHECK (kind IN ('lesson','assignment')),
  display_position integer NOT NULL,
  title text NOT NULL
);
CREATE TABLE titus.unit_revision (
  id uuid PRIMARY KEY,
  unit_id uuid NOT NULL REFERENCES titus.unit(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL UNIQUE,
  revision_number integer NOT NULL,
  body_text text NOT NULL,
  recorded_at timestamptz NOT NULL,
  UNIQUE (unit_id,revision_number)
);
INSERT INTO titus.course(id,title,manuscript,recorded_at) VALUES (
  'f1120000-0000-4000-8000-000000000001',
  'Fictional Source University',
  E'Original manuscript\r\nSecond line with 🌾',
  '2022-04-05T12:34:56.123456+00'
);
INSERT INTO titus.unit(id,course_id,kind,display_position,title) VALUES
 ('f1120000-0000-4000-8000-000000000002',
  'f1120000-0000-4000-8000-000000000001','lesson',1,'Fictional Class'),
 ('f1120000-0000-4000-8000-000000000003',
  'f1120000-0000-4000-8000-000000000001','assignment',2,'Fictional Homework');
INSERT INTO titus.unit_revision(id,unit_id,request_id,revision_number,body_text,recorded_at) VALUES
 ('f1120000-0000-4000-8000-000000000004',
  'f1120000-0000-4000-8000-000000000002',
  'f1120000-0000-4000-8000-000000000010',1,
  E'First lesson line\r\nSecond lesson line',
  '2022-04-05T12:34:56.123456+00'),
 ('f1120000-0000-4000-8000-000000000005',
  'f1120000-0000-4000-8000-000000000002',
  'f1120000-0000-4000-8000-000000000011',2,
  E'First lesson line\r\nSecond lesson line, revised 🌾',
  '2022-04-06T12:34:56.123456+00'),
 ('f1120000-0000-4000-8000-000000000006',
  'f1120000-0000-4000-8000-000000000003',
  'f1120000-0000-4000-8000-000000000012',1,
  E'Homework prompt. Do not assign Work.',
  '2022-04-07T12:34:56.123456+00');

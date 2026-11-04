-- RiverSong-only fake Atlas Teaching entities and root authorization.
-- Identity GUCs and fake source records are NOT genuine GoTrue/Atlas evidence.
-- Run after the preexisting fixture and before the new source candidate.
CREATE TABLE atlas.principals(
 id uuid PRIMARY KEY,person_id uuid NOT NULL,
 status text NOT NULL
);
CREATE TABLE atlas.principal_ledger_authorities(
 principal_id uuid NOT NULL,ledger_id uuid NOT NULL,
 authority_kind text NOT NULL,status text NOT NULL,
 PRIMARY KEY(principal_id,ledger_id)
);
CREATE TABLE atlas.teaching_courses(
 id uuid PRIMARY KEY,ledger_id uuid NOT NULL,
 capability_activation_id uuid NOT NULL,status text NOT NULL
);
CREATE TABLE atlas.teaching_course_offerings(
 id uuid PRIMARY KEY,ledger_id uuid NOT NULL,
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id),
 state text NOT NULL
);
CREATE TABLE atlas.teaching_enrollments(
 id uuid PRIMARY KEY,ledger_id uuid NOT NULL,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id),
 person_id uuid NOT NULL,state text NOT NULL,
 withdrawn_at timestamptz
);
INSERT INTO atlas.principals VALUES
 ('00000000-0000-4000-8000-000000000630',
  '00000000-0000-4000-8000-000000000204','active');
INSERT INTO atlas.principal_ledger_authorities VALUES
 ('00000000-0000-4000-8000-000000000630',
  '00000000-0000-4000-8000-000000000600','root_governing','active');
INSERT INTO atlas.teaching_courses VALUES
 ('00000000-0000-4000-8000-000000000620',
  '00000000-0000-4000-8000-000000000600',
  '00000000-0000-4000-8000-000000000621','active');
INSERT INTO atlas.teaching_course_offerings VALUES
 ('00000000-0000-4000-8000-000000000610',
  '00000000-0000-4000-8000-000000000600',
  '00000000-0000-4000-8000-000000000620','open');
INSERT INTO atlas.teaching_enrollments VALUES
 ('00000000-0000-4000-8000-000000000611',
  '00000000-0000-4000-8000-000000000600',
  '00000000-0000-4000-8000-000000000610',
  '00000000-0000-4000-8000-000000000201','active',NULL);

-- The real Atlas versions of these funcs, not GUCs, own production proof.
CREATE FUNCTION atlas.current_principal_id_v1()
RETURNS uuid LANGUAGE sql STABLE SET search_path=pg_catalog,atlas
AS $$
 SELECT p.id FROM atlas.principals p
 WHERE p.person_id=NULLIF(current_setting('titus.test_person',true),'')::uuid
 AND p.status='active' LIMIT 1
$$;
CREATE FUNCTION atlas.principal_has_ledger_authority_v1(
 p_principal_id uuid,p_ledger_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog,atlas
AS $$
 SELECT EXISTS(SELECT 1 FROM atlas.principal_ledger_authorities a
 WHERE a.principal_id=p_principal_id AND a.ledger_id=p_ledger_id
 AND a.authority_kind='root_governing' AND a.status='active')
$$;
CREATE FUNCTION atlas.teaching_activation_active_v1(
 p_ledger_id uuid,p_capability_activation_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT true$$;

-- NOTE: lesson-part rows are separately seeded after the unified bundle.

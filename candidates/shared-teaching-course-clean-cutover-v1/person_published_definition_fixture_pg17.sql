-- Synthetic PG17 copy of current live IMMUTABLE Version table shape.
-- Only fictional identities/rows; no production database export.
CREATE TABLE atlas.teaching_course_versions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 version_no integer NOT NULL CHECK(version_no>0),
 title text NOT NULL CHECK(btrim(title)<>''),
 summary text,
 learning_outcomes text[] NOT NULL DEFAULT '{}'::text[],
 published_by_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 published_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 published_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(course_id,id),UNIQUE(course_id,version_no)
);
ALTER TABLE atlas.teaching_course_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_versions FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_teaching_course_version_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $immutable_version$
BEGIN
 RAISE EXCEPTION 'Published Teaching Course Versions are immutable.'
  USING ERRCODE='55000';
END $immutable_version$;
CREATE TRIGGER teaching_course_versions_immutable_v1
 BEFORE DELETE OR UPDATE ON atlas.teaching_course_versions
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_teaching_course_version_mutation_v1();

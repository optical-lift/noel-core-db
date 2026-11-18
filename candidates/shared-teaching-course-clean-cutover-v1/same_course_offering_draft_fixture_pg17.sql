-- Fictional PG17 old institution-first Offering table to prove that
-- the SAME native Person-root Course can be referenced after exact-FK repair.
CREATE TABLE atlas.teaching_course_offerings(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL,
 course_id uuid NOT NULL,
 course_version_id uuid NOT NULL,
 state text NOT NULL DEFAULT 'draft'
  CHECK(state IN ('draft','open','closed','retired')),
 delivery_mode text NOT NULL
  CHECK(delivery_mode IN ('self_paced','cohort','scheduled','live_hybrid')),
 starts_at timestamptz,
 ends_at timestamptz,
 created_by_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 opened_at timestamptz,
 closed_at timestamptz,
 retired_at timestamptz,
 CONSTRAINT teaching_course_offerings_ledger_id_course_id_fkey
  FOREIGN KEY(ledger_id,course_id) REFERENCES atlas.teaching_courses(ledger_id,id) ON DELETE RESTRICT,
 CONSTRAINT teaching_course_offerings_course_id_course_version_id_fkey
  FOREIGN KEY(course_id,course_version_id)
   REFERENCES atlas.teaching_course_versions(course_id,id) ON DELETE RESTRICT,
 CHECK(ends_at IS NULL OR starts_at IS NULL OR ends_at>=starts_at),
 CHECK((state='draft' AND opened_at IS NULL AND closed_at IS NULL AND retired_at IS NULL)
 OR (state='open' AND opened_at IS NOT NULL AND closed_at IS NULL AND retired_at IS NULL)
 OR (state='closed' AND opened_at IS NOT NULL AND closed_at IS NOT NULL AND retired_at IS NULL)
 OR (state='retired' AND retired_at IS NOT NULL))
);
ALTER TABLE atlas.teaching_course_offerings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_offerings FROM PUBLIC,anon,authenticated;

-- Retain the existing independent legacy Offering identity/state guard.
CREATE FUNCTION atlas.guard_teaching_course_offering_update_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $legacy_offering_guard$
BEGIN
 IF OLD.ledger_id IS DISTINCT FROM NEW.ledger_id
 OR OLD.course_id IS DISTINCT FROM NEW.course_id
 OR OLD.course_version_id IS DISTINCT FROM NEW.course_version_id
 OR OLD.created_by_person_id IS DISTINCT FROM NEW.created_by_person_id
 OR OLD.created_by_principal_id IS DISTINCT FROM NEW.created_by_principal_id
 OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
  RAISE EXCEPTION 'Existing Offering identity immutability violated' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END $legacy_offering_guard$;
CREATE TRIGGER teaching_course_offerings_update_guard_v1
 BEFORE UPDATE ON atlas.teaching_course_offerings
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_teaching_course_offering_update_v1();

-- HELD M3.13: disposable production-shaped enough enrollment carrier
-- to prove privilege-elevated legacy writers cannot admit into shared Course.
-- All rows fictional; transaction rolls back.
CREATE TABLE atlas.teaching_enrollments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 ledger_id uuid NOT NULL,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 state text NOT NULL DEFAULT 'active'
  CHECK(state IN ('active','withdrawn')),
 enrolled_by_person_id uuid REFERENCES atlas.people(id) ON DELETE RESTRICT,
 enrolled_by_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 enrolled_at timestamptz NOT NULL DEFAULT now(),
 withdrawn_at timestamptz,
 withdrawal_reason text,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE atlas.teaching_enrollments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_enrollments FROM PUBLIC,anon,authenticated;

-- These fictional SECURITY DEFINER sources deliberately model old
-- privileged UPDATE/INSERT paths, no source-issued authorization.
-- They are NOT new client operations, nor proof of production equivalence.
CREATE FUNCTION atlas.fictional_legacy_open_self_api_v1(p_offering_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $old_open$
BEGIN
 UPDATE atlas.teaching_course_offerings
 SET state='open',opened_at=clock_timestamp()
 WHERE id=p_offering_id AND state='draft';
END $old_open$;
CREATE FUNCTION atlas.fictional_legacy_enroll_self_api_v1(
 p_offering_id uuid,p_person_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $old_enroll$
DECLARE v_ledger uuid;
BEGIN
 SELECT o.ledger_id INTO v_ledger FROM atlas.teaching_course_offerings o
 WHERE o.id=p_offering_id AND o.state='open';
 IF v_ledger IS NULL THEN RAISE EXCEPTION 'no open Offering'; END IF;
 INSERT INTO atlas.teaching_enrollments(
 ledger_id,offering_id,person_id,state)
 VALUES(v_ledger,p_offering_id,p_person_id,'active');
END $old_enroll$;

-- SHARED SOURCE CANDIDATE ONLY, never run on live Supabase.
-- Learner-private notes for already existing Atlas Teaching Enrollment and exact
-- published Course Version. This is NOT a Titus customer draft Course notebook,
-- an Atlas Work, a shared classroom event, or instructor-visible feedback.
-- Source owner: Noel shared_ lane; signature/release review remains REQUIRED.
BEGIN;

CREATE TABLE titus.learner_private_course_note_events_v1 (
  event_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  enrollment_id uuid NOT NULL REFERENCES atlas.teaching_enrollments(id) ON DELETE RESTRICT,
  learner_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
  course_version_id uuid NOT NULL REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  body_text text NOT NULL CHECK (
    body_text=pg_catalog.btrim(body_text) AND
    pg_catalog.char_length(body_text) BETWEEN 1 AND 3000
  ),
  recorded_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  CONSTRAINT learner_private_note_idempotency_v1 UNIQUE(enrollment_id,request_id)
);
CREATE INDEX learner_private_note_events_order_v1
 ON titus.learner_private_course_note_events_v1(enrollment_id,recorded_at DESC,event_id DESC);

ALTER TABLE titus.learner_private_course_note_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.learner_private_course_note_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE titus.learner_private_course_note_events_v1
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION titus.reject_learner_private_note_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $block$
BEGIN
 RAISE EXCEPTION 'Learner private note originals are immutable'
   USING ERRCODE='55000';
END;
$block$;
CREATE TRIGGER learner_private_notes_immutable_v1
 BEFORE UPDATE OR DELETE ON titus.learner_private_course_note_events_v1
 FOR EACH ROW EXECUTE FUNCTION titus.reject_learner_private_note_mutation_v1();
REVOKE ALL ON FUNCTION titus.reject_learner_private_note_mutation_v1()
 FROM PUBLIC,anon,authenticated,service_role;

-- Every call resolves a live signed Titus-client Auth session to a canonical
-- Reality Person AND matches that exact active Atlas Person credential.
-- Neither matching Auth User ID nor an arbitrary Enrollment UUID alone is authority.
CREATE FUNCTION titus.learner_private_note_authority_self_v1(p_enrollment_id uuid)
RETURNS TABLE(learner_person_id uuid,course_version_id uuid)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $guard$
DECLARE
 v_auth uuid:=auth.uid();
 v_reality_person uuid;
BEGIN
 IF v_auth IS NULL OR p_enrollment_id IS NULL
    OR coalesce(auth.jwt()->>'client_id','') <>
       'd0b999e7-a2e2-4bb8-91ea-482fcd44b257'
 THEN RAISE EXCEPTION 'Learner private notebook unavailable'
    USING ERRCODE='42501'; END IF;

 -- The existing resolver checks auth.sessions and current auth.users and
 -- resolves a canonical active reality.auth_person_bindings source.
 IF NOT EXISTS(
    SELECT 1 FROM auth.users u WHERE u.id=v_auth
      AND u.deleted_at IS NULL
      AND NOT coalesce(u.is_anonymous,false)
      AND (u.email_confirmed_at IS NOT NULL OR u.phone_confirmed_at IS NOT NULL)
      AND (u.banned_until IS NULL OR u.banned_until<=now())
 ) THEN RAISE EXCEPTION 'Learner private notebook unavailable'
    USING ERRCODE='42501'; END IF;

 v_reality_person:=titus.current_authenticated_person_entity_id_v1();
 IF v_reality_person IS NULL OR (
   SELECT count(DISTINCT b.person_entity_id)
   FROM reality.auth_person_bindings b
   JOIN reality.entities entity
     ON entity.id=b.person_entity_id
    AND entity.entity_kind='person' AND entity.identity_state='canonical'
   WHERE b.auth_user_id=v_auth AND b.binding_state='active'
     AND b.retired_at IS NULL
 ) <> 1
 THEN RAISE EXCEPTION 'Learner private notebook unavailable'
    USING ERRCODE='42501'; END IF;

 RETURN QUERY SELECT e.person_id,o.course_version_id
 FROM atlas.person_auth_credentials credential
 JOIN atlas.people person ON person.id=credential.person_id
     AND person.status='active'
 JOIN atlas.teaching_enrollments e ON e.person_id=person.id
 JOIN atlas.teaching_course_offerings o
     ON o.id=e.offering_id AND o.ledger_id=e.ledger_id
 JOIN atlas.teaching_courses c
     ON c.id=o.course_id AND c.ledger_id=o.ledger_id
 JOIN atlas.teaching_course_versions v
     ON v.id=o.course_version_id AND v.course_id=c.id
 WHERE credential.auth_user_id=v_auth
   AND credential.person_id=v_reality_person
   AND credential.credential_kind='supabase_auth_user'
   AND credential.status='active' AND credential.retired_at IS NULL
   AND e.id=p_enrollment_id AND e.state='active' AND e.withdrawn_at IS NULL
   AND o.state='open' AND o.opened_at IS NOT NULL
   AND o.closed_at IS NULL AND o.retired_at IS NULL
   AND c.status='active' AND c.retired_at IS NULL
   AND v.published_at IS NOT NULL
   AND atlas.teaching_activation_active_v1(c.ledger_id,c.capability_activation_id);
 IF NOT FOUND THEN RAISE EXCEPTION 'Learner private notebook unavailable'
    USING ERRCODE='42501'; END IF;
END;
$guard$;
REVOKE ALL ON FUNCTION titus.learner_private_note_authority_self_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- One private original. No classroom/teacher rights, learner profile creation,
-- Course enrollment creation, Note revisions, or automatic submission.
CREATE FUNCTION public.titus_learner_private_note_create_self_api_v1(
 p_enrollment_id uuid,p_request_id uuid,p_body_text text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $create$
DECLARE
 v_person uuid;v_version uuid;
 v_existing titus.learner_private_course_note_events_v1%ROWTYPE;
 v_created titus.learner_private_course_note_events_v1%ROWTYPE;
BEGIN
 IF p_request_id IS NULL OR p_body_text IS NULL
    OR pg_catalog.char_length(pg_catalog.btrim(p_body_text)) NOT BETWEEN 1 AND 3000
 THEN RAISE EXCEPTION 'Valid private note original required'
     USING ERRCODE='22023'; END IF;

 SELECT g.learner_person_id,g.course_version_id INTO v_person,v_version
 FROM titus.learner_private_note_authority_self_v1(p_enrollment_id) g;
 -- Serialize learner note creation/replay against Enrollment withdrawal.
 PERFORM 1 FROM atlas.teaching_enrollments e
  WHERE e.id=p_enrollment_id AND e.person_id=v_person FOR UPDATE;
 SELECT g.learner_person_id,g.course_version_id INTO v_person,v_version
 FROM titus.learner_private_note_authority_self_v1(p_enrollment_id) g;

 SELECT * INTO v_existing FROM titus.learner_private_course_note_events_v1 n
 WHERE n.enrollment_id=p_enrollment_id AND n.request_id=p_request_id;
 IF v_existing.event_id IS NOT NULL THEN
  IF v_existing.learner_person_id IS DISTINCT FROM v_person
     OR v_existing.course_version_id IS DISTINCT FROM v_version
     OR v_existing.body_text IS DISTINCT FROM pg_catalog.btrim(p_body_text)
  THEN RAISE EXCEPTION 'Private note request conflicts with original'
    USING ERRCODE='23505'; END IF;
  RETURN pg_catalog.jsonb_build_object(
    'contractVersion','titus_learner_private_note_v1','state','ready',
    'noteId',v_existing.event_id,'replay',true);
 END IF;
 IF (SELECT count(*) FROM titus.learner_private_course_note_events_v1 n
     WHERE n.enrollment_id=p_enrollment_id)>=100 THEN
  RAISE EXCEPTION 'Private notebook note limit reached'
    USING ERRCODE='22023'; END IF;

 INSERT INTO titus.learner_private_course_note_events_v1
 (enrollment_id,learner_person_id,course_version_id,request_id,body_text)
 VALUES (p_enrollment_id,v_person,v_version,p_request_id,pg_catalog.btrim(p_body_text))
 RETURNING * INTO v_created;
 RETURN pg_catalog.jsonb_build_object(
    'contractVersion','titus_learner_private_note_v1','state','ready',
    'noteId',v_created.event_id,'replay',false);
END;
$create$;
REVOKE ALL ON FUNCTION public.titus_learner_private_note_create_self_api_v1(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.titus_learner_private_note_create_self_api_v1(uuid,uuid,text)
 TO authenticated;

-- Only the exact current enrolled learner can read the originals.
-- Withdrawal/offering close/person/session revocation all deny current access.
-- Neither teacher nor author of the Course receives an independent reader.
CREATE FUNCTION public.titus_learner_private_notes_read_self_api_v1(p_enrollment_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog
AS $read$
DECLARE
 v_person uuid;v_version uuid;v_notes jsonb;
BEGIN
 SELECT g.learner_person_id,g.course_version_id INTO v_person,v_version
 FROM titus.learner_private_note_authority_self_v1(p_enrollment_id) g;
 SELECT coalesce(pg_catalog.jsonb_agg(
  pg_catalog.jsonb_build_object(
   'noteId',n.event_id,'body',n.body_text,'recordedAt',n.recorded_at)
   ORDER BY n.recorded_at,n.event_id),'[]'::jsonb) INTO v_notes
 FROM titus.learner_private_course_note_events_v1 n
 WHERE n.enrollment_id=p_enrollment_id AND n.learner_person_id=v_person
   AND n.course_version_id=v_version;
 RETURN pg_catalog.jsonb_build_object(
   'contractVersion','titus_learner_private_notes_v1',
   'state','ready','enrollmentId',p_enrollment_id,
   'courseVersionId',v_version,'notes',v_notes);
END;
$read$;
REVOKE ALL ON FUNCTION public.titus_learner_private_notes_read_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.titus_learner_private_notes_read_self_api_v1(uuid)
 TO authenticated;

-- Never grant direct private-table access or public roster/source discovery.
-- No Course is seeded, no Enrollment is issued, and no customer draft is published.
COMMIT;

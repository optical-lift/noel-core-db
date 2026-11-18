-- HELD M3.10: author-gated immutable Version use, institutional DRAFT Offering.
-- Same Person-origin Course root; never new Course ID or curriculum disclosure.
-- Requires M3.5–M3.9; clone-only, not a released migration.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('public.shared_teaching_course_operating_title_read_self_api_v1(uuid)') IS NULL
 OR to_regprocedure('public.shared_teaching_course_definition_publish_self_api_v1(uuid,uuid,text,text,text[])') IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)') IS NULL
 OR to_regclass('atlas.teaching_course_offerings') IS NULL THEN
  RAISE EXCEPTION 'protected canonical Course/Offering prerequisites missing'
    USING ERRCODE='42501';
 END IF;
END $gate$;

-- Old Offering carrier is tied to institution-first Course(ledger_id,id),
-- impossible for a Person-root Course with NULL Course.ledger_id. Preserve
-- same-ID Course+Version composite FK while separating *operating* Ledger FK.
ALTER TABLE atlas.teaching_course_offerings
 DROP CONSTRAINT IF EXISTS teaching_course_offerings_ledger_id_course_id_fkey RESTRICT,
 ADD CONSTRAINT shared_course_offering_native_ledger_fkey
  FOREIGN KEY(ledger_id) REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 ADD CONSTRAINT shared_course_offering_course_root_fkey
  FOREIGN KEY(course_id) REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 ALTER COLUMN created_by_person_id DROP NOT NULL,
 ALTER COLUMN created_by_principal_id DROP NOT NULL,
 ADD COLUMN created_by_person_entity_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
 ADD COLUMN operating_proposal_id uuid REFERENCES atlas.teaching_course_operating_standings(id) ON DELETE RESTRICT,
 ADD COLUMN creation_request_id uuid,
 ADD CONSTRAINT shared_course_offering_request_unique UNIQUE(operating_proposal_id,creation_request_id),
 ADD CONSTRAINT shared_course_offering_creator_coherence CHECK(
  (created_by_person_id IS NOT NULL AND created_by_principal_id IS NOT NULL)
  OR created_by_person_entity_id IS NOT NULL
 );

ALTER TABLE atlas.teaching_course_offerings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_offerings FROM PUBLIC,anon,authenticated;

-- A second immutable source guard protects the new exact relation columns.
-- Old Offering state guard remains unchanged. New canonical Offerings are
-- locked to draft until a later independently authorized open transition.
CREATE FUNCTION atlas.guard_shared_course_offering_identity_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $immut$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.operating_proposal_id IS NOT NULL THEN
   RAISE EXCEPTION 'shared Course Offering identity cannot be deleted'
    USING ERRCODE='55000';
  END IF;
  RETURN OLD;
 END IF;
 IF OLD.operating_proposal_id IS NOT NULL THEN
  IF NEW.ledger_id IS DISTINCT FROM OLD.ledger_id
  OR NEW.course_id IS DISTINCT FROM OLD.course_id
  OR NEW.course_version_id IS DISTINCT FROM OLD.course_version_id
  OR NEW.operating_proposal_id IS DISTINCT FROM OLD.operating_proposal_id
  OR NEW.creation_request_id IS DISTINCT FROM OLD.creation_request_id
  OR NEW.created_by_person_entity_id IS DISTINCT FROM OLD.created_by_person_entity_id
   OR NEW.state IS DISTINCT FROM 'draft'
  OR NEW.delivery_mode IS DISTINCT FROM OLD.delivery_mode
  OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
  OR NEW.ends_at IS DISTINCT FROM OLD.ends_at THEN
   RAISE EXCEPTION 'shared Course draft Offering identity/state is immutable'
    USING ERRCODE='55000';
  END IF;
 END IF;
 RETURN NEW;
END $immut$;

CREATE TRIGGER shared_course_offerings_exact_identity_v1
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_offerings
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_shared_course_offering_identity_v1();

ALTER TABLE atlas.teaching_course_operating_standings
 ADD CONSTRAINT shared_course_standing_id_course_pair UNIQUE(id,course_id);

-- Author decision on EXACT proposal+Version: no implicit authorization
-- from title disclosure, published Version, standing or Ledger governance.
CREATE TABLE atlas.teaching_course_version_use_decision_events (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 proposal_id uuid NOT NULL,
 course_id uuid NOT NULL,
 course_version_id uuid NOT NULL,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('allow_draft_offering','withhold_draft_offering')),
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(proposal_id,course_id)
  REFERENCES atlas.teaching_course_operating_standings(id,course_id) ON DELETE RESTRICT,
 FOREIGN KEY(course_id,course_version_id)
  REFERENCES atlas.teaching_course_versions(course_id,id) ON DELETE RESTRICT,
 UNIQUE(proposal_id,course_version_id,request_id)
);
CREATE INDEX shared_version_use_latest_decision
 ON atlas.teaching_course_version_use_decision_events(proposal_id,course_version_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_version_use_decision_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_version_use_decision_events FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.teaching_course_version_use_decision_events_event_seq_seq
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_course_version_use_decide_self_api_v1(
 p_proposal_id uuid,p_course_version_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $author_use$
DECLARE
 s atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_previous atlas.teaching_course_version_use_decision_events%ROWTYPE;
 v_seq bigint;
BEGIN
 IF p_proposal_id IS NULL OR p_course_version_id IS NULL OR p_request_id IS NULL
 OR p_decision NOT IN ('allow_draft_offering','withhold_draft_offering') THEN
  RAISE EXCEPTION 'exact Course Version use decision required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO s FROM atlas.teaching_course_operating_standings
  WHERE id=p_proposal_id FOR UPDATE;
 IF s.id IS NULL THEN
  RAISE EXCEPTION 'Course Version use decision unavailable' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(s.course_id,p_decision='allow_draft_offering');
 v_person:=atlas.current_person_for_private_course_v1();
 IF NOT EXISTS (SELECT 1 FROM atlas.teaching_course_versions v
   WHERE v.id=p_course_version_id AND v.course_id=s.course_id
    AND v.published_by_person_entity_id=v_person
    AND v.publication_scope='definition_metadata_only') THEN
  RAISE EXCEPTION 'own original immutable Course Version required' USING ERRCODE='42501';
 END IF;
 IF p_decision='allow_draft_offering' AND
 (s.proposal_state<>'proposed' OR s.operator_acceptance_state<>'accepted'
  OR (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
      WHERE d.proposal_id=s.id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_title') THEN
  RAISE EXCEPTION 'active accepted relationship and independent author title release required'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_previous FROM atlas.teaching_course_version_use_decision_events d
 WHERE d.proposal_id=s.id AND d.course_version_id=p_course_version_id
   AND d.request_id=p_request_id;
 IF v_previous.event_seq IS NOT NULL THEN
  IF v_previous.decision IS DISTINCT FROM p_decision
   OR v_previous.decided_by_person_entity_id IS DISTINCT FROM v_person THEN
   RAISE EXCEPTION 'changed immutable Course Version use request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_version_use_decision_v1',
   'proposalId',s.id,'courseVersionId',p_course_version_id,
   'decision',p_decision,'eventSequence',v_previous.event_seq,
   'alreadyExists',true,'canOpenOffering',false);
 END IF;
 INSERT INTO atlas.teaching_course_version_use_decision_events(
  proposal_id,course_id,course_version_id,request_id,decision,decided_by_person_entity_id)
 VALUES(s.id,s.course_id,p_course_version_id,p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_seq;
 RETURN jsonb_build_object(
   'contractVersion','shared_course_version_use_decision_v1',
   'proposalId',s.id,'courseVersionId',p_course_version_id,
   'decision',p_decision,'eventSequence',v_seq,
   'alreadyExists',false,'canOpenOffering',false);
END $author_use$;

CREATE FUNCTION public.shared_teaching_course_offering_draft_create_self_api_v1(
 p_proposal_id uuid,p_course_version_id uuid,p_request_id uuid,
 p_delivery_mode text,p_starts_at timestamptz,p_ends_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog
AS $draft$
DECLARE
 s atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_version atlas.teaching_course_versions%ROWTYPE;
 v_existing atlas.teaching_course_offerings%ROWTYPE;
 v_new atlas.teaching_course_offerings%ROWTYPE;
 v_mode text:=btrim(coalesce(p_delivery_mode,''));
BEGIN
 IF p_proposal_id IS NULL OR p_course_version_id IS NULL OR p_request_id IS NULL
 OR v_mode NOT IN ('self_paced','cohort','scheduled','live_hybrid')
 OR (p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at<p_starts_at) THEN
  RAISE EXCEPTION 'valid exact Version/Offering request required' USING ERRCODE='22023';
 END IF;
 SELECT * INTO s FROM atlas.teaching_course_operating_standings
 WHERE id=p_proposal_id FOR UPDATE;
 IF s.id IS NULL OR s.proposal_state<>'proposed'
 OR s.operator_acceptance_state<>'accepted'
 OR s.teaching_activation_id IS NULL
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_courses c
   WHERE c.id=s.course_id AND c.status='active' AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'current author-approved institutional Course required'
   USING ERRCODE='42501';
 END IF;
 v_person:=atlas.require_shared_course_native_ledger_governor_self_v1(s.ledger_id);
 IF NOT atlas.capability_entitlement_grant_live_v1(s.ledger_id,'teaching',1)
 OR NOT atlas.teaching_activation_active_v1(s.ledger_id,s.teaching_activation_id) THEN
  RAISE EXCEPTION 'current exact-Ledger Teaching authority required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_version FROM atlas.teaching_course_versions v
 WHERE v.id=p_course_version_id AND v.course_id=s.course_id
  AND v.publication_scope='definition_metadata_only'
  AND v.published_by_person_entity_id=(
   SELECT created_by_person_entity_id FROM atlas.teaching_courses WHERE id=s.course_id);
 IF v_version.id IS NULL THEN
  RAISE EXCEPTION 'original Person-published Version required' USING ERRCODE='42501';
 END IF;
 IF (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
      WHERE d.proposal_id=s.id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_title'
 OR (SELECT d.decision FROM atlas.teaching_course_version_use_decision_events d
      WHERE d.proposal_id=s.id AND d.course_version_id=v_version.id
      ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_draft_offering' THEN
  RAISE EXCEPTION 'separate current author title and exact Version-use permission required'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_existing FROM atlas.teaching_course_offerings o
 WHERE o.operating_proposal_id=s.id AND o.creation_request_id=p_request_id;
 IF v_existing.id IS NOT NULL THEN
  IF v_existing.course_version_id IS DISTINCT FROM v_version.id
  OR v_existing.course_id IS DISTINCT FROM s.course_id
  OR v_existing.ledger_id IS DISTINCT FROM s.ledger_id
  OR v_existing.created_by_person_entity_id IS DISTINCT FROM v_person
  OR v_existing.delivery_mode IS DISTINCT FROM v_mode
  OR v_existing.starts_at IS DISTINCT FROM p_starts_at
  OR v_existing.ends_at IS DISTINCT FROM p_ends_at THEN
   RAISE EXCEPTION 'changed immutable Offering draft request' USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_offering_draft_v1',
   'courseId',s.course_id,'courseVersionId',v_version.id,
   'ledgerId',s.ledger_id,'offeringId',v_existing.id,
   'offeringState','draft','alreadyExists',true,'canOpen',false);
 END IF;

 INSERT INTO atlas.teaching_course_offerings(
  ledger_id,course_id,course_version_id,state,delivery_mode,starts_at,ends_at,
  created_by_person_entity_id,operating_proposal_id,creation_request_id
 ) VALUES(
  s.ledger_id,s.course_id,v_version.id,'draft',v_mode,p_starts_at,p_ends_at,
  v_person,s.id,p_request_id
 ) RETURNING * INTO v_new;
 RETURN jsonb_build_object(
   'contractVersion','shared_course_offering_draft_v1',
   'courseId',s.course_id,'courseVersionId',v_version.id,
   'ledgerId',s.ledger_id,'offeringId',v_new.id,
   'offeringState','draft','alreadyExists',false,'canOpen',false);
END $draft$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_version_use_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_version_use_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)
 TO authenticated;

-- NO open / close, no enrollment, no class contents, no student roster,
-- no Course or Version mutation and no direct source table privileges.

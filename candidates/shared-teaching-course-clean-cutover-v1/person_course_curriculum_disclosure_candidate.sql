-- HELD M3.12: explicit, revocable AUTHOR permission to release ONE SEALED
-- immutable curriculum Version to ONE accepted institutional Ledger.
-- No implicit release from title, Version publication, Version draft-use,
-- a root governing seat, a draft Offering or generic Teaching activation.
-- No student, instructor or public curriculum disclosure. Clone-only.
DO $clone_source$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)') IS NULL
 OR to_regclass('atlas.teaching_course_version_curriculum_snapshots') IS NULL
 OR to_regclass('atlas.teaching_course_version_use_decision_events') IS NULL
 OR to_regclass('atlas.teaching_course_operating_title_disclosure_events') IS NULL THEN
  RAISE EXCEPTION 'author-sealed Version, accepted governor and source grant required'
    USING ERRCODE='42501';
 END IF;
END $clone_source$;

CREATE TABLE atlas.teaching_course_curriculum_disclosure_decisions (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 proposal_id uuid NOT NULL,
 course_id uuid NOT NULL,
 course_version_id uuid NOT NULL,
 request_id uuid NOT NULL,
 decision text NOT NULL
  CHECK(decision IN ('allow_sealed_curriculum','withhold_sealed_curriculum')),
 decided_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(proposal_id,course_id)
  REFERENCES atlas.teaching_course_operating_standings(id,course_id)
  ON DELETE RESTRICT,
 FOREIGN KEY(course_id,course_version_id)
  REFERENCES atlas.teaching_course_versions(course_id,id)
  ON DELETE RESTRICT,
 UNIQUE(proposal_id,course_version_id,request_id)
);
CREATE INDEX shared_curriculum_current_decision_v1
 ON atlas.teaching_course_curriculum_disclosure_decisions
 (proposal_id,course_version_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_curriculum_disclosure_decisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_curriculum_disclosure_decisions
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.teaching_course_curriculum_disclosure_decisions_event_seq_seq
 FROM PUBLIC,anon,authenticated;

-- A standalone author decision; NEVER conflates title permission or
-- author Version use for draft Offering with sealed-text disclosure.
CREATE FUNCTION public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(
 p_proposal_id uuid,p_course_version_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $author_decides$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_person uuid;
 v_prior atlas.teaching_course_curriculum_disclosure_decisions%ROWTYPE;
 v_event bigint;
BEGIN
 IF p_proposal_id IS NULL OR p_course_version_id IS NULL
 OR p_request_id IS NULL OR p_decision IS NULL
 OR p_decision NOT IN ('allow_sealed_curriculum','withhold_sealed_curriculum') THEN
  RAISE EXCEPTION 'exact author curriculum release request required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_standing
 FROM atlas.teaching_course_operating_standings
 WHERE id=p_proposal_id FOR UPDATE;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'author Course relation required' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(
  v_standing.course_id,p_decision='allow_sealed_curriculum');
 v_person:=atlas.current_person_for_private_course_v1();
 IF NOT EXISTS(
   SELECT 1 FROM atlas.teaching_course_version_curriculum_snapshots s
   JOIN atlas.teaching_course_versions v
     ON v.course_id=s.course_id AND v.id=s.course_version_id
   WHERE s.course_id=v_standing.course_id AND s.course_version_id=p_course_version_id
   AND s.sealed_by_person_entity_id=v_person
   AND v.published_by_person_entity_id=v_person
 ) THEN
  RAISE EXCEPTION 'own sealed immutable Version required' USING ERRCODE='42501';
 END IF;

 IF p_decision='allow_sealed_curriculum' AND (
  v_standing.proposal_state<>'proposed' OR
  v_standing.operator_acceptance_state<>'accepted' OR
  (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
   WHERE d.proposal_id=v_standing.id ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_title' OR
  (SELECT d.decision FROM atlas.teaching_course_version_use_decision_events d
   WHERE d.proposal_id=v_standing.id AND d.course_version_id=p_course_version_id
   ORDER BY d.event_seq DESC LIMIT 1)
      IS DISTINCT FROM 'allow_draft_offering'
 ) THEN
  RAISE EXCEPTION 'independent current title and Version-use authorization required'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior
 FROM atlas.teaching_course_curriculum_disclosure_decisions d
 WHERE d.proposal_id=v_standing.id AND d.course_version_id=p_course_version_id
   AND d.request_id=p_request_id;
 IF v_prior.event_seq IS NOT NULL THEN
  IF v_prior.decided_by_person_entity_id IS DISTINCT FROM v_person
     OR v_prior.decision IS DISTINCT FROM p_decision THEN
   RAISE EXCEPTION 'changed curriculum disclosure request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_curriculum_disclosure_decision_v1',
   'proposalId',v_standing.id,'courseVersionId',p_course_version_id,
   'decision',p_decision,'eventSequence',v_prior.event_seq,
   'alreadyExists',true,'canEnroll',false,'canOpenOffering',false);
 END IF;
 INSERT INTO atlas.teaching_course_curriculum_disclosure_decisions(
  proposal_id,course_id,course_version_id,request_id,decision,
  decided_by_person_entity_id)
 VALUES(v_standing.id,v_standing.course_id,p_course_version_id,
  p_request_id,p_decision,v_person)
 RETURNING event_seq INTO v_event;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_curriculum_disclosure_decision_v1',
  'proposalId',v_standing.id,'courseVersionId',p_course_version_id,
  'decision',p_decision,'eventSequence',v_event,
  'alreadyExists',false,'canEnroll',false,'canOpenOffering',false);
END $author_decides$;

CREATE FUNCTION public.shared_teaching_course_curriculum_governor_read_self_api_v1(
 p_proposal_id uuid,p_course_version_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $governor_reads$
DECLARE
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_snapshot atlas.teaching_course_version_curriculum_snapshots%ROWTYPE;
BEGIN
 IF p_proposal_id IS NULL OR p_course_version_id IS NULL THEN
  RAISE EXCEPTION 'sealed Course curriculum unavailable' USING ERRCODE='42501';
 END IF;
 -- A concurrent author withdrawal, title/Version/curriculum withhold,
 -- or new grant all acquire this same proposal lock before committing.
 SELECT * INTO v_standing FROM atlas.teaching_course_operating_standings
 WHERE id=p_proposal_id FOR SHARE;
 IF v_standing.id IS NULL OR v_standing.proposal_state<>'proposed'
 OR v_standing.operator_acceptance_state<>'accepted'
 OR v_standing.teaching_activation_id IS NULL
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_courses c
   WHERE c.id=v_standing.course_id AND c.status='active'
     AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'sealed Course curriculum unavailable' USING ERRCODE='42501';
 END IF;
 PERFORM atlas.require_shared_course_native_ledger_governor_self_v1(
  v_standing.ledger_id);
 IF NOT atlas.capability_entitlement_grant_live_v1(
   v_standing.ledger_id,'teaching',1)
 OR NOT atlas.teaching_activation_active_v1(
   v_standing.ledger_id,v_standing.teaching_activation_id) THEN
  RAISE EXCEPTION 'sealed Course curriculum unavailable' USING ERRCODE='42501';
 END IF;
 IF (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
    WHERE d.proposal_id=v_standing.id ORDER BY d.event_seq DESC LIMIT 1)
    IS DISTINCT FROM 'allow_title'
 OR (SELECT d.decision FROM atlas.teaching_course_version_use_decision_events d
    WHERE d.proposal_id=v_standing.id
      AND d.course_version_id=p_course_version_id
    ORDER BY d.event_seq DESC LIMIT 1) IS DISTINCT FROM 'allow_draft_offering'
 OR (SELECT d.decision FROM atlas.teaching_course_curriculum_disclosure_decisions d
    WHERE d.proposal_id=v_standing.id
      AND d.course_version_id=p_course_version_id
    ORDER BY d.event_seq DESC LIMIT 1) IS DISTINCT FROM 'allow_sealed_curriculum' THEN
  RAISE EXCEPTION 'sealed Course curriculum unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_snapshot
 FROM atlas.teaching_course_version_curriculum_snapshots s
 WHERE s.course_id=v_standing.course_id AND s.course_version_id=p_course_version_id
 AND s.sealed_by_person_entity_id=(
   SELECT c.created_by_person_entity_id FROM atlas.teaching_courses c
   WHERE c.id=v_standing.course_id);
 IF v_snapshot.snapshot_id IS NULL THEN
  RAISE EXCEPTION 'sealed Course curriculum unavailable' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_curriculum_governor_read_v1',
  'proposalId',v_standing.id,'ledgerId',v_standing.ledger_id,
  'courseId',v_standing.course_id,'courseVersionId',p_course_version_id,
  'snapshotId',v_snapshot.snapshot_id,
  'curriculum',v_snapshot.curriculum_payload,
  'scope','sealed_version_curriculum_to_current_governor_only',
  'canOpenOffering',false,'canEnroll',false,'canAppointTeacher',false);
END $governor_reads$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_course_curriculum_governor_read_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_curriculum_disclose_decide_self_api_v1(uuid,uuid,uuid,text),
 public.shared_teaching_course_curriculum_governor_read_self_api_v1(uuid,uuid)
 TO authenticated;
-- Explicitly no general institution roster, no learner/teacher source
-- material read, no publication, Offering opening or Work grant.

-- HELD M3.13 — two-party, exact Offering-opening issuance on ONE
-- Person-authored Course. Opening is NOT classroom activation/enrollment.
-- Source-owned, isolated PG17/protected clone only. No production migration.
DO $source_gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('public.shared_teaching_course_offering_draft_create_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz)') IS NULL
 OR to_regprocedure('public.shared_teaching_course_curriculum_governor_read_self_api_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.require_shared_course_native_ledger_governor_self_v1(uuid)') IS NULL
 OR to_regclass('atlas.teaching_enrollments') IS NULL
 OR to_regclass('atlas.teaching_course_offerings') IS NULL THEN
  RAISE EXCEPTION 'exact draft, source ownership and enrollment containment required'
   USING ERRCODE='42501';
 END IF;
END $source_gate$;

-- Independent original author decision on one exact existing draft Offering,
-- not a generalized institution or Course Version opening permission.
CREATE TABLE atlas.teaching_course_offering_open_decision_events (
 event_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 offering_id uuid NOT NULL REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 proposal_id uuid NOT NULL REFERENCES atlas.teaching_course_operating_standings(id) ON DELETE RESTRICT,
 course_version_id uuid NOT NULL REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 decision text NOT NULL CHECK(decision IN ('allow_open_offering','withhold_open_offering')),
 decided_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(offering_id,request_id)
);
CREATE INDEX shared_course_offering_current_open_decision_v1
 ON atlas.teaching_course_offering_open_decision_events(offering_id,event_seq DESC);
ALTER TABLE atlas.teaching_course_offering_open_decision_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_offering_open_decision_events FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE atlas.teaching_course_offering_open_decision_events_event_seq_seq
 FROM PUBLIC,anon,authenticated;

-- Source-owned, immutable opening receipt. The matching current TXID
-- differentiates an authorized opening UPDATE from old privileged writer
-- RPCs. No caller can insert/alter a receipt or forge a transaction's
-- recorded issuance by setting an arbitrary custom session GUC.
CREATE TABLE atlas.teaching_course_offering_open_issuances (
 offering_id uuid PRIMARY KEY REFERENCES atlas.teaching_course_offerings(id) ON DELETE RESTRICT,
 proposal_id uuid NOT NULL REFERENCES atlas.teaching_course_operating_standings(id) ON DELETE RESTRICT,
 course_version_id uuid NOT NULL REFERENCES atlas.teaching_course_versions(id) ON DELETE RESTRICT,
 open_request_id uuid NOT NULL UNIQUE,
 issued_by_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 issuer_txid bigint NOT NULL,
 opened_at timestamptz NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE atlas.teaching_course_offering_open_issuances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_offering_open_issuances FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.reject_shared_course_open_issuance_change_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $guard$
BEGIN
 RAISE EXCEPTION 'source-issued shared Course opening receipts are immutable'
  USING ERRCODE='55000';
END $guard$;
CREATE TRIGGER shared_course_open_issuance_immutable_v1
 BEFORE UPDATE OR DELETE ON atlas.teaching_course_offering_open_issuances
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_shared_course_open_issuance_change_v1();
REVOKE ALL ON FUNCTION atlas.reject_shared_course_open_issuance_change_v1()
 FROM PUBLIC,anon,authenticated;

-- Replace ONLY the held M3.10 shared draft guard; preserve the legacy
-- Teaching Offering identity guard already present on the table. The old
-- transition RPC cannot create the issuance row and is denied even if it
-- has postgres-level UPDATE rights.
CREATE OR REPLACE FUNCTION atlas.guard_shared_course_offering_identity_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog
AS $shared_issuer_guard$
DECLARE v_issued atlas.teaching_course_offering_open_issuances%ROWTYPE;
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.operating_proposal_id IS NOT NULL THEN
   RAISE EXCEPTION 'shared Course Offering cannot be deleted' USING ERRCODE='55000';
  END IF;
  RETURN OLD;
 END IF;
 IF OLD.operating_proposal_id IS NULL THEN
  RETURN NEW;
 END IF;
 IF NEW.ledger_id IS DISTINCT FROM OLD.ledger_id
 OR NEW.course_id IS DISTINCT FROM OLD.course_id
 OR NEW.course_version_id IS DISTINCT FROM OLD.course_version_id
 OR NEW.operating_proposal_id IS DISTINCT FROM OLD.operating_proposal_id
 OR NEW.creation_request_id IS DISTINCT FROM OLD.creation_request_id
 OR NEW.created_by_person_entity_id IS DISTINCT FROM OLD.created_by_person_entity_id
 OR NEW.created_by_person_id IS DISTINCT FROM OLD.created_by_person_id
 OR NEW.created_by_principal_id IS DISTINCT FROM OLD.created_by_principal_id
 OR NEW.delivery_mode IS DISTINCT FROM OLD.delivery_mode
 OR NEW.starts_at IS DISTINCT FROM OLD.starts_at
 OR NEW.ends_at IS DISTINCT FROM OLD.ends_at
 OR NEW.created_at IS DISTINCT FROM OLD.created_at
 OR NEW.closed_at IS DISTINCT FROM OLD.closed_at
 OR NEW.retired_at IS DISTINCT FROM OLD.retired_at THEN
  RAISE EXCEPTION 'shared Course Offering identity and schedule are immutable'
   USING ERRCODE='55000';
 END IF;
 IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
  IF NEW.opened_at IS DISTINCT FROM OLD.opened_at THEN
   RAISE EXCEPTION 'shared Course opened-at receipt is immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
 END IF;
 IF OLD.state IS DISTINCT FROM 'draft' OR NEW.state IS DISTINCT FROM 'open'
 OR OLD.opened_at IS NOT NULL OR NEW.opened_at IS NULL
 OR NEW.closed_at IS NOT NULL OR NEW.retired_at IS NOT NULL THEN
  RAISE EXCEPTION 'shared Course Offering transition is not source-issued'
   USING ERRCODE='55000';
 END IF;
 SELECT * INTO v_issued FROM atlas.teaching_course_offering_open_issuances i
 WHERE i.offering_id=OLD.id AND i.proposal_id=OLD.operating_proposal_id
 AND i.course_version_id=OLD.course_version_id
 AND i.opened_at=NEW.opened_at AND i.issuer_txid=txid_current();
 IF v_issued.offering_id IS NULL THEN
  RAISE EXCEPTION 'shared Course opening requires an exact current source issuance'
   USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $shared_issuer_guard$;

-- Strong DB-level deny: existing privileged institution-first enrollment
-- RPC writes DIRECTLY to this table. Block ALL shared Offering enrollment
-- inserts, changes or deletes regardless of session/old RPC/helper.
-- Do not infer a learner's consent from Offering.state='open'.
CREATE FUNCTION atlas.guard_shared_course_enrollment_pending_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog
AS $enroll_gate$
DECLARE v_id uuid;
BEGIN
 IF TG_OP IN ('UPDATE','DELETE') THEN
  v_id:=OLD.offering_id;
  IF EXISTS(
   SELECT 1 FROM atlas.teaching_course_offerings o
   WHERE o.id=v_id AND o.operating_proposal_id IS NOT NULL
  ) THEN
   RAISE EXCEPTION 'shared Course learner enrollment is not source-issued'
    USING ERRCODE='42501';
  END IF;
 END IF;
 IF TG_OP IN ('INSERT','UPDATE') THEN
  v_id:=NEW.offering_id;
  IF EXISTS(
   SELECT 1 FROM atlas.teaching_course_offerings o
   WHERE o.id=v_id AND o.operating_proposal_id IS NOT NULL
  ) THEN
   RAISE EXCEPTION 'shared Course learner enrollment is not source-issued'
    USING ERRCODE='42501';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $enroll_gate$;
CREATE TRIGGER shared_course_enrollment_pending_v1
 BEFORE INSERT OR UPDATE OR DELETE ON atlas.teaching_enrollments
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_shared_course_enrollment_pending_v1();
REVOKE ALL ON FUNCTION atlas.guard_shared_course_enrollment_pending_v1()
 FROM PUBLIC,anon,authenticated;

-- Original author may sign an exact DRAFT transition decision. This is
-- separate from title, Version use and curriculum release. Withholding is
-- permitted for a draft even after prior allow; no editing sealed bytes.
CREATE FUNCTION public.shared_teaching_course_offering_open_decide_self_api_v1(
 p_offering_id uuid,p_request_id uuid,p_decision text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $author_decision$
DECLARE
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_author uuid;
 v_previous atlas.teaching_course_offering_open_decision_events%ROWTYPE;
 v_seq bigint;
BEGIN
 IF p_offering_id IS NULL OR p_request_id IS NULL
 OR p_decision IS NULL
 OR p_decision NOT IN ('allow_open_offering','withhold_open_offering') THEN
  RAISE EXCEPTION 'valid exact author opening decision required' USING ERRCODE='22023';
 END IF;
 -- Lock proposal first, same order used by governor open issuance, so
 -- author consent mutation and governor open are serialized.
 SELECT s.* INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 JOIN atlas.teaching_course_offerings o ON o.operating_proposal_id=s.id
 WHERE o.id=p_offering_id FOR UPDATE OF s;
 IF v_standing.id IS NULL THEN
  RAISE EXCEPTION 'shared Course draft Offering required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings
 WHERE id=p_offering_id FOR UPDATE;
 PERFORM atlas.require_private_course_author_self_v1(
   v_standing.course_id,p_decision='allow_open_offering');
 v_author:=atlas.current_person_for_private_course_v1();
 IF v_offering.course_id IS DISTINCT FROM v_standing.course_id
 OR v_offering.ledger_id IS DISTINCT FROM v_standing.ledger_id
 OR v_offering.state NOT IN ('draft','open')
 OR (p_decision='allow_open_offering' AND v_offering.state<>'draft')
 OR v_standing.proposal_state<>'proposed'
 OR v_standing.operator_acceptance_state<>'accepted' THEN
  RAISE EXCEPTION 'current accepted draft Offering required'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM atlas.teaching_course_version_curriculum_snapshots s
  WHERE s.course_id=v_standing.course_id
  AND s.course_version_id=v_offering.course_version_id
  AND s.sealed_by_person_entity_id=v_author
 ) THEN
  RAISE EXCEPTION 'original author sealed curriculum required' USING ERRCODE='42501';
 END IF;
 IF p_decision='allow_open_offering' AND (
   (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
    WHERE d.proposal_id=v_standing.id ORDER BY d.event_seq DESC LIMIT 1)
     IS DISTINCT FROM 'allow_title'
 OR (SELECT d.decision FROM atlas.teaching_course_version_use_decision_events d
    WHERE d.proposal_id=v_standing.id
    AND d.course_version_id=v_offering.course_version_id
    ORDER BY d.event_seq DESC LIMIT 1) IS DISTINCT FROM 'allow_draft_offering'
 OR (SELECT d.decision FROM atlas.teaching_course_curriculum_disclosure_decisions d
    WHERE d.proposal_id=v_standing.id
    AND d.course_version_id=v_offering.course_version_id
    ORDER BY d.event_seq DESC LIMIT 1) IS DISTINCT FROM 'allow_sealed_curriculum'
 ) THEN
  RAISE EXCEPTION 'separate current author title, Version and curriculum release required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_previous FROM atlas.teaching_course_offering_open_decision_events d
 WHERE d.offering_id=p_offering_id AND d.request_id=p_request_id;
 IF v_previous.event_seq IS NOT NULL THEN
  IF v_previous.decision IS DISTINCT FROM p_decision
  OR v_previous.decided_by_person_entity_id IS DISTINCT FROM v_author THEN
   RAISE EXCEPTION 'changed exact author opening request'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_offering_open_decision_v1',
   'offeringId',v_offering.id,'decision',p_decision,
   'alreadyExists',true,'canEnroll',false,'canAppointTeacher',false);
 END IF;
 INSERT INTO atlas.teaching_course_offering_open_decision_events(
  offering_id,proposal_id,course_version_id,request_id,decision,decided_by_person_entity_id
 ) VALUES(
  v_offering.id,v_standing.id,v_offering.course_version_id,p_request_id,p_decision,v_author
 ) RETURNING event_seq INTO v_seq;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_offering_open_decision_v1',
  'offeringId',v_offering.id,'decision',p_decision,
  'eventSequence',v_seq,'alreadyExists',false,
  'canEnroll',false,'canAppointTeacher',false);
END $author_decision$;

-- Actual existing Offering opens exactly once, only from current independent
-- governor source, with current author allowance of that precise Offering,
-- sealed content and current independent title+Version+content consent.
CREATE FUNCTION public.shared_teaching_course_offering_open_self_api_v1(
 p_offering_id uuid,p_request_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $open$
DECLARE
 v_offering atlas.teaching_course_offerings%ROWTYPE;
 v_standing atlas.teaching_course_operating_standings%ROWTYPE;
 v_issuer uuid;
 v_previous atlas.teaching_course_offering_open_issuances%ROWTYPE;
 v_now timestamptz;
BEGIN
 IF p_offering_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'exact shared Course Offering opening request required'
   USING ERRCODE='22023';
 END IF;
 -- The same proposal row is the serialization boundary for all author
 -- title/Version/curriculum/open changes and institution opens.
 SELECT s.* INTO v_standing
 FROM atlas.teaching_course_operating_standings s
 JOIN atlas.teaching_course_offerings o ON o.operating_proposal_id=s.id
 WHERE o.id=p_offering_id FOR UPDATE OF s;
 IF v_standing.id IS NULL OR v_standing.proposal_state<>'proposed'
 OR v_standing.operator_acceptance_state<>'accepted'
 OR v_standing.teaching_activation_id IS NULL THEN
  RAISE EXCEPTION 'currently accepted exact Course relationship required'
   USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_offering FROM atlas.teaching_course_offerings
 WHERE id=p_offering_id FOR UPDATE;
 IF v_offering.operating_proposal_id IS DISTINCT FROM v_standing.id
 OR v_offering.course_id IS DISTINCT FROM v_standing.course_id
 OR v_offering.ledger_id IS DISTINCT FROM v_standing.ledger_id
 OR NOT EXISTS(SELECT 1 FROM atlas.teaching_courses c
   WHERE c.id=v_standing.course_id AND c.status='active'
   AND c.retired_at IS NULL) THEN
  RAISE EXCEPTION 'same original active Course and institution required'
   USING ERRCODE='42501';
 END IF;
 v_issuer:=atlas.require_shared_course_native_ledger_governor_self_v1(v_standing.ledger_id);
 IF NOT atlas.capability_entitlement_grant_live_v1(
  v_standing.ledger_id,'teaching',1)
 OR NOT atlas.teaching_activation_active_v1(
  v_standing.ledger_id,v_standing.teaching_activation_id) THEN
  RAISE EXCEPTION 'live exact native Ledger root and Teaching issuance required'
   USING ERRCODE='42501';
 END IF;
 IF (SELECT d.decision FROM atlas.teaching_course_operating_title_disclosure_events d
     WHERE d.proposal_id=v_standing.id ORDER BY d.event_seq DESC LIMIT 1)
     IS DISTINCT FROM 'allow_title'
 OR (SELECT d.decision FROM atlas.teaching_course_version_use_decision_events d
     WHERE d.proposal_id=v_standing.id
       AND d.course_version_id=v_offering.course_version_id
     ORDER BY d.event_seq DESC LIMIT 1)
     IS DISTINCT FROM 'allow_draft_offering'
 OR (SELECT d.decision FROM atlas.teaching_course_curriculum_disclosure_decisions d
     WHERE d.proposal_id=v_standing.id
       AND d.course_version_id=v_offering.course_version_id
     ORDER BY d.event_seq DESC LIMIT 1)
     IS DISTINCT FROM 'allow_sealed_curriculum'
 OR (SELECT d.decision FROM atlas.teaching_course_offering_open_decision_events d
     WHERE d.offering_id=v_offering.id
       AND d.proposal_id=v_standing.id
       AND d.course_version_id=v_offering.course_version_id
     ORDER BY d.event_seq DESC LIMIT 1)
     IS DISTINCT FROM 'allow_open_offering' THEN
  RAISE EXCEPTION 'four independent current author grants required'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1
  FROM atlas.teaching_course_version_curriculum_snapshots s
  JOIN atlas.teaching_course_versions v
    ON v.course_id=s.course_id AND v.id=s.course_version_id
  WHERE s.course_id=v_standing.course_id
   AND s.course_version_id=v_offering.course_version_id
   AND v.published_by_person_entity_id=s.sealed_by_person_entity_id
   AND s.sealed_by_person_entity_id=(
    SELECT c.created_by_person_entity_id FROM atlas.teaching_courses c
    WHERE c.id=v_standing.course_id)) THEN
  RAISE EXCEPTION 'exact author-sealed immutable Course Version required'
   USING ERRCODE='42501';
 END IF;
 IF EXISTS (SELECT 1 FROM atlas.teaching_enrollments e
  WHERE e.offering_id=v_offering.id) THEN
  RAISE EXCEPTION 'unissued learner enrollment contaminates shared Course Offering'
   USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_previous FROM atlas.teaching_course_offering_open_issuances i
 WHERE i.offering_id=v_offering.id;
 IF v_previous.offering_id IS NOT NULL THEN
  IF v_previous.open_request_id IS DISTINCT FROM p_request_id
  OR v_previous.issued_by_person_entity_id IS DISTINCT FROM v_issuer
  OR v_offering.state<>'open' OR v_offering.opened_at IS DISTINCT FROM v_previous.opened_at THEN
   RAISE EXCEPTION 'immutable shared Offering opening request changed'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_offering_open_v1',
   'offeringId',v_offering.id,'courseId',v_offering.course_id,
   'courseVersionId',v_offering.course_version_id,
   'ledgerId',v_offering.ledger_id,'offeringState','open',
   'alreadyExists',true,'canEnroll',false,'canAppointTeacher',false);
 END IF;
 IF v_offering.state<>'draft' OR v_offering.opened_at IS NOT NULL THEN
  RAISE EXCEPTION 'only exact draft shared Offering can be opened'
   USING ERRCODE='42501';
 END IF;
 v_now:=clock_timestamp();
 INSERT INTO atlas.teaching_course_offering_open_issuances(
  offering_id,proposal_id,course_version_id,open_request_id,
  issued_by_person_entity_id,issuer_txid,opened_at
 ) VALUES(
  v_offering.id,v_standing.id,v_offering.course_version_id,p_request_id,
  v_issuer,txid_current(),v_now
 );
 UPDATE atlas.teaching_course_offerings o
 SET state='open',opened_at=v_now
 WHERE o.id=v_offering.id;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'opening source write not performed' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_offering_open_v1',
  'offeringId',v_offering.id,'courseId',v_offering.course_id,
  'courseVersionId',v_offering.course_version_id,
  'ledgerId',v_offering.ledger_id,'offeringState','open',
  'alreadyExists',false,'canEnroll',false,'canAppointTeacher',false);
END $open$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_offering_open_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_offering_open_decide_self_api_v1(uuid,uuid,text),
 public.shared_teaching_course_offering_open_self_api_v1(uuid,uuid)
 TO authenticated;
-- No teacher/learner admission, classroom contents to learners, old Course
-- writer, generic transition, or implicit student enrollment is issued here.

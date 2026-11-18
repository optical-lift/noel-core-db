-- HELD M3.5: institutional Course operating INTENT, no institution acceptance.
-- One original Course only. Source-only for disposable/protected clone.
-- Reader/writer never uses deprecated Atlas Principal or ledger seats as
-- authority. A seat is participation, NOT permission to operate a Course.
-- No stored accepted/active standing may be created by this source.
DO $guard$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved' THEN
  RAISE EXCEPTION 'clone-only institutional standing proposal'
   USING ERRCODE='42501';
 END IF;
 IF to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)')
    IS NULL THEN
  RAISE EXCEPTION 'canonical author guard not installed'
   USING ERRCODE='23514';
 END IF;
END
$guard$;

-- A Course author's proposal does NOT establish an institutional right or
-- disclose the Course to the institution. Formal standing acceptance requires
-- independent, source-proven current jurisdiction and Teaching activation,
-- to be implemented later as an authorized separate issuance operation.
CREATE TABLE atlas.teaching_course_operating_standings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES atlas.teaching_courses(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 proposed_by_person_entity_id uuid NOT NULL
  REFERENCES reality.entities(id) ON DELETE RESTRICT,
 proposal_state text NOT NULL DEFAULT 'proposed'
  CHECK (proposal_state IN ('proposed','withdrawn')),
 proposed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 withdrawn_at timestamptz,
 UNIQUE(course_id,request_id),
 CONSTRAINT teaching_course_proposal_state_coherence
 CHECK (
  (proposal_state='proposed' AND withdrawn_at IS NULL)
  OR (proposal_state='withdrawn' AND withdrawn_at IS NOT NULL)
 )
);
CREATE UNIQUE INDEX teaching_course_one_pending_ledger_proposal
 ON atlas.teaching_course_operating_standings(course_id,ledger_id)
 WHERE proposal_state='proposed';
ALTER TABLE atlas.teaching_course_operating_standings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_operating_standings
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.shared_teaching_course_operating_propose_self_api_v1(
 p_course_id uuid,p_ledger_id uuid,p_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $propose$
DECLARE v_course uuid;v_person uuid;
 v_previous atlas.teaching_course_operating_standings%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_ledger_id IS NULL OR p_request_id IS NULL THEN
  RAISE EXCEPTION 'valid Course and proposal request required'
   USING ERRCODE='22023';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO v_previous
 FROM atlas.teaching_course_operating_standings
 WHERE course_id=v_course AND request_id=p_request_id;
 IF v_previous.id IS NOT NULL THEN
  IF v_previous.ledger_id IS DISTINCT FROM p_ledger_id THEN
   RAISE EXCEPTION 'original operating request changed'
    USING ERRCODE='23505';
  END IF;
  RETURN jsonb_build_object(
   'contractVersion','shared_course_operating_proposal_v1',
   'courseId',v_course,'proposalId',v_previous.id,
   'ledgerId',v_previous.ledger_id,
   'state',v_previous.proposal_state);
 END IF;
 -- Ledger existence and canonical subject are checked from source; the
 -- author is NOT credited with governance merely from knowing its UUID.
 IF NOT EXISTS(
  SELECT 1 FROM ledger.ledgers l JOIN reality.entities e
   ON e.id=l.subject_entity_id
   AND e.identity_state='canonical'
  WHERE l.id=p_ledger_id AND l.ledger_state='active'
   AND l.retired_at IS NULL
 ) THEN
  RAISE EXCEPTION 'current canonical operating Ledger required'
   USING ERRCODE='42501';
 END IF;
 INSERT INTO atlas.teaching_course_operating_standings(
  course_id,ledger_id,request_id,proposed_by_person_entity_id)
 VALUES(v_course,p_ledger_id,p_request_id,v_person)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_operating_proposal_v1',
  'courseId',v_course,'proposalId',v_id,
  'ledgerId',p_ledger_id,'state','proposed');
END
$propose$;

CREATE FUNCTION public.shared_teaching_course_operating_withdraw_self_api_v1(
 p_course_id uuid,p_request_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $withdraw$
DECLARE v_course uuid;v_prior atlas.teaching_course_operating_standings%ROWTYPE;
BEGIN
 IF p_request_id IS NULL THEN
  RAISE EXCEPTION 'original proposal request required'
   USING ERRCODE='22023';
 END IF;
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 -- Pending withdrawal is allowed even if original Course was retired.
 SELECT * INTO v_prior FROM atlas.teaching_course_operating_standings
  WHERE course_id=v_course AND request_id=p_request_id FOR UPDATE;
 IF v_prior.id IS NULL THEN
  RAISE EXCEPTION 'authorized proposal required' USING ERRCODE='42501';
 END IF;
 IF v_prior.proposal_state='proposed' THEN
  UPDATE atlas.teaching_course_operating_standings
    SET proposal_state='withdrawn',withdrawn_at=clock_timestamp()
  WHERE id=v_prior.id;
 END IF;
 RETURN jsonb_build_object(
   'contractVersion','shared_course_operating_proposal_v1',
   'courseId',v_course,'proposalId',v_prior.id,
   'ledgerId',v_prior.ledger_id,'state','withdrawn');
END
$withdraw$;

CREATE FUNCTION public.shared_teaching_course_operating_proposals_self_api_v1(
 p_course_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO pg_catalog
AS $proposals$
DECLARE v_course uuid;v_items jsonb;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,false);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'proposalId',i.id,'ledgerId',i.ledger_id,
   'state',i.proposal_state,'requestId',i.request_id)
   ORDER BY i.proposed_at,i.id),'[]'::jsonb)
 INTO v_items FROM atlas.teaching_course_operating_standings i
 WHERE i.course_id=v_course;
 RETURN jsonb_build_object(
  'contractVersion','shared_course_operating_proposals_v1',
  'courseId',v_course,'proposals',v_items);
END
$proposals$;

REVOKE ALL ON FUNCTION
 public.shared_teaching_course_operating_propose_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_course_operating_withdraw_self_api_v1(uuid,uuid),
 public.shared_teaching_course_operating_proposals_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.shared_teaching_course_operating_propose_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_course_operating_withdraw_self_api_v1(uuid,uuid),
 public.shared_teaching_course_operating_proposals_self_api_v1(uuid)
 TO authenticated;
-- No institutional acceptance, activation, Course publishing, Offering,
-- teacher appointment, enrollment, assignment or disclosure RPC here.

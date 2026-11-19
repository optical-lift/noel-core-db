-- HELD M3.17D: one explicit learner submission and direct author review.
-- No institution, publication, enrollment, generic Notebook reader or grade.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regclass('atlas.teaching_course_private_study_answer_revisions') IS NULL
 OR to_regprocedure('atlas.private_study_answer_scope_self_v1(uuid,uuid,uuid,uuid,uuid)') IS NULL
 THEN RAISE EXCEPTION 'held private answer source required' USING ERRCODE='42501'; END IF;
END $gate$;
CREATE TABLE atlas.teaching_course_private_answer_submissions(
 submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 answer_revision_id uuid NOT NULL UNIQUE REFERENCES atlas.teaching_course_private_study_answer_revisions(answer_revision_id) ON DELETE RESTRICT,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(learner_person_entity_id,request_id),
 CHECK(learner_person_entity_id<>reviewer_person_entity_id)
);
CREATE TABLE atlas.teaching_course_private_answer_review_events(
 event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 submission_id uuid NOT NULL REFERENCES atlas.teaching_course_private_answer_submissions(submission_id) ON DELETE RESTRICT,
 event_kind text NOT NULL CHECK(event_kind IN ('accept_review','withdraw','feedback')),
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 feedback_text text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(submission_id,event_kind),UNIQUE(actor_person_entity_id,request_id),
 CHECK((event_kind='feedback' AND feedback_text IS NOT NULL AND char_length(feedback_text) BETWEEN 1 AND 20000 AND btrim(feedback_text,E' \r\n\t')<>'')
 OR (event_kind<>'feedback' AND feedback_text IS NULL))
);
ALTER TABLE atlas.teaching_course_private_answer_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.teaching_course_private_answer_review_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_answer_submissions,atlas.teaching_course_private_answer_review_events FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER private_submission_immutable BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_answer_submissions FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_submission_no_truncate BEFORE TRUNCATE ON atlas.teaching_course_private_answer_submissions FOR EACH STATEMENT EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_review_event_immutable BEFORE UPDATE OR DELETE ON atlas.teaching_course_private_answer_review_events FOR EACH ROW EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_review_event_no_truncate BEFORE TRUNCATE ON atlas.teaching_course_private_answer_review_events FOR EACH STATEMENT EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Teacher standing is the current direct-study original Course author, not a
-- role name or client flag. Exact consent AND independent reviewer acceptance
-- are still required to disclose even the selected answer text.
CREATE FUNCTION atlas.private_answer_reviewer_current_v1(
 a atlas.teaching_course_private_study_answer_revisions,p_reviewer uuid)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE i atlas.teaching_course_private_study_invitations%ROWTYPE;
 d atlas.teaching_course_private_study_unit_decisions%ROWTYPE;
BEGIN
 SELECT * INTO i FROM atlas.teaching_course_private_study_invitations
 WHERE invitation_id=a.invitation_id AND invited_by_person_entity_id=p_reviewer
 AND learner_person_entity_id=a.learner_person_entity_id;
 IF i.invitation_id IS NULL THEN RAISE EXCEPTION 'exact named reviewer required' USING ERRCODE='42501'; END IF;
 -- Same lock order as existing author release/withdrawal. Require current
 -- author write access even for review read in this narrow held contract.
 PERFORM atlas.require_private_course_author_self_v1(i.course_id,true);
 PERFORM 1 FROM atlas.teaching_course_private_study_invitations WHERE invitation_id=i.invitation_id FOR SHARE;
 IF NOT atlas.private_course_study_current_v1(i.course_id,i.learner_person_entity_id)
 THEN RAISE EXCEPTION 'current accepted direct study required' USING ERRCODE='42501'; END IF;
 SELECT * INTO d FROM atlas.teaching_course_private_study_unit_decisions
 WHERE invitation_id=i.invitation_id AND unit_id=a.unit_id ORDER BY event_seq DESC LIMIT 1;
 IF d.decision IS DISTINCT FROM 'allow' OR d.snapshot_id IS DISTINCT FROM a.snapshot_id
 THEN RAISE EXCEPTION 'current released answer edition required' USING ERRCODE='42501'; END IF;
END $$;
REVOKE ALL ON FUNCTION atlas.private_answer_reviewer_current_v1(atlas.teaching_course_private_study_answer_revisions,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(
 p_answer_revision_id uuid,p_reviewer_person_id uuid,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 s atlas.teaching_course_private_answer_submissions%ROWTYPE;
BEGIN
 IF p_answer_revision_id IS NULL OR p_reviewer_person_id IS NULL OR p_request_id IS NULL
 THEN RAISE EXCEPTION 'select saved revision and named reviewer explicitly' USING ERRCODE='22023'; END IF;
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=p_answer_revision_id AND learner_person_entity_id=v_person;
 IF a.answer_revision_id IS NULL THEN RAISE EXCEPTION 'own saved revision required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_invitations i WHERE i.invitation_id=a.invitation_id
 AND i.invited_by_person_entity_id=p_reviewer_person_id AND i.learner_person_entity_id=v_person)
 THEN RAISE EXCEPTION 'reviewer must be the actual direct-study author' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(a.answer_revision_id::text,1));
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE learner_person_entity_id=v_person AND request_id=p_request_id;
 IF s.submission_id IS NOT NULL THEN
  IF s.answer_revision_id IS DISTINCT FROM a.answer_revision_id OR s.reviewer_person_entity_id IS DISTINCT FROM p_reviewer_person_id OR s.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
   THEN RAISE EXCEPTION 'changed submission request' USING ERRCODE='23505'; END IF;
 ELSE
  INSERT INTO atlas.teaching_course_private_answer_submissions(answer_revision_id,learner_person_entity_id,reviewer_person_entity_id,request_id,recorded_by_auth_user_id)
  VALUES(a.answer_revision_id,v_person,p_reviewer_person_id,p_request_id,auth.uid()) RETURNING * INTO s;
 END IF;
 RETURN jsonb_build_object('contractVersion','private_answer_submission_v1','submissionId',s.submission_id,
 'answerRevisionId',s.answer_revision_id,'reviewerPersonId',s.reviewer_person_entity_id,'requestId',s.request_id,
 'submittedAt',s.recorded_at,'purpose','review_selected_answer','notebookDisclosed',false);
END $$;

-- Own learner or exact named reviewer. Locks the original Course, invitation,
-- then submission. All later decisions serialize on this SAME row.
CREATE FUNCTION atlas.private_answer_submission_scope_v1(p_submission uuid,p_mode text)
RETURNS atlas.teaching_course_private_answer_submissions LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;s atlas.teaching_course_private_answer_submissions%ROWTYPE;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE submission_id=p_submission
 AND ((p_mode='learner' AND learner_person_entity_id=v_person) OR (p_mode='reviewer' AND reviewer_person_entity_id=v_person));
 IF s.submission_id IS NULL THEN RAISE EXCEPTION 'own selected submission required' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=s.answer_revision_id;
 IF p_mode='learner' THEN
  PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 ELSE PERFORM atlas.private_answer_reviewer_current_v1(a,v_person); END IF;
 SELECT * INTO s FROM atlas.teaching_course_private_answer_submissions WHERE submission_id=p_submission FOR UPDATE;
 RETURN s;
END $$;
REVOKE ALL ON FUNCTION atlas.private_answer_submission_scope_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_answer_review_event_self_api_v1(
 p_submission_id uuid,p_request_id uuid,p_action text,p_feedback text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE s atlas.teaching_course_private_answer_submissions%ROWTYPE;e atlas.teaching_course_private_answer_review_events%ROWTYPE;v_person uuid;
BEGIN
 IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('accept_review','withdraw','feedback')
 OR (p_action='feedback' AND (p_feedback IS NULL OR char_length(p_feedback) NOT BETWEEN 1 AND 20000 OR btrim(p_feedback,E' \r\n\t')=''))
 OR (p_action<>'feedback' AND p_feedback IS NOT NULL)
 THEN RAISE EXCEPTION 'explicit valid review action required' USING ERRCODE='22023'; END IF;
 s:=atlas.private_answer_submission_scope_v1(p_submission_id,CASE WHEN p_action='withdraw' THEN 'learner' ELSE 'reviewer' END);
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO e FROM atlas.teaching_course_private_answer_review_events WHERE actor_person_entity_id=v_person AND request_id=p_request_id;
 IF e.event_id IS NOT NULL THEN
  IF e.submission_id IS DISTINCT FROM s.submission_id OR e.event_kind IS DISTINCT FROM p_action OR e.feedback_text IS DISTINCT FROM p_feedback OR e.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
   THEN RAISE EXCEPTION 'changed review request' USING ERRCODE='23505'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='withdraw')
  THEN RAISE EXCEPTION 'submission withdrawn' USING ERRCODE='42501'; END IF;
  IF p_action='feedback' AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='accept_review' AND actor_person_entity_id=v_person)
  THEN RAISE EXCEPTION 'independent reviewer acceptance required' USING ERRCODE='42501'; END IF;
  INSERT INTO atlas.teaching_course_private_answer_review_events(submission_id,event_kind,actor_person_entity_id,recorded_by_auth_user_id,request_id,feedback_text)
  VALUES(s.submission_id,p_action,v_person,auth.uid(),p_request_id,p_feedback) RETURNING * INTO e;
 END IF;
 RETURN jsonb_build_object('contractVersion','private_answer_review_event_v1','submissionId',s.submission_id,
 'eventId',e.event_id,'action',e.event_kind,'requestId',e.request_id,'recordedAt',e.recorded_at);
END $$;

-- The reviewer may inspect a bounded submission header before acceptance,
-- but receives no answer, prompt text, other revision, private notes or list.
-- After withdrawal reviewer gets no contents. Own learner read remains gated
-- by current encounter; retained-history policy is not decided here.
CREATE FUNCTION public.shared_teaching_private_answer_submission_read_self_api_v1(
 p_submission_id uuid,p_mode text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE s atlas.teaching_course_private_answer_submissions%ROWTYPE;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 f atlas.teaching_course_private_answer_review_events%ROWTYPE;accepted boolean;withdrawn boolean;
BEGIN
 IF p_mode IS NULL OR p_mode NOT IN ('learner','reviewer') THEN RAISE EXCEPTION 'exact participant mode required' USING ERRCODE='22023'; END IF;
 s:=atlas.private_answer_submission_scope_v1(p_submission_id,p_mode);
 SELECT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='withdraw'),
 EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='accept_review' AND actor_person_entity_id=s.reviewer_person_entity_id)
 INTO withdrawn,accepted;
 IF p_mode='reviewer' AND withdrawn THEN RAISE EXCEPTION 'submission withdrawn' USING ERRCODE='42501'; END IF;
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions WHERE answer_revision_id=s.answer_revision_id;
 SELECT * INTO f FROM atlas.teaching_course_private_answer_review_events WHERE submission_id=s.submission_id AND event_kind='feedback' AND actor_person_entity_id=s.reviewer_person_entity_id;
 RETURN jsonb_build_object('contractVersion','private_answer_submission_read_v1','submissionId',s.submission_id,
 'answerRevisionId',a.answer_revision_id,'invitationId',a.invitation_id,'unitId',a.unit_id,'snapshotId',a.snapshot_id,
 'unitRevisionId',a.unit_revision_id,'activityId',a.activity_id,'revisionNumber',a.revision_no,
 'reviewerPersonId',s.reviewer_person_entity_id,'state',CASE WHEN withdrawn THEN 'withdrawn' WHEN f.event_id IS NOT NULL THEN 'feedback' WHEN accepted THEN 'accepted' ELSE 'submitted' END,
 'text',CASE WHEN p_mode='learner' OR accepted THEN a.body_text ELSE NULL END,
 'feedback',CASE WHEN f.event_id IS NULL THEN NULL ELSE jsonb_build_object('eventId',f.event_id,'text',f.feedback_text,'recordedAt',f.recorded_at) END,
 'notebookDisclosed',false);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_answer_submit_self_api_v1(uuid,uuid,uuid),
 public.shared_teaching_private_answer_review_event_self_api_v1(uuid,uuid,text,text),
 public.shared_teaching_private_answer_submission_read_self_api_v1(uuid,text) TO authenticated;

-- Own-answer entry point: derive the only direct reviewer from the source,
-- never from an entered person name. No automatic submission.
CREATE FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(p_answer_revision_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;a atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
 reviewer uuid;s_id uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 SELECT * INTO a FROM atlas.teaching_course_private_study_answer_revisions
 WHERE answer_revision_id=p_answer_revision_id AND learner_person_entity_id=v_person;
 IF a.answer_revision_id IS NULL THEN RAISE EXCEPTION 'own answer required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.private_study_answer_scope_self_v1(a.invitation_id,a.unit_id,a.snapshot_id,a.unit_revision_id,a.activity_id);
 SELECT invited_by_person_entity_id INTO reviewer FROM atlas.teaching_course_private_study_invitations WHERE invitation_id=a.invitation_id;
 SELECT submission_id INTO s_id FROM atlas.teaching_course_private_answer_submissions WHERE answer_revision_id=a.answer_revision_id;
 RETURN jsonb_build_object('contractVersion','private_answer_review_target_v1','answerRevisionId',a.answer_revision_id,
 'reviewerPersonId',reviewer,'submissionId',s_id,'purpose','review_selected_answer');
END $$;
-- Bounded author inbox: only consented submissions for this original Course
-- with current exact issued relationship, including submitted headers prior
-- to review acceptance. No answer text, private revisions, unrelated records
-- or roster. Cursor is on the immutable submission ordering.
CREATE FUNCTION public.shared_teaching_private_answer_review_inbox_self_api_v1(p_course_id uuid,p_before uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_course uuid;v_person uuid;v_before_at timestamptz;items jsonb;
BEGIN
 v_course:=atlas.require_private_course_author_self_v1(p_course_id,true);
 v_person:=atlas.current_person_for_private_course_v1();
 IF p_before IS NOT NULL THEN
  SELECT s.recorded_at INTO v_before_at FROM atlas.teaching_course_private_answer_submissions s
  JOIN atlas.teaching_course_private_study_answer_revisions a ON a.answer_revision_id=s.answer_revision_id
  JOIN atlas.teaching_course_private_study_invitations i ON i.invitation_id=a.invitation_id
  WHERE s.submission_id=p_before AND s.reviewer_person_entity_id=v_person AND i.course_id=v_course;
  IF v_before_at IS NULL THEN RAISE EXCEPTION 'invalid inbox cursor' USING ERRCODE='42501'; END IF;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('submissionId',q.submission_id,'answerRevisionId',q.answer_revision_id,
 'unitId',q.unit_id,'activityId',q.activity_id,'revisionNumber',q.revision_no,'recordedAt',q.recorded_at,'state',q.state)
 ORDER BY q.recorded_at DESC,q.submission_id DESC),'[]'::jsonb) INTO items FROM (
 SELECT s.submission_id,s.answer_revision_id,s.recorded_at,a.unit_id,a.activity_id,a.revision_no,
 CASE WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='feedback') THEN 'feedback'
 WHEN EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='accept_review') THEN 'accepted'
 ELSE 'submitted' END AS state
 FROM atlas.teaching_course_private_answer_submissions s
 JOIN atlas.teaching_course_private_study_answer_revisions a ON a.answer_revision_id=s.answer_revision_id
 JOIN atlas.teaching_course_private_study_invitations i ON i.invitation_id=a.invitation_id
 JOIN LATERAL (SELECT d.decision,d.snapshot_id FROM atlas.teaching_course_private_study_unit_decisions d
 WHERE d.invitation_id=i.invitation_id AND d.unit_id=a.unit_id ORDER BY event_seq DESC LIMIT 1) d ON d.decision='allow' AND d.snapshot_id=a.snapshot_id
 WHERE s.reviewer_person_entity_id=v_person AND i.course_id=v_course AND i.invited_by_person_entity_id=v_person
 AND atlas.private_course_study_current_v1(v_course,i.learner_person_entity_id)
 AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_answer_review_events e WHERE e.submission_id=s.submission_id AND e.event_kind='withdraw')
 AND (p_before IS NULL OR (s.recorded_at,s.submission_id)<(v_before_at,p_before))
 ORDER BY s.recorded_at DESC,s.submission_id DESC LIMIT 21
 ) q;
 RETURN jsonb_build_object('contractVersion','private_answer_review_inbox_v1','courseId',v_course,
 'items',CASE WHEN jsonb_array_length(items)>20 THEN items-20 ELSE items END,
 'more',jsonb_array_length(items)>20);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(uuid),
 public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_answer_review_target_self_api_v1(uuid),
 public.shared_teaching_private_answer_review_inbox_self_api_v1(uuid,uuid) TO authenticated;

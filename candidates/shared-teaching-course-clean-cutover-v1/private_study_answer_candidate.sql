-- HELD M3.17C: private student answer originals on the existing direct-study
-- sealed Unit. No submission, teacher read, issuance, grading or learner seed.
DO $gate$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('public.shared_teaching_private_study_sealed_unit_read_self_api_v1(uuid,uuid)') IS NULL
 OR to_regprocedure('atlas.current_person_for_private_course_v1()') IS NULL
 THEN RAISE EXCEPTION 'held sealed private study prerequisite' USING ERRCODE='42501'; END IF;
END $gate$;

CREATE TABLE atlas.teaching_course_private_study_answer_revisions(
 answer_revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 invitation_id uuid NOT NULL REFERENCES atlas.teaching_course_private_study_invitations(invitation_id) ON DELETE RESTRICT,
 unit_id uuid NOT NULL REFERENCES atlas.teaching_course_units(unit_id) ON DELETE RESTRICT,
 snapshot_id uuid NOT NULL REFERENCES atlas.teaching_course_version_curriculum_snapshots(snapshot_id) ON DELETE RESTRICT,
 unit_revision_id uuid NOT NULL REFERENCES atlas.teaching_course_unit_revisions(revision_id) ON DELETE RESTRICT,
 activity_id uuid NOT NULL,
 learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK(based_on_revision BETWEEN 0 AND 9999),
 revision_no integer NOT NULL CHECK(revision_no=based_on_revision+1),
 body_text text NOT NULL CHECK(char_length(body_text) BETWEEN 1 AND 20000 AND btrim(body_text)<>''),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(invitation_id,unit_id,snapshot_id,unit_revision_id,activity_id,revision_no),
 UNIQUE(learner_person_entity_id,request_id)
);
ALTER TABLE atlas.teaching_course_private_study_answer_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.teaching_course_private_study_answer_revisions FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER private_answer_immutable BEFORE UPDATE OR DELETE
 ON atlas.teaching_course_private_study_answer_revisions FOR EACH ROW
 EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();
CREATE TRIGGER private_answer_no_truncate BEFORE TRUNCATE
 ON atlas.teaching_course_private_study_answer_revisions FOR EACH STATEMENT
 EXECUTE FUNCTION atlas.reject_private_study_original_mutation_v1();

-- Conservative shared text grammar: explicit top-level UUIDv4 Question, a
-- unique marker, and a nonempty first ordinary paragraph. No code or
-- presentation block can create an answerable question. More complex source
-- is deliberately refused rather than guessed. No title/ordinal identity.
CREATE FUNCTION atlas.private_study_question_valid_v1(p_text text,p_activity uuid)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO pg_catalog AS $$
DECLARE lines text[];i integer;line text;marker text;hits integer:=0;found boolean:=false;
 disclosure boolean:=false;fence text:=NULL;j integer;
BEGIN
 IF p_text IS NULL OR p_activity IS NULL OR p_activity::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN RETURN false; END IF;
 marker:=' {#titus-activity:'||p_activity::text||'}';
 lines:=string_to_array(replace(replace(p_text,E'\r\n',E'\n'),E'\r',E'\n'),E'\n');
 FOR i IN 1..coalesce(array_length(lines,1),0) LOOP
  line:=lines[i];
  -- Count even malformed duplicates; refuse ambiguous marker anywhere.
  IF strpos(lower(line),marker)>0 THEN hits:=hits+1;
   IF strpos(substring(lower(line) FROM strpos(lower(line),marker)+length(marker)),marker)>0 THEN RETURN false; END IF;
  END IF;
  IF line ~ '^ {0,3}(\x60{3,}|~{3,})' THEN
   IF fence IS NULL THEN fence:=left(ltrim(line),1);
   ELSIF left(ltrim(line),1)=fence THEN fence:=NULL; END IF;
   CONTINUE;
  END IF;
  IF fence IS NOT NULL THEN CONTINUE; END IF;
  IF line ~ '^:::(scripture|evidence|reveal) ' THEN
   IF disclosure THEN RETURN false; END IF;
   disclosure:=true;CONTINUE;
  END IF;
  IF line=':::' THEN disclosure:=false;CONTINUE; END IF;
  IF disclosure THEN CONTINUE; END IF;
  IF lower(line)='## question'||marker THEN
   j:=i+1;
   WHILE j<=array_length(lines,1) AND btrim(lines[j])='' LOOP j:=j+1; END LOOP;
   IF j>array_length(lines,1) OR lines[j] ~ '^\s*(#|>|[-*] |\d+\. |\||:::|\x60{3,}|~{3,})' THEN RETURN false; END IF;
   found:=true;
  END IF;
 END LOOP;
 RETURN found AND hits=1 AND NOT disclosure AND fence IS NULL;
END $$;
REVOKE ALL ON FUNCTION atlas.private_study_question_valid_v1(text,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Reuse the exact existing signed learner, Course lock, invitation lock,
-- accepted relation and current author-released sealed Unit check. A private
-- write is learner-origin only and never changes the source or discloses it.
CREATE FUNCTION atlas.private_study_answer_scope_self_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid)
RETURNS uuid LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $$
DECLARE j jsonb;v_person uuid;
BEGIN
 v_person:=atlas.current_person_for_private_course_v1();
 j:=public.shared_teaching_private_study_sealed_unit_read_self_api_v1(p_invitation,p_unit);
 IF j->>'contractVersion' IS DISTINCT FROM 'private_study_sealed_unit_read_v1'
 OR j->>'snapshotId' IS DISTINCT FROM p_snapshot::text
 OR j->'unit'->>'revisionId' IS DISTINCT FROM p_unit_revision::text
 OR NOT atlas.private_study_question_valid_v1(j->'unit'->>'text',p_activity)
 THEN RAISE EXCEPTION 'current exact issued question unavailable' USING ERRCODE='42501'; END IF;
 RETURN v_person;
END $$;
REVOKE ALL ON FUNCTION atlas.private_study_answer_scope_self_v1(uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION atlas.private_study_answer_receipt_v1(r atlas.teaching_course_private_study_answer_revisions)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO pg_catalog AS $$
 SELECT jsonb_build_object('contractVersion','private_study_answer_v1','invitationId',r.invitation_id,
 'unitId',r.unit_id,'snapshotId',r.snapshot_id,'unitRevisionId',r.unit_revision_id,
 'activityId',r.activity_id,'answerRevisionId',r.answer_revision_id,'revisionNumber',r.revision_no,
 'requestId',r.request_id,'text',r.body_text,'savedAt',r.recorded_at,'private',true,'submitted',false)
$$;
REVOKE ALL ON FUNCTION atlas.private_study_answer_receipt_v1(atlas.teaching_course_private_study_answer_revisions) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;r atlas.teaching_course_private_study_answer_revisions%ROWTYPE;
BEGIN
 v_person:=atlas.private_study_answer_scope_self_v1(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity);
 SELECT * INTO r FROM atlas.teaching_course_private_study_answer_revisions a
 WHERE a.invitation_id=p_invitation AND a.unit_id=p_unit AND a.snapshot_id=p_snapshot
 AND a.unit_revision_id=p_unit_revision AND a.activity_id=p_activity AND a.learner_person_entity_id=v_person
 ORDER BY a.revision_no DESC LIMIT 1;
 IF r.answer_revision_id IS NULL THEN
  RETURN jsonb_build_object('contractVersion','private_study_answer_v1','invitationId',p_invitation,
   'unitId',p_unit,'snapshotId',p_snapshot,'unitRevisionId',p_unit_revision,'activityId',p_activity,
   'answerRevisionId',NULL,'revisionNumber',0,'requestId',NULL,'text',NULL,'savedAt',NULL,'private',true,'submitted',false);
 END IF;
 RETURN atlas.private_study_answer_receipt_v1(r);
END $$;
CREATE FUNCTION public.shared_teaching_private_study_answer_save_self_api_v1(
 p_invitation uuid,p_unit uuid,p_snapshot uuid,p_unit_revision uuid,p_activity uuid,
 p_request uuid,p_expected_revision integer,p_text text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $$
DECLARE v_person uuid;r atlas.teaching_course_private_study_answer_revisions%ROWTYPE;n integer;
BEGIN
 IF p_request IS NULL OR p_expected_revision IS NULL OR p_expected_revision NOT BETWEEN 0 AND 9999
 OR p_text IS NULL OR char_length(p_text) NOT BETWEEN 1 AND 20000 OR btrim(p_text)=''
 THEN RAISE EXCEPTION 'invalid answer revision' USING ERRCODE='22023'; END IF;
 v_person:=atlas.private_study_answer_scope_self_v1(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity);
 -- The existing source acquired Course/invitation shared locks; do not
 -- upgrade them. Serialize only this answer thread after authorization.
 PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws(':',p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity),0));
 SELECT * INTO r FROM atlas.teaching_course_private_study_answer_revisions
 WHERE learner_person_entity_id=v_person AND request_id=p_request;
 IF r.answer_revision_id IS NOT NULL THEN
  IF r.invitation_id IS DISTINCT FROM p_invitation OR r.unit_id IS DISTINCT FROM p_unit
  OR r.snapshot_id IS DISTINCT FROM p_snapshot OR r.unit_revision_id IS DISTINCT FROM p_unit_revision
  OR r.activity_id IS DISTINCT FROM p_activity OR r.based_on_revision IS DISTINCT FROM p_expected_revision
  OR r.body_text IS DISTINCT FROM p_text OR r.recorded_by_auth_user_id IS DISTINCT FROM auth.uid()
  THEN RAISE EXCEPTION 'changed answer request' USING ERRCODE='23505'; END IF;
  RETURN atlas.private_study_answer_receipt_v1(r);
 END IF;
 SELECT coalesce(max(revision_no),0) INTO n FROM atlas.teaching_course_private_study_answer_revisions
 WHERE invitation_id=p_invitation AND unit_id=p_unit AND snapshot_id=p_snapshot
 AND unit_revision_id=p_unit_revision AND activity_id=p_activity AND learner_person_entity_id=v_person;
 IF n<>p_expected_revision THEN RAISE EXCEPTION 'stale answer revision' USING ERRCODE='40001'; END IF;
 INSERT INTO atlas.teaching_course_private_study_answer_revisions(invitation_id,unit_id,snapshot_id,unit_revision_id,activity_id,
 learner_person_entity_id,recorded_by_auth_user_id,request_id,based_on_revision,revision_no,body_text)
 VALUES(p_invitation,p_unit,p_snapshot,p_unit_revision,p_activity,v_person,auth.uid(),p_request,n,n+1,p_text)
 RETURNING * INTO r;
 RETURN atlas.private_study_answer_receipt_v1(r);
END $$;
REVOKE ALL ON FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid),
 public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_private_study_answer_read_self_api_v1(uuid,uuid,uuid,uuid,uuid),
 public.shared_teaching_private_study_answer_save_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid,integer,text)
 TO authenticated;

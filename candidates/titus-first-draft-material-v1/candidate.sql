-- Titus blank-product first authoring operation: ONE private Course material body.
-- SOURCE-ONLY CANDIDATE. Not a migration; no direct application to Noel production.
-- Builds on already released Titus customer workspace/course/entitlement source v1.
-- Source-issued active entitlement + current confirmed live Auth session required
-- on EVERY operation. Caller may identify one Course; never supply owner/Person.
-- Course draft is not an Offering, class, teacher appointment or published lesson.
-- Append-only original and revisions; no fixed modules or seed curriculum.
BEGIN;

CREATE TABLE titus.customer_course_material_revisions_v1(
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 course_id uuid NOT NULL REFERENCES titus.customer_course_drafts_v1(course_id)
   ON DELETE RESTRICT,
 edit_request_id uuid NOT NULL,
 based_on_revision integer NOT NULL CHECK(based_on_revision>=0),
 revision_number integer NOT NULL CHECK(revision_number>0),
 body_text text NOT NULL CHECK(char_length(body_text)<=40000),
 recorded_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id)
   ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT titus_material_revision_sequence_v1
   CHECK(revision_number=based_on_revision+1),
 CONSTRAINT titus_material_request_per_course_v1
   UNIQUE(course_id,edit_request_id),
 CONSTRAINT titus_material_revision_per_course_v1
   UNIQUE(course_id,revision_number)
);
CREATE INDEX titus_material_latest_by_course_v1
 ON titus.customer_course_material_revisions_v1(course_id,revision_number DESC);
ALTER TABLE titus.customer_course_material_revisions_v1 ENABLE ROW LEVEL SECURITY;

-- No direct owner/anon/service access. All reads and writes via narrow signed
-- functions, including when a client knows a UUID from an old session.
REVOKE ALL ON TABLE titus.customer_course_material_revisions_v1 FROM PUBLIC;
DO $revoke$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  REVOKE ALL ON TABLE titus.customer_course_material_revisions_v1 FROM authenticated;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  REVOKE ALL ON TABLE titus.customer_course_material_revisions_v1 FROM anon;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
  REVOKE ALL ON TABLE titus.customer_course_material_revisions_v1 FROM service_role;
 END IF;
END; $revoke$;

-- Current session and entitlement through the released Titus source helper.
-- Returned content is only for one Course in the current owner's workspace.
-- A missing or another buyer's ID is the same denial (no title disclosure).
CREATE FUNCTION public.titus_customer_material_read_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog
AS $read$
DECLARE
 v_user uuid;
 v_course titus.customer_course_drafts_v1%ROWTYPE;
 v_revision titus.customer_course_material_revisions_v1%ROWTYPE;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_course_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 SELECT c.* INTO v_course
 FROM titus.customer_course_drafts_v1 c
 JOIN titus.customer_workspaces_v1 w ON w.workspace_id=c.workspace_id
 WHERE c.course_id=p_course_id AND w.owner_auth_user_id=v_user;
 IF v_course.course_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 SELECT r.* INTO v_revision
 FROM titus.customer_course_material_revisions_v1 r
 WHERE r.course_id=v_course.course_id
 ORDER BY r.revision_number DESC LIMIT 1;
 RETURN jsonb_build_object(
  'contractVersion','titus_customer_material_v1',
  'courseId',v_course.course_id,
  'material',CASE WHEN v_revision.revision_id IS NULL THEN NULL ELSE
   jsonb_build_object(
    'revisionId',v_revision.revision_id,
    'revisionNumber',v_revision.revision_number,
    'text',v_revision.body_text,
    'savedAt',v_revision.recorded_at
   ) END
 );
END;
$read$;

-- Revision write: same confirmed owner, unique idempotency, locked workspace,
-- exact expected revision, no overwrite/deletion, no learner publication.
-- Existing material can be revised without hardcoded lessons/modules.
CREATE FUNCTION public.titus_customer_material_save_self_api_v1(
 p_course_id uuid,p_request_id uuid,p_expected_revision integer,p_text text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog
AS $save$
DECLARE
 v_user uuid;
 v_workspace titus.customer_workspaces_v1%ROWTYPE;
 v_course titus.customer_course_drafts_v1%ROWTYPE;
 v_existing titus.customer_course_material_revisions_v1%ROWTYPE;
 v_latest integer;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_course_id IS NULL OR p_request_id IS NULL OR p_text IS NULL
   OR p_expected_revision IS NULL OR p_expected_revision<0
   OR p_expected_revision>=10000 OR char_length(p_text)>40000 THEN
  RAISE EXCEPTION 'Invalid Course material write' USING ERRCODE='22023';
 END IF;
 -- A single owner/workspace lock serializes every revision for that owner.
 SELECT * INTO v_workspace FROM titus.customer_workspaces_v1
 WHERE owner_auth_user_id=v_user FOR UPDATE;
 IF v_workspace.workspace_id IS NULL OR v_workspace.state<>'active' THEN
  RAISE EXCEPTION 'Active owned workspace required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_course FROM titus.customer_course_drafts_v1
 WHERE course_id=p_course_id AND workspace_id=v_workspace.workspace_id;
 IF v_course.course_id IS NULL THEN
  RAISE EXCEPTION 'Owned Course required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_existing FROM titus.customer_course_material_revisions_v1
 WHERE course_id=v_course.course_id AND edit_request_id=p_request_id;
 IF v_existing.revision_id IS NOT NULL THEN
  IF v_existing.based_on_revision IS DISTINCT FROM p_expected_revision
    OR v_existing.body_text IS DISTINCT FROM p_text THEN
   RAISE EXCEPTION 'Material request conflicts with earlier original'
    USING ERRCODE='23505';
  END IF;
  RETURN public.titus_customer_material_read_self_api_v1(v_course.course_id);
 END IF;
 SELECT coalesce(max(revision_number),0) INTO v_latest
 FROM titus.customer_course_material_revisions_v1
 WHERE course_id=v_course.course_id;
 IF v_latest<>p_expected_revision THEN
  RAISE EXCEPTION 'Material revision is out of date' USING ERRCODE='40001';
 END IF;
 INSERT INTO titus.customer_course_material_revisions_v1(
   course_id,edit_request_id,based_on_revision,revision_number,body_text,
   recorded_by_auth_user_id
 ) VALUES(
   v_course.course_id,p_request_id,v_latest,v_latest+1,p_text,v_user
 );
 RETURN public.titus_customer_material_read_self_api_v1(v_course.course_id);
END;
$save$;

REVOKE ALL ON FUNCTION public.titus_customer_material_read_self_api_v1(uuid)
 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)
 FROM PUBLIC;
DO $api_privs$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  GRANT EXECUTE ON FUNCTION public.titus_customer_material_read_self_api_v1(uuid)
   TO authenticated;
  GRANT EXECUTE ON FUNCTION public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)
   TO authenticated;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  REVOKE ALL ON FUNCTION public.titus_customer_material_read_self_api_v1(uuid)
   FROM anon;
  REVOKE ALL ON FUNCTION public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)
   FROM anon;
 END IF;
 -- Supabase's public-function default ACL separately grants EXECUTE to
 -- service_role. Revoking PUBLIC does not withdraw that direct grant.
 -- These signed-owner RPCs are for authenticated users, not service-role transport.
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
  REVOKE ALL ON FUNCTION public.titus_customer_material_read_self_api_v1(uuid)
   FROM service_role;
  REVOKE ALL ON FUNCTION public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)
   FROM service_role;
 END IF;
END; $api_privs$;
COMMIT;

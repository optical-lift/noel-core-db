-- Titus customer software: blank workspace and first draft Course. SOURCE ONLY.
-- 2026-11-04. Not a migration; never apply directly to the shared live database.
-- No courses, students, user IDs, entitlements or research bodies are seeded.
-- Do not mistake these private customer draft Courses for existing titus.courses,
-- Atlas Teaching Course/Offering or released Titus Formation curriculum.
-- Explicit signed-owner authorization on every call; no actor/workspace id
-- accepted from browser JSON. Public SECURITY DEFINER RPCs are deliberately
-- narrow and executable only by authenticated; source reviewers must check
-- the privileged boundary before any governed release.
BEGIN;

CREATE TABLE titus.customer_workspaces_v1(
  workspace_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id)
    ON DELETE RESTRICT,
  title text NOT NULL DEFAULT 'My university'
    CHECK(title=btrim(title) AND length(title) BETWEEN 1 AND 120),
  state text NOT NULL DEFAULT 'active'
    CHECK(state IN ('active','suspended')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE titus.customer_course_drafts_v1(
  course_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES titus.customer_workspaces_v1(workspace_id)
    ON DELETE RESTRICT,
  created_by_auth_user_id uuid NOT NULL REFERENCES auth.users(id)
    ON DELETE RESTRICT,
  create_request_id uuid NOT NULL,
  title text NOT NULL
    CHECK(title=btrim(title) AND length(title) BETWEEN 1 AND 150),
  state text NOT NULL DEFAULT 'draft' CHECK(state='draft'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT customer_course_request_scoped_v1 UNIQUE(workspace_id,create_request_id)
);
CREATE INDEX customer_course_drafts_by_workspace_v1
  ON titus.customer_course_drafts_v1(workspace_id,created_at,course_id);

-- A verified Auth login is NOT a Titus purchase. Zero grants are deployed.
-- Issuance/revocation must later be a separately authorized source operation
-- after a genuine payment or explicit private-pilot owner approval.
CREATE TABLE titus.customer_workspace_entitlements_v1(
  owner_auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id)
    ON DELETE RESTRICT,
  grant_kind text NOT NULL
    CHECK(grant_kind IN ('private_pilot','purchase')),
  grant_source_receipt text NOT NULL UNIQUE
    CHECK(grant_source_receipt=btrim(grant_source_receipt)
      AND length(grant_source_receipt) BETWEEN 8 AND 200),
  state text NOT NULL DEFAULT 'active'
    CHECK(state IN ('active','suspended','revoked')),
  granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  valid_until timestamptz,
  CHECK(valid_until IS NULL OR valid_until>granted_at)
);
ALTER TABLE titus.customer_workspaces_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.customer_course_drafts_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.customer_workspace_entitlements_v1 ENABLE ROW LEVEL SECURITY;
-- No table-level access for end users: only guarded, narrow source RPCs.
REVOKE ALL ON TABLE titus.customer_workspaces_v1,
 titus.customer_course_drafts_v1,
 titus.customer_workspace_entitlements_v1 FROM PUBLIC;
DO $privs$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
   REVOKE ALL ON TABLE titus.customer_workspaces_v1,
    titus.customer_course_drafts_v1,
    titus.customer_workspace_entitlements_v1 FROM authenticated;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
   REVOKE ALL ON TABLE titus.customer_workspaces_v1,
    titus.customer_course_drafts_v1,
    titus.customer_workspace_entitlements_v1 FROM anon;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN
   REVOKE ALL ON TABLE titus.customer_workspaces_v1,
    titus.customer_course_drafts_v1,
    titus.customer_workspace_entitlements_v1 FROM service_role;
 END IF;
END; $privs$;

-- This is Titus-specific buyer authentication, independent of Atlas
-- Teaching capability, Atlas Person, School Ledger, learner, or enrollment.
-- PostgREST verifies the JWT cryptographically before setting auth claims.
-- Recheck the current confirmed user/session AND a source-issued entitlement.
-- A fresh signed Atlas OAuth identity alone is NOT a Titus purchase.
CREATE FUNCTION titus.customer_current_auth_user_v1()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog
AS $auth$
DECLARE v_user uuid:=auth.uid();
BEGIN
 IF v_user IS NULL OR NOT EXISTS(
   SELECT 1 FROM auth.users u
   JOIN auth.sessions s ON s.user_id=u.id
   WHERE u.id=v_user AND u.deleted_at IS NULL
     AND (u.email_confirmed_at IS NOT NULL OR u.phone_confirmed_at IS NOT NULL)
     AND NOT coalesce(u.is_anonymous,false)
     AND (u.banned_until IS NULL OR u.banned_until<=now())
     AND s.id::text=auth.jwt()->>'session_id'
     AND (s.not_after IS NULL OR s.not_after>now())
 ) THEN
   RAISE EXCEPTION 'Current confirmed Titus Auth session required'
    USING ERRCODE='42501';
 END IF;
 -- Authentication cannot create a purchase or private-pilot invitation.
 -- Every catalog access must have a separately issued active entitlement.
 IF NOT EXISTS(
   SELECT 1 FROM titus.customer_workspace_entitlements_v1 e
   WHERE e.owner_auth_user_id=v_user AND e.state='active'
     AND (e.valid_until IS NULL OR e.valid_until>now())
 ) THEN
   RAISE EXCEPTION 'Active Titus customer entitlement required'
     USING ERRCODE='42501';
 END IF;
 RETURN v_user;
END;
$auth$;
REVOKE ALL ON FUNCTION titus.customer_current_auth_user_v1()
 FROM PUBLIC;

-- A catalog read NEVER invents a Course or initializes a workspace.
-- A new signed buyer correctly receives workspace:null and courses:[].
CREATE FUNCTION public.titus_customer_catalog_self_api_v1()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog
AS $catalog$
DECLARE v_user uuid;v_workspace titus.customer_workspaces_v1%ROWTYPE;
        v_courses jsonb;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 SELECT * INTO v_workspace
 FROM titus.customer_workspaces_v1
 WHERE owner_auth_user_id=v_user;
 IF v_workspace.workspace_id IS NULL THEN
   RETURN jsonb_build_object('contractVersion','titus_customer_catalog_v1',
    'workspace',NULL,'courses','[]'::jsonb);
 END IF;
 -- No caller-provided tenant or workspace ID. Never enumerate other buyers.
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'courseId',c.course_id,'title',c.title,'state',c.state,
  'createdAt',c.created_at
 ) ORDER BY c.created_at,c.course_id),'[]'::jsonb) INTO v_courses
 FROM titus.customer_course_drafts_v1 c
 WHERE c.workspace_id=v_workspace.workspace_id;
 RETURN jsonb_build_object(
  'contractVersion','titus_customer_catalog_v1',
  'workspace',jsonb_build_object(
    'workspaceId',v_workspace.workspace_id,'title',v_workspace.title,
    'state',v_workspace.state),
  'courses',v_courses);
END;
$catalog$;

-- An explicit owner action creates a workspace, which may have zero Courses.
-- A repeated request cannot create a second workspace for this same user.
CREATE FUNCTION public.titus_customer_start_workspace_self_api_v1(p_title text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog
AS $start$
DECLARE v_user uuid;v_title text:=btrim(coalesce(p_title,''));
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF length(v_title) NOT BETWEEN 1 AND 120 THEN
  RAISE EXCEPTION 'University title must be 1 to 120 characters'
    USING ERRCODE='22023';
 END IF;
 INSERT INTO titus.customer_workspaces_v1(owner_auth_user_id,title)
 VALUES(v_user,v_title)
 ON CONFLICT (owner_auth_user_id) DO NOTHING;
 RETURN public.titus_customer_catalog_self_api_v1();
END;
$start$;

-- An explicit owner action creates one new, unpublished original draft Course.
-- It never opens a Teaching Offering, publishes curriculum or enrolls a Person.
-- The UUID request ID is idempotent within this workspace; reusing a key
-- in a separate customer's workspace is a distinct authorized original.
CREATE FUNCTION public.titus_customer_create_course_self_api_v1(
 p_request_id uuid,p_title text
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog
AS $create$
DECLARE v_user uuid;v_workspace titus.customer_workspaces_v1%ROWTYPE;
        v_title text:=btrim(coalesce(p_title,''));
        v_previous titus.customer_course_drafts_v1%ROWTYPE;
        v_count integer;
BEGIN
 v_user:=titus.customer_current_auth_user_v1();
 IF p_request_id IS NULL OR length(v_title) NOT BETWEEN 1 AND 150 THEN
  RAISE EXCEPTION 'Valid request ID and Course title required'
    USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_workspace FROM titus.customer_workspaces_v1
 WHERE owner_auth_user_id=v_user FOR UPDATE;
 IF v_workspace.workspace_id IS NULL OR v_workspace.state<>'active' THEN
  RAISE EXCEPTION 'An active owned workspace is required'
    USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_previous FROM titus.customer_course_drafts_v1
 WHERE workspace_id=v_workspace.workspace_id AND create_request_id=p_request_id;
 IF v_previous.course_id IS NOT NULL THEN
   IF v_previous.title IS DISTINCT FROM v_title THEN
     RAISE EXCEPTION 'Course request conflicts with prior original'
       USING ERRCODE='23505';
   END IF;
   RETURN public.titus_customer_catalog_self_api_v1();
 END IF;
 SELECT count(*) INTO v_count FROM titus.customer_course_drafts_v1
 WHERE workspace_id=v_workspace.workspace_id;
 IF v_count>=100 THEN
   RAISE EXCEPTION 'Workspace Course limit reached'
     USING ERRCODE='22023';
 END IF;
 INSERT INTO titus.customer_course_drafts_v1(
    workspace_id,created_by_auth_user_id,create_request_id,title)
 VALUES(v_workspace.workspace_id,v_user,p_request_id,v_title);
 RETURN public.titus_customer_catalog_self_api_v1();
END;
$create$;

-- A privileged public RPC must not be callable by implicit PUBLIC/anon grants.
REVOKE ALL ON FUNCTION public.titus_customer_catalog_self_api_v1()
 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.titus_customer_start_workspace_self_api_v1(text)
 FROM PUBLIC;
REVOKE ALL ON FUNCTION public.titus_customer_create_course_self_api_v1(uuid,text)
 FROM PUBLIC;
DO $rpc_grants$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  GRANT EXECUTE ON FUNCTION public.titus_customer_catalog_self_api_v1()
   TO authenticated;
  GRANT EXECUTE ON FUNCTION public.titus_customer_start_workspace_self_api_v1(text)
   TO authenticated;
  GRANT EXECUTE ON FUNCTION public.titus_customer_create_course_self_api_v1(uuid,text)
   TO authenticated;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  REVOKE ALL ON FUNCTION public.titus_customer_catalog_self_api_v1()
   FROM anon;
  REVOKE ALL ON FUNCTION public.titus_customer_start_workspace_self_api_v1(text)
   FROM anon;
  REVOKE ALL ON FUNCTION public.titus_customer_create_course_self_api_v1(uuid,text)
   FROM anon;
 END IF;
END; $rpc_grants$;
COMMIT;

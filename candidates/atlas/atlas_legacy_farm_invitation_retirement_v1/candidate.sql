-- SOURCE ONLY / HELD: retirement candidate, NOT authorization for live use.
-- UNRESOLVED EXTERNAL-CALLER GATE: optical-lift/farm-atlas still has owner
-- invite draft/send/revoke API handlers in its main source. Its actual
-- deployed reachability and cutover must be proved independently.
-- Canonical newer Atlas uses Organization-access invitation API instead.
-- No existing historical invite row may be discarded. No member row moves.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $legacy_farm_invites_pre$
DECLARE
  r record;
  v_oid oid;
  v_list_oid oid := to_regprocedure('atlas.owner_list_farm_members_v1(uuid)');
BEGIN
  IF to_regclass('atlas.farm_membership_invites') IS NULL
     OR to_regclass('atlas.farm_memberships') IS NULL
     OR to_regclass('atlas.organization_memberships') IS NULL
     OR to_regclass('atlas.organization_access_invitations') IS NULL
     OR to_regclass('atlas.tasks') IS NULL
     OR to_regclass('atlas.work_items') IS NULL
     OR to_regclass('atlas.work_requirements') IS NULL
     OR to_regclass('atlas.task_release_queue_items') IS NULL
     OR v_list_oid IS NULL THEN
    RAISE EXCEPTION 'Original invitation, membership, or Work source missing';
  END IF;
  IF EXISTS (SELECT 1 FROM atlas.farm_membership_invites) THEN
    RAISE EXCEPTION 'Legacy invitation source contains rows; adjudicate in original custody before any retirement';
  END IF;
  IF md5(pg_get_functiondef(v_list_oid))
     IS DISTINCT FROM 'f573e800606afcc2023cf1354922c741'
     OR NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=v_list_oid
       AND p.proowner='postgres'::regrole AND p.prosecdef
       AND has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) THEN
    RAISE EXCEPTION 'Original live membership-list source or ACL changed; stop';
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('accept_membership_invite_v1'::text,'uuid'::text,'2c8ebcc5e52ad26cd782803b5a2833d4'::text),
    ('owner_get_membership_invite_v1'::text,'uuid,uuid'::text,'64878bf1ead1050c3c393bbb845540a1'::text),
    ('owner_mark_membership_invite_error_v1'::text,'uuid,uuid,text'::text,'eb8047176b2c2464d2a0cc7452fef62c'::text),
    ('owner_mark_membership_invite_sent_v1'::text,'uuid,uuid,uuid'::text,'47f8bd0ad9ebba945a3f54c838319244'::text),
    ('owner_prepare_membership_invite_v1'::text,'uuid,text,text,text,text'::text,'6e79c5aa753b8bcdd1c02296aff0c5c2'::text),
    ('owner_revoke_membership_invite_v1'::text,'uuid,uuid'::text,'772c76184cd857afb91f160c23f9afc6'::text),
    ('pending_membership_invite_for_current_user_v1'::text,'uuid'::text,'273db6390b95a55d60532272f64cd042'::text)
  ) AS expected(proname,args,source_md5) LOOP
    v_oid := to_regprocedure('atlas.'||r.proname||'('||r.args||')');
    IF v_oid IS NULL OR md5(pg_get_functiondef(v_oid)) IS DISTINCT FROM r.source_md5 THEN
      RAISE EXCEPTION 'Legacy invitation function source missing or changed: %',r.proname;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=v_oid
       AND p.proowner='postgres'::regrole AND p.prosecdef
       AND has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
       AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')) THEN
      RAISE EXCEPTION 'Original invitation function ACL/owner changed: %',r.proname;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgfoid=v_oid AND NOT t.tgisinternal)
       OR EXISTS (SELECT 1 FROM pg_depend d WHERE d.refobjid=v_oid AND d.deptype='n')
       OR EXISTS (SELECT 1 FROM cron.job j WHERE lower(j.command) LIKE '%'||r.proname||'%')
       OR EXISTS (
         SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE p.oid<>v_oid AND p.prokind IN ('f','p')
         AND n.nspname NOT IN('pg_catalog','information_schema')
         AND n.nspname NOT LIKE 'pg_toast%'
         AND position(r.proname IN lower(pg_get_functiondef(p.oid)))>0
       ) THEN
      RAISE EXCEPTION 'Invitation function now has dependent caller: %',r.proname;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_constraint
       WHERE confrelid='atlas.farm_membership_invites'::regclass)
     OR EXISTS (SELECT 1 FROM pg_trigger
       WHERE tgrelid='atlas.farm_membership_invites'::regclass AND NOT tgisinternal)
     OR EXISTS (SELECT 1 FROM pg_publication_tables
       WHERE schemaname='atlas' AND tablename='farm_membership_invites')
     OR EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE c.relkind IN ('v','m')
         AND n.nspname NOT IN ('pg_catalog','information_schema')
         AND lower(pg_get_viewdef(c.oid,true)) LIKE '%farm_membership_invites%')
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE p.prokind IN('f','p') AND n.nspname NOT IN('pg_catalog','information_schema')
       AND n.nspname NOT LIKE 'pg_toast%'
       AND position('farm_membership_invites' IN lower(pg_get_functiondef(p.oid)))>0
       AND p.proname NOT IN (
        'accept_membership_invite_v1','owner_get_membership_invite_v1',
        'owner_mark_membership_invite_error_v1','owner_mark_membership_invite_sent_v1',
        'owner_prepare_membership_invite_v1','owner_revoke_membership_invite_v1',
        'pending_membership_invite_for_current_user_v1','owner_list_farm_members_v1'))
  THEN
    RAISE EXCEPTION 'Legacy invitation table has an unadjudicated SQL reader or dependency';
  END IF;
  PERFORM set_config('atlas.invites_farm_members_before',
    (SELECT count(*)::text FROM atlas.farm_memberships),true);
  PERFORM set_config('atlas.invites_org_members_before',
    (SELECT count(*)::text FROM atlas.organization_memberships),true);
  PERFORM set_config('atlas.invites_org_invites_before',
    (SELECT count(*)::text FROM atlas.organization_access_invitations),true);
  PERFORM set_config('atlas.invites_tasks_before',
    (SELECT count(*)::text FROM atlas.tasks),true);
  PERFORM set_config('atlas.invites_work_before',
    (SELECT count(*)::text FROM atlas.work_items),true);
  PERFORM set_config('atlas.invites_requirements_before',
    (SELECT count(*)::text FROM atlas.work_requirements),true);
  PERFORM set_config('atlas.invites_queue_before',
    (SELECT count(*)::text FROM atlas.task_release_queue_items),true);
END $legacy_farm_invites_pre$;

-- The historical farm member-list reader has REAL existing member rows.
-- Preserve the exact authenticated owner-only member list/return signature,
-- but remove its empty invitation-list UNION before dropping its dead table.
-- This is an OLD APP source bridge, NOT canonical universal membership.
CREATE OR REPLACE FUNCTION atlas.owner_list_farm_members_v1(p_farm_id uuid)
RETURNS TABLE(record_kind text,record_id uuid,user_id uuid,email text,
 display_name text,role text,worker_key text,active boolean,status text,
 created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth'
AS $member_list$
BEGIN
  IF NOT atlas.is_farm_owner(p_farm_id) THEN
    RAISE EXCEPTION 'Owner membership required.' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT 'membership'::text,fm.id,fm.user_id,au.email::text,
    COALESCE(up.display_name,au.email,'Atlas user')::text,
    fm.role,fm.worker_key,fm.active,
    CASE WHEN fm.active THEN 'active' ELSE 'inactive' END::text,
    fm.created_at
  FROM atlas.farm_memberships fm
  JOIN auth.users au ON au.id=fm.user_id
  LEFT JOIN atlas.user_profiles up ON up.user_id=fm.user_id
  WHERE fm.farm_id=p_farm_id
  ORDER BY 10 DESC, 5;
END $member_list$;

-- Only the seven old invitation-only RPCs; no CASCADE.
DROP FUNCTION atlas.accept_membership_invite_v1(uuid) RESTRICT;
DROP FUNCTION atlas.owner_get_membership_invite_v1(uuid,uuid) RESTRICT;
DROP FUNCTION atlas.owner_mark_membership_invite_error_v1(uuid,uuid,text) RESTRICT;
DROP FUNCTION atlas.owner_mark_membership_invite_sent_v1(uuid,uuid,uuid) RESTRICT;
DROP FUNCTION atlas.owner_prepare_membership_invite_v1(uuid,text,text,text,text) RESTRICT;
DROP FUNCTION atlas.owner_revoke_membership_invite_v1(uuid,uuid) RESTRICT;
DROP FUNCTION atlas.pending_membership_invite_for_current_user_v1(uuid) RESTRICT;
DROP TABLE atlas.farm_membership_invites RESTRICT;

DO $legacy_farm_invites_post$
BEGIN
  IF to_regclass('atlas.farm_membership_invites') IS NOT NULL
     OR to_regprocedure('atlas.accept_membership_invite_v1(uuid)') IS NOT NULL
     OR to_regprocedure('atlas.owner_prepare_membership_invite_v1(uuid,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('atlas.pending_membership_invite_for_current_user_v1(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='atlas' AND p.proname IN (
          'owner_get_membership_invite_v1','owner_mark_membership_invite_error_v1',
          'owner_mark_membership_invite_sent_v1','owner_revoke_membership_invite_v1')) THEN
    RAISE EXCEPTION 'Old invitation-specific table or RPCs remain after retirement';
  END IF;
  IF to_regprocedure('atlas.owner_list_farm_members_v1(uuid)') IS NULL
     OR position('farm_membership_invites' IN lower(pg_get_functiondef(
        to_regprocedure('atlas.owner_list_farm_members_v1(uuid)'))))>0
     OR NOT has_function_privilege('authenticated',
        to_regprocedure('atlas.owner_list_farm_members_v1(uuid)'),'EXECUTE')
     OR has_function_privilege('anon',
        to_regprocedure('atlas.owner_list_farm_members_v1(uuid)'),'EXECUTE') THEN
    RAISE EXCEPTION 'Original authorized member-list read or its permissions changed';
  END IF;
  IF (SELECT count(*)::text FROM atlas.farm_memberships)
        IS DISTINCT FROM current_setting('atlas.invites_farm_members_before')
     OR (SELECT count(*)::text FROM atlas.organization_memberships)
        IS DISTINCT FROM current_setting('atlas.invites_org_members_before')
     OR (SELECT count(*)::text FROM atlas.organization_access_invitations)
        IS DISTINCT FROM current_setting('atlas.invites_org_invites_before')
     OR (SELECT count(*)::text FROM atlas.tasks)
        IS DISTINCT FROM current_setting('atlas.invites_tasks_before')
     OR (SELECT count(*)::text FROM atlas.work_items)
        IS DISTINCT FROM current_setting('atlas.invites_work_before')
     OR (SELECT count(*)::text FROM atlas.work_requirements)
        IS DISTINCT FROM current_setting('atlas.invites_requirements_before')
     OR (SELECT count(*)::text FROM atlas.task_release_queue_items)
        IS DISTINCT FROM current_setting('atlas.invites_queue_before') THEN
    RAISE EXCEPTION 'Unrelated membership, Task, Work, Requirement or queue rows changed';
  END IF;
END $legacy_farm_invites_post$;
COMMIT;

-- SCRATCH ONLY: uses prior fictional Auth fixture and the released customer
-- source candidate, then the new held material candidate.
-- This cannot establish real GoTrue-signed acceptance or release privileges.
DO $schema_checks$ BEGIN
 IF (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>0 THEN
  RAISE EXCEPTION 'Content was seeded into a blank product';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='titus' AND c.relname='customer_course_material_revisions_v1'
                 AND c.relrowsecurity) THEN
  RAISE EXCEPTION 'No material RLS';
 END IF;
 IF has_table_privilege('authenticated','titus.customer_course_material_revisions_v1','SELECT')
    OR has_table_privilege('authenticated','titus.customer_course_material_revisions_v1','INSERT')
    OR has_table_privilege('service_role','titus.customer_course_material_revisions_v1','SELECT')
    OR has_table_privilege('anon','titus.customer_course_material_revisions_v1','SELECT')
    OR has_function_privilege('anon','public.titus_customer_material_read_self_api_v1(uuid)','EXECUTE')
    OR has_function_privilege('anon','public.titus_customer_material_save_self_api_v1(uuid,uuid,integer,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Material permissions leaked'; END IF;
END $schema_checks$;

-- A signed-shaped but unentitled person is denied all content operations.
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $no_grant$ BEGIN
 BEGIN
  PERFORM public.titus_customer_material_read_self_api_v1(
    '00000000-0000-4000-8000-000000000401');
  RAISE EXCEPTION 'Unentitled material read succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
    '00000000-0000-4000-8000-000000000401',
    '00000000-0000-4000-8000-000000000501',0,'wrong');
  RAISE EXCEPTION 'Unentitled material write succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $no_grant$;
RESET ROLE;

-- Fictional grants exist in TEST FIXTURE ONLY, never in source candidate.
INSERT INTO titus.customer_workspace_entitlements_v1(
 owner_auth_user_id,grant_kind,grant_source_receipt
) VALUES
 ('00000000-0000-4000-8000-000000000101','private_pilot','fictional-material-pilot-a'),
 ('00000000-0000-4000-8000-000000000102','private_pilot','fictional-material-pilot-b');

SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $owner_a$
DECLARE v jsonb; v_course uuid;
BEGIN
 v:=public.titus_customer_start_workspace_self_api_v1('No sample course university');
 IF v->'courses' <> '[]'::jsonb THEN RAISE EXCEPTION 'Workspace was seeded'; END IF;
 v:=public.titus_customer_create_course_self_api_v1(
  '00000000-0000-4000-8000-000000000301','Original Research');
 v_course:=(v->'courses'->0->>'courseId')::uuid;
 v:=public.titus_customer_material_read_self_api_v1(v_course);
 IF v->>'contractVersion'<>'titus_customer_material_v1'
    OR v->'material' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'Blank Course must contain zero content revisions';
 END IF;
 v:=public.titus_customer_material_save_self_api_v1(
  v_course,'00000000-0000-4000-8000-000000000501',0,
  'First notes without any required lesson format');
 IF v->'material'->>'text'<>'First notes without any required lesson format'
     OR (v->'material'->>'revisionNumber')::integer<>1 THEN
  RAISE EXCEPTION 'First original material did not save';
 END IF;
 -- Exact replay must not duplicate the original.
 v:=public.titus_customer_material_save_self_api_v1(
  v_course,'00000000-0000-4000-8000-000000000501',0,
  'First notes without any required lesson format');
 IF (v->'material'->>'revisionNumber')::integer<>1 THEN
  RAISE EXCEPTION 'Replay changed content revision';
 END IF;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000501',0,'Changed replay');
  RAISE EXCEPTION 'Conflicting replay allowed';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000502',0,'Stale edit');
  RAISE EXCEPTION 'Stale write accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 v:=public.titus_customer_material_save_self_api_v1(
  v_course,'00000000-0000-4000-8000-000000000503',1,
  'Revised original notes, prior version preserved');
 IF (v->'material'->>'revisionNumber')::integer<>2
    OR v->'material'->>'text'<>'Revised original notes, prior version preserved' THEN
  RAISE EXCEPTION 'Revision did not reopen';
 END IF;
 v:=public.titus_customer_material_read_self_api_v1(v_course);
 IF (v->'material'->>'revisionNumber')::integer<>2 THEN
  RAISE EXCEPTION 'Reopening did not return latest saved original';
 END IF;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000505',2,
   repeat('x',40001));
  RAISE EXCEPTION 'Overlong material accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $owner_a$;
RESET ROLE;

DO $history$ BEGIN
 IF (SELECT count(*) FROM titus.customer_course_material_revisions_v1)<>2 THEN
  RAISE EXCEPTION 'Revision history must have two append-only originals';
 END IF;
 IF EXISTS(SELECT 1 FROM titus.customer_course_material_revisions_v1
           WHERE revision_number=1 AND
             body_text<>'First notes without any required lesson format') THEN
  RAISE EXCEPTION 'Prior material was overwritten';
 END IF;
END $history$;
SELECT set_config('test.owner_a_course',(
 SELECT course_id::text FROM titus.customer_course_drafts_v1
 WHERE created_by_auth_user_id='00000000-0000-4000-8000-000000000101'
 LIMIT 1),false);

-- B has a valid separate grant but never gets A's material via its UUID.
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $outsider$
DECLARE v_course uuid:=current_setting('test.owner_a_course')::uuid;
BEGIN
 BEGIN
  PERFORM public.titus_customer_material_read_self_api_v1(v_course);
  RAISE EXCEPTION 'Outsider read other owner material';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000511',2,'Outsider write');
  RAISE EXCEPTION 'Outsider edited other owner material';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $outsider$;
RESET ROLE;

-- Independent control: B must be able to read/write B's OWN Course before
-- session expiration. Without this control, reading A's Course after expiry
-- would pass due to ownership denial alone, even if session checks regressed.
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $owner_b_active$
DECLARE v jsonb; v_course uuid;
BEGIN
 v:=public.titus_customer_start_workspace_self_api_v1('Independent fictional owner B');
 IF v->'courses' <> '[]'::jsonb THEN
  RAISE EXCEPTION 'Unrelated buyer must start with no seeded Courses';
 END IF;
 v:=public.titus_customer_create_course_self_api_v1(
   '00000000-0000-4000-8000-000000000302','Owner B private control');
 v_course:=(v->'courses'->0->>'courseId')::uuid;
 v:=public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000521',0,'Only B can access this private control');
 IF v->'material'->>'text'<>'Only B can access this private control' THEN
  RAISE EXCEPTION 'B active-session own-Course save failed';
 END IF;
 v:=public.titus_customer_material_read_self_api_v1(v_course);
 IF v->'material'->>'text'<>'Only B can access this private control' THEN
  RAISE EXCEPTION 'B active-session own-Course read failed';
 END IF;
END $owner_b_active$;
RESET ROLE;
SELECT set_config('test.owner_b_course',(
 SELECT course_id::text FROM titus.customer_course_drafts_v1
 WHERE created_by_auth_user_id='00000000-0000-4000-8000-000000000102'
 LIMIT 1),false);

-- Active user A loses all material access immediately after grant revocation.
UPDATE titus.customer_workspace_entitlements_v1 SET state='revoked'
 WHERE owner_auth_user_id='00000000-0000-4000-8000-000000000101';
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $revoked$
DECLARE v_course uuid:=current_setting('test.owner_a_course')::uuid;
BEGIN
 BEGIN
  PERFORM public.titus_customer_material_read_self_api_v1(v_course);
  RAISE EXCEPTION 'Revoked customer retained material';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000512',2,'Revoked write');
  RAISE EXCEPTION 'Revoked customer retained writer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $revoked$;
RESET ROLE;

-- B has a valid entitlement and known OWN Course; only its expired session
-- can explain this read/write denial. A foreign UUID alone was not a valid test.
UPDATE auth.sessions SET not_after=now()-interval '1 minute'
 WHERE id='00000000-0000-4000-8000-000000000202';
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $expired$
DECLARE v_course uuid:=current_setting('test.owner_b_course')::uuid;
BEGIN
 BEGIN
  PERFORM public.titus_customer_material_read_self_api_v1(v_course);
  RAISE EXCEPTION 'Expired session retained its OWN material reader';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_material_save_self_api_v1(
   v_course,'00000000-0000-4000-8000-000000000522',1,'Expired own-Course write');
  RAISE EXCEPTION 'Expired session retained its OWN material writer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $expired$;
RESET ROLE;
RESET request.jwt.claims;
RESET test.owner_a_course;
RESET test.owner_b_course;
SELECT 'PASS: source-auth first material, revisions, replay, stale denial, outsider, revoked, same-owner expired read/write, private grants (scratch-only)' as result;

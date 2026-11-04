-- Scratch-only acceptance: two fictional signed-shaped users, one empty
-- workspace, original draft, same-operation replay, outsider isolation,
-- withdrawal/expired session denial and private table privilege checks.
-- Claims in this test are NOT verified GoTrue bearer tokens.
DO $denial$ BEGIN
 IF has_function_privilege('anon',
   'public.titus_customer_catalog_self_api_v1()','EXECUTE') THEN
   RAISE EXCEPTION 'anon can invoke catalog';
 END IF;
 IF has_table_privilege('authenticated',
    'titus.customer_course_drafts_v1','SELECT')
    OR has_table_privilege('authenticated',
    'titus.customer_workspaces_v1','INSERT') THEN
   RAISE EXCEPTION 'private table grants leaked';
 END IF;
END; $denial$;

SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $owner_a$
DECLARE v jsonb;
BEGIN
 v:=public.titus_customer_catalog_self_api_v1();
 IF v->'workspace' IS DISTINCT FROM 'null'::jsonb OR
     v->'courses' IS DISTINCT FROM '[]'::jsonb THEN
   RAISE EXCEPTION 'new owner cannot read true empty catalog';
 END IF;
 v:=public.titus_customer_start_workspace_self_api_v1('First University');
 IF v->'workspace'->>'title'<>'First University' OR
    v->'courses' <> '[]'::jsonb THEN
   RAISE EXCEPTION 'workspace is not empty after first creation';
 END IF;
 v:=public.titus_customer_start_workspace_self_api_v1('Changed Name');
 IF v->'workspace'->>'title'<>'First University' THEN
   RAISE EXCEPTION 'repeated start rewrote original name';
 END IF;
 v:=public.titus_customer_create_course_self_api_v1(
   '00000000-0000-4000-8000-000000000301','History of Trees');
 IF jsonb_array_length(v->'courses')<>1 OR
    v->'courses'->0->>'title'<>'History of Trees' THEN
   RAISE EXCEPTION 'first owned draft not saved';
 END IF;
 v:=public.titus_customer_create_course_self_api_v1(
   '00000000-0000-4000-8000-000000000301','History of Trees');
 IF jsonb_array_length(v->'courses')<>1 THEN
   RAISE EXCEPTION 'same operation created duplicate course';
 END IF;
 BEGIN
   PERFORM public.titus_customer_create_course_self_api_v1(
    '00000000-0000-4000-8000-000000000301','Different Title');
   RAISE EXCEPTION 'conflicting replay was accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
END; $owner_a$;
RESET ROLE;

SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $owner_b$
DECLARE v jsonb;
BEGIN
 v:=public.titus_customer_catalog_self_api_v1();
 IF v->'workspace'<>'null'::jsonb OR
   jsonb_array_length(v->'courses')<>0 THEN
   RAISE EXCEPTION 'buyer B can read buyer A';
 END IF;
 BEGIN
   PERFORM public.titus_customer_create_course_self_api_v1(
     '00000000-0000-4000-8000-000000000302','Should fail');
   RAISE EXCEPTION 'buyer B created without a workspace';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 v:=public.titus_customer_start_workspace_self_api_v1('Second University');
 IF jsonb_array_length(v->'courses')<>0 OR
    v->'workspace'->>'title'<>'Second University' THEN
   RAISE EXCEPTION 'buyer B workspace creation failed';
 END IF;
 v:=public.titus_customer_create_course_self_api_v1(
   '00000000-0000-4000-8000-000000000302','Buyer B Course');
 IF jsonb_array_length(v->'courses')<>1 OR
    v->'courses'->0->>'title'<>'Buyer B Course' THEN
   RAISE EXCEPTION 'buyer B original missing';
 END IF;
END; $owner_b$;
RESET ROLE;
DO $counts$
BEGIN
 IF (SELECT count(*) FROM titus.customer_workspaces_v1)<>2 OR
    (SELECT count(*) FROM titus.customer_course_drafts_v1)<>2 THEN
   RAISE EXCEPTION 'wrong durable owner or course count';
 END IF;
END; $counts$;

-- Revocation must block even when a previously issued JWT claim remains.
UPDATE auth.sessions SET not_after=now()-interval '1 minute'
 WHERE id='00000000-0000-4000-8000-000000000202';
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $expired$
BEGIN
 BEGIN
   PERFORM public.titus_customer_catalog_self_api_v1();
   RAISE EXCEPTION 'expired session retained catalog read';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END; $expired$;
RESET ROLE;
RESET request.jwt.claims;

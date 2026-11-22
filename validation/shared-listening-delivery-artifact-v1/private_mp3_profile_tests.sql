-- HELD isolated PostgreSQL-only private MP3 delivery-profile proof.
-- Request JWT GUCs below are fictional and UNSIGNED: not a real GoTrue test.
-- The protected signed owner/editor/viewer/outsider clone remains a later gate.
BEGIN;
CREATE FUNCTION pg_temp.profile_expect_denial(p_statement text,p_expected text)
RETURNS void LANGUAGE plpgsql AS $denial$
BEGIN
  BEGIN
    EXECUTE p_statement;
    RAISE EXCEPTION 'Unapproved profile operation succeeded' USING ERRCODE='P0001';
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_expected THEN RAISE; END IF;
  END;
END $denial$;
CREATE FUNCTION pg_temp.profile_identity(
 p_user uuid,p_session uuid,
 p_anonymous boolean DEFAULT false,
 p_role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $identity$
BEGIN
  PERFORM set_config('test.listening_uid',p_user::text,true);
  PERFORM set_config('test.listening_claims',jsonb_build_object(
    'sub',p_user::text,'role',p_role,'session_id',p_session::text,
    'is_anonymous',p_anonymous,
    'exp',floor(extract(epoch from clock_timestamp()+interval '1 hour'))::bigint
  )::text,true);
END $identity$;

-- An already-existing conflicting version in a DIFFERENT workspace must not
-- be overwritten or adopted. This represents an incompatible source owner.
INSERT INTO transcript_core.delivery_profiles(
 id,workspace_id,profile_key,rule_version,display_name,configuration)
VALUES (
 '00000000-0000-0000-0000-000000002999',
 '00000000-0000-0000-0000-000000000002',
 'private_audiobook_mp3','native_private_mp3_v1',
 'Competing private profile','{}'::jsonb);

-- Exact role grants only; source table remains private even to service_role.
DO $acl$
BEGIN
  IF NOT has_function_privilege('authenticated',
      'public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)','EXECUTE')
    OR has_function_privilege('anon',
      'public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)','EXECUTE')
    OR has_function_privilege('service_role',
      'public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)','EXECUTE')
    OR has_table_privilege('authenticated','transcript_core.delivery_profiles','SELECT')
    OR has_table_privilege('authenticated','transcript_core.delivery_profiles','INSERT')
    OR has_table_privilege('service_role','transcript_core.delivery_profiles','SELECT')
  THEN RAISE EXCEPTION 'Profile ACL boundary changed'; END IF;
END $acl$;

SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001101',
 '00000000-0000-0000-0000-000000002101');
SET LOCAL ROLE anon;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');
RESET ROLE;

-- The real signed source editor sees no profile until one is established.
SET LOCAL ROLE authenticated;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',false)','42501');
DO $owner$
DECLARE a jsonb; b jsonb; c jsonb;
BEGIN
  a:=public.transcript_core_private_mp3_profile_self_api_v1(
    '00000000-0000-0000-0000-000000000001',true);
  b:=public.transcript_core_private_mp3_profile_self_api_v1(
    '00000000-0000-0000-0000-000000000001',true);
  c:=public.transcript_core_private_mp3_profile_self_api_v1(
    '00000000-0000-0000-0000-000000000001',false);
  IF a IS DISTINCT FROM b OR b IS DISTINCT FROM c
    OR a->>'contractVersion' IS DISTINCT FROM 'transcript_core_private_mp3_profile_v1'
    OR a->>'workspaceId' IS DISTINCT FROM '00000000-0000-0000-0000-000000000001'
    OR a->>'profileKey' IS DISTINCT FROM 'private_audiobook_mp3'
    OR a->>'ruleVersion' IS DISTINCT FROM 'native_private_mp3_v1'
    OR a->'publication_approved' IS DISTINCT FROM 'false'::jsonb
    OR a->'configuration'->>'codec' IS DISTINCT FROM 'libmp3lame'
    OR a->'configuration'->>'bitrate' IS DISTINCT FROM '128k'
  THEN RAISE EXCEPTION 'Idempotent source-owned profile receipt mismatch'; END IF;
END $owner$;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000002'',true)','23505');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(NULL::uuid,true)','22023');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',NULL::boolean)','22023');

-- Viewer, outsider, an anonymous Auth user, a missing session and a
-- mismatched subject all deny even if a client presents a fixture GUC.
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001103',
 '00000000-0000-0000-0000-000000002103');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001104',
 '00000000-0000-0000-0000-000000002104');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',false)','42501');
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001102',
 '00000000-0000-0000-0000-000000002102',true);
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001102',
 '00000000-0000-0000-0000-000000002199');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',false)','42501');
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001102',
 '00000000-0000-0000-0000-000000002101');
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');

-- An editor is independently entitled to read the same fixed profile.
SELECT pg_temp.profile_identity(
 '00000000-0000-0000-0000-000000001102',
 '00000000-0000-0000-0000-000000002102');
DO $editor$
DECLARE result jsonb;
BEGIN
  result:=public.transcript_core_private_mp3_profile_self_api_v1(
    '00000000-0000-0000-0000-000000000001',false);
  IF result->>'ruleVersion' IS DISTINCT FROM 'native_private_mp3_v1'
     OR result->'publication_approved' IS DISTINCT FROM 'false'::jsonb
  THEN RAISE EXCEPTION 'Editor cannot read immutable profile'; END IF;
END $editor$;
RESET ROLE;

-- Revoke live membership and session in the fictional source; an already
-- established profile must not turn that user into an editor.
UPDATE transcript_core.workspace_memberships SET role='viewer'
WHERE workspace_id='00000000-0000-0000-0000-000000000001'
  AND user_id='00000000-0000-0000-0000-000000001102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',false)','42501');
RESET ROLE;
UPDATE transcript_core.workspace_memberships SET role='editor'
WHERE workspace_id='00000000-0000-0000-0000-000000000001'
  AND user_id='00000000-0000-0000-0000-000000001102';
UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 minute'
WHERE id='00000000-0000-0000-0000-000000002102';
SET LOCAL ROLE authenticated;
SELECT pg_temp.profile_expect_denial(
 'SELECT public.transcript_core_private_mp3_profile_self_api_v1(''00000000-0000-0000-0000-000000000001'',true)','42501');
RESET ROLE;

-- One exact new profile, a separate deliberately incompatible fixture.
DO $rows$
DECLARE total int; records int;
BEGIN
 SELECT count(*) INTO total FROM transcript_core.delivery_profiles
 WHERE workspace_id='00000000-0000-0000-0000-000000000001'
   AND profile_key='private_audiobook_mp3' AND rule_version='native_private_mp3_v1';
 IF total<>1 THEN RAISE EXCEPTION 'Exact retry created duplicate profile'; END IF;
 SELECT count(*) INTO records FROM transcript_core.delivery_profiles
 WHERE workspace_id='00000000-0000-0000-0000-000000000002'
   AND id='00000000-0000-0000-0000-000000002999'
   AND display_name='Competing private profile' AND configuration='{}'::jsonb;
 IF records<>1 THEN RAISE EXCEPTION 'Incompatible profile was modified'; END IF;
END $rows$;
ROLLBACK;
SELECT 'PASS fictional private MP3 profile source, idempotency, isolation and denial (UNSIGNED)' AS result;

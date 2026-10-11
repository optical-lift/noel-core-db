DO $proof$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM information_schema.tables
   WHERE table_schema='atlas' AND table_name='titus_constellation_viewer_grants')
 THEN RAISE EXCEPTION 'Missing Atlas-owned research viewer permission store'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='atlas.titus_constellation_viewer_grants'::regclass)
 THEN RAISE EXCEPTION 'Missing grant-table RLS'; END IF;
 IF has_table_privilege('anon','atlas.titus_constellation_viewer_grants','SELECT')
   OR has_table_privilege('authenticated','atlas.titus_constellation_viewer_grants','SELECT')
   OR has_table_privilege('anon','atlas.titus_constellation_viewer_grants','INSERT')
   OR has_table_privilege('authenticated','atlas.titus_constellation_viewer_grants','INSERT')
 THEN RAISE EXCEPTION 'Browser privileges granted on private Atlas research grants'; END IF;
 IF has_function_privilege('anon','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
   OR NOT has_function_privilege('service_role','public.titus_constellation_viewer_allowed_v1(uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Research authorization API role boundary failed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.titus_constellation_viewer_grants)
 THEN RAISE EXCEPTION 'Candidate unexpectedly inserted user research access grants'; END IF;
 IF public.titus_constellation_viewer_allowed_v1(gen_random_uuid(),gen_random_uuid(),gen_random_uuid())
 THEN RAISE EXCEPTION 'Foreign unrelated identity/session gained research access'; END IF;
 IF public.titus_constellation_viewer_allowed_v1(NULL,NULL,NULL)
 THEN RAISE EXCEPTION 'Null identity/session gained research access'; END IF;

 IF has_function_privilege('anon','public.titus_constellation_atlas_native_allowed_v1(uuid,uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.titus_constellation_atlas_native_allowed_v1(uuid,uuid)','EXECUTE')
   OR NOT has_function_privilege('service_role','public.titus_constellation_atlas_native_allowed_v1(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Atlas native research authorization must remain service-only'; END IF;
 IF public.titus_constellation_atlas_native_allowed_v1(gen_random_uuid(),gen_random_uuid())
   OR public.titus_constellation_atlas_native_allowed_v1(NULL,NULL)
 THEN RAISE EXCEPTION 'Atlas native research access granted without real session and Person'; END IF;
END $proof$;


-- All below runs ONLY in a disposable clone after fixture rows are seeded.
-- Positive access is not inferred from Atlas login; it needs one explicit grant.
DO $authorization_fixture$
DECLARE
  principal uuid:='10000000-0000-4000-8000-000000000001';
  other_user uuid:='10000000-0000-4000-8000-000000000002';
  native_session uuid:='10000000-0000-4000-8000-000000000201';
  oauth_session uuid:='10000000-0000-4000-8000-000000000202';
  other_session uuid:='10000000-0000-4000-8000-000000000203';
  expired_session uuid:='10000000-0000-4000-8000-000000000204';
  oauth_client uuid:='10000000-0000-4000-8000-000000000101';
  wrong_client uuid:='10000000-0000-4000-8000-000000000102';
  person uuid:='10000000-0000-4000-8000-000000000301';
BEGIN
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'A real Auth identity without an explicit grant was accepted'; END IF;

 INSERT INTO atlas.titus_constellation_viewer_grants(
   person_entity_id,grant_state,valid_from,reviewed_by_principal_id,authority_basis
 ) VALUES(
   person,'active',now()-interval '1 hour',
   '10000000-0000-4000-8000-000000000401',
   'Disposable reviewer-backed source-clone fixture; not production authorization'
 );
 IF NOT public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 THEN RAISE EXCEPTION 'Canonical Person native session with active grant denied'; END IF;
 IF NOT public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Correct Titus OAuth session with active Person grant denied'; END IF;

 IF public.titus_constellation_atlas_native_allowed_v1(principal,oauth_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,native_session,oauth_client)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,wrong_client)
 OR public.titus_constellation_atlas_native_allowed_v1(principal,expired_session)
 OR public.titus_constellation_atlas_native_allowed_v1(principal,other_session)
 OR public.titus_constellation_atlas_native_allowed_v1(other_user,native_session)
 OR public.titus_constellation_atlas_native_allowed_v1(other_user,other_session)
 THEN RAISE EXCEPTION 'Foreign client, foreign Person, expired or mismatched session admitted'; END IF;

 UPDATE atlas.titus_constellation_viewer_grants
 SET grant_state='revoked', revoked_at=now()
 WHERE person_entity_id=person;
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Revoked grant admitted'; END IF;
 UPDATE atlas.titus_constellation_viewer_grants
 SET grant_state='active', revoked_at=NULL,valid_until=now()-interval '1 minute'
 WHERE person_entity_id=person;
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Expired grant admitted'; END IF;
 UPDATE atlas.titus_constellation_viewer_grants SET valid_until=NULL WHERE person_entity_id=person;

 UPDATE reality.auth_person_bindings SET binding_state='retired',retired_at=now()
 WHERE auth_user_id=principal;
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Retired Person binding admitted'; END IF;
 UPDATE reality.auth_person_bindings SET binding_state='active',retired_at=NULL
 WHERE auth_user_id=principal;

 UPDATE reality.entities SET identity_state='disputed' WHERE id=person;
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Disputed Person admitted'; END IF;
 UPDATE reality.entities SET identity_state='canonical' WHERE id=person;

 UPDATE auth.sessions SET not_after=now()-interval '1 minute' WHERE id=native_session;
 IF public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 THEN RAISE EXCEPTION 'Revoked/expired native session admitted'; END IF;
 UPDATE auth.sessions SET not_after=now()+interval '1 day' WHERE id=native_session;

 UPDATE auth.oauth_clients SET deleted_at=now() WHERE id=oauth_client;
 IF public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Deleted OAuth client admitted'; END IF;
 UPDATE auth.oauth_clients SET deleted_at=NULL WHERE id=oauth_client;

 IF NOT public.titus_constellation_atlas_native_allowed_v1(principal,native_session)
 OR NOT public.titus_constellation_viewer_allowed_v1(principal,oauth_session,oauth_client)
 THEN RAISE EXCEPTION 'Grant not restored after isolated fixture reversals'; END IF;
 RAISE NOTICE 'Titus private authorization fixture PASS: native and OAuth positive plus denial/revocation/expiry/identity cases';
END $authorization_fixture$;


-- Runtime-role proof. The actual Atlas backend calls this with service_role,
-- which intentionally cannot SELECT Supabase Auth tables. The definer functions
-- may return only booleans, and must not leak Auth rows or their privileges.
SET ROLE service_role;
DO $service_role_proof$
DECLARE
  identity_id uuid:='10000000-0000-4000-8000-000000000001';
  active_native uuid:='10000000-0000-4000-8000-000000000201';
  active_oauth uuid:='10000000-0000-4000-8000-000000000202';
  oauth_client uuid:='10000000-0000-4000-8000-000000000101';
BEGIN
 IF has_table_privilege('service_role','auth.sessions','SELECT')
 OR has_table_privilege('service_role','auth.oauth_clients','SELECT')
 THEN RAISE EXCEPTION 'Service role unexpectedly received broad Auth table permissions'; END IF;

 IF NOT public.titus_constellation_atlas_native_allowed_v1(identity_id,active_native)
 OR NOT public.titus_constellation_viewer_allowed_v1(identity_id,active_oauth,oauth_client)
 THEN RAISE EXCEPTION 'Backend service_role cannot verify authorized Person without Auth table SELECT'; END IF;

 IF public.titus_constellation_atlas_native_allowed_v1(identity_id,active_oauth)
 OR public.titus_constellation_viewer_allowed_v1(identity_id,active_native,oauth_client)
 OR public.titus_constellation_atlas_native_allowed_v1(
    '10000000-0000-4000-8000-000000000002',active_native)
 THEN RAISE EXCEPTION 'Service-role Boolean read incorrectly authorized a foreign caller'; END IF;
 RAISE NOTICE 'Service-only definer RPC positive/negative, no raw Auth SELECT: PASS';
END $service_role_proof$;
RESET ROLE;

-- DO NOT RUN ON PRODUCTION. Disposable production-shaped clone only.
-- This script leaves ALL synthetic Auth and Foundry records rolled back.
-- It checks DB function semantics but not signed-JWT transport.
-- Harness must set:
--   SET foundry.validation_disposable_clone = 'confirmed';
BEGIN;
DO $tests$
DECLARE
  v_user_id uuid := gen_random_uuid();
  v_other_user_id uuid := gen_random_uuid();
  v_request uuid := gen_random_uuid();
  v_req_other uuid := gen_random_uuid();
  v_owner uuid;
  v_first jsonb;
  v_retry jsonb;
  v_other jsonb;
  v_workspace text;
  v_fail boolean;
  v_prev uuid;
  v_owner_session uuid:=gen_random_uuid();
BEGIN
  IF current_setting('foundry.validation_disposable_clone',true)
       IS DISTINCT FROM 'confirmed' THEN
    RAISE EXCEPTION 'Refusing synthetic fixtures without disposable clone confirmation';
  END IF;

  INSERT INTO auth.users(id,is_anonymous)
    VALUES (v_user_id,false),(v_other_user_id,false);
  INSERT INTO auth.sessions(id,user_id) VALUES(v_owner_session,v_user_id);
  INSERT INTO atlas.principals(user_id,stable_key,name)
    VALUES (v_user_id,'foundryprep_'||replace(v_user_id::text,'-',''),
            'Synthetic Foundry Operator')
    RETURNING id INTO v_owner;

  -- This is only a SQL simulation of verified JWT claims in the test
  -- transaction; production requires provider-backed authentication.
  PERFORM set_config('request.jwt.claim.sub',v_user_id::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user_id,'role','authenticated','session_id',v_owner_session)::text,true);

  v_first := atlas.prepare_foundry_workspace_self_api_v1(
    v_request,'Provisional External Human','Synthetic external field',
    'documented_external');
  IF COALESCE((v_first->>'ok')::boolean,false) IS DISTINCT FROM true
     OR v_first->>'custodyReviewState' IS DISTINCT FROM 'pending'
     OR v_first->>'subjectIdentityState' IS DISTINCT FROM 'unresolved'
  THEN RAISE EXCEPTION 'Failed initial pending workspace preparation: %',v_first; END IF;

  v_workspace := v_first->>'workspaceId';
  IF v_workspace IS NULL OR v_workspace='' THEN
    RAISE EXCEPTION 'No server-generated workspace ID';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM foundry.workspace_authority_registry_v1
    WHERE workspace_id=v_workspace
      AND owner_principal_id=v_owner
      AND creation_request_id=v_request
      AND custody_review_state='pending'
      AND cardinality(custody_basis_refs)=0
  ) THEN RAISE EXCEPTION 'Registry authority was silently established or lost'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM foundry.events
    WHERE workspace_id=v_workspace
      AND sequence=1 AND event_type='WORKSPACE_CREATED'
      AND envelope->>'actor_kind'='human'
      AND envelope->>'authority'='authenticated_owner_preparation_only'
  ) THEN RAISE EXCEPTION 'Compliant source event not appended atomically'; END IF;

  v_retry := atlas.prepare_foundry_workspace_self_api_v1(
    v_request,'Provisional External Human','Synthetic external field',
    'documented_external');
  IF v_retry->>'workspaceId' IS DISTINCT FROM v_workspace
     OR COALESCE((v_retry->>'replayed')::boolean,false) IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Idempotent workspace preparation replay failed'; END IF;

  v_fail:=false;
  BEGIN
    PERFORM atlas.prepare_foundry_workspace_self_api_v1(
      v_request,'Changed subject same key','Synthetic external field',
      'documented_external');
  EXCEPTION WHEN OTHERS THEN v_fail:=true;
  END;
  IF NOT v_fail THEN RAISE EXCEPTION 'Changed payload reused creation request ID'; END IF;

  -- A second signed-in human who has no active Principal is denied.
  PERFORM set_config('request.jwt.claim.sub',v_other_user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_other_user_id,'role','authenticated','session_id',v_owner_session)::text,true);
  v_fail:=false;
  BEGIN
    PERFORM atlas.prepare_foundry_workspace_self_api_v1(
      v_req_other,'Foreign claim','Other field','documented_external');
  EXCEPTION WHEN OTHERS THEN v_fail:=true;
  END;
  IF NOT v_fail THEN RAISE EXCEPTION 'User without Principal created workspace'; END IF;

  -- Restore owner context, then verify all discovered custody stays pending.
  PERFORM set_config('request.jwt.claim.sub',v_user_id::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user_id,'role','authenticated','session_id',v_owner_session)::text,true);
  IF EXISTS(
    SELECT 1 FROM foundry.workspace_authority_registry_v1
    WHERE workspace_id=v_workspace AND custody_review_state='reviewed'
  ) THEN RAISE EXCEPTION 'Preparation pretended subject consent was reviewed'; END IF;
END
$tests$;
ROLLBACK;

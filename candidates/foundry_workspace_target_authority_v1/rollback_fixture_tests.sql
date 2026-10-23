-- DISPOSABLE PRODUCTION-SHAPED CLONE ONLY.
-- After applying private registry candidate PR #2093, then target evaluator.
-- This test inserts synthetic Auth/Principal/carrier/delegation/registry rows
-- and ROLLS BACK everything. It must NEVER be run on production.
--
-- The harness must set the session parameter before running:
--   SET foundry.validation_disposable_clone = 'confirmed';
-- The test refuses to run without it. Do not set this on production.
BEGIN;
DO $tests$
DECLARE
  v_owner_auth uuid:=gen_random_uuid();
  v_other_auth uuid:=gen_random_uuid();
  v_owner uuid;
  v_other uuid;
  v_carrier uuid;
  v_grant uuid;
  v_workspace text:='foundry-test-'||gen_random_uuid()::text;
  v_scope jsonb;
  v_result jsonb;
  v_ok boolean;
BEGIN
  IF current_setting('foundry.validation_disposable_clone',true)
       IS DISTINCT FROM 'confirmed' THEN
    RAISE EXCEPTION 'Refusing fixture tests: disposable clone not confirmed';
  END IF;

  -- These are disposable synthetic identities, not real customer records.
  INSERT INTO auth.users(id) VALUES (v_owner_auth),(v_other_auth);

  INSERT INTO atlas.principals(user_id,stable_key,name)
    VALUES (v_owner_auth,'foundry_test_'||replace(v_owner_auth::text,'-',''),
            'Foundry synthetic owner')
    RETURNING id INTO v_owner;
  INSERT INTO atlas.principals(user_id,stable_key,name)
    VALUES (v_other_auth,'foundry_test_'||replace(v_other_auth::text,'-',''),
            'Foundry synthetic foreign Principal')
    RETURNING id INTO v_other;

  INSERT INTO atlas.delegated_agent_carriers(stable_key,display_name,carrier_kind)
    VALUES ('foundrytest_'||replace(gen_random_uuid()::text,'-',''),
            'Foundry synthetic carrier','ai_agent')
    RETURNING id INTO v_carrier;

  -- Test command only; status never survives rollback.
  INSERT INTO atlas.agent_command_definitions
    (command_key,label,scope_kind,execution_class,
     confirmation_requirement,handler_key,target_contract)
  VALUES
    ('foundry.test.read','Foundry synthetic read','foundry_workspace','read',
     'none','not_an_executable_handler',
     jsonb_build_object('kind','foundry_workspace'));

  v_scope:=jsonb_build_object(
    'targetKinds',jsonb_build_array('foundry_workspace'),
    'targetIds',jsonb_build_array(v_workspace)
  );
  INSERT INTO atlas.delegated_agent_authorizations
    (carrier_id,principal_id,allowed_command_keys,max_execution_class,
     scope,purpose,basis)
  VALUES (v_carrier,v_owner,ARRAY['foundry.test.read'],'read',v_scope,
          'isolated Foundry workspace admission proof',
          jsonb_build_object('source','synthetic_rollback_fixture'))
    RETURNING id INTO v_grant;

  INSERT INTO foundry.workspace_authority_registry_v1
    (workspace_id,owner_principal_id,provisional_subject_label,
     provisional_field,custody_scope_kind,custody_review_state,
     custody_basis_refs,custody_reviewed_by_principal_id,
     custody_reviewed_at,custody_review_method,created_by_principal_id)
  VALUES
    (v_workspace,v_owner,'synthetic third-party subject',
     'isolated Foundry field','documented_external','reviewed',
     ARRAY['synthetic-authority-receipt'],v_owner,
     now(),'reviewed_source_authorization',v_owner);

  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Valid reviewed workspace target unexpectedly denied: %',v_result;
  END IF;

  -- Same allowlist, different workspace ID: always denied.
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id','not-this-workspace'));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Foreign workspace ID accepted';
  END IF;

  -- A Ledger/Person target cannot masquerade as a Foundry workspace.
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','ledger','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Wrong target kind accepted';
  END IF;

  -- Explicit target ID allowlist is mandatory, even if the owner matches.
  UPDATE atlas.delegated_agent_authorizations
    SET scope=jsonb_build_object(
      'targetKinds',jsonb_build_array('foundry_workspace'))
    WHERE id=v_grant;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Missing exact target ID allowlist accepted';
  END IF;
  UPDATE atlas.delegated_agent_authorizations SET scope=v_scope WHERE id=v_grant;

  -- The workspace exists but is owned by another Principal.
  UPDATE foundry.workspace_authority_registry_v1
    SET owner_principal_id=v_other WHERE workspace_id=v_workspace;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Foreign owner workspace was authorized';
  END IF;
  UPDATE foundry.workspace_authority_registry_v1
    SET owner_principal_id=v_owner WHERE workspace_id=v_workspace;

  -- Source custody is not established merely by a preserved source label.
  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='pending' WHERE workspace_id=v_workspace;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Unreviewed subject source custody was authorized';
  END IF;
  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='reviewed' WHERE workspace_id=v_workspace;

  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='suspended', suspended_at=now()
    WHERE workspace_id=v_workspace;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Suspended workspace custody was authorized';
  END IF;
  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='reviewed',suspended_at=NULL
    WHERE workspace_id=v_workspace;

  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='revoked',revoked_at=now()
    WHERE workspace_id=v_workspace;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Revoked workspace custody was authorized';
  END IF;
  UPDATE foundry.workspace_authority_registry_v1
    SET custody_review_state='reviewed',revoked_at=NULL
    WHERE workspace_id=v_workspace;

  UPDATE atlas.delegated_agent_authorizations
    SET authorization_state='revoked',revoked_at=now()
    WHERE id=v_grant;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Revoked carrier authorization was accepted';
  END IF;
  UPDATE atlas.delegated_agent_authorizations
    SET authorization_state='active',revoked_at=NULL
    WHERE id=v_grant;

  UPDATE atlas.delegated_agent_authorizations
    SET begins_at=now()-interval '3 days',ends_at=now()-interval '1 day'
    WHERE id=v_grant;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Expired delegated carrier authorization was accepted';
  END IF;
  UPDATE atlas.delegated_agent_authorizations
    SET begins_at=now()-interval '1 day',ends_at=NULL
    WHERE id=v_grant;

  UPDATE atlas.delegated_agent_carriers SET status='retired'
    WHERE id=v_carrier;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Retired AI carrier was accepted';
  END IF;

  -- All other mutations in this block roll back after successful checks.
END
$tests$;
ROLLBACK;

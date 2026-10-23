-- Postconditions + synthetic rollback tests on disposable local clone only.
-- Gate 1 candidate validation ONLY after applying candidate.sql to a
-- disposable production-schema clone. No writes. Not a production script.
DO $assert$
DECLARE
  v_oid oid;
BEGIN
  SELECT c.oid INTO v_oid FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='foundry' AND c.relname='workspace_authority_registry_v1'
    AND c.relkind='r';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'missing private Foundry authority registry'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_oid) THEN
    RAISE EXCEPTION 'Foundry registry RLS disabled';
  END IF;
  IF has_table_privilege('anon',v_oid,'SELECT') OR
     has_table_privilege('anon',v_oid,'INSERT') OR
     has_table_privilege('authenticated',v_oid,'SELECT') OR
     has_table_privilege('authenticated',v_oid,'INSERT') OR
     has_table_privilege('service_role',v_oid,'SELECT') OR
     has_table_privilege('service_role',v_oid,'INSERT') THEN
    RAISE EXCEPTION 'unexpected direct client/service_role access';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_oid) THEN
    RAISE EXCEPTION 'a direct table policy was added without authorization review';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid=v_oid AND contype='f'
      AND pg_get_constraintdef(oid) LIKE '%atlas.principals%'
  ) THEN
    RAISE EXCEPTION 'missing canonical Principal custody FK';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid=v_oid AND contype='u'
      AND pg_get_constraintdef(oid) LIKE '%owner_principal_id%'
      AND pg_get_constraintdef(oid) LIKE '%creation_request_id%'
  ) THEN
    RAISE EXCEPTION 'missing owner-scoped idempotent creation uniqueness';
  END IF;
  IF (SELECT count(*) FROM foundry.workspace_authority_registry_v1)<>0 THEN
    RAISE EXCEPTION 'candidate created/backfilled registry rows unexpectedly';
  END IF;
  IF to_regclass('foundry.events') IS NULL OR to_regclass('foundry.snapshots') IS NULL THEN
    RAISE EXCEPTION 'historical Foundry persistence missing';
  END IF;
END
$assert$;

-- Read-only POSTCONDITIONS for disposable full production-schema clone,
-- after PR #2093 registry and this target evaluator candidate have been applied.
-- No fixture rows or production permissions are created here.
DO $assert$
DECLARE
  v_def text;
  v_check text;
BEGIN
  IF to_regclass('foundry.workspace_authority_registry_v1') IS NULL THEN
    RAISE EXCEPTION 'Missing protected source-registry dependency';
  END IF;
  SELECT pg_get_constraintdef(c.oid) INTO v_check
    FROM pg_constraint c
    WHERE c.conrelid='atlas.agent_command_definitions'::regclass
      AND c.conname='agent_command_definitions_scope_kind_check';
  IF v_check IS NULL OR position('foundry_workspace' in v_check)=0 THEN
    RAISE EXCEPTION 'Foundry workspace is not an admitted explicit scope';
  END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas' AND p.proname='evaluate_delegated_agent_command_target_authority_v1';
  IF v_def IS NULL
     OR position('foundry_workspace_not_explicitly_delegated' in v_def)=0
     OR position('foundry_workspace_custody_not_authorized' in v_def)=0
     OR position('non_foundry_command_cannot_target_workspace' in v_def)=0
     OR position('foundry.workspace_authority_registry_v1' in v_def)=0
     OR position('w.owner_principal_id=v_auth.principal_id' in v_def)=0
  THEN RAISE EXCEPTION 'Verified registry owner/consent target check missing'; END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas' AND p.proname='evaluate_delegated_agent_command_authority_v1';
  IF v_def IS NULL OR position('foundry_command_cannot_use_ledger_delegation' in v_def)=0 THEN
    RAISE EXCEPTION 'Foundry command must refuse Ledger delegation'; END IF;
  IF EXISTS(
    SELECT 1 FROM atlas.agent_command_definitions
    WHERE scope_kind='foundry_workspace'
  ) THEN
    RAISE EXCEPTION 'Gate 1 may not prematurely register Foundry commands';
  END IF;
  IF has_table_privilege('authenticated','foundry.workspace_authority_registry_v1','SELECT')
    OR has_table_privilege('anon','foundry.workspace_authority_registry_v1','SELECT')
    OR has_table_privilege('service_role','foundry.workspace_authority_registry_v1','SELECT')
  THEN RAISE EXCEPTION 'Unexpected direct registry disclosure'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='foundry.workspace_authority_registry_v1'::regclass)
  THEN RAISE EXCEPTION 'Foundry registry RLS is off'; END IF;
END $assert$;

-- Postconditions only after Gate 1c source candidate applied to a
-- disposable production-shaped clone. Read-only assertions.
DO $assert$
DECLARE
  v_proc oid;
BEGIN
  SELECT p.oid INTO v_proc
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas'
    AND p.proname='prepare_foundry_workspace_self_api_v1'
    AND pg_get_function_identity_arguments(p.oid)=
      'p_request_id uuid, p_subject_label text, p_provisional_field text, p_custody_scope_kind text';
  IF v_proc IS NULL THEN
    RAISE EXCEPTION 'Foundry workspace preparation function missing';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_proc) THEN
    RAISE EXCEPTION 'Foundry workspace preparation lost its private-table execution';
  END IF;
  IF NOT has_function_privilege('authenticated',v_proc,'EXECUTE')
     OR has_function_privilege('anon',v_proc,'EXECUTE')
     OR has_function_privilege('service_role',v_proc,'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected direct API execution privilege';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint
    WHERE conrelid='foundry.workspace_authority_registry_v1'::regclass
      AND contype='u'
      AND pg_get_constraintdef(oid) LIKE '%creation_request_id%'
  ) THEN
    RAISE EXCEPTION 'Owner-scoped idempotency constraint missing';
  END IF;
  IF has_table_privilege('authenticated','foundry.workspace_authority_registry_v1','INSERT')
     OR has_table_privilege('authenticated','foundry.events','INSERT') THEN
    RAISE EXCEPTION 'Direct Foundry table writes improperly exposed';
  END IF;
  IF position('authenticated_owner_preparation_only' in pg_get_functiondef(v_proc))=0
     OR position('foundry.append_event' in pg_get_functiondef(v_proc))=0
  THEN RAISE EXCEPTION 'Provisional event custody requirements missing'; END IF;
END
$assert$;

SET foundry.validation_disposable_clone = 'confirmed';
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
    (workspace_id,creation_request_id,owner_principal_id,provisional_subject_label,
     provisional_field,custody_scope_kind,custody_review_state,
     custody_basis_refs,custody_reviewed_by_principal_id,
     custody_reviewed_at,custody_review_method,created_by_principal_id)
  VALUES
    (v_workspace,gen_random_uuid(),v_owner,'synthetic third-party subject',
     'isolated Foundry field','documented_external','reviewed',
     ARRAY['synthetic-authority-receipt'],v_owner,
     now(),'reviewed_source_authorization',v_owner);

  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.read',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Valid reviewed workspace target unexpectedly denied: %',v_result;
  END IF;

  -- A generic Personal command must not use a Foundry workspace target.
  INSERT INTO atlas.agent_command_definitions
    (command_key,label,scope_kind,execution_class,
     confirmation_requirement,handler_key,target_contract)
  VALUES
    ('foundry.test.personal','Foundry synthetic personal control',
     'personal','read','none','not_an_executable_handler','{}'::jsonb);
  UPDATE atlas.delegated_agent_authorizations
    SET allowed_command_keys=ARRAY['foundry.test.read','foundry.test.personal']
    WHERE id=v_grant;
  v_result:=atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_grant,'foundry.test.personal',1,
    jsonb_build_object('kind','foundry_workspace','id',v_workspace));
  IF COALESCE((v_result->>'allowed')::boolean,false) THEN
    RAISE EXCEPTION 'Personal command tunneled into Foundry workspace';
  END IF;
  UPDATE atlas.delegated_agent_authorizations
    SET allowed_command_keys=ARRAY['foundry.test.read'] WHERE id=v_grant;

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
BEGIN
  IF current_setting('foundry.validation_disposable_clone',true)
       IS DISTINCT FROM 'confirmed' THEN
    RAISE EXCEPTION 'Refusing synthetic fixtures without disposable clone confirmation';
  END IF;

  INSERT INTO auth.users(id,is_anonymous)
    VALUES (v_user_id,false),(v_other_user_id,false);
  INSERT INTO atlas.principals(user_id,stable_key,name)
    VALUES (v_user_id,'foundryprep_'||replace(v_user_id::text,'-',''),
            'Synthetic Foundry Operator')
    RETURNING id INTO v_owner;

  -- This is only a SQL simulation of verified JWT claims in the test
  -- transaction; production requires provider-backed authentication.
  PERFORM set_config('request.jwt.claim.sub',v_user_id::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);

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
  v_fail:=false;
  BEGIN
    PERFORM atlas.prepare_foundry_workspace_self_api_v1(
      v_req_other,'Foreign claim','Other field','documented_external');
  EXCEPTION WHEN OTHERS THEN v_fail:=true;
  END;
  IF NOT v_fail THEN RAISE EXCEPTION 'User without Principal created workspace'; END IF;

  -- Restore owner context, then verify all discovered custody stays pending.
  PERFORM set_config('request.jwt.claim.sub',v_user_id::text,true);
  IF EXISTS(
    SELECT 1 FROM foundry.workspace_authority_registry_v1
    WHERE workspace_id=v_workspace AND custody_review_state='reviewed'
  ) THEN RAISE EXCEPTION 'Preparation pretended subject consent was reviewed'; END IF;
END
$tests$;
ROLLBACK;

RESET foundry.validation_disposable_clone;

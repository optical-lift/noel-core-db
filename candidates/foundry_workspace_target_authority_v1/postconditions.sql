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

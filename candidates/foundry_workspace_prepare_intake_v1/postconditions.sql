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
  IF to_regprocedure('atlas.get_foundry_workspace_preparation_self_api_v1(text)') IS NULL
  THEN RAISE EXCEPTION 'Missing verified owner-only workspace inspection'; END IF;
  IF has_function_privilege('anon',
       'atlas.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,
       'EXECUTE')
     OR has_function_privilege('service_role',
       'atlas.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,
       'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'atlas.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,
       'EXECUTE')
  THEN RAISE EXCEPTION 'Owner-only read API privileges incorrect'; END IF;

  -- Public API is a narrow SECURITY INVOKER bridge; no private Atlas
  -- schema exposure and no elevated security-definer public function.
  IF to_regprocedure('public.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)') IS NULL
     OR to_regprocedure('public.get_foundry_workspace_preparation_self_api_v1(text)') IS NULL
  THEN RAISE EXCEPTION 'Missing public Foundry RPC bridges'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid IN (
      'public.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)'::regprocedure,
      'public.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure
    ) AND prosecdef
  ) THEN RAISE EXCEPTION 'Public Foundry bridge must stay SECURITY INVOKER'; END IF;
  IF NOT has_function_privilege('authenticated',
       'public.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)'::regprocedure,'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.get_foundry_workspace_preparation_self_api_v1(text)'::regprocedure,'EXECUTE')
  THEN RAISE EXCEPTION 'Unexpected public Foundry bridge execute privileges'; END IF;
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

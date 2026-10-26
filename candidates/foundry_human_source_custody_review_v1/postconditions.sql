-- Assert source-review isolation on disposable schema-clone ONLY.
DO $assert$
DECLARE v_oid oid;
BEGIN
  SELECT 'foundry.source_custody_review_cases_v1'::regclass::oid INTO v_oid;
  IF v_oid IS NULL OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_oid) THEN
    RAISE EXCEPTION 'Missing private RLS-gated human review record';
  END IF;
  IF has_table_privilege('authenticated',v_oid,'SELECT')
     OR has_table_privilege('authenticated',v_oid,'INSERT')
     OR has_table_privilege('anon',v_oid,'SELECT')
     OR has_table_privilege('service_role',v_oid,'SELECT') THEN
    RAISE EXCEPTION 'Direct custody case table access exposed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'request_foundry_source_custody_review_self_api_v1',
        'inspect_foundry_source_custody_review_self_api_v1',
        'decide_foundry_source_custody_review_self_api_v1',
        'revoke_foundry_source_custody_review_self_api_v1'
      ) AND p.prosecdef
  ) THEN RAISE EXCEPTION 'Elevated public custody review RPC'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname IN (
        'request_foundry_source_custody_review_self_api_v1',
        'inspect_foundry_source_custody_review_self_api_v1',
        'decide_foundry_source_custody_review_self_api_v1',
        'revoke_foundry_source_custody_review_self_api_v1'
      ))<>4 THEN RAISE EXCEPTION 'Missing narrow public custody review RPC'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname IN (
        'request_foundry_source_custody_review_self_api_v1',
        'inspect_foundry_source_custody_review_self_api_v1',
        'decide_foundry_source_custody_review_self_api_v1',
        'revoke_foundry_source_custody_review_self_api_v1'
      ) AND (has_function_privilege('anon',p.oid,'EXECUTE')
        OR has_function_privilege('service_role',p.oid,'EXECUTE')
        OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))
  ) THEN RAISE EXCEPTION 'Custody review RPC grants incorrect'; END IF;
  IF to_regprocedure('public.list_foundry_source_custody_reviewers_self_api_v1(text)') IS NULL
     OR NOT has_function_privilege('authenticated',
       'public.list_foundry_source_custody_reviewers_self_api_v1(text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.list_foundry_source_custody_reviewers_self_api_v1(text)'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.list_foundry_source_custody_reviewers_self_api_v1(text)'::regprocedure,'EXECUTE')
     OR (SELECT prosecdef FROM pg_proc WHERE
       oid='public.list_foundry_source_custody_reviewers_self_api_v1(text)'::regprocedure)
  THEN RAISE EXCEPTION 'Connected reviewer directory must stay narrow and session-owned'; END IF;
  IF to_regprocedure('public.list_foundry_source_custody_reviews_self_api_v1()') IS NULL
     OR NOT has_function_privilege('authenticated',
       'public.list_foundry_source_custody_reviews_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.list_foundry_source_custody_reviews_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.list_foundry_source_custody_reviews_self_api_v1()'::regprocedure,'EXECUTE')
     OR (SELECT prosecdef FROM pg_proc WHERE
       oid='public.list_foundry_source_custody_reviews_self_api_v1()'::regprocedure)
  THEN RAISE EXCEPTION 'Reviewer inbox must be signed and private'; END IF;
  IF to_regprocedure('public.list_foundry_owned_workspaces_self_api_v1()') IS NULL
     OR NOT has_function_privilege('authenticated',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR (SELECT prosecdef FROM pg_proc WHERE
       oid='public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure)
  THEN RAISE EXCEPTION 'Owner Index must require signed private scoped access'; END IF;
  IF to_regprocedure('public.list_foundry_owned_workspaces_self_api_v1()') IS NULL
     OR NOT has_function_privilege('authenticated',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('anon',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR has_function_privilege('service_role',
       'public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure,'EXECUTE')
     OR (SELECT prosecdef FROM pg_proc WHERE
       oid='public.list_foundry_owned_workspaces_self_api_v1()'::regprocedure)
  THEN RAISE EXCEPTION 'Foundry owner Index must remain private to signed owner'; END IF;
  IF EXISTS(SELECT 1 FROM foundry.workspace_authority_registry_v1
            WHERE custody_review_state='reviewed') THEN
    RAISE EXCEPTION 'Human review silently elevated carrier-level custody';
  END IF;
  IF EXISTS(SELECT 1 FROM atlas.agent_command_definitions
            WHERE scope_kind='foundry_workspace') THEN
    RAISE EXCEPTION 'Human review registered an AI command';
  END IF;
END
$assert$;

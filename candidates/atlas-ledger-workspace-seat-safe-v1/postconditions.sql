-- Disposable schema-clone postconditions.
do $post$
declare
  v_public text;
  v_safe text;
  v_old text;
begin
  if to_regprocedure('atlas.ledger_workspace_self_api_v1(uuid)') is null
    or to_regprocedure('atlas.ledger_workspace_unfiltered_internal_v1(uuid)') is null
    or to_regprocedure('public.ledger_workspace_self_api_v1(uuid)') is null then
    raise exception 'Safe Ledger workspace chain incomplete';
  end if;
  if has_function_privilege('anon',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('service_role',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('anon',
      'public.ledger_workspace_self_api_v1(uuid)','EXECUTE')
    or not has_function_privilege('authenticated',
      'public.ledger_workspace_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Internal full Ledger reader exposes unsafe EXECUTE grants';
  end if;
  select pg_get_functiondef('public.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    into v_public;
  select pg_get_functiondef('atlas.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    into v_safe;
  select pg_get_functiondef('atlas.ledger_workspace_unfiltered_internal_v1(uuid)'::regprocedure)
    into v_old;
  if (select p.prosecdef from pg_proc p
      where p.oid='public.ledger_workspace_self_api_v1(uuid)'::regprocedure)
    or position('capability_root_authority_context_self_v1' in v_safe)=0
    or position('ledger_workspace_unfiltered_internal_v1' in v_safe)=0
    or position('No current authorized Ledger seat' in v_safe)=0
    or position('seat_only' in v_safe)=0
    or position('nativeFullHistoryRequiresExactRootAuthority' in v_safe)=0
    or position('ledger.actions' in v_old)=0 then
    raise exception 'Safe native Ledger reader contract not preserved';
  end if;
  if position('ledger_workspace_unfiltered_internal_v1' in v_public)>0 then
    raise exception 'Public wrapper directly invokes unsafe private reader';
  end if;
end
$post$;

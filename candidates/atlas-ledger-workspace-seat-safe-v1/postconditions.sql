-- Disposable schema-clone postconditions.
do $post$
declare
  v_public text;
  v_safe text;
  v_old text;
  v_entity_safe text;
  v_temporal_safe text;
  v_temporal_old text;
begin
  if to_regprocedure('atlas.ledger_workspace_self_api_v1(uuid)') is null
    or to_regprocedure('atlas.ledger_workspace_unfiltered_internal_v1(uuid)') is null
    or to_regprocedure('public.ledger_workspace_self_api_v1(uuid)') is null then
    raise exception 'Safe Ledger workspace chain incomplete';
  end if;
  if to_regprocedure('atlas.ledger_entity_contexts_self_api_v1(uuid,text)') is null
    or to_regprocedure('atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)') is null then
    raise exception 'Safe Ledger entity-context chain incomplete';
  end if;
  if to_regprocedure('atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)') is null
    or to_regprocedure('atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)') is null then
    raise exception 'Safe Ledger temporal-composer chain incomplete';
  end if;
  if has_function_privilege('anon',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('service_role',
      'atlas.ledger_workspace_unfiltered_internal_v1(uuid)','EXECUTE')
    or has_function_privilege('anon',
      'public.ledger_workspace_self_api_v1(uuid)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)','EXECUTE')
    or has_function_privilege('anon',
      'atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)','EXECUTE')
    or has_function_privilege('authenticated',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or has_function_privilege('anon',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or has_function_privilege('service_role',
      'atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)','EXECUTE')
    or not has_function_privilege('authenticated',
      'atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)','EXECUTE')
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
  select pg_get_functiondef('atlas.ledger_entity_contexts_self_api_v1(uuid,text)'::regprocedure)
    into v_entity_safe;
  select pg_get_functiondef('atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)'::regprocedure)
    into v_temporal_safe;
  select pg_get_functiondef('atlas.ledger_temporal_composer_unfiltered_internal_v1(uuid,date,date,text,integer)'::regprocedure)
    into v_temporal_old;
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
  if position('capability_root_authority_context_self_v1' in v_entity_safe)=0
    or position('ledger_entity_contexts_unfiltered_internal_v1' in v_entity_safe)=0 then
    raise exception 'Entity-context API still trusts seat without root authority';
  end if;
  if position('capability_root_authority_context_self_v1' in v_temporal_safe)=0
    or position('ledger_temporal_composer_unfiltered_internal_v1' in v_temporal_safe)=0
    or position('current_active_ledger_seat_v1' in v_temporal_old)=0 then
    raise exception 'Temporal composer still trusts seat without root authority';
  end if;
end
$post$;

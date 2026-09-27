-- Validation: Atlas Implementation Workbench v1
-- Read-only assertions. Run after 20260927224500_atlas_implementation_workbench_v1.sql.

do $validate$
declare
  v_registry_rls boolean;
  v_intents_rls boolean;
  v_def text;
  v_preview text;
  v_compose text;
  v_count integer;
begin
  if to_regclass('atlas.workbench_operation_registry') is null then
    raise exception 'Missing atlas.workbench_operation_registry';
  end if;
  if to_regclass('atlas.workbench_intents') is null then
    raise exception 'Missing atlas.workbench_intents';
  end if;

  select relrowsecurity into v_registry_rls
  from pg_class where oid='atlas.workbench_operation_registry'::regclass;
  select relrowsecurity into v_intents_rls
  from pg_class where oid='atlas.workbench_intents'::regclass;
  if not coalesce(v_registry_rls,false) or not coalesce(v_intents_rls,false) then
    raise exception 'Workbench tables must have RLS enabled';
  end if;

  if has_table_privilege('authenticated','atlas.workbench_operation_registry','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated','atlas.workbench_intents','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','atlas.workbench_operation_registry','SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('service_role','atlas.workbench_intents','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'Workbench raw tables must not be directly mutable/readable by app roles';
  end if;

  select count(*) into v_count
  from atlas.workbench_operation_registry
  where registry_state='active';
  if v_count<>9 then
    raise exception 'Expected nine active Workbench operations, got %',v_count;
  end if;

  select count(*) into v_count
  from atlas.workbench_operation_registry
  where registry_state='active' and route_class='DISCOVER';
  if v_count<>4 then
    raise exception 'Expected four DISCOVER operations, got %',v_count;
  end if;

  select count(*) into v_count
  from atlas.workbench_operation_registry
  where registry_state='active' and route_class='ESTABLISH';
  if v_count<>4 then
    raise exception 'Expected four ESTABLISH operations, got %',v_count;
  end if;

  select count(*) into v_count
  from atlas.workbench_operation_registry
  where registry_state='active' and route_class='ACT';
  if v_count<>1 then
    raise exception 'Expected one ACT routing class operation, got %',v_count;
  end if;

  if exists(
    select 1
    from atlas.workbench_operation_registry
    where route_class='ACT'
      and (not requires_operation_contract or destination_membrane<>'atlas.operation_contract')
  ) then
    raise exception 'Every Workbench ACT route must be Operation Contract governed';
  end if;

  if exists(
    select 1
    from atlas.workbench_operation_registry
    where route_class<>'ACT' and requires_operation_contract
  ) then
    raise exception 'Operation Contract requirement must not leak into DISCOVER/ESTABLISH';
  end if;

  if exists(
    select 1
    from atlas.workbench_operation_registry
    where not human_route_confirmation_required
  ) then
    raise exception 'Workbench v1 requires explicit human route confirmation';
  end if;

  if exists(
    select 1
    from atlas.workbench_operation_registry
    where lower(destination_membrane||'.'||destination_operation)
      ~ '(execute_sql|generic_crud|direct_atlas_reality_write|force_seal|bypass_readiness)'
  ) then
    raise exception 'Forbidden generic mutation surface found in Workbench registry';
  end if;

  if not exists(
    select 1 from atlas.workbench_operation_registry
    where operation_key='discover.record_testimony'
      and route_class='DISCOVER'
      and destination_membrane='foundry.service'
      and destination_operation='record_testimony'
  ) then
    raise exception 'Foundry testimony route missing';
  end if;

  if not exists(
    select 1 from atlas.workbench_operation_registry
    where operation_key='establish.foundry_admission_handoff'
      and route_class='ESTABLISH'
      and destination_membrane='atlas.foundry_admission'
  ) then
    raise exception 'Foundry admission route missing';
  end if;

  if not exists(
    select 1 from atlas.workbench_operation_registry
    where operation_key='establish.reality_identity_merge_confirmation'
      and route_class='ESTABLISH'
      and destination_membrane='reality.entity_reconciliation'
  ) then
    raise exception 'Reality reconciliation route missing';
  end if;

  if not exists(
    select 1 from atlas.workbench_operation_registry
    where operation_key='act.governed_operation'
      and route_class='ACT'
      and requires_operation_contract
  ) then
    raise exception 'Governed ACT route missing';
  end if;

  if not has_function_privilege('authenticated','atlas.workbench_operation_catalog_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.workbench_preview_intent_api_v1(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.workbench_route_intent_api_v1(uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.workbench_cancel_intent_api_v1(uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.workbench_intent_api_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated Workbench API grants are incomplete';
  end if;

  if has_function_privilege('anon','atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.workbench_preview_intent_api_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.workbench_route_intent_api_v1(uuid,text)','EXECUTE')
     or has_function_privilege('service_role','atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)','EXECUTE')
     or has_function_privilege('service_role','atlas.workbench_preview_intent_api_v1(uuid)','EXECUTE')
     or has_function_privilege('service_role','atlas.workbench_route_intent_api_v1(uuid,text)','EXECUTE') then
    raise exception 'Anonymous/service role must not receive generic Workbench human routing authority';
  end if;

  if has_function_privilege('authenticated','atlas.workbench_sentence_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('service_role','atlas.workbench_sentence_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.workbench_preview_internal_v1(uuid)','EXECUTE')
     or has_function_privilege('service_role','atlas.workbench_preview_internal_v1(uuid)','EXECUTE') then
    raise exception 'Workbench internal/normalization functions must stay behind governed APIs';
  end if;

  select pg_get_functiondef('atlas.workbench_route_intent_api_v1(uuid,text)'::regprocedure)
  into v_def;
  select pg_get_functiondef('atlas.workbench_preview_internal_v1(uuid)'::regprocedure)
  into v_preview;
  select pg_get_functiondef('atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)'::regprocedure)
  into v_compose;

  if lower(v_def) like '%insert into reality.entities%'
     or lower(v_def) like '%insert into ledger.ledgers%'
     or lower(v_def) like '%update reality.entities%'
     or lower(v_def) like '%execute %' then
    raise exception 'Workbench route API contains forbidden canonical mutation/dynamic execution';
  end if;

  if position('destinationExecutionOccurred' in v_def)=0
     or position('canonicalTruthChangedByWorkbench' in v_def)=0
     or position('destinationAuthoritySatisfiedByRouting' in v_def)=0 then
    raise exception 'Workbench route receipt does not make its authority boundary explicit';
  end if;

  if position('operation_contract_normalize_v1' in v_preview)=0
     or position('GENERIC_MUTATION_SURFACE_FORBIDDEN' in v_preview)=0
     or position('GOVERNED_COMMAND_CONTRACT_REQUIRED' in v_preview)=0 then
    raise exception 'Workbench ACT preview contract is incomplete';
  end if;

  if position('workbench_sentence_normalize_v1' in v_compose)=0
     or position('workbench_operation_registry' in v_compose)=0 then
    raise exception 'Workbench composition must normalize sentence and resolve registry route';
  end if;

  if exists(
    select 1
    from atlas.workbench_intents i
    join atlas.workbench_operation_registry r on r.operation_key=i.operation_key
    where i.route_class<>r.route_class
  ) then
    raise exception 'Stored Workbench intent route disagrees with registry';
  end if;

  if exists(
    select 1 from atlas.workbench_intents
    where intent_state='ROUTED'
      and (
        route_receipt='{}'::jsonb
        or coalesce((route_receipt->>'destinationExecutionOccurred')::boolean,true)
        or coalesce((route_receipt->>'canonicalTruthChangedByWorkbench')::boolean,true)
        or coalesce((route_receipt->>'destinationAuthoritySatisfiedByRouting')::boolean,true)
      )
  ) then
    raise exception 'Routed Workbench receipt claims authority/effect that Workbench does not possess';
  end if;

  raise notice 'Implementation Workbench v1 validation passed.';
end
$validate$;

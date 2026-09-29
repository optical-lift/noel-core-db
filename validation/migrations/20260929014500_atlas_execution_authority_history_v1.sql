-- Versioned postconditions: Atlas Canonical Execution Authority History v1.
-- Structural validation only. This validator does not create authority, allocate
-- Work, create tasks, establish Principal claims, admit Clock state, or mutate
-- underlying subject outcomes.

do $block$
declare
  v_table regclass;
  v_api regprocedure;
  v_trigger_function regprocedure;
  v_api_def text;
  v_trigger_def text;
begin
  v_table:=to_regclass('atlas.execution_authority_history');
  if v_table is null then
    raise exception 'atlas.execution_authority_history is missing';
  end if;

  v_api:=to_regprocedure('atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text)');
  if v_api is null then
    raise exception 'atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text) is missing';
  end if;

  v_trigger_function:=to_regprocedure('atlas.enforce_execution_authority_chain_v1()');
  if v_trigger_function is null then
    raise exception 'atlas.enforce_execution_authority_chain_v1() is missing';
  end if;

  select pg_get_functiondef(v_api) into v_api_def;
  select pg_get_functiondef(v_trigger_function) into v_trigger_def;

  if v_api_def not like '%execution_authority_history_v1%' then
    raise exception 'Execution Authority API contract version missing';
  end if;
  if v_api_def not like '%includesAllAuthorityStates%' then
    raise exception 'Execution Authority API does not declare complete state history';
  end if;
  if v_api_def not like '%laterEventsDoNotReplaceEarlierEvents%' then
    raise exception 'Execution Authority API does not preserve historical event semantics';
  end if;
  if v_api_def not like '%workerDayIdentifiersAcceptedAsCanonicalIdentity%' then
    raise exception 'Execution Authority API lacks Worker Day identity boundary';
  end if;
  if v_api_def not like '%terminalAuthorityStateEstablishesUnderlyingSubjectOutcome%' then
    raise exception 'Execution Authority API lacks terminal-outcome boundary';
  end if;
  if v_api_def not like '%workAllocationCreated%' or v_api_def not like '%clockOrTodayStateCreated%' then
    raise exception 'Execution Authority API lacks downstream truth boundaries';
  end if;

  -- The canonical lookup is exact Reality coordinates. Legacy operational IDs
  -- belong in provenance/carrier payloads, not in this function signature.
  if v_api_def like '%farm_id%' or v_api_def like '%membership_id%' or v_api_def like '%service_date%' then
    raise exception 'Legacy Worker Day identity leaked into canonical Execution Authority API';
  end if;

  if v_trigger_def not like '%person_entity_id%' or v_trigger_def not like '%responsibility_entity_id%' then
    raise exception 'Execution Authority chain guard does not freeze canonical coordinates';
  end if;
  if v_trigger_def not like '%operation_key%' or v_trigger_def not like '%target_entity_id%' then
    raise exception 'Execution Authority chain guard does not freeze target/operation coordinates';
  end if;

  if not exists(
    select 1
    from pg_trigger t
    where t.tgrelid=v_table
      and t.tgname='enforce_execution_authority_chain_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Execution Authority chain trigger is missing';
  end if;

  if not exists(
    select 1
    from pg_constraint c
    where c.conrelid=v_table
      and c.conname='execution_authority_state_v1'
      and pg_get_constraintdef(c.oid) like '%leased%'
      and pg_get_constraintdef(c.oid) like '%started%'
      and pg_get_constraintdef(c.oid) like '%interrupted%'
      and pg_get_constraintdef(c.oid) like '%completed%'
      and pg_get_constraintdef(c.oid) like '%withdrawn%'
      and pg_get_constraintdef(c.oid) like '%expired%'
  ) then
    raise exception 'Execution Authority state constraint does not preserve lease physics';
  end if;

  if has_table_privilege('anon',v_table,'SELECT')
     or has_table_privilege('authenticated',v_table,'SELECT')
     or has_table_privilege('service_role',v_table,'SELECT') then
    raise exception 'Execution Authority history table is directly readable outside its membrane';
  end if;

  if has_function_privilege('anon',v_api,'EXECUTE') then
    raise exception 'anon may not execute canonical Execution Authority history API';
  end if;
  if not has_function_privilege('authenticated',v_api,'EXECUTE') then
    raise exception 'authenticated lacks canonical Execution Authority history API access';
  end if;
end
$block$;

-- Validation for 20260911172800 communication provider-independence foundation.
-- Intended for disposable/clone validation after this migration alone is applied.

begin;

-- Existing institutional endpoint custody must remain valid.
do $validation$
begin
  if exists (
    select 1
    from atlas.communication_endpoints ep
    where ep.organization_id is not null
      and ep.principal_id is not null
  ) then
    raise exception 'Endpoint has both Principal and Organization custody.';
  end if;

  if exists (
    select 1
    from atlas.communication_endpoints ep
    where ep.organization_id is null
      and ep.principal_id is null
  ) then
    raise exception 'Endpoint has no custody root.';
  end if;

  if exists (
    select 1
    from atlas.communication_endpoints ep
    where ep.principal_id is not null
      and ep.organization_unit_id is not null
  ) then
    raise exception 'Principal endpoint incorrectly has Organization Unit custody.';
  end if;
end;
$validation$;

-- Every pre-existing Institutional Conversation must bridge one-to-one to the
-- common provider-independent conversation root without changing old IDs.
do $validation$
declare
  v_institutional bigint;
  v_roots bigint;
  v_distinct_roots bigint;
begin
  select count(*) into v_institutional from atlas.institutional_conversations;
  select count(*),count(distinct communication_conversation_id)
  into v_roots,v_distinct_roots
  from atlas.institutional_conversation_roots;

  if v_roots<>v_institutional or v_distinct_roots<>v_institutional then
    raise exception 'Institutional conversation root bridge is incomplete: institutional %, roots %, distinct roots %',v_institutional,v_roots,v_distinct_roots;
  end if;

  if exists (
    select 1
    from atlas.institutional_conversation_roots root
    join atlas.institutional_conversations ic on ic.id=root.institutional_conversation_id
    join atlas.communication_conversations cc on cc.id=root.communication_conversation_id
    where cc.organization_id is distinct from ic.organization_id
       or cc.organization_unit_id is distinct from ic.organization_unit_id
       or cc.principal_id is not null
  ) then
    raise exception 'Institutional root bridge changed custody.';
  end if;
end;
$validation$;

-- Every existing institutional source-thread bridge must also exist beneath the
-- new common conversation root, preserving the original Communication Thread ID.
do $validation$
declare
  v_old bigint;
  v_new bigint;
begin
  select count(*) into v_old from atlas.institutional_conversation_source_threads;
  select count(*) into v_new
  from atlas.communication_conversation_source_threads cst
  join atlas.institutional_conversation_roots root on root.communication_conversation_id=cst.communication_conversation_id;

  if v_new<>v_old then
    raise exception 'Institutional source-thread compatibility bridge mismatch: old %, new %',v_old,v_new;
  end if;

  if exists (
    select 1
    from atlas.institutional_conversation_source_threads old
    left join atlas.institutional_conversation_roots root on root.institutional_conversation_id=old.institutional_conversation_id
    left join atlas.communication_conversation_source_threads new
      on new.communication_conversation_id=root.communication_conversation_id
     and new.communication_thread_id=old.communication_thread_id
     and new.connected_source_id=old.connected_source_id
    where new.id is null
  ) then
    raise exception 'At least one existing provider/source thread was not preserved in the common conversation bridge.';
  end if;
end;
$validation$;

-- Provider-neutral synchronization state must remain structurally generic.
do $validation$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_source_sync_states' and column_name='state_payload' and data_type='jsonb'
  ) then
    raise exception 'Provider-neutral sync state payload missing.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='communication_source_sync_states'
      and column_name in ('imap_uid','imap_uidvalidity','gmail_history_id','microsoft_delta_token')
  ) then
    raise exception 'Provider-specific cursor leaked into generic sync-state schema.';
  end if;
end;
$validation$;

-- Actionability is evidence only; the existing response-case opener must not
-- have been silently rewritten by this foundation release.
do $validation$
declare
  v_definition text;
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='ensure_institutional_response_case_for_event_service_v1'
  order by p.oid desc
  limit 1;

  if v_definition is null then
    raise exception 'Existing institutional response-case opener missing.';
  end if;

  if position('communication_event_actionability_v1' in v_definition)>0
     or position('communication_actionability_assessments' in v_definition)>0 then
    raise exception 'Foundation release unexpectedly cut live response responsibility over to actionability.';
  end if;
end;
$validation$;

-- Internal tables must not be directly writable/readable by browser roles.
do $validation$
declare
  v_table text;
begin
  foreach v_table in array array[
    'communication_conversations',
    'communication_conversation_source_threads',
    'communication_conversation_endpoints',
    'institutional_conversation_roots',
    'communication_source_sync_states',
    'communication_actionability_assessments'
  ] loop
    if has_table_privilege('authenticated','atlas.'||v_table,'SELECT')
       or has_table_privilege('authenticated','atlas.'||v_table,'INSERT')
       or has_table_privilege('authenticated','atlas.'||v_table,'UPDATE')
       or has_table_privilege('authenticated','atlas.'||v_table,'DELETE') then
      raise exception 'Authenticated browser role has direct privilege on atlas.%',v_table;
    end if;
  end loop;
end;
$validation$;

-- This migration opens only the Principal endpoint upsert client seam.
do $validation$
begin
  if not has_function_privilege('authenticated','atlas.upsert_principal_communication_endpoint_self_api_v1(text,text,text,jsonb)','EXECUTE') then
    raise exception 'Principal endpoint upsert API is not executable by authenticated.';
  end if;
end;
$validation$;

rollback;

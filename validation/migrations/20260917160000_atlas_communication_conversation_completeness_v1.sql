-- Validation for Atlas Communications convergence Stage 1.
-- Run only after the candidate migration in disposable / production-schema-clone validation.

begin;

do $validation$
begin
  if to_regclass('atlas.communication_conversation_events') is null then
    raise exception 'Common Communication Conversation event membership table is missing.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversations ic
    left join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ic.id
    where root.institutional_conversation_id is null
  ) then
    raise exception 'At least one Institutional Conversation lacks a common Communication Conversation root.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversations ic
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ic.id
    join atlas.communication_conversations cc
      on cc.id=root.communication_conversation_id
    where cc.principal_id is not null
       or cc.organization_id is distinct from ic.organization_id
       or cc.organization_unit_id is distinct from ic.organization_unit_id
  ) then
    raise exception 'Institutional/common Conversation custody mismatch exists.';
  end if;
end;
$validation$;

do $validation$
begin
  if exists(
    select 1
    from atlas.institutional_conversation_source_threads ist
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ist.institutional_conversation_id
    left join atlas.communication_conversation_source_threads cst
      on cst.communication_thread_id=ist.communication_thread_id
     and cst.communication_conversation_id=root.communication_conversation_id
    where cst.communication_thread_id is null
  ) then
    raise exception 'Institutional source thread is not represented beneath its common Conversation root.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversation_endpoints ice
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ice.institutional_conversation_id
    left join atlas.communication_conversation_endpoints cce
      on cce.communication_conversation_id=root.communication_conversation_id
     and cce.communication_endpoint_id=ice.communication_endpoint_id
    where cce.communication_endpoint_id is null
  ) then
    raise exception 'Institutional endpoint is not represented beneath its common Conversation root.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversation_messages message
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=message.institutional_conversation_id
    left join atlas.communication_conversation_events event_link
      on event_link.communication_event_id=message.communication_event_id
     and event_link.communication_conversation_id=root.communication_conversation_id
    where event_link.communication_event_id is null
  ) then
    raise exception 'Institutional message event is not a member of its common Communication Conversation.';
  end if;
end;
$validation$;

do $validation$
declare
  v_definition text;
begin
  if to_regprocedure('atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid)') is null then
    raise exception 'Institutional conversation admission function is missing.';
  end if;

  select pg_get_functiondef(
    to_regprocedure('atlas.ensure_institutional_conversation_for_communication_event_service_v1(uuid)')
  ) into v_definition;

  if position('ensure_organization_communication_conversation_service_v1' in v_definition)=0 then
    raise exception 'Institutional admission does not establish the common Communication Conversation first.';
  end if;

  if position('institutional_conversation_roots' in v_definition)=0 then
    raise exception 'Institutional admission does not bind its compatibility root.';
  end if;

  if to_regprocedure('atlas.ensure_institutional_conversation_compatibility_service_v1(uuid)') is null then
    raise exception 'Transitional Institutional compatibility carrier is missing.';
  end if;
end;
$validation$;

do $validation$
declare
  v_response_definition text;
  v_ingest_definition text;
begin
  select pg_get_functiondef(p.oid)
  into v_response_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='ensure_institutional_response_case_for_event_service_v1'
  order by p.oid desc
  limit 1;

  if v_response_definition is null then
    raise exception 'Existing Institutional Response Case opener is missing.';
  end if;

  if position('communication_event_actionability_v1' in v_response_definition)>0
     or position('communication_actionability_assessments' in v_response_definition)>0 then
    raise exception 'Stage 1 unexpectedly cut Institutional response responsibility over to actionability.';
  end if;

  select pg_get_functiondef(p.oid)
  into v_ingest_definition
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='ingest_organization_communication_events_service_v3'
  order by p.oid desc
  limit 1;

  if v_ingest_definition is null
     or position('ensure_institutional_response_case_for_event_service_v1' in v_ingest_definition)=0 then
    raise exception 'Stage 1 unexpectedly removed the existing response-case compatibility consequence.';
  end if;
end;
$validation$;

do $validation$
declare
  v_required_trigger record;
begin
  select tg.tgname,tg.tgdeferrable,tg.tginitdeferred
  into v_required_trigger
  from pg_trigger tg
  join pg_class c on c.oid=tg.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='atlas'
    and c.relname='institutional_conversations'
    and tg.tgname='institutional_conversation_common_root_required_v1'
    and not tg.tgisinternal;

  if v_required_trigger.tgname is null
     or not v_required_trigger.tgdeferrable
     or not v_required_trigger.tginitdeferred then
    raise exception 'Deferred Institutional Conversation common-root invariant is not installed.';
  end if;
end;
$validation$;

do $validation$
begin
  if has_table_privilege('authenticated','atlas.communication_conversation_events','SELECT')
     or has_table_privilege('authenticated','atlas.communication_conversation_events','INSERT')
     or has_table_privilege('authenticated','atlas.communication_conversation_events','UPDATE')
     or has_table_privilege('authenticated','atlas.communication_conversation_events','DELETE') then
    raise exception 'Authenticated direct access leaked to common Communication Conversation event membership.';
  end if;

  if has_function_privilege(
      'authenticated',
      'atlas.ensure_organization_communication_conversation_service_v1(uuid)',
      'EXECUTE'
    ) then
    raise exception 'Browser may execute Organization common-conversation admission directly.';
  end if;

  if not has_function_privilege(
      'service_role',
      'atlas.ensure_organization_communication_conversation_service_v1(uuid)',
      'EXECUTE'
    ) then
    raise exception 'Service Organization common-conversation admission is unavailable.';
  end if;
end;
$validation$;

rollback;

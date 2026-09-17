-- Validation for Package 7 Communications convergence Stage 2.
-- Run only after Stage 1 + Stage 2 in disposable / production-schema-clone validation.

begin;

do $validation$
declare
  v_missing text[]:=array[]::text[];
  v_name text;
begin
  foreach v_name in array array[
    'organization_correspondence_effective_organization_v1(uuid)',
    'organization_correspondence_read_authorized_self_v1(uuid)',
    'organization_correspondence_list_self_api_v1(uuid,uuid,integer)',
    'organization_correspondence_conversation_self_api_v1(uuid)',
    'organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer)',
    'organization_correspondence_sent_self_api_v1(uuid,uuid,integer)',
    'institutional_shared_inbox_self_v3(uuid,integer)',
    'institutional_conversation_detail_self_v4(uuid)',
    'institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer)',
    'institutional_sent_mail_self_v1(uuid,integer)'
  ] loop
    if to_regprocedure('atlas.'||v_name) is null then
      v_missing:=array_append(v_missing,v_name);
    end if;
  end loop;

  if cardinality(v_missing)>0 then
    raise exception 'Stage 2 required functions are missing: %',array_to_string(v_missing,', ');
  end if;
end;
$validation$;

-- Stage 2 is deliberately downstream of Stage 1. The production clone must
-- apply both candidates in order until Stage 1 is released.
do $validation$
begin
  if to_regclass('atlas.communication_conversation_events') is null then
    raise exception 'Stage 1 common Communication Conversation event membership is missing.';
  end if;

  if exists(
    select 1
    from atlas.institutional_conversations ic
    left join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=ic.id
    where root.institutional_conversation_id is null
  ) then
    raise exception 'Stage 2 cannot operate while an Institutional Conversation lacks a common root.';
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
    raise exception 'Stage 2 common timeline would omit an Institutional message event.';
  end if;
end;
$validation$;

-- Canonical APIs must be rooted in common Conversation membership, not in the
-- Institutional inbox view or an endpoint-first conversation table.
do $validation$
declare
  v_definition text;
  v_proc regprocedure;
begin
  foreach v_proc in array array[
    'atlas.organization_correspondence_list_self_api_v1(uuid,uuid,integer)'::regprocedure,
    'atlas.organization_correspondence_conversation_self_api_v1(uuid)'::regprocedure,
    'atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer)'::regprocedure
  ] loop
    select pg_get_functiondef(v_proc) into v_definition;

    if position('communication_conversations' in v_definition)=0
       or position('communication_conversation_events' in v_definition)=0 then
      raise exception 'Canonical Correspondence reader % is not rooted in common Conversation/event membership.',v_proc::text;
    end if;

    if position('organization_correspondence_read_authorized_self_v1' in v_definition)=0 then
      raise exception 'Canonical Correspondence reader % bypasses the common read authority membrane.',v_proc::text;
    end if;

    if position('v_institutional_shared_inbox_v1' in v_definition)>0 then
      raise exception 'Canonical Correspondence reader % still depends on endpoint-first Institutional inbox identity.',v_proc::text;
    end if;
  end loop;
end;
$validation$;

-- Effective institutional custody and endpoint capability remain access
-- semantics beneath the common identity root.
do $validation$
declare
  v_auth text;
  v_effective text;
begin
  select pg_get_functiondef('atlas.organization_correspondence_read_authorized_self_v1(uuid)'::regprocedure)
  into v_auth;
  select pg_get_functiondef('atlas.organization_correspondence_effective_organization_v1(uuid)'::regprocedure)
  into v_effective;

  if position('communication_conversation_endpoints' in v_auth)=0
     or position('communication_endpoint_authorized_self_v1' in v_auth)=0 then
    raise exception 'Common Correspondence read authorization no longer preserves endpoint view authority.';
  end if;

  if position('effective_communication_endpoint_organization_v1' in v_effective)=0 then
    raise exception 'Common Correspondence effective Organization no longer preserves institutional custody re-homing.';
  end if;
end;
$validation$;

-- Response Case and Company Work are read-only projected consequences.
-- Canonical Stage 2 functions are STABLE and must contain no direct data
-- mutation statement.
do $validation$
declare
  r record;
  v_definition text;
begin
  for r in
    select p.oid,p.proname,p.provolatile
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'organization_correspondence_list_self_api_v1',
        'organization_correspondence_conversation_self_api_v1',
        'organization_correspondence_search_self_api_v1',
        'organization_correspondence_sent_self_api_v1',
        'organization_correspondence_read_authorized_self_v1',
        'organization_correspondence_effective_organization_v1'
      )
  loop
    if r.provolatile<>'s' then
      raise exception 'Stage 2 read function % is not STABLE.',r.proname;
    end if;

    select lower(pg_get_functiondef(r.oid)) into v_definition;
    if v_definition ~ E'\\m(insert|update|delete|merge|truncate)\\M[[:space:]]+(into|atlas\\.|from|table)' then
      raise exception 'Stage 2 read function % contains a direct mutation statement.',r.proname;
    end if;
  end loop;
end;
$validation$;

-- Institutional public names are compatibility carriers into common identity,
-- while the preserved legacy implementations are no longer browser-executable.
do $validation$
declare
  v_inbox text;
  v_detail text;
  v_search text;
  v_sent text;
begin
  select pg_get_functiondef('atlas.institutional_shared_inbox_self_v3(uuid,integer)'::regprocedure) into v_inbox;
  select pg_get_functiondef('atlas.institutional_conversation_detail_self_v4(uuid)'::regprocedure) into v_detail;
  select pg_get_functiondef('atlas.institutional_correspondence_search_self_api_v1(text,uuid,jsonb,integer)'::regprocedure) into v_search;
  select pg_get_functiondef('atlas.institutional_sent_mail_self_v1(uuid,integer)'::regprocedure) into v_sent;

  if position('institutional_conversation_roots' in v_inbox)=0
     or position('organization_correspondence_read_authorized_self_v1' in v_inbox)=0 then
    raise exception 'Institutional inbox v3 does not cross the common Conversation membrane.';
  end if;

  if position('organization_correspondence_conversation_self_api_v1' in v_detail)=0 then
    raise exception 'Institutional detail v4 does not read common Conversation first.';
  end if;

  if position('organization_correspondence_search_self_api_v1' in v_search)=0 then
    raise exception 'Institutional search is not a compatibility carrier over common search.';
  end if;

  if position('organization_correspondence_sent_self_api_v1' in v_sent)=0 then
    raise exception 'Institutional sent mail is not a compatibility carrier over common sent correspondence.';
  end if;

  if has_function_privilege('authenticated','atlas.institutional_shared_inbox_legacy_v3(uuid,integer)','EXECUTE')
     or has_function_privilege('authenticated','atlas.institutional_conversation_detail_legacy_v4(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.institutional_correspondence_search_legacy_v1(text,uuid,jsonb,integer)','EXECUTE')
     or has_function_privilege('authenticated','atlas.institutional_sent_mail_legacy_v1(uuid,integer)','EXECUTE') then
    raise exception 'Authenticated browser can bypass common identity through a preserved legacy reader.';
  end if;
end;
$validation$;

-- Direct tables stay closed. Canonical self APIs are explicitly browser-readable.
do $validation$
begin
  if has_table_privilege('authenticated','atlas.communication_conversations','SELECT')
     or has_table_privilege('authenticated','atlas.communication_conversation_endpoints','SELECT')
     or has_table_privilege('authenticated','atlas.communication_conversation_events','SELECT') then
    raise exception 'Authenticated direct table access bypasses the Correspondence membrane.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_correspondence_list_self_api_v1(uuid,uuid,integer)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_conversation_self_api_v1(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_search_self_api_v1(text,uuid,uuid,jsonb,integer)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_sent_self_api_v1(uuid,uuid,integer)','EXECUTE') then
    raise exception 'Canonical Organization Correspondence self API grant is incomplete.';
  end if;

  if has_function_privilege('authenticated','atlas.organization_correspondence_effective_organization_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.organization_correspondence_read_authorized_self_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated browser can call an internal Correspondence authority helper directly.';
  end if;
end;
$validation$;

rollback;

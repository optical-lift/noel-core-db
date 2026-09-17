-- Validation for Package 7 Communications convergence Stage 4.
-- Requires Stage 3 to be present in the receiving schema.

begin;

-- Stage dependency and common custody columns.
do $validation$
begin
  if to_regprocedure('atlas.communication_event_actionability_packet_v2(uuid)') is null
     or to_regprocedure('atlas.adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid)') is null then
    raise exception 'Stage 4 requires the released Stage 3 actionability cutover.';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_email_drafts'
      and column_name='communication_conversation_id' and data_type='uuid'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_outbound_operations'
      and column_name='communication_conversation_id' and data_type='uuid'
  ) then
    raise exception 'Stage 4 common Conversation custody columns are missing.';
  end if;

  if to_regclass('atlas.communication_email_drafts_common_conversation_idx') is null
     or to_regclass('atlas.communication_outbound_operations_common_conversation_idx') is null then
    raise exception 'Stage 4 common Conversation consequence indexes are missing.';
  end if;
end;
$validation$;

-- Existing consequence rows must already satisfy paired common/compatibility custody.
do $validation$
begin
  if exists (
    select 1
    from atlas.communication_outbound_operations operation
    left join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=operation.institutional_conversation_id
    where operation.communication_conversation_id is null
       or operation.institutional_conversation_id is null
       or root.communication_conversation_id is distinct from operation.communication_conversation_id
  ) then
    raise exception 'Outbound operation exists outside one common Conversation root.';
  end if;

  if exists (
    select 1
    from atlas.communication_email_drafts draft
    left join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=draft.institutional_conversation_id
    where (draft.communication_conversation_id is null) <> (draft.institutional_conversation_id is null)
       or (draft.communication_conversation_id is not null
           and root.communication_conversation_id is distinct from draft.communication_conversation_id)
       or (draft.reply_to_communication_event_id is not null
           and draft.communication_conversation_id is null)
  ) then
    raise exception 'Draft conversation custody is one-sided, mismatched, or an unbound reply.';
  end if;
end;
$validation$;

-- Root translation remains symmetric.
do $validation$
declare
  v_root record;
begin
  select root.institutional_conversation_id,root.communication_conversation_id
  into v_root
  from atlas.institutional_conversation_roots root
  order by root.created_at,root.institutional_conversation_id
  limit 1;

  if v_root.institutional_conversation_id is not null then
    if atlas.require_common_communication_conversation_for_institutional_v1(
         v_root.institutional_conversation_id
       ) is distinct from v_root.communication_conversation_id
       or atlas.require_institutional_compatibility_for_communication_conversation_v1(
         v_root.communication_conversation_id
       ) is distinct from v_root.institutional_conversation_id then
      raise exception 'Common/Institutional root translation is not symmetric.';
    end if;
  end if;
end;
$validation$;

-- Deferred consequence guard must re-read final persisted rows and preserve exact
-- reply Conversation + Endpoint continuity. Normalize whitespace before testing.
do $validation$
declare
  v_definition text;
  v_compact text;
begin
  select lower(pg_get_functiondef('atlas.guard_communication_consequence_common_root_v1()'::regprocedure))
  into v_definition;
  v_compact:=regexp_replace(v_definition,'[[:space:]]+','','g');

  if position('fromatlas.communication_outbound_operations' in v_compact)=0
     or position('fromatlas.communication_email_drafts' in v_compact)=0
     or position('whereoperation.id=new.id' in v_compact)=0
     or position('wheredraft.id=new.id' in v_compact)=0
     or position('v_reply_common_idisdistinctfromv_common_id' in v_compact)=0
     or position('v_reply_endpoint_idisdistinctfromv_endpoint_id' in v_compact)=0 then
    raise exception 'Deferred consequence guard lost final-state or exact reply continuity.';
  end if;
end;
$validation$;

-- Both final-state guards are deferred constraint triggers.
do $validation$
begin
  if not exists (
    select 1
    from pg_trigger trigger
    join pg_constraint constraint_row on constraint_row.oid=trigger.tgconstraint
    where trigger.tgrelid='atlas.communication_email_drafts'::regclass
      and trigger.tgname='communication_email_draft_common_root_guard_v1'
      and not trigger.tgisinternal
      and constraint_row.condeferrable and constraint_row.condeferred
  ) or not exists (
    select 1
    from pg_trigger trigger
    join pg_constraint constraint_row on constraint_row.oid=trigger.tgconstraint
    where trigger.tgrelid='atlas.communication_outbound_operations'::regclass
      and trigger.tgname='communication_outbound_operation_common_root_guard_v1'
      and not trigger.tgisinternal
      and constraint_row.condeferrable and constraint_row.condeferred
  ) then
    raise exception 'Stage 4 deferred consequence root guards are missing.';
  end if;
end;
$validation$;

-- New outbound intent creates common identity before Institutional compatibility.
do $validation$
declare
  v_definition text;
  v_common_insert int;
  v_institutional_insert int;
  v_root_insert int;
begin
  select lower(pg_get_functiondef(
    'atlas.ensure_organization_communication_command_pair_service_v1(uuid,uuid,uuid,uuid,uuid,text,boolean)'::regprocedure
  )) into v_definition;

  v_common_insert:=position('insert into atlas.communication_conversations' in v_definition);
  v_institutional_insert:=position('insert into atlas.institutional_conversations' in v_definition);
  v_root_insert:=position('insert into atlas.institutional_conversation_roots' in v_definition);

  if v_common_insert=0 or v_institutional_insert=0 or v_root_insert=0
     or v_common_insert>v_institutional_insert
     or v_institutional_insert>v_root_insert
     or position('communication_conversation_events' in v_definition)=0
     or position('reply command must use the exact communication endpoint of the source event' in v_definition)=0 then
    raise exception 'Outbound command pair violates common-first or exact reply continuity.';
  end if;
end;
$validation$;

-- Send v3 resolves the pair before legacy transport and persists common custody.
do $validation$
declare
  v_definition text;
  v_compact text;
  v_pair_pos int;
  v_legacy_pos int;
begin
  select lower(pg_get_functiondef(
    'atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text)'::regprocedure
  )) into v_definition;
  v_compact:=regexp_replace(v_definition,'[[:space:]]+','','g');
  v_pair_pos:=position('ensure_organization_communication_command_pair_service_v1' in v_definition);
  v_legacy_pos:=position('prepare_institutional_email_send_internal_v2' in v_definition);

  if v_pair_pos=0 or v_legacy_pos=0 or v_pair_pos>v_legacy_pos
     or position('communication_conversation_id=v_common_id' in v_compact)=0 then
    raise exception 'Outbound send v3 bypasses common command custody.';
  end if;
end;
$validation$;

-- Legacy browser send, immediate draft authorization, and scheduled draft release
-- all route through the common-root send membrane.
do $validation$
declare
  v_send text;
  v_authorize text;
  v_release text;
begin
  select lower(pg_get_functiondef(
    'atlas.prepare_institutional_email_send_self_api_v1(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)'::regprocedure
  )) into v_send;
  select lower(pg_get_functiondef(
    'atlas.authorize_communication_email_draft_self_api_v1(uuid)'::regprocedure
  )) into v_authorize;
  select lower(pg_get_functiondef(
    'atlas.release_due_communication_email_drafts_service_v1(integer)'::regprocedure
  )) into v_release;

  if position('prepare_communication_email_send_internal_v3' in v_send)=0
     or position('prepare_institutional_email_send_internal_v2' in v_send)>0
     or position('prepare_communication_email_send_internal_v3' in v_authorize)=0
     or position('prepare_institutional_email_send_internal_v2' in v_authorize)>0
     or position('prepare_communication_email_send_internal_v3' in v_release)=0
     or position('prepare_institutional_email_send_internal_v2' in v_release)>0 then
    raise exception 'A legacy send/draft-release entrypoint bypasses send v3.';
  end if;
end;
$validation$;

-- Common draft v2 binds reply Event, common Conversation, and exact Endpoint.
do $validation$
declare
  v_definition text;
  v_compact text;
begin
  select lower(pg_get_functiondef(
    'atlas.save_communication_email_draft_self_api_v2(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)'::regprocedure
  )) into v_definition;
  v_compact:=regexp_replace(v_definition,'[[:space:]]+','','g');

  if position('communication_conversation_events' in v_definition)=0
     or position('v_reply_endpoint_idisdistinctfromp_communication_endpoint_id' in v_compact)=0
     or position('require_institutional_compatibility_for_communication_conversation_v1' in v_definition)=0 then
    raise exception 'Common draft v2 lacks exact reply custody.';
  end if;
end;
$validation$;

-- Response, collaboration, response-state, and Work-context commands use common
-- Conversation as their public identifier and translate compatibility internally.
do $validation$
declare
  v_signature text;
  v_definition text;
begin
  foreach v_signature in array array[
    'claim_communication_conversation_self_api_v1(uuid,text)',
    'handoff_communication_conversation_self_api_v1(uuid,uuid,text)',
    'add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)',
    'remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)',
    'set_communication_conversation_response_state_self_api_v1(uuid,text,text)',
    'communication_work_context_candidates_self_v2(uuid,text)'
  ] loop
    if to_regprocedure('atlas.'||v_signature) is null then
      raise exception 'Missing common Conversation consequence API %.',v_signature;
    end if;
    execute format('select lower(pg_get_functiondef(%L::regprocedure))','atlas.'||v_signature)
    into v_definition;
    if position('require_institutional_compatibility_for_communication_conversation_v1' in v_definition)=0 then
      raise exception 'Common consequence API % bypasses compatibility translation.',v_signature;
    end if;
  end loop;
end;
$validation$;

-- Company Work creation requires exact Event membership in the common Conversation.
do $validation$
declare
  v_definition text;
  v_compact text;
begin
  select lower(pg_get_functiondef(
    'atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text)'::regprocedure
  )) into v_definition;
  v_compact:=regexp_replace(v_definition,'[[:space:]]+','','g');

  if position('communication_conversation_events' in v_definition)=0
     or position('membership.communication_conversation_id=p_communication_conversation_id' in v_compact)=0
     or position('membership.communication_event_id=p_communication_event_id' in v_compact)=0
     or position('communicationcommandroot' in v_definition)=0 then
    raise exception 'Communication-derived Work v3 lacks exact common Conversation/Event custody.';
  end if;
end;
$validation$;

-- Mailbox disposition remains endpoint-scoped.
do $validation$
begin
  if to_regprocedure('atlas.set_communication_conversation_disposition_self_api_v1(uuid,text,text)') is not null then
    raise exception 'Stage 4 incorrectly promoted mailbox disposition to common Conversation authority.';
  end if;
end;
$validation$;

-- Browser privilege membrane.
do $validation$
begin
  if has_function_privilege('authenticated','atlas.require_institutional_compatibility_for_communication_conversation_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.require_common_communication_conversation_for_institutional_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.ensure_organization_communication_command_pair_service_v1(uuid,uuid,uuid,uuid,uuid,text,boolean)','EXECUTE')
     or has_function_privilege('authenticated','atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)','EXECUTE') then
    raise exception 'Authenticated browser can bypass Stage 4 command custody.';
  end if;

  if not has_function_privilege('authenticated','atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.save_communication_email_draft_self_api_v2(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.claim_communication_conversation_self_api_v1(uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text)','EXECUTE') then
    raise exception 'Authenticated browser lacks Stage 4 common Conversation command APIs.';
  end if;
end;
$validation$;

-- Only ordinary functions are valid inputs to pg_get_functiondef; exclude
-- aggregates/windows/procedures before scanning for bypasses of send v3.
do $validation$
declare
  v_bypass_count integer;
begin
  select count(*)
  into v_bypass_count
  from pg_proc function
  join pg_namespace namespace on namespace.oid=function.pronamespace
  where namespace.nspname='atlas'
    and function.prokind='f'
    and function.proname not in ('prepare_institutional_email_send_internal_v2','prepare_communication_email_send_internal_v3')
    and lower(pg_get_functiondef(function.oid)) like '%prepare_institutional_email_send_internal_v2%';

  if v_bypass_count<>0 then
    raise exception 'A Communication function still bypasses send v3 and calls old internal v2 directly: % function(s).',v_bypass_count;
  end if;
end;
$validation$;

rollback;

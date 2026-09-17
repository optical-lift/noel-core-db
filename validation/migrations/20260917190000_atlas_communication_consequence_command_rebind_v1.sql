-- Validation for Package 7 Communications convergence Stage 4.
-- Requires Stage 3 to be present in the receiving schema.

begin;

-- Stage 4 must never be validated against a Stage-2-only receiving schema.
do $validation$
begin
  if to_regprocedure('atlas.communication_event_actionability_packet_v2(uuid)') is null
     or to_regprocedure('atlas.adjudicate_communication_actionability_service_v1(uuid,text,jsonb,uuid)') is null then
    raise exception 'Stage 4 requires the released Stage 3 actionability cutover.';
  end if;
end;
$validation$;

-- Common Conversation custody columns exist on both draft and outbound consequence rows.
do $validation$
begin
  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_email_drafts'
      and column_name='communication_conversation_id' and data_type='uuid'
  ) then
    raise exception 'Draft common Conversation custody column is missing.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_outbound_operations'
      and column_name='communication_conversation_id' and data_type='uuid'
  ) then
    raise exception 'Outbound common Conversation custody column is missing.';
  end if;

  if to_regclass('atlas.communication_email_drafts_common_conversation_idx') is null
     or to_regclass('atlas.communication_outbound_operations_common_conversation_idx') is null then
    raise exception 'Stage 4 common Conversation consequence indexes are missing.';
  end if;
end;
$validation$;

-- Existing rows, if any, must be either a lawful unbound draft or a complete
-- common+compatibility pair. Outbound operations are never allowed unbound.
do $validation$
begin
  if exists(
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

  if exists(
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

-- Root translation is one-to-one and preserves Organization custody.
do $validation$
declare
  v_root record;
  v_common uuid;
  v_institutional uuid;
begin
  select root.institutional_conversation_id,root.communication_conversation_id
  into v_root
  from atlas.institutional_conversation_roots root
  order by root.created_at,root.institutional_conversation_id
  limit 1;

  if v_root.institutional_conversation_id is not null then
    v_common:=atlas.require_common_communication_conversation_for_institutional_v1(
      v_root.institutional_conversation_id
    );
    v_institutional:=atlas.require_institutional_compatibility_for_communication_conversation_v1(
      v_root.communication_conversation_id
    );

    if v_common is distinct from v_root.communication_conversation_id
       or v_institutional is distinct from v_root.institutional_conversation_id then
      raise exception 'Common/Institutional root translation is not symmetric.';
    end if;
  end if;
end;
$validation$;

-- The deferred final-state guard must re-read rows rather than trust the NEW
-- image captured before a compatibility wrapper's later update.
do $validation$
declare
  v_definition text;
begin
  select lower(pg_get_functiondef('atlas.guard_communication_consequence_common_root_v1()'::regprocedure))
  into v_definition;

  if position('from atlas.communication_outbound_operations' in v_definition)=0
     or position('from atlas.communication_email_drafts' in v_definition)=0
     or position('where operation.id = new.id' in v_definition)=0
     or position('where draft.id = new.id' in v_definition)=0 then
    raise exception 'Deferred consequence guard does not re-read final row state.';
  end if;

  if position('reply consequence must preserve exact common conversation and communication endpoint continuity' in v_definition)=0 then
    raise exception 'Deferred consequence guard lost exact reply endpoint continuity.';
  end if;
end;
$validation$;

-- Both deferred guards must be installed.
do $validation$
begin
  if not exists(
    select 1 from pg_trigger
    where tgrelid='atlas.communication_email_drafts'::regclass
      and tgname='communication_email_draft_common_root_guard_v1'
      and not tgisinternal
  ) then
    raise exception 'Draft common-root constraint trigger is missing.';
  end if;

  if not exists(
    select 1 from pg_trigger
    where tgrelid='atlas.communication_outbound_operations'::regclass
      and tgname='communication_outbound_operation_common_root_guard_v1'
      and not tgisinternal
  ) then
    raise exception 'Outbound common-root constraint trigger is missing.';
  end if;
end;
$validation$;

-- New outbound intent must create common identity before compatibility identity.
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
     or v_institutional_insert>v_root_insert then
    raise exception 'New outbound command pair does not create common Conversation before compatibility/root.';
  end if;

  if position('communication_conversation_events' in v_definition)=0
     or position('reply command must use the exact communication endpoint of the source event' in v_definition)=0 then
    raise exception 'Outbound command pair does not preserve exact reply Event continuity.';
  end if;
end;
$validation$;

-- Common-root send v3 must resolve/create the pair before delegating transport
-- authority to the historical internal v2 implementation.
do $validation$
declare
  v_definition text;
  v_pair_pos int;
  v_legacy_pos int;
begin
  select lower(pg_get_functiondef(
    'atlas.prepare_communication_email_send_internal_v3(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text)'::regprocedure
  )) into v_definition;

  v_pair_pos:=position('ensure_organization_communication_command_pair_service_v1' in v_definition);
  v_legacy_pos:=position('prepare_institutional_email_send_internal_v2' in v_definition);
  if v_pair_pos=0 or v_legacy_pos=0 or v_pair_pos>v_legacy_pos then
    raise exception 'Outbound send v3 does not establish common command identity before compatibility transport authorization.';
  end if;

  if position('communication_conversation_id = v_common_id' in v_definition)=0 then
    raise exception 'Outbound send v3 does not persist common Conversation custody on the operation.';
  end if;
end;
$validation$;

-- Every live legacy browser/send-draft entrypoint must flow through the common
-- command membrane rather than calling internal v2 directly.
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
     or position('prepare_institutional_email_send_internal_v2' in v_send)>0 then
    raise exception 'Legacy browser send bypasses the common Conversation command membrane.';
  end if;
  if position('prepare_communication_email_send_internal_v3' in v_authorize)=0
     or position('prepare_institutional_email_send_internal_v2' in v_authorize)>0 then
    raise exception 'Draft authorization bypasses the common Conversation command membrane.';
  end if;
  if position('prepare_communication_email_send_internal_v3' in v_release)=0
     or position('prepare_institutional_email_send_internal_v2' in v_release)>0 then
    raise exception 'Scheduled draft release bypasses the common Conversation command membrane.';
  end if;
end;
$validation$;

-- Draft compatibility implementation is private; common v2 is the new public
-- contract. Reply drafts must derive both common Conversation and exact endpoint.
do $validation$
declare
  v_definition text;
begin
  select lower(pg_get_functiondef(
    'atlas.save_communication_email_draft_self_api_v2(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)'::regprocedure
  )) into v_definition;

  if position('communication_conversation_events' in v_definition)=0
     or position('v_reply_endpoint_id is distinct from p_communication_endpoint_id' in v_definition)=0
     or position('require_institutional_compatibility_for_communication_conversation_v1' in v_definition)=0 then
    raise exception 'Common draft v2 does not prove reply Conversation/Endpoint continuity.';
  end if;
end;
$validation$;

-- Response/handoff/collaboration/context/work APIs use common Conversation as
-- their public identifier and only then resolve the compatibility carrier.
do $validation$
declare
  v_name text;
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
      raise exception 'Common consequence API % bypasses the compatibility resolver.',v_signature;
    end if;
  end loop;
end;
$validation$;

-- Work creation must bind an exact Event that belongs to the common Conversation.
do $validation$
declare
  v_definition text;
begin
  select lower(pg_get_functiondef(
    'atlas.create_communication_derived_work_self_api_v3(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,jsonb,text)'::regprocedure
  )) into v_definition;

  if position('communication_conversation_events' in v_definition)=0
     or position('membership.communication_conversation_id = p_communication_conversation_id' in v_definition)=0
     or position('membership.communication_event_id = p_communication_event_id' in v_definition)=0
     or position('communicationcommandroot' in v_definition)=0 then
    raise exception 'Communication-derived Work v3 lacks exact common Conversation/Event custody.';
  end if;
end;
$validation$;

-- Stage 4 intentionally does NOT create a common-level mailbox disposition API.
-- Disposition remains endpoint/mailbox state until Product cutover supplies an
-- explicit endpoint context.
do $validation$
begin
  if to_regprocedure('atlas.set_communication_conversation_disposition_self_api_v1(uuid,text,text)') is not null then
    raise exception 'Stage 4 incorrectly promoted endpoint mailbox disposition to common Conversation authority.';
  end if;
end;
$validation$;

-- Privilege boundary: browser sees new self APIs, never internal compatibility
-- or root-resolution authority.
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

-- No current service/browser function besides the Stage 4 v3 compatibility
-- membrane may call the old send internal v2 implementation.
do $validation$
declare
  v_bypass_count integer;
begin
  select count(*)
  into v_bypass_count
  from pg_proc function
  join pg_namespace namespace on namespace.oid=function.pronamespace
  where namespace.nspname='atlas'
    and function.proname not in ('prepare_institutional_email_send_internal_v2','prepare_communication_email_send_internal_v3')
    and lower(pg_get_functiondef(function.oid)) like '%prepare_institutional_email_send_internal_v2%';

  if v_bypass_count<>0 then
    raise exception 'A Communication function still bypasses send v3 and calls old internal v2 directly: % function(s).',v_bypass_count;
  end if;
end;
$validation$;

rollback;

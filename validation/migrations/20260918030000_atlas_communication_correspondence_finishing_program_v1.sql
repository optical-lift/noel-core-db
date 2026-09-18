begin;

do $validation$
declare
  v_count bigint;
begin
  if to_regclass('atlas.communication_conversation_notes') is null
     or to_regclass('atlas.communication_conversation_note_mentions') is null
     or to_regclass('atlas.communication_conversation_followups') is null
     or to_regclass('atlas.communication_conversation_activity_events') is null then
    raise exception 'Communication collaboration tables are missing.';
  end if;

  if to_regprocedure('atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)') is null
     or to_regprocedure('atlas.save_communication_email_draft_self_api_v3(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)') is null
     or to_regprocedure('atlas.organization_correspondence_drafts_self_api_v2(uuid,uuid,uuid,integer)') is null
     or to_regprocedure('atlas.record_communication_conversation_note_self_api_v1(uuid,text,jsonb)') is null
     or to_regprocedure('atlas.schedule_communication_conversation_followup_self_api_v1(uuid,timestamptz,text)') is null
     or to_regprocedure('atlas.takeover_communication_email_draft_self_api_v1(uuid,text)') is null
     or to_regprocedure('atlas.organization_correspondence_attention_summary_self_api_v2(uuid)') is null
     or to_regprocedure('atlas.organization_correspondence_list_self_api_v3(uuid,uuid,integer)') is null
     or to_regprocedure('atlas.organization_correspondence_conversation_self_api_v5(uuid)') is null then
    raise exception 'Communication finishing-program API surface is incomplete.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_email_drafts'
      and column_name='composition_kind'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_email_drafts'
      and column_name='source_communication_event_id'
  ) then
    raise exception 'Draft composition provenance is missing.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_outbound_operations'
      and column_name='composition_kind'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='communication_outbound_operations'
      and column_name='source_communication_event_id'
  ) then
    raise exception 'Outbound composition provenance is missing.';
  end if;

  select count(*) into v_count
  from atlas.communication_email_drafts
  where (composition_kind in ('reply','reply_all') and source_communication_event_id is distinct from reply_to_communication_event_id)
     or (composition_kind='forward' and (source_communication_event_id is null or reply_to_communication_event_id is not null))
     or (composition_kind='compose' and (source_communication_event_id is not null or reply_to_communication_event_id is not null));
  if v_count<>0 then raise exception 'Existing draft provenance violates the exact Event contract.'; end if;

  select count(*) into v_count
  from atlas.communication_outbound_operations
  where (composition_kind in ('reply','reply_all') and source_communication_event_id is distinct from reply_to_communication_event_id)
     or (composition_kind='forward' and (source_communication_event_id is null or reply_to_communication_event_id is not null))
     or (composition_kind='compose' and (source_communication_event_id is not null or reply_to_communication_event_id is not null));
  if v_count<>0 then raise exception 'Existing outbound provenance violates the exact Event contract.'; end if;

  if exists(
    select 1 from information_schema.role_table_grants
    where table_schema='atlas'
      and table_name in (
        'communication_conversation_notes',
        'communication_conversation_note_mentions',
        'communication_conversation_followups',
        'communication_conversation_activity_events'
      )
      and grantee in ('anon','authenticated')
  ) then
    raise exception 'Internal communication collaboration tables must not be directly exposed to browser roles.';
  end if;

  if has_function_privilege('anon','atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)','EXECUTE')
     or has_function_privilege('anon','atlas.record_communication_conversation_note_self_api_v1(uuid,text,jsonb)','EXECUTE')
     or has_function_privilege('anon','atlas.schedule_communication_conversation_followup_self_api_v1(uuid,timestamptz,text)','EXECUTE')
     or has_function_privilege('anon','atlas.takeover_communication_email_draft_self_api_v1(uuid,text)','EXECUTE') then
    raise exception 'Authenticated Communication commands are exposed to anon.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.save_communication_email_draft_self_api_v3(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_conversation_self_api_v5(uuid)','EXECUTE') then
    raise exception 'Authenticated Communication finishing-program commands are not callable.';
  end if;

  if position('participant_role=''cc''' in pg_get_functiondef(
       'atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)'::regprocedure
     ))=0
     or position('not p.is_self' in pg_get_functiondef(
       'atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)'::regprocedure
     ))=0
     or position('participant_role=''bcc''' in pg_get_functiondef(
       'atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text)'::regprocedure
     ))<>0 then
    raise exception 'Reply All proposal must derive exact non-self sender/To/CC evidence and must not inherit BCC.';
  end if;

  if position('source_communication_event_id' in pg_get_functiondef(
       'atlas.organization_correspondence_conversation_self_api_v5(uuid)'::regprocedure
     ))=0
     or position('communication_conversation_activity_events' in pg_get_functiondef(
       'atlas.organization_correspondence_conversation_self_api_v5(uuid)'::regprocedure
     ))=0 then
    raise exception 'Conversation v5 does not expose governed draft/activity provenance.';
  end if;
end;
$validation$;

rollback;

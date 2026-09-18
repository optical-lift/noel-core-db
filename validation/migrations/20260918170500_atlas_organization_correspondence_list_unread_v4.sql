begin;

do $validation$
begin
  if to_regprocedure('atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)') is null then
    raise exception 'organization_correspondence_list_self_api_v4 is missing.';
  end if;

  if has_function_privilege('anon','atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)','EXECUTE') then
    raise exception 'anon may not execute organization_correspondence_list_self_api_v4.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)','EXECUTE') then
    raise exception 'authenticated must execute organization_correspondence_list_self_api_v4.';
  end if;

  if to_regclass('atlas.communication_conversation_endpoint_disposition_events') is null then
    raise exception 'Common Conversation + Endpoint mailbox disposition history is missing.';
  end if;

  if has_table_privilege('authenticated','atlas.communication_conversation_endpoint_disposition_events','SELECT')
     or has_table_privilege('authenticated','atlas.communication_conversation_endpoint_disposition_events','INSERT')
     or has_table_privilege('authenticated','atlas.communication_conversation_endpoint_disposition_events','UPDATE')
     or has_table_privilege('authenticated','atlas.communication_conversation_endpoint_disposition_events','DELETE') then
    raise exception 'Authenticated clients may not directly access common mailbox disposition history.';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger
    join pg_class rel on rel.oid=trigger.tgrelid
    join pg_namespace ns on ns.oid=rel.relnamespace
    where ns.nspname='atlas'
      and rel.relname='communication_conversation_endpoint_disposition_events'
      and trigger.tgname='communication_conversation_endpoint_disposition_append_only_v1'
      and not trigger.tgisinternal
  ) then
    raise exception 'Common mailbox disposition history lost append-only protection.';
  end if;

  if exists (
    select 1
    from atlas.institutional_conversation_disposition_events legacy
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=legacy.institutional_conversation_id
    where not exists (
      select 1
      from atlas.communication_conversation_endpoint_disposition_events common
      where common.communication_conversation_id=root.communication_conversation_id
        and common.communication_endpoint_id=legacy.communication_endpoint_id
        and common.disposition=legacy.disposition
        and common.created_at=legacy.created_at
        and common.metadata->>'sourceInstitutionalDispositionEventId'=legacy.id::text
    )
  ) then
    raise exception 'Legacy mailbox disposition history was not completely preserved in common custody.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='organization_correspondence_list_self_api_v4'
      and p.prosrc ilike '%communication_attention_events%'
      and p.prosrc ilike '%openedByMe%'
      and p.prosrc ilike '%latestAttentionKind%'
      and p.prosrc ilike '%organization_correspondence_list_self_api_v3%'
      and p.prosrc ilike '%viewerMembershipId%'
      and p.prosrc ilike '%organization_memberships%'
      and p.prosrc ilike '%communication_event_participants%'
      and p.prosrc ilike '%speakerDisplayName%'
      and p.prosrc ilike '%communication_conversation_endpoint_disposition_events%'
      and p.prosrc ilike '%mailboxDisposition%'
  ) then
    raise exception 'Correspondence list v4 lost common mailbox, viewer membership, sender identity, or exact Event attention dependency.';
  end if;

  if to_regprocedure('atlas.organization_correspondence_conversation_self_api_v6(uuid)') is null
     or has_function_privilege('anon','atlas.organization_correspondence_conversation_self_api_v6(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_conversation_self_api_v6(uuid)','EXECUTE') then
    raise exception 'Common Correspondence detail v6 authority is malformed.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='organization_correspondence_conversation_self_api_v6'
      and p.prosrc ilike '%organization_correspondence_conversation_self_api_v5%'
      and p.prosrc ilike '%communication_conversation_endpoint_disposition_events%'
  ) then
    raise exception 'Common Correspondence detail v6 lost common mailbox dependency.';
  end if;

  if to_regprocedure('atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer)') is null
     or has_function_privilege('anon','atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer)','EXECUTE') then
    raise exception 'Common Correspondence search v2 authority is malformed.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='organization_correspondence_search_self_api_v2'
      and p.prosrc ilike '%organization_correspondence_search_self_api_v1%'
      and p.prosrc ilike '%communication_conversation_endpoint_disposition_events%'
      and p.prosrc ilike '%p_filters%'
      and p.prosrc ilike '%disposition%'
  ) then
    raise exception 'Common Correspondence search v2 lost common mailbox dependency.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname='set_communication_conversation_endpoint_disposition_self_api_v1'
      and p.prosrc ilike '%communication_conversation_endpoint_disposition_events%'
      and p.prosrc ilike '%communication_conversation_endpoint_disposition_v2%'
      and p.prosrc not ilike '%institutional_conversation_disposition_events%'
      and p.prosrc not ilike '%institutional_conversation_roots%'
      and p.prosrc not ilike '%Institutional compatibility carrier%'
  ) then
    raise exception 'Mailbox disposition setter did not cut over completely to common Conversation custody.';
  end if;
end;
$validation$;

rollback;

begin;

-- Package 7 / Stage 5:
-- expose email drafts without reusing Institutional Conversation identity.
-- Draft is its own durable identity; when bound, its command/root Conversation is
-- the common Communication Conversation. Institutional ids remain compatibility
-- metadata only.

create or replace function atlas.organization_correspondence_drafts_self_api_v1(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_communication_conversation_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_limit < 1 or p_limit > 500 then
    raise exception 'Draft limit must be between 1 and 500.' using errcode='22023';
  end if;

  if p_communication_endpoint_id is not null
     and not atlas.communication_endpoint_authorized_self_v1(p_communication_endpoint_id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  if p_communication_conversation_id is not null
     and not atlas.organization_correspondence_read_authorized_self_v1(p_communication_conversation_id) then
    raise exception 'Communication Conversation read authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'draftId',q.id,
    'communicationEndpointId',q.communication_endpoint_id,
    'communicationConversationId',q.communication_conversation_id,
    'institutionalCompatibilityId',q.institutional_conversation_id,
    'replyToCommunicationEventId',q.reply_to_communication_event_id,
    'authorMembershipId',q.author_membership_id,
    'authorLabel',q.author_label,
    'isMine',q.is_mine,
    'to',case when q.is_mine then q.to_recipients else '[]'::jsonb end,
    'cc',case when q.is_mine then q.cc_recipients else '[]'::jsonb end,
    'bcc',case when q.is_mine then q.bcc_recipients else '[]'::jsonb end,
    'subject',q.subject,
    'bodyText',case when q.is_mine then q.body_text else null end,
    'bodyHtml',case when q.is_mine then q.body_html else null end,
    'attachmentRefs',case when q.is_mine then q.attachment_refs else '[]'::jsonb end,
    'attachments',case when q.is_mine then coalesce((
      select jsonb_agg(jsonb_build_object(
        'attachmentId',a.id,
        'fileName',a.file_name,
        'mimeType',a.mime_type,
        'state',a.attachment_state,
        'storageBucket',a.storage_bucket,
        'storageObjectPath',a.storage_object_path,
        'byteLength',a.byte_length,
        'sha256',a.sha256
      ) order by a.created_at,a.id)
      from atlas.communication_outbound_attachments a
      where a.id::text in (
        select ref.value #>> '{}'
        from jsonb_array_elements(q.attachment_refs) ref(value)
      )
    ),'[]'::jsonb) else '[]'::jsonb end,
    'signatureId',case when q.is_mine then q.signature_id else null end,
    'sendAfter',q.send_after,
    'state',q.draft_state,
    'version',q.version,
    'updatedAt',q.updated_at,
    'commandRoot',case when q.communication_conversation_id is null then 'unbound_draft' else 'communication_conversation' end
  ) order by q.updated_at desc,q.id),'[]'::jsonb)
  into v_items
  from (
    select
      d.*,
      coalesce(up.display_name,u.email,d.author_membership_id::text) as author_label,
      (author.user_id=auth.uid()) as is_mine
    from atlas.communication_email_drafts d
    join atlas.communication_endpoints ep
      on ep.id=d.communication_endpoint_id
     and ep.endpoint_state='active'
    join atlas.organization_memberships viewer
      on viewer.organization_id=ep.organization_id
     and viewer.user_id=auth.uid()
     and viewer.active
    join atlas.organization_memberships author
      on author.id=d.author_membership_id
    left join auth.users u on u.id=author.user_id
    left join atlas.user_profiles up on up.user_id=author.user_id
    where d.draft_state in ('active','scheduled')
      and atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer.id,'view')
      and (p_organization_id is null or ep.organization_id=p_organization_id)
      and (p_communication_endpoint_id is null or d.communication_endpoint_id=p_communication_endpoint_id)
      and (p_communication_conversation_id is null or d.communication_conversation_id=p_communication_conversation_id)
    order by d.updated_at desc,d.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_drafts_v1',
    'identityRoot','communication_email_draft',
    'conversationRoot','communication_conversation',
    'organizationId',p_organization_id,
    'communicationEndpointFilterId',p_communication_endpoint_id,
    'communicationConversationFilterId',p_communication_conversation_id,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_drafts_self_api_v1(uuid,uuid,uuid,integer) from public,anon;
grant execute on function atlas.organization_correspondence_drafts_self_api_v1(uuid,uuid,uuid,integer) to authenticated,service_role;

commit;

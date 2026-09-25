create or replace function atlas.require_institutional_communication_operation_self_v1(
  p_communication_endpoint_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_resolution jsonb;
begin
  v_resolution:=atlas.resolve_institutional_communication_operation_self_v1(
    p_communication_endpoint_id,p_operation_key
  );

  if not coalesce((v_resolution->>'allowed')::boolean,false) then
    raise exception 'Institutional communication operation % is not authorized: %.',
      p_operation_key,coalesce(v_resolution->>'reason','not_authorized')
      using errcode='42501';
  end if;

  if nullif(v_resolution->>'legacyCarrierMembershipId','') is null then
    raise exception 'Authorized communication operation has no usable legacy carrier.'
      using errcode='42501';
  end if;

  return v_resolution;
end
$function$;

revoke all on function atlas.require_institutional_communication_operation_self_v1(uuid,text)
  from public,anon,authenticated;

create or replace function atlas.assert_communication_send_response_boundary_self_v1(
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_institutional_id uuid;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_claim_resolution jsonb;
begin
  if p_communication_conversation_id is null then
    return;
  end if;

  v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(
    p_communication_conversation_id
  );

  if not exists(
    select 1
    from atlas.institutional_conversation_endpoints ce
    where ce.institutional_conversation_id=v_institutional_id
      and ce.communication_endpoint_id=p_communication_endpoint_id
  ) then
    raise exception 'Conversation is outside the requested Communication Endpoint.'
      using errcode='42501';
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases c
  where c.institutional_conversation_id=v_institutional_id
    and c.case_state not in ('complete','informational')
  order by c.case_number desc
  limit 1;

  if v_case.id is null or v_case.case_state<>'unclaimed' then
    return;
  end if;

  select * into v_binding
  from atlas.institutional_conversation_response_work_bindings b
  where b.response_case_id=v_case.id;

  if v_binding.id is not null then
    select * into v_current
    from atlas.work_allocations a
    where a.work_item_id=v_binding.work_item_id
      and a.allocation_role='responsible'
      and a.state='active'
    limit 1;
  end if;

  if v_current.id is not null then
    return;
  end if;

  v_claim_resolution:=atlas.resolve_institutional_communication_operation_self_v1(
    p_communication_endpoint_id,'conversation.claim'
  );

  if not coalesce((v_claim_resolution->>'allowed')::boolean,false) then
    raise exception 'Answering an unclaimed conversation requires separate response-work authority: %.',
      coalesce(v_claim_resolution->>'reason','company_work_authority_required')
      using errcode='42501';
  end if;
end
$function$;

revoke all on function atlas.assert_communication_send_response_boundary_self_v1(uuid,uuid)
  from public,anon,authenticated;

create or replace function atlas.prepare_communication_email_send_self_api_v2(
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb default '[]'::jsonb,
  p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null,
  p_body_text text default null,
  p_body_html text default null,
  p_attachment_refs jsonb default '[]'::jsonb,
  p_reply_to_communication_event_id uuid default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Communication Endpoint not found.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_endpoint.id,'message.send'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  perform atlas.assert_communication_send_response_boundary_self_v1(
    v_endpoint.id,p_communication_conversation_id
  );

  return atlas.prepare_communication_email_send_internal_v3(
    v_member_id,p_communication_endpoint_id,p_communication_conversation_id,null,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,
    p_attachment_refs,p_reply_to_communication_event_id,p_idempotency_key,
    'institutional_communication_context:message.send'
  );
end
$function$;

create or replace function atlas.prepare_communication_outbound_attachment_self_api_v1(
  p_communication_endpoint_id uuid,
  p_file_name text,
  p_mime_type text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
  v_id uuid:=gen_random_uuid();
  v_path text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Active communication endpoint not found.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_endpoint.id,'attachment.prepare'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  if btrim(coalesce(p_file_name,''))=''
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'File name and object metadata are required.' using errcode='22023';
  end if;

  v_path:='org/'||v_endpoint.organization_id::text||
    '/endpoint/'||v_endpoint.id::text||'/'||v_id::text;

  insert into atlas.communication_outbound_attachments(
    id,organization_id,organization_unit_id,communication_endpoint_id,
    staged_by_membership_id,file_name,mime_type,storage_object_path,metadata
  ) values(
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,
    v_member_id,btrim(p_file_name),
    nullif(lower(btrim(coalesce(p_mime_type,''))),''),
    v_path,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'authoritySource','institutional_communication_context:attachment.prepare',
      'personEntityId',v_authorization->>'personEntityId',
      'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
    )
  );

  return jsonb_build_object(
    'contractVersion','communication_outbound_attachment_prepare_v2',
    'attachmentId',v_id,
    'storageBucket','atlas-communication-outbound-attachments',
    'storageObjectPath',v_path,
    'fileName',btrim(p_file_name),
    'mimeType',nullif(lower(btrim(coalesce(p_mime_type,''))),''),
    'state','staging',
    'personEntityId',v_authorization->>'personEntityId',
    'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
  );
end
$function$;

create or replace function atlas.confirm_communication_outbound_attachment_self_api_v1(
  p_attachment_id uuid,
  p_sha256 text,
  p_byte_length bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','storage'
as $function$
declare
  v_attachment atlas.communication_outbound_attachments%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
  v_hash text:=lower(btrim(coalesce(p_sha256,'')));
  v_storage_exists boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_attachment
  from atlas.communication_outbound_attachments
  where id=p_attachment_id
  for update;

  if v_attachment.id is null then
    raise exception 'Outbound attachment not found.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_attachment.communication_endpoint_id,'attachment.confirm'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  if v_attachment.staged_by_membership_id is distinct from v_member_id then
    raise exception 'Attachment belongs to another communication carrier.'
      using errcode='42501';
  end if;

  if v_hash !~ '^[0-9a-f]{64}$'
     or p_byte_length is null
     or p_byte_length<0
     or p_byte_length>52428800 then
    raise exception 'Valid SHA-256 and attachment size up to 50 MiB are required.'
      using errcode='22023';
  end if;

  if v_attachment.attachment_state='revoked' then
    raise exception 'Revoked attachment cannot become ready.' using errcode='55000';
  end if;

  if v_attachment.attachment_state='ready' then
    if v_attachment.sha256 is distinct from v_hash
       or v_attachment.byte_length is distinct from p_byte_length then
      raise exception 'Attachment confirmation conflicts with existing custody.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','communication_outbound_attachment_confirm_v3',
      'attachmentId',v_attachment.id,
      'state','ready',
      'sha256',v_attachment.sha256,
      'byteLength',v_attachment.byte_length,
      'personEntityId',v_authorization->>'personEntityId',
      'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
    );
  end if;

  select exists(
    select 1
    from storage.objects o
    where o.bucket_id=v_attachment.storage_bucket
      and o.name=v_attachment.storage_object_path
  )
  into v_storage_exists;

  if not v_storage_exists then
    raise exception 'Attachment bytes are not yet present in governed storage.'
      using errcode='55000';
  end if;

  update atlas.communication_outbound_attachments
  set sha256=v_hash,
      byte_length=p_byte_length,
      attachment_state='ready',
      ready_at=now(),
      updated_at=now(),
      metadata=metadata||jsonb_build_object(
        'confirmationAuthoritySource','institutional_communication_context:attachment.confirm',
        'confirmationPersonEntityId',v_authorization->>'personEntityId',
        'confirmationResponsibilityRelationId',v_authorization->>'responsibilityRelationId'
      )
  where id=v_attachment.id
  returning * into v_attachment;

  return jsonb_build_object(
    'contractVersion','communication_outbound_attachment_confirm_v3',
    'attachmentId',v_attachment.id,
    'state','ready',
    'sha256',v_attachment.sha256,
    'byteLength',v_attachment.byte_length,
    'personEntityId',v_authorization->>'personEntityId',
    'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
  );
end
$function$;

create or replace function atlas.communication_outbound_attachment_storage_authorized_self_v1(
  p_bucket_id text,
  p_object_name text,
  p_action text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_attachment atlas.communication_outbound_attachments%rowtype;
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_operation text;
  v_resolution jsonb;
  v_member_id uuid;
begin
  if auth.uid() is null
     or p_bucket_id<>'atlas-communication-outbound-attachments' then
    return false;
  end if;

  select * into v_attachment
  from atlas.communication_outbound_attachments
  where storage_bucket=p_bucket_id
    and storage_object_path=p_object_name;

  if v_attachment.id is null then
    return false;
  end if;

  v_operation:=case
    when v_action='insert' then 'attachment.storage.insert'
    when v_action='delete' then 'attachment.storage.delete'
    else null
  end;

  if v_operation is null then
    return false;
  end if;

  v_resolution:=atlas.resolve_institutional_communication_operation_self_v1(
    v_attachment.communication_endpoint_id,v_operation
  );

  if not coalesce((v_resolution->>'allowed')::boolean,false) then
    return false;
  end if;

  v_member_id:=(v_resolution->>'legacyCarrierMembershipId')::uuid;

  if v_action='insert' then
    return v_attachment.attachment_state='staging'
      and v_attachment.staged_by_membership_id=v_member_id;
  end if;

  return v_attachment.attachment_state in ('staging','revoked');
end
$function$;

create or replace function atlas.save_communication_email_draft_compatibility_self_api_v1(
  p_draft_id uuid,
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
  p_reply_to_communication_event_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb,
  p_bcc_recipients jsonb,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_attachment_refs jsonb,
  p_signature_id uuid,
  p_send_after timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
  v_id uuid:=coalesce(p_draft_id,gen_random_uuid());
  v_state text;
  v_row atlas.communication_email_drafts%rowtype;
  v_ref text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then
    raise exception 'Active email endpoint required.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_endpoint.id,'draft.write'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Draft recipients, attachments, and metadata must be valid JSON containers.'
      using errcode='22023';
  end if;

  if p_institutional_conversation_id is not null
     and not exists(
       select 1
       from atlas.institutional_conversation_endpoints ce
       where ce.institutional_conversation_id=p_institutional_conversation_id
         and ce.communication_endpoint_id=v_endpoint.id
     ) then
    raise exception 'Draft conversation is not associated with this endpoint.'
      using errcode='42501';
  end if;

  if p_reply_to_communication_event_id is not null
     and (
       p_institutional_conversation_id is null
       or not exists(
         select 1
         from atlas.institutional_conversation_messages m
         where m.institutional_conversation_id=p_institutional_conversation_id
           and m.communication_event_id=p_reply_to_communication_event_id
       )
     ) then
    raise exception 'Reply target must belong to the draft conversation.'
      using errcode='22023';
  end if;

  if p_signature_id is not null
     and not exists(
       select 1
       from atlas.communication_email_signatures s
       where s.id=p_signature_id
         and s.communication_endpoint_id=v_endpoint.id
         and s.active
         and (s.owner_membership_id is null or s.owner_membership_id=v_member_id)
     ) then
    raise exception 'Signature is not available to this sender.' using errcode='22023';
  end if;

  for v_ref in
    select value #>> '{}'
    from jsonb_array_elements(coalesce(p_attachment_refs,'[]'::jsonb))
  loop
    if v_ref !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'Draft attachment reference is not a valid identifier.'
        using errcode='22023';
    end if;

    if not exists(
      select 1
      from atlas.communication_outbound_attachments a
      where a.id=v_ref::uuid
        and a.communication_endpoint_id=v_endpoint.id
        and a.staged_by_membership_id=v_member_id
        and a.attachment_state='ready'
    ) then
      raise exception 'Every draft attachment must be ready, belong to this endpoint, and be staged by the draft author.'
        using errcode='42501';
    end if;
  end loop;

  v_state:=case
    when p_send_after is not null and p_send_after>now() then 'scheduled'
    else 'active'
  end;

  if p_draft_id is not null then
    select * into v_row
    from atlas.communication_email_drafts
    where id=p_draft_id
    for update;

    if v_row.id is null or v_row.author_membership_id<>v_member_id then
      raise exception 'Draft not found for this author.' using errcode='P0002';
    end if;

    if v_row.draft_state in ('discarded','authorized') then
      raise exception 'Finalized draft cannot be edited.' using errcode='55000';
    end if;
  end if;

  insert into atlas.communication_email_drafts(
    id,organization_id,organization_unit_id,communication_endpoint_id,
    institutional_conversation_id,reply_to_communication_event_id,
    author_membership_id,to_recipients,cc_recipients,bcc_recipients,
    subject,body_text,body_html,attachment_refs,signature_id,
    send_after,draft_state,metadata
  ) values (
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,
    p_institutional_conversation_id,p_reply_to_communication_event_id,
    v_member_id,coalesce(p_to_recipients,'[]'::jsonb),
    coalesce(p_cc_recipients,'[]'::jsonb),coalesce(p_bcc_recipients,'[]'::jsonb),
    nullif(p_subject,''),p_body_text,p_body_html,
    coalesce(p_attachment_refs,'[]'::jsonb),p_signature_id,
    p_send_after,v_state,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'authoritySource','institutional_communication_context:draft.write',
      'personEntityId',v_authorization->>'personEntityId',
      'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
    )
  )
  on conflict(id) do update set
    institutional_conversation_id=excluded.institutional_conversation_id,
    reply_to_communication_event_id=excluded.reply_to_communication_event_id,
    to_recipients=excluded.to_recipients,
    cc_recipients=excluded.cc_recipients,
    bcc_recipients=excluded.bcc_recipients,
    subject=excluded.subject,
    body_text=excluded.body_text,
    body_html=excluded.body_html,
    attachment_refs=excluded.attachment_refs,
    signature_id=excluded.signature_id,
    send_after=excluded.send_after,
    draft_state=excluded.draft_state,
    metadata=excluded.metadata,
    version=atlas.communication_email_drafts.version+1,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','communication_email_draft_v5',
    'draftId',v_row.id,
    'state',v_row.draft_state,
    'version',v_row.version,
    'updatedAt',v_row.updated_at,
    'sendAfter',v_row.send_after,
    'personEntityId',v_authorization->>'personEntityId',
    'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
  );
end
$function$;

create or replace function atlas.communication_email_drafts_self_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Active communication endpoint required.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_endpoint.id,'draft.read'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'draftId',d.id,
    'conversationId',d.institutional_conversation_id,
    'replyToCommunicationEventId',d.reply_to_communication_event_id,
    'authorMembershipId',d.author_membership_id,
    'authorLabel',coalesce(up.display_name,u.email,d.author_membership_id::text),
    'isMine',d.author_membership_id=v_member_id,
    'to',case when d.author_membership_id=v_member_id then d.to_recipients else '[]'::jsonb end,
    'cc',case when d.author_membership_id=v_member_id then d.cc_recipients else '[]'::jsonb end,
    'bcc',case when d.author_membership_id=v_member_id then d.bcc_recipients else '[]'::jsonb end,
    'subject',d.subject,
    'bodyText',case when d.author_membership_id=v_member_id then d.body_text else null end,
    'attachmentRefs',case when d.author_membership_id=v_member_id then d.attachment_refs else '[]'::jsonb end,
    'signatureId',case when d.author_membership_id=v_member_id then d.signature_id else null end,
    'sendAfter',d.send_after,
    'state',d.draft_state,
    'version',d.version,
    'updatedAt',d.updated_at,
    'scheduleError',case when d.author_membership_id=v_member_id then nullif(d.metadata->>'lastScheduleError','') else null end,
    'lastScheduleAttemptAt',case when d.author_membership_id=v_member_id then d.metadata->>'lastScheduleAttemptAt' else null end
  ) order by d.updated_at desc),'[]'::jsonb)
  into v_items
  from atlas.communication_email_drafts d
  join atlas.organization_memberships om on om.id=d.author_membership_id
  left join auth.users u on u.id=om.user_id
  left join atlas.user_profiles up on up.user_id=om.user_id
  where d.communication_endpoint_id=v_endpoint.id
    and d.draft_state in ('active','scheduled')
    and (
      p_institutional_conversation_id is null
      or d.institutional_conversation_id=p_institutional_conversation_id
    );

  return jsonb_build_object(
    'contractVersion','communication_email_drafts_v3',
    'items',v_items,
    'personEntityId',v_authorization->>'personEntityId',
    'responsibilityRelationId',v_authorization->>'responsibilityRelationId'
  );
end
$function$;

create or replace function atlas.authorize_communication_email_draft_self_api_v1(
  p_draft_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_authorization jsonb;
  v_member_id uuid;
  v_signature atlas.communication_email_signatures%rowtype;
  v_body text;
  v_result jsonb;
  v_operation_id uuid;
  v_common_id uuid;
  v_institutional_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_row
  from atlas.communication_email_drafts
  where id=p_draft_id
  for update;

  if v_row.id is null then
    raise exception 'Draft not found.' using errcode='P0002';
  end if;

  v_authorization:=atlas.require_institutional_communication_operation_self_v1(
    v_row.communication_endpoint_id,'draft.authorize'
  );
  v_member_id:=(v_authorization->>'legacyCarrierMembershipId')::uuid;

  if v_row.author_membership_id is distinct from v_member_id then
    raise exception 'Only the draft author may send it.' using errcode='42501';
  end if;

  perform atlas.assert_communication_send_response_boundary_self_v1(
    v_row.communication_endpoint_id,v_row.communication_conversation_id
  );

  if v_row.draft_state='authorized' then
    return jsonb_build_object(
      'contractVersion','communication_email_draft_authorize_v3',
      'draftId',v_row.id,
      'outboundOperationId',v_row.authorized_outbound_operation_id,
      'communicationConversationId',v_row.communication_conversation_id,
      'deduplicated',true
    );
  end if;

  if v_row.draft_state='discarded' then
    raise exception 'Discarded draft cannot be sent.' using errcode='55000';
  end if;

  if jsonb_array_length(v_row.to_recipients)<1 then
    raise exception 'At least one To recipient is required.' using errcode='22023';
  end if;

  v_body:=coalesce(v_row.body_text,'');
  if v_row.signature_id is not null then
    select * into v_signature
    from atlas.communication_email_signatures
    where id=v_row.signature_id
      and active;

    if v_signature.id is not null and btrim(v_signature.body_text)<>'' then
      v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text;
    end if;
  end if;

  v_result:=atlas.prepare_communication_email_send_internal_v3(
    v_member_id,v_row.communication_endpoint_id,
    v_row.communication_conversation_id,v_row.institutional_conversation_id,
    v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,
    v_row.subject,v_body,v_row.body_html,v_row.attachment_refs,
    v_row.reply_to_communication_event_id,'draft:'||v_row.id::text,
    'institutional_communication_context:draft.authorize'
  );

  v_operation_id=(v_result->>'outboundOperationId')::uuid;
  v_common_id=(v_result->>'communicationConversationId')::uuid;
  v_institutional_id=(v_result->>'institutionalCompatibilityId')::uuid;

  update atlas.communication_email_drafts
  set draft_state='authorized',
      send_after=null,
      authorized_outbound_operation_id=v_operation_id,
      communication_conversation_id=v_common_id,
      institutional_conversation_id=v_institutional_id,
      metadata=metadata||jsonb_build_object(
        'commandRoot','communication_conversation',
        'authorizationAuthoritySource','institutional_communication_context:draft.authorize',
        'authorizationPersonEntityId',v_authorization->>'personEntityId',
        'authorizationResponsibilityRelationId',v_authorization->>'responsibilityRelationId'
      ),
      updated_at=now()
  where id=v_row.id;

  return v_result||jsonb_build_object(
    'contractVersion','communication_email_draft_authorize_v3',
    'draftId',v_row.id,
    'deduplicated',false
  );
end
$function$;

update atlas.authenticated_rpc_registry
set evidence=evidence||jsonb_build_object(
      'authoritySource','atlas.current_institutional_communication_context_self_api_v1',
      'operationResolver','atlas.resolve_institutional_communication_operation_self_v1',
      'legacyMembershipRole','transport/storage carrier only',
      'organizationMembershipIsAuthority',false,
      'companyWorkBoundary','Unclaimed response conversations require separately authorized conversation.claim.'
    ),
    reviewed_at=now()
where signature like 'atlas.prepare_communication_email_send_self_api_v2(%'
   or signature like 'atlas.prepare_communication_outbound_attachment_self_api_v1(%'
   or signature like 'atlas.confirm_communication_outbound_attachment_self_api_v1(%'
   or signature like 'atlas.communication_email_drafts_self_v1(%'
   or signature like 'atlas.authorize_communication_email_draft_self_api_v1(%';

comment on function atlas.require_institutional_communication_operation_self_v1(uuid,text) is
  'Internal fail-closed guard for Institutional Communication Context. Reality responsibility establishes authority; the returned legacy membership UUID is carrier identity only.';
comment on function atlas.assert_communication_send_response_boundary_self_v1(uuid,uuid) is
  'Prevents ordinary message.send authority from answering an unclaimed response conversation unless separate conversation.claim / response-work authority exists.';
comment on function atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text) is
  'Authenticated send edge authorized through Institutional Communication Context before transport compatibility.';
comment on function atlas.communication_outbound_attachment_storage_authorized_self_v1(text,text,text) is
  'Outbound attachment storage authorization comes from Institutional Communication Context; staged-by membership remains compatibility custody only.';

do $validation$
begin
  if pg_get_functiondef(
       'atlas.prepare_communication_email_send_self_api_v2(uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.communication_outbound_attachment_storage_authorized_self_v1(text,text,text)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.save_communication_email_draft_compatibility_self_api_v1(uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.authorize_communication_email_draft_self_api_v1(uuid)'::regprocedure
     ) ilike '%organization_memberships%' then
    raise exception 'Safe outbound edge retained Organization Membership authority lookup.';
  end if;
end
$validation$;

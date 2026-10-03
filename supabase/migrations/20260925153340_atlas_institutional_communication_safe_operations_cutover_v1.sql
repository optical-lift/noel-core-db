create or replace function atlas.communication_operation_authority_snapshot_valid_v1(
  p_authority jsonb,
  p_communication_endpoint_id uuid,
  p_operation_key text,
  p_membership_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_relation_id uuid;
  v_person_id uuid;
  v_entity_id uuid;
  v_required_capability text;
  v_endpoint atlas.communication_endpoints%rowtype;
begin
  if p_authority is null
     or jsonb_typeof(p_authority)<>'object'
     or p_communication_endpoint_id is null
     or p_membership_id is null then
    return false;
  end if;

  begin
    v_relation_id:=nullif(p_authority->>'responsibilityRelationId','')::uuid;
    v_person_id:=nullif(p_authority->>'personEntityId','')::uuid;
    v_entity_id:=nullif(p_authority->>'institutionEntityId','')::uuid;
  exception when invalid_text_representation then
    return false;
  end;

  if v_relation_id is null or v_person_id is null or v_entity_id is null then
    return false;
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null;

  if v_endpoint.id is null
     or atlas.reality_entity_for_legacy_organization_internal_v1(
       v_endpoint.organization_id
     ) is distinct from v_entity_id then
    return false;
  end if;

  case p_operation_key
    when 'conversation.read' then v_required_capability:='view';
    when 'draft.read' then v_required_capability:='view';
    when 'draft.write' then v_required_capability:='send';
    when 'draft.authorize' then v_required_capability:='send';
    when 'message.send' then v_required_capability:='send';
    when 'attachment.prepare' then v_required_capability:='send';
    when 'attachment.confirm' then v_required_capability:='send';
    when 'attachment.storage.insert' then v_required_capability:='send';
    when 'attachment.storage.delete' then v_required_capability:='send';
    else return false;
  end case;

  if not exists(
    select 1
    from reality.responsibility_relations rr
    where rr.id=v_relation_id
      and rr.carrier_person_entity_id=v_person_id
      and rr.responsibility_key='institutional_communication_operations'
      and rr.relation_state='active'
      and rr.began_at<=now()
      and rr.ended_at is null
      and rr.jurisdiction_kind='entity'
      and rr.jurisdiction_entity_id=v_entity_id
      and p_operation_key=any(rr.permitted_operations)
      and rr.scope @> jsonb_build_object(
        'communicationEndpointIds',
        jsonb_build_array(v_endpoint.id::text)
      )
  ) then
    return false;
  end if;

  if not exists(
    select 1
    from atlas.organization_memberships m
    join atlas.communication_endpoint_member_grants g
      on g.membership_id=m.id
     and g.communication_endpoint_id=v_endpoint.id
     and g.capability=v_required_capability
     and g.grant_state='active'
    where m.id=p_membership_id
      and m.organization_id=v_endpoint.organization_id
      and m.active
      and m.person_id=v_person_id
      and atlas.organization_membership_present_effective_at_v1(
        m.id,m.organization_id,now()
      )
  ) then
    return false;
  end if;

  return true;
end
$function$;

revoke all on function atlas.communication_operation_authority_snapshot_valid_v1(
  jsonb,uuid,text,uuid
) from public,anon,authenticated;

create or replace function atlas.resolve_institutional_communication_send_self_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_send jsonb;
  v_claim jsonb;
  v_case_state text;
begin
  v_send:=atlas.resolve_institutional_communication_operation_self_v1(
    p_communication_endpoint_id,'message.send'
  );

  if not coalesce((v_send->>'allowed')::boolean,false) then
    return v_send||jsonb_build_object('sendContext','message_send_denied');
  end if;

  if p_institutional_conversation_id is not null then
    if not exists(
      select 1
      from atlas.institutional_conversation_endpoints ce
      where ce.institutional_conversation_id=p_institutional_conversation_id
        and ce.communication_endpoint_id=p_communication_endpoint_id
    ) then
      return v_send||jsonb_build_object(
        'allowed',false,
        'reason','conversation_outside_endpoint_scope',
        'sendContext','conversation_scope_denied'
      );
    end if;

    select rc.case_state
    into v_case_state
    from atlas.institutional_conversation_response_cases rc
    where rc.institutional_conversation_id=p_institutional_conversation_id
      and rc.case_state not in ('complete','informational')
    order by rc.case_number desc
    limit 1;

    if v_case_state='unclaimed' then
      v_claim:=atlas.resolve_institutional_communication_operation_self_v1(
        p_communication_endpoint_id,'conversation.claim'
      );

      if not coalesce((v_claim->>'allowed')::boolean,false) then
        return v_send||jsonb_build_object(
          'allowed',false,
          'reason','company_work_authority_required',
          'sendContext','unclaimed_response_case',
          'responseCaseState',v_case_state,
          'claimAuthority',v_claim
        );
      end if;
    end if;
  end if;

  return v_send||jsonb_build_object(
    'allowed',true,
    'sendContext',case
      when p_institutional_conversation_id is null then 'new_outbound'
      else 'existing_conversation'
    end,
    'responseCaseState',v_case_state
  );
end
$function$;

revoke all on function atlas.resolve_institutional_communication_send_self_v1(uuid,uuid)
  from public,anon,authenticated;

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
  v_member_id uuid;
  v_authority jsonb;
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

  v_authority:=atlas.resolve_institutional_communication_operation_self_v1(
    v_endpoint.id,'draft.read'
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception 'Institutional communication draft-read responsibility required.'
      using errcode='42501';
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

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
    'authority',v_authority,
    'items',v_items
  );
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
  v_member_id uuid;
  v_authority jsonb;
  v_send_authority jsonb;
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

  v_authority:=atlas.resolve_institutional_communication_operation_self_v1(
    v_endpoint.id,'draft.write'
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception 'Institutional communication draft-write responsibility required.'
      using errcode='42501';
  end if;

  if p_send_after is not null and p_send_after>now() then
    v_send_authority:=atlas.resolve_institutional_communication_send_self_v1(
      v_endpoint.id,p_institutional_conversation_id
    );
    if not coalesce((v_send_authority->>'allowed')::boolean,false) then
      raise exception 'Scheduled send requires current send authority and may not establish unclaimed response work.'
        using errcode='42501';
    end if;
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

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
       select 1 from atlas.institutional_conversation_endpoints ce
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
         select 1 from atlas.institutional_conversation_messages m
         where m.institutional_conversation_id=p_institutional_conversation_id
           and m.communication_event_id=p_reply_to_communication_event_id
       )
     ) then
    raise exception 'Reply target must belong to the draft conversation.'
      using errcode='22023';
  end if;

  if p_signature_id is not null
     and not exists(
       select 1 from atlas.communication_email_signatures s
       where s.id=p_signature_id
         and s.communication_endpoint_id=v_endpoint.id
         and s.active
         and (
           s.owner_membership_id is null
           or s.owner_membership_id=v_member_id
         )
     ) then
    raise exception 'Signature is not available to this sender.'
      using errcode='22023';
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
      select 1 from atlas.communication_outbound_attachments a
      where a.id=v_ref::uuid
        and a.communication_endpoint_id=v_endpoint.id
        and a.staged_by_membership_id=v_member_id
        and a.attachment_state='ready'
    ) then
      raise exception 'Every draft attachment must be ready, belong to this endpoint, and be staged by the draft author.'
        using errcode='42501';
    end if;
  end loop;

  v_state:=case when p_send_after is not null and p_send_after>now()
    then 'scheduled' else 'active' end;

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
    subject,body_text,body_html,attachment_refs,signature_id,send_after,
    draft_state,metadata
  ) values (
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,
    v_endpoint.id,p_institutional_conversation_id,
    p_reply_to_communication_event_id,v_member_id,
    coalesce(p_to_recipients,'[]'::jsonb),
    coalesce(p_cc_recipients,'[]'::jsonb),
    coalesce(p_bcc_recipients,'[]'::jsonb),
    nullif(p_subject,''),p_body_text,p_body_html,
    coalesce(p_attachment_refs,'[]'::jsonb),
    p_signature_id,p_send_after,v_state,
    coalesce(p_metadata,'{}'::jsonb)
      ||jsonb_build_object('communicationAuthority',v_authority)
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
    metadata=atlas.communication_email_drafts.metadata||excluded.metadata,
    version=atlas.communication_email_drafts.version+1,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','communication_email_draft_v2',
    'draftId',v_row.id,
    'state',v_row.draft_state,
    'version',v_row.version,
    'updatedAt',v_row.updated_at,
    'sendAfter',v_row.send_after,
    'authority',v_authority
  );
end
$function$;

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
  v_institutional_id uuid;
  v_authority jsonb;
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

  if p_communication_conversation_id is not null then
    v_institutional_id:=atlas.require_institutional_compatibility_for_communication_conversation_v1(
      p_communication_conversation_id
    );
  end if;

  v_authority:=atlas.resolve_institutional_communication_send_self_v1(
    v_endpoint.id,v_institutional_id
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception '%',case
      when v_authority->>'reason'='company_work_authority_required'
        then 'Replying to an unclaimed conversation requires separate Company Work authority.'
      else 'Institutional communication send responsibility required.'
    end using errcode='42501';
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

  return atlas.prepare_communication_email_send_internal_v3(
    v_member_id,p_communication_endpoint_id,p_communication_conversation_id,
    v_institutional_id,p_to_recipients,p_cc_recipients,p_bcc_recipients,
    p_subject,p_body_text,p_body_html,p_attachment_refs,
    p_reply_to_communication_event_id,p_idempotency_key,
    'reality_communication_context_send'
  );
end
$function$;

create or replace function atlas.prepare_institutional_email_send_self_api_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
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
  v_member_id uuid;
  v_common_id uuid;
  v_authority jsonb;
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

  v_authority:=atlas.resolve_institutional_communication_send_self_v1(
    v_endpoint.id,p_institutional_conversation_id
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception '%',case
      when v_authority->>'reason'='company_work_authority_required'
        then 'Replying to an unclaimed conversation requires separate Company Work authority.'
      else 'Institutional communication send responsibility required.'
    end using errcode='42501';
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

  if p_institutional_conversation_id is not null then
    v_common_id:=atlas.require_common_communication_conversation_for_institutional_v1(
      p_institutional_conversation_id
    );
  end if;

  return atlas.prepare_communication_email_send_internal_v3(
    v_member_id,p_communication_endpoint_id,v_common_id,
    p_institutional_conversation_id,p_to_recipients,p_cc_recipients,
    p_bcc_recipients,p_subject,p_body_text,p_body_html,p_attachment_refs,
    p_reply_to_communication_event_id,p_idempotency_key,
    'reality_communication_context_institutional_send'
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
  v_signature atlas.communication_email_signatures%rowtype;
  v_authority jsonb;
  v_member_id uuid;
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

  v_authority:=atlas.resolve_institutional_communication_send_self_v1(
    v_row.communication_endpoint_id,v_row.institutional_conversation_id
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception '%',case
      when v_authority->>'reason'='company_work_authority_required'
        then 'Authorizing this reply requires separate Company Work authority.'
      else 'Institutional communication send responsibility required.'
    end using errcode='42501';
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

  if v_row.author_membership_id is distinct from v_member_id then
    raise exception 'Only the draft author may authorize it.' using errcode='42501';
  end if;

  if v_row.draft_state='authorized' then
    return jsonb_build_object(
      'contractVersion','communication_email_draft_authorize_v3',
      'draftId',v_row.id,
      'outboundOperationId',v_row.authorized_outbound_operation_id,
      'communicationConversationId',v_row.communication_conversation_id,
      'authority',v_authority,
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
    'reality_communication_context_draft_authorize'
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
        'communicationAuthority',v_authority,
        'commandRoot','communication_conversation'
      ),
      updated_at=now()
  where id=v_row.id;

  return v_result||jsonb_build_object(
    'contractVersion','communication_email_draft_authorize_v3',
    'draftId',v_row.id,
    'authority',v_authority,
    'deduplicated',false
  );
end
$function$;

create or replace function atlas.release_due_communication_email_drafts_service_v1(
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_signature atlas.communication_email_signatures%rowtype;
  v_body text;
  v_result jsonb;
  v_released integer:=0;
  v_failed integer:=0;
  v_case_state text;
begin
  if p_limit<1 or p_limit>500 then
    raise exception 'Limit must be between 1 and 500.' using errcode='22023';
  end if;

  for v_row in
    select d.*
    from atlas.communication_email_drafts d
    where d.draft_state='scheduled'
      and d.send_after<=now()
      and exists(
        select 1
        from atlas.communication_endpoint_source_bindings binding
        join atlas.connected_sources source
          on source.id=binding.connected_source_id
        where binding.communication_endpoint_id=d.communication_endpoint_id
          and binding.binding_state='active'
          and binding.binding_role in ('send','send_receive')
          and source.authorization_state='connected'
          and source.capabilities @> '{"communicationSend":true}'::jsonb
      )
    order by d.send_after,d.id
    for update skip locked
    limit p_limit
  loop
    begin
      if not atlas.communication_operation_authority_snapshot_valid_v1(
        v_row.metadata->'communicationAuthority',
        v_row.communication_endpoint_id,
        'message.send',
        v_row.author_membership_id
      ) then
        raise exception 'Scheduled draft communication authority is no longer valid.'
          using errcode='42501';
      end if;

      if v_row.institutional_conversation_id is not null then
        select rc.case_state
        into v_case_state
        from atlas.institutional_conversation_response_cases rc
        where rc.institutional_conversation_id=v_row.institutional_conversation_id
          and rc.case_state not in ('complete','informational')
        order by rc.case_number desc
        limit 1;

        if v_case_state='unclaimed' then
          raise exception 'Scheduled draft cannot establish unclaimed response work.'
            using errcode='42501';
        end if;
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
        v_row.author_membership_id,v_row.communication_endpoint_id,
        v_row.communication_conversation_id,v_row.institutional_conversation_id,
        v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,
        v_row.subject,v_body,v_row.body_html,v_row.attachment_refs,
        v_row.reply_to_communication_event_id,
        'draft:'||v_row.id::text,'scheduled_draft_release'
      );

      update atlas.communication_email_drafts
      set draft_state='authorized',
          send_after=null,
          authorized_outbound_operation_id=(v_result->>'outboundOperationId')::uuid,
          communication_conversation_id=(v_result->>'communicationConversationId')::uuid,
          institutional_conversation_id=(v_result->>'institutionalCompatibilityId')::uuid,
          metadata=((metadata-'lastScheduleError')-'lastScheduleAttemptAt')
            ||jsonb_build_object('commandRoot','communication_conversation'),
          updated_at=now()
      where id=v_row.id;

      v_released:=v_released+1;
    exception when others then
      update atlas.communication_email_drafts
      set metadata=metadata||jsonb_build_object(
        'lastScheduleError',sqlerrm,
        'lastScheduleAttemptAt',now()
      ),
      updated_at=now()
      where id=v_row.id;
      v_failed:=v_failed+1;
    end;
  end loop;

  return jsonb_build_object(
    'contractVersion','communication_email_draft_release_v4',
    'released',v_released,
    'failed',v_failed,
    'commandRoot','communication_conversation',
    'authorityMode','stored_reality_responsibility_snapshot'
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
  v_authority jsonb;
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

  v_authority:=atlas.resolve_institutional_communication_operation_self_v1(
    v_endpoint.id,'attachment.prepare'
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception 'Institutional communication attachment responsibility required.'
      using errcode='42501';
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

  if btrim(coalesce(p_file_name,''))=''
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'File name and object metadata are required.' using errcode='22023';
  end if;

  v_path:='org/'||v_endpoint.organization_id::text
    ||'/endpoint/'||v_endpoint.id::text
    ||'/'||v_id::text;

  insert into atlas.communication_outbound_attachments(
    id,organization_id,organization_unit_id,communication_endpoint_id,
    staged_by_membership_id,file_name,mime_type,storage_object_path,metadata
  ) values(
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,
    v_endpoint.id,v_member_id,btrim(p_file_name),
    nullif(lower(btrim(coalesce(p_mime_type,''))),''),
    v_path,
    coalesce(p_metadata,'{}'::jsonb)
      ||jsonb_build_object('communicationAuthority',v_authority)
  );

  return jsonb_build_object(
    'contractVersion','communication_outbound_attachment_prepare_v2',
    'attachmentId',v_id,
    'storageBucket','atlas-communication-outbound-attachments',
    'storageObjectPath',v_path,
    'fileName',btrim(p_file_name),
    'mimeType',nullif(lower(btrim(coalesce(p_mime_type,''))),''),
    'state','staging',
    'authority',v_authority
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
  v_authority jsonb;
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

  v_authority:=atlas.resolve_institutional_communication_operation_self_v1(
    v_attachment.communication_endpoint_id,'attachment.confirm'
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    raise exception 'Institutional communication attachment responsibility required.'
      using errcode='42501';
  end if;

  if v_attachment.staged_by_membership_id is distinct from
     (v_authority->>'legacyCarrierMembershipId')::uuid then
    raise exception 'Only the staging communication actor may confirm this attachment.'
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
      'attachmentId',v_attachment.id,'state','ready',
      'sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length,
      'authority',v_authority
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
      metadata=metadata||jsonb_build_object(
        'communicationAuthority',v_authority
      ),
      updated_at=now()
  where id=v_attachment.id
  returning * into v_attachment;

  return jsonb_build_object(
    'contractVersion','communication_outbound_attachment_confirm_v3',
    'attachmentId',v_attachment.id,'state','ready',
    'sha256',v_attachment.sha256,'byteLength',v_attachment.byte_length,
    'authority',v_authority
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
  v_authority jsonb;
  v_member_id uuid;
  v_action text:=lower(btrim(coalesce(p_action,'')));
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

  v_authority:=atlas.resolve_institutional_communication_operation_self_v1(
    v_attachment.communication_endpoint_id,
    case
      when v_action='insert' then 'attachment.storage.insert'
      when v_action='delete' then 'attachment.storage.delete'
      else 'unsupported'
    end
  );

  if not coalesce((v_authority->>'allowed')::boolean,false) then
    return false;
  end if;

  v_member_id:=(v_authority->>'legacyCarrierMembershipId')::uuid;

  if v_action='insert' then
    return v_attachment.attachment_state='staging'
      and v_attachment.staged_by_membership_id=v_member_id;
  elsif v_action='delete' then
    return v_attachment.attachment_state in ('staging','revoked')
      and (
        v_attachment.staged_by_membership_id=v_member_id
        or atlas.communication_endpoint_legacy_carrier_capability_self_v1(
          v_attachment.communication_endpoint_id,'admin'
        )
      );
  end if;

  return false;
end
$function$;

comment on function atlas.communication_operation_authority_snapshot_valid_v1(
  jsonb,uuid,text,uuid
) is
  'Validate a stored institutional communication responsibility snapshot for service execution. Revocation, scope loss, endpoint drift, carrier loss, or operation mismatch fails closed.';
comment on function atlas.resolve_institutional_communication_send_self_v1(uuid,uuid) is
  'Resolve message-send authority and refuse an unclaimed response case unless separately governed Company Work claim authority exists.';
comment on function atlas.communication_email_drafts_self_v1(uuid,uuid) is
  'Read institutional email drafts through Institutional Communication Context; Organization Membership remains author/routing compatibility only.';
comment on function atlas.save_communication_email_draft_compatibility_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb
) is
  'Draft writer governed by Institutional Communication Context. Scheduled drafts store the Reality authority snapshot and cannot schedule an unclaimed reply without Company Work authority.';
comment on function atlas.release_due_communication_email_drafts_service_v1(integer) is
  'Scheduled release validates the stored Reality communication responsibility remains active and refuses to establish unclaimed response work.';
comment on function atlas.prepare_communication_outbound_attachment_self_api_v1(uuid,text,text,jsonb) is
  'Stage outbound attachment custody through Institutional Communication Context.';
comment on function atlas.confirm_communication_outbound_attachment_self_api_v1(uuid,text,bigint) is
  'Confirm outbound attachment custody through Institutional Communication Context after governed storage bytes exist.';

update atlas.authenticated_rpc_registry
set evidence=evidence||jsonb_build_object(
      'authoritySource','institutional_communication_context_v1',
      'realityResponsibilityKey','institutional_communication_operations',
      'organizationMembershipIsAuthority',false,
      'legacyEndpointGrantRole','compatibility carrier constraint only',
      'companyWorkBoundary','Unclaimed response work remains separately governed.'
    ),
    reviewed_at=now()
where signature like 'atlas.communication_email_drafts_self_v1(%'
   or signature like 'atlas.save_communication_email_draft_self_api_v3(%'
   or signature like 'atlas.authorize_communication_email_draft_self_api_v1(%'
   or signature like 'atlas.prepare_communication_email_send_self_api_v2(%'
   or signature like 'atlas.prepare_institutional_email_send_self_api_v1(%'
   or signature like 'atlas.prepare_communication_outbound_attachment_self_api_v1(%'
   or signature like 'atlas.confirm_communication_outbound_attachment_self_api_v1(%';

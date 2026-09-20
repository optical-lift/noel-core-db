begin;

-- Authority Dimensions slice 1:
-- Communication Endpoint grants become exact for non-owner members.
-- Organization owner wildcard remains transitional compatibility in this slice.

create or replace function atlas.communication_endpoint_membership_has_capability_v1(
  p_endpoint_id uuid,
  p_membership_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select exists(
    select 1
    from atlas.communication_endpoints ep
    join atlas.organization_memberships om
      on om.id=p_membership_id
     and om.organization_id=ep.organization_id
     and om.active
    where ep.id=p_endpoint_id
      and ep.endpoint_state='active'
      and (
        om.role='owner'
        or exists(
          select 1
          from atlas.communication_endpoint_member_grants g
          where g.communication_endpoint_id=ep.id
            and g.membership_id=om.id
            and g.capability=lower(btrim(coalesce(p_capability,'')))
            and g.grant_state='active'
        )
      )
  );
$function$;

comment on function atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text) is
'Exact Communication Endpoint capability check for non-owner members. Organization owner remains transitional compatibility. Endpoint admin is configuration authority and is not a wildcard for view/send/claim/handoff/close.';

create or replace function atlas.communication_endpoint_authorized_self_v1(
  p_endpoint_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select exists(
    select 1
    from atlas.communication_endpoints ep
    join atlas.organization_memberships om
      on om.organization_id=ep.organization_id
     and om.user_id=auth.uid()
     and om.active
    where ep.id=p_endpoint_id
      and ep.endpoint_state='active'
      and (
        om.role='owner'
        or exists(
          select 1
          from atlas.communication_endpoint_member_grants g
          where g.communication_endpoint_id=ep.id
            and g.membership_id=om.id
            and g.capability=lower(btrim(coalesce(p_capability,'')))
            and g.grant_state='active'
        )
      )
  );
$function$;

comment on function atlas.communication_endpoint_authorized_self_v1(uuid,text) is
'Authenticated exact Communication Endpoint capability check. Organization owner remains transitional compatibility; admin does not imply sibling capabilities.';

create or replace function atlas.prepare_institutional_email_send_internal_v2(
  p_actor_membership_id uuid,
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid,
  p_to_recipients jsonb,
  p_cc_recipients jsonb default '[]'::jsonb,
  p_bcc_recipients jsonb default '[]'::jsonb,
  p_subject text default null::text,
  p_body_text text default null::text,
  p_body_html text default null::text,
  p_attachment_refs jsonb default '[]'::jsonb,
  p_reply_to_communication_event_id uuid default null::uuid,
  p_idempotency_key text default null::text,
  p_authorization_source text default 'internal_send_command'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','extensions'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_conv atlas.institutional_conversations%rowtype;
  v_conv_id uuid:=p_institutional_conversation_id;
  v_source_id uuid;
  v_source_count integer;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_is_collaborator boolean:=false;
  v_operation_id uuid:=gen_random_uuid();
  v_key text:=coalesce(nullif(btrim(p_idempotency_key),''),v_operation_id::text);
  v_hash text;
  v_stable text;
  v_attachment uuid;
  v_attachment_count integer:=0;
begin
  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id and endpoint_state='active';

  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then
    raise exception 'Active email communication endpoint required.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where id=p_actor_membership_id
    and organization_id=v_endpoint.organization_id
    and active;

  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(
       v_endpoint.id,v_member.id,'send'
     ) then
    raise exception 'Communication endpoint send authority required.' using errcode='42501';
  end if;

  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array'
     or jsonb_array_length(coalesce(p_to_recipients,'[]'::jsonb))<1
     or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array'
     or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array' then
    raise exception 'Recipients/attachments must be JSON arrays and at least one To recipient is required.' using errcode='22023';
  end if;

  select count(*),(array_agg(b.connected_source_id order by b.connected_source_id))[1]
    into v_source_count,v_source_id
  from atlas.communication_endpoint_source_bindings b
  join atlas.connected_sources s on s.id=b.connected_source_id
  where b.communication_endpoint_id=v_endpoint.id
    and b.binding_state='active'
    and b.binding_role in ('send','send_receive')
    and s.authorization_state='connected'
    and s.capabilities @> '{"communicationSend":true}'::jsonb;

  if v_source_count<>1 then
    raise exception 'Exactly one connected send transport is required for this endpoint; found %.',v_source_count
      using errcode='55000';
  end if;

  for v_attachment in
    select (value #>> '{}')::uuid
    from jsonb_array_elements(coalesce(p_attachment_refs,'[]'::jsonb))
  loop
    if not exists(
      select 1
      from atlas.communication_outbound_attachments a
      where a.id=v_attachment
        and a.communication_endpoint_id=v_endpoint.id
        and a.attachment_state='ready'
    ) then
      raise exception 'Every outbound attachment must be ready and belong to the sending endpoint.'
        using errcode='22023';
    end if;
    v_attachment_count:=v_attachment_count+1;
  end loop;

  if v_conv_id is null then
    v_stable:='outbound-intent:'||v_operation_id::text;

    insert into atlas.institutional_conversations(
      organization_id,organization_unit_id,stable_key,subject,opened_at,last_activity_at,metadata
    ) values(
      v_endpoint.organization_id,v_endpoint.organization_unit_id,v_stable,
      nullif(btrim(coalesce(p_subject,'')),''),now(),now(),
      jsonb_build_object('createdFromOutboundIntent',true,'initiatedByMembershipId',v_member.id)
    )
    returning id into v_conv_id;

    insert into atlas.institutional_conversation_endpoints(
      institutional_conversation_id,communication_endpoint_id,endpoint_role
    ) values(v_conv_id,v_endpoint.id,'primary');
  else
    select * into v_conv
    from atlas.institutional_conversations
    where id=v_conv_id
      and organization_id=v_endpoint.organization_id
      and organization_unit_id is not distinct from v_endpoint.organization_unit_id
      and conversation_state='open';

    if v_conv.id is null then
      raise exception 'Institutional conversation is outside endpoint scope or not open.'
        using errcode='42501';
    end if;

    if not exists(
      select 1
      from atlas.institutional_conversation_endpoints ce
      where ce.institutional_conversation_id=v_conv_id
        and ce.communication_endpoint_id=v_endpoint.id
    ) then
      raise exception 'Conversation is not associated with the sending endpoint.'
        using errcode='42501';
    end if;
  end if;

  select * into v_case
  from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv_id
    and case_state not in ('complete','informational')
  order by case_number desc
  limit 1;

  if v_case.id is not null then
    select * into v_binding
    from atlas.institutional_conversation_response_work_bindings
    where response_case_id=v_case.id;

    if v_binding.id is not null then
      select * into v_current
      from atlas.work_allocations
      where work_item_id=v_binding.work_item_id
        and allocation_role='responsible'
        and state='active'
      limit 1;

      select exists(
        select 1
        from atlas.work_allocations a
        where a.work_item_id=v_binding.work_item_id
          and a.assignee_membership_id=v_member.id
          and a.allocation_role in ('participant','approver')
          and a.state='active'
      )
      into v_is_collaborator;
    end if;

    if v_current.id is not null
       and v_current.assignee_membership_id is distinct from v_member.id
       and not v_is_collaborator then
      raise exception 'Another member currently owns this conversation response. Join the response work or receive a handoff before sending.'
        using errcode='42501';
    end if;

    if v_current.id is null
       and v_case.case_state='unclaimed'
       and not atlas.communication_endpoint_membership_has_capability_v1(
         v_endpoint.id,v_member.id,'claim'
       ) then
      raise exception 'Claim authority is required to answer an unclaimed conversation.'
        using errcode='42501';
    end if;
  end if;

  v_hash:=encode(extensions.digest(
    convert_to(
      jsonb_build_object(
        'endpointId',v_endpoint.id,
        'conversationId',v_conv_id,
        'to',coalesce(p_to_recipients,'[]'::jsonb),
        'cc',coalesce(p_cc_recipients,'[]'::jsonb),
        'bcc',coalesce(p_bcc_recipients,'[]'::jsonb),
        'subject',p_subject,
        'bodyText',p_body_text,
        'bodyHtml',p_body_html,
        'attachments',coalesce(p_attachment_refs,'[]'::jsonb),
        'replyToCommunicationEventId',p_reply_to_communication_event_id
      )::text,
      'UTF8'
    ),
    'sha256'
  ),'hex');

  insert into atlas.communication_outbound_operations(
    id,organization_id,organization_unit_id,communication_endpoint_id,
    institutional_conversation_id,connected_source_id,initiated_by_membership_id,
    to_recipients,cc_recipients,bcc_recipients,subject,body_text,body_html,
    attachment_refs,reply_to_communication_event_id,idempotency_key,
    content_sha256,operation_state,metadata
  ) values(
    v_operation_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,
    v_endpoint.id,v_conv_id,v_source_id,v_member.id,
    coalesce(p_to_recipients,'[]'::jsonb),
    coalesce(p_cc_recipients,'[]'::jsonb),
    coalesce(p_bcc_recipients,'[]'::jsonb),
    p_subject,p_body_text,p_body_html,
    coalesce(p_attachment_refs,'[]'::jsonb),
    p_reply_to_communication_event_id,v_key,v_hash,'authorized',
    jsonb_build_object(
      'authorizationSource',p_authorization_source,
      'actorUserId',v_member.user_id,
      'responseCollaborator',v_is_collaborator,
      'attachmentCount',v_attachment_count
    )
  )
  on conflict(organization_id,idempotency_key) do nothing;

  select id into strict v_operation_id
  from atlas.communication_outbound_operations
  where organization_id=v_endpoint.organization_id
    and idempotency_key=v_key;

  return jsonb_build_object(
    'contractVersion','institutional_email_send_intent_v2',
    'outboundOperationId',v_operation_id,
    'institutionalConversationId',v_conv_id,
    'communicationEndpointId',v_endpoint.id,
    'connectedSourceId',v_source_id,
    'operationState','authorized',
    'initiatedByMembershipId',v_member.id,
    'contentSha256',v_hash
  );
end;
$function$;

comment on function atlas.prepare_institutional_email_send_internal_v2(
  uuid,uuid,uuid,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,text,text
) is
'Authorizes institutional email only for exact send authority plus current response responsibility/collaboration. Endpoint administration does not override another member''s response responsibility.';

commit;

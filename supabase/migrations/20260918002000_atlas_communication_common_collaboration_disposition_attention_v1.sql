begin;

-- Package 7 / Stage 5:
-- expose collaborator, attention, and endpoint-scoped disposition truth through
-- common Communication Conversation custody. Institutional Conversation remains
-- compatibility storage only where legacy response/mailbox tables still require it.

create or replace function atlas.organization_correspondence_conversation_self_api_v3(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_conversation atlas.communication_conversations%rowtype;
  v_viewer atlas.organization_memberships%rowtype;
  v_events jsonb;
  v_endpoints jsonb;
  v_collaborators jsonb;
begin
  v_base:=atlas.organization_correspondence_conversation_self_api_v2(
    p_communication_conversation_id
  );

  if coalesce(v_base->>'identityRoot','') <> 'communication_conversation'
     or nullif(v_base->>'communicationConversationId','')::uuid is distinct from p_communication_conversation_id then
    raise exception 'Common Correspondence detail lost Communication Conversation custody.' using errcode='23514';
  end if;

  select * into v_conversation
  from atlas.communication_conversations
  where id=p_communication_conversation_id;

  if v_conversation.id is null then
    raise exception 'Communication Conversation not found.' using errcode='P0002';
  end if;
  if v_conversation.organization_id is null or v_conversation.principal_id is not null then
    raise exception 'Organization Correspondence detail requires an Organization Communication Conversation.' using errcode='22023';
  end if;

  select * into v_viewer
  from atlas.organization_memberships
  where organization_id=v_conversation.organization_id
    and user_id=auth.uid()
    and active
  order by created_at
  limit 1;

  if v_viewer.id is null then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    event || jsonb_build_object(
      'attention',jsonb_build_object(
        'openedByMe',coalesce((
          select case when attention.attention_kind='marked_unread' then false else true end
          from atlas.communication_attention_events attention
          where attention.communication_event_id=nullif(event->>'communicationEventId','')::uuid
            and attention.membership_id=v_viewer.id
            and attention.attention_kind in ('opened','marked_read','marked_unread')
          order by attention.occurred_at desc,attention.id desc
          limit 1
        ),false),
        'latestAttentionKind',(
          select attention.attention_kind
          from atlas.communication_attention_events attention
          where attention.communication_event_id=nullif(event->>'communicationEventId','')::uuid
            and attention.membership_id=v_viewer.id
            and attention.attention_kind in ('previewed','opened','marked_read','marked_unread')
          order by attention.occurred_at desc,attention.id desc
          limit 1
        ),
        'firstOpenedAt',(
          select min(attention.occurred_at)
          from atlas.communication_attention_events attention
          where attention.communication_event_id=nullif(event->>'communicationEventId','')::uuid
            and attention.attention_kind='opened'
        ),
        'firstOpenedByMembershipId',(
          select attention.membership_id
          from atlas.communication_attention_events attention
          where attention.communication_event_id=nullif(event->>'communicationEventId','')::uuid
            and attention.attention_kind='opened'
          order by attention.occurred_at,attention.id
          limit 1
        )
      )
    )
    order by coalesce((event->>'occurredAt')::timestamptz,(event->>'capturedAt')::timestamptz),event->>'communicationEventId'
  ),'[]'::jsonb)
  into v_events
  from jsonb_array_elements(coalesce(v_base->'events','[]'::jsonb)) event;

  select coalesce(jsonb_agg(
    endpoint || jsonb_build_object(
      'disposition',coalesce((
        select disposition.disposition
        from atlas.institutional_conversation_disposition_events disposition
        join atlas.institutional_conversation_roots root
          on root.institutional_conversation_id=disposition.institutional_conversation_id
        where root.communication_conversation_id=v_conversation.id
          and disposition.communication_endpoint_id=nullif(endpoint->>'communicationEndpointId','')::uuid
        order by disposition.created_at desc,disposition.id desc
        limit 1
      ),'inbox'),
      'canClose',atlas.communication_endpoint_membership_has_capability_v1(
        nullif(endpoint->>'communicationEndpointId','')::uuid,v_viewer.id,'close'
      ),
      'canHandoff',atlas.communication_endpoint_membership_has_capability_v1(
        nullif(endpoint->>'communicationEndpointId','')::uuid,v_viewer.id,'handoff'
      ),
      'canClaim',atlas.communication_endpoint_membership_has_capability_v1(
        nullif(endpoint->>'communicationEndpointId','')::uuid,v_viewer.id,'claim'
      )
    )
    order by endpoint->>'displayName',endpoint->>'address',endpoint->>'communicationEndpointId'
  ),'[]'::jsonb)
  into v_endpoints
  from jsonb_array_elements(coalesce(v_base->'endpoints','[]'::jsonb)) endpoint;

  select coalesce(jsonb_agg(jsonb_build_object(
    'responseCaseId',response_case.id,
    'institutionalCompatibilityId',response_case.institutional_conversation_id,
    'allocationId',allocation.id,
    'membershipId',allocation.assignee_membership_id,
    'allocationRole',allocation.allocation_role,
    'displayName',coalesce(profile.display_name,membership.role),
    'role',membership.role,
    'allocatedAt',allocation.allocated_at
  ) order by
    case allocation.allocation_role when 'responsible' then 0 when 'participant' then 1 else 2 end,
    allocation.allocated_at,
    allocation.id
  ),'[]'::jsonb)
  into v_collaborators
  from atlas.institutional_conversation_roots root
  join atlas.institutional_conversation_response_cases response_case
    on response_case.institutional_conversation_id=root.institutional_conversation_id
   and response_case.case_state not in ('complete','informational')
  join atlas.institutional_conversation_response_work_bindings binding
    on binding.response_case_id=response_case.id
  join atlas.work_allocations allocation
    on allocation.work_item_id=binding.work_item_id
   and allocation.state='active'
   and allocation.allocation_role in ('responsible','participant','approver')
  join atlas.organization_memberships membership
    on membership.id=allocation.assignee_membership_id
  left join atlas.user_profiles profile
    on profile.user_id=membership.user_id
  where root.communication_conversation_id=v_conversation.id;

  return (v_base-'events'-'endpoints') || jsonb_build_object(
    'contractVersion','organization_correspondence_conversation_v3',
    'viewerMembershipId',v_viewer.id,
    'events',v_events,
    'endpoints',v_endpoints,
    'responseCollaborators',v_collaborators
  );
end;
$function$;

create or replace function atlas.set_communication_conversation_endpoint_disposition_self_api_v1(
  p_communication_conversation_id uuid,
  p_communication_endpoint_id uuid,
  p_disposition text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_conversation atlas.communication_conversations%rowtype;
  v_institutional_id uuid;
  v_member atlas.organization_memberships%rowtype;
  v_sender text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_disposition not in ('inbox','archive','trash','spam') then
    raise exception 'Invalid mailbox disposition.' using errcode='22023';
  end if;

  select * into v_conversation
  from atlas.communication_conversations
  where id=p_communication_conversation_id;

  if v_conversation.id is null then
    raise exception 'Communication Conversation not found.' using errcode='P0002';
  end if;
  if v_conversation.organization_id is null or v_conversation.principal_id is not null then
    raise exception 'Mailbox disposition requires an Organization Communication Conversation.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.communication_conversation_endpoints endpoint_membership
    where endpoint_membership.communication_conversation_id=v_conversation.id
      and endpoint_membership.communication_endpoint_id=p_communication_endpoint_id
  ) then
    raise exception 'Communication Endpoint is not part of this common Conversation.' using errcode='23514';
  end if;

  select root.institutional_conversation_id
  into v_institutional_id
  from atlas.institutional_conversation_roots root
  join atlas.institutional_conversation_endpoints endpoint_membership
    on endpoint_membership.institutional_conversation_id=root.institutional_conversation_id
   and endpoint_membership.communication_endpoint_id=p_communication_endpoint_id
  where root.communication_conversation_id=v_conversation.id
  order by case endpoint_membership.endpoint_role when 'primary' then 0 else 1 end,
           endpoint_membership.created_at,
           root.institutional_conversation_id
  limit 1;

  if v_institutional_id is null then
    raise exception 'Endpoint-scoped mailbox disposition has no Institutional compatibility carrier.' using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.institutional_conversations institutional
    where institutional.id=v_institutional_id
      and institutional.organization_id=v_conversation.organization_id
      and institutional.organization_unit_id is not distinct from v_conversation.organization_unit_id
  ) then
    raise exception 'Institutional compatibility carrier disagrees with common Conversation custody.' using errcode='23514';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where organization_id=v_conversation.organization_id
    and user_id=auth.uid()
    and active
  order by created_at
  limit 1;

  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(
       p_communication_endpoint_id,v_member.id,'close'
     ) then
    raise exception 'Communication close authority required to change mailbox disposition.' using errcode='42501';
  end if;

  insert into atlas.institutional_conversation_disposition_events(
    organization_id,
    institutional_conversation_id,
    communication_endpoint_id,
    disposition,
    actor_membership_id,
    reason,
    metadata
  ) values (
    v_conversation.organization_id,
    v_institutional_id,
    p_communication_endpoint_id,
    p_disposition,
    v_member.id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'communicationConversationId',v_conversation.id,
      'institutionalCompatibilityId',v_institutional_id,
      'communicationCommandRoot','communication_conversation'
    )
  );

  select participant.address_normalized
  into v_sender
  from atlas.communication_conversation_events conversation_event
  join atlas.communication_events event
    on event.id=conversation_event.communication_event_id
  join atlas.communication_event_participants participant
    on participant.communication_event_id=event.id
   and participant.participant_role in ('sender','from')
   and not participant.is_self
  where conversation_event.communication_conversation_id=v_conversation.id
    and conversation_event.communication_endpoint_id=p_communication_endpoint_id
    and event.direction='incoming'
  order by coalesce(conversation_event.occurred_at,event.occurred_at,event.captured_at) desc,
           conversation_event.created_at desc,
           conversation_event.id desc
  limit 1;

  if p_disposition='spam' and v_sender is not null then
    insert into atlas.communication_endpoint_sender_rules(
      organization_id,
      communication_endpoint_id,
      address_normalized,
      rule_kind,
      created_by_membership_id,
      metadata
    ) values (
      v_conversation.organization_id,
      p_communication_endpoint_id,
      v_sender,
      'spam',
      v_member.id,
      jsonb_build_object(
        'sourceConversationId',v_institutional_id,
        'communicationConversationId',v_conversation.id,
        'institutionalCompatibilityId',v_institutional_id
      )
    )
    on conflict(communication_endpoint_id,address_normalized,rule_kind)
      where rule_state='active'
    do update set
      updated_at=now(),
      metadata=atlas.communication_endpoint_sender_rules.metadata||excluded.metadata;
  elsif p_disposition='inbox' and v_sender is not null then
    update atlas.communication_endpoint_sender_rules
    set rule_state='revoked',updated_at=now()
    where communication_endpoint_id=p_communication_endpoint_id
      and address_normalized=v_sender
      and rule_kind='spam'
      and rule_state='active';
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','communication_conversation_endpoint_disposition_v1',
    'identityRoot','communication_conversation',
    'communicationConversationId',v_conversation.id,
    'communicationEndpointId',p_communication_endpoint_id,
    'institutionalCompatibilityId',v_institutional_id,
    'disposition',p_disposition
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_conversation_self_api_v3(uuid) from public,anon;
revoke all on function atlas.set_communication_conversation_endpoint_disposition_self_api_v1(uuid,uuid,text,text) from public,anon;

grant execute on function atlas.organization_correspondence_conversation_self_api_v3(uuid) to authenticated,service_role;
grant execute on function atlas.set_communication_conversation_endpoint_disposition_self_api_v1(uuid,uuid,text,text) to authenticated,service_role;

comment on function atlas.organization_correspondence_conversation_self_api_v3(uuid) is
'Common Conversation detail projection with Event-rooted viewer attention, endpoint-scoped mailbox disposition/capabilities, and response-work collaborator consequences. Institutional Conversation remains compatibility storage only.';

comment on function atlas.set_communication_conversation_endpoint_disposition_self_api_v1(uuid,uuid,text,text) is
'Changes mailbox disposition using common Communication Conversation plus exact Communication Endpoint custody. Institutional Conversation remains compatibility storage for existing mailbox event tables.';

commit;

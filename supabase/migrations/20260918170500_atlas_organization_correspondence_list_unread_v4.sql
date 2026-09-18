begin;

create table atlas.communication_conversation_endpoint_disposition_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  communication_conversation_id uuid not null references atlas.communication_conversations(id),
  communication_endpoint_id uuid not null references atlas.communication_endpoints(id),
  disposition text not null check (disposition in ('inbox','archive','trash','spam')),
  actor_membership_id uuid references atlas.organization_memberships(id),
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index communication_conversation_endpoint_disposition_events_current_idx
  on atlas.communication_conversation_endpoint_disposition_events(
    communication_conversation_id,
    communication_endpoint_id,
    created_at desc,
    id desc
  );

alter table atlas.communication_conversation_endpoint_disposition_events enable row level security;
revoke all on atlas.communication_conversation_endpoint_disposition_events from public,anon,authenticated;

create or replace function atlas.prevent_communication_mailbox_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Communication mailbox disposition history is append-only.' using errcode='55000';
end;
$function$;

create trigger communication_conversation_endpoint_disposition_append_only_v1
before update or delete on atlas.communication_conversation_endpoint_disposition_events
for each row execute function atlas.prevent_communication_mailbox_history_mutation_v1();

insert into atlas.communication_conversation_endpoint_disposition_events(
  organization_id,
  communication_conversation_id,
  communication_endpoint_id,
  disposition,
  actor_membership_id,
  reason,
  metadata,
  created_at
)
select
  disposition.organization_id,
  root.communication_conversation_id,
  disposition.communication_endpoint_id,
  disposition.disposition,
  disposition.actor_membership_id,
  disposition.reason,
  coalesce(disposition.metadata,'{}'::jsonb)||jsonb_build_object(
    'migratedFrom','institutional_conversation_disposition_events',
    'sourceInstitutionalDispositionEventId',disposition.id,
    'institutionalCompatibilityId',disposition.institutional_conversation_id
  ),
  disposition.created_at
from atlas.institutional_conversation_disposition_events disposition
join atlas.institutional_conversation_roots root
  on root.institutional_conversation_id=disposition.institutional_conversation_id
join atlas.communication_conversation_endpoints conversation_endpoint
  on conversation_endpoint.communication_conversation_id=root.communication_conversation_id
 and conversation_endpoint.communication_endpoint_id=disposition.communication_endpoint_id;


create or replace function atlas.organization_correspondence_list_self_api_v4(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
  v_viewer_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_base:=atlas.organization_correspondence_list_self_api_v3(
    p_organization_id,
    p_communication_endpoint_id,
    p_limit
  );

  if p_organization_id is not null then
    select membership.id
    into v_viewer_membership_id
    from atlas.organization_memberships membership
    where membership.organization_id=p_organization_id
      and membership.user_id=auth.uid()
      and membership.active
    order by membership.created_at,membership.id
    limit 1;
  elsif p_communication_endpoint_id is not null then
    select membership.id
    into v_viewer_membership_id
    from atlas.communication_endpoints endpoint
    join atlas.organization_memberships membership
      on membership.organization_id=atlas.effective_communication_endpoint_organization_v1(endpoint.id)
     and membership.user_id=auth.uid()
     and membership.active
    where endpoint.id=p_communication_endpoint_id
    order by membership.created_at,membership.id
    limit 1;
  end if;

  select coalesce(
    jsonb_agg(
      case
        when nullif(item#>>'{latestEvent,communicationEventId}','') is null then item
        else jsonb_set(
          jsonb_set(
            item,
            '{latestEvent,attention}',
            jsonb_build_object(
              'openedByMe',
              coalesce((
                select case when attention.attention_kind='marked_unread' then false else true end
                from atlas.communication_attention_events attention
                join atlas.organization_memberships membership
                  on membership.id=attention.membership_id
                 and membership.user_id=auth.uid()
                 and membership.active
                where attention.communication_event_id=(item#>>'{latestEvent,communicationEventId}')::uuid
                  and attention.attention_kind in ('opened','marked_read','marked_unread')
                order by attention.occurred_at desc,attention.id desc
                limit 1
              ),false),
              'latestAttentionKind',(
                select attention.attention_kind
                from atlas.communication_attention_events attention
                join atlas.organization_memberships membership
                  on membership.id=attention.membership_id
                 and membership.user_id=auth.uid()
                 and membership.active
                where attention.communication_event_id=(item#>>'{latestEvent,communicationEventId}')::uuid
                  and attention.attention_kind in ('previewed','opened','marked_read','marked_unread')
                order by attention.occurred_at desc,attention.id desc
                limit 1
              )
            ),
            true
          ),
          '{latestEvent,speakerDisplayName}',
          to_jsonb(coalesce((
            select nullif(btrim(participant.metadata->>'displayName'),'')
            from atlas.communication_event_participants participant
            where participant.communication_event_id=(item#>>'{latestEvent,communicationEventId}')::uuid
              and participant.participant_role='sender'
            order by participant.is_self asc,participant.created_at,participant.id
            limit 1
          ),item#>>'{latestEvent,speakerAddress}','Unknown sender')),
          true
        )
        || jsonb_build_object(
          'mailboxDisposition',
          coalesce((
            select disposition.disposition
            from atlas.communication_conversation_endpoint_disposition_events disposition
            where disposition.communication_conversation_id=(item->>'communicationConversationId')::uuid
              and disposition.communication_endpoint_id=coalesce(
                p_communication_endpoint_id,
                nullif(item#>>'{latestEvent,communicationEndpointId}','')::uuid
              )
            order by disposition.created_at desc,disposition.id desc
            limit 1
          ),'inbox')
        )
      end
      order by
        (item->'personalAttention' is not null) desc,
        nullif(item#>>'{personalAttention,nextDueAt}','')::timestamptz nulls last,
        (item->>'lastActivityAt')::timestamptz desc,
        item->>'communicationConversationId'
    ),
    '[]'::jsonb
  )
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item;

  return (v_base-'items') || jsonb_build_object(
    'contractVersion','organization_correspondence_list_v4',
    'viewerMembershipId',v_viewer_membership_id,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer) from public;
revoke all on function atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer) from anon;
grant execute on function atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer) to authenticated;
grant execute on function atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer) to service_role;

comment on function atlas.organization_correspondence_list_self_api_v4(uuid,uuid,integer)
is 'Common Communication Conversation list v4. Extends v3 with common mailbox disposition, viewer Organization membership, viewer-specific latest Communication Event attention (opened/read/unread), and exact-Event sender display identity without restoring Institutional inbox identity.';

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
  v_member atlas.organization_memberships%rowtype;
  v_sender text;
  v_event_id uuid;
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

  select * into v_member
  from atlas.organization_memberships
  where organization_id=v_conversation.organization_id
    and user_id=auth.uid()
    and active
  order by created_at,id
  limit 1;

  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(
       p_communication_endpoint_id,v_member.id,'close'
     ) then
    raise exception 'Communication close authority required to change mailbox disposition.' using errcode='42501';
  end if;

  insert into atlas.communication_conversation_endpoint_disposition_events(
    organization_id,
    communication_conversation_id,
    communication_endpoint_id,
    disposition,
    actor_membership_id,
    reason,
    metadata
  ) values (
    v_conversation.organization_id,
    v_conversation.id,
    p_communication_endpoint_id,
    p_disposition,
    v_member.id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('communicationCommandRoot','communication_conversation')
  )
  returning id into v_event_id;

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
        'communicationConversationId',v_conversation.id,
        'mailboxDispositionEventId',v_event_id
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
    'contractVersion','communication_conversation_endpoint_disposition_v2',
    'identityRoot','communication_conversation',
    'communicationConversationId',v_conversation.id,
    'communicationEndpointId',p_communication_endpoint_id,
    'mailboxDispositionEventId',v_event_id,
    'disposition',p_disposition
  );
end;
$function$;

create or replace function atlas.organization_correspondence_conversation_self_api_v6(
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
  v_endpoints jsonb;
begin
  v_base:=atlas.organization_correspondence_conversation_self_api_v5(
    p_communication_conversation_id
  );

  if coalesce(v_base->>'identityRoot','')<>'communication_conversation' then
    raise exception 'Common Correspondence detail lost Communication Conversation custody.' using errcode='23514';
  end if;

  select coalesce(jsonb_agg(
    endpoint||jsonb_build_object(
      'disposition',
      coalesce((
        select disposition.disposition
        from atlas.communication_conversation_endpoint_disposition_events disposition
        where disposition.communication_conversation_id=p_communication_conversation_id
          and disposition.communication_endpoint_id=nullif(endpoint->>'communicationEndpointId','')::uuid
        order by disposition.created_at desc,disposition.id desc
        limit 1
      ),'inbox')
    )
    order by endpoint->>'displayName',endpoint->>'address',endpoint->>'communicationEndpointId'
  ),'[]'::jsonb)
  into v_endpoints
  from jsonb_array_elements(coalesce(v_base->'endpoints','[]'::jsonb)) endpoint;

  return (v_base-'endpoints')||jsonb_build_object(
    'contractVersion','organization_correspondence_conversation_v6',
    'endpoints',v_endpoints
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_conversation_self_api_v6(uuid) from public;
revoke all on function atlas.organization_correspondence_conversation_self_api_v6(uuid) from anon;
grant execute on function atlas.organization_correspondence_conversation_self_api_v6(uuid) to authenticated;
grant execute on function atlas.organization_correspondence_conversation_self_api_v6(uuid) to service_role;

create or replace function atlas.organization_correspondence_search_self_api_v2(
  p_query text,
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_filters jsonb default '{}'::jsonb,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.organization_correspondence_search_self_api_v1(
    p_query,p_organization_id,p_communication_endpoint_id,p_filters,p_limit
  );

  select coalesce(jsonb_agg(
    item||jsonb_build_object(
      'disposition',
      coalesce((
        select disposition.disposition
        from atlas.communication_conversation_endpoint_disposition_events disposition
        where disposition.communication_conversation_id=(item->>'communicationConversationId')::uuid
          and disposition.communication_endpoint_id=coalesce(
            p_communication_endpoint_id,
            nullif(item->>'endpointId','')::uuid
          )
        order by disposition.created_at desc,disposition.id desc
        limit 1
      ),'inbox')
    )
    order by coalesce((item->>'rank')::real,0) desc,
             nullif(item->>'lastActivityAt','')::timestamptz desc nulls last,
             item->>'communicationConversationId'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item;

  return (v_base-'items')||jsonb_build_object(
    'contractVersion','organization_correspondence_search_v2',
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer) from public;
revoke all on function atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer) from anon;
grant execute on function atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer) to authenticated;
grant execute on function atlas.organization_correspondence_search_self_api_v2(text,uuid,uuid,jsonb,integer) to service_role;

commit;

begin;

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
is 'Common Communication Conversation list v4. Extends v3 with viewer Organization membership, viewer-specific latest Communication Event attention (opened/read/unread), and exact-Event sender display identity without restoring Institutional inbox identity.';

commit;

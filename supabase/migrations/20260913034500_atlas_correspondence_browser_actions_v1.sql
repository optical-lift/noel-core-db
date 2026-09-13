begin;

-- Read projections v2: read/unread is the latest explicit attention state,
-- not whether a message was ever opened in the past. The inbox projection also
-- exposes last-sender evidence so the Atlas presentation can distinguish human
-- correspondence from system traffic without making that heuristic canonical.
create or replace function atlas.institutional_shared_inbox_self_v2(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_member atlas.organization_memberships%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'Limit must be between 1 and 1000.' using errcode='22023';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id = p_communication_endpoint_id;
  if v_endpoint.id is null then
    raise exception 'Communication endpoint not found.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where organization_id = v_endpoint.organization_id
    and user_id = auth.uid()
    and active
  order by created_at
  limit 1;

  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id, v_member.id, 'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.last_activity_at desc, x.institutional_conversation_id),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      v.*,
      e.speaker_address as last_message_speaker_address,
      (
        select nullif(p.value->'metadata'->>'displayName','')
        from jsonb_array_elements(coalesce(e.canonical_event->'participants','[]'::jsonb)) as p(value)
        where p.value->>'role' = 'sender'
          and coalesce((p.value->>'isSelf')::boolean, false) = false
        limit 1
      ) as last_message_sender_display_name,
      coalesce((
        select case
          when a.attention_kind = 'marked_unread' then false
          else true
        end
        from atlas.communication_attention_events a
        where a.communication_event_id = v.last_message_event_id
          and a.membership_id = v_member.id
          and a.attention_kind in ('opened','marked_read','marked_unread')
        order by a.occurred_at desc, a.id desc
        limit 1
      ), false) as last_message_opened_by_me
    from atlas.v_institutional_shared_inbox_v1 v
    left join atlas.communication_events e on e.id = v.last_message_event_id
    where v.communication_endpoint_id = v_endpoint.id
    order by v.last_activity_at desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'contractVersion','institutional_shared_inbox_v2',
    'communicationEndpointId',v_endpoint.id,
    'membershipId',v_member.id,
    'items',v_items
  );
end;
$function$;

create or replace function atlas.institutional_conversation_detail_self_v2(
  p_institutional_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_endpoint_id uuid;
  v_member atlas.organization_memberships%rowtype;
  v_messages jsonb;
  v_response jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_conv
  from atlas.institutional_conversations
  where id = p_institutional_conversation_id;
  if v_conv.id is null then
    raise exception 'Institutional conversation not found.' using errcode='P0002';
  end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id = v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end, created_at
  limit 1;

  select * into v_member
  from atlas.organization_memberships
  where organization_id = v_conv.organization_id
    and user_id = auth.uid()
    and active
  order by created_at
  limit 1;

  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id, v_member.id, 'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at, x.communication_event_id), '[]'::jsonb)
  into v_messages
  from (
    select
      e.id as communication_event_id,
      e.occurred_at,
      e.direction,
      e.speaker_address,
      e.body,
      e.body_state,
      e.canonical_event,
      (select min(a.occurred_at)
         from atlas.communication_attention_events a
        where a.communication_event_id = e.id
          and a.attention_kind = 'opened') as first_opened_at,
      (select a.membership_id
         from atlas.communication_attention_events a
        where a.communication_event_id = e.id
          and a.attention_kind = 'opened'
        order by a.occurred_at, a.id
        limit 1) as first_opened_by_membership_id,
      coalesce((
        select case
          when a.attention_kind = 'marked_unread' then false
          else true
        end
        from atlas.communication_attention_events a
        where a.communication_event_id = e.id
          and a.membership_id = v_member.id
          and a.attention_kind in ('opened','marked_read','marked_unread')
        order by a.occurred_at desc, a.id desc
        limit 1
      ), false) as opened_by_me
    from atlas.institutional_conversation_messages m
    join atlas.communication_events e on e.id = m.communication_event_id
    where m.institutional_conversation_id = v_conv.id
  ) x;

  select to_jsonb(r) into v_response
  from atlas.v_institutional_shared_inbox_v1 r
  where r.institutional_conversation_id = v_conv.id;

  return jsonb_build_object(
    'contractVersion','institutional_conversation_detail_v2',
    'conversation',jsonb_build_object(
      'id',v_conv.id,
      'subject',v_conv.subject,
      'state',v_conv.conversation_state,
      'endpointId',v_endpoint_id
    ),
    'response',coalesce(v_response,'{}'::jsonb),
    'messages',v_messages,
    'membershipId',v_member.id
  );
end;
$function$;

-- Browser membranes. Each wrapper delegates to an existing self-authorized
-- Atlas command and intentionally adds no authority of its own.
create or replace function public.institutional_shared_inbox_self_v2(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.institutional_shared_inbox_self_v2(p_communication_endpoint_id, p_limit);
$function$;

create or replace function public.institutional_conversation_detail_self_v2(
  p_institutional_conversation_id uuid
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.institutional_conversation_detail_self_v2(p_institutional_conversation_id);
$function$;

create or replace function public.record_communication_attention_self_api_v1(
  p_communication_event_id uuid,
  p_attention_kind text default 'opened',
  p_client_event_key text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.record_communication_attention_self_api_v1(
    p_communication_event_id,
    p_attention_kind,
    p_client_event_key,
    p_metadata
  );
$function$;

create or replace function public.claim_institutional_conversation_self_api_v1(
  p_institutional_conversation_id uuid,
  p_reason text default null
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.claim_institutional_conversation_self_api_v1(
    p_institutional_conversation_id,
    p_reason
  );
$function$;

create or replace function public.handoff_institutional_conversation_self_api_v1(
  p_institutional_conversation_id uuid,
  p_target_membership_id uuid,
  p_reason text default null
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.handoff_institutional_conversation_self_api_v1(
    p_institutional_conversation_id,
    p_target_membership_id,
    p_reason
  );
$function$;

create or replace function public.set_institutional_conversation_response_state_self_api_v1(
  p_institutional_conversation_id uuid,
  p_to_state text,
  p_reason text default null
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.set_institutional_conversation_response_state_self_api_v1(
    p_institutional_conversation_id,
    p_to_state,
    p_reason
  );
$function$;

create or replace function public.prepare_institutional_email_send_self_api_v1(
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
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.prepare_institutional_email_send_self_api_v1(
    p_communication_endpoint_id,
    p_institutional_conversation_id,
    p_to_recipients,
    p_cc_recipients,
    p_bcc_recipients,
    p_subject,
    p_body_text,
    p_body_html,
    p_attachment_refs,
    p_reply_to_communication_event_id,
    p_idempotency_key
  );
$function$;

revoke all on function public.institutional_shared_inbox_self_v2(uuid, integer) from public, anon;
revoke all on function public.institutional_conversation_detail_self_v2(uuid) from public, anon;
revoke all on function public.record_communication_attention_self_api_v1(uuid, text, text, jsonb) from public, anon;
revoke all on function public.claim_institutional_conversation_self_api_v1(uuid, text) from public, anon;
revoke all on function public.handoff_institutional_conversation_self_api_v1(uuid, uuid, text) from public, anon;
revoke all on function public.set_institutional_conversation_response_state_self_api_v1(uuid, text, text) from public, anon;
revoke all on function public.prepare_institutional_email_send_self_api_v1(uuid, uuid, jsonb, jsonb, jsonb, text, text, text, jsonb, uuid, text) from public, anon;

grant execute on function public.institutional_shared_inbox_self_v2(uuid, integer) to authenticated, service_role;
grant execute on function public.institutional_conversation_detail_self_v2(uuid) to authenticated, service_role;
grant execute on function public.record_communication_attention_self_api_v1(uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function public.claim_institutional_conversation_self_api_v1(uuid, text) to authenticated, service_role;
grant execute on function public.handoff_institutional_conversation_self_api_v1(uuid, uuid, text) to authenticated, service_role;
grant execute on function public.set_institutional_conversation_response_state_self_api_v1(uuid, text, text) to authenticated, service_role;
grant execute on function public.prepare_institutional_email_send_self_api_v1(uuid, uuid, jsonb, jsonb, jsonb, text, text, text, jsonb, uuid, text) to authenticated, service_role;

comment on function public.record_communication_attention_self_api_v1(uuid, text, text, jsonb) is
  'Browser membrane for authenticated communication attention marks. Reading never claims responsibility.';
comment on function public.claim_institutional_conversation_self_api_v1(uuid, text) is
  'Browser membrane for the existing authority-checked institutional conversation claim command.';
comment on function public.handoff_institutional_conversation_self_api_v1(uuid, uuid, text) is
  'Browser membrane for the existing authority-checked institutional conversation handoff command.';
comment on function public.set_institutional_conversation_response_state_self_api_v1(uuid, text, text) is
  'Browser membrane for the existing authority-checked institutional response-state command.';
comment on function public.prepare_institutional_email_send_self_api_v1(uuid, uuid, jsonb, jsonb, jsonb, text, text, text, jsonb, uuid, text) is
  'Browser membrane for explicit authenticated institutional email send intent. This creates an authorized outbound operation; transport remains separate.';

commit;

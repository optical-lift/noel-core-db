begin;

create or replace function atlas.organization_correspondence_access_self_api_v1(
  p_organization_id uuid default null
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

  select coalesce(jsonb_agg(item order by item->>'organizationName',item->>'address'),'[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'communicationEndpointId',ep.id,
      'organizationId',effective_org.id,
      'organizationName',effective_org.name,
      'physicalOrganizationId',ep.organization_id,
      'organizationUnitId',ep.organization_unit_id,
      'organizationUnitName',unit.name,
      'endpointKind',ep.endpoint_kind,
      'address',ep.address,
      'displayName',ep.display_name,
      'endpointState',ep.endpoint_state,
      'membershipId',viewer_membership.id,
      'organizationRole',viewer_membership.role,
      'isOwner',(viewer_membership.role='owner'),
      'capabilities',jsonb_build_object(
        'view',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'view'),
        'send',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'send'),
        'claim',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'claim'),
        'handoff',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'handoff'),
        'close',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'close'),
        'admin',atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'admin')
      ),
      'providerKey',source.provider_key,
      'providerAccountKey',source.provider_account_key,
      'authorizationState',source.authorization_state,
      'sourceCapabilities',coalesce(source.capabilities,'{}'::jsonb),
      'lastSyncAt',source.last_sync_at,
      'members',case
        when viewer_membership.role='owner'
          or atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'handoff')
          or atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'admin')
        then coalesce((
          select jsonb_agg(jsonb_build_object(
            'membershipId',member.id,
            'role',member.role,
            'label',coalesce(member_user.email,member.id::text),
            'canClaim',atlas.communication_endpoint_membership_has_capability_v1(ep.id,member.id,'claim')
          ) order by coalesce(member_user.email,member.id::text),member.id)
          from atlas.organization_memberships member
          left join auth.users member_user on member_user.id=member.user_id
          where member.organization_id=ep.organization_id
            and member.active
        ),'[]'::jsonb)
        else '[]'::jsonb
      end
    ) as item
    from atlas.communication_endpoints ep
    join atlas.organization_memberships viewer_membership
      on viewer_membership.organization_id=ep.organization_id
     and viewer_membership.user_id=auth.uid()
     and viewer_membership.active
    join atlas.organizations effective_org
      on effective_org.id=atlas.effective_communication_endpoint_organization_v1(ep.id)
     and effective_org.status='active'
    left join atlas.organization_units unit
      on unit.id=ep.organization_unit_id
     and unit.organization_id=ep.organization_id
    left join lateral (
      select connected_source.*
      from atlas.communication_endpoint_source_bindings binding
      join atlas.connected_sources connected_source
        on connected_source.id=binding.connected_source_id
      where binding.communication_endpoint_id=ep.id
        and binding.binding_state='active'
      order by
        case binding.binding_role when 'send_receive' then 0 when 'receive' then 1 else 2 end,
        binding.created_at desc,
        binding.id
      limit 1
    ) source on true
    where ep.endpoint_state='active'
      and atlas.communication_endpoint_membership_has_capability_v1(ep.id,viewer_membership.id,'view')
      and (p_organization_id is null or effective_org.id=p_organization_id)
  ) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_access_v1',
    'identityRoot','communication_endpoint',
    'organizationId',p_organization_id,
    'items',v_items
  );
end;
$function$;

create or replace function atlas.organization_correspondence_attention_summary_self_api_v1(
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_attention_count integer;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  with authorized_conversations as (
    select
      conversation.id as communication_conversation_id,
      atlas.organization_correspondence_effective_organization_v1(conversation.id) as effective_organization_id,
      conversation.subject,
      atlas.current_effective_organization_membership_v1(
        atlas.organization_correspondence_effective_organization_v1(conversation.id)
      ) as viewer_membership_id
    from atlas.communication_conversations conversation
    where conversation.organization_id is not null
      and conversation.principal_id is null
      and atlas.organization_correspondence_read_authorized_self_v1(conversation.id)
      and (
        p_organization_id is null
        or atlas.organization_correspondence_effective_organization_v1(conversation.id)=p_organization_id
      )
  ),
  correspondence_state as (
    select
      authorized.communication_conversation_id,
      authorized.effective_organization_id,
      authorized.viewer_membership_id,
      authorized.subject,
      latest_event.communication_event_id,
      latest_event.speaker_address,
      response_case.case_state as response_state,
      responsible.assignee_membership_id as responsible_membership_id
    from authorized_conversations authorized
    left join lateral (
      select
        event.id as communication_event_id,
        event.speaker_address
      from atlas.communication_conversation_events membership
      join atlas.communication_events event
        on event.id=membership.communication_event_id
      where membership.communication_conversation_id=authorized.communication_conversation_id
      order by
        coalesce(membership.occurred_at,event.occurred_at,event.captured_at) desc,
        membership.created_at desc,
        membership.id desc
      limit 1
    ) latest_event on true
    left join lateral (
      select response.*
      from atlas.institutional_conversation_roots root
      join atlas.institutional_conversation_response_cases response
        on response.institutional_conversation_id=root.institutional_conversation_id
      where root.communication_conversation_id=authorized.communication_conversation_id
      order by
        (response.case_state<>'closed') desc,
        response.opened_at desc,
        response.id desc
      limit 1
    ) response_case on true
    left join lateral (
      select allocation.assignee_membership_id
      from atlas.institutional_conversation_response_work_bindings binding
      join atlas.work_allocations allocation
        on allocation.work_item_id=binding.work_item_id
      where binding.response_case_id=response_case.id
        and allocation.allocation_role='responsible'
        and allocation.state='active'
      order by allocation.allocated_at desc,allocation.id desc
      limit 1
    ) responsible on true
  )
  select count(*)::integer
  into v_attention_count
  from correspondence_state state
  where
    (
      state.response_state in ('needs_response','waiting_internal')
      and state.viewer_membership_id is not null
      and state.responsible_membership_id=state.viewer_membership_id
    )
    or
    (
      (state.response_state='unclaimed' or state.responsible_membership_id is null)
      and not (
        coalesce(state.speaker_address,'') ~* '(^|[-._+])(no-?reply|automated|automation|dmarc|mailer-daemon|notification|notifications|alerts?|security)([-._+]|@|$)'
        or coalesce(state.subject,'') ~* '\\m(confirmation code|verification code|reset your password|password reset|report domain:|report domain|dmarc|account activity:|account alert:|new login|security alert|one[- ]time code|sign[- ]in code)\\M'
      )
    );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_attention_summary_v1',
    'identityRoot','communication_conversation',
    'organizationId',p_organization_id,
    'attentionCount',coalesce(v_attention_count,0),
    'countSemantics','unique_common_conversations'
  );
end;
$function$;

revoke all on function atlas.organization_correspondence_access_self_api_v1(uuid) from public,anon;
grant execute on function atlas.organization_correspondence_access_self_api_v1(uuid) to authenticated,service_role;

revoke all on function atlas.organization_correspondence_attention_summary_self_api_v1(uuid) from public,anon;
grant execute on function atlas.organization_correspondence_attention_summary_self_api_v1(uuid) to authenticated,service_role;

comment on function atlas.organization_correspondence_access_self_api_v1(uuid) is
'Common Correspondence access metadata for Communication Endpoints. Returns endpoint authority, source send state, and bounded Organization member choices without Institutional Conversation identity.';

comment on function atlas.organization_correspondence_attention_summary_self_api_v1(uuid) is
'Common Correspondence attention summary. Counts unique authorized Communication Conversations needing viewer attention; response-case tables remain compatibility consequence storage and never become the identity root.';

commit;

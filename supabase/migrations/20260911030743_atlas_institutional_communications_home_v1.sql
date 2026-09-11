begin;

create or replace function atlas.institutional_communications_home_self_api_v1()
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

  select coalesce(jsonb_agg(item order by item->>'organizationName', item->>'address'),'[]'::jsonb)
  into v_items
  from (
    select jsonb_build_object(
      'communicationEndpointId', ep.id,
      'organizationId', ep.organization_id,
      'organizationName', org.name,
      'organizationUnitId', ep.organization_unit_id,
      'organizationUnitName', unit.name,
      'endpointKind', ep.endpoint_kind,
      'address', ep.address,
      'displayName', ep.display_name,
      'endpointState', ep.endpoint_state,
      'membershipId', me.id,
      'organizationRole', me.role,
      'isOwner', (me.role='owner'),
      'capabilities', jsonb_build_object(
        'view', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'view'),
        'send', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'send'),
        'claim', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'claim'),
        'handoff', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'handoff'),
        'close', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'close'),
        'admin', atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'admin')
      ),
      'connectedSourceId', src.id,
      'providerKey', src.provider_key,
      'providerAccountKey', src.provider_account_key,
      'authorizationState', src.authorization_state,
      'sourceCapabilities', coalesce(src.capabilities,'{}'::jsonb),
      'credentialPresent', case when src.id is null then false else exists(
        select 1 from atlas.connected_source_secret_refs secret_ref
        where secret_ref.connected_source_id=src.id and secret_ref.credential_kind='mailbox_password'
      ) end,
      'lastSyncAt', src.last_sync_at,
      'historyPolicy', coalesce(src.metadata->'communicationHistoryPolicy',jsonb_build_object('mode','from_now')),
      'gatewayState', heartbeat.state,
      'gatewayObservedAt', heartbeat.observed_at,
      'gatewayDetail', heartbeat.detail,
      'members', case
        when me.role='owner' or atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'handoff') or atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'admin') then
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'membershipId', member.id,
              'role', member.role,
              'label', coalesce(member_user.email,member.id::text),
              'canClaim', atlas.communication_endpoint_membership_has_capability_v1(ep.id,member.id,'claim')
            ) order by coalesce(member_user.email,member.id::text))
            from atlas.organization_memberships member
            left join auth.users member_user on member_user.id=member.user_id
            where member.organization_id=ep.organization_id and member.active
          ),'[]'::jsonb)
        else '[]'::jsonb
      end
    ) as item
    from atlas.communication_endpoints ep
    join atlas.organizations org on org.id=ep.organization_id
    left join atlas.organization_units unit on unit.id=ep.organization_unit_id and unit.organization_id=ep.organization_id
    join atlas.organization_memberships me on me.organization_id=ep.organization_id and me.user_id=auth.uid() and me.active
    left join lateral (
      select source.*
      from atlas.communication_endpoint_source_bindings binding
      join atlas.connected_sources source on source.id=binding.connected_source_id
      where binding.communication_endpoint_id=ep.id and binding.binding_state='active'
      order by case binding.binding_role when 'send_receive' then 0 when 'receive' then 1 else 2 end, binding.created_at desc, binding.id
      limit 1
    ) src on true
    left join lateral (
      select hb.*
      from atlas.communication_gateway_heartbeats hb
      where hb.connected_source_id=src.id
      order by hb.observed_at desc,hb.id desc
      limit 1
    ) heartbeat on true
    where ep.endpoint_state='active'
      and atlas.communication_endpoint_membership_has_capability_v1(ep.id,me.id,'view')
  ) q;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','institutional_communications_home_v1',
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.institutional_communications_home_self_api_v1() from public,anon;
grant execute on function atlas.institutional_communications_home_self_api_v1() to authenticated,service_role;

commit;

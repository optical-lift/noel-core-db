begin;

create or replace function atlas.organization_communication_endpoint_setup_authorized_self_v1(
  p_organization_id uuid
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null and (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id=p_organization_id
        and membership.user_id=auth.uid()
        and membership.active
        and membership.role='owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id=p_organization_id
        and actor.human_user_id=auth.uid()
        and actor.actor_kind='setup_actor'
        and actor.active
    )
  );
$function$;
revoke all on function atlas.organization_communication_endpoint_setup_authorized_self_v1(uuid) from public,anon,authenticated;

create or replace function atlas.upsert_communication_endpoint_self_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_endpoint_kind text,
  p_address text,
  p_display_name text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_kind text:=lower(btrim(coalesce(p_endpoint_kind,'')));
  v_address text:=btrim(coalesce(p_address,''));
  v_norm text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if not atlas.organization_communication_endpoint_setup_authorized_self_v1(p_organization_id) then
    raise exception 'Organization communication setup authority required.' using errcode='42501';
  end if;
  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.organization_id=p_organization_id and u.id=p_organization_unit_id
  ) then
    raise exception 'Organization unit is outside organization.' using errcode='23514';
  end if;
  if v_kind not in ('email','phone','sms','voice','web_form','social','atlas_native','other') or v_address='' then
    raise exception 'Valid endpoint kind and address are required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Endpoint metadata must be an object.' using errcode='22023';
  end if;

  v_norm:=atlas.normalize_communication_endpoint_address_v1(v_kind,v_address);
  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.organization_id=p_organization_id
    and ep.organization_unit_id is not distinct from p_organization_unit_id
    and ep.endpoint_kind=v_kind
    and ep.address_normalized=v_norm
  for update;

  if v_endpoint.id is null then
    insert into atlas.communication_endpoints(
      organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,metadata
    ) values (
      p_organization_id,p_organization_unit_id,v_kind,v_address,v_norm,
      nullif(btrim(p_display_name),''),coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_endpoint;
  else
    update atlas.communication_endpoints
    set display_name=coalesce(nullif(btrim(p_display_name),''),display_name),
        metadata=metadata||coalesce(p_metadata,'{}'::jsonb),
        endpoint_state='active',
        updated_at=now()
    where id=v_endpoint.id
    returning * into v_endpoint;
  end if;

  return jsonb_build_object(
    'contractVersion','communication_endpoint_v1',
    'communicationEndpointId',v_endpoint.id,
    'organizationId',v_endpoint.organization_id,
    'organizationUnitId',v_endpoint.organization_unit_id,
    'endpointKind',v_endpoint.endpoint_kind,
    'address',v_endpoint.address,
    'addressNormalized',v_endpoint.address_normalized,
    'endpointState',v_endpoint.endpoint_state
  );
end;
$function$;
revoke all on function atlas.upsert_communication_endpoint_self_api_v1(uuid,uuid,text,text,text,jsonb) from public,anon;
grant execute on function atlas.upsert_communication_endpoint_self_api_v1(uuid,uuid,text,text,text,jsonb) to authenticated;

create or replace function atlas.bind_communication_endpoint_source_self_api_v1(
  p_communication_endpoint_id uuid,
  p_connected_source_id uuid,
  p_binding_role text default 'send_receive',
  p_transport_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_binding atlas.communication_endpoint_source_bindings%rowtype;
  v_role text:=lower(btrim(coalesce(p_binding_role,'')));
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id;
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  if not atlas.organization_communication_endpoint_setup_authorized_self_v1(v_endpoint.organization_id) then
    raise exception 'Organization communication setup authority required.' using errcode='42501';
  end if;
  if v_role not in ('receive','send','send_receive') then
    raise exception 'Unsupported endpoint/source binding role.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_transport_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Endpoint/source transport metadata must be an object.' using errcode='22023';
  end if;

  select * into v_binding
  from atlas.communication_endpoint_source_bindings
  where communication_endpoint_id=v_endpoint.id
    and connected_source_id=p_connected_source_id
    and binding_state='active'
  limit 1
  for update;

  if v_binding.id is null then
    insert into atlas.communication_endpoint_source_bindings(
      communication_endpoint_id,connected_source_id,binding_role,transport_metadata
    ) values (
      v_endpoint.id,p_connected_source_id,v_role,coalesce(p_transport_metadata,'{}'::jsonb)
    ) returning * into v_binding;
  else
    update atlas.communication_endpoint_source_bindings
    set binding_role=v_role,
        transport_metadata=transport_metadata||coalesce(p_transport_metadata,'{}'::jsonb),
        updated_at=now()
    where id=v_binding.id
    returning * into v_binding;
  end if;

  return jsonb_build_object(
    'contractVersion','communication_endpoint_source_binding_v1',
    'bindingId',v_binding.id,
    'communicationEndpointId',v_endpoint.id,
    'connectedSourceId',p_connected_source_id,
    'bindingRole',v_binding.binding_role,
    'bindingState',v_binding.binding_state
  );
end;
$function$;
revoke all on function atlas.bind_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) from public,anon;
grant execute on function atlas.bind_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) to authenticated;

comment on function atlas.organization_communication_endpoint_setup_authorized_self_v1(uuid) is
  'Communication infrastructure setup authority for an organization: active owner or active organization onboarding setup_actor. Does not grant endpoint member capabilities.';

commit;

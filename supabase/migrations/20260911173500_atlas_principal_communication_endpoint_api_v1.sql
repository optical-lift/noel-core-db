begin;

create or replace function atlas.principal_communication_endpoints_self_api_v1()
returns table(
  communication_endpoint_id uuid,
  principal_id uuid,
  endpoint_kind text,
  address text,
  address_normalized text,
  display_name text,
  endpoint_state text,
  connected_source_id uuid,
  provider_key text,
  provider_account_key text,
  authorization_state text,
  binding_role text,
  binding_state text,
  source_capabilities jsonb,
  last_sync_at timestamptz
)
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  with me as (
    select p.id as principal_id
    from atlas.principals p
    where p.user_id=auth.uid() and p.status='active'
    order by p.created_at,p.id
    limit 1
  )
  select
    ep.id,
    ep.principal_id,
    ep.endpoint_kind,
    ep.address,
    ep.address_normalized,
    ep.display_name,
    ep.endpoint_state,
    b.connected_source_id,
    s.provider_key,
    s.provider_account_key,
    s.authorization_state,
    b.binding_role,
    b.binding_state,
    coalesce(s.capabilities,'{}'::jsonb),
    s.last_sync_at
  from me
  join atlas.communication_endpoints ep on ep.principal_id=me.principal_id
  left join atlas.communication_endpoint_source_bindings b
    on b.communication_endpoint_id=ep.id and b.binding_state='active'
  left join atlas.connected_sources s on s.id=b.connected_source_id
  order by ep.endpoint_kind,ep.address_normalized,b.created_at,b.id;
$function$;

revoke all on function atlas.principal_communication_endpoints_self_api_v1() from public;
grant execute on function atlas.principal_communication_endpoints_self_api_v1() to authenticated;

create or replace function atlas.bind_principal_communication_endpoint_source_self_api_v1(
  p_communication_endpoint_id uuid,
  p_connected_source_id uuid,
  p_binding_role text default 'send_receive',
  p_transport_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_binding atlas.communication_endpoint_source_bindings%rowtype;
  v_role text:=lower(btrim(coalesce(p_binding_role,'')));
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals
  where user_id=auth.uid() and status='active'
  order by created_at,id
  limit 1;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and principal_id=v_principal.id
    and endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Principal communication endpoint not found.' using errcode='P0002';
  end if;

  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id
    and custodian_user_id=auth.uid()
    and custodian_organization_id is null
    and authorization_state<>'revoked';

  if v_source.id is null then
    raise exception 'Connected source is outside Principal custody or revoked.' using errcode='42501';
  end if;

  if v_role not in ('receive','send','send_receive') then
    raise exception 'Unsupported endpoint/source binding role.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_transport_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Transport metadata must be an object.' using errcode='22023';
  end if;

  select * into v_binding
  from atlas.communication_endpoint_source_bindings
  where communication_endpoint_id=v_endpoint.id
    and connected_source_id=v_source.id
    and binding_state='active'
  limit 1
  for update;

  if v_binding.id is null then
    insert into atlas.communication_endpoint_source_bindings(
      communication_endpoint_id,connected_source_id,binding_role,transport_metadata
    )
    values(
      v_endpoint.id,v_source.id,v_role,coalesce(p_transport_metadata,'{}'::jsonb)
    )
    returning * into v_binding;
  else
    update atlas.communication_endpoint_source_bindings
    set binding_role=v_role,
        transport_metadata=transport_metadata||coalesce(p_transport_metadata,'{}'::jsonb),
        updated_at=now()
    where id=v_binding.id
    returning * into v_binding;
  end if;

  return jsonb_build_object(
    'contractVersion','principal_communication_endpoint_source_binding_v1',
    'bindingId',v_binding.id,
    'communicationEndpointId',v_endpoint.id,
    'principalId',v_principal.id,
    'connectedSourceId',v_source.id,
    'bindingRole',v_binding.binding_role,
    'bindingState',v_binding.binding_state
  );
end;
$function$;

revoke all on function atlas.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) from public;
grant execute on function atlas.bind_principal_communication_endpoint_source_self_api_v1(uuid,uuid,text,jsonb) to authenticated;

-- Actionability is append-only. More than one accepted assessment may exist over
-- time; the effective read deliberately chooses the latest accepted assessment.
-- A partial unique index would prevent append-only correction, so remove it.
drop index if exists atlas.communication_actionability_one_current_accepted_uq;

alter table atlas.communication_actionability_assessments
  add column supersedes_assessment_id uuid references atlas.communication_actionability_assessments(id) on delete restrict;

comment on column atlas.communication_actionability_assessments.supersedes_assessment_id is
'Optional append-only correction lineage. A later assessment may supersede an earlier assessment without mutating the earlier evidence.';

commit;

alter table atlas.connected_sources
  add column if not exists custodian_organization_unit_id uuid;

alter table atlas.connected_sources
  drop constraint if exists connected_sources_custodian_organization_unit_fk;
alter table atlas.connected_sources
  add constraint connected_sources_custodian_organization_unit_fk
  foreign key (custodian_organization_id, custodian_organization_unit_id)
  references atlas.organization_units(organization_id, id)
  on delete restrict;

create index if not exists connected_sources_organization_unit_idx
  on atlas.connected_sources(custodian_organization_id, custodian_organization_unit_id, provider_key)
  where custodian_organization_unit_id is not null;

create or replace function atlas.bind_connected_source_organization_unit_service_v1(
  p_connected_source_id uuid,
  p_organization_unit_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id for update;
  if v_source.id is null or v_source.custodian_organization_id is null then
    raise exception 'Organization-custodied connected source required.' using errcode='55000';
  end if;
  if not exists (
    select 1 from atlas.organization_units ou
    where ou.organization_id=v_source.custodian_organization_id and ou.id=p_organization_unit_id
  ) then
    raise exception 'Organization unit is outside connected source organization.' using errcode='23514';
  end if;
  if v_source.custodian_organization_unit_id is not null and v_source.custodian_organization_unit_id <> p_organization_unit_id then
    raise exception 'Connected source is already bound to another organization unit.' using errcode='55000';
  end if;
  update atlas.connected_sources
  set custodian_organization_unit_id=p_organization_unit_id,
      metadata=metadata || jsonb_build_object('ledgerBinding','explicit_organization_unit'),
      updated_at=now()
  where id=v_source.id;
  return jsonb_build_object('connectedSourceId',v_source.id,'organizationId',v_source.custodian_organization_id,'organizationUnitId',p_organization_unit_id);
end;
$function$;

revoke all on function atlas.bind_connected_source_organization_unit_service_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.bind_connected_source_organization_unit_service_v1(uuid,uuid) to service_role;
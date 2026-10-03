create or replace function reality.entity_operating_roots_service_v1(
  p_entity_id uuid,
  p_max_depth integer default 8,
  p_as_of timestamptz default now()
) returns table(
  root_entity_id uuid,
  root_entity_kind text,
  root_display_name text,
  depth integer,
  path_entity_ids uuid[],
  path_relationship_ids uuid[],
  path_relationship_kinds text[]
)
language sql stable security definer set search_path to ''
as $function$
  with ranked as (
    select distinct on (r.root_entity_id)
      r.root_entity_id,
      e.entity_kind as root_entity_kind,
      e.display_name as root_display_name,
      r.depth,
      r.path_entity_ids,
      r.path_relationship_ids,
      r.path_relationship_kinds
    from reality.entity_topology_roots_service_v1(p_entity_id,'operating_structure',p_max_depth,p_as_of) r
    join reality.entities e on e.id=r.root_entity_id and e.identity_state='canonical'
    order by r.root_entity_id,r.depth asc,r.path_relationship_kinds::text,r.path_relationship_ids::text
  )
  select root_entity_id,root_entity_kind,root_display_name,depth,path_entity_ids,path_relationship_ids,path_relationship_kinds
  from ranked
  order by depth desc,root_entity_id
$function$;

revoke all on function reality.entity_operating_roots_service_v1(uuid,integer,timestamptz) from public,anon,authenticated;
grant execute on function reality.entity_operating_roots_service_v1(uuid,integer,timestamptz) to service_role;
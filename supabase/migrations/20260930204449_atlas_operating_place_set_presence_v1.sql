create or replace function reality.operating_root_place_set_presence_service_v1(
  p_root_entity_id uuid,
  p_place_entity_ids uuid[],
  p_max_operating_depth integer default 8,
  p_max_spatial_depth integer default 8,
  p_as_of timestamptz default now()
) returns table(
  matched_place_entity_id uuid,
  operating_member_entity_id uuid,
  operating_depth integer,
  spatial_depth integer,
  operating_path_entity_ids uuid[],
  operating_path_relationship_ids uuid[],
  operating_path_relationship_kinds text[],
  spatial_path_entity_ids uuid[],
  spatial_path_relationship_ids uuid[],
  spatial_path_relationship_kinds text[]
)
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_root_count integer;
  v_root uuid;
  v_place_count integer;
begin
  if p_root_entity_id is null then raise exception 'Operating root Entity id is required.' using errcode='22023'; end if;
  if p_place_entity_ids is null or cardinality(p_place_entity_ids)=0 or cardinality(p_place_entity_ids)>100 then raise exception 'Place Entity set must contain 1 to 100 ids.' using errcode='22023'; end if;
  if array_position(p_place_entity_ids,null) is not null then raise exception 'Place Entity set cannot contain null ids.' using errcode='22023'; end if;
  if p_max_operating_depth<1 or p_max_operating_depth>32 or p_max_spatial_depth<1 or p_max_spatial_depth>32 then raise exception 'Traversal depths must be between 1 and 32.' using errcode='22023'; end if;
  if not exists(select 1 from reality.entities e where e.id=p_root_entity_id and e.identity_state='canonical') then raise exception 'Canonical Reality operating root required.' using errcode='P0002'; end if;

  select count(*),min(r.root_entity_id::text)::uuid into v_root_count,v_root
  from reality.entity_operating_roots_service_v1(p_root_entity_id,p_max_operating_depth,p_as_of) r;
  if v_root_count<>1 or v_root<>p_root_entity_id then raise exception 'Input Entity must already be the unique normalized operating root.' using errcode='23514'; end if;

  select count(distinct x)::integer into v_place_count from unnest(p_place_entity_ids) x;
  if v_place_count<>cardinality(p_place_entity_ids) then raise exception 'Place Entity set cannot contain duplicate ids.' using errcode='22023'; end if;
  if exists(
    select 1 from unnest(p_place_entity_ids) x
    where not exists(
      select 1 from reality.entities e
      join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
      where e.id=x and e.identity_state='canonical' and e.entity_kind='place'
    )
  ) then raise exception 'Every Place id must reference a canonical Reality Place with an active Place profile.' using errcode='23514'; end if;

  return query
  with raw_members as (
    select p_root_entity_id as member_id,0::integer as op_depth,array[p_root_entity_id]::uuid[] as op_entities,'{}'::uuid[] as op_relationships,'{}'::text[] as op_kinds
    union all
    select p.related_entity_id,p.depth,p.path_entity_ids,p.path_relationship_ids,p.path_relationship_kinds
    from reality.entity_topology_paths_service_v1(p_root_entity_id,'operating_structure','descendants',p_max_operating_depth,p_as_of,true) p
  ),
  members as (
    select distinct on (member_id) member_id,op_depth,op_entities,op_relationships,op_kinds
    from raw_members
    order by member_id,op_depth asc,op_relationships::text
  ),
  direct_matches as (
    select m.member_id as place_id,m.member_id,m.op_depth,0::integer as sp_depth,m.op_entities,m.op_relationships,m.op_kinds,array[m.member_id]::uuid[] as sp_entities,'{}'::uuid[] as sp_relationships,'{}'::text[] as sp_kinds
    from members m where m.member_id=any(p_place_entity_ids)
  ),
  ancestor_matches as (
    select sp.related_entity_id as place_id,m.member_id,m.op_depth,sp.depth as sp_depth,m.op_entities,m.op_relationships,m.op_kinds,sp.path_entity_ids as sp_entities,sp.path_relationship_ids as sp_relationships,sp.path_relationship_kinds as sp_kinds
    from members m
    cross join lateral reality.entity_topology_paths_service_v1(m.member_id,'spatial_containment','ancestors',p_max_spatial_depth,p_as_of,true) sp
    where sp.related_entity_id=any(p_place_entity_ids)
  ),
  matches as (
    select * from direct_matches
    union all
    select * from ancestor_matches
  )
  select distinct on (m.place_id,m.member_id)
    m.place_id,m.member_id,m.op_depth,m.sp_depth,m.op_entities,m.op_relationships,m.op_kinds,m.sp_entities,m.sp_relationships,m.sp_kinds
  from matches m
  order by m.place_id,m.member_id,m.op_depth asc,m.sp_depth asc,m.op_relationships::text,m.sp_relationships::text;
end
$function$;

revoke all on function reality.operating_root_place_set_presence_service_v1(uuid,uuid[],integer,integer,timestamptz) from public,anon,authenticated;
grant execute on function reality.operating_root_place_set_presence_service_v1(uuid,uuid[],integer,integer,timestamptz) to service_role;
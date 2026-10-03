-- ATLAS_PAIRED_OPERATING_PRESENCE_V1

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
    select
      p_root_entity_id as member_id,
      0::integer as op_depth,
      array[p_root_entity_id]::uuid[] as op_entities,
      '{}'::uuid[] as op_relationships,
      '{}'::text[] as op_kinds
    union all
    select
      p.related_entity_id,
      p.depth,
      p.path_entity_ids,
      p.path_relationship_ids,
      p.path_relationship_kinds
    from reality.entity_topology_paths_service_v1(
      p_root_entity_id,'operating_structure','descendants',p_max_operating_depth,p_as_of,true
    ) p
  ),
  members as (
    select distinct on (member_id)
      member_id,op_depth,op_entities,op_relationships,op_kinds
    from raw_members
    order by member_id,op_depth asc,op_relationships::text
  ),
  direct_matches as (
    select
      m.member_id as place_id,
      m.member_id,
      m.op_depth,
      0::integer as sp_depth,
      m.op_entities,m.op_relationships,m.op_kinds,
      array[m.member_id]::uuid[] as sp_entities,
      '{}'::uuid[] as sp_relationships,
      '{}'::text[] as sp_kinds
    from members m
    where m.member_id=any(p_place_entity_ids)
  ),
  ancestor_matches as (
    select
      sp.related_entity_id as place_id,
      m.member_id,
      m.op_depth,
      sp.depth as sp_depth,
      m.op_entities,m.op_relationships,m.op_kinds,
      sp.path_entity_ids as sp_entities,
      sp.path_relationship_ids as sp_relationships,
      sp.path_relationship_kinds as sp_kinds
    from members m
    cross join lateral reality.entity_topology_paths_service_v1(
      m.member_id,'spatial_containment','ancestors',p_max_spatial_depth,p_as_of,true
    ) sp
    where sp.related_entity_id=any(p_place_entity_ids)
  ),
  matches as (
    select * from direct_matches
    union all
    select * from ancestor_matches
  )
  select distinct on (m.place_id,m.member_id)
    m.place_id,m.member_id,m.op_depth,m.sp_depth,
    m.op_entities,m.op_relationships,m.op_kinds,
    m.sp_entities,m.sp_relationships,m.sp_kinds
  from matches m
  order by m.place_id,m.member_id,m.op_depth asc,m.sp_depth asc,m.op_relationships::text,m.sp_relationships::text;
end
$function$;

create or replace function reality.evaluate_operating_place_pair_service_v1(
  p_entity_id uuid,
  p_side_a_place_entity_ids uuid[],
  p_side_b_place_entity_ids uuid[],
  p_max_operating_depth integer default 8,
  p_max_spatial_depth integer default 8,
  p_as_of timestamptz default now()
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_root_count integer;
  v_root uuid;
  v_root_kind text;
  v_root_name text;
  v_root_depth integer;
  v_root_entities uuid[];
  v_root_relationships uuid[];
  v_root_kinds text[];
  v_side_a jsonb:='[]'::jsonb;
  v_side_b jsonb:='[]'::jsonb;
  v_obligations jsonb:='[]'::jsonb;
  v_state text;
begin
  if p_entity_id is null then raise exception 'Reality Entity id is required.' using errcode='22023'; end if;
  if p_side_a_place_entity_ids is null or cardinality(p_side_a_place_entity_ids)=0 or p_side_b_place_entity_ids is null or cardinality(p_side_b_place_entity_ids)=0 then raise exception 'Both Place sets are required.' using errcode='22023'; end if;
  if p_side_a_place_entity_ids && p_side_b_place_entity_ids then raise exception 'Paired Place sets must not share the same Place Entity id.' using errcode='22023'; end if;

  select count(*) into v_root_count from reality.entity_operating_roots_service_v1(p_entity_id,p_max_operating_depth,p_as_of);
  if v_root_count<>1 then raise exception 'Entity must resolve to exactly one operating root.' using errcode='23514'; end if;
  select root_entity_id,root_entity_kind,root_display_name,depth,path_entity_ids,path_relationship_ids,path_relationship_kinds
  into v_root,v_root_kind,v_root_name,v_root_depth,v_root_entities,v_root_relationships,v_root_kinds
  from reality.entity_operating_roots_service_v1(p_entity_id,p_max_operating_depth,p_as_of)
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'matchedPlaceEntityId',p.matched_place_entity_id,
    'operatingMemberEntityId',p.operating_member_entity_id,
    'operatingDepth',p.operating_depth,
    'spatialDepth',p.spatial_depth,
    'operatingProof',jsonb_build_object('entityIds',to_jsonb(p.operating_path_entity_ids),'relationshipIds',to_jsonb(p.operating_path_relationship_ids),'relationshipKinds',to_jsonb(p.operating_path_relationship_kinds)),
    'spatialProof',jsonb_build_object('entityIds',to_jsonb(p.spatial_path_entity_ids),'relationshipIds',to_jsonb(p.spatial_path_relationship_ids),'relationshipKinds',to_jsonb(p.spatial_path_relationship_kinds))
  ) order by p.matched_place_entity_id,p.operating_member_entity_id,p.operating_depth,p.spatial_depth),'[]'::jsonb)
  into v_side_a
  from reality.operating_root_place_set_presence_service_v1(v_root,p_side_a_place_entity_ids,p_max_operating_depth,p_max_spatial_depth,p_as_of) p;

  select coalesce(jsonb_agg(jsonb_build_object(
    'matchedPlaceEntityId',p.matched_place_entity_id,
    'operatingMemberEntityId',p.operating_member_entity_id,
    'operatingDepth',p.operating_depth,
    'spatialDepth',p.spatial_depth,
    'operatingProof',jsonb_build_object('entityIds',to_jsonb(p.operating_path_entity_ids),'relationshipIds',to_jsonb(p.operating_path_relationship_ids),'relationshipKinds',to_jsonb(p.operating_path_relationship_kinds)),
    'spatialProof',jsonb_build_object('entityIds',to_jsonb(p.spatial_path_entity_ids),'relationshipIds',to_jsonb(p.spatial_path_relationship_ids),'relationshipKinds',to_jsonb(p.spatial_path_relationship_kinds))
  ) order by p.matched_place_entity_id,p.operating_member_entity_id,p.operating_depth,p.spatial_depth),'[]'::jsonb)
  into v_side_b
  from reality.operating_root_place_set_presence_service_v1(v_root,p_side_b_place_entity_ids,p_max_operating_depth,p_max_spatial_depth,p_as_of) p;

  if jsonb_array_length(v_side_a)>0 and jsonb_array_length(v_side_b)>0 then
    v_state:='true';
  else
    v_state:='unknown';
    if jsonb_array_length(v_side_a)=0 then
      v_obligations:=v_obligations||jsonb_build_array(jsonb_build_object('kind','resolve_operating_place_presence','side','A','canonicalOperatingRootEntityId',v_root,'placeEntityIds',to_jsonb(p_side_a_place_entity_ids),'reason','no_established_operating_spatial_proof'));
    end if;
    if jsonb_array_length(v_side_b)=0 then
      v_obligations:=v_obligations||jsonb_build_array(jsonb_build_object('kind','resolve_operating_place_presence','side','B','canonicalOperatingRootEntityId',v_root,'placeEntityIds',to_jsonb(p_side_b_place_entity_ids),'reason','no_established_operating_spatial_proof'));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','reality_operating_place_pair_evaluation_v1',
    'inputEntityId',p_entity_id,
    'canonicalOperatingRootEntityId',v_root,
    'canonicalOperatingRootEntityKind',v_root_kind,
    'canonicalOperatingRootDisplayName',v_root_name,
    'rootResolutionProof',jsonb_build_object('depth',v_root_depth,'entityIds',to_jsonb(v_root_entities),'relationshipIds',to_jsonb(v_root_relationships),'relationshipKinds',to_jsonb(v_root_kinds)),
    'state',v_state,
    'sideA',jsonb_build_object('placeEntityIds',to_jsonb(p_side_a_place_entity_ids),'proofs',v_side_a),
    'sideB',jsonb_build_object('placeEntityIds',to_jsonb(p_side_b_place_entity_ids),'proofs',v_side_b),
    'obligations',v_obligations
  );
end
$function$;

create or replace function reality.operating_roots_spanning_place_sets_service_v1(
  p_side_a_place_entity_ids uuid[],
  p_side_b_place_entity_ids uuid[],
  p_max_operating_depth integer default 8,
  p_max_spatial_depth integer default 8,
  p_as_of timestamptz default now(),
  p_limit integer default 200
) returns table(
  root_entity_id uuid,
  root_entity_kind text,
  root_display_name text,
  side_a_proofs jsonb,
  side_b_proofs jsonb
)
language plpgsql stable security definer set search_path to ''
as $function$
begin
  if p_limit<1 or p_limit>1000 then raise exception 'Limit must be between 1 and 1000.' using errcode='22023'; end if;
  if p_side_a_place_entity_ids is null or cardinality(p_side_a_place_entity_ids)=0 or p_side_b_place_entity_ids is null or cardinality(p_side_b_place_entity_ids)=0 then raise exception 'Both Place sets are required.' using errcode='22023'; end if;
  if p_side_a_place_entity_ids && p_side_b_place_entity_ids then raise exception 'Paired Place sets must not share the same Place Entity id.' using errcode='22023'; end if;

  return query
  select e.id,e.entity_kind,e.display_name,
         q.eval->'sideA'->'proofs',q.eval->'sideB'->'proofs'
  from reality.entities e
  cross join lateral (
    select reality.evaluate_operating_place_pair_service_v1(e.id,p_side_a_place_entity_ids,p_side_b_place_entity_ids,p_max_operating_depth,p_max_spatial_depth,p_as_of) as eval
  ) q
  where e.identity_state='canonical'
    and e.entity_kind in ('business','organization','nonprofit')
    and (q.eval->>'canonicalOperatingRootEntityId')::uuid=e.id
    and q.eval->>'state'='true'
  order by e.display_name,e.id
  limit p_limit;
end
$function$;

revoke all on function reality.operating_root_place_set_presence_service_v1(uuid,uuid[],integer,integer,timestamptz) from public,anon,authenticated;
revoke all on function reality.evaluate_operating_place_pair_service_v1(uuid,uuid[],uuid[],integer,integer,timestamptz) from public,anon,authenticated;
revoke all on function reality.operating_roots_spanning_place_sets_service_v1(uuid[],uuid[],integer,integer,timestamptz,integer) from public,anon,authenticated;
grant execute on function reality.operating_root_place_set_presence_service_v1(uuid,uuid[],integer,integer,timestamptz) to service_role;
grant execute on function reality.evaluate_operating_place_pair_service_v1(uuid,uuid[],uuid[],integer,integer,timestamptz) to service_role;
grant execute on function reality.operating_roots_spanning_place_sets_service_v1(uuid[],uuid[],integer,integer,timestamptz,integer) to service_role;
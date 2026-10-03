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

revoke all on function reality.evaluate_operating_place_pair_service_v1(uuid,uuid[],uuid[],integer,integer,timestamptz) from public,anon,authenticated;
grant execute on function reality.evaluate_operating_place_pair_service_v1(uuid,uuid[],uuid[],integer,integer,timestamptz) to service_role;
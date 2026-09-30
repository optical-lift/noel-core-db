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

revoke all on function reality.operating_roots_spanning_place_sets_service_v1(uuid[],uuid[],integer,integer,timestamptz,integer) from public,anon,authenticated;
grant execute on function reality.operating_roots_spanning_place_sets_service_v1(uuid[],uuid[],integer,integer,timestamptz,integer) to service_role;
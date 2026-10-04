
create or replace function intelligence.enumerate_reality_motif_candidates_v1(
  p_occurrence_id bigint,
  p_min_edges integer default 2,
  p_max_edges integer default 5
)
returns table (
  instance_key text,
  edge_count integer,
  node_count integer,
  edge_keys text[],
  node_keys text[],
  canonical_signature text,
  role_signature text,
  coordinate_groups text[],
  witness_keys text[],
  structure jsonb
)
language sql
security invoker
stable
set search_path=''
as $$
with recursive
edges as (
  select *
  from intelligence.v_reality_alignment_graph_edges_v1
  where occurrence_id=p_occurrence_id
),
subgraphs(edge_keys,node_keys,edge_count) as (
  select
    array[e.edge_key]::text[],
    array(
      select distinct x
      from unnest(array[e.source_node_key,e.target_node_key]::text[]) x
      order by x
    )::text[],
    1
  from edges e

  union

  select
    array(
      select distinct x
      from unnest(s.edge_keys || e.edge_key) x
      order by x
    )::text[],
    array(
      select distinct x
      from unnest(s.node_keys || array[e.source_node_key,e.target_node_key]::text[]) x
      order by x
    )::text[],
    s.edge_count+1
  from subgraphs s
  join edges e
    on not (e.edge_key=any(s.edge_keys))
   and (
     e.source_node_key=any(s.node_keys)
     or e.target_node_key=any(s.node_keys)
   )
  where s.edge_count < least(greatest(p_max_edges,2),5)
),
uniq as (
  select distinct edge_keys,node_keys,edge_count
  from subgraphs
  where edge_count between greatest(p_min_edges,2) and least(greatest(p_max_edges,2),5)
),
eligible as (
  select u.*
  from uniq u
  where exists (
    select 1
    from edges e
    where e.edge_key=any(u.edge_keys)
      and (e.source_node_class='coordinate' or e.target_node_class='coordinate')
  )
  and exists (
    select 1
    from edges e
    where e.edge_key=any(u.edge_keys)
      and (e.source_node_class='witness_object' or e.target_node_class='witness_object')
  )
),
expanded_edges as (
  select
    array_to_string(u.edge_keys,',') candidate_key,
    u.edge_keys,
    u.node_keys,
    u.edge_count candidate_edge_count,
    e.*
  from eligible u
  join edges e on e.edge_key=any(u.edge_keys)
),
node_incidents as (
  select
    candidate_key,
    source_node_key node_key,
    source_node_class node_class,
    source_structural_type structural_type,
    count(*)::integer degree
  from expanded_edges
  group by candidate_key,source_node_key,source_node_class,source_structural_type

  union all

  select
    candidate_key,
    target_node_key,
    target_node_class,
    target_structural_type,
    count(*)::integer
  from expanded_edges
  group by candidate_key,target_node_key,target_node_class,target_structural_type
),
nodes as (
  select
    candidate_key,
    node_key,
    max(node_class) node_class,
    max(structural_type) structural_type,
    sum(degree)::integer degree,
    max(structural_type)||':d'||sum(degree)::text node_descriptor
  from node_incidents
  group by candidate_key,node_key
),
edge_descriptors as (
  select
    e.candidate_key,
    e.edge_key,
    e.edge_structural_type,
    least(ns.node_descriptor,nt.node_descriptor)
      ||'--'||e.edge_structural_type||'--'||
    greatest(ns.node_descriptor,nt.node_descriptor) edge_descriptor,
    case
      when e.edge_class='reality_touch'
        then 'touch:'||coalesce(e.dimension_key,'unknown')||':'||
             case when e.member_role like 'feature:%' then 'feature'
                  else coalesce(e.member_role,'member') end
      else 'touch:witness_object'
    end role_edge_descriptor
  from expanded_edges e
  join nodes ns
    on ns.candidate_key=e.candidate_key and ns.node_key=e.source_node_key
  join nodes nt
    on nt.candidate_key=e.candidate_key and nt.node_key=e.target_node_key
),
agg as (
  select
    e.candidate_key,
    min(e.occurrence_key) occurrence_key,
    min(e.independence_key) independence_key,
    string_to_array(e.candidate_key,',') edge_keys,
    array_agg(distinct n.node_key order by n.node_key) node_keys,
    count(distinct e.edge_key)::integer edge_count,
    count(distinct n.node_key)::integer node_count,
    array_agg(distinct e.coordinate_group_key order by e.coordinate_group_key)
      filter(where e.coordinate_group_key is not null) coordinate_groups,
    array_agg(distinct e.witness_key order by e.witness_key)
      filter(where e.witness_key is not null) witness_keys,
    string_agg(distinct n.node_descriptor,'|' order by n.node_descriptor) node_signature,
    string_agg(distinct ed.edge_descriptor,'|' order by ed.edge_descriptor) edge_signature,
    string_agg(distinct ed.role_edge_descriptor,'|' order by ed.role_edge_descriptor) role_edge_signature,
    jsonb_build_object(
      'nodes',(
        select jsonb_agg(
          jsonb_build_object(
            'class',n2.node_class,
            'type',n2.structural_type,
            'degree',n2.degree
          )
          order by n2.node_descriptor,n2.node_key
        )
        from nodes n2
        where n2.candidate_key=e.candidate_key
      ),
      'edges',(
        select jsonb_agg(
          jsonb_build_object(
            'type',ed2.edge_structural_type,
            'descriptor',ed2.edge_descriptor
          )
          order by ed2.edge_descriptor,ed2.edge_key
        )
        from edge_descriptors ed2
        where ed2.candidate_key=e.candidate_key
      )
    ) structure
  from expanded_edges e
  join nodes n on n.candidate_key=e.candidate_key
  join edge_descriptors ed on ed.candidate_key=e.candidate_key
  group by e.candidate_key
)
select
  a.occurrence_key||'::motif-instance::'||md5(array_to_string(a.edge_keys,',')),
  a.edge_count,
  a.node_count,
  a.edge_keys,
  a.node_keys,
  'degree_typed_v1|e='||a.edge_count::text||
    '|n='||a.node_count::text||
    '|nodes=['||a.node_signature||']'||
    '|edges=['||a.edge_signature||']',
  'role_v1|e='||a.edge_count::text||
    '|roles=['||a.role_edge_signature||']',
  coalesce(a.coordinate_groups,array[]::text[]),
  coalesce(a.witness_keys,array[]::text[]),
  a.structure
from agg a
order by 2,6,1;
$$;

comment on function intelligence.enumerate_reality_motif_candidates_v1(bigint,integer,integer) is
'Enumerates connected 2-5 edge subgraphs that reach from Reality Coordinates to at least one witness object. Canonical signatures exclude coordinate values, witness identities, native labels, and source object IDs.';

revoke all on function intelligence.enumerate_reality_motif_candidates_v1(bigint,integer,integer)
  from public,anon,authenticated;
grant execute on function intelligence.enumerate_reality_motif_candidates_v1(bigint,integer,integer)
  to service_role;

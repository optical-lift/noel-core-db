
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
reality_edges as (
  select *
  from edges
  where edge_class='reality_touch'
),
witness_edges as (
  select *
  from edges
  where edge_class='witness_touch'
),
star_subsets(alignment_node,edge_keys,last_member_id,reality_edge_count) as (
  select
    r.target_node_key,
    array[r.edge_key]::text[],
    r.alignment_member_id,
    1
  from reality_edges r

  union all

  select
    s.alignment_node,
    array(
      select x
      from unnest(s.edge_keys || r.edge_key) x
      order by x
    )::text[],
    r.alignment_member_id,
    s.reality_edge_count+1
  from star_subsets s
  join reality_edges r
    on r.target_node_key=s.alignment_node
   and r.alignment_member_id>s.last_member_id
  where s.reality_edge_count<4
),
star_candidates as (
  select distinct
    array(
      select x
      from unnest(s.edge_keys || w.edge_key) x
      order by x
    )::text[] edge_keys,
    'witness_star'::text template_kind
  from star_subsets s
  join witness_edges w on w.source_node_key=s.alignment_node
  where s.reality_edge_count+1 between greatest(p_min_edges,2) and least(greatest(p_max_edges,2),5)
),
convergence_base as (
  select
    r1.source_node_key central_coordinate_node,
    r1.edge_key r1_edge,
    r2.edge_key r2_edge,
    r1.target_node_key a1_node,
    r2.target_node_key a2_node,
    w1.edge_key w1_edge,
    w2.edge_key w2_edge
  from reality_edges r1
  join reality_edges r2
    on r2.source_node_key=r1.source_node_key
   and r2.target_node_key>r1.target_node_key
  join witness_edges w1 on w1.source_node_key=r1.target_node_key
  join witness_edges w2 on w2.source_node_key=r2.target_node_key
),
convergence_candidates as (
  select distinct
    array(
      select x
      from unnest(array[c.r1_edge,c.w1_edge,c.r2_edge,c.w2_edge]::text[]) x
      order by x
    )::text[] edge_keys,
    'coordinate_convergence'::text template_kind
  from convergence_base c
  where 4 between greatest(p_min_edges,2) and least(greatest(p_max_edges,2),5)
),
extended_convergence_candidates as (
  select distinct
    array(
      select x
      from unnest(array[c.r1_edge,c.w1_edge,c.r2_edge,c.w2_edge,r3.edge_key]::text[]) x
      order by x
    )::text[] edge_keys,
    'coordinate_convergence_extension'::text template_kind
  from convergence_base c
  join reality_edges r3
    on r3.target_node_key in (c.a1_node,c.a2_node)
   and r3.source_node_key<>c.central_coordinate_node
   and r3.edge_key not in (c.r1_edge,c.r2_edge)
  where 5 between greatest(p_min_edges,2) and least(greatest(p_max_edges,2),5)
),
candidate_sets as (
  select * from star_candidates
  union
  select * from convergence_candidates
  union
  select * from extended_convergence_candidates
),
expanded_edges as (
  select
    md5(array_to_string(c.edge_keys,',')) candidate_key,
    c.edge_keys,
    c.template_kind,
    e.*
  from candidate_sets c
  join edges e on e.edge_key=any(c.edge_keys)
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
    min(e.template_kind) template_kind,
    string_to_array(min(array_to_string(e.edge_keys,',')),',') edge_keys,
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
      'templateKind',min(e.template_kind),
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
  a.occurrence_key||'::motif-instance::'||a.candidate_key,
  a.edge_count,
  a.node_count,
  a.edge_keys,
  a.node_keys,
  'bounded_typed_v1|e='||a.edge_count::text||
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
'Bounded connected 2-5 edge motif enumerator. Exhaustively emits witness-centered stars, pairwise witness convergence at one Reality Coordinate, and 5-edge convergence extensions. Canonical signatures exclude coordinate values, witness identities, native labels, and source object IDs.';

revoke all on function intelligence.enumerate_reality_motif_candidates_v1(bigint,integer,integer)
  from public,anon,authenticated;
grant execute on function intelligence.enumerate_reality_motif_candidates_v1(bigint,integer,integer)
  to service_role;

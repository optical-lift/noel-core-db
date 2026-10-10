
create or replace function draft.get_noel_reality_composition_gaps_v1(
 p_lookup text,
 p_limit integer default 8
) returns jsonb
language sql stable security invoker
set search_path = ''
as $function$
with requested as (
 select case when upper(btrim(p_lookup)) ~ '^H0*[0-9]+$'
 then 'H'||lpad((substring(upper(btrim(p_lookup)) from 2)::integer)::text,4,'0')
 else btrim(p_lookup) end lookup_key
),
root as (
 select n.node_id,n.display_name,a.alias_value strong_key
 from draft.noel_reality_nodes n
 join draft.noel_reality_aliases a on a.node_id=n.node_id and a.alias_kind='strongs' and a.alias_value like 'H%'
 cross join requested p
 where n.is_active and n.node_kind='lexical_pool'
 and (n.node_id=p.lookup_key or a.alias_value=p.lookup_key)
 limit 1
),
composed_source_positions as (
 select c.composition_key,c.canonical_ref,t.book,t.chapter,t.verse,t.position root_position,t.source_token_id root_token,
 c.composition_statement
 from root r
 join draft.noel_reality_verse_compositions c on c.witness_key='mt_noel_current'
 cross join lateral jsonb_array_elements(c.token_roles) tr(role)
 join draft.ot_canonical_tokens_stage t on t.source_token_id=tr.role->>'source_token_id'
 where tr.role->>'node_id'=r.node_id
),
neighbors as (
 select n.node_id candidate_node_id,n.display_name candidate_name,n.original_definition,a.alias_value candidate_strong,
 p.composition_key,p.canonical_ref,p.composition_statement,
 t.source_token_id companion_token,t.hebrew_surface companion_surface,t.morph,
 p.root_token,abs(t.position-p.root_position) token_distance,
 row_number() over(partition by n.node_id,p.composition_key order by abs(t.position-p.root_position),t.source_token_id) within_composition_rank
 from composed_source_positions p
 join draft.ot_canonical_tokens_stage t on t.book=p.book and t.chapter=p.chapter and t.verse=p.verse
 and t.position between p.root_position-4 and p.root_position+4 and t.position<>p.root_position
 and t.strong_id like 'H%'
 join draft.noel_reality_aliases a on a.alias_kind='strongs'
 and a.alias_value='H'||lpad((substring(t.strong_id from 2)::integer)::text,4,'0')
 join draft.noel_reality_nodes n on n.node_id=a.node_id and n.is_active and n.node_kind='lexical_pool'
 join root r on r.node_id<>n.node_id
 where not (
 exists(select 1 from draft.noel_reality_token_anchors x where x.node_id=n.node_id)
 and exists(select 1 from draft.noel_reality_decisions d where d.subject_kind='node' and d.subject_id=n.node_id)
 and exists(select 1 from draft.noel_reality_edges e where e.is_active and e.from_node_id=n.node_id)
 )
),
summary as (
 select candidate_node_id,candidate_name,original_definition,candidate_strong,
 count(*)::integer composition_passages,
 min(token_distance)::integer minimum_distance,
 count(*) filter(where morph like 'HN%')::integer noun_passages,
 jsonb_agg(jsonb_build_object(
  'composition_key',composition_key,'canonical_ref',canonical_ref,
  'root_token_id',root_token,'companion_token_id',companion_token,
  'companion_surface',companion_surface,'companion_morphology',morph,
  'distance',token_distance)
  order by token_distance,composition_key) as evidence
 from neighbors where within_composition_rank=1
 group by candidate_node_id,candidate_name,original_definition,candidate_strong
),
ordered as (
 select s.*,
 case when exists(select 1 from draft.noel_reality_token_anchors a where a.node_id=s.candidate_node_id)
 or exists(select 1 from draft.noel_reality_decisions d where d.subject_id=s.candidate_node_id and d.subject_kind='node')
 or exists(select 1 from draft.noel_reality_edges e where e.from_node_id=s.candidate_node_id and e.is_active)
 then 'partially_recovered' else 'unexamined_in_reality_pools' end recovery_status
 from summary s
)
select jsonb_build_object(
 'lookup',p_lookup,
 'composition_gap_count',(select count(*) from ordered),
 'witness_scope','MT canonical verse compositions already written by Noel recovery; nearby founder lexical tokens within four positions of a recorded composition role',
 'candidates',coalesce((
 select jsonb_agg(jsonb_build_object(
  'node_id',candidate_node_id,'strong_id',candidate_strong,'name',candidate_name,
  'founder_definition',original_definition,'recovery_status',recovery_status,
  'composition_passages',composition_passages,'minimum_distance',minimum_distance,
  'noun_passages',noun_passages,'source_evidence',evidence
 ) order by composition_passages desc,noun_passages desc,minimum_distance,candidate_strong)
 from (select * from ordered order by composition_passages desc,noun_passages desc,minimum_distance,candidate_strong
 limit least(greatest(coalesce(p_limit,8),1),50)) first_candidates),'[]'::jsonb),
 'guardrail','A lexical gap adjacent to a human-reviewed verse composition is a strong study prompt but not a composition role until explicitly evidenced and recorded.'
);
$function$;
revoke all on function draft.get_noel_reality_composition_gaps_v1(text,integer) from public,anon,authenticated;
grant execute on function draft.get_noel_reality_composition_gaps_v1(text,integer) to service_role;


create or replace function draft.get_noel_reality_ecosystem_bridges_v1(
  p_lookup text,
  p_limit integer default 8
) returns jsonb
language sql stable security invoker
set search_path = ''
as $bridge$
with
requested as (
  select case when upper(btrim(p_lookup)) ~ '^H0*[0-9]+$'
    then 'H'||lpad((substring(upper(btrim(p_lookup)) from 2)::integer)::text,4,'0')
    else btrim(p_lookup) end lookup_key
),
root as (
  select n.node_id,n.display_name,a.alias_value strong_key,
    'H'||(substring(a.alias_value from 2)::integer)::text corpus_strong
  from draft.noel_reality_nodes n
  join draft.noel_reality_aliases a on a.node_id=n.node_id and a.alias_kind='strongs' and a.alias_value like 'H%'
  cross join requested p
  where n.is_active and n.node_kind='lexical_pool'
    and (n.node_id=p.lookup_key or a.alias_value=p.lookup_key)
  limit 1
),
recovered as (
  select n.node_id,a.alias_value,
    'H'||(substring(a.alias_value from 2)::integer)::text corpus_strong
  from draft.noel_reality_nodes n
  join draft.noel_reality_aliases a on a.node_id=n.node_id and a.alias_kind='strongs' and a.alias_value like 'H%'
  where n.is_active and n.node_kind='lexical_pool'
    and exists(select 1 from draft.noel_reality_decisions d where d.subject_kind='node' and d.subject_id=n.node_id)
    and exists(select 1 from draft.noel_reality_token_anchors x where x.node_id=n.node_id)
    and exists(select 1 from draft.noel_reality_edges e where e.from_node_id=n.node_id and e.is_active)
),
root_tokens as (
  select r.node_id,t.book,t.chapter,t.verse,t.position,t.source_token_id,
    exists(select 1 from draft.noel_reality_token_anchors a
      where a.node_id=r.node_id and a.witness_key='mt_noel_current'
      and a.source_token_id=t.source_token_id) curated
  from root r join draft.ot_canonical_tokens_stage t on t.strong_id=r.corpus_strong
),
candidate_tokens as (
  select distinct on (t.source_token_id)
     n.node_id candidate_node_id,n.display_name candidate_name,
     n.original_definition,a.alias_value candidate_strong,
     t.strong_id candidate_corpus_strong,t.source_token_id candidate_token,t.hebrew_surface candidate_surface,
     t.book,t.chapter,t.verse,t.position candidate_position,
     root_t.source_token_id root_token,
     abs(t.position-root_t.position) root_distance,root_t.curated
  from root_tokens root_t
  join draft.ot_canonical_tokens_stage t
    on t.book=root_t.book and t.chapter=root_t.chapter and t.verse=root_t.verse
    and t.position between root_t.position-4 and root_t.position+4
    and t.position<>root_t.position and t.strong_id like 'H%'
  join draft.noel_reality_aliases a
    on a.alias_kind='strongs'
    and a.alias_value='H'||lpad((substring(t.strong_id from 2)::integer)::text,4,'0')
    and a.node_id<>root_t.node_id
  join draft.noel_reality_nodes n
    on n.node_id=a.node_id and n.is_active and n.node_kind='lexical_pool'
  where not (
    exists(select 1 from draft.noel_reality_decisions d where d.subject_kind='node' and d.subject_id=n.node_id)
    and exists(select 1 from draft.noel_reality_token_anchors x where x.node_id=n.node_id)
    and exists(select 1 from draft.noel_reality_edges e where e.from_node_id=n.node_id and e.is_active)
  )
  order by t.source_token_id,root_t.curated desc,abs(t.position-root_t.position),root_t.source_token_id
),
bridge_passages as (
  select c.candidate_node_id,c.candidate_name,c.original_definition,c.candidate_strong,c.candidate_corpus_strong,
     c.candidate_token,c.candidate_surface,c.book,c.chapter,c.verse,c.root_token,c.root_distance,c.curated,
     count(distinct k.node_id)::integer established_pools,
     array_agg(distinct k.node_id order by k.node_id) established_pool_ids
  from candidate_tokens c
  join draft.ot_canonical_tokens_stage t
    on t.book=c.book and t.chapter=c.chapter and t.verse=c.verse
    and t.position between c.candidate_position-4 and c.candidate_position+4
  join recovered k on k.corpus_strong=t.strong_id and k.node_id<>c.candidate_node_id
  group by c.candidate_node_id,c.candidate_name,c.original_definition,c.candidate_strong,c.candidate_corpus_strong,
     c.candidate_token,c.candidate_surface,c.book,c.chapter,c.verse,c.root_token,c.root_distance,c.curated
  having count(distinct k.node_id)>=2
),
sampled as (
  select b.*,
    row_number() over(partition by candidate_node_id order by curated desc, established_pools desc,root_distance,book,chapter,verse,candidate_token) evidence_rank
  from bridge_passages b
),
stats as (
  select candidate_node_id,candidate_name,original_definition,candidate_strong,candidate_corpus_strong,
    count(distinct (book,chapter,verse))::integer bridge_verses,
    count(distinct (book,chapter,verse)) filter(where curated)::integer curated_bridge_verses,
    max(established_pools) strongest_cluster,
    min(root_distance) shortest_root_distance,
    jsonb_agg(jsonb_build_object(
      'reference',book||' '||chapter||':'||verse,
      'candidate_token_id',candidate_token,'candidate_surface',candidate_surface,
      'root_token_id',root_token,'root_distance',root_distance,
      'root_is_curated_anchor',curated,'established_pool_ids',to_jsonb(established_pool_ids)
    ) order by curated desc,established_pools desc,root_distance,book,chapter,verse)
     filter(where evidence_rank<=3) evidence_examples
  from sampled
  group by candidate_node_id,candidate_name,original_definition,candidate_strong,candidate_corpus_strong
),
scored as (
  select s.*,
    (select count(*) from draft.ot_canonical_tokens_stage t where t.strong_id=s.candidate_corpus_strong)::integer total_corpus_tokens,
    case when exists(select 1 from draft.noel_reality_token_anchors a where a.node_id=s.candidate_node_id)
      or exists(select 1 from draft.noel_reality_decisions d where d.subject_id=s.candidate_node_id and d.subject_kind='node')
      or exists(select 1 from draft.noel_reality_edges e where e.from_node_id=s.candidate_node_id and e.is_active)
      then 'partially_recovered' else 'unexamined_in_reality_pools' end recovery_status
  from stats s
),
ranked as (
  select *,round(
     bridge_verses::numeric*strongest_cluster::numeric*(1+curated_bridge_verses)::numeric /
     sqrt(greatest(total_corpus_tokens,1)::numeric),3) as attention_score
  from scored
)
select jsonb_build_object(
  'lookup',p_lookup,
  'source_pool',(select coalesce(jsonb_build_object('node_id',node_id,'name',display_name,'strong_id',strong_key),'null'::jsonb) from root),
  'method','Multi-pool convergence: target occurs within four Hebrew-token positions of requested pool and at least two already-recovered founder pools occur within four positions of target in the same MT verse.',
  'bridge_candidate_count',(select count(*) from ranked),
  'candidates',coalesce((
   select jsonb_agg(jsonb_build_object(
     'node_id',candidate_node_id,'strong_id',candidate_strong,'name',candidate_name,
     'founder_definition',original_definition,'recovery_status',recovery_status,
     'score',attention_score,'bridge_verses',bridge_verses,
     'curated_bridge_verses',curated_bridge_verses,
     'max_recovered_pool_cluster',strongest_cluster,
     'total_corpus_tokens',total_corpus_tokens,
     'evidence',evidence_examples
   ) order by attention_score desc,curated_bridge_verses desc,bridge_verses desc,candidate_strong)
   from (select * from ranked order by attention_score desc,curated_bridge_verses desc,bridge_verses desc,candidate_strong
         limit least(greatest(coalesce(p_limit,8),1),30)) top),'[]'::jsonb),
  'guardrail','Repeated proximity and multi-pool convergence are research prompts, never automatic definition, function edge, steward ratification or realm inheritance. Counts cover MT Hebrew only.'
);
$bridge$;
revoke all on function draft.get_noel_reality_ecosystem_bridges_v1(text,integer) from public,anon,authenticated;
grant execute on function draft.get_noel_reality_ecosystem_bridges_v1(text,integer) to service_role;

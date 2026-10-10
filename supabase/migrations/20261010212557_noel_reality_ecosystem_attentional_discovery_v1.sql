
create or replace function draft.get_noel_reality_ecosystem_v1(
  p_lookup text,
  p_limit integer default 12
) returns jsonb
language sql stable security invoker
set search_path = ''
as $body$
with
requested as (
  select case when upper(btrim(p_lookup)) ~ '^H0*[0-9]+$'
    then 'H'||lpad((substring(upper(btrim(p_lookup)) from 2)::integer)::text,4,'0')
    else btrim(p_lookup) end as lookup_key
),
root as (
  select n.node_id,n.display_name,a.alias_value as strong_key,
    'H'||(substring(a.alias_value from 2)::integer)::text as corpus_strong
  from draft.noel_reality_nodes n
  join draft.noel_reality_aliases a on a.node_id=n.node_id and a.alias_kind='strongs' and a.alias_value like 'H%'
  cross join requested p
  where n.is_active and n.node_kind='lexical_pool'
    and (n.node_id=p.lookup_key or a.alias_value=p.lookup_key)
  limit 1
),
source_occurrences as (
  select r.node_id,t.book,t.chapter,t.verse,t.position,t.source_token_id,
    exists(select 1 from draft.noel_reality_token_anchors aa
      where aa.node_id=r.node_id and aa.witness_key='mt_noel_current'
      and aa.source_token_id=t.source_token_id) as curated
  from root r
  join draft.ot_canonical_tokens_stage t on t.strong_id=r.corpus_strong
),
nearby as (
  select a.node_id as related_node_id,a.alias_value as related_strong,
    n.display_name as related_name,n.original_definition,
    o.book,o.chapter,o.verse,o.source_token_id as root_token,
    t.source_token_id as related_token,t.hebrew_surface as related_surface,
    abs(t.position-o.position) as token_distance,o.curated
  from source_occurrences o
  join draft.ot_canonical_tokens_stage t
    on t.book=o.book and t.chapter=o.chapter and t.verse=o.verse
    and t.position between o.position-4 and o.position+4
    and t.position<>o.position and t.strong_id like 'H%'
  join draft.noel_reality_aliases a
    on a.alias_kind='strongs'
    and a.alias_value='H'||lpad((substring(t.strong_id from 2)::integer)::text,4,'0')
    and a.node_id<>o.node_id
  join draft.noel_reality_nodes n on n.node_id=a.node_id and n.is_active and n.node_kind='lexical_pool'
),
evidence_order as (
  select nearby.*,
    row_number() over (
      partition by related_node_id
      order by curated desc,token_distance,book,chapter,verse,root_token,related_token
    ) as evidence_rank
  from nearby
),
summary as (
  select related_node_id,related_strong,related_name,original_definition,
    count(distinct (book,chapter,verse)) as shared_verses,
    count(distinct (book,chapter,verse)) filter(where curated) as curated_verses,
    min(token_distance) as closest_distance,
    coalesce(jsonb_agg(jsonb_build_object(
      'reference',book||' '||chapter||':'||verse,
      'root_token_id',root_token,
      'companion_token_id',related_token,
      'companion_surface',related_surface,
      'distance',token_distance,
      'root_anchor_in_verse',curated
    ) order by curated desc,token_distance,book,chapter,verse)
      filter(where evidence_rank<=3),'[]'::jsonb) as example_witnesses
  from evidence_order
  group by related_node_id,related_strong,related_name,original_definition
),
status as (
  select s.*,
    case when exists (select 1 from draft.noel_reality_token_anchors a where a.node_id=s.related_node_id)
          and exists (select 1 from draft.noel_reality_decisions d where d.subject_kind='node' and d.subject_id=s.related_node_id)
          and exists (select 1 from draft.noel_reality_edges e where e.from_node_id=s.related_node_id and e.is_active)
         then 'recovered_with_evidence'
         when exists (select 1 from draft.noel_reality_token_anchors a where a.node_id=s.related_node_id)
          or exists (select 1 from draft.noel_reality_decisions d where d.subject_kind='node' and d.subject_id=s.related_node_id)
          or exists (select 1 from draft.noel_reality_edges e where e.from_node_id=s.related_node_id and e.is_active)
          or n.metadata ? 'recovery_batch'
         then 'partially_recovered'
         else 'unexamined_in_reality_pools' end as recovery_status
  from summary s join draft.noel_reality_nodes n on n.node_id=s.related_node_id
),
attention as (
  select * from status
  where recovery_status <> 'recovered_with_evidence'
    and (curated_verses>0 or shared_verses>=2)
),
top_attention as (
  select * from attention
  order by curated_verses desc,shared_verses desc,closest_distance,related_strong
  limit least(greatest(coalesce(p_limit,12),1),50)
)
select jsonb_build_object(
  'lookup',p_lookup,
  'resolved_pool',(select coalesce(jsonb_build_object('node_id',node_id,'name',display_name,'strong_id',strong_key),'null'::jsonb) from root),
  'witness_scope','MT Hebrew: lexical same-verse proximity within four token positions; curated root anchors marked separately',
  'candidate_count',(select count(*) from attention),
  'not_yet_recovered_count',(select count(*) from attention where recovery_status='unexamined_in_reality_pools'),
  'partial_count',(select count(*) from attention where recovery_status='partially_recovered'),
  'candidates',coalesce((
    select jsonb_agg(jsonb_build_object(
      'node_id',related_node_id,'strong_id',related_strong,'name',related_name,
      'founder_definition',original_definition,'recovery_status',recovery_status,
      'curated_passages',curated_verses,'shared_passages',shared_verses,
      'nearest_token_distance',closest_distance,
      'evidence_examples',example_witnesses
    ) order by curated_verses desc,shared_verses desc,closest_distance,related_strong)
    from top_attention),'[]'::jsonb),
  'guardrail','This is an attention queue, not a claim of semantic identity, authorized relation, agreed definition, or reality-category inheritance. Unexamined means unexamined in these Reality Pool recovery records, not absent from all Noel research. No graph edges or definition changes are created.'
);
$body$;
revoke all on function draft.get_noel_reality_ecosystem_v1(text,integer) from public,anon,authenticated;
grant execute on function draft.get_noel_reality_ecosystem_v1(text,integer) to service_role;

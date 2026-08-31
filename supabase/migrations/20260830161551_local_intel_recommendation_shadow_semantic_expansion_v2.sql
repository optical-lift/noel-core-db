alter table local_intel.recommendation_shadow_candidate_adjudications
  alter column live_position drop not null;

alter table local_intel.recommendation_shadow_candidate_adjudications
  add column if not exists discovery_position integer,
  add column if not exists baseline_live_position integer,
  add column if not exists retrieval_terms text[] not null default '{}'::text[],
  add column if not exists retrieval_term_ranks jsonb not null default '{}'::jsonb,
  add column if not exists candidate_origin text not null default 'baseline'
    check (candidate_origin in ('baseline','semantic_expansion','both'));

create index if not exists recommendation_shadow_candidate_discovery_idx
  on local_intel.recommendation_shadow_candidate_adjudications (run_id, discovery_position);

create or replace function local_intel.start_recommendation_shadow_run_v2(
  p_organization_id uuid,
  p_lens_stable_key text,
  p_query text,
  p_query_state jsonb default '{}'::jsonb,
  p_retrieval_expansions text[] default '{}'::text[],
  p_object_types text[] default array['entity','offering','occurrence']::text[],
  p_city text default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_per_term_limit integer default 15,
  p_candidate_limit integer default 60
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, local_intel
as $$
declare
  v_lens_id uuid;
  v_run_id uuid;
  v_live_snapshot jsonb;
  v_terms text[];
begin
  select l.id into v_lens_id
  from local_intel.recommendation_lenses l
  where l.organization_id=p_organization_id
    and l.stable_key=p_lens_stable_key
    and l.mode in ('shadow','active')
    and l.status in ('working','approved')
  order by l.source_version desc
  limit 1;

  if v_lens_id is null then
    raise exception 'No usable recommendation lens % for organization %', p_lens_stable_key, p_organization_id;
  end if;

  select array_agg(term order by ord)
  into v_terms
  from (
    select distinct on (lower(btrim(term))) btrim(term) as term, ord
    from unnest(array_prepend(p_query,coalesce(p_retrieval_expansions,'{}'::text[]))) with ordinality u(term,ord)
    where nullif(btrim(term),'') is not null
    order by lower(btrim(term)),ord
  ) d;

  insert into local_intel.recommendation_shadow_runs(
    lens_id,query_text,query_state,retrieval_function,retrieval_parameters,active_operator_snapshot,status
  )
  select
    v_lens_id,p_query,coalesce(p_query_state,'{}'::jsonb),
    'local_intel.start_recommendation_shadow_run_v2',
    jsonb_build_object(
      'baseline_query',p_query,
      'semantic_expansions',coalesce(p_retrieval_expansions,'{}'::text[]),
      'object_types',p_object_types,
      'city',p_city,
      'start_at',p_start_at,
      'end_at',p_end_at,
      'per_term_limit',p_per_term_limit,
      'candidate_limit',p_candidate_limit
    ),
    coalesce((select jsonb_agg(jsonb_build_object(
      'operator_key',b.operator_key,
      'source_system',b.source_system,
      'source_ref',b.source_ref,
      'source_version',b.source_version,
      'authority_state',b.authority_state,
      'activation_rule',b.activation_rule,
      'prohibited_shortcuts',b.prohibited_shortcuts
    ) order by b.operator_key)
    from local_intel.recommendation_lens_operator_bindings b
    where b.lens_id=v_lens_id and b.status in ('working','approved')),'[]'::jsonb),
    'retrieved'
  returning id into v_run_id;

  with terms as (
    select term, ord, lower(term)=lower(p_query) as is_baseline
    from unnest(v_terms) with ordinality u(term,ord)
  ), raw as (
    select
      t.term,t.ord,t.is_baseline,
      row_number() over (partition by t.term order by s.rank desc,s.title,s.object_id)::integer as term_position,
      s.*
    from terms t
    cross join lateral local_intel.search_local_answers_v2(
      t.term,p_object_types,p_city,p_start_at,p_end_at,p_per_term_limit
    ) s
  ), agg as (
    select
      object_type,object_id,
      min(term_position) filter (where is_baseline) as baseline_position,
      max(rank) filter (where is_baseline) as baseline_rank,
      array_agg(distinct term order by term) as retrieval_terms,
      jsonb_object_agg(term,rank) as retrieval_term_ranks,
      bool_or(is_baseline) as has_baseline,
      bool_or(not is_baseline) as has_expansion
    from raw
    group by object_type,object_id
  ), chosen as (
    select distinct on (object_type,object_id)
      object_type,object_id,stable_key,entity_id,entity_name,title,description,category,audience,price,schedule,location,
      current_status,starts_at,ends_at,public_url,website_url,phone,email,last_verified_at,availability_freshness,
      current_availability,latest_current_observation_at,next_current_expiry_at,last_availability_expired_at,rank
    from raw
    order by object_type,object_id,is_baseline desc,rank desc,term
  ), candidates as (
    select
      a.*,c.*,
      row_number() over (
        order by a.baseline_position nulls last,
                 case when a.has_baseline then 0 else 1 end,
                 c.rank desc,
                 c.stable_key
      )::integer as discovery_position,
      case when a.has_baseline and a.has_expansion then 'both'
           when a.has_baseline then 'baseline'
           else 'semantic_expansion' end as candidate_origin
    from agg a
    join chosen c using(object_type,object_id)
    order by discovery_position
    limit greatest(1,least(coalesce(p_candidate_limit,60),200))
  )
  insert into local_intel.recommendation_shadow_candidate_adjudications(
    run_id,object_type,object_id,stable_key,live_position,live_rank,discovery_position,baseline_live_position,
    retrieval_terms,retrieval_term_ranks,candidate_origin,candidate_snapshot,status
  )
  select
    v_run_id,c.object_type,c.object_id,c.stable_key,c.baseline_position,c.baseline_rank,c.discovery_position,c.baseline_position,
    c.retrieval_terms,c.retrieval_term_ranks,c.candidate_origin,
    jsonb_build_object(
      'entity_id',c.entity_id,'entity_name',c.entity_name,'title',c.title,'description',c.description,'category',c.category,
      'audience',c.audience,'price',c.price,'schedule',c.schedule,'location',c.location,'current_status',c.current_status,
      'starts_at',c.starts_at,'ends_at',c.ends_at,'public_url',c.public_url,'website_url',c.website_url,'phone',c.phone,
      'email',c.email,'last_verified_at',c.last_verified_at,'availability_freshness',c.availability_freshness,
      'current_availability',c.current_availability
    ),
    'retrieved'
  from candidates c;

  select coalesce(jsonb_agg(jsonb_build_object(
    'object_type',c.object_type,'object_id',c.object_id,'stable_key',c.stable_key,
    'baseline_live_position',c.baseline_live_position,'live_rank',c.live_rank,
    'candidate',c.candidate_snapshot
  ) order by c.baseline_live_position),'[]'::jsonb)
  into v_live_snapshot
  from local_intel.recommendation_shadow_candidate_adjudications c
  where c.run_id=v_run_id and c.baseline_live_position is not null;

  update local_intel.recommendation_shadow_runs r
  set retrieval_count=(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=v_run_id),
      live_result_snapshot=coalesce(v_live_snapshot,'[]'::jsonb),
      shadow_summary=jsonb_build_object(
        'retrieval_stage','semantic_expansion_complete',
        'baseline_count',(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=v_run_id and c.baseline_live_position is not null),
        'expanded_only_count',(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=v_run_id and c.candidate_origin='semantic_expansion'),
        'candidate_count',(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=v_run_id)
      ),
      updated_at=now()
  where r.id=v_run_id;

  return v_run_id;
end;
$$;

create or replace view local_intel.v_recommendation_shadow_compare_v2
with (security_invoker=true)
as
select
  r.id as run_id,
  l.organization_id,
  l.stable_key as lens_key,
  l.source_system as lens_source_system,
  l.source_ref as lens_source_ref,
  l.source_version as lens_source_version,
  r.query_text,r.query_state,r.status as run_status,r.shadow_summary,
  c.object_type,c.object_id,c.stable_key,
  c.baseline_live_position,c.live_rank,c.discovery_position,c.candidate_origin,c.retrieval_terms,c.retrieval_term_ranks,
  c.verdict,c.shadow_position_group,c.confidence,c.rationale,c.activated_dimensions,c.basis_operator_keys,
  c.missing_evidence,c.does_not_establish,c.candidate_snapshot,r.created_at as run_created_at
from local_intel.recommendation_shadow_runs r
join local_intel.recommendation_lenses l on l.id=r.lens_id
join local_intel.recommendation_shadow_candidate_adjudications c on c.run_id=r.id;
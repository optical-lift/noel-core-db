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

  select array_agg(d.term order by d.ord)
  into v_terms
  from (
    select distinct on (lower(btrim(u.term))) btrim(u.term) as term, u.ord
    from unnest(array_prepend(p_query,coalesce(p_retrieval_expansions,'{}'::text[]))) with ordinality u(term,ord)
    where nullif(btrim(u.term),'') is not null
    order by lower(btrim(u.term)),u.ord
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
    select u.term,u.ord,lower(u.term)=lower(p_query) as is_baseline
    from unnest(v_terms) with ordinality u(term,ord)
  ), raw as (
    select
      t.term,t.ord,t.is_baseline,
      row_number() over (partition by t.term order by s.rank desc,s.title,s.object_id)::integer as term_position,
      s.object_type,s.object_id,s.stable_key,s.entity_id,s.entity_name,s.title,s.description,s.category,
      s.audience,s.price,s.schedule,s.location,s.current_status,s.starts_at,s.ends_at,s.public_url,s.website_url,
      s.phone,s.email,s.last_verified_at,s.availability_freshness,s.current_availability,
      s.latest_current_observation_at,s.next_current_expiry_at,s.last_availability_expired_at,s.rank
    from terms t
    cross join lateral local_intel.search_local_answers_v2(
      t.term,p_object_types,p_city,p_start_at,p_end_at,p_per_term_limit
    ) s
  ), agg as (
    select
      r.object_type,r.object_id,
      min(r.term_position) filter (where r.is_baseline) as baseline_position,
      max(r.rank) filter (where r.is_baseline) as baseline_rank,
      array_agg(distinct r.term order by r.term) as retrieval_terms,
      jsonb_object_agg(r.term,r.rank) as retrieval_term_ranks,
      bool_or(r.is_baseline) as has_baseline,
      bool_or(not r.is_baseline) as has_expansion
    from raw r
    group by r.object_type,r.object_id
  ), chosen as (
    select distinct on (r.object_type,r.object_id)
      r.object_type,r.object_id,r.stable_key,r.entity_id,r.entity_name,r.title,r.description,r.category,r.audience,r.price,
      r.schedule,r.location,r.current_status,r.starts_at,r.ends_at,r.public_url,r.website_url,r.phone,r.email,
      r.last_verified_at,r.availability_freshness,r.current_availability,r.latest_current_observation_at,
      r.next_current_expiry_at,r.last_availability_expired_at,r.rank
    from raw r
    order by r.object_type,r.object_id,r.is_baseline desc,r.rank desc,r.term
  ), candidates_pre as (
    select
      a.object_type,a.object_id,a.baseline_position,a.baseline_rank,a.retrieval_terms,a.retrieval_term_ranks,a.has_baseline,a.has_expansion,
      c.stable_key,c.entity_id,c.entity_name,c.title,c.description,c.category,c.audience,c.price,c.schedule,c.location,
      c.current_status,c.starts_at,c.ends_at,c.public_url,c.website_url,c.phone,c.email,c.last_verified_at,
      c.availability_freshness,c.current_availability,c.rank as discovery_rank,
      case when a.has_baseline and a.has_expansion then 'both'
           when a.has_baseline then 'baseline'
           else 'semantic_expansion' end as candidate_origin
    from agg a
    join chosen c on c.object_type=a.object_type and c.object_id=a.object_id
  ), candidates as (
    select cp.*,
      row_number() over (
        order by cp.baseline_position nulls last,
                 case when cp.has_baseline then 0 else 1 end,
                 cp.discovery_rank desc,
                 cp.stable_key
      )::integer as discovery_position
    from candidates_pre cp
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
    'baseline_live_position',c.baseline_live_position,'live_rank',c.live_rank,'candidate',c.candidate_snapshot
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
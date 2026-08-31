alter table local_intel.recommendation_shadow_candidate_adjudications
  drop constraint if exists recommendation_shadow_candidate_adjudica_candidate_origin_check;

alter table local_intel.recommendation_shadow_candidate_adjudications
  add constraint recommendation_shadow_candidate_adjudica_candidate_origin_check
  check (candidate_origin = any (array['baseline'::text,'semantic_expansion'::text,'both'::text,'time_window'::text,'multi'::text]));

create or replace function local_intel.add_recommendation_shadow_time_window_candidates_v1(
  p_run_id uuid,
  p_city text,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_limit integer default 100
)
returns integer
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_base_position integer;
  v_changed integer;
begin
  if p_start_at is null or p_end_at is null then
    raise exception 'time-window candidate expansion requires both start and end';
  end if;

  if not exists (select 1 from local_intel.recommendation_shadow_runs r where r.id=p_run_id) then
    raise exception 'recommendation shadow run % not found',p_run_id;
  end if;

  select coalesce(max(c.discovery_position),0)
  into v_base_position
  from local_intel.recommendation_shadow_candidate_adjudications c
  where c.run_id=p_run_id;

  with window_candidates as (
    select
      row_number() over (order by v.starts_at nulls last,v.title,v.object_id)::integer as window_position,
      v.object_type,v.object_id,v.stable_key,v.entity_id,v.entity_name,v.title,v.description,v.category,
      v.audience,v.price,v.schedule,v.location,v.current_status,v.starts_at,v.ends_at,v.public_url,v.website_url,
      v.phone,v.email,v.last_verified_at,
      coalesce(av.availability_freshness,'unknown') as availability_freshness,
      coalesce(av.current_availability,'[]'::jsonb) as current_availability
    from local_intel.v_answer_inventory v
    left join local_intel.v_entity_availability_summary av on av.entity_id=v.entity_id
    where v.object_type='occurrence'
      and (p_city is null or lower(coalesce(v.location->>'city',''))=lower(p_city))
      and coalesce(v.ends_at,v.starts_at)>=p_start_at
      and v.starts_at<=p_end_at
    order by v.starts_at nulls last,v.title,v.object_id
    limit greatest(1,least(coalesce(p_limit,100),500))
  )
  insert into local_intel.recommendation_shadow_candidate_adjudications(
    run_id,object_type,object_id,stable_key,live_position,live_rank,discovery_position,baseline_live_position,
    retrieval_terms,retrieval_term_ranks,candidate_origin,candidate_snapshot,status,metadata
  )
  select
    p_run_id,w.object_type,w.object_id,w.stable_key,null,null,v_base_position+w.window_position,null,
    array['__time_window__']::text[],jsonb_build_object('__time_window__',w.window_position),'time_window',
    jsonb_build_object(
      'entity_id',w.entity_id,'entity_name',w.entity_name,'title',w.title,'description',w.description,'category',w.category,
      'audience',w.audience,'price',w.price,'schedule',w.schedule,'location',w.location,'current_status',w.current_status,
      'starts_at',w.starts_at,'ends_at',w.ends_at,'public_url',w.public_url,'website_url',w.website_url,'phone',w.phone,
      'email',w.email,'last_verified_at',w.last_verified_at,'availability_freshness',w.availability_freshness,
      'current_availability',w.current_availability
    ),
    'retrieved',jsonb_build_object('time_window_position',w.window_position)
  from window_candidates w
  on conflict (run_id,object_type,object_id) do update
    set retrieval_terms=(select array_agg(distinct x order by x) from unnest(local_intel.recommendation_shadow_candidate_adjudications.retrieval_terms || array['__time_window__']::text[]) x),
        retrieval_term_ranks=local_intel.recommendation_shadow_candidate_adjudications.retrieval_term_ranks || excluded.retrieval_term_ranks,
        candidate_origin=case when local_intel.recommendation_shadow_candidate_adjudications.candidate_origin='time_window' then 'time_window' else 'multi' end,
        metadata=local_intel.recommendation_shadow_candidate_adjudications.metadata || excluded.metadata,
        updated_at=now();

  get diagnostics v_changed = row_count;

  update local_intel.recommendation_shadow_runs r
  set retrieval_count=(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=p_run_id),
      shadow_summary=coalesce(r.shadow_summary,'{}'::jsonb) || jsonb_build_object(
        'time_window_inventory_added',true,
        'time_window_start',p_start_at,
        'time_window_end',p_end_at,
        'time_window_candidate_count',(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=p_run_id and '__time_window__'=any(c.retrieval_terms))
      ),
      updated_at=now()
  where r.id=p_run_id;

  return v_changed;
end;
$function$;
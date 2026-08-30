create table if not exists local_intel.recommendation_lenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  stable_key text not null,
  name text not null,
  description text,
  source_system text not null,
  source_ref text not null,
  source_version integer not null default 1,
  mode text not null default 'shadow' check (mode in ('shadow','active','retired')),
  status text not null default 'working' check (status in ('draft','working','approved','retired')),
  governance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, stable_key, source_version)
);

create table if not exists local_intel.recommendation_lens_operator_bindings (
  id uuid primary key default gen_random_uuid(),
  lens_id uuid not null references local_intel.recommendation_lenses(id) on delete cascade,
  operator_key text not null,
  source_system text not null,
  source_ref text not null,
  source_version integer not null default 1,
  authority_state text not null default 'provisional' check (authority_state in ('candidate','provisional','supported','retired')),
  activation_rule jsonb not null default '{}'::jsonb,
  prohibited_shortcuts text[] not null default '{}'::text[],
  status text not null default 'working' check (status in ('working','approved','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lens_id, operator_key, source_system, source_ref, source_version)
);

create table if not exists local_intel.recommendation_shadow_runs (
  id uuid primary key default gen_random_uuid(),
  lens_id uuid not null references local_intel.recommendation_lenses(id) on delete restrict,
  query_text text not null,
  query_state jsonb not null default '{}'::jsonb,
  retrieval_function text not null default 'local_intel.search_local_answers_v2',
  retrieval_parameters jsonb not null default '{}'::jsonb,
  retrieval_count integer not null default 0,
  live_result_snapshot jsonb not null default '[]'::jsonb,
  active_operator_snapshot jsonb not null default '[]'::jsonb,
  shadow_summary jsonb not null default '{}'::jsonb,
  status text not null default 'retrieved' check (status in ('retrieved','adjudicating','adjudicated','reviewed','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists local_intel.recommendation_shadow_candidate_adjudications (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references local_intel.recommendation_shadow_runs(id) on delete cascade,
  object_type text not null,
  object_id uuid not null,
  stable_key text not null,
  live_position integer not null,
  live_rank real,
  candidate_snapshot jsonb not null default '{}'::jsonb,
  activated_dimensions jsonb not null default '[]'::jsonb,
  basis_operator_keys text[] not null default '{}'::text[],
  evidence_snapshot jsonb not null default '{}'::jsonb,
  missing_evidence text[] not null default '{}'::text[],
  verdict text not null default 'unresolved' check (verdict in ('preferred','eligible','tied','lower_fit','ineligible','unresolved')),
  shadow_position_group integer,
  confidence text check (confidence is null or confidence in ('low','medium','high','very_high')),
  rationale text,
  does_not_establish text[] not null default '{}'::text[],
  status text not null default 'retrieved' check (status in ('retrieved','working','adjudicated','reviewed','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (run_id, object_type, object_id)
);

create index if not exists recommendation_lenses_org_mode_idx
  on local_intel.recommendation_lenses (organization_id, mode, status);
create index if not exists recommendation_lens_operator_bindings_lens_idx
  on local_intel.recommendation_lens_operator_bindings (lens_id, status);
create index if not exists recommendation_shadow_runs_lens_created_idx
  on local_intel.recommendation_shadow_runs (lens_id, created_at desc);
create index if not exists recommendation_shadow_candidate_run_idx
  on local_intel.recommendation_shadow_candidate_adjudications (run_id, live_position);

create or replace function local_intel.start_recommendation_shadow_run_v1(
  p_organization_id uuid,
  p_lens_stable_key text,
  p_query text,
  p_query_state jsonb default '{}'::jsonb,
  p_object_types text[] default array['entity','offering','occurrence']::text[],
  p_city text default null,
  p_start_at timestamptz default null,
  p_end_at timestamptz default null,
  p_limit integer default 20
) returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, local_intel
as $$
declare
  v_lens_id uuid;
  v_run_id uuid;
  v_snapshot jsonb;
begin
  select l.id into v_lens_id
  from local_intel.recommendation_lenses l
  where l.organization_id = p_organization_id
    and l.stable_key = p_lens_stable_key
    and l.mode in ('shadow','active')
    and l.status in ('working','approved')
  order by l.source_version desc
  limit 1;

  if v_lens_id is null then
    raise exception 'No usable recommendation lens % for organization %', p_lens_stable_key, p_organization_id;
  end if;

  insert into local_intel.recommendation_shadow_runs (
    lens_id, query_text, query_state, retrieval_parameters, active_operator_snapshot, status
  )
  select
    v_lens_id,
    p_query,
    coalesce(p_query_state,'{}'::jsonb),
    jsonb_build_object(
      'object_types',p_object_types,
      'city',p_city,
      'start_at',p_start_at,
      'end_at',p_end_at,
      'limit',p_limit
    ),
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'operator_key',b.operator_key,
        'source_system',b.source_system,
        'source_ref',b.source_ref,
        'source_version',b.source_version,
        'authority_state',b.authority_state,
        'activation_rule',b.activation_rule,
        'prohibited_shortcuts',b.prohibited_shortcuts
      ) order by b.operator_key)
      from local_intel.recommendation_lens_operator_bindings b
      where b.lens_id=v_lens_id and b.status in ('working','approved')
    ),'[]'::jsonb),
    'retrieved'
  returning id into v_run_id;

  with retrieved as (
    select row_number() over (order by s.rank desc, s.title, s.object_id)::integer as live_position, s.*
    from local_intel.search_local_answers_v2(
      p_query,p_object_types,p_city,p_start_at,p_end_at,p_limit
    ) s
  ), inserted as (
    insert into local_intel.recommendation_shadow_candidate_adjudications (
      run_id,object_type,object_id,stable_key,live_position,live_rank,candidate_snapshot,status
    )
    select
      v_run_id,
      r.object_type,
      r.object_id,
      r.stable_key,
      r.live_position,
      r.rank,
      jsonb_build_object(
        'entity_id',r.entity_id,
        'entity_name',r.entity_name,
        'title',r.title,
        'description',r.description,
        'category',r.category,
        'audience',r.audience,
        'price',r.price,
        'schedule',r.schedule,
        'location',r.location,
        'current_status',r.current_status,
        'starts_at',r.starts_at,
        'ends_at',r.ends_at,
        'public_url',r.public_url,
        'website_url',r.website_url,
        'phone',r.phone,
        'email',r.email,
        'last_verified_at',r.last_verified_at,
        'availability_freshness',r.availability_freshness,
        'current_availability',r.current_availability
      ),
      'retrieved'
    from retrieved r
    returning id
  )
  select count(*) into strict v_snapshot from inserted;

  select coalesce(jsonb_agg(jsonb_build_object(
    'object_type',c.object_type,
    'object_id',c.object_id,
    'stable_key',c.stable_key,
    'live_position',c.live_position,
    'live_rank',c.live_rank,
    'candidate',c.candidate_snapshot
  ) order by c.live_position),'[]'::jsonb)
  into v_snapshot
  from local_intel.recommendation_shadow_candidate_adjudications c
  where c.run_id=v_run_id;

  update local_intel.recommendation_shadow_runs r
  set retrieval_count=(select count(*) from local_intel.recommendation_shadow_candidate_adjudications c where c.run_id=v_run_id),
      live_result_snapshot=coalesce(v_snapshot,'[]'::jsonb),
      updated_at=now()
  where r.id=v_run_id;

  return v_run_id;
end;
$$;

create or replace view local_intel.v_recommendation_shadow_compare_v1
with (security_invoker=true)
as
select
  r.id as run_id,
  l.organization_id,
  l.stable_key as lens_key,
  l.source_system as lens_source_system,
  l.source_ref as lens_source_ref,
  l.source_version as lens_source_version,
  r.query_text,
  r.query_state,
  r.status as run_status,
  c.object_type,
  c.object_id,
  c.stable_key,
  c.live_position,
  c.live_rank,
  c.verdict,
  c.shadow_position_group,
  c.confidence,
  c.rationale,
  c.activated_dimensions,
  c.basis_operator_keys,
  c.missing_evidence,
  c.does_not_establish,
  c.candidate_snapshot,
  r.created_at as run_created_at
from local_intel.recommendation_shadow_runs r
join local_intel.recommendation_lenses l on l.id=r.lens_id
join local_intel.recommendation_shadow_candidate_adjudications c on c.run_id=r.id;
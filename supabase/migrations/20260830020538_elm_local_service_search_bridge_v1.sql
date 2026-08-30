create or replace function public.elm_local_search_answers_v1(
  p_query text,
  p_object_types text[] default array['entity'::text,'offering'::text],
  p_city text default null,
  p_limit integer default 20
)
returns table(
  object_type text,
  object_id uuid,
  stable_key text,
  entity_id uuid,
  entity_name text,
  title text,
  description text,
  category text,
  current_status text,
  public_url text,
  website_url text,
  phone text,
  last_verified_at timestamptz,
  availability_freshness text,
  current_availability jsonb,
  latest_current_observation_at timestamptz,
  rank real
)
language sql
stable
security definer
set search_path = pg_catalog, public, local_intel
as $function$
  select
    s.object_type,
    s.object_id,
    s.stable_key,
    s.entity_id,
    s.entity_name,
    s.title,
    s.description,
    s.category,
    s.current_status,
    s.public_url,
    s.website_url,
    s.phone,
    s.last_verified_at,
    s.availability_freshness,
    s.current_availability,
    s.latest_current_observation_at,
    s.rank
  from local_intel.search_local_answers_v2(
    p_query,
    p_object_types,
    p_city,
    null,
    null,
    greatest(1, least(coalesce(p_limit,20),100))
  ) as s;
$function$;

revoke all on function public.elm_local_search_answers_v1(text,text[],text,integer) from public;
revoke all on function public.elm_local_search_answers_v1(text,text[],text,integer) from anon;
revoke all on function public.elm_local_search_answers_v1(text,text[],text,integer) from authenticated;
grant execute on function public.elm_local_search_answers_v1(text,text[],text,integer) to service_role;

comment on function public.elm_local_search_answers_v1(text,text[],text,integer) is
  'Server-only Elm Local read bridge into the private local_intel answer inventory. The service role may search governed public-facing local facts without exposing the local_intel schema to PostgREST clients.';
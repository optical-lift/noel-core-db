create or replace function atlas.atlas_home_identity_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
  select jsonb_build_object(
    'ok', true,
    'authenticated', auth.uid() is not null,
    'hasPrincipal', exists(select 1 from atlas.principals p where p.user_id=auth.uid() and p.status='active'),
    'principalName', (select p.name from atlas.principals p where p.user_id=auth.uid() and p.status='active' limit 1)
  );
$$;

create or replace function public.atlas_home_identity_self_api_v1()
returns jsonb
language sql
stable
security invoker
set search_path to 'pg_catalog','atlas','public'
as $$ select atlas.atlas_home_identity_self_api_v1(); $$;

revoke all on function public.atlas_home_identity_self_api_v1() from public, anon;
grant execute on function public.atlas_home_identity_self_api_v1() to authenticated;
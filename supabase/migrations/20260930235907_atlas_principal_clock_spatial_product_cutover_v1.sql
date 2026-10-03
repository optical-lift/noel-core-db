-- Atlas Principal Clock spatial product cutover v1
-- The current Atlas home already calls principal_clock_api_v2. Make that stable
-- product seam delegate to the spatially aware Clock while preserving the
-- existing top-level candidate contract.

create or replace function atlas.principal_clock_api_v2(
  p_day date default current_date,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  return atlas.principal_clock_spatial_api_v1(p_day,p_as_of);
end
$function$;

revoke all on function atlas.principal_clock_api_v2(date,timestamptz) from public,anon;
grant execute on function atlas.principal_clock_api_v2(date,timestamptz) to authenticated,service_role;

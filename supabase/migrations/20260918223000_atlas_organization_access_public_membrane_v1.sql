begin;

-- Browser/PostgREST membrane for the already-governed organization-access
-- projection. The Atlas function remains authoritative; this wrapper adds no
-- membership, seat, responsibility, Principal, execution, or exposure authority.

do $preflight$
begin
  if to_regprocedure('atlas.organization_access_self_api_v1()') is null then
    raise exception 'organization access public membrane prerequisite is missing: atlas.organization_access_self_api_v1()';
  end if;
end;
$preflight$;

create or replace function public.organization_access_self_api_v1()
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.organization_access_self_api_v1();
$function$;

revoke all on function public.organization_access_self_api_v1() from public, anon;
grant execute on function public.organization_access_self_api_v1() to authenticated, service_role;

comment on function public.organization_access_self_api_v1() is
  'Browser membrane for the authority-checked Atlas organization-access projection. Adds no authority and delegates to atlas.organization_access_self_api_v1().';

commit;

begin;

-- Thin PostgREST/browser membrane for the already-governed Company Operating Knowledge resolver.
-- Resolution authority remains inside atlas.resolve_company_operating_knowledge_v1.

do $preflight$
begin
  if to_regprocedure('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz)') is null then
    raise exception 'Operating Knowledge resolver prerequisite is missing: atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz)';
  end if;
end;
$preflight$;

create or replace function public.resolve_company_operating_knowledge_v1(
  p_organization_id uuid,
  p_knowledge_kind text,
  p_context jsonb,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.resolve_company_operating_knowledge_v1(
    p_organization_id,
    p_knowledge_kind,
    p_context,
    p_as_of
  );
$function$;

revoke all on function public.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) from public, anon;
grant execute on function public.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) to authenticated, service_role;

comment on function public.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamptz) is
  'Browser membrane for established Company Operating Knowledge resolution. The existing atlas.* resolver remains authoritative.';

commit;

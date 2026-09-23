begin;

-- Atlas Organization Unit Reality preview RPC alias v1.
--
-- The original preview identifier exceeded PostgreSQL's 63-byte identifier
-- limit and was stored as:
--   public.preview_implementation_reality_organization_unit_promotion_self(uuid)
--
-- SQL parser calls using the longer source spelling happened to resolve because
-- PostgreSQL truncates identifiers during parsing. PostgREST/Supabase RPC names
-- are literal API route names, so expose an explicit versioned alias under the
-- identifier limit.

do $prerequisites$
begin
  if to_regprocedure(
    'public.preview_implementation_reality_organization_unit_promotion_self(uuid)'
  ) is null then
    raise exception 'Released Organization Unit promotion preview must exist before RPC alias.'
      using errcode='0A000';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)'
  ) is null then
    raise exception 'Released Organization Unit promotion command must exist before RPC alias.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

create or replace function public.preview_implementation_reality_org_unit_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select public.preview_implementation_reality_organization_unit_promotion_self(
    p_candidate_id
  );
$function$;

revoke all on function public.preview_implementation_reality_org_unit_promotion_self_api_v1(uuid)
  from public,anon,service_role;

grant execute on function public.preview_implementation_reality_org_unit_promotion_self_api_v1(uuid)
  to authenticated;

comment on function public.preview_implementation_reality_org_unit_promotion_self_api_v1(uuid) is
  'Explicit PostgREST-safe versioned alias for the released Organization Unit Reality promotion preview. The original source identifier exceeded PostgreSQL''s 63-byte identifier limit and was stored truncated. This alias preserves the released preview behavior without adding mutation authority.';

commit;

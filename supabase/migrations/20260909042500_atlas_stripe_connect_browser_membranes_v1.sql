create or replace function public.organization_onboarding_context_self_api_v1(p_organization_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.organization_onboarding_context_self_api_v1(p_organization_id);
$function$;

revoke all on function public.organization_onboarding_context_self_api_v1(uuid) from public, anon;
grant execute on function public.organization_onboarding_context_self_api_v1(uuid) to authenticated, service_role;

create or replace function public.connected_sources_self_api_v1()
returns table(
  source_id uuid,
  custody_kind text,
  custodian_organization_id uuid,
  custodian_organization_unit_id uuid,
  provider_key text,
  provider_account_key text,
  display_label text,
  account_hint text,
  authorization_state text,
  granted_scopes text[],
  capabilities jsonb,
  last_sync_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
set search_path = pg_catalog, atlas, public
as $function$
  select * from atlas.connected_sources_self_api_v1();
$function$;

revoke all on function public.connected_sources_self_api_v1() from public, anon;
grant execute on function public.connected_sources_self_api_v1() to authenticated, service_role;

comment on function public.organization_onboarding_context_self_api_v1(uuid) is
  'Browser API membrane for the authenticated caller to read their onboarding relationship to one organization.';
comment on function public.connected_sources_self_api_v1() is
  'Browser API membrane for the authenticated caller to list connected sources they are authorized to see.';

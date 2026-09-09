drop function if exists atlas.connected_sources_self_api_v1();

create function atlas.connected_sources_self_api_v1()
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
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select
    source.id,
    case when source.custodian_user_id is not null then 'human' else 'organization' end,
    source.custodian_organization_id,
    source.custodian_organization_unit_id,
    source.provider_key,
    source.provider_account_key,
    source.display_label,
    source.account_hint,
    source.authorization_state,
    source.granted_scopes,
    source.capabilities,
    source.last_sync_at,
    source.created_at,
    source.updated_at
  from atlas.connected_sources source
  where auth.uid() is not null
    and (
      source.custodian_user_id = auth.uid()
      or exists (
        select 1 from atlas.organization_memberships membership
        where membership.organization_id = source.custodian_organization_id
          and membership.user_id = auth.uid()
          and membership.active
      )
      or exists (
        select 1 from atlas.organization_onboarding_actors actor
        where actor.organization_id = source.custodian_organization_id
          and actor.human_user_id = auth.uid()
          and actor.active
      )
    )
  order by source.created_at, source.id;
$function$;

revoke all on function atlas.connected_sources_self_api_v1() from public, anon;
grant execute on function atlas.connected_sources_self_api_v1() to authenticated, service_role;
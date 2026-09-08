-- Read-only authority check for client-side/provider connection initiation.
-- The mutation commands remain the final authority gate.

create or replace function atlas.organization_connected_source_authorized_self_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select auth.uid() is not null and (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = p_organization_id
        and membership.user_id = auth.uid()
        and membership.active
        and membership.role = 'owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id = p_organization_id
        and actor.human_user_id = auth.uid()
        and actor.actor_kind = 'setup_actor'
        and actor.active
    )
  );
$function$;

comment on function atlas.organization_connected_source_authorized_self_v1(uuid) is
'Returns whether the current authenticated human may authorize an organization-owned connected source: active organization owner or active temporary setup_actor.';

revoke all on function atlas.organization_connected_source_authorized_self_v1(uuid) from public, anon;
grant execute on function atlas.organization_connected_source_authorized_self_v1(uuid) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values (
  'atlas.organization_connected_source_authorized_self_v1(uuid)',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_organization_connected_source_authority_read_v1',
    'purpose','Fail fast before launching a provider authorization flow for an organization.',
    'boundary','Caller identity is auth.uid(); only active owner or active setup_actor returns true.',
    'truthBoundary','Read-only authority projection; it does not authorize a provider or mutate connected-source state.'
  ),false
)
on conflict (signature) do update
set classification=excluded.classification,
    confidence=excluded.confidence,
    review_status=excluded.review_status,
    authenticated_execute_expected=excluded.authenticated_execute_expected,
    security_definer_expected=excluded.security_definer_expected,
    service_execute_expected=excluded.service_execute_expected,
    caller_count=excluded.caller_count,
    policy_reference_count=excluded.policy_reference_count,
    evidence=excluded.evidence,
    anonymous_execute_expected=excluded.anonymous_execute_expected,
    reviewed_at=now();

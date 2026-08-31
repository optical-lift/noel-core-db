-- Atlas Organization Onboarding Context v1
--
-- Read membrane for a human who is carrying organization setup without being a member.

begin;

create or replace function atlas.organization_onboarding_context_self_api_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_org atlas.organizations%rowtype;
  v_setup_actor boolean := false;
  v_membership_role text;
  v_reconstruction jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select organization.*
  into v_org
  from atlas.organizations organization
  where organization.id = p_organization_id
    and organization.status = 'active';

  if not found then
    return null;
  end if;

  select exists (
    select 1
    from atlas.organization_onboarding_actors actor
    where actor.organization_id = p_organization_id
      and actor.human_user_id = v_uid
      and actor.active
  ) into v_setup_actor;

  select membership.role
  into v_membership_role
  from atlas.organization_memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = v_uid
    and membership.active
  limit 1;

  if not v_setup_actor and v_membership_role is null then
    return null;
  end if;

  select jsonb_build_object(
    'id', session.id,
    'status', session.status,
    'clean_room', session.clean_room,
    'allow_existing_atlas_canon', session.allow_existing_atlas_canon,
    'target_organization_id', session.target_organization_id
  )
  into v_reconstruction
  from atlas.reconstruction_sessions session
  where session.human_user_id = v_uid
    and session.target_organization_id = p_organization_id
    and session.status in ('collecting','reconstructing','needs_review','ready')
  order by session.started_at desc, session.id desc
  limit 1;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_org.id,
      'stable_key', v_org.stable_key,
      'name', v_org.name,
      'status', v_org.status,
      'onboarding_state', v_org.onboarding_state
    ),
    'relationship', jsonb_build_object(
      'setup_actor', v_setup_actor,
      'membership_role', v_membership_role
    ),
    'reconstruction', v_reconstruction
  );
end;
$function$;

comment on function atlas.organization_onboarding_context_self_api_v1(uuid) is
  'Returns one organization onboarding context only when auth.uid is either an active temporary setup actor or an active durable member. Setup actors are not promoted to membership.';

revoke all on function atlas.organization_onboarding_context_self_api_v1(uuid) from public, anon;
grant execute on function atlas.organization_onboarding_context_self_api_v1(uuid) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  anonymous_execute_expected
) values (
  'atlas.organization_onboarding_context_self_api_v1(uuid)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  0,
  jsonb_build_object(
    'source','atlas_organization_onboarding_context_v1',
    'purpose','Let a human continue organization setup without requiring a durable organization membership.',
    'boundary','Caller identity is auth.uid. Returns only organizations where the caller is an active setup actor or active member. Setup actor status remains distinct from membership.',
    'truthBoundary','Read-only onboarding context. Does not create membership, authorize providers, mutate organization facts, or import Atlas canon.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict (signature) do update set
  classification=excluded.classification,
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

do $invariants$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1() drift
    where drift.signature = 'atlas.organization_onboarding_context_self_api_v1(uuid)'
  ) then
    raise exception 'Organization onboarding context RPC custody drift remains.';
  end if;
end;
$invariants$;

commit;

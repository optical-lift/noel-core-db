-- Atlas Organization Setup Actor v2
--
-- Correction to the first organization-onboarding membrane:
--   beginning Organization Atlas does not make the setup human an owner/member;
--   the organization may exist before any employee/owner/member has an Atlas account;
--   an authenticated Atlas human may act as a temporary setup actor without becoming
--   part of the organization's durable membership graph;
--   future billing/checkout may create the same organization-onboarding state without
--   requiring that setup actor to already have a Personal Atlas subscription.

begin;

create table if not exists atlas.organization_onboarding_actors (
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  human_user_id uuid not null references auth.users(id) on delete cascade,
  actor_kind text not null default 'setup_actor'
    check (actor_kind in ('setup_actor')),
  active boolean not null default true,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  primary key (organization_id, human_user_id),
  check ((active and ended_at is null) or (not active and ended_at is not null))
);

comment on table atlas.organization_onboarding_actors is
  'Temporary setup relationship between a human and an independently existing organization. This is not employment, ownership, membership, or authorization to represent the organization after onboarding. It exists only to carry the setup process.';
comment on column atlas.organization_onboarding_actors.human_user_id is
  'Atlas human currently carrying setup. A future checkout path may establish the organization before this relation exists; organization identity does not depend on a human membership.';

create index if not exists organization_onboarding_actors_human_active_idx
  on atlas.organization_onboarding_actors (human_user_id, started_at desc)
  where active;

revoke all on table atlas.organization_onboarding_actors from public, anon, authenticated;
grant select, insert, update, delete on table atlas.organization_onboarding_actors to service_role;

-- Organization-targeted reconstruction may be carried either by an active member or
-- by a temporary setup actor. The target organization itself remains the custody root.
create or replace function atlas.guard_reconstruction_session_source_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_human_user_id uuid;
  v_target_organization_id uuid;
  v_source_user_id uuid;
  v_source_organization_id uuid;
begin
  select session.human_user_id, session.target_organization_id
  into v_human_user_id, v_target_organization_id
  from atlas.reconstruction_sessions session
  where session.id = new.reconstruction_session_id;

  if v_human_user_id is null then
    raise exception 'Reconstruction session not found.' using errcode = '23503';
  end if;

  select source.custodian_user_id, source.custodian_organization_id
  into v_source_user_id, v_source_organization_id
  from atlas.connected_sources source
  where source.id = new.connected_source_id;

  if not found then
    raise exception 'Connected source not found.' using errcode = '23503';
  end if;

  if v_target_organization_id is not null then
    if not (
      exists (
        select 1
        from atlas.organization_memberships membership
        where membership.organization_id = v_target_organization_id
          and membership.user_id = v_human_user_id
          and membership.active
      )
      or exists (
        select 1
        from atlas.organization_onboarding_actors actor
        where actor.organization_id = v_target_organization_id
          and actor.human_user_id = v_human_user_id
          and actor.active
      )
    ) then
      raise exception 'Human is not authorized to carry setup for the reconstruction target organization.' using errcode = '42501';
    end if;

    if v_source_organization_id = v_target_organization_id then
      return new;
    end if;

    raise exception 'Connected source is outside the target organization reconstruction custody.' using errcode = '42501';
  end if;

  if v_source_user_id = v_human_user_id then
    return new;
  end if;

  if v_source_organization_id is not null and exists (
    select 1
    from atlas.organization_memberships membership
    where membership.organization_id = v_source_organization_id
      and membership.user_id = v_human_user_id
      and membership.active
  ) then
    return new;
  end if;

  raise exception 'Connected source is outside this human reconstruction custody.' using errcode = '42501';
end;
$function$;

revoke all on function atlas.guard_reconstruction_session_source_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_reconstruction_session_source_custody_v1() to service_role;

-- Setup actors may inspect the non-secret source registry for the organization they are
-- currently onboarding, without being promoted into the durable membership graph.
create or replace function atlas.connected_sources_self_api_v1()
returns table (
  source_id uuid,
  custody_kind text,
  custodian_organization_id uuid,
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
        select 1
        from atlas.organization_memberships membership
        where membership.organization_id = source.custodian_organization_id
          and membership.user_id = auth.uid()
          and membership.active
      )
      or exists (
        select 1
        from atlas.organization_onboarding_actors actor
        where actor.organization_id = source.custodian_organization_id
          and actor.human_user_id = auth.uid()
          and actor.active
      )
    )
  order by source.created_at, source.id;
$function$;

revoke all on function atlas.connected_sources_self_api_v1() from public, anon;
grant execute on function atlas.connected_sources_self_api_v1() to authenticated, service_role;

-- The v1 establishment endpoint encoded a durable owner relation too early. Retire it
-- from authenticated callers. Keeping the function for service-role compatibility avoids
-- a destructive schema removal while preventing the browser from using the old semantics.
revoke execute on function atlas.establish_organization_self_api_v1(text) from authenticated;

update atlas.authenticated_rpc_registry
set
  classification = 'service_internal',
  review_status = 'revoked',
  authenticated_execute_expected = false,
  service_execute_expected = true,
  evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object(
    'supersededBy','atlas.begin_organization_onboarding_self_api_v1(text)',
    'reason','Organization setup no longer implies owner/member status. The old endpoint is retained only as service-internal compatibility and is not callable by authenticated clients.'
  ),
  reviewed_at = now()
where signature = 'atlas.establish_organization_self_api_v1(text)';

create or replace function atlas.begin_organization_onboarding_self_api_v1(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_organization_id uuid := gen_random_uuid();
  v_reconstruction_session_id uuid;
  v_stable_base text;
  v_stable_key text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if length(v_name) < 2 or length(v_name) > 160 then
    raise exception 'Organization name must be between 2 and 160 characters.' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from auth.users user_row
    where user_row.id = v_uid
      and user_row.deleted_at is null
      and (user_row.banned_until is null or user_row.banned_until <= now())
  ) then
    raise exception 'Authenticated setup human is unavailable.' using errcode = '42501';
  end if;

  v_stable_base := btrim(regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g'), '_');
  if v_stable_base = '' then
    v_stable_base := 'organization';
  end if;

  v_stable_key := v_stable_base;
  if exists (select 1 from atlas.organizations organization where organization.stable_key = v_stable_key) then
    v_stable_key := v_stable_base || '_' || substr(replace(v_organization_id::text, '-', ''), 1, 8);
  end if;

  insert into atlas.organizations (
    id,
    stable_key,
    name,
    status,
    metadata,
    onboarding_state,
    onboarding_started_at
  ) values (
    v_organization_id,
    v_stable_key,
    v_name,
    'active',
    jsonb_build_object(
      'onboarding_entry','existing_atlas_human',
      'membership_claimed',false
    ),
    'connecting_sources',
    now()
  );

  insert into atlas.organization_onboarding_actors (
    organization_id,
    human_user_id,
    actor_kind,
    active,
    metadata
  ) values (
    v_organization_id,
    v_uid,
    'setup_actor',
    true,
    jsonb_build_object('source','organization_onboarding_self')
  );

  insert into atlas.reconstruction_sessions (
    human_user_id,
    target_organization_id,
    status,
    clean_room,
    allow_existing_atlas_canon,
    purpose,
    metadata
  ) values (
    v_uid,
    v_organization_id,
    'collecting',
    true,
    false,
    'organization_onboarding',
    jsonb_build_object('organization_stable_key', v_stable_key)
  )
  returning id into v_reconstruction_session_id;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_organization_id,
      'stable_key', v_stable_key,
      'name', v_name,
      'status', 'active',
      'onboarding_state', 'connecting_sources'
    ),
    'setupActor', jsonb_build_object(
      'human_user_id', v_uid,
      'kind', 'setup_actor',
      'active', true,
      'membership_created', false
    ),
    'reconstruction', jsonb_build_object(
      'id', v_reconstruction_session_id,
      'clean_room', true,
      'allow_existing_atlas_canon', false,
      'target_organization_id', v_organization_id
    )
  );
end;
$function$;

comment on function atlas.begin_organization_onboarding_self_api_v1(text) is
  'Authenticated human begins setup for an independent organization. Creates the organization, a temporary setup-actor relation, and a target-scoped clean-room reconstruction. It creates no farm and no durable organization membership/owner/employee relation.';

revoke all on function atlas.begin_organization_onboarding_self_api_v1(text) from public, anon;
grant execute on function atlas.begin_organization_onboarding_self_api_v1(text) to authenticated, service_role;

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
  'atlas.begin_organization_onboarding_self_api_v1(text)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  0,
  jsonb_build_object(
    'source','atlas_organization_setup_actor_v2',
    'purpose','Begin Organization Atlas without prematurely attaching the setup human as an owner/member.',
    'boundary','Caller identity is auth.uid(). Organization is independently created. Caller receives only temporary setup-actor status; no farm, owner, employee, or member relation is created.',
    'truthBoundary','The setup act establishes only the organization name, onboarding state, temporary setup carrier, and clean-room reconstruction. Durable organization membership remains a later explicit claim.',
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

-- Existing production currently has no organization created through the v1 endpoint.
-- This invariant guards the new semantics going forward without rewriting historical
-- organizations or inventing memberships.
do $invariants$
begin
  if exists (
    select 1
    from atlas.organization_onboarding_actors actor
    join atlas.organization_memberships membership
      on membership.organization_id = actor.organization_id
     and membership.user_id = actor.human_user_id
    where actor.active
      and membership.active
      and coalesce((membership.permissions ->> 'created_by_setup_actor')::boolean, false)
  ) then
    raise exception 'Setup actor was silently converted into durable organization membership.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1() drift
    where drift.signature in (
      'atlas.establish_organization_self_api_v1(text)',
      'atlas.begin_organization_onboarding_self_api_v1(text)'
    )
  ) then
    raise exception 'Organization onboarding RPC custody drift remains.';
  end if;
end;
$invariants$;

commit;

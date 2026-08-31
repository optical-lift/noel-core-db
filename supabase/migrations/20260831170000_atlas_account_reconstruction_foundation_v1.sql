-- Atlas Account + Reconstruction Foundation v1
--
-- Governing boundary:
--   auth.users identifies the human account;
--   organizations remain independent institutional custody roots;
--   a human may participate in zero, one, or many organizations/farms;
--   connected provider accounts are evidence sources, not human identity;
--   reconstruction may observe aggressively but may not silently read Atlas canon in clean-room mode;
--   OAuth passwords/tokens/secrets are never stored in atlas.connected_sources.

begin;

alter table atlas.user_profiles
  add column if not exists default_organization_id uuid references atlas.organizations(id) on delete set null,
  add column if not exists onboarding_state text not null default 'new',
  add column if not exists onboarding_started_at timestamptz,
  add column if not exists onboarding_completed_at timestamptz;

alter table atlas.user_profiles
  drop constraint if exists user_profiles_onboarding_state_check,
  add constraint user_profiles_onboarding_state_check
    check (onboarding_state in ('new','connecting_sources','reconstructing','needs_review','ready'));

comment on column atlas.user_profiles.default_organization_id is
  'Optional preferred organization context for this human. It does not make the organization subordinate to the person and is used only when an active membership authorizes it.';
comment on column atlas.user_profiles.onboarding_state is
  'Account-level Atlas onboarding/reconstruction state. Farm or organization membership may already make a user operational even when this state is new.';

-- Preserve all existing Atlas users as established users. New profiles created after
-- this migration begin at `new` unless an explicit onboarding flow advances them.
update atlas.user_profiles
set onboarding_state = 'ready'
where onboarding_state = 'new';

-- Prefer the organization already implied by the existing default farm. If there is
-- no default farm, use the first active organization membership only as a preference;
-- application session normalization must still verify active membership before use.
update atlas.user_profiles profile
set default_organization_id = coalesce(
  (
    select farm.organization_id
    from atlas.farms farm
    where farm.id = profile.default_farm_id
  ),
  (
    select membership.organization_id
    from atlas.organization_memberships membership
    where membership.user_id = profile.user_id
      and membership.active
    order by membership.created_at, membership.id
    limit 1
  )
)
where profile.default_organization_id is null;

create table if not exists atlas.connected_sources (
  id uuid primary key default gen_random_uuid(),
  custodian_user_id uuid references auth.users(id) on delete cascade,
  custodian_organization_id uuid references atlas.organizations(id) on delete cascade,
  provider_key text not null,
  provider_account_key text not null,
  display_label text,
  account_hint text,
  authorization_state text not null default 'connected'
    check (authorization_state in ('pending','connected','reauthorization_required','revoked','error')),
  granted_scopes text[] not null default '{}'::text[],
  capabilities jsonb not null default '{}'::jsonb,
  last_sync_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(provider_key) <> ''),
  check (btrim(provider_account_key) <> ''),
  check ((custodian_user_id is not null)::integer + (custodian_organization_id is not null)::integer = 1),
  check (revoked_at is null or authorization_state = 'revoked')
);

comment on table atlas.connected_sources is
  'Registry of externally authorized source accounts. A source belongs to exactly one human or organization custody root. This table MUST NOT contain provider passwords, OAuth access/refresh tokens, API secrets, or other reusable credentials.';
comment on column atlas.connected_sources.provider_account_key is
  'Stable provider-side account identity when available; do not use a mutable email address as the only identity if the provider exposes a durable account id.';
comment on column atlas.connected_sources.account_hint is
  'Human-readable account hint such as an email address or workspace name. It is descriptive, never the Atlas human identity.';
comment on column atlas.connected_sources.capabilities is
  'Non-secret capability description (for example mail/calendar/files). Authorization credentials are intentionally outside this table.';

create unique index if not exists connected_sources_user_provider_account_uq
  on atlas.connected_sources (custodian_user_id, provider_key, provider_account_key)
  where custodian_user_id is not null;

create unique index if not exists connected_sources_org_provider_account_uq
  on atlas.connected_sources (custodian_organization_id, provider_key, provider_account_key)
  where custodian_organization_id is not null;

create index if not exists connected_sources_user_state_idx
  on atlas.connected_sources (custodian_user_id, authorization_state)
  where custodian_user_id is not null;

create index if not exists connected_sources_org_state_idx
  on atlas.connected_sources (custodian_organization_id, authorization_state)
  where custodian_organization_id is not null;

create trigger connected_sources_set_updated_at
before update on atlas.connected_sources
for each row execute function atlas.set_updated_at();

create table if not exists atlas.reconstruction_sessions (
  id uuid primary key default gen_random_uuid(),
  human_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'collecting'
    check (status in ('collecting','reconstructing','needs_review','ready','closed')),
  clean_room boolean not null default true,
  allow_existing_atlas_canon boolean not null default false,
  purpose text not null default 'account_onboarding',
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(purpose) <> ''),
  check (not clean_room or not allow_existing_atlas_canon),
  check (completed_at is null or status in ('ready','closed'))
);

comment on table atlas.reconstruction_sessions is
  'Isolated human-root reconstruction runs. Clean-room sessions are intentionally barred from existing Atlas canon so an existing institution can be used as an answer key rather than an input.';
comment on column atlas.reconstruction_sessions.allow_existing_atlas_canon is
  'Explicit canon-read permission. It must remain false for clean-room onboarding acceptance tests.';

create index if not exists reconstruction_sessions_human_state_idx
  on atlas.reconstruction_sessions (human_user_id, status, started_at desc);

create trigger reconstruction_sessions_set_updated_at
before update on atlas.reconstruction_sessions
for each row execute function atlas.set_updated_at();

create table if not exists atlas.reconstruction_session_sources (
  reconstruction_session_id uuid not null references atlas.reconstruction_sessions(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  source_role text not null default 'evidence'
    check (source_role in ('evidence','corroboration')),
  admitted_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  primary key (reconstruction_session_id, connected_source_id)
);

comment on table atlas.reconstruction_session_sources is
  'Explicit source allowlist for a reconstruction session. No connected source is readable by a reconstruction merely because the account exists.';

create index if not exists reconstruction_session_sources_source_idx
  on atlas.reconstruction_session_sources (connected_source_id, reconstruction_session_id);

create or replace function atlas.guard_reconstruction_session_source_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_human_user_id uuid;
  v_source_user_id uuid;
  v_source_organization_id uuid;
begin
  select session.human_user_id
  into v_human_user_id
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

create trigger reconstruction_session_sources_custody_guard
before insert or update on atlas.reconstruction_session_sources
for each row execute function atlas.guard_reconstruction_session_source_custody_v1();

-- A read-only, authenticated source registry surface is safe because credentials are
-- not stored here. Organization sources are visible only to active organization members.
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
    )
  order by source.created_at, source.id;
$function$;

comment on function atlas.connected_sources_self_api_v1() is
  'Authenticated read-only registry of the current human sources plus sources held by organizations in which that human has active membership. No reusable credentials are returned or stored.';

revoke all on function atlas.connected_sources_self_api_v1() from public, anon;
grant execute on function atlas.connected_sources_self_api_v1() to authenticated, service_role;

-- Extend the existing fast session projection without changing its name or legacy fields.
-- Current farm consumers keep receiving exactly the same keys they already use; newer
-- consumers gain account-level onboarding and preferred organization context.
create or replace function atlas.current_session_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_claims jsonb := auth.jwt();
  v_session_id uuid;
  v_email text;
  v_user_metadata jsonb := '{}'::jsonb;
  v_profile jsonb;
  v_memberships jsonb := '[]'::jsonb;
  v_organization_memberships jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    return null;
  end if;

  begin
    v_session_id := nullif(v_claims ->> 'session_id', '')::uuid;
  exception when others then
    return null;
  end;

  if v_session_id is null then
    return null;
  end if;

  if not exists (
    select 1
    from auth.sessions session
    where session.id = v_session_id
      and session.user_id = v_uid
      and (session.not_after is null or session.not_after > now())
  ) then
    return null;
  end if;

  select user_row.email, coalesce(user_row.raw_user_meta_data, '{}'::jsonb)
  into v_email, v_user_metadata
  from auth.users user_row
  where user_row.id = v_uid
    and user_row.deleted_at is null
    and (user_row.banned_until is null or user_row.banned_until <= now());

  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'user_id', profile.user_id,
    'display_name', profile.display_name,
    'default_farm_id', profile.default_farm_id,
    'default_organization_id', profile.default_organization_id,
    'onboarding_state', profile.onboarding_state,
    'onboarding_started_at', profile.onboarding_started_at,
    'onboarding_completed_at', profile.onboarding_completed_at,
    'active', profile.active
  )
  into v_profile
  from atlas.user_profiles profile
  where profile.user_id = v_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', membership.id,
    'farm_id', membership.farm_id,
    'role', membership.role,
    'worker_key', membership.worker_key,
    'active', membership.active,
    'permissions', coalesce(membership.permissions, '{}'::jsonb),
    'farm', jsonb_build_object(
      'id', farm.id,
      'stable_key', farm.stable_key,
      'name', farm.name,
      'status', farm.status
    )
  ) order by membership.id), '[]'::jsonb)
  into v_memberships
  from atlas.farm_memberships membership
  join atlas.farms farm on farm.id = membership.farm_id
  where membership.user_id = v_uid
    and membership.active = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', membership.id,
    'organization_id', membership.organization_id,
    'role', membership.role,
    'active', membership.active,
    'permissions', coalesce(membership.permissions, '{}'::jsonb),
    'organization', jsonb_build_object(
      'id', organization.id,
      'stable_key', organization.stable_key,
      'name', organization.name,
      'status', organization.status
    )
  ) order by membership.id), '[]'::jsonb)
  into v_organization_memberships
  from atlas.organization_memberships membership
  join atlas.organizations organization on organization.id = membership.organization_id
  where membership.user_id = v_uid
    and membership.active = true;

  return jsonb_build_object(
    'user', jsonb_build_object(
      'id', v_uid,
      'email', v_email,
      'user_metadata', v_user_metadata
    ),
    'profile', v_profile,
    'memberships', v_memberships,
    'organizationMemberships', v_organization_memberships
  );
end;
$function$;

revoke all on function atlas.current_session_context_api_v1() from public, anon;
grant execute on function atlas.current_session_context_api_v1() to authenticated, service_role;

-- Raw source/reconstruction tables remain server-owned. Human-facing access is through
-- narrow RPC surfaces so future OAuth callbacks cannot accidentally broaden table rights.
revoke all on table atlas.connected_sources from public, anon, authenticated;
revoke all on table atlas.reconstruction_sessions from public, anon, authenticated;
revoke all on table atlas.reconstruction_session_sources from public, anon, authenticated;
grant select, insert, update, delete on table atlas.connected_sources to service_role;
grant select, insert, update, delete on table atlas.reconstruction_sessions to service_role;
grant select, insert, update, delete on table atlas.reconstruction_session_sources to service_role;

-- Migration invariants.
do $invariants$
begin
  if exists (
    select 1
    from atlas.connected_sources source
    where (source.custodian_user_id is not null)::integer
        + (source.custodian_organization_id is not null)::integer <> 1
  ) then
    raise exception 'Connected source custody invariant failed.';
  end if;

  if exists (
    select 1
    from atlas.reconstruction_sessions session
    where session.clean_room
      and session.allow_existing_atlas_canon
  ) then
    raise exception 'Clean-room reconstruction canon isolation invariant failed.';
  end if;

  if exists (
    select 1
    from atlas.user_profiles profile
    where profile.active
      and profile.onboarding_state not in ('new','connecting_sources','reconstructing','needs_review','ready')
  ) then
    raise exception 'Atlas user onboarding-state invariant failed.';
  end if;
end;
$invariants$;

commit;

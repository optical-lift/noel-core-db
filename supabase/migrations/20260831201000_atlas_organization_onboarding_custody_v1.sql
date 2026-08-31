-- Atlas Organization Onboarding Custody v1
--
-- Governing boundary:
--   a human must be authenticated to establish an organization;
--   the organization is an independent custody root, not a child of that human;
--   the establishment act creates only an organization + explicit human authority relation;
--   it never creates a farm;
--   organization reconstruction is clean-room and may admit only sources held by that exact organization.

begin;

alter table atlas.organizations
  add column if not exists onboarding_state text not null default 'new',
  add column if not exists onboarding_started_at timestamptz,
  add column if not exists onboarding_completed_at timestamptz;

alter table atlas.organizations
  drop constraint if exists organizations_onboarding_state_check,
  add constraint organizations_onboarding_state_check
    check (onboarding_state in ('new','connecting_sources','reconstructing','needs_review','ready'));

comment on column atlas.organizations.onboarding_state is
  'Organization-level onboarding/reconstruction state. This state belongs to the independent organization custody root, not to any one human member.';

-- Preserve existing institutional truth. Organizations that predate this onboarding
-- membrane are already established and must not be silently reopened for reconstruction.
update atlas.organizations
set onboarding_state = 'ready'
where onboarding_state = 'new';

alter table atlas.reconstruction_sessions
  add column if not exists target_organization_id uuid references atlas.organizations(id) on delete cascade;

comment on column atlas.reconstruction_sessions.target_organization_id is
  'Optional independent organization custody root being reconstructed. When present, the session may admit only sources held by this exact organization.';

create index if not exists reconstruction_sessions_target_org_state_idx
  on atlas.reconstruction_sessions (target_organization_id, status, started_at desc)
  where target_organization_id is not null;

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

  -- Organization-targeted reconstruction is intentionally stricter than general
  -- human reconstruction. Membership in some other organization does not authorize
  -- its evidence into this target's clean room, and personal sources are not silently
  -- reclassified as organization evidence.
  if v_target_organization_id is not null then
    if not exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = v_target_organization_id
        and membership.user_id = v_human_user_id
        and membership.active
    ) then
      raise exception 'Human is not an active member of the reconstruction target organization.' using errcode = '42501';
    end if;

    if v_source_organization_id = v_target_organization_id then
      return new;
    end if;

    raise exception 'Connected source is outside the target organization reconstruction custody.' using errcode = '42501';
  end if;

  -- Preserve the existing human-root reconstruction contract for sessions that do
  -- not name an organization target.
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

create or replace function atlas.establish_organization_self_api_v1(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_organization_id uuid := gen_random_uuid();
  v_membership_id uuid;
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
    raise exception 'Authenticated human is unavailable.' using errcode = '42501';
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
    jsonb_build_object('establishment_mode', 'authenticated_human'),
    'connecting_sources',
    now()
  );

  insert into atlas.organization_memberships (
    organization_id,
    user_id,
    role,
    active,
    permissions
  ) values (
    v_organization_id,
    v_uid,
    'owner',
    true,
    '{}'::jsonb
  )
  returning id into v_membership_id;

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
    'membership', jsonb_build_object(
      'id', v_membership_id,
      'role', 'owner',
      'active', true
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

comment on function atlas.establish_organization_self_api_v1(text) is
  'Authenticated human establishes a new independent organization, receives an explicit owner membership relation, and opens an organization-targeted clean-room reconstruction. Creates no farm and imports no existing Atlas canon.';

revoke all on function atlas.establish_organization_self_api_v1(text) from public, anon;
grant execute on function atlas.establish_organization_self_api_v1(text) to authenticated, service_role;

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
  'atlas.establish_organization_self_api_v1(text)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'source','atlas_organization_onboarding_custody_v1',
    'purpose','Allow an authenticated human to establish a new independent organization and explicit founding authority relationship.',
    'boundary','Caller identity is auth.uid(). The organization is an independent custody root; the function creates an organization membership relation but no farm, source, provider credential, or imported canon.',
    'truthBoundary','Opening onboarding creates only the organization, owner relationship, and organization-targeted clean-room reconstruction session. It does not assert facts about the organization beyond the human-provided name and establishment authority.',
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

-- Migration invariants.
do $invariants$
begin
  if exists (
    select 1
    from atlas.reconstruction_sessions session
    where session.target_organization_id is not null
      and not exists (
        select 1
        from atlas.organization_memberships membership
        where membership.organization_id = session.target_organization_id
          and membership.user_id = session.human_user_id
          and membership.active
      )
  ) then
    raise exception 'Organization reconstruction target membership invariant failed.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1() drift
    where drift.signature = 'atlas.establish_organization_self_api_v1(text)'
  ) then
    raise exception 'Organization establishment RPC custody registry drift remains.';
  end if;
end;
$invariants$;

commit;

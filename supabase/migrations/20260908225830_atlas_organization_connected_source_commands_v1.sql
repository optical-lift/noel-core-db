-- Atlas organization-owned connected source command membrane v1.
--
-- Canonical truth owner: atlas.connected_sources
-- This migration closes the organization-provider custody mutation gap documented in
-- architecture/atlas-organization-connected-source-commands-v1.md.
-- Provider adapters remain responsible for provider OAuth/API semantics and MUST NOT
-- place reusable provider credentials in ordinary Atlas metadata.

create or replace function atlas.register_organization_connected_source_self_api_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_authorization_state text default 'connected',
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_provider_key text := btrim(coalesce(p_provider_key, ''));
  v_provider_account_key text := btrim(coalesce(p_provider_account_key, ''));
  v_requested_state text := btrim(coalesce(p_authorization_state, ''));
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if p_organization_id is null or not exists (
    select 1
    from atlas.organizations organization
    where organization.id = p_organization_id
  ) then
    raise exception 'Organization is unavailable.' using errcode = '22023';
  end if;

  if not (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = p_organization_id
        and membership.user_id = v_uid
        and membership.active
        and membership.role = 'owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id = p_organization_id
        and actor.human_user_id = v_uid
        and actor.actor_kind = 'setup_actor'
        and actor.active
    )
  ) then
    raise exception 'Organization provider connection authority required.' using errcode = '42501';
  end if;

  if v_provider_key = '' or v_provider_account_key = '' then
    raise exception 'Provider identity is required.' using errcode = '22023';
  end if;

  if v_requested_state not in ('pending', 'connected') then
    raise exception 'A source may only be registered as pending or connected.' using errcode = '22023';
  end if;

  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode = '22023';
  end if;

  select source.*
    into v_source
  from atlas.connected_sources source
  where source.custodian_organization_id = p_organization_id
    and source.provider_key = v_provider_key
    and source.provider_account_key = v_provider_account_key
  for update;

  if found then
    if v_source.authorization_state = 'revoked' then
      raise exception 'A revoked provider source cannot be silently rebound. Deliberate reauthorization is required.' using errcode = '55000';
    end if;

    if v_requested_state = 'connected'
       and v_source.authorization_state not in ('pending', 'connected', 'error', 'reauthorization_required') then
      raise exception 'Illegal provider authorization transition.' using errcode = '55000';
    end if;

    if v_requested_state = 'pending'
       and v_source.authorization_state not in ('pending', 'error') then
      -- A retry cannot downgrade an already-connected or reauthorization-required source.
      v_requested_state := v_source.authorization_state;
    end if;

    update atlas.connected_sources source
    set display_label = coalesce(nullif(btrim(p_display_label), ''), source.display_label),
        account_hint = coalesce(nullif(btrim(p_account_hint), ''), source.account_hint),
        authorization_state = v_requested_state,
        granted_scopes = coalesce(p_granted_scopes, source.granted_scopes),
        capabilities = coalesce(p_capabilities, source.capabilities),
        revoked_at = null,
        metadata = source.metadata || v_metadata,
        updated_at = now()
    where source.id = v_source.id
    returning source.* into v_source;
  else
    insert into atlas.connected_sources (
      custodian_user_id,
      custodian_organization_id,
      provider_key,
      provider_account_key,
      display_label,
      account_hint,
      authorization_state,
      granted_scopes,
      capabilities,
      metadata
    ) values (
      null,
      p_organization_id,
      v_provider_key,
      v_provider_account_key,
      nullif(btrim(p_display_label), ''),
      nullif(btrim(p_account_hint), ''),
      v_requested_state,
      coalesce(p_granted_scopes, '{}'::text[]),
      coalesce(p_capabilities, '{}'::jsonb),
      v_metadata
    )
    returning * into v_source;
  end if;

  return jsonb_build_object(
    'sourceId', v_source.id,
    'organizationId', v_source.custodian_organization_id,
    'providerKey', v_source.provider_key,
    'providerAccountKey', v_source.provider_account_key,
    'authorizationState', v_source.authorization_state,
    'grantedScopes', v_source.granted_scopes,
    'capabilities', v_source.capabilities,
    'reused', v_source.created_at <> v_source.updated_at
  );
end;
$function$;

create or replace function atlas.transition_organization_connected_source_authorization_self_api_v1(
  p_source_id uuid,
  p_to_state text,
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_to_state text := btrim(coalesce(p_to_state, ''));
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
  v_from_state text;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  select source.*
    into v_source
  from atlas.connected_sources source
  where source.id = p_source_id
    and source.custodian_organization_id is not null
  for update;

  if not found then
    raise exception 'Organization connected source is unavailable.' using errcode = '22023';
  end if;

  if not (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = v_source.custodian_organization_id
        and membership.user_id = v_uid
        and membership.active
        and membership.role = 'owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id = v_source.custodian_organization_id
        and actor.human_user_id = v_uid
        and actor.actor_kind = 'setup_actor'
        and actor.active
    )
  ) then
    raise exception 'Organization provider connection authority required.' using errcode = '42501';
  end if;

  if v_to_state not in ('pending', 'connected', 'reauthorization_required', 'revoked', 'error') then
    raise exception 'Unknown provider authorization state.' using errcode = '22023';
  end if;

  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode = '22023';
  end if;

  v_from_state := v_source.authorization_state;

  if v_from_state = 'revoked' and v_to_state <> 'revoked' then
    raise exception 'Revoked sources cannot be silently reactivated in v1.' using errcode = '55000';
  end if;

  if v_from_state <> v_to_state and not (
    (v_from_state = 'pending' and v_to_state in ('connected', 'error', 'revoked'))
    or (v_from_state = 'connected' and v_to_state in ('reauthorization_required', 'error', 'revoked'))
    or (v_from_state = 'reauthorization_required' and v_to_state in ('connected', 'error', 'revoked'))
    or (v_from_state = 'error' and v_to_state in ('pending', 'connected', 'reauthorization_required', 'revoked'))
  ) then
    raise exception 'Illegal provider authorization transition from % to %.', v_from_state, v_to_state using errcode = '55000';
  end if;

  update atlas.connected_sources source
  set authorization_state = v_to_state,
      granted_scopes = coalesce(p_granted_scopes, source.granted_scopes),
      capabilities = coalesce(p_capabilities, source.capabilities),
      revoked_at = case when v_to_state = 'revoked' then coalesce(source.revoked_at, now()) else null end,
      metadata = source.metadata || v_metadata,
      updated_at = now()
  where source.id = v_source.id
  returning source.* into v_source;

  return jsonb_build_object(
    'sourceId', v_source.id,
    'organizationId', v_source.custodian_organization_id,
    'providerKey', v_source.provider_key,
    'providerAccountKey', v_source.provider_account_key,
    'fromState', v_from_state,
    'authorizationState', v_source.authorization_state,
    'grantedScopes', v_source.granted_scopes,
    'capabilities', v_source.capabilities,
    'revokedAt', v_source.revoked_at
  );
end;
$function$;

create or replace function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(
  p_source_id uuid,
  p_synced_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_synced_at timestamptz := coalesce(p_synced_at, now());
  v_source atlas.connected_sources%rowtype;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;

  if v_synced_at > now() + interval '5 minutes' then
    raise exception 'Sync checkpoint cannot be materially in the future.' using errcode = '22023';
  end if;

  select source.*
    into v_source
  from atlas.connected_sources source
  where source.id = p_source_id
    and source.custodian_organization_id is not null
  for update;

  if not found then
    raise exception 'Organization connected source is unavailable.' using errcode = '22023';
  end if;

  if v_source.authorization_state <> 'connected' then
    raise exception 'Only a connected source may advance its sync checkpoint.' using errcode = '55000';
  end if;

  if not (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = v_source.custodian_organization_id
        and membership.user_id = v_uid
        and membership.active
        and membership.role = 'owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id = v_source.custodian_organization_id
        and actor.human_user_id = v_uid
        and actor.actor_kind = 'setup_actor'
        and actor.active
    )
  ) then
    raise exception 'Organization provider connection authority required.' using errcode = '42501';
  end if;

  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode = '22023';
  end if;

  update atlas.connected_sources source
  set last_sync_at = case
        when source.last_sync_at is null then v_synced_at
        else greatest(source.last_sync_at, v_synced_at)
      end,
      metadata = source.metadata || v_metadata,
      updated_at = now()
  where source.id = v_source.id
  returning source.* into v_source;

  return jsonb_build_object(
    'sourceId', v_source.id,
    'organizationId', v_source.custodian_organization_id,
    'authorizationState', v_source.authorization_state,
    'lastSyncAt', v_source.last_sync_at
  );
end;
$function$;

comment on function atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)
is 'Governed authenticated registration/reuse of an organization-owned external provider source. Owner or active setup-actor authority is required; reusable provider credentials are prohibited from ordinary metadata.';

comment on function atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb)
is 'Governed authenticated authorization-state transition for an organization-owned connected source. Revoked-source reactivation is deliberately excluded from v1.';

comment on function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb)
is 'Governed authenticated monotonic sync checkpoint update for a connected organization-owned provider source.';

revoke all on function atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb) from public, anon;
revoke all on function atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb) from public, anon;
revoke all on function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb) from public, anon;

grant execute on function atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb) to authenticated, service_role;
grant execute on function atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb) to authenticated, service_role;
grant execute on function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb) to authenticated, service_role;

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
) values
(
  'atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_organization_connected_source_commands_v1',
    'purpose','Register or idempotently reuse an organization-owned provider account after provider identity is known.',
    'boundary','Caller identity is auth.uid(). Active organization owner or active setup_actor authority is required. Provider credentials are not stored.',
    'truthBoundary','Creates provider custody/authorization evidence only. Provider observations do not become Money, Registration, Work, or other domain truth.'
  ),
  false
),
(
  'atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_organization_connected_source_commands_v1',
    'purpose','Advance a provider connection through governed authorization states.',
    'boundary','Caller identity is auth.uid(). Active organization owner or active setup_actor authority is required. Revoked reactivation is intentionally unsupported in v1.',
    'truthBoundary','Authorization state is provider custody truth only and cannot directly mutate Atlas business-domain state.'
  ),
  false
),
(
  'atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_organization_connected_source_commands_v1',
    'purpose','Advance the durable last-sync checkpoint for a connected organization-owned provider source.',
    'boundary','Caller identity is auth.uid(). Active organization owner or active setup_actor authority is required. Checkpoints are monotonic.',
    'truthBoundary','A sync checkpoint records provider acquisition progress only; it does not establish the meaning of acquired provider records.'
  ),
  false
)
on conflict (signature) do update
set classification = excluded.classification,
    confidence = excluded.confidence,
    review_status = excluded.review_status,
    authenticated_execute_expected = excluded.authenticated_execute_expected,
    security_definer_expected = excluded.security_definer_expected,
    service_execute_expected = excluded.service_execute_expected,
    caller_count = excluded.caller_count,
    policy_reference_count = excluded.policy_reference_count,
    evidence = excluded.evidence,
    anonymous_execute_expected = excluded.anonymous_execute_expected,
    reviewed_at = now();

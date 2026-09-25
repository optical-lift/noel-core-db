begin;

-- Reality Observation / Connected Source authority v1.
--
-- This slice adds no universal Observation table and no provider-specific domain
-- semantics. It separates source visibility from authority to use a reusable
-- Connected Source credential for a bounded read-only observation.

create or replace function atlas.connected_source_observe_authorized_self_v1(
  p_source_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select auth.uid() is not null
    and exists (
      select 1
      from atlas.connected_sources source
      where source.id = p_source_id
        and source.authorization_state = 'connected'
        and (
          source.custodian_user_id = auth.uid()
          or (
            source.custodian_organization_id is not null
            and atlas.organization_connected_source_authorized_self_v1(
              source.custodian_organization_id
            )
          )
        )
    );
$function$;

create or replace function atlas.prepare_source_observation_self_api_v1(
  p_source_id uuid,
  p_required_provider_key text default null,
  p_required_capability text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_provider text := nullif(lower(btrim(coalesce(p_required_provider_key, ''))), '');
  v_capability text := nullif(btrim(coalesce(p_required_capability, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  if not atlas.connected_source_observe_authorized_self_v1(p_source_id) then
    raise exception 'Connected Source observation authority required.' using errcode='42501';
  end if;

  select source.*
  into v_source
  from atlas.connected_sources source
  where source.id = p_source_id;

  if v_source.id is null then
    raise exception 'Connected Source is unavailable.' using errcode='P0002';
  end if;

  if v_source.authorization_state <> 'connected' then
    raise exception 'Connected Source requires reauthorization before observation.' using errcode='55000';
  end if;

  if v_provider is not null
     and lower(btrim(v_source.provider_key)) is distinct from v_provider then
    raise exception 'Connected Source provider does not match the observation request.' using errcode='22023';
  end if;

  if v_capability is not null
     and not coalesce(v_source.capabilities, '{}'::jsonb)
       @> jsonb_build_object(v_capability, true) then
    raise exception 'Connected Source does not declare the required observation capability.' using errcode='55000';
  end if;

  return jsonb_build_object(
    'contractVersion', 'connected_source_observation_prepare_v1',
    'sourceId', v_source.id,
    'custodyKind', case when v_source.custodian_user_id is not null then 'human' else 'organization' end,
    'custodianOrganizationId', v_source.custodian_organization_id,
    'custodianOrganizationUnitId', v_source.custodian_organization_unit_id,
    'providerKey', v_source.provider_key,
    'providerAccountKey', v_source.provider_account_key,
    'displayLabel', v_source.display_label,
    'accountHint', v_source.account_hint,
    'authorizationState', v_source.authorization_state,
    'grantedScopes', v_source.granted_scopes,
    'capabilities', v_source.capabilities,
    'requiredCapability', v_capability,
    'effectAuthority', 'observe_only'
  );
end;
$function$;

revoke all on function atlas.connected_source_observe_authorized_self_v1(uuid)
  from public, anon;
revoke all on function atlas.prepare_source_observation_self_api_v1(uuid,text,text)
  from public, anon;
grant execute on function atlas.connected_source_observe_authorized_self_v1(uuid)
  to authenticated, service_role;
grant execute on function atlas.prepare_source_observation_self_api_v1(uuid,text,text)
  to authenticated, service_role;

-- Stable public transport names for the canonical provider-connection rail.
-- The durable session and authority remain owned by atlas.provider_connection_sessions
-- and the current-canon provider connection functions.

create or replace function public.begin_source_connection_self_api_v1(
  p_custodian_kind text,
  p_organization_id uuid default null,
  p_provider_key text default null,
  p_requested_scopes text[] default '{}'::text[],
  p_requested_capabilities jsonb default '{}'::jsonb,
  p_state_nonce_digest text default null,
  p_pkce_challenge text default null,
  p_redirect_uri text default null,
  p_expires_in_seconds integer default 600,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.begin_provider_connection_self_api_v1(
    p_custodian_kind,
    p_organization_id,
    p_provider_key,
    p_requested_scopes,
    p_requested_capabilities,
    p_state_nonce_digest,
    p_pkce_challenge,
    p_redirect_uri,
    p_expires_in_seconds,
    p_metadata
  );
$function$;

create or replace function public.complete_source_connection_identity_service_v1(
  p_session_id uuid,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.complete_provider_connection_identity_service_v1(
    p_session_id,
    p_provider_account_key,
    p_display_label,
    p_account_hint,
    p_granted_scopes,
    p_capabilities,
    p_metadata
  );
$function$;

create or replace function public.activate_source_connection_service_v1(
  p_session_id uuid,
  p_required_credential_kind text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.activate_provider_connection_service_v1(
    p_session_id,
    p_required_credential_kind,
    p_metadata
  );
$function$;

revoke all on function public.begin_source_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) from public, anon;
revoke all on function public.complete_source_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) from public, anon, authenticated;
revoke all on function public.activate_source_connection_service_v1(
  uuid,text,jsonb
) from public, anon, authenticated;

grant execute on function public.begin_source_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) to authenticated, service_role;
grant execute on function public.complete_source_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) to service_role;
grant execute on function public.activate_source_connection_service_v1(
  uuid,text,jsonb
) to service_role;

-- Stable public PostgREST names for existing authenticated Connected Source
-- authority/registration/transition/sync contracts. These wrappers add no
-- authority and avoid depending on non-public schema routing or identifiers
-- longer than PostgreSQL's 63-byte catalog limit.

create or replace function public.organization_source_authorized_self_api_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.organization_connected_source_authorized_self_v1(p_organization_id);
$function$;

create or replace function public.register_organization_source_self_api_v1(
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
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.register_organization_connected_source_self_api_v1(
    p_organization_id,
    p_provider_key,
    p_provider_account_key,
    p_display_label,
    p_account_hint,
    p_authorization_state,
    p_granted_scopes,
    p_capabilities,
    p_metadata
  );
$function$;

create or replace function public.transition_organization_source_self_api_v1(
  p_source_id uuid,
  p_to_state text,
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.transition_organization_connected_source_authorization_self_api_v1(
    p_source_id,
    p_to_state,
    p_granted_scopes,
    p_capabilities,
    p_metadata
  );
$function$;

create or replace function public.update_organization_source_sync_self_api_v1(
  p_source_id uuid,
  p_synced_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(
    p_source_id,
    p_synced_at,
    p_metadata
  );
$function$;

create or replace function public.prepare_source_observation_self_api_v1(
  p_source_id uuid,
  p_required_provider_key text default null,
  p_required_capability text default null
)
returns jsonb
language sql
stable
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.prepare_source_observation_self_api_v1(
    p_source_id,
    p_required_provider_key,
    p_required_capability
  );
$function$;

revoke all on function public.organization_source_authorized_self_api_v1(uuid)
  from public, anon;
revoke all on function public.register_organization_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)
  from public, anon;
revoke all on function public.transition_organization_source_self_api_v1(uuid,text,text[],jsonb,jsonb)
  from public, anon;
revoke all on function public.update_organization_source_sync_self_api_v1(uuid,timestamptz,jsonb)
  from public, anon;
revoke all on function public.prepare_source_observation_self_api_v1(uuid,text,text)
  from public, anon;

grant execute on function public.organization_source_authorized_self_api_v1(uuid)
  to authenticated, service_role;
grant execute on function public.register_organization_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)
  to authenticated, service_role;
grant execute on function public.transition_organization_source_self_api_v1(uuid,text,text[],jsonb,jsonb)
  to authenticated, service_role;
grant execute on function public.update_organization_source_sync_self_api_v1(uuid,timestamptz,jsonb)
  to authenticated, service_role;
grant execute on function public.prepare_source_observation_self_api_v1(uuid,text,text)
  to authenticated, service_role;

-- Stable public service-only transport names for existing canonical Atlas
-- credential/observation functions. Plaintext credential custody remains Vault.

create or replace function public.store_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text,
  p_secret text,
  p_description text default null
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.store_connected_source_secret_service_v1(
    p_connected_source_id,
    p_credential_kind,
    p_secret,
    p_description
  );
$function$;

create or replace function public.read_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text
)
returns text
language sql
stable
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.read_connected_source_secret_service_v1(
    p_connected_source_id,
    p_credential_kind
  );
$function$;

create or replace function public.delete_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text
)
returns boolean
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.delete_connected_source_secret_service_v1(
    p_connected_source_id,
    p_credential_kind
  );
$function$;

create or replace function public.record_source_observation_batch_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_records jsonb,
  p_observed_at timestamptz default now(),
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.record_connected_source_observation_batch_service_v1(
    p_connected_source_id,
    p_provider_object_kind,
    p_records,
    p_observed_at,
    p_provenance
  );
$function$;

create or replace function public.bind_source_org_unit_service_v1(
  p_connected_source_id uuid,
  p_organization_unit_id uuid
)
returns jsonb
language sql
set search_path = pg_catalog, atlas, public
as $function$
  select atlas.bind_connected_source_organization_unit_service_v1(
    p_connected_source_id,
    p_organization_unit_id
  );
$function$;

revoke all on function public.store_source_secret_service_v1(uuid,text,text,text)
  from public, anon, authenticated;
revoke all on function public.read_source_secret_service_v1(uuid,text)
  from public, anon, authenticated;
revoke all on function public.delete_source_secret_service_v1(uuid,text)
  from public, anon, authenticated;
revoke all on function public.record_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)
  from public, anon, authenticated;
revoke all on function public.bind_source_org_unit_service_v1(uuid,uuid)
  from public, anon, authenticated;

grant execute on function public.store_source_secret_service_v1(uuid,text,text,text)
  to service_role;
grant execute on function public.read_source_secret_service_v1(uuid,text)
  to service_role;
grant execute on function public.delete_source_secret_service_v1(uuid,text)
  to service_role;
grant execute on function public.record_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)
  to service_role;
grant execute on function public.bind_source_org_unit_service_v1(uuid,uuid)
  to service_role;

insert into atlas.authenticated_rpc_registry(
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
  'atlas.connected_source_observe_authorized_self_v1(uuid)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_reality_observation_source_authority_v1',
    'purpose','Separate source visibility from authority to use a Connected Source for bounded observation.',
    'truthBoundary','Observation-use authority only; no credential disclosure or domain consequence.'
  ),
  false
),
(
  'atlas.prepare_source_observation_self_api_v1(uuid,text,text)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_reality_observation_source_authority_v1',
    'purpose','Return bounded non-secret Connected Source context before a machine observation.',
    'truthBoundary','Preparation only; no credential disclosure, provider mutation, or domain consequence.'
  ),
  false
)
on conflict(signature) do update
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

commit;

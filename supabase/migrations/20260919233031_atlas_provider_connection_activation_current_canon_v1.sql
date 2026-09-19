begin;

-- External Source Continuity slice 1:
-- actor-bound provider authorization sessions + two-phase Connected Source activation.
-- Provider-specific webhook/sync/mapping semantics remain out of scope.

create table atlas.provider_connection_sessions (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  custodian_kind text not null check (custodian_kind in ('human','organization')),
  custodian_user_id uuid references auth.users(id) on delete cascade,
  custodian_organization_id uuid references atlas.organizations(id) on delete cascade,
  provider_key text not null check (btrim(provider_key) <> ''),
  state_nonce_digest text not null check (state_nonce_digest ~ '^[0-9a-f]{64}$'),
  pkce_challenge text,
  redirect_uri text,
  requested_scopes text[] not null default '{}'::text[],
  requested_capabilities jsonb not null default '{}'::jsonb
    check (jsonb_typeof(requested_capabilities)='object'),
  session_state text not null default 'pending'
    check (session_state in ('pending','identity_verified','connected','failed','expired')),
  provider_account_key text,
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  expires_at timestamptz not null,
  completed_at timestamptz,
  failure_reason text,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (((custodian_user_id is not null)::int + (custodian_organization_id is not null)::int)=1),
  check (
    (custodian_kind='human' and custodian_user_id is not null and custodian_organization_id is null)
    or
    (custodian_kind='organization' and custodian_user_id is null and custodian_organization_id is not null)
  )
);

create unique index provider_connection_sessions_state_nonce_uq
  on atlas.provider_connection_sessions(state_nonce_digest);
create index provider_connection_sessions_actor_created_idx
  on atlas.provider_connection_sessions(actor_user_id,created_at desc);
create index provider_connection_sessions_source_idx
  on atlas.provider_connection_sessions(connected_source_id)
  where connected_source_id is not null;

comment on table atlas.provider_connection_sessions is
'Short-lived provider authorization correlation. The row preserves initiating actor, intended Atlas custody, provider callback correlation, requested scopes/capabilities, and resulting Connected Source identity. Provider credentials and authorization codes are forbidden.';

alter table atlas.provider_connection_sessions enable row level security;
revoke all on table atlas.provider_connection_sessions from public,anon,authenticated;
grant select,insert,update,delete on table atlas.provider_connection_sessions to service_role;

create or replace function atlas.begin_provider_connection_self_api_v1(
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
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_kind text:=lower(btrim(coalesce(p_custodian_kind,'')));
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_digest text:=lower(btrim(coalesce(p_state_nonce_digest,'')));
  v_expiry integer:=greatest(60,least(coalesce(p_expires_in_seconds,600),1800));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_session atlas.provider_connection_sessions%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if v_kind not in ('human','organization') then
    raise exception 'Provider connection custody must be human or organization.' using errcode='22023';
  end if;
  if v_provider='' or v_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'Provider and lowercase SHA-256 state digest are required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_requested_capabilities,'{}'::jsonb))<>'object'
     or jsonb_typeof(v_metadata)<>'object' then
    raise exception 'Capabilities and metadata must be JSON objects.' using errcode='22023';
  end if;
  if lower(v_metadata::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret|pkce_verifier|password)"[[:space:]]*:' then
    raise exception 'Provider secrets are not allowed in connection-session metadata.' using errcode='22023';
  end if;

  if v_kind='human' then
    if p_organization_id is not null then
      raise exception 'Human provider connection may not name Organization custody.' using errcode='22023';
    end if;
    if not exists(
      select 1 from atlas.principals p
      where p.user_id=v_user_id and p.status='active'
    ) then
      raise exception 'Active Principal required.' using errcode='42501';
    end if;

    insert into atlas.provider_connection_sessions(
      actor_user_id,custodian_kind,custodian_user_id,custodian_organization_id,
      provider_key,state_nonce_digest,pkce_challenge,redirect_uri,
      requested_scopes,requested_capabilities,expires_at,metadata
    ) values (
      v_user_id,'human',v_user_id,null,
      v_provider,v_digest,nullif(btrim(coalesce(p_pkce_challenge,'')),''),
      nullif(btrim(coalesce(p_redirect_uri,'')),''),
      coalesce(p_requested_scopes,'{}'::text[]),
      coalesce(p_requested_capabilities,'{}'::jsonb),
      now()+make_interval(secs=>v_expiry),
      v_metadata
    ) returning * into v_session;
  else
    if p_organization_id is null
       or not atlas.organization_connected_source_authorized_self_v1(p_organization_id) then
      raise exception 'Organization provider connection authority required.' using errcode='42501';
    end if;

    insert into atlas.provider_connection_sessions(
      actor_user_id,custodian_kind,custodian_user_id,custodian_organization_id,
      provider_key,state_nonce_digest,pkce_challenge,redirect_uri,
      requested_scopes,requested_capabilities,expires_at,metadata
    ) values (
      v_user_id,'organization',null,p_organization_id,
      v_provider,v_digest,nullif(btrim(coalesce(p_pkce_challenge,'')),''),
      nullif(btrim(coalesce(p_redirect_uri,'')),''),
      coalesce(p_requested_scopes,'{}'::text[]),
      coalesce(p_requested_capabilities,'{}'::jsonb),
      now()+make_interval(secs=>v_expiry),
      v_metadata
    ) returning * into v_session;
  end if;

  return jsonb_build_object(
    'contractVersion','provider_connection_session_v1',
    'sessionId',v_session.id,
    'custodianKind',v_session.custodian_kind,
    'custodianOrganizationId',v_session.custodian_organization_id,
    'providerKey',v_session.provider_key,
    'requestedScopes',v_session.requested_scopes,
    'requestedCapabilities',v_session.requested_capabilities,
    'sessionState',v_session.session_state,
    'expiresAt',v_session.expires_at
  );
end;
$function$;

revoke all on function atlas.begin_provider_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) from public,anon;
grant execute on function atlas.begin_provider_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) to authenticated,service_role;

create or replace function atlas.complete_provider_connection_identity_service_v1(
  p_session_id uuid,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_session atlas.provider_connection_sessions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_account text:=btrim(coalesce(p_provider_account_key,''));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_scopes text[]:=coalesce(p_granted_scopes,'{}'::text[]);
  v_capabilities jsonb:=coalesce(p_capabilities,'{}'::jsonb);
begin
  select * into v_session
  from atlas.provider_connection_sessions
  where id=p_session_id
  for update;

  if v_session.id is null then
    raise exception 'Provider connection session not found.' using errcode='P0002';
  end if;
  if v_session.session_state='connected' and v_session.connected_source_id is not null then
    return jsonb_build_object(
      'contractVersion','provider_connection_identity_v1',
      'sessionId',v_session.id,
      'connectedSourceId',v_session.connected_source_id,
      'sessionState','connected',
      'alreadyCompleted',true
    );
  end if;
  if v_session.session_state not in ('pending','identity_verified') then
    raise exception 'Provider connection session is not completable.' using errcode='55000';
  end if;
  if now()>v_session.expires_at then
    raise exception 'Provider connection session expired.' using errcode='55000';
  end if;
  if v_account='' then
    raise exception 'Provider account identity is required.' using errcode='22023';
  end if;
  if jsonb_typeof(v_capabilities)<>'object' or jsonb_typeof(v_metadata)<>'object' then
    raise exception 'Capabilities and metadata must be JSON objects.' using errcode='22023';
  end if;
  if lower(v_metadata::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret|pkce_verifier|password)"[[:space:]]*:' then
    raise exception 'Provider secrets are not allowed in Connected Source metadata.' using errcode='22023';
  end if;
  if not (v_scopes <@ v_session.requested_scopes) then
    raise exception 'Granted provider scopes exceed the requested session scope.' using errcode='22023';
  end if;
  if not (v_session.requested_capabilities @> v_capabilities) then
    raise exception 'Granted Atlas capabilities exceed the requested session capability.' using errcode='22023';
  end if;

  if v_session.custodian_kind='human' then
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,custodian_organization_unit_id,
      provider_key,provider_account_key,display_label,account_hint,
      authorization_state,granted_scopes,capabilities,metadata
    ) values (
      v_session.custodian_user_id,null,null,
      v_session.provider_key,v_account,
      nullif(btrim(coalesce(p_display_label,'')),''),
      nullif(btrim(coalesce(p_account_hint,'')),''),
      'pending',v_scopes,v_capabilities,
      jsonb_build_object(
        'providerConnectionContract','current_canon_v1',
        'lastConnectionSessionId',v_session.id
      )||v_metadata
    )
    on conflict (custodian_user_id,provider_key,provider_account_key)
      where custodian_user_id is not null
    do update set
      display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),
      account_hint=coalesce(excluded.account_hint,atlas.connected_sources.account_hint),
      granted_scopes=excluded.granted_scopes,
      capabilities=atlas.connected_sources.capabilities||excluded.capabilities,
      metadata=atlas.connected_sources.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_source;
  else
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,custodian_organization_unit_id,
      provider_key,provider_account_key,display_label,account_hint,
      authorization_state,granted_scopes,capabilities,metadata
    ) values (
      null,v_session.custodian_organization_id,null,
      v_session.provider_key,v_account,
      nullif(btrim(coalesce(p_display_label,'')),''),
      nullif(btrim(coalesce(p_account_hint,'')),''),
      'pending',v_scopes,v_capabilities,
      jsonb_build_object(
        'providerConnectionContract','current_canon_v1',
        'lastConnectionSessionId',v_session.id
      )||v_metadata
    )
    on conflict (custodian_organization_id,provider_key,provider_account_key)
      where custodian_organization_id is not null
    do update set
      display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),
      account_hint=coalesce(excluded.account_hint,atlas.connected_sources.account_hint),
      granted_scopes=excluded.granted_scopes,
      capabilities=atlas.connected_sources.capabilities||excluded.capabilities,
      metadata=atlas.connected_sources.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_source;
  end if;

  if v_source.authorization_state='revoked' then
    raise exception 'Revoked Connected Source cannot be silently reactivated.' using errcode='55000';
  end if;

  update atlas.provider_connection_sessions
  set session_state='identity_verified',
      provider_account_key=v_account,
      connected_source_id=v_source.id,
      metadata=metadata||jsonb_build_object('identityVerifiedAt',now()),
      updated_at=now()
  where id=v_session.id
  returning * into v_session;

  return jsonb_build_object(
    'contractVersion','provider_connection_identity_v1',
    'sessionId',v_session.id,
    'connectedSourceId',v_source.id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'sessionState',v_session.session_state,
    'alreadyCompleted',false
  );
end;
$function$;

revoke all on function atlas.complete_provider_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.complete_provider_connection_identity_service_v1(
  uuid,text,text,text,text[],jsonb,jsonb
) to service_role;

create or replace function atlas.activate_provider_connection_service_v1(
  p_session_id uuid,
  p_required_credential_kind text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_session atlas.provider_connection_sessions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_kind text:=btrim(coalesce(p_required_credential_kind,''));
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
begin
  select * into v_session
  from atlas.provider_connection_sessions
  where id=p_session_id
  for update;

  if v_session.id is null or v_session.connected_source_id is null then
    raise exception 'Provider connection identity must be verified first.' using errcode='55000';
  end if;
  if v_session.session_state='connected' then
    return jsonb_build_object(
      'contractVersion','provider_connection_activation_v1',
      'sessionId',v_session.id,
      'connectedSourceId',v_session.connected_source_id,
      'sessionState','connected',
      'alreadyActivated',true
    );
  end if;
  if v_session.session_state<>'identity_verified' then
    raise exception 'Provider connection is not ready for activation.' using errcode='55000';
  end if;
  if now()>v_session.expires_at then
    raise exception 'Provider connection session expired before activation.' using errcode='55000';
  end if;
  if v_kind='' then
    raise exception 'Required provider credential kind is required.' using errcode='22023';
  end if;
  if jsonb_typeof(v_metadata)<>'object'
     or lower(v_metadata::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret|pkce_verifier|password)"[[:space:]]*:' then
    raise exception 'Activation metadata must be a secret-free JSON object.' using errcode='22023';
  end if;
  if not exists(
    select 1
    from atlas.connected_source_secret_refs r
    where r.connected_source_id=v_session.connected_source_id
      and r.credential_kind=v_kind
  ) then
    raise exception 'Required provider credential is not in governed secret custody.' using errcode='55000';
  end if;

  select * into v_source
  from atlas.connected_sources
  where id=v_session.connected_source_id
  for update;

  if v_source.id is null then
    raise exception 'Connected Source is unavailable.' using errcode='P0002';
  end if;
  if v_session.custodian_kind='human'
     and (v_source.custodian_user_id is distinct from v_session.custodian_user_id
       or v_source.custodian_organization_id is not null) then
    raise exception 'Connected Source no longer matches intended human custody.' using errcode='42501';
  end if;
  if v_session.custodian_kind='organization'
     and (v_source.custodian_organization_id is distinct from v_session.custodian_organization_id
       or v_source.custodian_user_id is not null) then
    raise exception 'Connected Source no longer matches intended Organization custody.' using errcode='42501';
  end if;
  if v_source.provider_key is distinct from v_session.provider_key
     or v_source.provider_account_key is distinct from v_session.provider_account_key then
    raise exception 'Connected Source identity no longer matches provider verification.' using errcode='42501';
  end if;
  if v_source.authorization_state='revoked' then
    raise exception 'Revoked Connected Source cannot be silently reactivated.' using errcode='55000';
  end if;
  if v_source.authorization_state not in ('pending','connected','reauthorization_required','error') then
    raise exception 'Connected Source cannot be activated from its current state.' using errcode='55000';
  end if;

  if v_source.authorization_state<>'connected' then
    update atlas.connected_sources
    set authorization_state='connected',
        revoked_at=null,
        metadata=metadata||jsonb_build_object(
          'providerConnectionContract','current_canon_v1',
          'activatedFromConnectionSessionId',v_session.id,
          'activatedAt',now()
        )||v_metadata,
        updated_at=now()
    where id=v_source.id
    returning * into v_source;
  end if;

  update atlas.provider_connection_sessions
  set session_state='connected',
      completed_at=now(),
      metadata=metadata||jsonb_build_object('activatedAt',now()),
      updated_at=now()
  where id=v_session.id
  returning * into v_session;

  return jsonb_build_object(
    'contractVersion','provider_connection_activation_v1',
    'sessionId',v_session.id,
    'connectedSourceId',v_source.id,
    'authorizationState',v_source.authorization_state,
    'sessionState',v_session.session_state,
    'alreadyActivated',false
  );
end;
$function$;

revoke all on function atlas.activate_provider_connection_service_v1(
  uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.activate_provider_connection_service_v1(
  uuid,text,jsonb
) to service_role;

create or replace function atlas.bind_implementation_case_connected_source_self_api_v1(
  p_implementation_case_source_id uuid,
  p_connected_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_case_source atlas.implementation_case_sources%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_source_state text;
  v_custody_kind text;
begin
  if v_user_id is null
     or not atlas.implementation_source_authorized_self_v1(p_implementation_case_source_id) then
    raise exception 'Setup-sponsor authority required.' using errcode='42501';
  end if;

  select * into v_case_source
  from atlas.implementation_case_sources
  where id=p_implementation_case_source_id
  for update;

  if v_case_source.id is null or v_case_source.source_state='removed' then
    raise exception 'Implementation source requirement is unavailable.' using errcode='P0002';
  end if;

  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id;

  if v_source.id is null then
    raise exception 'Connected Source is unavailable.' using errcode='P0002';
  end if;
  if lower(btrim(v_case_source.provider_key)) is distinct from lower(btrim(v_source.provider_key)) then
    raise exception 'Connected Source provider does not match the implementation source requirement.' using errcode='22023';
  end if;

  if v_source.custodian_user_id is not null then
    if v_source.custodian_user_id is distinct from v_user_id then
      raise exception 'Human Connected Source is not owned by the authenticated setup sponsor.' using errcode='42501';
    end if;
    v_custody_kind:='human';
  else
    if v_source.custodian_organization_id is null
       or not atlas.organization_connected_source_authorized_self_v1(v_source.custodian_organization_id) then
      raise exception 'Organization Connected Source authority required.' using errcode='42501';
    end if;
    v_custody_kind:='organization';
  end if;

  v_source_state:=case
    when v_source.authorization_state='connected' then 'connected'
    when v_source.authorization_state='pending' then 'authorization_pending'
    else 'blocked'
  end;

  update atlas.implementation_case_sources
  set connected_source_id=v_source.id,
      authorized_by_user_id=v_user_id,
      source_state=v_source_state,
      usable_at=case when v_source_state='connected' then coalesce(usable_at,now()) else null end,
      blocker=case when v_source_state='blocked' then v_source.authorization_state else null end,
      authorization_context=authorization_context||jsonb_build_object(
        'bindingContract','implementation_connected_source_binding_v1',
        'connectedSourceId',v_source.id,
        'custodyKind',v_custody_kind,
        'custodianOrganizationId',v_source.custodian_organization_id,
        'boundByUserId',v_user_id
      ),
      updated_at=now()
  where id=v_case_source.id
  returning * into v_case_source;

  return jsonb_build_object(
    'contractVersion','implementation_connected_source_binding_v1',
    'implementationCaseSourceId',v_case_source.id,
    'connectedSourceId',v_source.id,
    'custodyKind',v_custody_kind,
    'authorizationState',v_source.authorization_state,
    'sourceState',v_case_source.source_state,
    'sourceOwnershipChanged',false
  );
end;
$function$;

revoke all on function atlas.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function atlas.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)
  to authenticated,service_role;

-- Retire the two implementation APIs that previously created or directly transitioned
-- Connected Source custody from implementation context. Preserve signatures fail-closed
-- so stale Product callers receive an explicit architectural error rather than a second writer.
create or replace function atlas.register_implementation_connected_source_self_api_v1(
  p_implementation_case_source_id uuid,
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text,
  p_account_hint text,
  p_authorization_state text,
  p_granted_scopes text[],
  p_capabilities jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
begin
  raise exception 'Direct implementation provider registration is retired. Establish provider custody through the provider connection session and then bind the resulting Connected Source.'
    using errcode='0A000';
end;
$function$;

create or replace function atlas.transition_implementation_connected_source_authorization_self_a(
  p_implementation_case_source_id uuid,
  p_source_id uuid,
  p_to_state text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
begin
  raise exception 'Implementation context may not transition Connected Source authorization. Provider authorization changes belong to the Connected Source/provider custody seam.'
    using errcode='0A000';
end;
$function$;

create or replace function public.begin_provider_connection_self_api_v1(
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
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.begin_provider_connection_self_api_v1(
    p_custodian_kind,p_organization_id,p_provider_key,p_requested_scopes,
    p_requested_capabilities,p_state_nonce_digest,p_pkce_challenge,p_redirect_uri,
    p_expires_in_seconds,p_metadata
  );
$function$;

revoke all on function public.begin_provider_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) from public,anon;
grant execute on function public.begin_provider_connection_self_api_v1(
  text,uuid,text,text[],jsonb,text,text,text,integer,jsonb
) to authenticated,service_role;

create or replace function public.bind_implementation_case_connected_source_self_api_v1(
  p_implementation_case_source_id uuid,
  p_connected_source_id uuid
)
returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.bind_implementation_case_connected_source_self_api_v1(
    p_implementation_case_source_id,p_connected_source_id
  );
$function$;

revoke all on function public.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)
  from public,anon;
grant execute on function public.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)
  to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.begin_provider_connection_self_api_v1(text, uuid, text, text[], jsonb, text, text, text, integer, jsonb)',
  'app_endpoint','verified','active',
  true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_provider_connection_activation_current_canon_v1',
    'purpose','Begin a short-lived provider authorization session under explicit human or Organization custody.',
    'truthBoundary','Begins provider authorization only; creates no provider identity, Connected Source, domain consequence, or provider credential.',
    'authority','auth.uid() plus active Principal for human custody or current Organization provider-connection authority for Organization custody.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),
  now(),false
),
(
  'atlas.bind_implementation_case_connected_source_self_api_v1(uuid, uuid)',
  'app_endpoint','verified','active',
  true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_provider_connection_activation_current_canon_v1',
    'purpose','Bind an implementation source requirement to an already established Connected Source without changing source ownership or authorization.',
    'truthBoundary','Implementation source admission is requirement context, not provider-account custody.',
    'authority','Authenticated setup sponsor plus lawful custody authority over the selected Connected Source.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),
  now(),false
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
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,0,
  jsonb_build_object(
    'source','atlas_provider_connection_activation_current_canon_v1',
    'purpose','Resolve provider-verified account identity into one pending/reused Connected Source under the session''s fixed custody.',
    'truthBoundary','Provider identity verification does not activate the source and does not create domain truth.',
    'classificationRuleVersion',3
  ),
  now(),false
),
(
  'atlas.activate_provider_connection_service_v1(uuid,text,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,0,
  jsonb_build_object(
    'source','atlas_provider_connection_activation_current_canon_v1',
    'purpose','Activate a provider connection only after required reusable credential custody exists.',
    'truthBoundary','Activation changes Connected Source authorization only; downstream domain authority remains separate.',
    'classificationRuleVersion',3
  ),
  now(),false
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
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;

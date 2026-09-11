begin;

create or replace function atlas.validate_provider_connection_callback_service_v1(
  p_session_id uuid,
  p_provider_key text,
  p_state_nonce_digest text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_session atlas.provider_connection_sessions%rowtype;
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_digest text:=lower(btrim(coalesce(p_state_nonce_digest,'')));
begin
  select * into v_session
  from atlas.provider_connection_sessions
  where id=p_session_id
  for update;

  if v_session.id is null then
    raise exception 'Provider connection session not found.' using errcode='P0002';
  end if;
  if v_session.session_state<>'pending' then
    raise exception 'Provider callback session is no longer pending.' using errcode='55000';
  end if;
  if now()>v_session.expires_at then
    update atlas.provider_connection_sessions
    set session_state='expired',updated_at=now()
    where id=v_session.id;
    raise exception 'Provider connection session expired.' using errcode='55000';
  end if;
  if v_provider='' or v_provider is distinct from v_session.provider_key then
    raise exception 'Provider callback does not match the connection session.' using errcode='42501';
  end if;
  if v_digest !~ '^[0-9a-f]{64}$' or v_digest is distinct from v_session.state_nonce_digest then
    raise exception 'Provider callback state is invalid.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','provider_connection_callback_validation_v1',
    'sessionId',v_session.id,
    'providerKey',v_session.provider_key,
    'custodianKind',v_session.custodian_kind,
    'custodianUserId',v_session.custodian_user_id,
    'organizationId',v_session.custodian_organization_id,
    'redirectUri',v_session.redirect_uri,
    'sessionState',v_session.session_state,
    'expiresAt',v_session.expires_at,
    'validated',true
  );
end;
$function$;
revoke all on function atlas.validate_provider_connection_callback_service_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.validate_provider_connection_callback_service_v1(uuid,text,text) to service_role;

create or replace function atlas.store_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text,
  p_secret text,
  p_description text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,vault
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_kind text:=lower(btrim(coalesce(p_credential_kind,'')));
  v_existing_secret_id uuid;
  v_secret_id uuid;
  v_name text;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id for update;
  if v_source.id is null then raise exception 'Connected source not found.' using errcode='P0002'; end if;
  if v_kind='' or p_secret is null or p_secret='' then raise exception 'Credential kind and secret are required.' using errcode='22023'; end if;
  if v_source.authorization_state='revoked' then raise exception 'Revoked source cannot receive new credentials.' using errcode='55000'; end if;

  v_name:='atlas-connected-source-'||v_source.id::text||'-'||regexp_replace(v_kind,'[^a-z0-9_-]+','-','g');
  select vault_secret_id into v_existing_secret_id
  from atlas.connected_source_secret_refs
  where connected_source_id=v_source.id and credential_kind=v_kind
  for update;

  if v_existing_secret_id is null then
    select vault.create_secret(p_secret,v_name,coalesce(nullif(btrim(p_description),''),'Atlas provider credential'),null)
      into v_secret_id;
    insert into atlas.connected_source_secret_refs(connected_source_id,credential_kind,vault_secret_id)
    values(v_source.id,v_kind,v_secret_id);
  else
    perform vault.update_secret(v_existing_secret_id,p_secret,v_name,coalesce(nullif(btrim(p_description),''),'Atlas provider credential'),null);
    v_secret_id:=v_existing_secret_id;
    update atlas.connected_source_secret_refs set updated_at=now()
    where connected_source_id=v_source.id and credential_kind=v_kind;
  end if;

  return jsonb_build_object(
    'contractVersion','connected_source_secret_custody_v1',
    'connectedSourceId',v_source.id,
    'credentialKind',v_kind,
    'stored',true
  );
end;
$function$;
revoke all on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) from public,anon,authenticated;
grant execute on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) to service_role;

create or replace function atlas.resolve_provider_webhook_source_service_v1(
  p_provider_key text,
  p_provider_account_key text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_account text:=btrim(coalesce(p_provider_account_key,''));
  v_count integer;
  v_source atlas.connected_sources%rowtype;
begin
  if v_provider='' or v_account='' then raise exception 'Provider and account key are required.' using errcode='22023'; end if;
  select count(*),(array_agg(id order by id))[1]
  into v_count,v_source.id
  from atlas.connected_sources
  where provider_key=v_provider and provider_account_key=v_account and authorization_state='connected';

  if v_count=0 then raise exception 'No connected source matches this provider account.' using errcode='P0002'; end if;
  if v_count<>1 then raise exception 'Provider account webhook custody is ambiguous.' using errcode='55000'; end if;

  select * into v_source from atlas.connected_sources where id=v_source.id;
  return jsonb_build_object(
    'contractVersion','provider_webhook_source_resolution_v1',
    'connectedSourceId',v_source.id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'custodianKind',case when v_source.custodian_user_id is not null then 'human' else 'organization' end,
    'custodianUserId',v_source.custodian_user_id,
    'organizationId',v_source.custodian_organization_id
  );
end;
$function$;
revoke all on function atlas.resolve_provider_webhook_source_service_v1(text,text) from public,anon,authenticated;
grant execute on function atlas.resolve_provider_webhook_source_service_v1(text,text) to service_role;

create or replace function public.validate_provider_connection_callback_service_v1(p_session_id uuid,p_provider_key text,p_state_nonce_digest text)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.validate_provider_connection_callback_service_v1(p_session_id,p_provider_key,p_state_nonce_digest);
$function$;
revoke all on function public.validate_provider_connection_callback_service_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function public.validate_provider_connection_callback_service_v1(uuid,text,text) to service_role;

create or replace function public.store_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text,p_secret text,p_description text default null)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.store_connected_source_secret_service_v1(p_connected_source_id,p_credential_kind,p_secret,p_description);
$function$;
revoke all on function public.store_connected_source_secret_service_v1(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.store_connected_source_secret_service_v1(uuid,text,text,text) to service_role;

create or replace function public.resolve_provider_webhook_source_service_v1(p_provider_key text,p_provider_account_key text)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$
  select atlas.resolve_provider_webhook_source_service_v1(p_provider_key,p_provider_account_key);
$function$;
revoke all on function public.resolve_provider_webhook_source_service_v1(text,text) from public,anon,authenticated;
grant execute on function public.resolve_provider_webhook_source_service_v1(text,text) to service_role;

commit;

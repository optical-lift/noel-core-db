create or replace function atlas.register_delegated_agent_carrier_service_v1(
  p_stable_key text,
  p_display_name text,
  p_carrier_kind text,
  p_provider_key text,
  p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = atlas, public, pg_temp
as $$
declare
  v_id uuid;
begin
  insert into atlas.delegated_agent_carriers(
    stable_key,display_name,carrier_kind,provider_key,metadata
  ) values (
    lower(btrim(p_stable_key)),
    btrim(p_display_name),
    p_carrier_kind,
    nullif(btrim(p_provider_key),''),
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict(stable_key) do update
  set display_name = excluded.display_name,
      provider_key = excluded.provider_key,
      metadata = atlas.delegated_agent_carriers.metadata || excluded.metadata,
      updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function atlas.issue_delegated_agent_credential_service_v1(
  p_authorization_id uuid,
  p_token_hash text,
  p_expires_at timestamptz,
  p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = atlas, public, pg_temp
as $$
declare
  v_id uuid;
begin
  if lower(p_token_hash) !~ '^[0-9a-f]{64}$' then
    raise exception 'token hash must be lowercase SHA-256 hex';
  end if;
  if not exists(
    select 1
    from atlas.delegated_agent_authorizations
    where id = p_authorization_id
      and authorization_state = 'active'
      and now() >= begins_at
      and (ends_at is null or now() < ends_at)
  ) then
    raise exception 'active authorization required';
  end if;

  insert into atlas.delegated_agent_credentials(
    authorization_id,token_hash,expires_at,metadata
  ) values (
    p_authorization_id,lower(p_token_hash),p_expires_at,coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$$;
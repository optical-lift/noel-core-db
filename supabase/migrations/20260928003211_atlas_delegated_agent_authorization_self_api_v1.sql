create or replace function atlas.establish_delegated_agent_authorization_self_api_v1(
  p_carrier_id uuid,
  p_ledger_id uuid,
  p_delegating_seat_id uuid,
  p_max_execution_class text,
  p_allowed_command_keys text[],
  p_denied_command_keys text[],
  p_scope jsonb,
  p_confirmation_policy jsonb,
  p_purpose text,
  p_ends_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = atlas, ledger, auth, public, pg_temp
as $$
declare
  v_user uuid:=auth.uid();
  v_principal atlas.principals%rowtype;
  v_seat ledger.seats%rowtype;
  v_id uuid;
  v_unknown integer;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_principal from atlas.principals where user_id=v_user and status='active' limit 1;
  if not found then raise exception 'active principal required'; end if;
  if not exists(select 1 from atlas.delegated_agent_carriers where id=p_carrier_id and status='active') then raise exception 'active carrier required'; end if;
  if p_max_execution_class not in ('read','prepare','commit') then raise exception 'invalid execution class'; end if;
  if coalesce(array_length(p_allowed_command_keys,1),0)=0 then raise exception 'at least one explicit allowed command is required'; end if;
  if coalesce(p_allowed_command_keys,'{}'::text[]) && coalesce(p_denied_command_keys,'{}'::text[]) then raise exception 'allowed and denied command sets overlap'; end if;
  if p_ledger_id is not null and not atlas.principal_has_ledger_authority_v1(v_principal.id,p_ledger_id) then raise exception 'principal lacks ledger authority'; end if;

  if p_delegating_seat_id is not null then
    select * into v_seat from ledger.seats where id=p_delegating_seat_id;
    if v_seat.id is null or v_seat.seat_state<>'active' or v_seat.ledger_id<>p_ledger_id then raise exception 'active delegating seat on ledger required'; end if;
    if v_principal.person_id is not null and v_seat.person_entity_id<>v_principal.person_id then raise exception 'delegating seat must be held by current principal'; end if;
  end if;

  select count(*) into v_unknown
  from unnest(coalesce(p_allowed_command_keys,'{}'::text[]) || coalesce(p_denied_command_keys,'{}'::text[])) k
  where not exists(
    select 1 from atlas.agent_command_definitions d
    where d.command_key=k and d.command_version=1 and d.status='active'
  );
  if v_unknown>0 then raise exception 'authorization references unknown or inactive commands'; end if;

  if p_ends_at is not null and p_ends_at<=now() then raise exception 'authorization end must be in the future'; end if;
  if btrim(coalesce(p_purpose,''))='' then raise exception 'delegation purpose is required'; end if;

  insert into atlas.delegated_agent_authorizations(
    carrier_id,principal_id,ledger_id,delegating_seat_id,max_execution_class,
    allowed_command_keys,denied_command_keys,scope,confirmation_policy,purpose,basis,ends_at,created_by_user_id
  ) values (
    p_carrier_id,v_principal.id,p_ledger_id,p_delegating_seat_id,p_max_execution_class,
    coalesce(p_allowed_command_keys,'{}'::text[]),coalesce(p_denied_command_keys,'{}'::text[]),
    coalesce(p_scope,'{}'::jsonb),coalesce(p_confirmation_policy,'{}'::jsonb),btrim(p_purpose),
    jsonb_build_object('establishedBy','principal_self_api','userId',v_user),p_ends_at,v_user
  ) returning id into v_id;

  return v_id;
end;
$$;

create or replace function atlas.revoke_delegated_agent_authorization_self_api_v1(
  p_authorization_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
declare
  v_user uuid:=auth.uid();
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_principal atlas.principals%rowtype;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_auth from atlas.delegated_agent_authorizations where id=p_authorization_id for update;
  if not found then raise exception 'authorization not found'; end if;
  select * into v_principal from atlas.principals where id=v_auth.principal_id;
  if v_principal.user_id<>v_user then raise exception 'authorization does not belong to current principal'; end if;
  if v_auth.authorization_state='revoked' then return jsonb_build_object('authorizationId',v_auth.id,'state','revoked','replayed',true); end if;
  update atlas.delegated_agent_authorizations
  set authorization_state='revoked',revoked_at=now(),updated_at=now(),
      basis=basis||jsonb_build_object('revokedReason',btrim(coalesce(p_reason,'')),'revokedByUserId',v_user)
  where id=v_auth.id;
  update atlas.delegated_agent_credentials
  set credential_state='revoked',revoked_at=now()
  where authorization_id=v_auth.id and credential_state='active';
  return jsonb_build_object('authorizationId',v_auth.id,'state','revoked','replayed',false);
end;
$$;

create or replace function atlas.delegated_agent_authorizations_self_api_v1()
returns table(
  authorization_id uuid,
  carrier_id uuid,
  carrier_key text,
  carrier_name text,
  ledger_id uuid,
  delegating_seat_id uuid,
  authorization_state text,
  max_execution_class text,
  allowed_command_keys text[],
  denied_command_keys text[],
  scope jsonb,
  confirmation_policy jsonb,
  purpose text,
  begins_at timestamptz,
  ends_at timestamptz
)
language sql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
  select a.id,a.carrier_id,c.stable_key,c.display_name,a.ledger_id,a.delegating_seat_id,
         a.authorization_state,a.max_execution_class,a.allowed_command_keys,a.denied_command_keys,
         a.scope,a.confirmation_policy,a.purpose,a.begins_at,a.ends_at
  from atlas.delegated_agent_authorizations a
  join atlas.delegated_agent_carriers c on c.id=a.carrier_id
  join atlas.principals p on p.id=a.principal_id
  where p.user_id=auth.uid()
  order by a.created_at desc;
$$;
begin;

create table if not exists atlas.delegated_agent_carriers (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  display_name text not null,
  carrier_kind text not null check (carrier_kind in ('ai_agent','automation','tool_process')),
  provider_key text,
  status text not null default 'active' check (status in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  check (stable_key ~ '^[a-z][a-z0-9_]*$')
);

comment on table atlas.delegated_agent_carriers is
'Carrier identities for delegated technical agents. A carrier is never a principal, Person, or source of authority.';

create table if not exists atlas.delegated_agent_authorizations (
  id uuid primary key default gen_random_uuid(),
  carrier_id uuid not null references atlas.delegated_agent_carriers(id),
  principal_id uuid not null references atlas.principals(id),
  ledger_id uuid references ledger.ledgers(id),
  delegating_seat_id uuid references ledger.seats(id),
  authorization_state text not null default 'active' check (authorization_state in ('active','suspended','revoked','expired')),
  max_execution_class text not null default 'prepare' check (max_execution_class in ('read','prepare','commit')),
  allowed_command_keys text[] not null default '{}'::text[],
  denied_command_keys text[] not null default '{}'::text[],
  scope jsonb not null default '{}'::jsonb,
  confirmation_policy jsonb not null default '{}'::jsonb,
  purpose text not null,
  basis jsonb not null default '{}'::jsonb,
  begins_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (ends_at is null or ends_at > begins_at),
  check (not (allowed_command_keys && denied_command_keys))
);

create index if not exists delegated_agent_authorizations_lookup_idx
  on atlas.delegated_agent_authorizations (carrier_id, principal_id, ledger_id, authorization_state);

create table if not exists atlas.delegated_agent_credentials (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references atlas.delegated_agent_authorizations(id),
  token_hash text not null unique,
  credential_state text not null default 'active' check (credential_state in ('active','rotated','revoked','expired')),
  begins_at timestamptz not null default now(),
  expires_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  rotated_at timestamptz,
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  check (token_hash ~ '^[0-9a-f]{64}$'),
  check (expires_at is null or expires_at > begins_at)
);

create index if not exists delegated_agent_credentials_authorization_idx
  on atlas.delegated_agent_credentials (authorization_id, credential_state);

create table if not exists atlas.agent_command_definitions (
  command_key text not null,
  command_version integer not null default 1,
  label text not null,
  scope_kind text not null default 'ledger' check (scope_kind in ('personal','ledger','either')),
  execution_class text not null check (execution_class in ('read','prepare','commit')),
  confirmation_requirement text not null default 'none' check (confirmation_requirement in ('none','principal_explicit')),
  operation_class_key text references atlas.operation_classes(stable_key),
  capability_key text,
  capability_version integer,
  handler_key text not null,
  status text not null default 'active' check (status in ('draft','active','retired')),
  input_contract jsonb not null default '{}'::jsonb,
  target_contract jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  primary key (command_key, command_version),
  check (command_key ~ '^[a-z][a-z0-9_.]*$'),
  check ((capability_key is null and capability_version is null) or (capability_key is not null and capability_version is not null))
);

create table if not exists atlas.agent_command_invocations (
  id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references atlas.delegated_agent_authorizations(id),
  credential_id uuid not null references atlas.delegated_agent_credentials(id),
  carrier_id uuid not null references atlas.delegated_agent_carriers(id),
  principal_id uuid not null references atlas.principals(id),
  ledger_id uuid references ledger.ledgers(id),
  delegating_seat_id uuid references ledger.seats(id),
  command_key text not null,
  command_version integer not null,
  idempotency_key text not null,
  target jsonb not null default '{}'::jsonb,
  input jsonb not null default '{}'::jsonb,
  authority_snapshot jsonb not null default '{}'::jsonb,
  invocation_state text not null check (invocation_state in ('rejected','needs_confirmation','authorized','executing','succeeded','failed','cancelled')),
  confirmation_required boolean not null default false,
  confirmed_by_user_id uuid,
  confirmed_at timestamptz,
  result jsonb not null default '{}'::jsonb,
  failure jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  authorized_at timestamptz,
  execution_started_at timestamptz,
  completed_at timestamptz,
  unique (authorization_id, idempotency_key),
  foreign key (command_key, command_version) references atlas.agent_command_definitions(command_key, command_version)
);

create index if not exists agent_command_invocations_principal_idx
  on atlas.agent_command_invocations (principal_id, created_at desc);
create index if not exists agent_command_invocations_state_idx
  on atlas.agent_command_invocations (invocation_state, created_at desc);

create table if not exists atlas.agent_command_invocation_events (
  id uuid primary key default gen_random_uuid(),
  invocation_id uuid not null references atlas.agent_command_invocations(id),
  event_kind text not null,
  from_state text,
  to_state text not null,
  actor_kind text not null check (actor_kind in ('agent','principal','service')),
  actor_user_id uuid,
  reason text,
  evidence jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create or replace function atlas.reject_agent_command_event_mutation_v1()
returns trigger language plpgsql as $$
begin
  raise exception 'agent command invocation events are append-only';
end;
$$;

drop trigger if exists agent_command_invocation_events_immutable on atlas.agent_command_invocation_events;
create trigger agent_command_invocation_events_immutable
before update or delete on atlas.agent_command_invocation_events
for each row execute function atlas.reject_agent_command_event_mutation_v1();

create or replace function atlas.execution_class_rank_v1(p_execution_class text)
returns integer language sql immutable strict as $$
  select case p_execution_class when 'read' then 1 when 'prepare' then 2 when 'commit' then 3 else 99 end;
$$;

create or replace function atlas.evaluate_delegated_agent_command_authority_v1(
  p_authorization_id uuid,
  p_command_key text,
  p_command_version integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_command atlas.agent_command_definitions%rowtype;
  v_carrier atlas.delegated_agent_carriers%rowtype;
  v_principal atlas.principals%rowtype;
  v_seat ledger.seats%rowtype;
  v_reasons jsonb := '[]'::jsonb;
  v_allowed boolean := true;
  v_confirmation_required boolean := false;
begin
  select * into v_auth from atlas.delegated_agent_authorizations where id = p_authorization_id;
  if not found then
    return jsonb_build_object('allowed', false, 'reasons', jsonb_build_array('authorization_not_found'));
  end if;

  select * into v_carrier from atlas.delegated_agent_carriers where id = v_auth.carrier_id;
  select * into v_principal from atlas.principals where id = v_auth.principal_id;
  select * into v_command from atlas.agent_command_definitions
    where command_key = p_command_key and command_version = p_command_version;

  if v_carrier.id is null or v_carrier.status <> 'active' then
    v_allowed := false; v_reasons := v_reasons || '"carrier_not_active"'::jsonb;
  end if;
  if v_principal.id is null or v_principal.status <> 'active' then
    v_allowed := false; v_reasons := v_reasons || '"principal_not_active"'::jsonb;
  end if;
  if v_command.command_key is null or v_command.status <> 'active' then
    v_allowed := false; v_reasons := v_reasons || '"command_not_active"'::jsonb;
  end if;
  if v_auth.authorization_state <> 'active' then
    v_allowed := false; v_reasons := v_reasons || '"authorization_not_active"'::jsonb;
  end if;
  if now() < v_auth.begins_at or (v_auth.ends_at is not null and now() >= v_auth.ends_at) then
    v_allowed := false; v_reasons := v_reasons || '"authorization_outside_time_window"'::jsonb;
  end if;
  if coalesce(array_length(v_auth.allowed_command_keys, 1), 0) > 0 and not (p_command_key = any(v_auth.allowed_command_keys)) then
    v_allowed := false; v_reasons := v_reasons || '"command_not_in_allowlist"'::jsonb;
  end if;
  if p_command_key = any(v_auth.denied_command_keys) then
    v_allowed := false; v_reasons := v_reasons || '"command_denied"'::jsonb;
  end if;
  if v_command.command_key is not null and atlas.execution_class_rank_v1(v_command.execution_class) > atlas.execution_class_rank_v1(v_auth.max_execution_class) then
    v_allowed := false; v_reasons := v_reasons || '"execution_class_exceeds_delegation"'::jsonb;
  end if;

  if v_auth.ledger_id is not null then
    if not atlas.principal_has_ledger_authority_v1(v_auth.principal_id, v_auth.ledger_id) then
      v_allowed := false; v_reasons := v_reasons || '"principal_lacks_ledger_authority"'::jsonb;
    end if;
    if v_command.command_key is not null and v_command.scope_kind = 'personal' then
      v_allowed := false; v_reasons := v_reasons || '"personal_command_cannot_use_ledger_delegation"'::jsonb;
    end if;
  elsif v_command.command_key is not null and v_command.scope_kind = 'ledger' then
    v_allowed := false; v_reasons := v_reasons || '"ledger_command_requires_ledger_delegation"'::jsonb;
  end if;

  if v_auth.delegating_seat_id is not null then
    select * into v_seat from ledger.seats where id = v_auth.delegating_seat_id;
    if v_seat.id is null or v_seat.seat_state <> 'active' then
      v_allowed := false; v_reasons := v_reasons || '"delegating_seat_not_active"'::jsonb;
    elsif v_auth.ledger_id is null or v_seat.ledger_id <> v_auth.ledger_id then
      v_allowed := false; v_reasons := v_reasons || '"delegating_seat_ledger_mismatch"'::jsonb;
    elsif v_principal.person_id is not null and v_seat.person_entity_id <> v_principal.person_id then
      v_allowed := false; v_reasons := v_reasons || '"delegating_seat_not_held_by_principal"'::jsonb;
    end if;
  end if;

  if v_command.capability_key is not null then
    if not atlas.capability_definition_active_v1(v_command.capability_key, v_command.capability_version) then
      v_allowed := false; v_reasons := v_reasons || '"required_capability_not_active"'::jsonb;
    elsif v_auth.ledger_id is not null and not atlas.capability_entitlement_grant_live_v1(v_auth.ledger_id, v_command.capability_key, v_command.capability_version) then
      v_allowed := false; v_reasons := v_reasons || '"ledger_not_entitled_for_capability"'::jsonb;
    end if;
  end if;

  v_confirmation_required := v_command.command_key is not null
    and v_command.confirmation_requirement = 'principal_explicit';

  return jsonb_build_object(
    'allowed', v_allowed,
    'reasons', v_reasons,
    'authorizationId', v_auth.id,
    'carrierId', v_auth.carrier_id,
    'principalId', v_auth.principal_id,
    'ledgerId', v_auth.ledger_id,
    'delegatingSeatId', v_auth.delegating_seat_id,
    'commandKey', p_command_key,
    'commandVersion', p_command_version,
    'executionClass', v_command.execution_class,
    'confirmationRequired', v_confirmation_required,
    'handlerKey', v_command.handler_key,
    'scope', v_auth.scope,
    'authoritySource', 'delegated_agent_authorization_v1'
  );
end;
$$;

create or replace function atlas.resolve_delegated_agent_credential_service_v1(p_token_hash text)
returns jsonb
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select jsonb_build_object(
    'credentialId', c.id,
    'authorizationId', a.id,
    'carrierId', a.carrier_id,
    'principalId', a.principal_id,
    'ledgerId', a.ledger_id,
    'delegatingSeatId', a.delegating_seat_id,
    'credentialState', c.credential_state,
    'authorizationState', a.authorization_state,
    'credentialExpiresAt', c.expires_at,
    'authorizationEndsAt', a.ends_at
  )
  from atlas.delegated_agent_credentials c
  join atlas.delegated_agent_authorizations a on a.id = c.authorization_id
  where c.token_hash = lower(p_token_hash)
    and c.credential_state = 'active'
    and now() >= c.begins_at
    and (c.expires_at is null or now() < c.expires_at)
    and a.authorization_state = 'active'
    and now() >= a.begins_at
    and (a.ends_at is null or now() < a.ends_at)
  limit 1;
$$;

create or replace function atlas.begin_delegated_agent_command_service_v1(
  p_token_hash text,
  p_command_key text,
  p_command_version integer,
  p_target jsonb,
  p_input jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare
  v_cred atlas.delegated_agent_credentials%rowtype;
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_eval jsonb;
  v_state text;
  v_invocation atlas.agent_command_invocations%rowtype;
begin
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'idempotency key is required';
  end if;

  select * into v_cred
  from atlas.delegated_agent_credentials
  where token_hash = lower(p_token_hash)
    and credential_state = 'active'
    and now() >= begins_at
    and (expires_at is null or now() < expires_at)
  limit 1;
  if not found then raise exception 'delegated agent credential is unavailable'; end if;

  select * into v_auth from atlas.delegated_agent_authorizations where id = v_cred.authorization_id;
  if not found then raise exception 'delegated agent authorization is unavailable'; end if;

  select * into v_invocation from atlas.agent_command_invocations
  where authorization_id = v_auth.id and idempotency_key = p_idempotency_key;
  if found then
    return jsonb_build_object('invocationId',v_invocation.id,'state',v_invocation.invocation_state,'replayed',true,'confirmationRequired',v_invocation.confirmation_required,'authority',v_invocation.authority_snapshot,'result',v_invocation.result,'failure',v_invocation.failure);
  end if;

  v_eval := atlas.evaluate_delegated_agent_command_authority_v1(v_auth.id,p_command_key,p_command_version);
  if coalesce((v_eval->>'allowed')::boolean,false) = false then
    v_state := 'rejected';
  elsif coalesce((v_eval->>'confirmationRequired')::boolean,false) then
    v_state := 'needs_confirmation';
  else
    v_state := 'authorized';
  end if;

  insert into atlas.agent_command_invocations(
    authorization_id,credential_id,carrier_id,principal_id,ledger_id,delegating_seat_id,
    command_key,command_version,idempotency_key,target,input,authority_snapshot,invocation_state,
    confirmation_required,authorized_at
  ) values (
    v_auth.id,v_cred.id,v_auth.carrier_id,v_auth.principal_id,v_auth.ledger_id,v_auth.delegating_seat_id,
    p_command_key,p_command_version,p_idempotency_key,coalesce(p_target,'{}'::jsonb),coalesce(p_input,'{}'::jsonb),v_eval,v_state,
    coalesce((v_eval->>'confirmationRequired')::boolean,false),case when v_state='authorized' then now() else null end
  ) returning * into v_invocation;

  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,to_state,actor_kind,reason,evidence)
  values (v_invocation.id,'command_requested',v_state,'agent',case when v_state='rejected' then 'authority evaluation rejected command' else null end,v_eval);

  update atlas.delegated_agent_credentials set last_used_at=now() where id=v_cred.id;

  return jsonb_build_object('invocationId',v_invocation.id,'state',v_state,'replayed',false,'confirmationRequired',v_invocation.confirmation_required,'authority',v_eval);
end;
$$;

create or replace function atlas.confirm_delegated_agent_command_self_api_v1(p_invocation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, auth, public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_inv atlas.agent_command_invocations%rowtype;
  v_principal atlas.principals%rowtype;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_inv from atlas.agent_command_invocations where id=p_invocation_id for update;
  if not found then raise exception 'invocation not found'; end if;
  select * into v_principal from atlas.principals where id=v_inv.principal_id;
  if v_principal.user_id <> v_user then raise exception 'invocation does not belong to current principal'; end if;
  if v_inv.invocation_state <> 'needs_confirmation' then raise exception 'invocation is not awaiting confirmation'; end if;
  if coalesce((atlas.evaluate_delegated_agent_command_authority_v1(v_inv.authorization_id,v_inv.command_key,v_inv.command_version)->>'allowed')::boolean,false) = false then
    raise exception 'delegated authority is no longer valid';
  end if;

  update atlas.agent_command_invocations
  set invocation_state='authorized', confirmed_by_user_id=v_user, confirmed_at=now(), authorized_at=now()
  where id=v_inv.id;

  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,from_state,to_state,actor_kind,actor_user_id,evidence)
  values (v_inv.id,'principal_confirmed','needs_confirmation','authorized','principal',v_user,jsonb_build_object('confirmedByUserId',v_user));

  return jsonb_build_object('invocationId',v_inv.id,'state','authorized','confirmed',true);
end;
$$;

create or replace function atlas.mark_delegated_agent_command_executing_service_v1(p_invocation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare v_inv atlas.agent_command_invocations%rowtype;
begin
  select * into v_inv from atlas.agent_command_invocations where id=p_invocation_id for update;
  if not found then raise exception 'invocation not found'; end if;
  if v_inv.invocation_state='executing' then return jsonb_build_object('invocationId',v_inv.id,'state','executing','replayed',true); end if;
  if v_inv.invocation_state <> 'authorized' then raise exception 'invocation is not authorized for execution'; end if;
  update atlas.agent_command_invocations set invocation_state='executing', execution_started_at=now() where id=v_inv.id;
  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,from_state,to_state,actor_kind)
  values(v_inv.id,'execution_started','authorized','executing','service');
  return jsonb_build_object('invocationId',v_inv.id,'state','executing','replayed',false);
end;
$$;

create or replace function atlas.complete_delegated_agent_command_service_v1(
  p_invocation_id uuid,
  p_succeeded boolean,
  p_result jsonb,
  p_failure jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare v_inv atlas.agent_command_invocations%rowtype; v_state text;
begin
  select * into v_inv from atlas.agent_command_invocations where id=p_invocation_id for update;
  if not found then raise exception 'invocation not found'; end if;
  if v_inv.invocation_state in ('succeeded','failed') then
    return jsonb_build_object('invocationId',v_inv.id,'state',v_inv.invocation_state,'replayed',true,'result',v_inv.result,'failure',v_inv.failure);
  end if;
  if v_inv.invocation_state <> 'executing' then raise exception 'invocation is not executing'; end if;
  v_state := case when p_succeeded then 'succeeded' else 'failed' end;
  update atlas.agent_command_invocations
  set invocation_state=v_state,
      result=case when p_succeeded then coalesce(p_result,'{}'::jsonb) else '{}'::jsonb end,
      failure=case when p_succeeded then '{}'::jsonb else coalesce(p_failure,'{}'::jsonb) end,
      completed_at=now()
  where id=v_inv.id;
  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,from_state,to_state,actor_kind,evidence)
  values(v_inv.id,case when p_succeeded then 'execution_succeeded' else 'execution_failed' end,'executing',v_state,'service',case when p_succeeded then coalesce(p_result,'{}'::jsonb) else coalesce(p_failure,'{}'::jsonb) end);
  return jsonb_build_object('invocationId',v_inv.id,'state',v_state,'replayed',false,'result',case when p_succeeded then coalesce(p_result,'{}'::jsonb) else '{}'::jsonb end,'failure',case when p_succeeded then '{}'::jsonb else coalesce(p_failure,'{}'::jsonb) end);
end;
$$;

create or replace function atlas.delegated_agent_command_invocation_service_v1(p_token_hash text,p_invocation_id uuid)
returns jsonb
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select jsonb_build_object(
    'invocationId',i.id,'state',i.invocation_state,'commandKey',i.command_key,'commandVersion',i.command_version,
    'confirmationRequired',i.confirmation_required,'confirmedAt',i.confirmed_at,'authority',i.authority_snapshot,
    'target',i.target,'input',i.input,'result',i.result,'failure',i.failure,'createdAt',i.created_at,'completedAt',i.completed_at
  )
  from atlas.agent_command_invocations i
  join atlas.delegated_agent_credentials c on c.id=i.credential_id
  where i.id=p_invocation_id and c.token_hash=lower(p_token_hash)
  limit 1;
$$;

create or replace function atlas.register_delegated_agent_carrier_service_v1(
  p_stable_key text,p_display_name text,p_carrier_kind text,p_provider_key text,p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = atlas, public, pg_temp
as $$
declare v_id uuid;
begin
  insert into atlas.delegated_agent_carriers(stable_key,display_name,carrier_kind,provider_key,metadata)
  values(lower(btrim(p_stable_key)),btrim(p_display_name),p_carrier_kind,nullif(btrim(p_provider_key),''),coalesce(p_metadata,'{}'::jsonb))
  on conflict(stable_key) do update set display_name=excluded.display_name,provider_key=excluded.provider_key,metadata=atlas.delegated_agent_carriers.metadata||excluded.metadata,updated_at=now()
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function atlas.issue_delegated_agent_credential_service_v1(
  p_authorization_id uuid,p_token_hash text,p_expires_at timestamptz,p_metadata jsonb
)
returns uuid
language plpgsql
security definer
set search_path = atlas, public, pg_temp
as $$
declare v_id uuid;
begin
  if lower(p_token_hash) !~ '^[0-9a-f]{64}$' then raise exception 'token hash must be lowercase SHA-256 hex'; end if;
  if not exists(select 1 from atlas.delegated_agent_authorizations where id=p_authorization_id and authorization_state='active') then raise exception 'active authorization required'; end if;
  insert into atlas.delegated_agent_credentials(authorization_id,token_hash,expires_at,metadata)
  values(p_authorization_id,lower(p_token_hash),p_expires_at,coalesce(p_metadata,'{}'::jsonb)) returning id into v_id;
  return v_id;
end;
$$;

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
  v_user uuid := auth.uid();
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
  if p_ledger_id is not null and not atlas.principal_has_ledger_authority_v1(v_principal.id,p_ledger_id) then raise exception 'principal lacks ledger authority'; end if;
  if p_delegating_seat_id is not null then
    select * into v_seat from ledger.seats where id=p_delegating_seat_id;
    if v_seat.id is null or v_seat.seat_state<>'active' or v_seat.ledger_id<>p_ledger_id then raise exception 'active delegating seat on ledger required'; end if;
    if v_principal.person_id is not null and v_seat.person_entity_id<>v_principal.person_id then raise exception 'delegating seat must be held by current principal'; end if;
  end if;
  select count(*) into v_unknown
  from unnest(coalesce(p_allowed_command_keys,'{}'::text[]) || coalesce(p_denied_command_keys,'{}'::text[])) k
  where not exists(select 1 from atlas.agent_command_definitions d where d.command_key=k and d.command_version=1 and d.status='active');
  if v_unknown>0 then raise exception 'authorization references unknown or inactive commands'; end if;

  insert into atlas.delegated_agent_authorizations(
    carrier_id,principal_id,ledger_id,delegating_seat_id,max_execution_class,allowed_command_keys,denied_command_keys,
    scope,confirmation_policy,purpose,basis,ends_at,created_by_user_id
  ) values (
    p_carrier_id,v_principal.id,p_ledger_id,p_delegating_seat_id,p_max_execution_class,
    coalesce(p_allowed_command_keys,'{}'::text[]),coalesce(p_denied_command_keys,'{}'::text[]),
    coalesce(p_scope,'{}'::jsonb),coalesce(p_confirmation_policy,'{}'::jsonb),btrim(p_purpose),
    jsonb_build_object('establishedBy','principal_self_api','userId',v_user),p_ends_at,v_user
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function atlas.revoke_delegated_agent_authorization_self_api_v1(p_authorization_id uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
declare v_user uuid:=auth.uid(); v_auth atlas.delegated_agent_authorizations%rowtype; v_principal atlas.principals%rowtype;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_auth from atlas.delegated_agent_authorizations where id=p_authorization_id for update;
  if not found then raise exception 'authorization not found'; end if;
  select * into v_principal from atlas.principals where id=v_auth.principal_id;
  if v_principal.user_id<>v_user then raise exception 'authorization does not belong to current principal'; end if;
  if v_auth.authorization_state='revoked' then return jsonb_build_object('authorizationId',v_auth.id,'state','revoked','replayed',true); end if;
  update atlas.delegated_agent_authorizations set authorization_state='revoked',revoked_at=now(),updated_at=now(),basis=basis||jsonb_build_object('revokedReason',p_reason,'revokedByUserId',v_user) where id=v_auth.id;
  update atlas.delegated_agent_credentials set credential_state='revoked',revoked_at=now() where authorization_id=v_auth.id and credential_state='active';
  return jsonb_build_object('authorizationId',v_auth.id,'state','revoked','replayed',false);
end;
$$;

create or replace function atlas.delegated_agent_authorizations_self_api_v1()
returns table(
  authorization_id uuid,carrier_id uuid,carrier_key text,carrier_name text,ledger_id uuid,delegating_seat_id uuid,
  authorization_state text,max_execution_class text,allowed_command_keys text[],denied_command_keys text[],scope jsonb,
  purpose text,begins_at timestamptz,ends_at timestamptz
)
language sql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
  select a.id,a.carrier_id,c.stable_key,c.display_name,a.ledger_id,a.delegating_seat_id,a.authorization_state,a.max_execution_class,
         a.allowed_command_keys,a.denied_command_keys,a.scope,a.purpose,a.begins_at,a.ends_at
  from atlas.delegated_agent_authorizations a
  join atlas.delegated_agent_carriers c on c.id=a.carrier_id
  join atlas.principals p on p.id=a.principal_id
  where p.user_id=auth.uid()
  order by a.created_at desc;
$$;

insert into atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,confirmation_requirement,handler_key,status,input_contract,target_contract,metadata)
values
 ('booking.request.read',1,'Read booking request','ledger','read','none','booking_request_detail_v1','active','{}'::jsonb,'{"required":["requestId"]}'::jsonb,'{"domain":"booking"}'::jsonb),
 ('booking.request.evaluate_commitment',1,'Evaluate booking commitment','ledger','read','none','booking_request_commitment_evaluation_v1','active','{}'::jsonb,'{"required":["requestId"]}'::jsonb,'{"domain":"booking"}'::jsonb),
 ('booking.request.place_hold',1,'Place booking request hold','ledger','commit','principal_explicit','establish_booking_request_holds_service_v1','active','{"required":["expiresAt"]}'::jsonb,'{"required":["requestId"]}'::jsonb,'{"domain":"booking","effect":"resource_hold"}'::jsonb),
 ('booking.request.approve',1,'Approve booking request','ledger','commit','principal_explicit','decide_booking_request_service_v1','active','{"fixedDecision":"approved","optional":["reason"]}'::jsonb,'{"required":["requestId"]}'::jsonb,'{"domain":"booking","effect":"approval"}'::jsonb)
on conflict(command_key,command_version) do update set
  label=excluded.label,scope_kind=excluded.scope_kind,execution_class=excluded.execution_class,
  confirmation_requirement=excluded.confirmation_requirement,handler_key=excluded.handler_key,status=excluded.status,
  input_contract=excluded.input_contract,target_contract=excluded.target_contract,metadata=excluded.metadata,updated_at=now();

revoke all on atlas.delegated_agent_carriers from public, anon, authenticated;
revoke all on atlas.delegated_agent_authorizations from public, anon, authenticated;
revoke all on atlas.delegated_agent_credentials from public, anon, authenticated;
revoke all on atlas.agent_command_definitions from public, anon, authenticated;
revoke all on atlas.agent_command_invocations from public, anon, authenticated;
revoke all on atlas.agent_command_invocation_events from public, anon, authenticated;

revoke all on function atlas.evaluate_delegated_agent_command_authority_v1(uuid,text,integer) from public, anon, authenticated;
revoke all on function atlas.resolve_delegated_agent_credential_service_v1(text) from public, anon, authenticated;
revoke all on function atlas.begin_delegated_agent_command_service_v1(text,text,integer,jsonb,jsonb,text) from public, anon, authenticated;
revoke all on function atlas.mark_delegated_agent_command_executing_service_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.complete_delegated_agent_command_service_v1(uuid,boolean,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.delegated_agent_command_invocation_service_v1(text,uuid) from public, anon, authenticated;
revoke all on function atlas.register_delegated_agent_carrier_service_v1(text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function atlas.issue_delegated_agent_credential_service_v1(uuid,text,timestamptz,jsonb) from public, anon, authenticated;

grant execute on function atlas.evaluate_delegated_agent_command_authority_v1(uuid,text,integer) to service_role;
grant execute on function atlas.resolve_delegated_agent_credential_service_v1(text) to service_role;
grant execute on function atlas.begin_delegated_agent_command_service_v1(text,text,integer,jsonb,jsonb,text) to service_role;
grant execute on function atlas.mark_delegated_agent_command_executing_service_v1(uuid) to service_role;
grant execute on function atlas.complete_delegated_agent_command_service_v1(uuid,boolean,jsonb,jsonb) to service_role;
grant execute on function atlas.delegated_agent_command_invocation_service_v1(text,uuid) to service_role;
grant execute on function atlas.register_delegated_agent_carrier_service_v1(text,text,text,text,jsonb) to service_role;
grant execute on function atlas.issue_delegated_agent_credential_service_v1(uuid,text,timestamptz,jsonb) to service_role;

revoke all on function atlas.confirm_delegated_agent_command_self_api_v1(uuid) from public, anon;
revoke all on function atlas.establish_delegated_agent_authorization_self_api_v1(uuid,uuid,uuid,text,text[],text[],jsonb,jsonb,text,timestamptz) from public, anon;
revoke all on function atlas.revoke_delegated_agent_authorization_self_api_v1(uuid,text) from public, anon;
revoke all on function atlas.delegated_agent_authorizations_self_api_v1() from public, anon;
grant execute on function atlas.confirm_delegated_agent_command_self_api_v1(uuid) to authenticated;
grant execute on function atlas.establish_delegated_agent_authorization_self_api_v1(uuid,uuid,uuid,text,text[],text[],jsonb,jsonb,text,timestamptz) to authenticated;
grant execute on function atlas.revoke_delegated_agent_authorization_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.delegated_agent_authorizations_self_api_v1() to authenticated;

commit;

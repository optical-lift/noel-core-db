begin;

-- Delegation is explicit, never ambient: an empty allowlist grants nothing.
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
  select * into v_auth
  from atlas.delegated_agent_authorizations
  where id = p_authorization_id;

  if not found then
    return jsonb_build_object(
      'allowed', false,
      'reasons', jsonb_build_array('authorization_not_found')
    );
  end if;

  select * into v_carrier
  from atlas.delegated_agent_carriers
  where id = v_auth.carrier_id;

  select * into v_principal
  from atlas.principals
  where id = v_auth.principal_id;

  select * into v_command
  from atlas.agent_command_definitions
  where command_key = p_command_key
    and command_version = p_command_version;

  if v_carrier.id is null or v_carrier.status <> 'active' then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('carrier_not_active');
  end if;

  if v_principal.id is null or v_principal.status <> 'active' then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('principal_not_active');
  end if;

  if v_command.command_key is null or v_command.status <> 'active' then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('command_not_active');
  end if;

  if v_auth.authorization_state <> 'active' then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('authorization_not_active');
  end if;

  if now() < v_auth.begins_at
     or (v_auth.ends_at is not null and now() >= v_auth.ends_at) then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('authorization_outside_time_window');
  end if;

  if not (p_command_key = any(v_auth.allowed_command_keys)) then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('command_not_in_explicit_allowlist');
  end if;

  if p_command_key = any(v_auth.denied_command_keys) then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('command_denied');
  end if;

  if v_command.command_key is not null
     and atlas.execution_class_rank_v1(v_command.execution_class)
       > atlas.execution_class_rank_v1(v_auth.max_execution_class) then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('execution_class_exceeds_delegation');
  end if;

  if v_auth.ledger_id is not null then
    if not atlas.principal_has_ledger_authority_v1(
      v_auth.principal_id,
      v_auth.ledger_id
    ) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('principal_lacks_ledger_authority');
    end if;

    if v_command.command_key is not null
       and v_command.scope_kind = 'personal' then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('personal_command_cannot_use_ledger_delegation');
    end if;
  elsif v_command.command_key is not null
        and v_command.scope_kind = 'ledger' then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('ledger_command_requires_ledger_delegation');
  end if;

  if v_auth.delegating_seat_id is not null then
    select * into v_seat
    from ledger.seats
    where id = v_auth.delegating_seat_id;

    if v_seat.id is null or v_seat.seat_state <> 'active' then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('delegating_seat_not_active');
    elsif v_auth.ledger_id is null or v_seat.ledger_id <> v_auth.ledger_id then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('delegating_seat_ledger_mismatch');
    elsif v_principal.person_id is not null
          and v_seat.person_entity_id <> v_principal.person_id then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('delegating_seat_not_held_by_principal');
    end if;
  end if;

  if v_command.capability_key is not null then
    if not atlas.capability_definition_active_v1(
      v_command.capability_key,
      v_command.capability_version
    ) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('required_capability_not_active');
    elsif v_auth.ledger_id is not null
          and not atlas.capability_entitlement_grant_live_v1(
            v_auth.ledger_id,
            v_command.capability_key,
            v_command.capability_version
          ) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('ledger_not_entitled_for_capability');
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

-- Scope is evaluated against the typed target envelope, not merely the command name.
create or replace function atlas.evaluate_delegated_agent_command_target_authority_v1(
  p_authorization_id uuid,
  p_command_key text,
  p_command_version integer,
  p_target jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_base jsonb;
  v_allowed boolean;
  v_reasons jsonb;
  v_confirmation_required boolean;
  v_target_kind text := nullif(btrim(coalesce(p_target->>'kind','')), '');
  v_target_id text := nullif(btrim(coalesce(p_target->>'id','')), '');
  v_force_all_commits boolean := false;
begin
  v_base := atlas.evaluate_delegated_agent_command_authority_v1(
    p_authorization_id,
    p_command_key,
    p_command_version
  );

  if not coalesce(v_base ? 'authorizationId', false) then
    return v_base;
  end if;

  select * into v_auth
  from atlas.delegated_agent_authorizations
  where id = p_authorization_id;

  v_allowed := coalesce((v_base->>'allowed')::boolean,false);
  v_reasons := coalesce(v_base->'reasons','[]'::jsonb);
  v_confirmation_required := coalesce(
    (v_base->>'confirmationRequired')::boolean,
    false
  );

  if v_auth.scope ? 'targetKinds' then
    if v_target_kind is null
       or not ((v_auth.scope->'targetKinds') ? v_target_kind) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('target_kind_outside_delegated_scope');
    end if;
  end if;

  if v_auth.scope ? 'targetIds' then
    if v_target_id is null
       or not ((v_auth.scope->'targetIds') ? v_target_id) then
      v_allowed := false;
      v_reasons := v_reasons || jsonb_build_array('target_id_outside_delegated_scope');
    end if;
  end if;

  v_force_all_commits := coalesce(
    (v_auth.confirmation_policy->>'forceAllCommits')::boolean,
    false
  );

  if v_force_all_commits
     and coalesce(v_base->>'executionClass','') = 'commit' then
    v_confirmation_required := true;
  end if;

  if v_auth.confirmation_policy ? 'forceConfirmationCommandKeys'
     and (v_auth.confirmation_policy->'forceConfirmationCommandKeys') ? p_command_key then
    v_confirmation_required := true;
  end if;

  return v_base || jsonb_build_object(
    'allowed', v_allowed,
    'reasons', v_reasons,
    'confirmationRequired', v_confirmation_required,
    'target', coalesce(p_target,'{}'::jsonb),
    'targetScopeEvaluated', true
  );
end;
$$;

-- Begin records a durable receipt. Idempotency is scoped to the delegation.
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

  if not found then
    raise exception 'delegated agent credential is unavailable';
  end if;

  select * into v_auth
  from atlas.delegated_agent_authorizations
  where id = v_cred.authorization_id;

  if not found then
    raise exception 'delegated agent authorization is unavailable';
  end if;

  select * into v_invocation
  from atlas.agent_command_invocations
  where authorization_id = v_auth.id
    and idempotency_key = p_idempotency_key;

  if found then
    return jsonb_build_object(
      'invocationId', v_invocation.id,
      'state', v_invocation.invocation_state,
      'replayed', true,
      'confirmationRequired', v_invocation.confirmation_required,
      'authority', v_invocation.authority_snapshot,
      'result', v_invocation.result,
      'failure', v_invocation.failure
    );
  end if;

  v_eval := atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_auth.id,
    p_command_key,
    p_command_version,
    coalesce(p_target,'{}'::jsonb)
  );

  if coalesce((v_eval->>'allowed')::boolean,false) = false then
    v_state := 'rejected';
  elsif coalesce((v_eval->>'confirmationRequired')::boolean,false) then
    v_state := 'needs_confirmation';
  else
    v_state := 'authorized';
  end if;

  insert into atlas.agent_command_invocations(
    authorization_id,
    credential_id,
    carrier_id,
    principal_id,
    ledger_id,
    delegating_seat_id,
    command_key,
    command_version,
    idempotency_key,
    target,
    input,
    authority_snapshot,
    invocation_state,
    confirmation_required,
    authorized_at
  ) values (
    v_auth.id,
    v_cred.id,
    v_auth.carrier_id,
    v_auth.principal_id,
    v_auth.ledger_id,
    v_auth.delegating_seat_id,
    p_command_key,
    p_command_version,
    p_idempotency_key,
    coalesce(p_target,'{}'::jsonb),
    coalesce(p_input,'{}'::jsonb),
    v_eval,
    v_state,
    coalesce((v_eval->>'confirmationRequired')::boolean,false),
    case when v_state='authorized' then now() else null end
  )
  returning * into v_invocation;

  insert into atlas.agent_command_invocation_events(
    invocation_id,event_kind,to_state,actor_kind,reason,evidence
  ) values (
    v_invocation.id,
    'command_requested',
    v_state,
    'agent',
    case when v_state='rejected' then 'authority evaluation rejected command' else null end,
    v_eval
  );

  update atlas.delegated_agent_credentials
  set last_used_at = now()
  where id = v_cred.id;

  return jsonb_build_object(
    'invocationId',v_invocation.id,
    'state',v_state,
    'replayed',false,
    'confirmationRequired',v_invocation.confirmation_required,
    'authority',v_eval
  );
end;
$$;

-- Confirmation belongs to the authenticated Principal whose authority was delegated.
create or replace function atlas.confirm_delegated_agent_command_self_api_v1(
  p_invocation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, auth, public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_inv atlas.agent_command_invocations%rowtype;
  v_principal atlas.principals%rowtype;
  v_eval jsonb;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select * into v_inv
  from atlas.agent_command_invocations
  where id = p_invocation_id
  for update;

  if not found then
    raise exception 'invocation not found';
  end if;

  select * into v_principal
  from atlas.principals
  where id = v_inv.principal_id;

  if v_principal.user_id <> v_user then
    raise exception 'invocation does not belong to current principal';
  end if;

  if v_inv.invocation_state <> 'needs_confirmation' then
    raise exception 'invocation is not awaiting confirmation';
  end if;

  v_eval := atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_inv.authorization_id,
    v_inv.command_key,
    v_inv.command_version,
    v_inv.target
  );

  if coalesce((v_eval->>'allowed')::boolean,false) = false then
    raise exception 'delegated authority is no longer valid';
  end if;

  update atlas.agent_command_invocations
  set invocation_state = 'authorized',
      confirmed_by_user_id = v_user,
      confirmed_at = now(),
      authorized_at = now(),
      authority_snapshot = v_eval
  where id = v_inv.id;

  insert into atlas.agent_command_invocation_events(
    invocation_id,event_kind,from_state,to_state,actor_kind,actor_user_id,evidence
  ) values (
    v_inv.id,
    'principal_confirmed',
    'needs_confirmation',
    'authorized',
    'principal',
    v_user,
    jsonb_build_object('confirmedByUserId',v_user,'authority',v_eval)
  );

  return jsonb_build_object(
    'invocationId',v_inv.id,
    'state','authorized',
    'confirmed',true
  );
end;
$$;

-- Authority is rechecked immediately before execution; old approval is not ambient authority.
create or replace function atlas.mark_delegated_agent_command_executing_service_v1(
  p_invocation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
declare
  v_inv atlas.agent_command_invocations%rowtype;
  v_eval jsonb;
begin
  select * into v_inv
  from atlas.agent_command_invocations
  where id = p_invocation_id
  for update;

  if not found then
    raise exception 'invocation not found';
  end if;

  if v_inv.invocation_state = 'executing' then
    return jsonb_build_object(
      'invocationId',v_inv.id,
      'state','executing',
      'replayed',true
    );
  end if;

  if v_inv.invocation_state <> 'authorized' then
    raise exception 'invocation is not authorized for execution';
  end if;

  v_eval := atlas.evaluate_delegated_agent_command_target_authority_v1(
    v_inv.authorization_id,
    v_inv.command_key,
    v_inv.command_version,
    v_inv.target
  );

  if coalesce((v_eval->>'allowed')::boolean,false) = false then
    raise exception 'delegated authority is no longer valid';
  end if;

  update atlas.agent_command_invocations
  set invocation_state = 'executing',
      execution_started_at = now(),
      authority_snapshot = v_eval
  where id = v_inv.id;

  insert into atlas.agent_command_invocation_events(
    invocation_id,event_kind,from_state,to_state,actor_kind,evidence
  ) values (
    v_inv.id,
    'execution_started',
    'authorized',
    'executing',
    'service',
    v_eval
  );

  return jsonb_build_object(
    'invocationId',v_inv.id,
    'state','executing',
    'replayed',false
  );
end;
$$;

-- Principals may establish only explicit, bounded delegations rooted in their own authority.
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
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select * into v_principal
  from atlas.principals
  where user_id = v_user
    and status = 'active'
  limit 1;

  if not found then
    raise exception 'active principal required';
  end if;

  if not exists(
    select 1
    from atlas.delegated_agent_carriers
    where id = p_carrier_id
      and status = 'active'
  ) then
    raise exception 'active carrier required';
  end if;

  if p_max_execution_class not in ('read','prepare','commit') then
    raise exception 'invalid execution class';
  end if;

  if coalesce(array_length(p_allowed_command_keys,1),0) = 0 then
    raise exception 'at least one explicit allowed command is required';
  end if;

  if coalesce(p_allowed_command_keys,'{}'::text[])
     && coalesce(p_denied_command_keys,'{}'::text[]) then
    raise exception 'allowed and denied command sets overlap';
  end if;

  if p_ledger_id is not null
     and not atlas.principal_has_ledger_authority_v1(v_principal.id,p_ledger_id) then
    raise exception 'principal lacks ledger authority';
  end if;

  if p_delegating_seat_id is not null then
    select * into v_seat
    from ledger.seats
    where id = p_delegating_seat_id;

    if v_seat.id is null
       or v_seat.seat_state <> 'active'
       or v_seat.ledger_id <> p_ledger_id then
      raise exception 'active delegating seat on ledger required';
    end if;

    if v_principal.person_id is not null
       and v_seat.person_entity_id <> v_principal.person_id then
      raise exception 'delegating seat must be held by current principal';
    end if;
  end if;

  select count(*) into v_unknown
  from unnest(
    coalesce(p_allowed_command_keys,'{}'::text[])
    || coalesce(p_denied_command_keys,'{}'::text[])
  ) k
  where not exists(
    select 1
    from atlas.agent_command_definitions d
    where d.command_key = k
      and d.command_version = 1
      and d.status = 'active'
  );

  if v_unknown > 0 then
    raise exception 'authorization references unknown or inactive commands';
  end if;

  if p_ends_at is not null and p_ends_at <= now() then
    raise exception 'authorization end must be in the future';
  end if;

  if btrim(coalesce(p_purpose,'')) = '' then
    raise exception 'delegation purpose is required';
  end if;

  insert into atlas.delegated_agent_authorizations(
    carrier_id,
    principal_id,
    ledger_id,
    delegating_seat_id,
    max_execution_class,
    allowed_command_keys,
    denied_command_keys,
    scope,
    confirmation_policy,
    purpose,
    basis,
    ends_at,
    created_by_user_id
  ) values (
    p_carrier_id,
    v_principal.id,
    p_ledger_id,
    p_delegating_seat_id,
    p_max_execution_class,
    coalesce(p_allowed_command_keys,'{}'::text[]),
    coalesce(p_denied_command_keys,'{}'::text[]),
    coalesce(p_scope,'{}'::jsonb),
    coalesce(p_confirmation_policy,'{}'::jsonb),
    btrim(p_purpose),
    jsonb_build_object('establishedBy','principal_self_api','userId',v_user),
    p_ends_at,
    v_user
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- An agent can discover only the typed commands actually available under its current delegation.
create or replace function atlas.delegated_agent_command_catalog_service_v1(
  p_token_hash text
)
returns table(
  command_key text,
  command_version integer,
  label text,
  execution_class text,
  confirmation_required boolean,
  input_contract jsonb,
  target_contract jsonb
)
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select d.command_key,
         d.command_version,
         d.label,
         d.execution_class,
         (
           d.confirmation_requirement = 'principal_explicit'
           or (
             coalesce((a.confirmation_policy->>'forceAllCommits')::boolean,false)
             and d.execution_class = 'commit'
           )
           or (
             a.confirmation_policy ? 'forceConfirmationCommandKeys'
             and (a.confirmation_policy->'forceConfirmationCommandKeys') ? d.command_key
           )
         ) as confirmation_required,
         d.input_contract,
         d.target_contract
  from atlas.delegated_agent_credentials c
  join atlas.delegated_agent_authorizations a
    on a.id = c.authorization_id
  join atlas.agent_command_definitions d
    on d.command_key = any(a.allowed_command_keys)
   and d.status = 'active'
  where c.token_hash = lower(p_token_hash)
    and c.credential_state = 'active'
    and now() >= c.begins_at
    and (c.expires_at is null or now() < c.expires_at)
    and a.authorization_state = 'active'
    and now() >= a.begins_at
    and (a.ends_at is null or now() < a.ends_at)
    and not (d.command_key = any(a.denied_command_keys))
    and atlas.execution_class_rank_v1(d.execution_class)
      <= atlas.execution_class_rank_v1(a.max_execution_class)
  order by d.command_key,d.command_version;
$$;

-- Universal target envelope: {kind, id}. Handler adapters translate id to domain-specific arguments.
update atlas.agent_command_definitions
set target_contract = jsonb_build_object(
      'required',jsonb_build_array('kind','id'),
      'kind','booking_request'
    ),
    updated_at = now()
where command_key in (
  'booking.request.read',
  'booking.request.evaluate_commitment',
  'booking.request.place_hold',
  'booking.request.approve'
)
  and command_version = 1;

revoke all on function atlas.evaluate_delegated_agent_command_target_authority_v1(uuid,text,integer,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.delegated_agent_command_catalog_service_v1(text)
  from public,anon,authenticated;

grant execute on function atlas.evaluate_delegated_agent_command_target_authority_v1(uuid,text,integer,jsonb)
  to service_role;
grant execute on function atlas.delegated_agent_command_catalog_service_v1(text)
  to service_role;

commit;

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
  select * into v_auth from atlas.delegated_agent_authorizations where id=p_authorization_id;
  if not found then
    return jsonb_build_object('allowed',false,'reasons',jsonb_build_array('authorization_not_found'));
  end if;

  select * into v_carrier from atlas.delegated_agent_carriers where id=v_auth.carrier_id;
  select * into v_principal from atlas.principals where id=v_auth.principal_id;
  select * into v_command from atlas.agent_command_definitions
  where command_key=p_command_key and command_version=p_command_version;

  if v_carrier.id is null or v_carrier.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('carrier_not_active'); end if;
  if v_principal.id is null or v_principal.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('principal_not_active'); end if;
  if v_command.command_key is null or v_command.status<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('command_not_active'); end if;
  if v_auth.authorization_state<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('authorization_not_active'); end if;
  if now()<v_auth.begins_at or (v_auth.ends_at is not null and now()>=v_auth.ends_at) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('authorization_outside_time_window'); end if;

  if not (p_command_key = any(v_auth.allowed_command_keys)) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('command_not_in_explicit_allowlist');
  end if;
  if p_command_key = any(v_auth.denied_command_keys) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('command_denied');
  end if;
  if v_command.command_key is not null and atlas.execution_class_rank_v1(v_command.execution_class)>atlas.execution_class_rank_v1(v_auth.max_execution_class) then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('execution_class_exceeds_delegation');
  end if;

  if v_auth.ledger_id is not null then
    if not atlas.principal_has_ledger_authority_v1(v_auth.principal_id,v_auth.ledger_id) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('principal_lacks_ledger_authority'); end if;
    if v_command.command_key is not null and v_command.scope_kind='personal' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('personal_command_cannot_use_ledger_delegation'); end if;
  elsif v_command.command_key is not null and v_command.scope_kind='ledger' then
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('ledger_command_requires_ledger_delegation');
  end if;

  if v_auth.delegating_seat_id is not null then
    select * into v_seat from ledger.seats where id=v_auth.delegating_seat_id;
    if v_seat.id is null or v_seat.seat_state<>'active' then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_not_active');
    elsif v_auth.ledger_id is null or v_seat.ledger_id<>v_auth.ledger_id then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_ledger_mismatch');
    elsif v_principal.person_id is not null and v_seat.person_entity_id<>v_principal.person_id then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('delegating_seat_not_held_by_principal'); end if;
  end if;

  if v_command.capability_key is not null then
    if not atlas.capability_definition_active_v1(v_command.capability_key,v_command.capability_version) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('required_capability_not_active');
    elsif v_auth.ledger_id is not null and not atlas.capability_entitlement_grant_live_v1(v_auth.ledger_id,v_command.capability_key,v_command.capability_version) then v_allowed:=false; v_reasons:=v_reasons||jsonb_build_array('ledger_not_entitled_for_capability'); end if;
  end if;

  v_confirmation_required:=v_command.command_key is not null and v_command.confirmation_requirement='principal_explicit';

  return jsonb_build_object(
    'allowed',v_allowed,
    'reasons',v_reasons,
    'authorizationId',v_auth.id,
    'carrierId',v_auth.carrier_id,
    'principalId',v_auth.principal_id,
    'ledgerId',v_auth.ledger_id,
    'delegatingSeatId',v_auth.delegating_seat_id,
    'commandKey',p_command_key,
    'commandVersion',p_command_version,
    'executionClass',v_command.execution_class,
    'confirmationRequired',v_confirmation_required,
    'handlerKey',v_command.handler_key,
    'scope',v_auth.scope,
    'authoritySource','delegated_agent_authorization_v1'
  );
end;
$$;
-- SOURCE CANDIDATE ONLY. Requires private Foundry registry from PR #2093.
-- No migration release, no production DDL, no user-data mutations.
-- Versioned extension to Atlas's existing delegated-agent command authority.
-- Reuses live v1 evaluator bodies; only Foundry-specific checks are added.
-- Existing Ledger and personal command behavior is otherwise unchanged.
BEGIN;

ALTER TABLE atlas.agent_command_definitions
  DROP CONSTRAINT agent_command_definitions_scope_kind_check;
ALTER TABLE atlas.agent_command_definitions
  ADD CONSTRAINT agent_command_definitions_scope_kind_check
  CHECK (scope_kind = ANY (ARRAY[
    'personal'::text,'ledger'::text,'either'::text,'foundry_workspace'::text
  ]));

CREATE OR REPLACE FUNCTION atlas.evaluate_delegated_agent_command_authority_v1(p_authorization_id uuid, p_command_key text, p_command_version integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'atlas', 'ledger', 'public', 'pg_temp'
AS $function$
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
    if v_command.command_key is not null and v_command.scope_kind='foundry_workspace' then
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_command_cannot_use_ledger_delegation');
    end if;
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
$function$;


CREATE OR REPLACE FUNCTION atlas.evaluate_delegated_agent_command_target_authority_v1(p_authorization_id uuid, p_command_key text, p_command_version integer, p_target jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'atlas', 'ledger', 'public', 'pg_temp'
AS $function$
declare
  v_auth atlas.delegated_agent_authorizations%rowtype;
  v_command atlas.agent_command_definitions%rowtype;
  v_base jsonb;
  v_allowed boolean;
  v_reasons jsonb;
  v_confirmation_required boolean;
  v_target_kind text := nullif(btrim(coalesce(p_target->>'kind','')), '');
  v_target_id text := nullif(btrim(coalesce(p_target->>'id','')), '');
  v_expected_kind text;
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

  select * into v_command
  from atlas.agent_command_definitions
  where command_key = p_command_key
    and command_version = p_command_version;

  v_allowed := coalesce((v_base->>'allowed')::boolean,false);
  v_reasons := coalesce(v_base->'reasons','[]'::jsonb);
  v_confirmation_required := coalesce((v_base->>'confirmationRequired')::boolean,false);
  v_expected_kind := nullif(btrim(coalesce(v_command.target_contract->>'kind','')), '');

  if v_target_kind is null then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_kind_required');
  end if;

  if v_target_id is null then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_id_required');
  end if;

  if v_expected_kind is not null
     and v_target_kind is distinct from v_expected_kind then
    v_allowed := false;
    v_reasons := v_reasons || jsonb_build_array('target_kind_does_not_match_command_contract');
  end if;

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

  v_force_all_commits := coalesce((v_auth.confirmation_policy->>'forceAllCommits')::boolean,false);
  if v_force_all_commits
     and coalesce(v_base->>'executionClass','') = 'commit' then
    v_confirmation_required := true;
  end if;

  if v_auth.confirmation_policy ? 'forceConfirmationCommandKeys'
     and (v_auth.confirmation_policy->'forceConfirmationCommandKeys') ? p_command_key then
    v_confirmation_required := true;
  end if;

  -- A non-Foundry command cannot tunnel through a generic target contract
  -- to a Foundry workspace just because an agent chooses that target kind.
  IF v_target_kind='foundry_workspace'
     AND v_command.scope_kind IS DISTINCT FROM 'foundry_workspace' THEN
    v_allowed:=false;
    v_reasons:=v_reasons||jsonb_build_array('non_foundry_command_cannot_target_workspace');
  END IF;

  -- Foundry is neither a Ledger nor a Personal Atlas command.
  -- A JSON target allowlist alone cannot establish Foundry jurisdiction.
  IF v_command.scope_kind='foundry_workspace' THEN
    IF v_target_kind IS DISTINCT FROM 'foundry_workspace'
       OR v_expected_kind IS DISTINCT FROM 'foundry_workspace' THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_target_kind_required');
    END IF;

    IF v_auth.ledger_id IS NOT NULL OR v_auth.delegating_seat_id IS NOT NULL THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_requires_pre_ledger_delegation');
    END IF;

    -- Require a literal workspace target in BOTH scope allowlists.
    -- Caller control of these arrays does not suffice; the private registry
    -- ownership and current source-custody review below are also mandatory.
    IF jsonb_typeof(v_auth.scope->'targetKinds') IS DISTINCT FROM 'array'
       OR NOT COALESCE((v_auth.scope->'targetKinds') ? 'foundry_workspace',false)
       OR jsonb_typeof(v_auth.scope->'targetIds') IS DISTINCT FROM 'array'
       OR NOT COALESCE((v_auth.scope->'targetIds') ? v_target_id,false) THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_workspace_not_explicitly_delegated');
    END IF;

    IF v_target_id IS NULL OR NOT EXISTS (
      SELECT 1
      FROM foundry.workspace_authority_registry_v1 w
      WHERE w.workspace_id=v_target_id
        AND w.owner_principal_id=v_auth.principal_id
        AND w.protocol_version='0.1'
        AND w.custody_review_state='reviewed'
        AND w.custody_reviewed_by_principal_id IS NOT NULL
        AND w.custody_reviewed_at IS NOT NULL
        AND cardinality(w.custody_basis_refs)>0
        AND w.suspended_at IS NULL
        AND w.revoked_at IS NULL
    ) THEN
      v_allowed:=false;
      v_reasons:=v_reasons||jsonb_build_array('foundry_workspace_custody_not_authorized');
    END IF;
  END IF;

  return v_base || jsonb_build_object(
    'allowed',v_allowed,
    'reasons',v_reasons,
    'confirmationRequired',v_confirmation_required,
    'target',coalesce(p_target,'{}'::jsonb),
    'targetExpectedKind',v_expected_kind,
    'targetScopeEvaluated',true
  );
end;
$function$;


-- No Foundry commands are activated in this gate. Do not add a broad
-- allowlist, API/SQL invocation route, or direct table access.
-- The existing agent command executor remains the sole command bridge.
-- Source-custody state changes require a separately authorized human command.
COMMIT;

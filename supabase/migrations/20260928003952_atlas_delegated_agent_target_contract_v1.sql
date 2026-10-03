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

  return v_base || jsonb_build_object(
    'allowed',v_allowed,
    'reasons',v_reasons,
    'confirmationRequired',v_confirmation_required,
    'target',coalesce(p_target,'{}'::jsonb),
    'targetExpectedKind',v_expected_kind,
    'targetScopeEvaluated',true
  );
end;
$$;
create or replace function atlas.mark_delegated_agent_command_executing_service_v1(p_invocation_id uuid)
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
    return jsonb_build_object('invocationId',v_inv.id,'state','executing','replayed',true);
  end if;
  if v_inv.invocation_state <> 'authorized' then
    raise exception 'invocation is not authorized for execution';
  end if;

  v_eval := atlas.evaluate_delegated_agent_command_authority_v1(
    v_inv.authorization_id,
    v_inv.command_key,
    v_inv.command_version
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
    v_inv.id,'execution_started','authorized','executing','service',v_eval
  );

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
declare
  v_inv atlas.agent_command_invocations%rowtype;
  v_state text;
begin
  select * into v_inv
  from atlas.agent_command_invocations
  where id = p_invocation_id
  for update;
  if not found then
    raise exception 'invocation not found';
  end if;

  if v_inv.invocation_state in ('succeeded','failed') then
    return jsonb_build_object(
      'invocationId',v_inv.id,
      'state',v_inv.invocation_state,
      'replayed',true,
      'result',v_inv.result,
      'failure',v_inv.failure
    );
  end if;
  if v_inv.invocation_state <> 'executing' then
    raise exception 'invocation is not executing';
  end if;

  v_state := case when p_succeeded then 'succeeded' else 'failed' end;

  update atlas.agent_command_invocations
  set invocation_state = v_state,
      result = case when p_succeeded then coalesce(p_result,'{}'::jsonb) else '{}'::jsonb end,
      failure = case when p_succeeded then '{}'::jsonb else coalesce(p_failure,'{}'::jsonb) end,
      completed_at = now()
  where id = v_inv.id;

  insert into atlas.agent_command_invocation_events(
    invocation_id,event_kind,from_state,to_state,actor_kind,evidence
  ) values (
    v_inv.id,
    case when p_succeeded then 'execution_succeeded' else 'execution_failed' end,
    'executing',
    v_state,
    'service',
    case when p_succeeded then coalesce(p_result,'{}'::jsonb) else coalesce(p_failure,'{}'::jsonb) end
  );

  return jsonb_build_object(
    'invocationId',v_inv.id,
    'state',v_state,
    'replayed',false,
    'result',case when p_succeeded then coalesce(p_result,'{}'::jsonb) else '{}'::jsonb end,
    'failure',case when p_succeeded then '{}'::jsonb else coalesce(p_failure,'{}'::jsonb) end
  );
end;
$$;
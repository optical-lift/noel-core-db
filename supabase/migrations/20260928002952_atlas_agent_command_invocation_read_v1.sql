create or replace function atlas.delegated_agent_command_invocation_service_v1(
  p_token_hash text,
  p_invocation_id uuid
)
returns jsonb
language sql
security definer
set search_path = atlas, ledger, public, pg_temp
as $$
  select jsonb_build_object(
    'invocationId',i.id,
    'state',i.invocation_state,
    'commandKey',i.command_key,
    'commandVersion',i.command_version,
    'confirmationRequired',i.confirmation_required,
    'confirmedAt',i.confirmed_at,
    'authority',i.authority_snapshot,
    'target',i.target,
    'input',i.input,
    'result',i.result,
    'failure',i.failure,
    'createdAt',i.created_at,
    'completedAt',i.completed_at
  )
  from atlas.agent_command_invocations i
  join atlas.delegated_agent_credentials c on c.id = i.credential_id
  where i.id = p_invocation_id
    and c.token_hash = lower(p_token_hash)
    and c.credential_state = 'active'
    and now() >= c.begins_at
    and (c.expires_at is null or now() < c.expires_at)
  limit 1;
$$;
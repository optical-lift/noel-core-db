create or replace function atlas.delegated_agent_pending_confirmations_self_api_v1()
returns table(
  invocation_id uuid,
  command_key text,
  command_version integer,
  command_label text,
  carrier_id uuid,
  carrier_key text,
  carrier_name text,
  ledger_id uuid,
  target jsonb,
  input jsonb,
  authority_snapshot jsonb,
  created_at timestamptz
)
language sql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
  select i.id,
         i.command_key,
         i.command_version,
         d.label,
         i.carrier_id,
         c.stable_key,
         c.display_name,
         i.ledger_id,
         i.target,
         i.input,
         i.authority_snapshot,
         i.created_at
  from atlas.agent_command_invocations i
  join atlas.principals p on p.id = i.principal_id
  join atlas.delegated_agent_carriers c on c.id = i.carrier_id
  join atlas.agent_command_definitions d
    on d.command_key = i.command_key
   and d.command_version = i.command_version
  where p.user_id = auth.uid()
    and i.invocation_state = 'needs_confirmation'
  order by i.created_at;
$$;

create or replace function atlas.reject_delegated_agent_command_self_api_v1(
  p_invocation_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, auth, public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_inv atlas.agent_command_invocations%rowtype;
  v_principal atlas.principals%rowtype;
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

  if v_inv.invocation_state = 'cancelled' then
    return jsonb_build_object(
      'invocationId',v_inv.id,
      'state','cancelled',
      'replayed',true
    );
  end if;

  if v_inv.invocation_state <> 'needs_confirmation' then
    raise exception 'invocation is not awaiting confirmation';
  end if;

  update atlas.agent_command_invocations
  set invocation_state = 'cancelled',
      completed_at = now(),
      failure = jsonb_build_object(
        'kind','principal_rejected',
        'reason',btrim(coalesce(p_reason,''))
      )
  where id = v_inv.id;

  insert into atlas.agent_command_invocation_events(
    invocation_id,event_kind,from_state,to_state,actor_kind,actor_user_id,reason,evidence
  ) values (
    v_inv.id,
    'principal_rejected',
    'needs_confirmation',
    'cancelled',
    'principal',
    v_user,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('rejectedByUserId',v_user)
  );

  return jsonb_build_object(
    'invocationId',v_inv.id,
    'state','cancelled',
    'replayed',false
  );
end;
$$;

revoke all on function atlas.delegated_agent_pending_confirmations_self_api_v1() from public,anon;
revoke all on function atlas.reject_delegated_agent_command_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.delegated_agent_pending_confirmations_self_api_v1() to authenticated;
grant execute on function atlas.reject_delegated_agent_command_self_api_v1(uuid,text) to authenticated;
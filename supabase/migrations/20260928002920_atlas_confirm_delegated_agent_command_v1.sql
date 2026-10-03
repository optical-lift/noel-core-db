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

  v_eval := atlas.evaluate_delegated_agent_command_authority_v1(
    v_inv.authorization_id,
    v_inv.command_key,
    v_inv.command_version
  );
  if coalesce((v_eval->>'allowed')::boolean, false) = false then
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
    v_inv.id,'principal_confirmed','needs_confirmation','authorized','principal',v_user,
    jsonb_build_object('confirmedByUserId',v_user,'authority',v_eval)
  );

  return jsonb_build_object(
    'invocationId', v_inv.id,
    'state', 'authorized',
    'confirmed', true
  );
end;
$$;
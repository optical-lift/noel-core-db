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
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then raise exception 'idempotency key is required'; end if;
  select * into v_cred from atlas.delegated_agent_credentials
  where token_hash=lower(p_token_hash) and credential_state='active' and now()>=begins_at and (expires_at is null or now()<expires_at) limit 1;
  if not found then raise exception 'delegated agent credential is unavailable'; end if;
  select * into v_auth from atlas.delegated_agent_authorizations where id=v_cred.authorization_id;
  if not found then raise exception 'delegated agent authorization is unavailable'; end if;
  select * into v_invocation from atlas.agent_command_invocations where authorization_id=v_auth.id and idempotency_key=p_idempotency_key;
  if found then
    return jsonb_build_object('invocationId',v_invocation.id,'state',v_invocation.invocation_state,'replayed',true,'confirmationRequired',v_invocation.confirmation_required,'authority',v_invocation.authority_snapshot,'result',v_invocation.result,'failure',v_invocation.failure);
  end if;

  v_eval:=atlas.evaluate_delegated_agent_command_target_authority_v1(v_auth.id,p_command_key,p_command_version,coalesce(p_target,'{}'::jsonb));
  if coalesce((v_eval->>'allowed')::boolean,false)=false then v_state:='rejected';
  elsif coalesce((v_eval->>'confirmationRequired')::boolean,false) then v_state:='needs_confirmation';
  else v_state:='authorized'; end if;

  insert into atlas.agent_command_invocations(authorization_id,credential_id,carrier_id,principal_id,ledger_id,delegating_seat_id,command_key,command_version,idempotency_key,target,input,authority_snapshot,invocation_state,confirmation_required,authorized_at)
  values(v_auth.id,v_cred.id,v_auth.carrier_id,v_auth.principal_id,v_auth.ledger_id,v_auth.delegating_seat_id,p_command_key,p_command_version,p_idempotency_key,coalesce(p_target,'{}'::jsonb),coalesce(p_input,'{}'::jsonb),v_eval,v_state,coalesce((v_eval->>'confirmationRequired')::boolean,false),case when v_state='authorized' then now() else null end)
  returning * into v_invocation;

  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,to_state,actor_kind,reason,evidence)
  values(v_invocation.id,'command_requested',v_state,'agent',case when v_state='rejected' then 'authority evaluation rejected command' else null end,v_eval);
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
  v_user uuid:=auth.uid();
  v_inv atlas.agent_command_invocations%rowtype;
  v_principal atlas.principals%rowtype;
  v_eval jsonb;
begin
  if v_user is null then raise exception 'authentication required'; end if;
  select * into v_inv from atlas.agent_command_invocations where id=p_invocation_id for update;
  if not found then raise exception 'invocation not found'; end if;
  select * into v_principal from atlas.principals where id=v_inv.principal_id;
  if v_principal.user_id<>v_user then raise exception 'invocation does not belong to current principal'; end if;
  if v_inv.invocation_state<>'needs_confirmation' then raise exception 'invocation is not awaiting confirmation'; end if;

  v_eval:=atlas.evaluate_delegated_agent_command_target_authority_v1(v_inv.authorization_id,v_inv.command_key,v_inv.command_version,v_inv.target);
  if coalesce((v_eval->>'allowed')::boolean,false)=false then raise exception 'delegated authority is no longer valid'; end if;

  update atlas.agent_command_invocations set invocation_state='authorized',confirmed_by_user_id=v_user,confirmed_at=now(),authorized_at=now(),authority_snapshot=v_eval where id=v_inv.id;
  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,from_state,to_state,actor_kind,actor_user_id,evidence)
  values(v_inv.id,'principal_confirmed','needs_confirmation','authorized','principal',v_user,jsonb_build_object('confirmedByUserId',v_user,'authority',v_eval));
  return jsonb_build_object('invocationId',v_inv.id,'state','authorized','confirmed',true);
end;
$$;

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
  select * into v_inv from atlas.agent_command_invocations where id=p_invocation_id for update;
  if not found then raise exception 'invocation not found'; end if;
  if v_inv.invocation_state='executing' then return jsonb_build_object('invocationId',v_inv.id,'state','executing','replayed',true); end if;
  if v_inv.invocation_state<>'authorized' then raise exception 'invocation is not authorized for execution'; end if;
  v_eval:=atlas.evaluate_delegated_agent_command_target_authority_v1(v_inv.authorization_id,v_inv.command_key,v_inv.command_version,v_inv.target);
  if coalesce((v_eval->>'allowed')::boolean,false)=false then raise exception 'delegated authority is no longer valid'; end if;
  update atlas.agent_command_invocations set invocation_state='executing',execution_started_at=now(),authority_snapshot=v_eval where id=v_inv.id;
  insert into atlas.agent_command_invocation_events(invocation_id,event_kind,from_state,to_state,actor_kind,evidence)
  values(v_inv.id,'execution_started','authorized','executing','service',v_eval);
  return jsonb_build_object('invocationId',v_inv.id,'state','executing','replayed',false);
end;
$$;
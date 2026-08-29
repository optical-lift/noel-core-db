create or replace function atlas.worker_record_production_hardening_v1(
  p_task_id uuid,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_role text;
  v_membership_id uuid;
  v_readiness jsonb;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  v_role:=atlas.current_farm_role(v_task.farm_id);
  v_membership_id:=atlas.current_membership_id(v_task.farm_id);
  if v_role not in ('farm_hand','manager') or v_membership_id is null
     or v_task.visibility_scope<>'assigned_worker' or v_task.assigned_membership_id<>v_membership_id then
    raise exception 'This hardening task is not assigned to the signed-in farm member.' using errcode='42501';
  end if;
  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  if not coalesce((v_readiness->>'ready')::boolean,false) then
    raise exception 'This hardening work is not executable in current farm reality.' using errcode='23514';
  end if;
  return atlas.record_production_hardening_v1(p_task_id,p_observed_date,p_note,p_idempotency_key);
end;
$$;

create or replace function atlas.owner_record_production_hardening_v1(
  p_task_id uuid,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare v_farm_id uuid;
begin
  select farm_id into v_farm_id from atlas.tasks where id=p_task_id;
  if v_farm_id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  if not atlas.is_farm_owner(v_farm_id) then raise exception 'Owner membership required for production hardening.' using errcode='42501'; end if;
  return atlas.record_production_hardening_v1(p_task_id,p_observed_date,p_note,p_idempotency_key);
end;
$$;

create or replace function atlas.owner_operator_record_production_hardening_v1(
  p_effective_membership_id uuid,
  p_task_id uuid,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare
  v_context jsonb;
  v_task atlas.tasks%rowtype;
  v_effective_id uuid;
  v_effective_role text;
  v_visible boolean:=false;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  v_effective_id:=(v_context#>>'{effective,membershipId}')::uuid;
  v_effective_role:=v_context#>>'{effective,role}';
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  if v_task.farm_id<>(v_context->>'farmId')::uuid then raise exception 'The hardening task is outside the operated farm.' using errcode='42501'; end if;
  v_visible:=case
    when v_effective_role='owner' then v_task.visibility_scope in ('owner','management','assigned_worker','farm_shared')
    when v_effective_role='manager' then v_task.visibility_scope in ('management','farm_shared') or (v_task.visibility_scope='assigned_worker' and v_task.assigned_membership_id=v_effective_id)
    else v_task.visibility_scope='farm_shared' or (v_task.visibility_scope='assigned_worker' and v_task.assigned_membership_id=v_effective_id)
  end;
  if not v_visible then raise exception 'The hardening task is not visible in the selected worker context.' using errcode='42501'; end if;
  return atlas.record_production_hardening_v1(p_task_id,p_observed_date,p_note,p_idempotency_key);
end;
$$;

create or replace function atlas.worker_record_production_readiness_v1(
  p_task_id uuid,
  p_action text,
  p_surviving_seedlings numeric,
  p_tray_count numeric default null,
  p_observed_date date default current_date,
  p_next_check_date date default null,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare
  v_task atlas.tasks%rowtype;
  v_role text;
  v_membership_id uuid;
  v_readiness jsonb;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Production readiness task was not found.' using errcode='P0002'; end if;
  v_role:=atlas.current_farm_role(v_task.farm_id);
  v_membership_id:=atlas.current_membership_id(v_task.farm_id);
  if v_role not in ('farm_hand','manager') or v_membership_id is null
     or v_task.visibility_scope<>'assigned_worker' or v_task.assigned_membership_id<>v_membership_id then
    raise exception 'This production readiness task is not assigned to the signed-in farm member.' using errcode='42501';
  end if;
  v_readiness:=atlas.task_execution_readiness_v1(p_task_id);
  if p_action in ('ready','failed') and not coalesce((v_readiness->>'ready')::boolean,false) then
    raise exception 'This readiness result is not executable in current farm reality.' using errcode='23514';
  end if;
  return atlas.record_production_readiness_v1(p_task_id,p_action,p_surviving_seedlings,p_tray_count,p_observed_date,p_next_check_date,p_note,p_idempotency_key);
end;
$$;

create or replace function atlas.owner_record_production_readiness_v1(
  p_task_id uuid,
  p_action text,
  p_surviving_seedlings numeric,
  p_tray_count numeric default null,
  p_observed_date date default current_date,
  p_next_check_date date default null,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare v_farm_id uuid;
begin
  select farm_id into v_farm_id from atlas.tasks where id=p_task_id;
  if v_farm_id is null then raise exception 'Production readiness task was not found.' using errcode='P0002'; end if;
  if not atlas.is_farm_owner(v_farm_id) then raise exception 'Owner membership required for production readiness.' using errcode='42501'; end if;
  return atlas.record_production_readiness_v1(p_task_id,p_action,p_surviving_seedlings,p_tray_count,p_observed_date,p_next_check_date,p_note,p_idempotency_key);
end;
$$;

create or replace function atlas.owner_operator_record_production_readiness_v1(
  p_effective_membership_id uuid,
  p_task_id uuid,
  p_action text,
  p_surviving_seedlings numeric,
  p_tray_count numeric default null,
  p_observed_date date default current_date,
  p_next_check_date date default null,
  p_note text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $$
declare
  v_context jsonb;
  v_task atlas.tasks%rowtype;
  v_effective_id uuid;
  v_effective_role text;
  v_visible boolean:=false;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  v_effective_id:=(v_context#>>'{effective,membershipId}')::uuid;
  v_effective_role:=v_context#>>'{effective,role}';
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Production readiness task was not found.' using errcode='P0002'; end if;
  if v_task.farm_id<>(v_context->>'farmId')::uuid then raise exception 'The readiness task is outside the operated farm.' using errcode='42501'; end if;
  v_visible:=case
    when v_effective_role='owner' then v_task.visibility_scope in ('owner','management','assigned_worker','farm_shared')
    when v_effective_role='manager' then v_task.visibility_scope in ('management','farm_shared') or (v_task.visibility_scope='assigned_worker' and v_task.assigned_membership_id=v_effective_id)
    else v_task.visibility_scope='farm_shared' or (v_task.visibility_scope='assigned_worker' and v_task.assigned_membership_id=v_effective_id)
  end;
  if not v_visible then raise exception 'The readiness task is not visible in the selected worker context.' using errcode='42501'; end if;
  return atlas.record_production_readiness_v1(p_task_id,p_action,p_surviving_seedlings,p_tray_count,p_observed_date,p_next_check_date,p_note,p_idempotency_key);
end;
$$;

revoke all on function atlas.record_production_hardening_v1(uuid,date,text,text) from public;
revoke all on function atlas.record_production_readiness_v1(uuid,text,numeric,numeric,date,date,text,text) from public;
grant execute on function atlas.worker_record_production_hardening_v1(uuid,date,text,text) to authenticated;
grant execute on function atlas.owner_record_production_hardening_v1(uuid,date,text,text) to authenticated;
grant execute on function atlas.owner_operator_record_production_hardening_v1(uuid,uuid,date,text,text) to authenticated;
grant execute on function atlas.worker_record_production_readiness_v1(uuid,text,numeric,numeric,date,date,text,text) to authenticated;
grant execute on function atlas.owner_record_production_readiness_v1(uuid,text,numeric,numeric,date,date,text,text) to authenticated;
grant execute on function atlas.owner_operator_record_production_readiness_v1(uuid,uuid,text,numeric,numeric,date,date,text,text) to authenticated;
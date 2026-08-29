alter table atlas.flower_fulfillment_events
  add column if not exists effective_fulfillment_date date;

create index if not exists flower_fulfillment_events_effective_date_idx
  on atlas.flower_fulfillment_events(farm_id,effective_fulfillment_date desc)
  where effective_fulfillment_date is not null;

comment on column atlas.flower_fulfillment_events.effective_fulfillment_date is
  'Physical fulfillment date when known. Legacy rows remain null and retain fulfilled_at as their only timestamp; append-only commercial history is never backfilled by mutation.';

create or replace function atlas.record_flower_fulfillment_core_v1(
  p_task_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_order atlas.flower_sale_orders%rowtype;
  v_existing atlas.flower_fulfillment_events%rowtype;
  v_event atlas.flower_fulfillment_events%rowtype;
  v_order_id uuid;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_transition jsonb;
  v_effective_date date:=(now() at time zone 'America/Chicago')::date;
begin
  if v_key is null then raise exception 'Fulfillment idempotency key is required.' using errcode='22023'; end if;
  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Flower fulfillment task not found.' using errcode='P0002'; end if;
  if v_task.task_type<>'flower_fulfillment' or v_task.status not in ('open','blocked') then
    raise exception 'Task is not an open flower fulfillment.' using errcode='22023';
  end if;
  if p_effective_role not in ('owner','manager','farm_hand') then
    raise exception 'Selected account cannot record flower fulfillment.' using errcode='42501';
  end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_task.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if p_effective_role='farm_hand' and (
    v_task.visibility_scope<>'assigned_worker' or v_task.assigned_membership_id is distinct from p_effective_membership_id
  ) then
    raise exception 'Fulfillment task is not assigned to this worker.' using errcode='42501';
  end if;

  begin v_order_id:=nullif(v_task.metadata->>'flower_sale_order_id','')::uuid;
  exception when invalid_text_representation then v_order_id:=null; end;
  if v_order_id is null then raise exception 'Fulfillment task has no sale order.' using errcode='22023'; end if;
  select * into v_order from atlas.flower_sale_orders where id=v_order_id;
  if v_order.id is null or v_order.farm_id is distinct from v_task.farm_id then
    raise exception 'Fulfillment sale order is outside the task farm.' using errcode='22023';
  end if;

  select * into v_existing from atlas.flower_fulfillment_events where sale_order_id=v_order.id;
  if v_existing.id is not null then
    return jsonb_build_object(
      'fulfillmentEventId',v_existing.id,
      'saleOrderId',v_order.id,
      'taskId',v_task.id,
      'effectiveFulfillmentDate',coalesce(v_existing.effective_fulfillment_date,(v_existing.fulfilled_at at time zone 'America/Chicago')::date),
      'deduplicated',true
    );
  end if;

  insert into atlas.flower_fulfillment_events(
    farm_id,sale_order_id,task_id,fulfilled_at,effective_fulfillment_date,fulfillment_method,recorded_by_membership_id,
    note,idempotency_key,created_by_user_id,metadata
  ) values (
    v_order.farm_id,v_order.id,v_task.id,now(),v_effective_date,v_order.fulfillment_mode,p_effective_membership_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,auth.uid(),
    jsonb_build_object('operatorMode',p_operator_mode,'truthBoundary','actual_handoff','recordedAt',now())
  ) returning * into v_event;

  v_transition:=atlas.record_task_transition_v1_internal(
    v_task.id,'done','flower-fulfillment:'||v_event.id::text,v_effective_date,p_note,null,
    'fulfill','flower_fulfillment',
    jsonb_build_object(
      'flower_sale_order_id',v_order.id,
      'flower_fulfillment_event_id',v_event.id,
      'effective_fulfillment_date',v_effective_date
    ),null
  );

  return jsonb_build_object(
    'fulfillmentEventId',v_event.id,
    'saleOrderId',v_order.id,
    'taskId',v_task.id,
    'effectiveFulfillmentDate',v_event.effective_fulfillment_date,
    'transition',v_transition,
    'deduplicated',false
  );
end;
$function$;

create or replace function atlas.record_flower_fulfillment_late_entry_v1(
  p_task_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_fulfillment_date date,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_order atlas.flower_sale_orders%rowtype;
  v_existing atlas.flower_fulfillment_events%rowtype;
  v_event atlas.flower_fulfillment_events%rowtype;
  v_order_id uuid;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_transition jsonb;
begin
  if p_fulfillment_date is null then raise exception 'Fulfillment date is required.' using errcode='22023'; end if;
  if p_fulfillment_date>v_today then raise exception 'Fulfillment date cannot be in the future.' using errcode='22023'; end if;
  if v_key is null then raise exception 'Fulfillment idempotency key is required.' using errcode='22023'; end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Flower fulfillment task not found.' using errcode='P0002'; end if;
  if v_task.task_type<>'flower_fulfillment' or v_task.status not in ('open','blocked') then
    raise exception 'Task is not an open flower fulfillment.' using errcode='22023';
  end if;
  if p_effective_role not in ('owner','manager','farm_hand') then
    raise exception 'Selected account cannot record flower fulfillment.' using errcode='42501';
  end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_task.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if p_effective_role='farm_hand' and (
    v_task.visibility_scope<>'assigned_worker' or v_task.assigned_membership_id is distinct from p_effective_membership_id
  ) then
    raise exception 'Fulfillment task is not assigned to this worker.' using errcode='42501';
  end if;

  begin v_order_id:=nullif(v_task.metadata->>'flower_sale_order_id','')::uuid;
  exception when invalid_text_representation then v_order_id:=null; end;
  if v_order_id is null then raise exception 'Fulfillment task has no sale order.' using errcode='22023'; end if;
  select * into v_order from atlas.flower_sale_orders where id=v_order_id;
  if v_order.id is null or v_order.farm_id is distinct from v_task.farm_id then
    raise exception 'Fulfillment sale order is outside the task farm.' using errcode='22023';
  end if;

  select * into v_existing from atlas.flower_fulfillment_events where sale_order_id=v_order.id;
  if v_existing.id is not null then
    return jsonb_build_object(
      'fulfillmentEventId',v_existing.id,
      'saleOrderId',v_order.id,
      'taskId',v_task.id,
      'effectiveFulfillmentDate',coalesce(v_existing.effective_fulfillment_date,(v_existing.fulfilled_at at time zone 'America/Chicago')::date),
      'deduplicated',true
    );
  end if;

  insert into atlas.flower_fulfillment_events(
    farm_id,sale_order_id,task_id,fulfilled_at,effective_fulfillment_date,fulfillment_method,recorded_by_membership_id,
    note,idempotency_key,created_by_user_id,metadata
  ) values (
    v_order.farm_id,v_order.id,v_task.id,now(),p_fulfillment_date,v_order.fulfillment_mode,p_effective_membership_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,auth.uid(),
    jsonb_build_object(
      'operatorMode',p_operator_mode,
      'truthBoundary','actual_handoff_date_with_late_entry_recorded_at',
      'lateEntry',p_fulfillment_date<v_today,
      'effectiveFulfillmentDate',p_fulfillment_date,
      'recordedAt',now()
    )
  ) returning * into v_event;

  v_transition:=atlas.record_task_transition_v1_internal(
    v_task.id,'done','flower-fulfillment:'||v_event.id::text,p_fulfillment_date,p_note,'late_entry_recovery',
    'fulfill','flower_fulfillment',
    jsonb_build_object(
      'flower_sale_order_id',v_order.id,
      'flower_fulfillment_event_id',v_event.id,
      'effective_fulfillment_date',p_fulfillment_date,
      'late_entry_recorded_at',now()
    ),null
  );

  return jsonb_build_object(
    'fulfillmentEventId',v_event.id,
    'saleOrderId',v_order.id,
    'taskId',v_task.id,
    'effectiveFulfillmentDate',v_event.effective_fulfillment_date,
    'recordedAt',v_event.fulfilled_at,
    'transition',v_transition,
    'deduplicated',false,
    'lateEntry',p_fulfillment_date<v_today
  );
end;
$function$;

revoke all on function atlas.record_flower_fulfillment_late_entry_v1(uuid,uuid,text,date,text,text,boolean) from public,anon,authenticated;
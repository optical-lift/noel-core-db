BEGIN;

-- Explicitly accept requested flower demand into committed demand without
-- collapsing demand, inventory reservation, sale, fulfillment, or payment truth.
-- The event is durable provenance for the requested -> committed transition;
-- the demand row's demand_strength remains the current-state projection used by
-- existing coverage and demand-to-sale authorities.

create table if not exists atlas.flower_demand_commitment_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  demand_order_id uuid not null references atlas.flower_demand_orders(id) on delete restrict,
  from_strength text not null default 'requested',
  to_strength text not null default 'committed',
  note text,
  recorded_by_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  idempotency_key text not null,
  created_by_user_id uuid default auth.uid(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_demand_commitment_transition_check
    check (from_strength = 'requested' and to_strength = 'committed'),
  constraint flower_demand_commitment_order_unique unique (demand_order_id),
  constraint flower_demand_commitment_idempotency_unique unique (farm_id, idempotency_key)
);

comment on table atlas.flower_demand_commitment_events is
  'Append-only provenance for explicit requested -> committed flower demand acceptance. Creates no inventory, sale, fulfillment, task, or payment truth.';

alter table atlas.flower_demand_commitment_events enable row level security;

drop policy if exists flower_demand_commitment_member_read_v1 on atlas.flower_demand_commitment_events;
create policy flower_demand_commitment_member_read_v1
  on atlas.flower_demand_commitment_events
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

grant select on atlas.flower_demand_commitment_events to authenticated;
grant all on atlas.flower_demand_commitment_events to service_role;
revoke all on atlas.flower_demand_commitment_events from anon;

create or replace function atlas.validate_flower_demand_commitment_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_order_farm uuid;
  v_member_farm uuid;
begin
  select farm_id into v_order_farm
  from atlas.flower_demand_orders
  where id = new.demand_order_id;

  select farm_id into v_member_farm
  from atlas.farm_memberships
  where id = new.recorded_by_membership_id
    and active = true;

  if v_order_farm is null
     or v_member_farm is null
     or v_order_farm is distinct from new.farm_id
     or v_member_farm is distinct from new.farm_id then
    raise exception 'Flower demand commitment is outside its farm.' using errcode='22023';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.validate_flower_demand_commitment_v1() from public, anon, authenticated;

drop trigger if exists flower_demand_commitment_validate_v1 on atlas.flower_demand_commitment_events;
create trigger flower_demand_commitment_validate_v1
  before insert or update on atlas.flower_demand_commitment_events
  for each row execute function atlas.validate_flower_demand_commitment_v1();

create or replace function atlas.commit_flower_demand_order_core_v1(
  p_demand_order_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_order atlas.flower_demand_orders%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_existing atlas.flower_demand_commitment_events%rowtype;
  v_key text := nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if v_key is null then
    raise exception 'Demand commitment idempotency key is required.' using errcode='22023';
  end if;

  if p_effective_role not in ('owner','manager') then
    raise exception 'Owner or Manager authority is required to commit flower demand.' using errcode='42501';
  end if;

  select * into v_order
  from atlas.flower_demand_orders
  where id = p_demand_order_id
  for update;

  if v_order.id is null then
    raise exception 'Flower demand order not found.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.farm_memberships
  where id = p_effective_membership_id;

  if v_member.id is null
     or not v_member.active
     or v_member.farm_id is distinct from v_order.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  if exists (
    select 1
    from atlas.flower_demand_order_cancellation_events
    where demand_order_id = v_order.id
  ) then
    raise exception 'Cancelled flower demand cannot be committed.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.flower_demand_commitment_events
  where demand_order_id = v_order.id;

  if v_existing.id is not null then
    return jsonb_build_object(
      'demandOrderId', v_order.id,
      'commitmentEventId', v_existing.id,
      'demandStrength', 'committed',
      'deduplicated', true,
      'supplyClaimed', false,
      'saleRecorded', false,
      'workerTimeScheduled', false,
      'paymentStatus', 'not_recorded'
    );
  end if;

  if exists (
    select 1
    from atlas.flower_demand_commitment_events
    where farm_id = v_order.farm_id
      and idempotency_key = v_key
      and demand_order_id is distinct from v_order.id
  ) then
    raise exception 'Demand commitment idempotency key is already used by another order.' using errcode='22023';
  end if;

  if v_order.demand_strength = 'committed' then
    return jsonb_build_object(
      'demandOrderId', v_order.id,
      'commitmentEventId', null,
      'demandStrength', 'committed',
      'alreadyCommitted', true,
      'deduplicated', true,
      'supplyClaimed', false,
      'saleRecorded', false,
      'workerTimeScheduled', false,
      'paymentStatus', 'not_recorded'
    );
  end if;

  if v_order.demand_strength <> 'requested' then
    raise exception 'Only requested flower demand may transition to committed.' using errcode='22023';
  end if;

  insert into atlas.flower_demand_commitment_events(
    farm_id,
    demand_order_id,
    from_strength,
    to_strength,
    note,
    recorded_by_membership_id,
    idempotency_key,
    created_by_user_id,
    metadata
  ) values (
    v_order.farm_id,
    v_order.id,
    'requested',
    'committed',
    nullif(btrim(coalesce(p_note,'')),''),
    p_effective_membership_id,
    v_key,
    auth.uid(),
    jsonb_build_object(
      'operatorMode', p_operator_mode,
      'truthBoundary', 'demand_commitment_acceptance',
      'supplyClaimed', false,
      'saleTruth', false,
      'workerTimeScheduled', false,
      'paymentTruth', false
    )
  ) returning * into v_existing;

  update atlas.flower_demand_orders
  set demand_strength = 'committed'
  where id = v_order.id;

  return jsonb_build_object(
    'demandOrderId', v_order.id,
    'commitmentEventId', v_existing.id,
    'demandStrength', 'committed',
    'deduplicated', false,
    'supplyClaimed', false,
    'saleRecorded', false,
    'workerTimeScheduled', false,
    'paymentStatus', 'not_recorded'
  );
end;
$function$;

revoke all on function atlas.commit_flower_demand_order_core_v1(uuid,uuid,text,text,text,boolean) from public, anon, authenticated;
grant execute on function atlas.commit_flower_demand_order_core_v1(uuid,uuid,text,text,text,boolean) to service_role;

create or replace function atlas.commit_flower_demand_order_for_member_v1(
  p_farm_id uuid,
  p_demand_order_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_role text;
  v_membership uuid;
begin
  v_role := atlas.current_farm_role(p_farm_id);
  v_membership := atlas.current_membership_id(p_farm_id);

  if auth.uid() is null or v_role is null or v_membership is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  return atlas.commit_flower_demand_order_core_v1(
    p_demand_order_id,
    v_membership,
    v_role,
    p_note,
    p_idempotency_key,
    false
  );
end;
$function$;

revoke all on function atlas.commit_flower_demand_order_for_member_v1(uuid,uuid,text,text) from public, anon;
grant execute on function atlas.commit_flower_demand_order_for_member_v1(uuid,uuid,text,text) to authenticated, service_role;

create or replace function atlas.owner_operator_commit_flower_demand_order_v1(
  p_effective_membership_id uuid,
  p_demand_order_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_context jsonb;
begin
  v_context := atlas.owner_operator_context_v1(p_effective_membership_id);

  return atlas.commit_flower_demand_order_core_v1(
    p_demand_order_id,
    (v_context#>>'{effective,membershipId}')::uuid,
    v_context#>>'{effective,role}',
    p_note,
    p_idempotency_key,
    true
  );
end;
$function$;

revoke all on function atlas.owner_operator_commit_flower_demand_order_v1(uuid,uuid,text,text) from public, anon;
grant execute on function atlas.owner_operator_commit_flower_demand_order_v1(uuid,uuid,text,text) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values
  (
    'atlas.commit_flower_demand_order_for_member_v1(uuid, uuid, text, text)',
    'app_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose', 'Explicitly accept requested flower demand into committed demand without claiming inventory or recording a sale.',
      'boundary', 'Owner or Manager authority required.',
      'historyTruth', 'Commitment acceptance is durable in flower_demand_commitment_events.',
      'inventoryTruth', 'Commitment creates no Ready reservation or inventory claim.',
      'saleTruth', 'Commitment creates no Sale, fulfillment, or payment truth.',
      'caller', 'Reserved for farm-atlas demand acceptance wiring; no app caller in this migration.'
    ),
    now(),
    false
  ),
  (
    'atlas.owner_operator_commit_flower_demand_order_v1(uuid, uuid, text, text)',
    'owner_admin_endpoint',
    'verified',
    'active',
    true,
    true,
    true,
    0,
    0,
    jsonb_build_object(
      'purpose', 'Perform the same requested-to-committed demand acceptance in Owner operator mode.',
      'boundary', 'owner_operator_context_v1 resolves effective membership; effective role must be Owner or Manager.',
      'historyTruth', 'Commitment acceptance is durable in flower_demand_commitment_events.',
      'inventoryTruth', 'Operator mode cannot manufacture Ready inventory or reservation truth.',
      'saleTruth', 'Operator mode cannot manufacture Sale, fulfillment, or payment truth.',
      'caller', 'Reserved for farm-atlas demand acceptance wiring; no app caller in this migration.'
    ),
    now(),
    false
  )
on conflict (signature) do update
set
  classification = excluded.classification,
  confidence = excluded.confidence,
  review_status = excluded.review_status,
  authenticated_execute_expected = excluded.authenticated_execute_expected,
  security_definer_expected = excluded.security_definer_expected,
  service_execute_expected = excluded.service_execute_expected,
  caller_count = excluded.caller_count,
  policy_reference_count = excluded.policy_reference_count,
  evidence = excluded.evidence,
  reviewed_at = excluded.reviewed_at,
  anonymous_execute_expected = excluded.anonymous_execute_expected;

COMMIT;

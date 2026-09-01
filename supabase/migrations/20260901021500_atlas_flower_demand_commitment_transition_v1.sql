BEGIN;

-- Explicitly accept requested flower demand into committed demand without
-- collapsing demand, inventory reservation, sale, fulfillment, or payment truth.
-- Flower demand orders are append-only commercial evidence, so acceptance is
-- recorded as a durable event rather than mutating the original demand row.
-- Existing orders born as committed remain committed without a synthetic event.

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
  before insert on atlas.flower_demand_commitment_events
  for each row execute function atlas.validate_flower_demand_commitment_v1();

drop trigger if exists flower_demand_commitment_append_only_v1 on atlas.flower_demand_commitment_events;
create trigger flower_demand_commitment_append_only_v1
  before update or delete on atlas.flower_demand_commitment_events
  for each row execute function atlas.prevent_flower_commercial_truth_mutation_v1();

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

  -- A demand recorded as committed at intake already carries explicit commitment
  -- truth in the immutable order itself. Do not fabricate a second history event.
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

-- Preserve the existing canonical Demand -> Sale kernel, but recognize the
-- append-only commitment event as effective committed state. This keeps old
-- orders born as committed working while allowing requested demand to move
-- forward without rewriting its original evidence row.
create or replace function atlas.record_flower_sale_from_demand_core_v1(
  p_demand_order_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_tax_amount numeric,
  p_tip_amount numeric,
  p_fulfillment_membership_id uuid,
  p_source_task_id uuid,
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
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_existing_sale uuid;
  v_sale_result jsonb;
  v_sale_id uuid;
  v_sale_lines jsonb;
  v_bad integer;
  v_release_count integer:=0;
  v_link_count integer:=0;
  v_target_line_count integer:=0;
  v_fulfillment_date date;
  v_fulfillment_time time without time zone;
  v_effective_committed boolean:=false;
begin
  if v_key is null then
    raise exception 'Demand-to-sale idempotency key is required.' using errcode='22023';
  end if;
  if p_effective_role not in ('owner','manager') then
    raise exception 'Owner or Manager authority is required to convert flower demand to sale.' using errcode='42501';
  end if;

  select * into v_order
  from atlas.flower_demand_orders
  where id=p_demand_order_id
  for update;

  if v_order.id is null then
    raise exception 'Flower demand order not found.' using errcode='P0002';
  end if;

  select * into v_member
  from atlas.farm_memberships
  where id=p_effective_membership_id;

  if v_member.id is null
     or not v_member.active
     or v_member.farm_id is distinct from v_order.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  if exists(
    select 1
    from atlas.flower_demand_order_cancellation_events
    where demand_order_id=v_order.id
  ) then
    raise exception 'Cancelled flower demand cannot become a sale.' using errcode='22023';
  end if;

  v_effective_committed :=
    v_order.demand_strength='committed'
    or exists(
      select 1
      from atlas.flower_demand_commitment_events c
      where c.demand_order_id=v_order.id
        and c.to_strength='committed'
    );

  if not v_effective_committed then
    raise exception 'Only committed flower demand may convert to sale.' using errcode='22023';
  end if;

  select so.id into v_existing_sale
  from atlas.flower_demand_sale_order_links dsl
  join atlas.flower_sale_orders so on so.id=dsl.sale_order_id
  where dsl.demand_order_id=v_order.id
    and not exists(
      select 1
      from atlas.flower_sale_order_cancellation_events c
      where c.sale_order_id=so.id
    )
  order by so.created_at desc
  limit 1;

  if v_existing_sale is not null then
    return jsonb_build_object(
      'demandOrderId',v_order.id,
      'saleOrderId',v_existing_sale,
      'deduplicated',true,
      'coverageState','sold_committed'
    );
  end if;

  select count(*) into v_bad
  from atlas.flower_demand_coverage_v1 c
  where c.demand_order_id=v_order.id
    and (c.coverage_state<>'covered' or c.sold_quantity<>0);

  if v_bad>0 then
    raise exception 'Demand must be fully reserved, with no active prior sale, before conversion.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.flower_demand_order_lines
    where demand_order_id=v_order.id
  ) then
    raise exception 'Demand has no product lines.' using errcode='22023';
  end if;

  if exists(
    select 1
    from atlas.flower_demand_order_lines
    where demand_order_id=v_order.id
      and target_unit_price is null
  ) then
    raise exception 'Every demand line requires a target unit price before sale conversion.' using errcode='22023';
  end if;

  with active as (
    select a.id as allocation_id,a.ready_lot_id,a.quantity,dl.target_unit_price
    from atlas.flower_demand_allocations a
    join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
    where dl.demand_order_id=v_order.id
      and not exists(
        select 1
        from atlas.flower_demand_allocation_release_events r
        where r.allocation_id=a.id
      )
      and not exists(
        select 1
        from atlas.flower_demand_sale_line_links sl
        where sl.allocation_id=a.id
      )
  ), grouped as (
    select ready_lot_id,
           sum(quantity) as quantity,
           min(target_unit_price) as unit_price,
           max(target_unit_price) as max_unit_price
    from active
    group by ready_lot_id
  )
  select count(*) filter(where unit_price is distinct from max_unit_price),
         coalesce(
           jsonb_agg(
             jsonb_build_object(
               'readyLotId',ready_lot_id,
               'quantity',quantity,
               'unitPrice',unit_price
             )
             order by ready_lot_id
           ),
           '[]'::jsonb
         )
  into v_bad,v_sale_lines
  from grouped;

  if jsonb_array_length(v_sale_lines)=0 then
    raise exception 'Covered demand has no active allocations to convert.' using errcode='22023';
  end if;
  if v_bad>0 then
    raise exception 'Allocations sharing one Ready lot must use the same demand unit price.' using errcode='22023';
  end if;

  insert into atlas.flower_demand_allocation_release_events(
    farm_id,allocation_id,reason_kind,note,recorded_by_membership_id,
    idempotency_key,created_by_user_id,metadata
  )
  select a.farm_id,
         a.id,
         'converted_to_sale',
         null,
         p_effective_membership_id,
         v_key||':release:'||a.id::text,
         auth.uid(),
         jsonb_build_object(
           'operatorMode',p_operator_mode,
           'truthBoundary','atomic_demand_to_sale_conversion'
         )
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  where dl.demand_order_id=v_order.id
    and not exists(
      select 1
      from atlas.flower_demand_allocation_release_events r
      where r.allocation_id=a.id
    )
    and not exists(
      select 1
      from atlas.flower_demand_sale_line_links sl
      where sl.allocation_id=a.id
    );
  get diagnostics v_release_count=row_count;

  if v_order.fulfillment_mode='immediate_handoff' then
    v_fulfillment_date:=null;
    v_fulfillment_time:=null;
  else
    v_fulfillment_date:=v_order.requested_for_date;
    v_fulfillment_time:=v_order.fulfillment_due_time;
  end if;

  v_sale_result:=atlas.record_flower_sale_core_v2(
    v_order.farm_id,
    p_effective_membership_id,
    p_effective_role,
    v_order.buyer_relationship_id,
    v_order.customer_label,
    v_order.sales_channel,
    'demand:'||v_order.id::text,
    v_sale_lines,
    coalesce(p_tax_amount,0),
    coalesce(p_tip_amount,0),
    v_order.fulfillment_mode,
    v_fulfillment_date,
    v_fulfillment_time,
    p_fulfillment_membership_id,
    p_source_task_id,
    coalesce(nullif(btrim(coalesce(p_note,'')),''),v_order.note),
    v_key,
    p_operator_mode
  );

  v_sale_id:=(v_sale_result->>'saleOrderId')::uuid;
  if v_sale_id is null then
    raise exception 'Demand conversion did not produce a sale order.' using errcode='P0001';
  end if;

  insert into atlas.flower_demand_sale_order_links(
    farm_id,demand_order_id,sale_order_id,metadata
  ) values (
    v_order.farm_id,
    v_order.id,
    v_sale_id,
    jsonb_build_object(
      'truthBoundary','demand_to_sale_provenance',
      'conversionIdempotencyKey',v_key
    )
  );

  insert into atlas.flower_demand_sale_line_links(
    farm_id,allocation_id,demand_line_id,sale_order_line_id,quantity,metadata
  )
  select a.farm_id,
         a.id,
         a.demand_line_id,
         sol.id,
         a.quantity,
         jsonb_build_object(
           'truthBoundary','allocation_to_sale_provenance',
           'conversionIdempotencyKey',v_key
         )
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  join atlas.flower_demand_allocation_release_events r
    on r.allocation_id=a.id
   and r.idempotency_key=v_key||':release:'||a.id::text
  join atlas.flower_sale_order_lines sol
    on sol.sale_order_id=v_sale_id
   and sol.ready_lot_id=a.ready_lot_id
  where dl.demand_order_id=v_order.id;
  get diagnostics v_link_count=row_count;

  select count(*) into v_target_line_count
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  join atlas.flower_demand_allocation_release_events r
    on r.allocation_id=a.id
   and r.idempotency_key=v_key||':release:'||a.id::text
  where dl.demand_order_id=v_order.id;

  if v_link_count<>v_target_line_count or v_link_count<>v_release_count then
    raise exception 'Demand conversion provenance did not link every released allocation.' using errcode='P0001';
  end if;

  return jsonb_build_object(
    'demandOrderId',v_order.id,
    'saleOrderId',v_sale_id,
    'sale',v_sale_result,
    'convertedAllocationCount',v_link_count,
    'coverageState','sold_committed',
    'deduplicated',false
  );
end;
$function$;

revoke all on function atlas.record_flower_sale_from_demand_core_v1(uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean) from public, anon, authenticated;
grant execute on function atlas.record_flower_sale_from_demand_core_v1(uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean) to service_role;

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
      'historyTruth', 'Commitment acceptance is durable in flower_demand_commitment_events; the original demand row remains immutable.',
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
      'historyTruth', 'Commitment acceptance is durable in flower_demand_commitment_events; the original demand row remains immutable.',
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

BEGIN;

-- Flower demand rows and lines are immutable evidence. Commercial acceptance and
-- pricing changes therefore live in append-only events, while canonical read
-- projections and Demand -> Sale consume the effective current terms.

create table atlas.flower_demand_line_pricing_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  demand_line_id uuid not null references atlas.flower_demand_order_lines(id) on delete restrict,
  unit_price numeric not null check (unit_price >= 0),
  currency text not null,
  reason_kind text not null check (reason_kind in ('price_set','price_revised','entry_correction','other')),
  note text,
  recorded_by_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  idempotency_key text not null,
  created_by_user_id uuid default auth.uid(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_demand_line_pricing_idempotency_unique unique (farm_id,idempotency_key)
);

create index flower_demand_line_pricing_latest_idx
  on atlas.flower_demand_line_pricing_events (demand_line_id,created_at desc,id desc);

comment on table atlas.flower_demand_line_pricing_events is
  'Append-only pricing evidence for flower demand. Latest event supersedes earlier price evidence for conversion/projection without mutating the original demand line.';

alter table atlas.flower_demand_line_pricing_events enable row level security;
create policy flower_demand_line_pricing_member_read_v1
  on atlas.flower_demand_line_pricing_events
  for select to authenticated
  using (atlas.is_farm_member(farm_id));

grant select on atlas.flower_demand_line_pricing_events to authenticated;
grant all on atlas.flower_demand_line_pricing_events to service_role;
revoke all on atlas.flower_demand_line_pricing_events from anon;

create or replace function atlas.validate_flower_demand_line_pricing_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_line_farm uuid;
  v_line_currency text;
  v_member_farm uuid;
begin
  select farm_id,currency into v_line_farm,v_line_currency
  from atlas.flower_demand_order_lines
  where id=new.demand_line_id;

  select farm_id into v_member_farm
  from atlas.farm_memberships
  where id=new.recorded_by_membership_id and active=true;

  if v_line_farm is null
     or v_member_farm is null
     or v_line_farm is distinct from new.farm_id
     or v_member_farm is distinct from new.farm_id then
    raise exception 'Flower demand pricing is outside its farm.' using errcode='22023';
  end if;
  if v_line_currency is distinct from new.currency then
    raise exception 'Flower demand pricing currency must match the demand line.' using errcode='22023';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.validate_flower_demand_line_pricing_v1() from public,anon,authenticated;

create trigger flower_demand_line_pricing_validate_v1
  before insert on atlas.flower_demand_line_pricing_events
  for each row execute function atlas.validate_flower_demand_line_pricing_v1();

create trigger flower_demand_line_pricing_append_only_v1
  before update or delete on atlas.flower_demand_line_pricing_events
  for each row execute function atlas.prevent_flower_commercial_truth_mutation_v1();

create or replace function atlas.flower_demand_line_effective_unit_price_v1(p_demand_line_id uuid)
returns numeric
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select coalesce(
    (
      select e.unit_price
      from atlas.flower_demand_line_pricing_events e
      where e.demand_line_id=p_demand_line_id
      order by e.created_at desc,e.id desc
      limit 1
    ),
    l.target_unit_price
  )
  from atlas.flower_demand_order_lines l
  where l.id=p_demand_line_id;
$function$;

revoke all on function atlas.flower_demand_line_effective_unit_price_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.flower_demand_line_effective_unit_price_v1(uuid) to service_role;

create or replace function atlas.record_flower_demand_line_price_core_v1(
  p_demand_line_id uuid,
  p_unit_price numeric,
  p_reason_kind text,
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
  v_line atlas.flower_demand_order_lines%rowtype;
  v_order atlas.flower_demand_orders%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_existing atlas.flower_demand_line_pricing_events%rowtype;
  v_event atlas.flower_demand_line_pricing_events%rowtype;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_prior_price numeric;
begin
  if v_key is null then raise exception 'Demand pricing idempotency key is required.' using errcode='22023'; end if;
  if p_effective_role not in ('owner','manager') then raise exception 'Owner or Manager authority is required to price flower demand.' using errcode='42501'; end if;
  if p_unit_price is null or p_unit_price<0 then raise exception 'Flower demand unit price must be non-negative.' using errcode='22023'; end if;
  if p_reason_kind not in ('price_set','price_revised','entry_correction','other') then raise exception 'Choose a supported flower demand pricing reason.' using errcode='22023'; end if;

  select * into v_line from atlas.flower_demand_order_lines where id=p_demand_line_id for update;
  if v_line.id is null then raise exception 'Flower demand line not found.' using errcode='P0002'; end if;
  select * into v_order from atlas.flower_demand_orders where id=v_line.demand_order_id for update;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;

  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_order.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if exists(select 1 from atlas.flower_demand_order_cancellation_events where demand_order_id=v_order.id) then
    raise exception 'Cancelled flower demand cannot be priced.' using errcode='22023';
  end if;
  if exists(
    select 1
    from atlas.flower_demand_sale_order_links dsl
    join atlas.flower_sale_orders so on so.id=dsl.sale_order_id
    where dsl.demand_order_id=v_order.id
      and not exists(select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=so.id)
  ) then
    raise exception 'Sold flower demand cannot be repriced.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.flower_demand_line_pricing_events
  where farm_id=v_order.farm_id and idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.demand_line_id is distinct from v_line.id then
      raise exception 'Demand pricing idempotency key is already used by another line.' using errcode='22023';
    end if;
    return jsonb_build_object(
      'pricingEventId',v_existing.id,'demandOrderId',v_order.id,'demandLineId',v_line.id,
      'unitPrice',v_existing.unit_price,'currency',v_existing.currency,'reasonKind',v_existing.reason_kind,
      'deduplicated',true,'saleRecorded',false,'paymentStatus','not_recorded'
    );
  end if;

  v_prior_price:=atlas.flower_demand_line_effective_unit_price_v1(v_line.id);
  insert into atlas.flower_demand_line_pricing_events(
    farm_id,demand_line_id,unit_price,currency,reason_kind,note,recorded_by_membership_id,
    idempotency_key,created_by_user_id,metadata
  ) values (
    v_order.farm_id,v_line.id,round(p_unit_price,2),v_line.currency,p_reason_kind,
    nullif(btrim(coalesce(p_note,'')),''),p_effective_membership_id,v_key,auth.uid(),
    jsonb_strip_nulls(jsonb_build_object(
      'operatorMode',p_operator_mode,
      'truthBoundary','demand_pricing_evidence',
      'priorEffectiveUnitPrice',v_prior_price,
      'saleTruth',false,
      'paymentTruth',false
    ))
  ) returning * into v_event;

  return jsonb_build_object(
    'pricingEventId',v_event.id,'demandOrderId',v_order.id,'demandLineId',v_line.id,
    'unitPrice',v_event.unit_price,'currency',v_event.currency,'reasonKind',v_event.reason_kind,
    'priorEffectiveUnitPrice',v_prior_price,'deduplicated',false,'saleRecorded',false,'paymentStatus','not_recorded'
  );
end;
$function$;

revoke all on function atlas.record_flower_demand_line_price_core_v1(uuid,numeric,text,uuid,text,text,text,boolean) from public,anon,authenticated;
grant execute on function atlas.record_flower_demand_line_price_core_v1(uuid,numeric,text,uuid,text,text,text,boolean) to service_role;

create or replace function atlas.record_flower_demand_line_price_for_member_v1(
  p_farm_id uuid,
  p_demand_line_id uuid,
  p_unit_price numeric,
  p_reason_kind text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.record_flower_demand_line_price_core_v1(
    p_demand_line_id,p_unit_price,p_reason_kind,v_membership,v_role,p_note,p_idempotency_key,false
  );
end;
$function$;

revoke all on function atlas.record_flower_demand_line_price_for_member_v1(uuid,uuid,numeric,text,text,text) from public,anon;
grant execute on function atlas.record_flower_demand_line_price_for_member_v1(uuid,uuid,numeric,text,text,text) to authenticated,service_role;

create or replace function atlas.owner_operator_record_flower_demand_line_price_v1(
  p_effective_membership_id uuid,
  p_demand_line_id uuid,
  p_unit_price numeric,
  p_reason_kind text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_context jsonb;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  return atlas.record_flower_demand_line_price_core_v1(
    p_demand_line_id,p_unit_price,p_reason_kind,
    (v_context#>>'{effective,membershipId}')::uuid,v_context#>>'{effective,role}',
    p_note,p_idempotency_key,true
  );
end;
$function$;

revoke all on function atlas.owner_operator_record_flower_demand_line_price_v1(uuid,uuid,numeric,text,text,text) from public,anon;
grant execute on function atlas.owner_operator_record_flower_demand_line_price_v1(uuid,uuid,numeric,text,text,text) to authenticated,service_role;

-- Keep canonical demand read models aligned with append-only acceptance/pricing.
create or replace view atlas.flower_demand_line_position_v1 as
select
  o.id as demand_order_id,
  o.farm_id,
  o.buyer_relationship_id,
  o.customer_label,
  case when o.demand_strength='committed' or ce.id is not null then 'committed' else o.demand_strength end as demand_strength,
  o.sales_channel,
  o.requested_for_date,
  o.fulfillment_mode,
  o.fulfillment_due_time,
  o.source_standing_order_id,
  l.id as demand_line_id,
  l.inventory_kind,
  l.crop_profile_id,
  l.product_label,
  l.quantity,
  l.unit,
  atlas.flower_demand_line_effective_unit_price_v1(l.id) as target_unit_price,
  l.currency,
  case when c.id is not null then 'cancelled' else 'open' end as demand_state,
  case
    when atlas.flower_demand_line_effective_unit_price_v1(l.id) is null then null::numeric
    else round(l.quantity*atlas.flower_demand_line_effective_unit_price_v1(l.id),2)
  end as target_line_value,
  o.created_at
from atlas.flower_demand_orders o
join atlas.flower_demand_order_lines l on l.demand_order_id=o.id
left join atlas.flower_demand_commitment_events ce on ce.demand_order_id=o.id
left join atlas.flower_demand_order_cancellation_events c on c.demand_order_id=o.id;

create or replace view atlas.flower_demand_coverage_v1 as
with active_allocation as (
  select a.demand_line_id,sum(a.quantity) as quantity
  from atlas.flower_demand_allocations a
  where not exists(select 1 from atlas.flower_demand_allocation_release_events r where r.allocation_id=a.id)
    and not exists(select 1 from atlas.flower_demand_sale_line_links sl where sl.allocation_id=a.id)
  group by a.demand_line_id
), sold as (
  select sl.demand_line_id,
         sum(sl.quantity) filter(where c.id is null) as sold_quantity,
         sum(sl.quantity) filter(where c.id is null and f.id is not null) as fulfilled_quantity
  from atlas.flower_demand_sale_line_links sl
  join atlas.flower_sale_order_lines sol on sol.id=sl.sale_order_line_id
  join atlas.flower_sale_orders so on so.id=sol.sale_order_id
  left join atlas.flower_sale_order_cancellation_events c on c.sale_order_id=so.id
  left join atlas.flower_fulfillment_events f on f.sale_order_id=so.id
  group by sl.demand_line_id
)
select
  o.id as demand_order_id,
  o.farm_id,
  o.buyer_relationship_id,
  o.customer_label,
  case when o.demand_strength='committed' or ce.id is not null then 'committed' else o.demand_strength end as demand_strength,
  o.sales_channel,
  o.requested_for_date,
  o.fulfillment_mode,
  l.id as demand_line_id,
  l.inventory_kind,
  l.crop_profile_id,
  l.product_label,
  l.quantity as demanded_quantity,
  l.unit,
  atlas.flower_demand_line_effective_unit_price_v1(l.id) as target_unit_price,
  case when dc.id is null then coalesce(a.quantity,0::numeric) else 0::numeric end as reserved_quantity,
  case when dc.id is null then coalesce(s.sold_quantity,0::numeric) else 0::numeric end as sold_quantity,
  case when dc.id is null then coalesce(s.fulfilled_quantity,0::numeric) else 0::numeric end as fulfilled_quantity,
  case when dc.id is null then greatest(0::numeric,l.quantity-coalesce(a.quantity,0::numeric)-coalesce(s.sold_quantity,0::numeric)) else 0::numeric end as short_quantity,
  case
    when dc.id is not null then 'cancelled'::text
    when coalesce(a.quantity,0::numeric)+coalesce(s.sold_quantity,0::numeric)=0::numeric then 'uncovered'::text
    when coalesce(a.quantity,0::numeric)+coalesce(s.sold_quantity,0::numeric)<l.quantity then 'short'::text
    when coalesce(a.quantity,0::numeric)+coalesce(s.sold_quantity,0::numeric)=l.quantity then 'covered'::text
    else 'overcovered'::text
  end as coverage_state,
  case
    when atlas.flower_demand_line_effective_unit_price_v1(l.id) is null then null::numeric
    else round(l.quantity*atlas.flower_demand_line_effective_unit_price_v1(l.id),2)
  end as target_demand_value
from atlas.flower_demand_orders o
join atlas.flower_demand_order_lines l on l.demand_order_id=o.id
left join atlas.flower_demand_commitment_events ce on ce.demand_order_id=o.id
left join atlas.flower_demand_order_cancellation_events dc on dc.demand_order_id=o.id
left join active_allocation a on a.demand_line_id=l.id
left join sold s on s.demand_line_id=l.id;

-- Preserve the canonical conversion kernel while consuming effective pricing.
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
  v_existing_sale uuid; v_sale_result jsonb; v_sale_id uuid; v_sale_lines jsonb;
  v_bad integer; v_release_count integer:=0; v_link_count integer:=0; v_target_line_count integer:=0;
  v_fulfillment_date date; v_fulfillment_time time without time zone; v_effective_committed boolean:=false;
begin
  if v_key is null then raise exception 'Demand-to-sale idempotency key is required.' using errcode='22023'; end if;
  if p_effective_role not in ('owner','manager') then raise exception 'Owner or Manager authority is required to convert flower demand to sale.' using errcode='42501'; end if;
  select * into v_order from atlas.flower_demand_orders where id=p_demand_order_id for update;
  if v_order.id is null then raise exception 'Flower demand order not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_order.farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  if exists(select 1 from atlas.flower_demand_order_cancellation_events where demand_order_id=v_order.id) then raise exception 'Cancelled flower demand cannot become a sale.' using errcode='22023'; end if;

  v_effective_committed:=v_order.demand_strength='committed' or exists(
    select 1 from atlas.flower_demand_commitment_events c where c.demand_order_id=v_order.id and c.to_strength='committed'
  );
  if not v_effective_committed then raise exception 'Only committed flower demand may convert to sale.' using errcode='22023'; end if;

  select so.id into v_existing_sale
  from atlas.flower_demand_sale_order_links dsl
  join atlas.flower_sale_orders so on so.id=dsl.sale_order_id
  where dsl.demand_order_id=v_order.id
    and not exists(select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=so.id)
  order by so.created_at desc limit 1;
  if v_existing_sale is not null then
    return jsonb_build_object('demandOrderId',v_order.id,'saleOrderId',v_existing_sale,'deduplicated',true,'coverageState','sold_committed');
  end if;

  select count(*) into v_bad from atlas.flower_demand_coverage_v1 c
  where c.demand_order_id=v_order.id and (c.coverage_state<>'covered' or c.sold_quantity<>0);
  if v_bad>0 then raise exception 'Demand must be fully reserved, with no active prior sale, before conversion.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.flower_demand_order_lines where demand_order_id=v_order.id) then raise exception 'Demand has no product lines.' using errcode='22023'; end if;
  if exists(
    select 1 from atlas.flower_demand_order_lines dl
    where dl.demand_order_id=v_order.id and atlas.flower_demand_line_effective_unit_price_v1(dl.id) is null
  ) then raise exception 'Every demand line requires an effective unit price before sale conversion.' using errcode='22023'; end if;

  with active as (
    select a.id as allocation_id,a.ready_lot_id,a.quantity,atlas.flower_demand_line_effective_unit_price_v1(dl.id) as target_unit_price
    from atlas.flower_demand_allocations a
    join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
    where dl.demand_order_id=v_order.id
      and not exists(select 1 from atlas.flower_demand_allocation_release_events r where r.allocation_id=a.id)
      and not exists(select 1 from atlas.flower_demand_sale_line_links sl where sl.allocation_id=a.id)
  ), grouped as (
    select ready_lot_id,sum(quantity) as quantity,min(target_unit_price) as unit_price,max(target_unit_price) as max_unit_price
    from active group by ready_lot_id
  )
  select count(*) filter(where unit_price is distinct from max_unit_price),
         coalesce(jsonb_agg(jsonb_build_object('readyLotId',ready_lot_id,'quantity',quantity,'unitPrice',unit_price) order by ready_lot_id),'[]'::jsonb)
  into v_bad,v_sale_lines from grouped;
  if jsonb_array_length(v_sale_lines)=0 then raise exception 'Covered demand has no active allocations to convert.' using errcode='22023'; end if;
  if v_bad>0 then raise exception 'Allocations sharing one Ready lot must use the same demand unit price.' using errcode='22023'; end if;

  insert into atlas.flower_demand_allocation_release_events(farm_id,allocation_id,reason_kind,note,recorded_by_membership_id,idempotency_key,created_by_user_id,metadata)
  select a.farm_id,a.id,'converted_to_sale',null,p_effective_membership_id,v_key||':release:'||a.id::text,auth.uid(),jsonb_build_object('operatorMode',p_operator_mode,'truthBoundary','atomic_demand_to_sale_conversion')
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  where dl.demand_order_id=v_order.id
    and not exists(select 1 from atlas.flower_demand_allocation_release_events r where r.allocation_id=a.id)
    and not exists(select 1 from atlas.flower_demand_sale_line_links sl where sl.allocation_id=a.id);
  get diagnostics v_release_count=row_count;

  if v_order.fulfillment_mode='immediate_handoff' then v_fulfillment_date:=null; v_fulfillment_time:=null;
  else v_fulfillment_date:=v_order.requested_for_date; v_fulfillment_time:=v_order.fulfillment_due_time; end if;

  v_sale_result:=atlas.record_flower_sale_core_v2(
    v_order.farm_id,p_effective_membership_id,p_effective_role,v_order.buyer_relationship_id,v_order.customer_label,
    v_order.sales_channel,'demand:'||v_order.id::text,v_sale_lines,coalesce(p_tax_amount,0),coalesce(p_tip_amount,0),
    v_order.fulfillment_mode,v_fulfillment_date,v_fulfillment_time,p_fulfillment_membership_id,p_source_task_id,
    coalesce(nullif(btrim(coalesce(p_note,'')),''),v_order.note),v_key,p_operator_mode
  );
  v_sale_id:=(v_sale_result->>'saleOrderId')::uuid;
  if v_sale_id is null then raise exception 'Demand conversion did not produce a sale order.' using errcode='P0001'; end if;

  insert into atlas.flower_demand_sale_order_links(farm_id,demand_order_id,sale_order_id,metadata)
  values(v_order.farm_id,v_order.id,v_sale_id,jsonb_build_object('truthBoundary','demand_to_sale_provenance','conversionIdempotencyKey',v_key));

  insert into atlas.flower_demand_sale_line_links(farm_id,allocation_id,demand_line_id,sale_order_line_id,quantity,metadata)
  select a.farm_id,a.id,a.demand_line_id,sol.id,a.quantity,jsonb_build_object('truthBoundary','allocation_to_sale_provenance','conversionIdempotencyKey',v_key)
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  join atlas.flower_demand_allocation_release_events r on r.allocation_id=a.id and r.idempotency_key=v_key||':release:'||a.id::text
  join atlas.flower_sale_order_lines sol on sol.sale_order_id=v_sale_id and sol.ready_lot_id=a.ready_lot_id
  where dl.demand_order_id=v_order.id;
  get diagnostics v_link_count=row_count;

  select count(*) into v_target_line_count
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines dl on dl.id=a.demand_line_id
  join atlas.flower_demand_allocation_release_events r on r.allocation_id=a.id and r.idempotency_key=v_key||':release:'||a.id::text
  where dl.demand_order_id=v_order.id;
  if v_link_count<>v_target_line_count or v_link_count<>v_release_count then raise exception 'Demand conversion provenance did not link every released allocation.' using errcode='P0001'; end if;

  return jsonb_build_object('demandOrderId',v_order.id,'saleOrderId',v_sale_id,'sale',v_sale_result,'convertedAllocationCount',v_link_count,'coverageState','sold_committed','deduplicated',false);
end;
$function$;

revoke all on function atlas.record_flower_sale_from_demand_core_v1(uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function atlas.record_flower_sale_from_demand_core_v1(uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,
  security_definer_expected,service_execute_expected,caller_count,policy_reference_count,
  evidence,reviewed_at,anonymous_execute_expected
)
values
(
  'atlas.record_flower_demand_line_price_for_member_v1(uuid, uuid, numeric, text, text, text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Append a governed price or reprice event to an open flower demand line.',
    'boundary','Owner or Manager authority required; immutable demand line is never rewritten.',
    'saleTruth','Pricing creates no Sale, fulfillment, inventory, task, or payment truth.',
    'caller','Reserved for farm-atlas generic flower demand workflow wiring.'
  ),now(),false
),
(
  'atlas.owner_operator_record_flower_demand_line_price_v1(uuid, uuid, numeric, text, text, text)',
  'owner_admin_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Append the same governed flower demand price evidence in Owner operator mode.',
    'boundary','owner_operator_context_v1 resolves effective membership; effective role must be Owner or Manager.',
    'saleTruth','Pricing creates no Sale, fulfillment, inventory, task, or payment truth.',
    'caller','Reserved for farm-atlas generic flower demand workflow wiring.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

COMMIT;

BEGIN;

-- A bundle is not merely a generic counted flower unit. Atlas' canonical flower
-- vocabulary defines a bundle as exactly 5, 10, or 20 stripped stems. Preserve
-- that fact from demand through inventory allocation so a buyer's requested form
-- cannot be silently fulfilled with a different bundle size.

alter table atlas.flower_demand_order_lines
  add column if not exists stems_per_unit integer;

alter table atlas.flower_demand_order_lines
  drop constraint if exists flower_demand_order_lines_bundle_size_check;
alter table atlas.flower_demand_order_lines
  add constraint flower_demand_order_lines_bundle_size_check
  check (
    (inventory_kind = 'bundle' and stems_per_unit in (5,10,20))
    or (inventory_kind <> 'bundle' and stems_per_unit is null)
  );

comment on column atlas.flower_demand_order_lines.stems_per_unit is
  'Canonical bundle size. Required only for bundle demand and limited to 5, 10, or 20 stems.';

create or replace function atlas.record_flower_demand_order_core_v1(
  p_farm_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_buyer_relationship_id uuid,
  p_customer_label text,
  p_demand_strength text,
  p_sales_channel text,
  p_requested_for_date date,
  p_fulfillment_mode text,
  p_fulfillment_due_time time without time zone,
  p_lines jsonb,
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
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_member atlas.farm_memberships%rowtype; v_existing atlas.flower_demand_orders%rowtype;
  v_order atlas.flower_demand_orders%rowtype; v_line jsonb; v_kind text; v_unit text;
  v_quantity numeric; v_price numeric; v_crop uuid; v_stems_per_unit integer;
  v_buyer_farm uuid; v_customer text:=nullif(btrim(coalesce(p_customer_label,'')),'');
  v_rows jsonb:='[]'::jsonb; v_inserted atlas.flower_demand_order_lines%rowtype;
begin
  if v_key is null then raise exception 'Demand idempotency key is required.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':flower-demand:'||v_key,0));
  if p_effective_role not in ('owner','manager','farm_hand') then raise exception 'Selected account cannot record flower demand.' using errcode='42501'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from p_farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select * into v_existing from atlas.flower_demand_orders where farm_id=p_farm_id and idempotency_key=v_key;
  if v_existing.id is not null then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'id',l.id,'inventoryKind',l.inventory_kind,'cropProfileId',l.crop_profile_id,
      'productLabel',l.product_label,'quantity',l.quantity,'unit',l.unit,
      'stemsPerUnit',l.stems_per_unit,'targetUnitPrice',l.target_unit_price
    )) order by l.created_at),'[]'::jsonb) into v_rows
    from atlas.flower_demand_order_lines l where l.demand_order_id=v_existing.id;
    return jsonb_build_object('demandOrderId',v_existing.id,'lines',v_rows,'deduplicated',true);
  end if;
  if p_demand_strength not in ('requested','committed') then raise exception 'Demand strength must be requested or committed.' using errcode='22023'; end if;
  if p_sales_channel not in ('wholesale','farm_pickup','delivery','market','subscription','event','other') then raise exception 'Choose a supported flower demand channel.' using errcode='22023'; end if;
  if p_fulfillment_mode not in ('immediate_handoff','pickup','delivery') then raise exception 'Choose a supported demand fulfillment mode.' using errcode='22023'; end if;
  if p_requested_for_date is null then raise exception 'Demand requires a requested date.' using errcode='22023'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>24 then raise exception 'Demand requires between 1 and 24 product lines.' using errcode='22023'; end if;
  if p_buyer_relationship_id is not null then
    select farm_id,business_name into v_buyer_farm,v_customer from atlas.buyer_relationship_reconstruction where id=p_buyer_relationship_id;
    if v_buyer_farm is null or v_buyer_farm is distinct from p_farm_id then raise exception 'Demand buyer is outside this farm.' using errcode='22023'; end if;
    v_customer:=coalesce(nullif(btrim(coalesce(p_customer_label,'')),''),v_customer);
  elsif v_customer is null then raise exception 'Demand requires a buyer relationship or customer label.' using errcode='22023'; end if;
  insert into atlas.flower_demand_orders(
    farm_id,buyer_relationship_id,customer_label,demand_strength,sales_channel,
    requested_for_date,fulfillment_mode,fulfillment_due_time,recorded_by_membership_id,
    note,idempotency_key,created_by_user_id,metadata
  ) values (
    p_farm_id,p_buyer_relationship_id,v_customer,p_demand_strength,p_sales_channel,
    p_requested_for_date,p_fulfillment_mode,p_fulfillment_due_time,p_effective_membership_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,auth.uid(),jsonb_build_object(
      'operatorMode',p_operator_mode,'truthBoundary','independent_demand',
      'supplyClaimed',false,'workerTimeScheduled',false
    )
  ) returning * into v_order;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_kind:=nullif(btrim(v_line->>'inventoryKind'),'');
    v_unit:=atlas.flower_demand_line_unit_v1(v_kind);
    begin v_quantity:=(v_line->>'quantity')::numeric; exception when others then raise exception 'Invalid quantity in flower demand line.' using errcode='22023'; end;
    begin v_price:=nullif(v_line->>'targetUnitPrice','')::numeric; exception when others then raise exception 'Invalid targetUnitPrice in flower demand line.' using errcode='22023'; end;
    begin v_crop:=nullif(v_line->>'cropProfileId','')::uuid; exception when others then raise exception 'Invalid cropProfileId in flower demand line.' using errcode='22023'; end;
    begin v_stems_per_unit:=nullif(v_line->>'stemsPerUnit','')::integer; exception when others then raise exception 'Invalid stemsPerUnit in flower demand line.' using errcode='22023'; end;
    if v_unit is null then raise exception 'Unsupported flower demand inventory kind.' using errcode='22023'; end if;
    if v_quantity is null or v_quantity<=0 then raise exception 'Flower demand quantity must be positive.' using errcode='22023'; end if;
    if v_price is not null and v_price<0 then raise exception 'Flower demand target price cannot be negative.' using errcode='22023'; end if;
    if v_crop is not null and not exists(select 1 from atlas.crop_profiles where id=v_crop) then raise exception 'Flower demand crop profile was not found.' using errcode='22023'; end if;
    if v_kind='bundle' then
      if v_stems_per_unit not in (5,10,20) then raise exception 'Flower bundle demand must specify exactly 5, 10, or 20 stems per bundle.' using errcode='22023'; end if;
    elsif v_stems_per_unit is not null then
      raise exception 'Only flower bundle demand may specify stemsPerUnit.' using errcode='22023';
    end if;

    insert into atlas.flower_demand_order_lines(
      farm_id,demand_order_id,inventory_kind,crop_profile_id,product_label,quantity,
      unit,stems_per_unit,target_unit_price,currency,metadata
    ) values (
      p_farm_id,v_order.id,v_kind,v_crop,nullif(btrim(coalesce(v_line->>'productLabel','')),''),
      v_quantity,v_unit,v_stems_per_unit,v_price,'USD',jsonb_strip_nulls(jsonb_build_object(
        'truthBoundary','demand_product_requirement','stemsPerUnit',v_stems_per_unit,
        'flowerVocabularyVersion',1
      ))
    ) returning * into v_inserted;
    v_rows:=v_rows||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id',v_inserted.id,'inventoryKind',v_inserted.inventory_kind,
      'cropProfileId',v_inserted.crop_profile_id,'productLabel',v_inserted.product_label,
      'quantity',v_inserted.quantity,'unit',v_inserted.unit,
      'stemsPerUnit',v_inserted.stems_per_unit,'targetUnitPrice',v_inserted.target_unit_price
    )));
  end loop;

  return jsonb_build_object(
    'demandOrderId',v_order.id,'lines',v_rows,'demandStrength',v_order.demand_strength,
    'requestedForDate',v_order.requested_for_date,'deduplicated',false
  );
end;
$function$;

create or replace function atlas.record_flower_demand_allocation_core_v1(
  p_demand_line_id uuid,
  p_ready_lot_id uuid,
  p_quantity numeric,
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
  v_line atlas.flower_demand_order_lines%rowtype; v_order atlas.flower_demand_orders%rowtype; v_ready atlas.flower_ready_inventory_lots%rowtype;
  v_member atlas.farm_memberships%rowtype; v_existing atlas.flower_demand_allocations%rowtype; v_allocation atlas.flower_demand_allocations%rowtype;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),''); v_available numeric; v_remaining numeric; v_ready_stems_per_unit integer;
begin
  if v_key is null then raise exception 'Demand allocation idempotency key is required.' using errcode='22023'; end if;
  if p_effective_role not in ('owner','manager') then raise exception 'Owner or Manager authority is required to allocate flower inventory.' using errcode='42501'; end if;
  select * into v_line from atlas.flower_demand_order_lines where id=p_demand_line_id for update;
  if v_line.id is null then raise exception 'Flower demand line not found.' using errcode='P0002'; end if;
  select * into v_order from atlas.flower_demand_orders where id=v_line.demand_order_id for update;
  if exists(select 1 from atlas.flower_demand_order_cancellation_events where demand_order_id=v_order.id) then raise exception 'Cancelled flower demand cannot receive inventory.' using errcode='22023'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_order.farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  select * into v_existing from atlas.flower_demand_allocations where farm_id=v_order.farm_id and idempotency_key=v_key;
  if v_existing.id is not null then
    return jsonb_build_object('allocationId',v_existing.id,'demandLineId',v_existing.demand_line_id,'readyLotId',v_existing.ready_lot_id,'quantity',v_existing.quantity,'deduplicated',true);
  end if;
  select * into v_ready from atlas.flower_ready_inventory_lots where id=p_ready_lot_id for update;
  if v_ready.id is null or v_ready.farm_id is distinct from v_order.farm_id then raise exception 'Ready inventory is outside the demand farm.' using errcode='22023'; end if;
  if v_ready.inventory_kind is distinct from v_line.inventory_kind or v_ready.unit is distinct from v_line.unit then raise exception 'Ready inventory kind/unit does not match the demand line.' using errcode='22023'; end if;
  if v_line.crop_profile_id is not null and v_ready.crop_profile_id is distinct from v_line.crop_profile_id then raise exception 'Ready crop identity does not match the demand crop.' using errcode='22023'; end if;
  if v_line.inventory_kind='bundle' then
    begin v_ready_stems_per_unit:=nullif(v_ready.metadata->>'stemsPerUnit','')::integer; exception when others then v_ready_stems_per_unit:=null; end;
    if v_ready_stems_per_unit is distinct from v_line.stems_per_unit then
      raise exception 'Ready bundle size does not match the demanded bundle size.' using errcode='22023';
    end if;
  end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'Allocation quantity must be positive.' using errcode='22023'; end if;
  if v_line.unit='bucket_equivalent' then
    if mod(p_quantity*4,1)<>0 then raise exception 'Bucket allocation must use quarter-bucket increments.' using errcode='22023'; end if;
  elsif mod(p_quantity,1)<>0 then raise exception 'Counted allocation units must be whole numbers.' using errcode='22023'; end if;
  v_remaining:=atlas.flower_demand_line_remaining_quantity_v1(v_line.id);
  if p_quantity>coalesce(v_remaining,0) then raise exception 'Allocation would exceed the demand quantity still uncovered.' using errcode='22023'; end if;
  v_available:=atlas.flower_ready_available_quantity_v1(v_ready.id);
  if p_quantity>coalesce(v_available,0) then raise exception 'Allocation would exceed the Ready quantity still Available.' using errcode='22023'; end if;
  insert into atlas.flower_demand_allocations(
    farm_id,demand_line_id,ready_lot_id,quantity,recorded_by_membership_id,note,
    idempotency_key,created_by_user_id,metadata
  ) values (
    v_order.farm_id,v_line.id,v_ready.id,p_quantity,p_effective_membership_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,auth.uid(),jsonb_strip_nulls(jsonb_build_object(
      'operatorMode',p_operator_mode,'truthBoundary','demand_inventory_reservation',
      'saleTruth',false,'stemsPerUnit',v_line.stems_per_unit,'flowerVocabularyVersion',1
    ))
  ) returning * into v_allocation;
  return jsonb_build_object(
    'allocationId',v_allocation.id,'demandLineId',v_line.id,'readyLotId',v_ready.id,
    'quantity',v_allocation.quantity,'stemsPerUnit',v_line.stems_per_unit,
    'remainingDemand',atlas.flower_demand_line_remaining_quantity_v1(v_line.id),
    'readyAvailable',atlas.flower_ready_available_quantity_v1(v_ready.id),'deduplicated',false
  );
end;
$function$;

COMMIT;

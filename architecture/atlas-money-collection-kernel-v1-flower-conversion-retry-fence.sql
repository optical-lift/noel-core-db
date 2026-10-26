-- Atlas Money Collection Kernel v1 — Flower conversion retry fence.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- Demand and Prospect conversion cores each have a legitimate early idempotent
-- return for an already-created Sale. That return occurs before their normal
-- call into record_flower_sale_core_v2. Wrap the whole conversion command so
-- BOTH new conversion and deduplicated conversion enforce the same Sale money
-- postcondition. The subordinate domain implementations remain unexposed.

alter function atlas.record_flower_sale_from_demand_core_v1(
  uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean
) rename to record_flower_sale_from_demand_core_v1_domain_impl;

revoke execute on function atlas.record_flower_sale_from_demand_core_v1_domain_impl(
  uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean
) from public,anon,authenticated,service_role;

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
set search_path=''
as $$
declare
  v_result jsonb;
  v_sale_order_id uuid;
begin
  v_result:=atlas.record_flower_sale_from_demand_core_v1_domain_impl(
    p_demand_order_id,p_effective_membership_id,p_effective_role,
    p_tax_amount,p_tip_amount,p_fulfillment_membership_id,p_source_task_id,
    p_note,p_idempotency_key,p_operator_mode
  );
  begin
    v_sale_order_id:=nullif(v_result->>'saleOrderId','')::uuid;
  exception when others then
    raise exception 'Demand-to-Sale result omitted canonical Sale identity.' using errcode='23514';
  end;
  if v_sale_order_id is null then
    raise exception 'Demand-to-Sale result omitted canonical Sale identity.' using errcode='23514';
  end if;
  perform atlas.ensure_flower_sale_money_obligation_v1(v_sale_order_id);
  return v_result;
end;
$$;

revoke all on function atlas.record_flower_sale_from_demand_core_v1(
  uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean
) from public,anon,authenticated;
grant execute on function atlas.record_flower_sale_from_demand_core_v1(
  uuid,uuid,text,numeric,numeric,uuid,uuid,text,text,boolean
) to service_role;

alter function atlas.record_flower_sale_from_prospect_core_v1(
  uuid,numeric,numeric,uuid,text,text,text,numeric,numeric,text,text,boolean
) rename to record_flower_sale_from_prospect_core_v1_domain_impl;

revoke execute on function atlas.record_flower_sale_from_prospect_core_v1_domain_impl(
  uuid,numeric,numeric,uuid,text,text,text,numeric,numeric,text,text,boolean
) from public,anon,authenticated,service_role;

create or replace function atlas.record_flower_sale_from_prospect_core_v1(
  p_prospect_route_line_id uuid,
  p_quantity numeric,
  p_unit_price numeric,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_customer_label text,
  p_sales_channel text,
  p_tax_amount numeric,
  p_tip_amount numeric,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
  v_sale_order_id uuid;
begin
  v_result:=atlas.record_flower_sale_from_prospect_core_v1_domain_impl(
    p_prospect_route_line_id,p_quantity,p_unit_price,p_effective_membership_id,
    p_effective_role,p_customer_label,p_sales_channel,p_tax_amount,p_tip_amount,
    p_note,p_idempotency_key,p_operator_mode
  );
  begin
    v_sale_order_id:=nullif(v_result->>'saleOrderId','')::uuid;
  exception when others then
    raise exception 'Prospect-to-Sale result omitted canonical Sale identity.' using errcode='23514';
  end;
  if v_sale_order_id is null then
    raise exception 'Prospect-to-Sale result omitted canonical Sale identity.' using errcode='23514';
  end if;
  perform atlas.ensure_flower_sale_money_obligation_v1(v_sale_order_id);
  return v_result;
end;
$$;

revoke all on function atlas.record_flower_sale_from_prospect_core_v1(
  uuid,numeric,numeric,uuid,text,text,text,numeric,numeric,text,text,boolean
) from public,anon,authenticated;
grant execute on function atlas.record_flower_sale_from_prospect_core_v1(
  uuid,numeric,numeric,uuid,text,text,text,numeric,numeric,text,text,boolean
) to service_role;

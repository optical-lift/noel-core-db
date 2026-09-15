begin;

-- Package 4 / Flower Operations commercial command membrane v1.
-- Browser callers receive fixed public delegates only. Canonical Demand, Sale,
-- allocation, and Fulfillment logic remains owned by the existing atlas member commands.

create or replace function public.record_flower_demand_order_self_api_v1(
  p_farm_id uuid,
  p_buyer_relationship_id uuid,
  p_customer_label text,
  p_demand_strength text,
  p_sales_channel text,
  p_requested_for_date date,
  p_fulfillment_mode text,
  p_fulfillment_due_time time without time zone,
  p_lines jsonb,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_demand_order_for_member_v1(
    p_farm_id,p_buyer_relationship_id,p_customer_label,p_demand_strength,p_sales_channel,
    p_requested_for_date,p_fulfillment_mode,p_fulfillment_due_time,p_lines,p_note,p_idempotency_key
  );
$function$;

create or replace function public.commit_flower_demand_order_self_api_v1(
  p_farm_id uuid,
  p_demand_order_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.commit_flower_demand_order_for_member_v1(
    p_farm_id,p_demand_order_id,p_note,p_idempotency_key
  );
$function$;

create or replace function public.record_flower_demand_line_price_self_api_v1(
  p_farm_id uuid,
  p_demand_line_id uuid,
  p_unit_price numeric,
  p_reason_kind text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_demand_line_price_for_member_v1(
    p_farm_id,p_demand_line_id,p_unit_price,p_reason_kind,p_note,p_idempotency_key
  );
$function$;

create or replace function public.record_flower_demand_allocation_self_api_v1(
  p_farm_id uuid,
  p_demand_line_id uuid,
  p_ready_lot_id uuid,
  p_quantity numeric,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_demand_allocation_for_member_v1(
    p_farm_id,p_demand_line_id,p_ready_lot_id,p_quantity,p_note,p_idempotency_key
  );
$function$;

create or replace function public.release_flower_demand_allocation_self_api_v1(
  p_farm_id uuid,
  p_allocation_id uuid,
  p_reason_kind text,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.release_flower_demand_allocation_for_member_v1(
    p_farm_id,p_allocation_id,p_reason_kind,p_note,p_idempotency_key
  );
$function$;

create or replace function public.record_flower_sale_from_demand_self_api_v1(
  p_farm_id uuid,
  p_demand_order_id uuid,
  p_tax_amount numeric,
  p_tip_amount numeric,
  p_fulfillment_membership_id uuid,
  p_source_task_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_sale_from_demand_for_member_v1(
    p_farm_id,p_demand_order_id,p_tax_amount,p_tip_amount,p_fulfillment_membership_id,
    p_source_task_id,p_note,p_idempotency_key
  );
$function$;

create or replace function public.record_flower_sale_self_api_v1(
  p_farm_id uuid,
  p_buyer_relationship_id uuid,
  p_customer_label text,
  p_sales_channel text,
  p_event_key text,
  p_lines jsonb,
  p_tax_amount numeric,
  p_tip_amount numeric,
  p_fulfillment_mode text,
  p_fulfillment_due_date date,
  p_fulfillment_due_time time without time zone,
  p_fulfillment_membership_id uuid,
  p_source_task_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_sale_for_member_v1(
    p_farm_id,p_buyer_relationship_id,p_customer_label,p_sales_channel,p_event_key,p_lines,
    p_tax_amount,p_tip_amount,p_fulfillment_mode,p_fulfillment_due_date,p_fulfillment_due_time,
    p_fulfillment_membership_id,p_source_task_id,p_note,p_idempotency_key
  );
$function$;

create or replace function public.record_flower_fulfillment_self_api_v1(
  p_farm_id uuid,
  p_task_id uuid,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language sql
volatile
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.record_flower_fulfillment_for_member_v1(
    p_farm_id,p_task_id,p_note,p_idempotency_key
  );
$function$;

-- Public command membrane: browser callers may execute only these fixed delegates.
revoke all on function public.record_flower_demand_order_self_api_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)
  from public,anon;
grant execute on function public.record_flower_demand_order_self_api_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)
  to authenticated,service_role;

revoke all on function public.commit_flower_demand_order_self_api_v1(uuid,uuid,text,text)
  from public,anon;
grant execute on function public.commit_flower_demand_order_self_api_v1(uuid,uuid,text,text)
  to authenticated,service_role;

revoke all on function public.record_flower_demand_line_price_self_api_v1(uuid,uuid,numeric,text,text,text)
  from public,anon;
grant execute on function public.record_flower_demand_line_price_self_api_v1(uuid,uuid,numeric,text,text,text)
  to authenticated,service_role;

revoke all on function public.record_flower_demand_allocation_self_api_v1(uuid,uuid,uuid,numeric,text,text)
  from public,anon;
grant execute on function public.record_flower_demand_allocation_self_api_v1(uuid,uuid,uuid,numeric,text,text)
  to authenticated,service_role;

revoke all on function public.release_flower_demand_allocation_self_api_v1(uuid,uuid,text,text,text)
  from public,anon;
grant execute on function public.release_flower_demand_allocation_self_api_v1(uuid,uuid,text,text,text)
  to authenticated,service_role;

revoke all on function public.record_flower_sale_from_demand_self_api_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)
  from public,anon;
grant execute on function public.record_flower_sale_from_demand_self_api_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)
  to authenticated,service_role;

revoke all on function public.record_flower_sale_self_api_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)
  from public,anon;
grant execute on function public.record_flower_sale_self_api_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)
  to authenticated,service_role;

revoke all on function public.record_flower_fulfillment_self_api_v1(uuid,uuid,text,text)
  from public,anon;
grant execute on function public.record_flower_fulfillment_self_api_v1(uuid,uuid,text,text)
  to authenticated,service_role;

-- Remove direct browser authority from the private member command layer.
revoke all on function atlas.record_flower_demand_order_for_member_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_demand_order_for_member_v1(uuid,uuid,text,text,text,date,text,time without time zone,jsonb,text,text)
  to service_role;

revoke all on function atlas.commit_flower_demand_order_for_member_v1(uuid,uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.commit_flower_demand_order_for_member_v1(uuid,uuid,text,text)
  to service_role;

revoke all on function atlas.record_flower_demand_line_price_for_member_v1(uuid,uuid,numeric,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_demand_line_price_for_member_v1(uuid,uuid,numeric,text,text,text)
  to service_role;

revoke all on function atlas.record_flower_demand_allocation_for_member_v1(uuid,uuid,uuid,numeric,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_demand_allocation_for_member_v1(uuid,uuid,uuid,numeric,text,text)
  to service_role;

revoke all on function atlas.release_flower_demand_allocation_for_member_v1(uuid,uuid,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.release_flower_demand_allocation_for_member_v1(uuid,uuid,text,text,text)
  to service_role;

revoke all on function atlas.record_flower_sale_from_demand_for_member_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_sale_from_demand_for_member_v1(uuid,uuid,numeric,numeric,uuid,uuid,text,text)
  to service_role;

revoke all on function atlas.record_flower_sale_for_member_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_sale_for_member_v1(uuid,uuid,text,text,text,jsonb,numeric,numeric,text,date,time without time zone,uuid,uuid,text,text)
  to service_role;

revoke all on function atlas.record_flower_fulfillment_for_member_v1(uuid,uuid,text,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_fulfillment_for_member_v1(uuid,uuid,text,text)
  to service_role;

commit;

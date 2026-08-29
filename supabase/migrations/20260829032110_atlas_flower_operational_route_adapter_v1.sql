alter table atlas.operational_route_stops add column if not exists execution_task_id uuid references atlas.tasks(id) on delete set null;
create index if not exists operational_route_stops_execution_task_idx on atlas.operational_route_stops(execution_task_id) where execution_task_id is not null;
comment on column atlas.operational_route_stops.execution_task_id is 'Optional Atlas execution task for this stop. Generic routes may exist without a task; domain adapters may bind a canonical worker task when one exists.';

drop function atlas.worker_operational_route_stops_v1(uuid,date);
create or replace function atlas.worker_operational_route_stops_v1(p_organization_id uuid,p_for_date date default ((now() at time zone 'America/Chicago')::date))
returns table(route_id uuid,route_label text,route_kind text,route_date date,route_state text,stop_id uuid,sequence_number integer,stop_kind text,stop_state text,destination_label text,address_text text,contact_name text,contact_detail text,service_window_start timestamptz,service_window_end timestamptz,worker_instruction text,execution_task_id uuid,obligations jsonb)
language plpgsql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_membership_id uuid;
begin
  v_membership_id:=atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'No active organization membership.' using errcode='42501'; end if;
  return query
  select r.id,r.route_label,r.route_kind,r.route_date,r.state,s.id,s.sequence_number,s.stop_kind,s.state,s.destination_label,s.address_text,s.contact_name,s.contact_detail,s.service_window_start,s.service_window_end,s.worker_instruction,s.execution_task_id,
    coalesce((select jsonb_agg(jsonb_build_object('bindingId',b.id,'obligationKind',b.obligation_kind,'domainKey',b.domain_key,'quantity',b.quantity,'unit',b.unit,'description',b.worker_description) order by b.created_at,b.id) from atlas.operational_route_bindings b where b.operational_route_stop_id=s.id),'[]'::jsonb)
  from atlas.operational_routes r join atlas.operational_route_stops s on s.operational_route_id=r.id
  where r.organization_id=p_organization_id and r.route_date=p_for_date and r.state not in ('completed','cancelled') and s.state not in ('completed','cancelled')
    and coalesce(s.assigned_organization_membership_id,r.assigned_organization_membership_id)=v_membership_id
  order by r.route_date,r.created_at,s.sequence_number,s.created_at;
end;
$function$;
revoke all on function atlas.worker_operational_route_stops_v1(uuid,date) from public,anon;
grant execute on function atlas.worker_operational_route_stops_v1(uuid,date) to authenticated,service_role;

create or replace function atlas.record_operational_route_v1(
  p_organization_id uuid,p_stable_key text,p_route_date date,p_route_label text,p_route_kind text,
  p_assigned_organization_membership_id uuid,p_external_custodian_label text,
  p_source_authority text,p_source_system_key text,p_source_record_key text,p_source_observed_at timestamptz,
  p_stops jsonb,p_metadata jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare
  v_actor uuid; v_route atlas.operational_routes%rowtype; v_stop jsonb; v_stop_row atlas.operational_route_stops%rowtype;
  v_binding jsonb; v_sequence integer; v_stop_assignee uuid; v_execution_task uuid; v_count integer:=0;
begin
  v_actor:=atlas.require_operational_route_owner_v1(p_organization_id);
  if nullif(btrim(p_stable_key),'') is null or nullif(btrim(p_route_label),'') is null then raise exception 'Route key and label are required.' using errcode='22023'; end if;
  if p_route_date is null then raise exception 'Route date is required.' using errcode='22023'; end if;
  if p_route_kind not in ('delivery','pickup','service','mixed','handoff') then raise exception 'Route kind is invalid.' using errcode='22023'; end if;
  if p_source_authority not in ('atlas','external') then raise exception 'Source authority is invalid.' using errcode='22023'; end if;
  if p_source_authority='external' and (nullif(btrim(p_source_system_key),'') is null or nullif(btrim(p_source_record_key),'') is null) then raise exception 'External route truth requires source system and source record identity.' using errcode='23514'; end if;
  if p_assigned_organization_membership_id is not null and nullif(btrim(p_external_custodian_label),'') is not null then raise exception 'Choose an internal assignee or an external custodian, not both.' using errcode='23514'; end if;
  if p_assigned_organization_membership_id is not null and not exists(select 1 from atlas.organization_memberships where id=p_assigned_organization_membership_id and organization_id=p_organization_id and active) then raise exception 'Route assignee is not active in this organization.' using errcode='23514'; end if;
  if p_stops is null or jsonb_typeof(p_stops)<>'array' or jsonb_array_length(p_stops)=0 or jsonb_array_length(p_stops)>100 then raise exception 'A route requires 1 to 100 stops.' using errcode='22023'; end if;
  if nullif(btrim(p_idempotency_key),'') is null then raise exception 'An idempotency key is required.' using errcode='22023'; end if;
  select * into v_route from atlas.operational_routes where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if v_route.id is not null then return jsonb_build_object('contractVersion','operational_route_v1','routeId',v_route.id,'idempotentReplay',true); end if;
  insert into atlas.operational_routes(organization_id,stable_key,route_date,route_label,route_kind,state,assigned_organization_membership_id,external_custodian_label,source_authority,source_system_key,source_record_key,source_observed_at,idempotency_key,metadata,created_by_user_id)
  values(p_organization_id,btrim(p_stable_key),p_route_date,btrim(p_route_label),p_route_kind,'planned',p_assigned_organization_membership_id,nullif(btrim(p_external_custodian_label),''),p_source_authority,nullif(btrim(p_source_system_key),''),nullif(btrim(p_source_record_key),''),p_source_observed_at,p_idempotency_key,coalesce(p_metadata,'{}'::jsonb),auth.uid()) returning * into v_route;
  for v_stop in select value from jsonb_array_elements(p_stops) loop
    v_sequence:=coalesce(nullif(v_stop->>'sequence','')::integer,v_count+1);
    v_stop_assignee:=nullif(v_stop->>'assignedOrganizationMembershipId','')::uuid;
    v_execution_task:=nullif(v_stop->>'executionTaskId','')::uuid;
    if v_stop_assignee is not null and not exists(select 1 from atlas.organization_memberships where id=v_stop_assignee and organization_id=p_organization_id and active) then raise exception 'Stop assignee is not active in this organization.' using errcode='23514'; end if;
    if v_execution_task is not null and not exists(select 1 from atlas.tasks t join atlas.farms f on f.id=t.farm_id where t.id=v_execution_task and f.organization_id=p_organization_id) then raise exception 'Execution task is outside this organization.' using errcode='23514'; end if;
    insert into atlas.operational_route_stops(organization_id,operational_route_id,stable_key,sequence_number,stop_kind,state,destination_label,address_text,contact_name,contact_detail,service_window_start,service_window_end,assigned_organization_membership_id,source_authority,source_system_key,source_record_key,source_observed_at,worker_instruction,execution_task_id,metadata)
    values(p_organization_id,v_route.id,coalesce(nullif(btrim(v_stop->>'stableKey'),''),'stop-'||v_sequence::text),v_sequence,coalesce(nullif(v_stop->>'stopKind',''),'handoff'),'planned',coalesce(nullif(btrim(v_stop->>'destinationLabel'),''),'Route stop '||v_sequence::text),nullif(btrim(v_stop->>'addressText'),''),nullif(btrim(v_stop->>'contactName'),''),nullif(btrim(v_stop->>'contactDetail'),''),nullif(v_stop->>'windowStart','')::timestamptz,nullif(v_stop->>'windowEnd','')::timestamptz,v_stop_assignee,coalesce(nullif(v_stop->>'sourceAuthority',''),p_source_authority),coalesce(nullif(v_stop->>'sourceSystemKey',''),nullif(btrim(p_source_system_key),'')),coalesce(nullif(v_stop->>'sourceRecordKey',''),nullif(btrim(p_source_record_key),'')),coalesce(nullif(v_stop->>'sourceObservedAt','')::timestamptz,p_source_observed_at),nullif(btrim(v_stop->>'workerInstruction'),''),v_execution_task,coalesce(v_stop->'metadata','{}'::jsonb)) returning * into v_stop_row;
    if v_stop ? 'bindings' and jsonb_typeof(v_stop->'bindings')='array' then
      for v_binding in select value from jsonb_array_elements(v_stop->'bindings') loop
        insert into atlas.operational_route_bindings(organization_id,operational_route_stop_id,stable_key,obligation_kind,domain_key,source_record_id,source_record_key,quantity,unit,worker_description,payload)
        values(p_organization_id,v_stop_row.id,coalesce(nullif(btrim(v_binding->>'stableKey'),''),'binding-'||substr(md5(v_binding::text),1,12)),coalesce(nullif(v_binding->>'obligationKind',''),'handoff'),coalesce(nullif(btrim(v_binding->>'domainKey'),''),'generic'),nullif(v_binding->>'sourceRecordId','')::uuid,nullif(btrim(v_binding->>'sourceRecordKey'),''),nullif(v_binding->>'quantity','')::numeric,nullif(btrim(v_binding->>'unit'),''),coalesce(nullif(btrim(v_binding->>'workerDescription'),''),'Complete the assigned route obligation.'),coalesce(v_binding->'payload','{}'::jsonb));
      end loop;
    end if;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('contractVersion','operational_route_v1','routeId',v_route.id,'stopCount',v_count,'idempotentReplay',false);
end;
$function$;

create or replace function atlas.sync_flower_sale_order_to_operational_route_v1(p_sale_order_id uuid)
returns uuid language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$
declare
  v_order atlas.flower_sale_orders%rowtype; v_farm atlas.farms%rowtype; v_org_membership uuid; v_task atlas.tasks%rowtype;
  v_route_id uuid; v_stop_id uuid; v_route_kind text; v_stop_kind text; v_address text; v_contact text; v_instruction text;
  v_line record; v_fulfilled boolean; v_cancelled boolean;
begin
  select * into v_order from atlas.flower_sale_orders where id=p_sale_order_id;
  if v_order.id is null or v_order.fulfillment_mode not in ('pickup_later','delivery') then return null; end if;
  select * into v_farm from atlas.farms where id=v_order.farm_id;
  if v_farm.id is null then return null; end if;
  if v_order.fulfillment_membership_id is not null then v_org_membership:=atlas.resolve_route_org_membership_from_farm_membership_v1(v_farm.organization_id,v_order.fulfillment_membership_id); end if;
  select * into v_task from atlas.tasks where metadata->>'flower_sale_order_id'=v_order.id::text and status not in ('cancelled','archived') order by created_at desc limit 1;
  if v_task.id is null and v_order.source_task_id is not null then select * into v_task from atlas.tasks where id=v_order.source_task_id; end if;
  v_route_kind:=case when v_order.fulfillment_mode='delivery' then 'delivery' else 'pickup' end;
  v_stop_kind:=case when v_order.fulfillment_mode='delivery' then 'product_delivery' else 'product_pickup' end;
  v_address:=coalesce(nullif(v_task.metadata->>'destination_address',''),nullif(v_task.metadata->>'address',''),nullif(v_order.metadata->>'destination_address',''));
  v_contact:=coalesce(nullif(v_task.metadata->>'contact_name',''),nullif(v_order.metadata->>'contact_name',''));
  v_instruction:=coalesce(nullif(v_task.metadata->>'execution_do',''),nullif(v_task.metadata->>'display_detail',''),case when v_order.fulfillment_mode='delivery' then 'Deliver the assigned order to '||coalesce(v_order.customer_label,'the customer')||'.' else 'Hand the assigned pickup to '||coalesce(v_order.customer_label,'the customer')||'.' end);
  v_fulfilled:=exists(select 1 from atlas.flower_fulfillment_events where sale_order_id=v_order.id);
  v_cancelled:=exists(select 1 from atlas.flower_sale_order_cancellation_events where sale_order_id=v_order.id);
  insert into atlas.operational_routes(organization_id,stable_key,route_date,route_label,route_kind,state,assigned_organization_membership_id,source_authority,source_system_key,source_record_key,idempotency_key,metadata,created_by_user_id)
  values(v_farm.organization_id,'flower-sale-order:'||v_order.id::text,coalesce(v_order.fulfillment_due_date,v_order.sale_date),case when v_order.fulfillment_mode='delivery' then 'Delivery · ' else 'Pickup · ' end||coalesce(v_order.customer_label,'Flower order'),v_route_kind,case when v_cancelled then 'cancelled' when v_fulfilled then 'completed' else 'planned' end,v_org_membership,'atlas','flower_sale_order',v_order.id::text,'flower-sale-order:'||v_order.id::text,jsonb_build_object('domainKey','flowers','farmId',v_order.farm_id,'saleOrderId',v_order.id,'fulfillmentMode',v_order.fulfillment_mode),v_order.created_by_user_id)
  on conflict(organization_id,stable_key) do update set route_date=excluded.route_date,route_label=excluded.route_label,route_kind=excluded.route_kind,state=excluded.state,assigned_organization_membership_id=excluded.assigned_organization_membership_id,metadata=atlas.operational_routes.metadata||excluded.metadata,updated_at=now() returning id into v_route_id;
  insert into atlas.operational_route_stops(organization_id,operational_route_id,stable_key,sequence_number,stop_kind,state,destination_label,address_text,contact_name,service_window_start,service_window_end,assigned_organization_membership_id,source_authority,source_system_key,source_record_key,worker_instruction,execution_task_id,metadata)
  values(v_farm.organization_id,v_route_id,'order-stop',1,v_stop_kind,case when v_cancelled then 'cancelled' when v_fulfilled then 'completed' else 'planned' end,coalesce(v_order.customer_label,'Flower customer'),v_address,v_contact,case when v_order.fulfillment_due_date is not null and v_order.fulfillment_due_time is not null then (v_order.fulfillment_due_date::text||' '||v_order.fulfillment_due_time::text||' America/Chicago')::timestamptz when v_order.fulfillment_due_date is not null then (v_order.fulfillment_due_date::text||' 00:00 America/Chicago')::timestamptz else null end,case when v_order.fulfillment_due_date is not null and v_order.fulfillment_due_time is not null then (v_order.fulfillment_due_date::text||' '||v_order.fulfillment_due_time::text||' America/Chicago')::timestamptz when v_order.fulfillment_due_date is not null then (v_order.fulfillment_due_date::text||' 23:59 America/Chicago')::timestamptz else null end,v_org_membership,'atlas','flower_sale_order',v_order.id::text,v_instruction,v_task.id,jsonb_build_object('farmId',v_order.farm_id,'saleOrderId',v_order.id,'sourceTaskId',v_order.source_task_id))
  on conflict(operational_route_id,stable_key) do update set state=excluded.state,destination_label=excluded.destination_label,address_text=excluded.address_text,contact_name=excluded.contact_name,service_window_start=excluded.service_window_start,service_window_end=excluded.service_window_end,assigned_organization_membership_id=excluded.assigned_organization_membership_id,worker_instruction=excluded.worker_instruction,execution_task_id=excluded.execution_task_id,metadata=atlas.operational_route_stops.metadata||excluded.metadata,updated_at=now() returning id into v_stop_id;
  delete from atlas.operational_route_bindings where operational_route_stop_id=v_stop_id and domain_key='flowers.sale_order_line';
  for v_line in select l.id,l.quantity,l.unit,coalesce(ri.product_label,l.inventory_kind) product_label from atlas.flower_sale_order_lines l left join atlas.flower_ready_inventory_lots ri on ri.id=l.ready_lot_id where l.sale_order_id=v_order.id order by l.created_at,l.id loop
    insert into atlas.operational_route_bindings(organization_id,operational_route_stop_id,stable_key,obligation_kind,domain_key,source_record_id,source_record_key,quantity,unit,worker_description,payload)
    values(v_farm.organization_id,v_stop_id,'sale-line:'||v_line.id::text,'product','flowers.sale_order_line',v_line.id,v_line.id::text,v_line.quantity,v_line.unit,trim(to_char(v_line.quantity,'FM999999990.###'))||' × '||v_line.product_label,jsonb_build_object('saleOrderLineId',v_line.id));
  end loop;
  return v_route_id;
end;
$function$;

create or replace function atlas.sync_flower_prospect_route_to_operational_route_v1(p_prospect_route_id uuid)
returns uuid language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$
declare
  v_source atlas.flower_prospect_routes%rowtype; v_farm atlas.farms%rowtype; v_org_membership uuid; v_route_id uuid; v_stop_id uuid; v_line record; v_sequence integer:=0; v_destination text;
begin
  select * into v_source from atlas.flower_prospect_routes where id=p_prospect_route_id;
  if v_source.id is null then return null; end if;
  select * into v_farm from atlas.farms where id=v_source.farm_id;
  if v_farm.id is null then return null; end if;
  if v_source.assigned_membership_id is not null then v_org_membership:=atlas.resolve_route_org_membership_from_farm_membership_v1(v_farm.organization_id,v_source.assigned_membership_id); end if;
  insert into atlas.operational_routes(organization_id,stable_key,route_date,route_label,route_kind,state,assigned_organization_membership_id,external_custodian_label,source_authority,source_system_key,source_record_key,idempotency_key,metadata,created_by_user_id)
  values(v_farm.organization_id,'flower-prospect-route:'||v_source.id::text,v_source.route_date,v_source.route_label,'delivery','active',v_org_membership,v_source.custodian_label,'atlas','flower_prospect_route',v_source.id::text,'flower-prospect-route:'||v_source.id::text,jsonb_build_object('domainKey','flowers','farmId',v_source.farm_id,'prospectRouteId',v_source.id,'truthBoundary','custody_before_sale'),v_source.created_by_user_id)
  on conflict(organization_id,stable_key) do update set route_date=excluded.route_date,route_label=excluded.route_label,state=excluded.state,assigned_organization_membership_id=excluded.assigned_organization_membership_id,external_custodian_label=excluded.external_custodian_label,metadata=atlas.operational_routes.metadata||excluded.metadata,updated_at=now() returning id into v_route_id;
  for v_line in select l.id,l.quantity,l.destination_label,coalesce(ri.product_label,ri.inventory_kind) product_label,ri.unit from atlas.flower_prospect_route_lines l join atlas.flower_ready_inventory_lots ri on ri.id=l.ready_lot_id where l.prospect_route_id=v_source.id order by l.created_at,l.id loop
    v_sequence:=v_sequence+1; v_destination:=coalesce(nullif(btrim(v_line.destination_label),''),v_source.route_label);
    insert into atlas.operational_route_stops(organization_id,operational_route_id,stable_key,sequence_number,stop_kind,state,destination_label,assigned_organization_membership_id,source_authority,source_system_key,source_record_key,worker_instruction,metadata)
    values(v_farm.organization_id,v_route_id,'prospect-line:'||v_line.id::text,v_sequence,'product_delivery','en_route',v_destination,v_org_membership,'atlas','flower_prospect_route_line',v_line.id::text,'Carry the assigned flowers on this route. Record any sale only through the flower sales flow.',jsonb_build_object('farmId',v_source.farm_id,'prospectRouteId',v_source.id,'prospectRouteLineId',v_line.id,'saleTruth','not_implied'))
    on conflict(operational_route_id,stable_key) do update set sequence_number=excluded.sequence_number,state=case when atlas.operational_route_stops.state in ('completed','failed','cancelled') then atlas.operational_route_stops.state else excluded.state end,destination_label=excluded.destination_label,assigned_organization_membership_id=excluded.assigned_organization_membership_id,worker_instruction=excluded.worker_instruction,metadata=atlas.operational_route_stops.metadata||excluded.metadata,updated_at=now() returning id into v_stop_id;
    insert into atlas.operational_route_bindings(organization_id,operational_route_stop_id,stable_key,obligation_kind,domain_key,source_record_id,source_record_key,quantity,unit,worker_description,payload)
    values(v_farm.organization_id,v_stop_id,'prospect-line:'||v_line.id::text,'product','flowers.prospect_route_line',v_line.id,v_line.id::text,v_line.quantity,v_line.unit,trim(to_char(v_line.quantity,'FM999999990.###'))||' × '||v_line.product_label,jsonb_build_object('prospectRouteLineId',v_line.id,'saleTruth','not_implied'))
    on conflict(operational_route_stop_id,stable_key) do update set quantity=excluded.quantity,unit=excluded.unit,worker_description=excluded.worker_description,payload=excluded.payload;
  end loop;
  update atlas.operational_route_stops s set state='cancelled',updated_at=now() where s.operational_route_id=v_route_id and s.source_system_key='flower_prospect_route_line' and not exists(select 1 from atlas.flower_prospect_route_lines l where l.id::text=s.source_record_key and l.prospect_route_id=v_source.id) and s.state not in ('completed','cancelled');
  return v_route_id;
end;
$function$;

create or replace function atlas.trg_sync_flower_sale_order_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_sale_order_to_operational_route_v1(new.id); return new; end; $function$;
create or replace function atlas.trg_sync_flower_sale_order_line_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_sale_order_to_operational_route_v1(case when tg_op='DELETE' then old.sale_order_id else new.sale_order_id end); return case when tg_op='DELETE' then old else new end; end; $function$;
create or replace function atlas.trg_sync_flower_fulfillment_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_sale_order_to_operational_route_v1(new.sale_order_id); return new; end; $function$;
create or replace function atlas.trg_sync_flower_cancellation_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_sale_order_to_operational_route_v1(new.sale_order_id); return new; end; $function$;
create or replace function atlas.trg_sync_flower_prospect_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_prospect_route_to_operational_route_v1(new.id); return new; end; $function$;
create or replace function atlas.trg_sync_flower_prospect_line_operational_route_v1() returns trigger language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$ begin perform atlas.sync_flower_prospect_route_to_operational_route_v1(case when tg_op='DELETE' then old.prospect_route_id else new.prospect_route_id end); return case when tg_op='DELETE' then old else new end; end; $function$;

drop trigger if exists trg_sync_flower_sale_order_operational_route_v1 on atlas.flower_sale_orders;
create trigger trg_sync_flower_sale_order_operational_route_v1 after insert or update of fulfillment_mode,fulfillment_due_date,fulfillment_due_time,fulfillment_membership_id,customer_label,source_task_id on atlas.flower_sale_orders for each row execute function atlas.trg_sync_flower_sale_order_operational_route_v1();
drop trigger if exists trg_sync_flower_sale_order_line_operational_route_v1 on atlas.flower_sale_order_lines;
create trigger trg_sync_flower_sale_order_line_operational_route_v1 after insert or update or delete on atlas.flower_sale_order_lines for each row execute function atlas.trg_sync_flower_sale_order_line_operational_route_v1();
drop trigger if exists trg_sync_flower_fulfillment_operational_route_v1 on atlas.flower_fulfillment_events;
create trigger trg_sync_flower_fulfillment_operational_route_v1 after insert on atlas.flower_fulfillment_events for each row execute function atlas.trg_sync_flower_fulfillment_operational_route_v1();
drop trigger if exists trg_sync_flower_cancellation_operational_route_v1 on atlas.flower_sale_order_cancellation_events;
create trigger trg_sync_flower_cancellation_operational_route_v1 after insert on atlas.flower_sale_order_cancellation_events for each row execute function atlas.trg_sync_flower_cancellation_operational_route_v1();
drop trigger if exists trg_sync_flower_prospect_operational_route_v1 on atlas.flower_prospect_routes;
create trigger trg_sync_flower_prospect_operational_route_v1 after insert or update of route_date,route_label,assigned_membership_id,custodian_label on atlas.flower_prospect_routes for each row execute function atlas.trg_sync_flower_prospect_operational_route_v1();
drop trigger if exists trg_sync_flower_prospect_line_operational_route_v1 on atlas.flower_prospect_route_lines;
create trigger trg_sync_flower_prospect_line_operational_route_v1 after insert or update or delete on atlas.flower_prospect_route_lines for each row execute function atlas.trg_sync_flower_prospect_line_operational_route_v1();

do $backfill$ declare v_id uuid; begin
  for v_id in select id from atlas.flower_sale_orders where fulfillment_mode in ('pickup_later','delivery') loop perform atlas.sync_flower_sale_order_to_operational_route_v1(v_id); end loop;
  for v_id in select id from atlas.flower_prospect_routes loop perform atlas.sync_flower_prospect_route_to_operational_route_v1(v_id); end loop;
end; $backfill$;

revoke all on function atlas.sync_flower_sale_order_to_operational_route_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.sync_flower_prospect_route_to_operational_route_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.sync_flower_sale_order_to_operational_route_v1(uuid) to service_role;
grant execute on function atlas.sync_flower_prospect_route_to_operational_route_v1(uuid) to service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected)
values('atlas.worker_operational_route_stops_v1(uuid, date)','app_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('source','atlas_flower_operational_route_adapter_v1','scope','assigned_worker_only','workerBoundary','Returns only worker-safe assigned stop context, optional execution task identity, and never returns binding payload/commercial totals.'),now(),false)
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,reviewed_at=excluded.reviewed_at,anonymous_execute_expected=excluded.anonymous_execute_expected;

comment on function atlas.sync_flower_sale_order_to_operational_route_v1(uuid) is 'Flower-domain adapter: projects pickup/delivery execution into generic operational route truth while keeping sale, inventory, price, and fulfillment authority in flower tables.';
comment on function atlas.sync_flower_prospect_route_to_operational_route_v1(uuid) is 'Flower-domain adapter: projects prospect-route custody into generic worker routing without turning custody into a sale.';
BEGIN;

-- Atlas Principal decision source-withdrawal v1
--
-- Principal admission is explicit and Clock arbitration is domain-agnostic.
-- Therefore a domain adapter must withdraw an admitted decision when canonical
-- source truth makes that exact decision non-executable before it is acted on.
-- Withdrawal never rewrites Demand, never fabricates a different decision, and
-- never automatically re-admits the source if it later becomes executable.

create or replace function atlas.withdraw_flower_demand_sale_principal_escalation_if_unexecutable_v1(
  p_demand_order_id uuid,
  p_source_event_kind text,
  p_source_event_id text
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_order atlas.flower_demand_orders%rowtype;
  v_line_count integer:=0;
  v_not_ready integer:=0;
  v_rows integer:=0;
begin
  if p_demand_order_id is null then
    return 0;
  end if;

  select * into v_order
  from atlas.flower_demand_orders
  where id=p_demand_order_id;

  if v_order.id is null then
    return 0;
  end if;

  -- Once canonical Sale exists, the successful-transition resolver owns the
  -- lifecycle. A later source event must not reinterpret that completed choice.
  if exists(
    select 1
    from atlas.flower_demand_sale_order_links l
    join atlas.flower_sale_orders so on so.id=l.sale_order_id
    where l.demand_order_id=p_demand_order_id
      and not exists(
        select 1
        from atlas.flower_sale_order_cancellation_events sc
        where sc.sale_order_id=so.id
      )
  ) then
    return 0;
  end if;

  select
    count(*),
    count(*) filter(
      where c.coverage_state<>'covered'
         or c.sold_quantity<>0
         or c.target_unit_price is null
    )
  into v_line_count,v_not_ready
  from atlas.flower_demand_coverage_v1 c
  where c.demand_order_id=p_demand_order_id;

  if v_order.demand_strength='committed'
     and not exists(
       select 1
       from atlas.flower_demand_order_cancellation_events dc
       where dc.demand_order_id=p_demand_order_id
     )
     and v_line_count>0
     and v_not_ready=0 then
    return 0;
  end if;

  update atlas.operational_escalations e
  set status='resolved',
      resolved_at=coalesce(e.resolved_at,now()),
      updated_at=now(),
      metadata=coalesce(e.metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
        'resolvedBy','flower_demand_sale_source_withdrawal_v1',
        'resolvedReason','canonical_demand_to_sale_transition_no_longer_executable',
        'resolutionDisposition','withdrawn_by_source',
        'sourceEventKind',nullif(btrim(p_source_event_kind),''),
        'sourceEventId',nullif(btrim(p_source_event_id),'')
      ))
  where e.source_system='flower_commerce'
    and e.source_type='flower_demand_order'
    and e.source_id=p_demand_order_id::text
    and e.escalation_kind='sale_commitment_decision'
    and e.status in ('open','acknowledged');

  get diagnostics v_rows=row_count;
  return v_rows;
end;
$function$;

revoke all on function atlas.withdraw_flower_demand_sale_principal_escalation_if_unexecutable_v1(uuid,text,text)
  from public,anon,authenticated;

comment on function atlas.withdraw_flower_demand_sale_principal_escalation_if_unexecutable_v1(uuid,text,text) is
  'Source-derived withdrawal for the Flower Demand -> Sale Principal decision. Resolves only an already-admitted sale_commitment_decision when canonical Demand truth makes that exact transition non-executable. It does not infer a replacement decision and does not re-admit the source later.';

create or replace function atlas.withdraw_flower_demand_sale_principal_escalation_on_cancel_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  perform atlas.withdraw_flower_demand_sale_principal_escalation_if_unexecutable_v1(
    new.demand_order_id,
    'flower_demand_order_cancellation_event',
    new.id::text
  );
  return new;
end;
$function$;

revoke all on function atlas.withdraw_flower_demand_sale_principal_escalation_on_cancel_v1()
  from public,anon,authenticated;

create or replace function atlas.withdraw_flower_demand_sale_principal_escalation_on_allocation_release_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_demand_order_id uuid;
begin
  select l.demand_order_id
  into v_demand_order_id
  from atlas.flower_demand_allocations a
  join atlas.flower_demand_order_lines l on l.id=a.demand_line_id
  where a.id=new.allocation_id;

  perform atlas.withdraw_flower_demand_sale_principal_escalation_if_unexecutable_v1(
    v_demand_order_id,
    'flower_demand_allocation_release_event',
    new.id::text
  );
  return new;
end;
$function$;

revoke all on function atlas.withdraw_flower_demand_sale_principal_escalation_on_allocation_release_v1()
  from public,anon,authenticated;

drop trigger if exists flower_demand_cancel_withdraws_sale_principal_escalation_v1
  on atlas.flower_demand_order_cancellation_events;
create trigger flower_demand_cancel_withdraws_sale_principal_escalation_v1
after insert on atlas.flower_demand_order_cancellation_events
for each row execute function atlas.withdraw_flower_demand_sale_principal_escalation_on_cancel_v1();

drop trigger if exists flower_demand_allocation_release_withdraws_sale_principal_escalation_v1
  on atlas.flower_demand_allocation_release_events;
create trigger flower_demand_allocation_release_withdraws_sale_principal_escalation_v1
after insert on atlas.flower_demand_allocation_release_events
for each row execute function atlas.withdraw_flower_demand_sale_principal_escalation_on_allocation_release_v1();

-- Contract proof: the source-withdrawal hooks must remain downstream of source
-- truth and must not alter Clock arbitration or create Principal admissions.
do $proof$
declare
  v_cancel_trigger boolean;
  v_release_trigger boolean;
begin
  select exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='flower_demand_order_cancellation_events'
      and t.tgname='flower_demand_cancel_withdraws_sale_principal_escalation_v1'
      and not t.tgisinternal
  ) into v_cancel_trigger;

  select exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='flower_demand_allocation_release_events'
      and t.tgname='flower_demand_allocation_release_withdraws_sale_principal_escalation_v1'
      and not t.tgisinternal
  ) into v_release_trigger;

  if not v_cancel_trigger or not v_release_trigger then
    raise exception 'Principal decision source-withdrawal proof failed: canonical invalidation hook missing.';
  end if;
end;
$proof$;

COMMIT;

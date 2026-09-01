BEGIN;

-- Atlas Principal decision admission firewall v1
--
-- Generic operational escalation is an explicit admission mechanism. Clock may
-- trust that inventory only if a domain-specific decision kind guarantees that
-- the source identity, Principal custody, and executable decision are truthful
-- at admission time. This firewall validates only the Flower Demand -> Sale
-- adapter contract; it does not infer whether the Principal should be involved.

create or replace function atlas.validate_flower_demand_sale_principal_escalation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_demand_order_id uuid;
  v_order atlas.flower_demand_orders%rowtype;
  v_line_count integer:=0;
  v_not_ready integer:=0;
begin
  if new.source_system<>'flower_commerce'
     or new.source_type<>'flower_demand_order'
     or new.escalation_kind<>'sale_commitment_decision'
     or new.status not in ('open','acknowledged') then
    return new;
  end if;

  begin
    v_demand_order_id:=new.source_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Flower Sale-commitment escalation requires a UUID flower_demand_order source_id.' using errcode='23514';
  end;

  select * into v_order
  from atlas.flower_demand_orders
  where id=v_demand_order_id;

  if v_order.id is null then
    raise exception 'Flower Sale-commitment escalation source Demand order does not exist.' using errcode='23514';
  end if;

  if new.portfolio_unit_id is null
     or not exists(
       select 1
       from atlas.portfolio_units u
       where u.id=new.portfolio_unit_id
         and u.owner_id=new.principal_id
         and u.linked_farm_id=v_order.farm_id
         and u.archived_at is null
     ) then
    raise exception 'Flower Sale-commitment escalation Principal custody does not match the Demand source.' using errcode='23514';
  end if;

  if exists(
    select 1
    from atlas.flower_demand_sale_order_links l
    join atlas.flower_sale_orders so on so.id=l.sale_order_id
    where l.demand_order_id=v_demand_order_id
      and not exists(
        select 1
        from atlas.flower_sale_order_cancellation_events sc
        where sc.sale_order_id=so.id
      )
  ) then
    raise exception 'Flower Sale-commitment escalation cannot be admitted after canonical Sale already exists.' using errcode='23514';
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
  where c.demand_order_id=v_demand_order_id;

  if v_order.demand_strength<>'committed'
     or exists(
       select 1
       from atlas.flower_demand_order_cancellation_events dc
       where dc.demand_order_id=v_demand_order_id
     )
     or v_line_count=0
     or v_not_ready>0 then
    raise exception 'Flower Sale-commitment escalation cannot be admitted while the canonical Demand -> Sale transition is not executable.' using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.validate_flower_demand_sale_principal_escalation_v1()
  from public,anon,authenticated;

comment on function atlas.validate_flower_demand_sale_principal_escalation_v1() is
  'Domain admission firewall for sale_commitment_decision operational escalations. It validates canonical source identity, Principal portfolio custody, and current Demand -> Sale executability without inferring Principal responsibility or escalation thresholds.';

drop trigger if exists flower_demand_sale_principal_escalation_admission_firewall_v1
  on atlas.operational_escalations;
create trigger flower_demand_sale_principal_escalation_admission_firewall_v1
before insert or update of principal_id,source_system,source_type,source_id,portfolio_unit_id,escalation_kind,status
on atlas.operational_escalations
for each row execute function atlas.validate_flower_demand_sale_principal_escalation_v1();

-- Contract proof: the firewall belongs at admission, upstream of raw candidate
-- inventory and Clock arbitration. It may reject a false domain translation but
-- may not create an escalation, Sale, Task, Clock placement, or commitment.
do $proof$
declare
  v_trigger boolean;
begin
  select exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='operational_escalations'
      and t.tgname='flower_demand_sale_principal_escalation_admission_firewall_v1'
      and not t.tgisinternal
  ) into v_trigger;

  if not v_trigger then
    raise exception 'Principal decision admission-firewall proof failed: trigger missing.';
  end if;
end;
$proof$;

COMMIT;

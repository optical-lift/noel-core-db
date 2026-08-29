create table if not exists atlas.buyer_identity_aliases (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  buyer_relationship_id uuid not null references atlas.buyer_relationship_reconstruction(id) on delete cascade,
  alias text not null,
  alias_normalized text generated always as (regexp_replace(lower(trim(alias)), '[^a-z0-9]+', '', 'g')) stored,
  alias_type text not null default 'business_name' check (alias_type in ('business_name','person_name','nickname','legacy_name','email','other')),
  contact_name text,
  contact_role text,
  is_current boolean not null default true,
  priority smallint not null default 3 check (priority between 1 and 5),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, buyer_relationship_id, alias_normalized)
);

create index if not exists buyer_identity_aliases_lookup_idx
  on atlas.buyer_identity_aliases (farm_id, alias_normalized, priority);

create trigger set_buyer_identity_aliases_updated_at
before update on atlas.buyer_identity_aliases
for each row execute function atlas.set_updated_at();

alter table atlas.buyer_identity_aliases enable row level security;

drop policy if exists buyer_identity_aliases_member_read on atlas.buyer_identity_aliases;
create policy buyer_identity_aliases_member_read
on atlas.buyer_identity_aliases for select
using (atlas.is_farm_member(farm_id));

create table if not exists atlas.buyer_reported_purchase_history (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  buyer_relationship_id uuid not null references atlas.buyer_relationship_reconstruction(id) on delete cascade,
  evidence_key text not null,
  summary text not null,
  amount_min numeric check (amount_min is null or amount_min >= 0),
  amount_max numeric check (amount_max is null or amount_max >= 0),
  source_person text,
  source_date date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, buyer_relationship_id, evidence_key),
  check (amount_min is null or amount_max is null or amount_max >= amount_min)
);

create trigger set_buyer_reported_purchase_history_updated_at
before update on atlas.buyer_reported_purchase_history
for each row execute function atlas.set_updated_at();

alter table atlas.buyer_reported_purchase_history enable row level security;

drop policy if exists buyer_reported_purchase_history_member_read on atlas.buyer_reported_purchase_history;
create policy buyer_reported_purchase_history_member_read
on atlas.buyer_reported_purchase_history for select
using (atlas.is_farm_member(farm_id));

-- Every existing buyer can always be resolved by business name.
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,priority,metadata)
select farm_id,id,business_name,'business_name',1,jsonb_build_object('source','buyer_relationship_reconstruction')
from atlas.buyer_relationship_reconstruction
where business_name is not null and trim(business_name) <> ''
on conflict do nothing;

-- Current known people/nicknames used conversationally.
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Sue','nickname','Sue Minor','owner',1,jsonb_build_object('source','owner_operator_context','maps_to','Ruth''s Flowers and Gifts')
from atlas.buyer_relationship_reconstruction where stable_key='ruths_flowers_and_gifts'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Sue Minor','person_name','Sue Minor','owner',1,jsonb_build_object('source','owner_operator_context')
from atlas.buyer_relationship_reconstruction where stable_key='ruths_flowers_and_gifts'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Josh','person_name','Josh','buyer',1,jsonb_build_object('source','current_contact')
from atlas.buyer_relationship_reconstruction where stable_key='lindas_flowers'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Kim','person_name','Kim','buyer',1,jsonb_build_object('source','current_contact')
from atlas.buyer_relationship_reconstruction where stable_key='schaffitzels'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Recinna','person_name','Recinna','contact',1,jsonb_build_object('source','current_contact','pronunciation','Re-seen-a')
from atlas.buyer_relationship_reconstruction where stable_key='flowerama'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Theresa','nickname','Theresa Suda','owner',1,jsonb_build_object('source','current_contact')
from atlas.buyer_relationship_reconstruction where stable_key='rose_among_thorns'
on conflict do nothing;
insert into atlas.buyer_identity_aliases (farm_id,buyer_relationship_id,alias,alias_type,contact_name,contact_role,priority,metadata)
select farm_id,id,'Theresa Suda','person_name','Theresa Suda','owner',1,jsonb_build_object('source','current_contact')
from atlas.buyer_relationship_reconstruction where stable_key='rose_among_thorns'
on conflict do nothing;

update atlas.buyer_relationship_reconstruction
set primary_contact_name='Sue Minor', updated_at=now(), metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object('current_contact','Sue Minor','contact_alias','Sue')
where stable_key='ruths_flowers_and_gifts' and (primary_contact_name is null or primary_contact_name='');

-- Preserve historical purchase reports as evidence, not as fabricated Atlas orders.
insert into atlas.buyer_reported_purchase_history (farm_id,buyer_relationship_id,evidence_key,summary,amount_min,amount_max,source_person,source_date,metadata)
select farm_id,id,'reconstruction_2026_08_10',purchase_history_summary,10,30,source_person,source_date,jsonb_build_object('truth_class','reported_historical_purchase','exact_order_unknown',true)
from atlas.buyer_relationship_reconstruction where stable_key='ruths_flowers_and_gifts'
on conflict do nothing;
insert into atlas.buyer_reported_purchase_history (farm_id,buyer_relationship_id,evidence_key,summary,source_person,source_date,metadata)
select farm_id,id,'reconstruction_current',purchase_history_summary,source_person,source_date,jsonb_build_object('truth_class','reported_historical_purchase','exact_order_unknown',true,'historical_rank','highest-volume florist relationship')
from atlas.buyer_relationship_reconstruction where stable_key='lindas_flowers'
on conflict do nothing;
insert into atlas.buyer_reported_purchase_history (farm_id,buyer_relationship_id,evidence_key,summary,source_person,source_date,metadata)
select farm_id,id,'reconstruction_2026_08_10',purchase_history_summary,source_person,source_date,jsonb_build_object('truth_class','reported_historical_purchase','exact_order_unknown',true,'competitor','MFE')
from atlas.buyer_relationship_reconstruction where stable_key='cassidy_station'
on conflict do nothing;
insert into atlas.buyer_reported_purchase_history (farm_id,buyer_relationship_id,evidence_key,summary,source_person,source_date,metadata)
select farm_id,id,'historical_before_2026_08_28','Historically usually bought at least a few things when Elm reached the correct flower buyer; exact historical Atlas orders are not in custody.',source_person,source_date,jsonb_build_object('truth_class','reported_historical_purchase','exact_order_unknown',true)
from atlas.buyer_relationship_reconstruction where stable_key='schaffitzels'
on conflict do nothing;

create or replace view intelligence.v_noel_buyer_order_history as
select
  s.farm_id,
  s.buyer_relationship_id,
  s.id as sale_order_id,
  s.sale_date,
  s.sales_channel,
  s.fulfillment_mode,
  s.total_amount,
  s.currency,
  s.note,
  s.created_at,
  coalesce(jsonb_agg(
    jsonb_build_object(
      'sale_line_id', l.id,
      'ready_lot_id', l.ready_lot_id,
      'product_label', coalesce(r.product_label,l.inventory_kind),
      'inventory_kind', l.inventory_kind,
      'quantity', l.quantity,
      'unit', l.unit,
      'unit_price', l.unit_price,
      'line_total', l.line_total
    ) order by l.created_at, l.id
  ) filter (where l.id is not null), '[]'::jsonb) as line_items
from atlas.flower_sale_orders s
left join atlas.flower_sale_order_lines l on l.sale_order_id=s.id
left join atlas.flower_ready_inventory_lots r on r.id=l.ready_lot_id
where not exists (select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=s.id)
group by s.farm_id,s.buyer_relationship_id,s.id,s.sale_date,s.sales_channel,s.fulfillment_mode,s.total_amount,s.currency,s.note,s.created_at;

create or replace view intelligence.v_noel_buyer_memory_v1 as
with aliases as (
  select farm_id,buyer_relationship_id,
    jsonb_agg(jsonb_build_object('alias',alias,'alias_type',alias_type,'contact_name',contact_name,'contact_role',contact_role,'is_current',is_current,'priority',priority) order by priority,alias) as aliases
  from atlas.buyer_identity_aliases
  group by farm_id,buyer_relationship_id
), latest_contact as (
  select distinct on (farm_id,buyer_relationship_id)
    farm_id,buyer_relationship_id,id as last_contact_event_id,occurred_at as last_contact_at,contact_method as last_contact_method,
    outcome as last_contact_outcome,contact_name as last_contact_name,notes as last_contact_notes,follow_up as last_contact_follow_up,metadata as last_contact_metadata
  from atlas.buyer_contact_events
  order by farm_id,buyer_relationship_id,occurred_at desc,created_at desc,id desc
), orders as (
  select farm_id,buyer_relationship_id,
    count(*)::int as atlas_purchase_count,
    coalesce(sum(total_amount),0)::numeric as atlas_lifetime_spend,
    max(sale_date) as last_atlas_purchase_date,
    (array_agg(sale_order_id order by sale_date desc,created_at desc))[1] as last_atlas_order_id,
    (array_agg(total_amount order by sale_date desc,created_at desc))[1] as last_atlas_purchase_amount,
    jsonb_agg(jsonb_build_object('sale_order_id',sale_order_id,'sale_date',sale_date,'total_amount',total_amount,'currency',currency,'sales_channel',sales_channel,'fulfillment_mode',fulfillment_mode,'line_items',line_items,'note',note) order by sale_date desc,created_at desc) as atlas_orders
  from intelligence.v_noel_buyer_order_history
  group by farm_id,buyer_relationship_id
), reported as (
  select farm_id,buyer_relationship_id,count(*)::int as reported_purchase_evidence_count,
    jsonb_agg(jsonb_build_object('evidence_id',id,'evidence_key',evidence_key,'summary',summary,'amount_min',amount_min,'amount_max',amount_max,'source_person',source_person,'source_date',source_date,'metadata',metadata) order by source_date desc nulls last,created_at desc) as reported_purchase_history
  from atlas.buyer_reported_purchase_history
  group by farm_id,buyer_relationship_id
)
select
  p.*,
  coalesce(a.aliases,'[]'::jsonb) as aliases,
  lc.last_contact_event_id,lc.last_contact_at,lc.last_contact_method,lc.last_contact_outcome,lc.last_contact_name,lc.last_contact_notes,lc.last_contact_follow_up,lc.last_contact_metadata,
  coalesce(o.atlas_purchase_count,0) as exact_atlas_purchase_count,
  coalesce(o.atlas_lifetime_spend,0) as exact_atlas_lifetime_spend,
  o.last_atlas_purchase_date,o.last_atlas_order_id,o.last_atlas_purchase_amount,
  coalesce(o.atlas_orders,'[]'::jsonb) as exact_atlas_orders,
  coalesce(r.reported_purchase_evidence_count,0) as reported_purchase_evidence_count,
  coalesce(r.reported_purchase_history,'[]'::jsonb) as reported_purchase_history,
  case
    when coalesce(o.atlas_purchase_count,0)>0 then 'exact_atlas_order_exists'
    when coalesce(r.reported_purchase_evidence_count,0)>0 then 'reported_purchase_history_only'
    else 'no_purchase_evidence'
  end as purchase_truth_state,
  (
    p.route_state='active' and coalesce(o.atlas_purchase_count,0)=0 and coalesce(r.reported_purchase_evidence_count,0)=0
    and (
      p.buying_stage in ('prospect','receptive','trial_buyer','recurring_candidate')
      or p.relationship_status ilike '%interested%'
      or p.relationship_status ilike '%receptive%'
      or p.relationship_status ilike '%sample%'
      or p.relationship_status ilike '%awaiting_reply%'
    )
  ) as warm_never_purchased_known,
  (
    p.route_state='active' and coalesce(o.atlas_purchase_count,0)=0
    and (
      p.buying_stage in ('prospect','receptive','trial_buyer','recurring_candidate','active_buyer')
      or p.relationship_status ilike '%interested%'
      or p.relationship_status ilike '%receptive%'
      or p.relationship_status ilike '%buyer%'
      or p.relationship_status ilike '%awaiting_reply%'
    )
  ) as warm_without_atlas_order
from atlas.v_flower_buyer_position_v1 p
left join aliases a on a.farm_id=p.farm_id and a.buyer_relationship_id=p.buyer_relationship_id
left join latest_contact lc on lc.farm_id=p.farm_id and lc.buyer_relationship_id=p.buyer_relationship_id
left join orders o on o.farm_id=p.farm_id and o.buyer_relationship_id=p.buyer_relationship_id
left join reported r on r.farm_id=p.farm_id and r.buyer_relationship_id=p.buyer_relationship_id;

create or replace function intelligence.resolve_flower_buyer_v1(p_farm_id uuid,p_reference text)
returns table(
  buyer_relationship_id uuid,
  stable_key text,
  business_name text,
  primary_contact_name text,
  matched_alias text,
  alias_type text,
  match_rank integer
)
language sql stable security invoker set search_path=atlas,intelligence,public as $$
with needle as (
  select regexp_replace(lower(trim(p_reference)), '[^a-z0-9]+', '', 'g') as n
), candidates as (
  select a.buyer_relationship_id,b.stable_key,b.business_name,b.primary_contact_name,a.alias as matched_alias,a.alias_type,
    case when a.alias_normalized=(select n from needle) then 1
         when a.alias_normalized like (select n from needle)||'%' then 2
         when a.alias_normalized like '%'||(select n from needle)||'%' then 3
         else 9 end + a.priority as rank_value
  from atlas.buyer_identity_aliases a
  join atlas.buyer_relationship_reconstruction b on b.id=a.buyer_relationship_id and b.farm_id=a.farm_id
  where a.farm_id=p_farm_id and a.is_current and (a.alias_normalized=(select n from needle) or a.alias_normalized like (select n from needle)||'%' or a.alias_normalized like '%'||(select n from needle)||'%')
)
select buyer_relationship_id,stable_key,business_name,primary_contact_name,matched_alias,alias_type,rank_value::int
from candidates
order by rank_value,business_name
limit 10;
$$;

grant select on intelligence.v_noel_buyer_order_history to authenticated;
grant select on intelligence.v_noel_buyer_memory_v1 to authenticated;
grant execute on function intelligence.resolve_flower_buyer_v1(uuid,text) to authenticated;
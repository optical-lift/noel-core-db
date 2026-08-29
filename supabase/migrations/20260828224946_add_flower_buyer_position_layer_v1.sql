create table atlas.flower_buyer_buying_profiles (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  buyer_relationship_id uuid not null references atlas.buyer_relationship_reconstruction(id) on delete cascade,
  buyer_lane text not null default 'other',
  buying_stage text not null default 'prospect',
  buying_cadence text not null default 'unknown',
  purchasing_window_class text not null default 'unknown',
  preferred_order_days smallint[] not null default '{}'::smallint[],
  preferred_delivery_days smallint[] not null default '{}'::smallint[],
  preferred_delivery_start_time time without time zone,
  preferred_delivery_end_time time without time zone,
  route_state text not null default 'active',
  route_priority smallint not null default 3,
  commercial_use_cases text[] not null default '{}'::text[],
  typical_weekly_spend_min numeric(12,2),
  typical_weekly_spend_max numeric(12,2),
  purchasing_window_notes text,
  route_notes text,
  last_observed_at timestamptz,
  source_note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint flower_buyer_buying_profiles_buyer_unique unique (farm_id,buyer_relationship_id),
  constraint flower_buyer_buying_profiles_lane_check check (buyer_lane in ('florist_wholesale','worship_altar','hospitality','reception_lobby','event_venue','direct_retail','other')),
  constraint flower_buyer_buying_profiles_stage_check check (buying_stage in ('unqualified','prospect','receptive','trial_buyer','active_buyer','recurring_candidate','recurring','inactive','disqualified')),
  constraint flower_buyer_buying_profiles_cadence_check check (buying_cadence in ('unknown','one_time','occasional','weekly_potential','weekly','biweekly','seasonal')),
  constraint flower_buyer_buying_profiles_window_check check (purchasing_window_class in ('unknown','early_week','midweek','late_week','weekend','flexible')),
  constraint flower_buyer_buying_profiles_order_days_check check (preferred_order_days <@ array[1,2,3,4,5,6,7]::smallint[]),
  constraint flower_buyer_buying_profiles_delivery_days_check check (preferred_delivery_days <@ array[1,2,3,4,5,6,7]::smallint[]),
  constraint flower_buyer_buying_profiles_delivery_time_check check (preferred_delivery_end_time is null or preferred_delivery_start_time is null or preferred_delivery_end_time >= preferred_delivery_start_time),
  constraint flower_buyer_buying_profiles_route_state_check check (route_state in ('active','hold','do_not_route')),
  constraint flower_buyer_buying_profiles_route_priority_check check (route_priority between 1 and 5),
  constraint flower_buyer_buying_profiles_spend_min_check check (typical_weekly_spend_min is null or typical_weekly_spend_min >= 0),
  constraint flower_buyer_buying_profiles_spend_max_check check (typical_weekly_spend_max is null or typical_weekly_spend_max >= 0),
  constraint flower_buyer_buying_profiles_spend_range_check check (typical_weekly_spend_min is null or typical_weekly_spend_max is null or typical_weekly_spend_max >= typical_weekly_spend_min)
);

create index flower_buyer_buying_profiles_route_idx
  on atlas.flower_buyer_buying_profiles(farm_id,route_state,route_priority,buying_stage);
create index flower_buyer_buying_profiles_delivery_days_gin
  on atlas.flower_buyer_buying_profiles using gin(preferred_delivery_days);

create table atlas.flower_buyer_product_preferences (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  buyer_relationship_id uuid not null references atlas.buyer_relationship_reconstruction(id) on delete cascade,
  crop_profile_id uuid references atlas.crop_profiles(id) on delete restrict,
  product_label text not null,
  preference_state text not null default 'unknown',
  usual_quantity numeric(10,2),
  unit text,
  accepted_unit_price numeric(12,2),
  trial_note text,
  notes text,
  source_contact_event_id uuid references atlas.buyer_contact_events(id) on delete set null,
  source_sale_order_id uuid references atlas.flower_sale_orders(id) on delete set null,
  last_observed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint flower_buyer_product_preferences_product_label_check check (nullif(btrim(product_label),'') is not null),
  constraint flower_buyer_product_preferences_state_check check (preference_state in ('unknown','interested','trial','buys','prefers','declined')),
  constraint flower_buyer_product_preferences_quantity_check check (usual_quantity is null or usual_quantity > 0),
  constraint flower_buyer_product_preferences_unit_check check (unit is null or nullif(btrim(unit),'') is not null),
  constraint flower_buyer_product_preferences_price_check check (accepted_unit_price is null or accepted_unit_price >= 0),
  constraint flower_buyer_product_preferences_unique unique nulls not distinct (buyer_relationship_id,crop_profile_id,product_label)
);

create index flower_buyer_product_preferences_buyer_idx
  on atlas.flower_buyer_product_preferences(farm_id,buyer_relationship_id,preference_state);
create index flower_buyer_product_preferences_crop_idx
  on atlas.flower_buyer_product_preferences(farm_id,crop_profile_id) where crop_profile_id is not null;

create or replace function atlas.validate_flower_buyer_buying_profile_scope_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $$
declare v_farm_id uuid;
begin
  select farm_id into v_farm_id from atlas.buyer_relationship_reconstruction where id=new.buyer_relationship_id;
  if v_farm_id is null then raise exception 'Flower buyer profile requires an existing buyer relationship.' using errcode='23503'; end if;
  if v_farm_id is distinct from new.farm_id then raise exception 'Flower buyer profile buyer relationship is outside this farm.' using errcode='23514'; end if;
  return new;
end;
$$;

create or replace function atlas.validate_flower_buyer_product_preference_scope_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $$
declare
  v_farm_id uuid;
  v_source_farm_id uuid;
  v_source_buyer_id uuid;
begin
  select farm_id into v_farm_id from atlas.buyer_relationship_reconstruction where id=new.buyer_relationship_id;
  if v_farm_id is null then raise exception 'Flower buyer product preference requires an existing buyer relationship.' using errcode='23503'; end if;
  if v_farm_id is distinct from new.farm_id then raise exception 'Flower buyer product preference buyer relationship is outside this farm.' using errcode='23514'; end if;

  if new.source_contact_event_id is not null then
    select farm_id,buyer_relationship_id into v_source_farm_id,v_source_buyer_id from atlas.buyer_contact_events where id=new.source_contact_event_id;
    if v_source_farm_id is null or v_source_farm_id is distinct from new.farm_id or v_source_buyer_id is distinct from new.buyer_relationship_id then
      raise exception 'Source contact event does not belong to this buyer relationship.' using errcode='23514';
    end if;
  end if;

  if new.source_sale_order_id is not null then
    select farm_id,buyer_relationship_id into v_source_farm_id,v_source_buyer_id from atlas.flower_sale_orders where id=new.source_sale_order_id;
    if v_source_farm_id is null or v_source_farm_id is distinct from new.farm_id or v_source_buyer_id is distinct from new.buyer_relationship_id then
      raise exception 'Source sale order does not belong to this buyer relationship.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger flower_buyer_buying_profiles_scope_v1
before insert or update on atlas.flower_buyer_buying_profiles
for each row execute function atlas.validate_flower_buyer_buying_profile_scope_v1();
create trigger flower_buyer_buying_profiles_updated_at_v1
before update on atlas.flower_buyer_buying_profiles
for each row execute function atlas.set_updated_at();

create trigger flower_buyer_product_preferences_scope_v1
before insert or update on atlas.flower_buyer_product_preferences
for each row execute function atlas.validate_flower_buyer_product_preference_scope_v1();
create trigger flower_buyer_product_preferences_updated_at_v1
before update on atlas.flower_buyer_product_preferences
for each row execute function atlas.set_updated_at();

alter table atlas.flower_buyer_buying_profiles enable row level security;
alter table atlas.flower_buyer_product_preferences enable row level security;

create policy flower_buyer_buying_profiles_member_read_v1
on atlas.flower_buyer_buying_profiles for select
using (atlas.is_farm_member(farm_id));
create policy flower_buyer_product_preferences_member_read_v1
on atlas.flower_buyer_product_preferences for select
using (atlas.is_farm_member(farm_id));

create or replace view atlas.v_flower_buyer_sales_summary_v1
with (security_invoker=true)
as
with active_sales as (
  select s.*
  from atlas.flower_sale_orders s
  where s.buyer_relationship_id is not null
    and not exists (
      select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=s.id
    )
), last_sale as (
  select distinct on (buyer_relationship_id)
    buyer_relationship_id,id as last_sale_order_id,sale_date as last_purchase_date,total_amount as last_purchase_amount,created_at as last_purchase_recorded_at
  from active_sales
  order by buyer_relationship_id,sale_date desc,created_at desc
)
select
  br.farm_id,
  br.id as buyer_relationship_id,
  count(a.id)::integer as purchase_count,
  coalesce(round(sum(a.total_amount),2),0)::numeric(12,2) as lifetime_spend,
  min(a.sale_date) as first_purchase_date,
  max(a.sale_date) as last_purchase_date,
  ls.last_sale_order_id,
  ls.last_purchase_amount,
  ls.last_purchase_recorded_at
from atlas.buyer_relationship_reconstruction br
left join active_sales a on a.buyer_relationship_id=br.id
left join last_sale ls on ls.buyer_relationship_id=br.id
group by br.farm_id,br.id,ls.last_sale_order_id,ls.last_purchase_amount,ls.last_purchase_recorded_at;

create or replace view atlas.v_flower_buyer_product_sales_v1
with (security_invoker=true)
as
select
  s.farm_id,
  s.buyer_relationship_id,
  r.crop_profile_id,
  coalesce(r.product_label,'Unlabeled flower product') as product_label,
  l.unit,
  count(distinct s.id)::integer as purchase_order_count,
  sum(l.quantity)::numeric(12,2) as total_quantity_purchased,
  round(sum(l.line_total),2)::numeric(12,2) as lifetime_product_spend,
  min(s.sale_date) as first_purchase_date,
  max(s.sale_date) as last_purchase_date,
  min(l.unit_price)::numeric(12,2) as min_accepted_unit_price,
  max(l.unit_price)::numeric(12,2) as max_accepted_unit_price
from atlas.flower_sale_orders s
join atlas.flower_sale_order_lines l on l.sale_order_id=s.id
join atlas.flower_ready_inventory_lots r on r.id=l.ready_lot_id
where s.buyer_relationship_id is not null
  and not exists (select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=s.id)
group by s.farm_id,s.buyer_relationship_id,r.crop_profile_id,coalesce(r.product_label,'Unlabeled flower product'),l.unit;

create or replace view atlas.v_flower_buyer_position_v1
with (security_invoker=true)
as
with standing as (
  select
    buyer_relationship_id,
    count(distinct standing_order_id) filter (where standing_state in ('active','scheduled'))::integer as active_standing_order_count,
    min(next_due_date) filter (where standing_state in ('active','scheduled')) as next_standing_due_date,
    round(sum(target_occurrence_line_value) filter (where standing_state in ('active','scheduled')),2)::numeric(12,2) as active_standing_order_value
  from atlas.flower_standing_order_position_v1
  where buyer_relationship_id is not null
  group by buyer_relationship_id
)
select
  br.farm_id,
  br.id as buyer_relationship_id,
  br.stable_key,
  br.business_name,
  br.buyer_type,
  br.city,
  br.primary_contact_name,
  br.relationship_status,
  coalesce(p.buyer_lane,
    case when br.buyer_type in ('florist','florist_or_flower_retail','mobile_truck_florist','florist_resale','designer') then 'florist_wholesale' else 'other' end
  ) as buyer_lane,
  case when coalesce(st.active_standing_order_count,0)>0 then 'recurring' else p.buying_stage end as buying_stage,
  p.buying_cadence,
  p.purchasing_window_class,
  p.preferred_order_days,
  p.preferred_delivery_days,
  p.preferred_delivery_start_time,
  p.preferred_delivery_end_time,
  coalesce(p.route_state,
    case when br.relationship_status='do_not_contact' or br.pursuit_recommendation='do_not_contact' then 'do_not_route' else 'active' end
  ) as route_state,
  coalesce(p.route_priority,br.priority_rank,3)::smallint as route_priority,
  p.commercial_use_cases,
  p.typical_weekly_spend_min,
  p.typical_weekly_spend_max,
  p.purchasing_window_notes,
  p.route_notes,
  p.last_observed_at,
  br.purchase_history_summary,
  br.buying_preferences as legacy_buying_preferences,
  br.access_notes,
  br.pursuit_recommendation,
  br.next_action,
  coalesce(ss.purchase_count,0) as purchase_count,
  coalesce(ss.lifetime_spend,0)::numeric(12,2) as lifetime_spend,
  ss.first_purchase_date,
  ss.last_purchase_date,
  ss.last_sale_order_id,
  ss.last_purchase_amount,
  coalesce(st.active_standing_order_count,0) as active_standing_order_count,
  st.next_standing_due_date,
  st.active_standing_order_value,
  p.metadata as buying_profile_metadata
from atlas.buyer_relationship_reconstruction br
left join atlas.flower_buyer_buying_profiles p on p.buyer_relationship_id=br.id
left join atlas.v_flower_buyer_sales_summary_v1 ss on ss.buyer_relationship_id=br.id
left join standing st on st.buyer_relationship_id=br.id;

create or replace view intelligence.v_noel_flower_buyer_positions
as
select
  p.*,
  coalesce(pref.preferences,'[]'::jsonb) as known_product_preferences,
  coalesce(sales.products,'[]'::jsonb) as observed_product_sales
from atlas.v_flower_buyer_position_v1 p
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'productLabel',fp.product_label,
    'cropProfileId',fp.crop_profile_id,
    'state',fp.preference_state,
    'usualQuantity',fp.usual_quantity,
    'unit',fp.unit,
    'acceptedUnitPrice',fp.accepted_unit_price,
    'trialNote',fp.trial_note,
    'notes',fp.notes,
    'lastObservedAt',fp.last_observed_at
  ) order by fp.product_label) as preferences
  from atlas.flower_buyer_product_preferences fp
  where fp.buyer_relationship_id=p.buyer_relationship_id
) pref on true
left join lateral (
  select jsonb_agg(jsonb_build_object(
    'productLabel',sp.product_label,
    'cropProfileId',sp.crop_profile_id,
    'unit',sp.unit,
    'orderCount',sp.purchase_order_count,
    'quantityPurchased',sp.total_quantity_purchased,
    'lifetimeSpend',sp.lifetime_product_spend,
    'firstPurchaseDate',sp.first_purchase_date,
    'lastPurchaseDate',sp.last_purchase_date,
    'minAcceptedUnitPrice',sp.min_accepted_unit_price,
    'maxAcceptedUnitPrice',sp.max_accepted_unit_price
  ) order by sp.last_purchase_date desc,sp.product_label) as products
  from atlas.v_flower_buyer_product_sales_v1 sp
  where sp.buyer_relationship_id=p.buyer_relationship_id
) sales on true;

create or replace view intelligence.v_noel_flower_buyer_product_positions
as
select
  br.farm_id,
  br.id as buyer_relationship_id,
  br.stable_key,
  br.business_name,
  fp.crop_profile_id,
  fp.product_label,
  fp.preference_state,
  fp.usual_quantity,
  fp.unit as preferred_unit,
  fp.accepted_unit_price,
  fp.trial_note,
  fp.notes,
  fp.last_observed_at,
  sp.purchase_order_count,
  sp.total_quantity_purchased,
  sp.lifetime_product_spend,
  sp.first_purchase_date,
  sp.last_purchase_date,
  sp.min_accepted_unit_price,
  sp.max_accepted_unit_price
from atlas.buyer_relationship_reconstruction br
join atlas.flower_buyer_product_preferences fp on fp.buyer_relationship_id=br.id
left join atlas.v_flower_buyer_product_sales_v1 sp
  on sp.buyer_relationship_id=br.id
 and sp.crop_profile_id is not distinct from fp.crop_profile_id
 and lower(sp.product_label)=lower(fp.product_label);

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,purchasing_window_notes,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','active_buyer','occasional','unknown','active',1,
  array['florist resale/design']::text[],
  null,
  'Kim is the current purchasing contact. Follow up on the goldenrod trial and learn the useful weekly delivery rhythm.',
  timestamptz '2026-08-28 16:00:00-05',
  'Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('currentContact','Kim','instagramFollowed',true,'instagramPostedImmediately',true)
from atlas.buyer_relationship_reconstruction br where br.stable_key='schaffitzels'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  route_state=excluded.route_state,route_priority=excluded.route_priority,commercial_use_cases=excluded.commercial_use_cases,
  route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  preferred_delivery_days,route_state,route_priority,commercial_use_cases,purchasing_window_notes,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','receptive','weekly_potential','midweek',array[3]::smallint[],'active',1,
  array['florist resale/design']::text[],
  'They were already stocked on Friday. The current staff contact explicitly said Wednesday delivery is preferred.',
  'Approach before the shop is already supplied; Tuesday outreach for a Wednesday drop is the current best test.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('preferredDeliveryDaySource','explicit in-person statement','noSaleReason','already stocked')
from atlas.buyer_relationship_reconstruction br where br.stable_key='house_of_flowers'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  purchasing_window_class=excluded.purchasing_window_class,preferred_delivery_days=excluded.preferred_delivery_days,
  route_state=excluded.route_state,route_priority=excluded.route_priority,commercial_use_cases=excluded.commercial_use_cases,
  purchasing_window_notes=excluded.purchasing_window_notes,route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,
  source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,purchasing_window_notes,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','active_buyer','weekly_potential','early_week','active',1,
  array['florist resale/design']::text[],
  'Historical pattern: by Thursday/Friday the weekly flower budget had usually already been spent with MFE. Contact at the beginning of the buying week.',
  'Use the Monday harvest lane to reach Cassidy Station before MFE captures the week budget.',
  (br.source_date::timestamp at time zone 'America/Chicago'),'Marshall buyer reconstruction, 2026-08-10',
  jsonb_build_object('competitorTimingConstraint','MFE','timingSignal','early_week_before_competitor_budget_commitment')
from atlas.buyer_relationship_reconstruction br where br.stable_key='cassidy_station'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  purchasing_window_class=excluded.purchasing_window_class,route_state=excluded.route_state,route_priority=excluded.route_priority,
  commercial_use_cases=excluded.commercial_use_cases,purchasing_window_notes=excluded.purchasing_window_notes,route_notes=excluded.route_notes,
  last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,purchasing_window_notes,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'worship_altar','recurring_candidate','weekly_potential','unknown','active',1,
  array['altar flowers','church wholesale delivery']::text[],
  'Interested in wholesale delivery for altar flowers; exact delivery day, weekly quantity and budget still need qualification.',
  'Owner follow-up is required to convert this supplier vacancy into a standing order if the economics fit.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('supplierGap',true,'recurringUseCase','altar flowers')
from atlas.buyer_relationship_reconstruction br where br.stable_key='messiah_lutheran_church'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  purchasing_window_class=excluded.purchasing_window_class,route_state=excluded.route_state,route_priority=excluded.route_priority,
  commercial_use_cases=excluded.commercial_use_cases,purchasing_window_notes=excluded.purchasing_window_notes,route_notes=excluded.route_notes,
  last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','receptive','unknown','unknown','active',3,
  array['florist resale/design','educational tour relationship']::text[],
  'Recinna is receptive and followed Elm, but Flowerama has not yet demonstrated flower demand. Preserve the education relationship while lightly qualifying purchasing.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('contactName','Recinna','contactNamePronunciation','Re-seen-a','educationalTourLead',true,'purchaseMade',false)
from atlas.buyer_relationship_reconstruction br where br.stable_key='flowerama'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  route_state=excluded.route_state,route_priority=excluded.route_priority,commercial_use_cases=excluded.commercial_use_cases,
  route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','prospect','unknown','unknown','hold',2,
  array['florist resale/design']::text[],
  'Katie reached only a non-decisionmaker. Preserve the account as potentially warm, but hold immediate follow-up because the owner was reportedly going to the hospital.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('decisionMakerReached',false,'holdReason','owner personal emergency reported during visit')
from atlas.buyer_relationship_reconstruction br where br.stable_key='rose_among_thorns'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  route_state=excluded.route_state,route_priority=excluded.route_priority,commercial_use_cases=excluded.commercial_use_cases,
  route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'florist_wholesale','unqualified','unknown','unknown','do_not_route',5,
  array['florist resale/design']::text[],
  'Katie could not locate this business. Do not place it on another worker route until existence and address are reverified.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('routeAttemptResult','unlocated','requiresAddressReverification',true)
from atlas.buyer_relationship_reconstruction br where br.stable_key='blossoms_floral'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  route_state=excluded.route_state,route_priority=excluded.route_priority,commercial_use_cases=excluded.commercial_use_cases,
  route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_buying_profiles(
  farm_id,buyer_relationship_id,buyer_lane,buying_stage,buying_cadence,purchasing_window_class,
  route_state,route_priority,commercial_use_cases,typical_weekly_spend_min,typical_weekly_spend_max,route_notes,last_observed_at,source_note,metadata
)
select br.farm_id,br.id,'reception_lobby','trial_buyer','one_time','flexible','active',5,
  array['reception desk flowers']::text[],35,35,
  'Count the $35 purchase as real revenue but not as recurring demand. Katie perceived it as possibly a sympathy purchase and saw no follow-up buying signal.',
  timestamptz '2026-08-28 16:00:00-05','Katie final Springfield route report, 2026-08-28',
  jsonb_build_object('purchaseSignalQuality','low recurrence signal','futureInterestObserved',false)
from atlas.buyer_relationship_reconstruction br where br.stable_key='life_meant_to_live'
on conflict (farm_id,buyer_relationship_id) do update set
  buyer_lane=excluded.buyer_lane,buying_stage=excluded.buying_stage,buying_cadence=excluded.buying_cadence,
  purchasing_window_class=excluded.purchasing_window_class,route_state=excluded.route_state,route_priority=excluded.route_priority,
  commercial_use_cases=excluded.commercial_use_cases,typical_weekly_spend_min=excluded.typical_weekly_spend_min,
  typical_weekly_spend_max=excluded.typical_weekly_spend_max,route_notes=excluded.route_notes,last_observed_at=excluded.last_observed_at,
  source_note=excluded.source_note,metadata=atlas.flower_buyer_buying_profiles.metadata||excluded.metadata;

insert into atlas.flower_buyer_product_preferences(
  farm_id,buyer_relationship_id,crop_profile_id,product_label,preference_state,usual_quantity,unit,accepted_unit_price,
  trial_note,notes,source_sale_order_id,last_observed_at,metadata
)
select
  s.farm_id,
  s.buyer_relationship_id,
  r.crop_profile_id,
  r.product_label,
  case when lower(r.product_label)='goldenrod' then 'trial' else 'buys' end,
  l.quantity,
  l.unit,
  l.unit_price,
  case when lower(r.product_label)='goldenrod' then 'Kim bought one goldenrod bundle to see how it opens up.' else null end,
  case when lower(r.product_label) like '%sunflower%' then 'Kim purchased two sunflower bundles on Katie''s 2026-08-28 route.' else null end,
  s.id,
  s.created_at,
  jsonb_build_object('evidence','completed sale','routeSeller','Katie Langenberg')
from atlas.flower_sale_orders s
join atlas.flower_sale_order_lines l on l.sale_order_id=s.id
join atlas.flower_ready_inventory_lots r on r.id=l.ready_lot_id
where s.idempotency_key='katie-route-20260828-schaffitzels-20-corrected'
  and not exists (select 1 from atlas.flower_sale_order_cancellation_events c where c.sale_order_id=s.id)
on conflict on constraint flower_buyer_product_preferences_unique do update set
  preference_state=excluded.preference_state,
  usual_quantity=excluded.usual_quantity,
  unit=excluded.unit,
  accepted_unit_price=excluded.accepted_unit_price,
  trial_note=excluded.trial_note,
  notes=excluded.notes,
  source_sale_order_id=excluded.source_sale_order_id,
  last_observed_at=excluded.last_observed_at,
  metadata=atlas.flower_buyer_product_preferences.metadata||excluded.metadata;
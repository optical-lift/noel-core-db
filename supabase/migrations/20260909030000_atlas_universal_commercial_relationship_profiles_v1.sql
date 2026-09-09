begin;

-- Commercial relationship behavior is not a flower-domain concept. Preserve crop,
-- route, and farm-specific observations as extension metadata while promoting the
-- reusable relationship profile and item-preference semantics to Atlas core.

create table atlas.external_relationship_commercial_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  external_relationship_id uuid not null unique references atlas.external_relationships(id) on delete restrict,
  commercial_stage text,
  engagement_cadence text,
  purchasing_window_class text,
  preferred_order_days smallint[] not null default '{}'::smallint[],
  preferred_fulfillment_days smallint[] not null default '{}'::smallint[],
  preferred_fulfillment_start_time time,
  preferred_fulfillment_end_time time,
  commercial_use_cases text[] not null default '{}'::text[],
  typical_spend_min numeric(14,2),
  typical_spend_max numeric(14,2),
  spend_currency text,
  purchasing_window_note text,
  last_observed_at timestamptz,
  source_note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_relationship_commercial_profiles_spend_check check (typical_spend_min is null or typical_spend_max is null or typical_spend_max>=typical_spend_min),
  constraint external_relationship_commercial_profiles_currency_check check (spend_currency is null or spend_currency ~ '^[A-Z]{3}$'),
  constraint external_relationship_commercial_profiles_order_days_check check (preferred_order_days <@ array[0,1,2,3,4,5,6]::smallint[]),
  constraint external_relationship_commercial_profiles_fulfillment_days_check check (preferred_fulfillment_days <@ array[0,1,2,3,4,5,6]::smallint[])
);
comment on table atlas.external_relationship_commercial_profiles is 'Current reusable commercial-behavior projection for an external relationship: stage, cadence, purchasing windows, fulfillment preferences, use cases, and observed spend range. Domain-specific route or product facts remain extension metadata.';

create table atlas.external_relationship_item_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  offering_id uuid references atlas.commercial_offerings(id) on delete restrict,
  item_label text not null,
  preference_state text not null,
  usual_quantity numeric(14,3),
  unit text,
  accepted_unit_price numeric(14,2),
  currency text,
  note text,
  source_interaction_id uuid references atlas.external_relationship_interactions(id) on delete set null,
  source_commercial_order_id uuid references atlas.commercial_orders(id) on delete set null,
  last_observed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_relationship_item_preferences_item_nonblank check (btrim(item_label)<>''),
  constraint external_relationship_item_preferences_quantity_check check (usual_quantity is null or usual_quantity>0),
  constraint external_relationship_item_preferences_price_check check (accepted_unit_price is null or accepted_unit_price>=0),
  constraint external_relationship_item_preferences_currency_check check (currency is null or currency ~ '^[A-Z]{3}$')
);
create index external_relationship_item_preferences_relationship_idx on atlas.external_relationship_item_preferences(external_relationship_id,preference_state,item_label);
create index external_relationship_item_preferences_offering_idx on atlas.external_relationship_item_preferences(offering_id) where offering_id is not null;
comment on table atlas.external_relationship_item_preferences is 'Observed item/offering preference for an external relationship. The universal preference can point to a canonical commercial offering when resolved; unresolved or domain-specific item identity remains labeled and evidenced in metadata.';

create table atlas.flower_buyer_profile_commercial_extensions (
  flower_buyer_buying_profile_id uuid primary key references atlas.flower_buyer_buying_profiles(id) on delete restrict,
  external_relationship_commercial_profile_id uuid not null unique references atlas.external_relationship_commercial_profiles(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table atlas.flower_buyer_preference_commercial_extensions (
  flower_buyer_product_preference_id uuid primary key references atlas.flower_buyer_product_preferences(id) on delete restrict,
  external_relationship_item_preference_id uuid not null unique references atlas.external_relationship_item_preferences(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  crop_profile_id uuid references atlas.crop_profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create or replace function atlas.guard_external_relationship_commercial_profile_scope_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if not exists(select 1 from atlas.external_relationships r where r.id=new.external_relationship_id and r.organization_id=new.organization_id) then
    raise exception 'Commercial profile/preference relationship must belong to the same organization.' using errcode='23514';
  end if;
  if tg_table_name='external_relationship_item_preferences' then
    if new.offering_id is not null and not exists(select 1 from atlas.commercial_offerings o where o.id=new.offering_id and o.organization_id=new.organization_id) then
      raise exception 'Commercial preference offering must belong to the same organization.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
create trigger external_relationship_commercial_profiles_scope_guard_v1 before insert or update of organization_id,external_relationship_id on atlas.external_relationship_commercial_profiles for each row execute function atlas.guard_external_relationship_commercial_profile_scope_v1();
create trigger external_relationship_item_preferences_scope_guard_v1 before insert or update of organization_id,external_relationship_id,offering_id on atlas.external_relationship_item_preferences for each row execute function atlas.guard_external_relationship_commercial_profile_scope_v1();

insert into atlas.external_relationship_commercial_profiles(
  organization_id,external_relationship_id,commercial_stage,engagement_cadence,purchasing_window_class,
  preferred_order_days,preferred_fulfillment_days,preferred_fulfillment_start_time,preferred_fulfillment_end_time,
  commercial_use_cases,typical_spend_min,typical_spend_max,spend_currency,purchasing_window_note,last_observed_at,source_note,metadata,created_at,updated_at
)
select f.organization_id,m.external_relationship_id,b.buying_stage,b.buying_cadence,b.purchasing_window_class,
  b.preferred_order_days,b.preferred_delivery_days,b.preferred_delivery_start_time,b.preferred_delivery_end_time,
  b.commercial_use_cases,b.typical_weekly_spend_min,b.typical_weekly_spend_max,null,b.purchasing_window_notes,b.last_observed_at,b.source_note,
  jsonb_build_object('sourceDomain','flower_buyer_buying_profile','legacyFlowerBuyerBuyingProfileId',b.id,'buyerLane',b.buyer_lane,'routeState',b.route_state,'routePriority',b.route_priority,'routeNotes',b.route_notes,'spendPeriod','week','legacyMetadata',b.metadata),b.created_at,b.updated_at
from atlas.flower_buyer_buying_profiles b
join atlas.farms f on f.id=b.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.buyer_relationship_id
where not exists(select 1 from atlas.flower_buyer_profile_commercial_extensions x where x.flower_buyer_buying_profile_id=b.id);

insert into atlas.flower_buyer_profile_commercial_extensions(flower_buyer_buying_profile_id,external_relationship_commercial_profile_id,farm_id)
select b.id,p.id,b.farm_id
from atlas.flower_buyer_buying_profiles b
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.buyer_relationship_id
join atlas.external_relationship_commercial_profiles p on p.external_relationship_id=m.external_relationship_id
on conflict do nothing;

insert into atlas.external_relationship_item_preferences(
  organization_id,external_relationship_id,offering_id,item_label,preference_state,usual_quantity,unit,
  accepted_unit_price,currency,note,source_interaction_id,source_commercial_order_id,last_observed_at,metadata,created_at,updated_at
)
select f.organization_id,m.external_relationship_id,null,p.product_label,p.preference_state,p.usual_quantity,p.unit,
  p.accepted_unit_price,null,concat_ws(E'\n',p.trial_note,p.notes),ci.external_relationship_interaction_id,fo.commercial_order_id,p.last_observed_at,
  jsonb_build_object('sourceDomain','flower_buyer_product_preference','legacyFlowerBuyerProductPreferenceId',p.id,'cropProfileId',p.crop_profile_id,'legacyMetadata',p.metadata),p.created_at,p.updated_at
from atlas.flower_buyer_product_preferences p
join atlas.farms f on f.id=p.farm_id
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=p.buyer_relationship_id
left join atlas.legacy_buyer_contact_external_interaction_mappings ci on ci.buyer_contact_event_id=p.source_contact_event_id
left join atlas.flower_commercial_order_extensions fo on fo.flower_sale_order_id=p.source_sale_order_id
where not exists(select 1 from atlas.flower_buyer_preference_commercial_extensions x where x.flower_buyer_product_preference_id=p.id);

insert into atlas.flower_buyer_preference_commercial_extensions(flower_buyer_product_preference_id,external_relationship_item_preference_id,farm_id,crop_profile_id)
select p.id,g.id,p.farm_id,p.crop_profile_id
from atlas.flower_buyer_product_preferences p
join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=p.buyer_relationship_id
join atlas.external_relationship_item_preferences g on g.external_relationship_id=m.external_relationship_id and (g.metadata->>'legacyFlowerBuyerProductPreferenceId')::uuid=p.id
on conflict do nothing;

alter table atlas.external_relationship_commercial_profiles enable row level security;
alter table atlas.external_relationship_item_preferences enable row level security;
alter table atlas.flower_buyer_profile_commercial_extensions enable row level security;
alter table atlas.flower_buyer_preference_commercial_extensions enable row level security;
revoke all on atlas.external_relationship_commercial_profiles,atlas.external_relationship_item_preferences,atlas.flower_buyer_profile_commercial_extensions,atlas.flower_buyer_preference_commercial_extensions from public,anon,authenticated;
grant select,insert,update on atlas.external_relationship_commercial_profiles,atlas.external_relationship_item_preferences to service_role;
grant select,insert on atlas.flower_buyer_profile_commercial_extensions,atlas.flower_buyer_preference_commercial_extensions to service_role;
revoke all on function atlas.guard_external_relationship_commercial_profile_scope_v1() from public,anon,authenticated;
grant execute on function atlas.guard_external_relationship_commercial_profile_scope_v1() to service_role;

commit;

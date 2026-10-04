-- Atlas flower-commercial extension parentage v1
-- Make flower-specific commercial state a direct Organization/external-
-- relationship extension. Legacy buyer_relationship_id remains an optional
-- compatibility pointer for pre-succession rows, not the identity parent.

alter table atlas.flower_buyer_buying_profiles
  add column if not exists organization_id uuid,
  add column if not exists external_relationship_id uuid;

alter table atlas.flower_buyer_product_preferences
  add column if not exists organization_id uuid,
  add column if not exists external_relationship_id uuid;

alter table atlas.buyer_reported_purchase_history
  add column if not exists organization_id uuid,
  add column if not exists external_relationship_id uuid;

-- Backfill flower buying-profile parentage from the already-proven universal
-- commercial-profile extension bridge.
update atlas.flower_buyer_buying_profiles p
set organization_id=gp.organization_id,
    external_relationship_id=gp.external_relationship_id
from atlas.flower_buyer_profile_commercial_extensions x
join atlas.external_relationship_commercial_profiles gp
  on gp.id=x.external_relationship_commercial_profile_id
where x.flower_buyer_buying_profile_id=p.id
  and (p.organization_id is null or p.external_relationship_id is null);

-- Backfill flower item-preference parentage from the already-proven universal
-- item-preference extension bridge.
update atlas.flower_buyer_product_preferences p
set organization_id=ip.organization_id,
    external_relationship_id=ip.external_relationship_id
from atlas.flower_buyer_preference_commercial_extensions x
join atlas.external_relationship_item_preferences ip
  on ip.id=x.external_relationship_item_preference_id
where x.flower_buyer_product_preference_id=p.id
  and (p.organization_id is null or p.external_relationship_id is null);

-- Backfill legacy reported-history parentage from buyer succession.
update atlas.buyer_reported_purchase_history h
set organization_id=r.organization_id,
    external_relationship_id=m.external_relationship_id
from atlas.legacy_buyer_relationship_external_mappings m
join atlas.external_relationships r
  on r.id=m.external_relationship_id
where m.buyer_relationship_id=h.buyer_relationship_id
  and (h.organization_id is null or h.external_relationship_id is null);

do $$
begin
  if exists(
    select 1 from atlas.flower_buyer_buying_profiles
    where organization_id is null or external_relationship_id is null
  ) then
    raise exception 'Flower buyer profile succession left unresolved parentage.'
      using errcode='23514';
  end if;

  if exists(
    select 1 from atlas.flower_buyer_product_preferences
    where organization_id is null or external_relationship_id is null
  ) then
    raise exception 'Flower buyer preference succession left unresolved parentage.'
      using errcode='23514';
  end if;

  if exists(
    select 1 from atlas.buyer_reported_purchase_history
    where organization_id is null or external_relationship_id is null
  ) then
    raise exception 'Buyer reported-history succession left unresolved parentage.'
      using errcode='23514';
  end if;
end
$$;

alter table atlas.flower_buyer_buying_profiles
  alter column organization_id set not null,
  alter column external_relationship_id set not null,
  alter column buyer_relationship_id drop not null;

alter table atlas.flower_buyer_product_preferences
  alter column organization_id set not null,
  alter column external_relationship_id set not null,
  alter column buyer_relationship_id drop not null;

alter table atlas.buyer_reported_purchase_history
  alter column organization_id set not null,
  alter column external_relationship_id set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.flower_buyer_buying_profiles'::regclass
      and conname='flower_buyer_buying_profiles_org_fk_v1'
  ) then
    alter table atlas.flower_buyer_buying_profiles
      add constraint flower_buyer_buying_profiles_org_fk_v1
      foreign key (organization_id)
      references atlas.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.flower_buyer_buying_profiles'::regclass
      and conname='flower_buyer_buying_profiles_external_relationship_fk_v1'
  ) then
    alter table atlas.flower_buyer_buying_profiles
      add constraint flower_buyer_buying_profiles_external_relationship_fk_v1
      foreign key (organization_id,external_relationship_id)
      references atlas.external_relationships(organization_id,id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.flower_buyer_buying_profiles'::regclass
      and conname='flower_buyer_buying_profiles_org_relationship_uq_v1'
  ) then
    alter table atlas.flower_buyer_buying_profiles
      add constraint flower_buyer_buying_profiles_org_relationship_uq_v1
      unique (organization_id,external_relationship_id);
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.flower_buyer_product_preferences'::regclass
      and conname='flower_buyer_product_preferences_org_fk_v1'
  ) then
    alter table atlas.flower_buyer_product_preferences
      add constraint flower_buyer_product_preferences_org_fk_v1
      foreign key (organization_id)
      references atlas.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.flower_buyer_product_preferences'::regclass
      and conname='flower_buyer_product_preferences_external_relationship_fk_v1'
  ) then
    alter table atlas.flower_buyer_product_preferences
      add constraint flower_buyer_product_preferences_external_relationship_fk_v1
      foreign key (organization_id,external_relationship_id)
      references atlas.external_relationships(organization_id,id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.buyer_reported_purchase_history'::regclass
      and conname='buyer_reported_purchase_history_org_fk_v1'
  ) then
    alter table atlas.buyer_reported_purchase_history
      add constraint buyer_reported_purchase_history_org_fk_v1
      foreign key (organization_id)
      references atlas.organizations(id)
      on delete restrict;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.buyer_reported_purchase_history'::regclass
      and conname='buyer_reported_purchase_history_external_relationship_fk_v1'
  ) then
    alter table atlas.buyer_reported_purchase_history
      add constraint buyer_reported_purchase_history_external_relationship_fk_v1
      foreign key (organization_id,external_relationship_id)
      references atlas.external_relationships(organization_id,id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists flower_buyer_product_preferences_relationship_item_uq_v1
  on atlas.flower_buyer_product_preferences(
    organization_id,
    external_relationship_id,
    crop_profile_id,
    product_label
  ) nulls not distinct;

-- Complete the one remaining reported-commercial-history succession row.
with source_history as (
  select
    h.id,
    h.organization_id,
    h.external_relationship_id,
    h.evidence_key,
    h.summary,
    h.amount_min,
    h.amount_max,
    h.source_person,
    h.source_date,
    h.metadata
  from atlas.buyer_reported_purchase_history h
  where h.id='51aa2e28-707f-4e2c-86e9-313ae037a065'::uuid
),
inserted as (
  insert into atlas.external_relationship_reported_commercial_history(
    organization_id,
    external_relationship_id,
    evidence_key,
    summary,
    amount_min,
    amount_max,
    currency,
    source_label,
    source_date,
    metadata
  )
  select
    h.organization_id,
    h.external_relationship_id,
    h.evidence_key,
    h.summary,
    h.amount_min,
    h.amount_max,
    case when h.amount_min is not null or h.amount_max is not null then 'USD' else null end,
    h.source_person,
    h.source_date,
    coalesce(h.metadata,'{}'::jsonb) || jsonb_build_object(
      'legacyBuyerReportedHistoryId',h.id,
      'successionBasis','legacy_buyer_reported_purchase_history'
    )
  from source_history h
  where not exists(
    select 1
    from atlas.legacy_buyer_reported_history_external_mappings m
    where m.buyer_reported_history_id=h.id
  )
  on conflict (organization_id,evidence_key) do nothing
  returning id,organization_id,evidence_key
)
insert into atlas.legacy_buyer_reported_history_external_mappings(
  buyer_reported_history_id,
  external_relationship_reported_history_id
)
select h.id,coalesce(
  i.id,
  (
    select gh.id
    from atlas.external_relationship_reported_commercial_history gh
    where gh.organization_id=h.organization_id
      and gh.evidence_key=h.evidence_key
    limit 1
  )
)
from source_history h
left join inserted i
  on i.organization_id=h.organization_id
 and i.evidence_key=h.evidence_key
where not exists(
  select 1
  from atlas.legacy_buyer_reported_history_external_mappings m
  where m.buyer_reported_history_id=h.id
);

create or replace function atlas.validate_flower_buyer_buying_profile_scope_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_farm_org uuid;
  v_legacy_relationship uuid;
begin
  select f.organization_id
  into v_farm_org
  from atlas.farms f
  where f.id=new.farm_id;

  if v_farm_org is null then
    raise exception 'Flower commercial profile requires an existing farm.'
      using errcode='23503';
  end if;

  if v_farm_org is distinct from new.organization_id then
    raise exception 'Flower commercial profile relationship is outside the farm Organization.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.external_relationships r
    where r.id=new.external_relationship_id
      and r.organization_id=new.organization_id
  ) then
    raise exception 'Flower commercial profile requires an Organization external relationship.'
      using errcode='23503';
  end if;

  if new.buyer_relationship_id is not null then
    select m.external_relationship_id
    into v_legacy_relationship
    from atlas.legacy_buyer_relationship_external_mappings m
    where m.buyer_relationship_id=new.buyer_relationship_id;

    if v_legacy_relationship is null
       or v_legacy_relationship is distinct from new.external_relationship_id then
      raise exception 'Legacy buyer pointer disagrees with the generic external relationship parent.'
        using errcode='23514';
    end if;
  end if;

  return new;
end
$function$;

create or replace function atlas.validate_flower_buyer_product_preference_scope_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_farm_org uuid;
  v_legacy_relationship uuid;
  v_source_farm_id uuid;
  v_source_buyer_id uuid;
begin
  select f.organization_id
  into v_farm_org
  from atlas.farms f
  where f.id=new.farm_id;

  if v_farm_org is null then
    raise exception 'Flower product preference requires an existing farm.'
      using errcode='23503';
  end if;

  if v_farm_org is distinct from new.organization_id then
    raise exception 'Flower product preference relationship is outside the farm Organization.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.external_relationships r
    where r.id=new.external_relationship_id
      and r.organization_id=new.organization_id
  ) then
    raise exception 'Flower product preference requires an Organization external relationship.'
      using errcode='23503';
  end if;

  if new.buyer_relationship_id is not null then
    select m.external_relationship_id
    into v_legacy_relationship
    from atlas.legacy_buyer_relationship_external_mappings m
    where m.buyer_relationship_id=new.buyer_relationship_id;

    if v_legacy_relationship is null
       or v_legacy_relationship is distinct from new.external_relationship_id then
      raise exception 'Legacy buyer pointer disagrees with the generic external relationship parent.'
        using errcode='23514';
    end if;
  end if;

  if new.source_contact_event_id is not null then
    select e.farm_id,e.buyer_relationship_id
    into v_source_farm_id,v_source_buyer_id
    from atlas.buyer_contact_events e
    where e.id=new.source_contact_event_id;

    if v_source_farm_id is null
       or v_source_farm_id is distinct from new.farm_id
       or (
         new.buyer_relationship_id is not null
         and v_source_buyer_id is distinct from new.buyer_relationship_id
       ) then
      raise exception 'Source legacy contact event is outside this flower relationship extension.'
        using errcode='23514';
    end if;
  end if;

  if new.source_sale_order_id is not null then
    select o.farm_id,o.buyer_relationship_id
    into v_source_farm_id,v_source_buyer_id
    from atlas.flower_sale_orders o
    where o.id=new.source_sale_order_id;

    if v_source_farm_id is null
       or v_source_farm_id is distinct from new.farm_id
       or (
         new.buyer_relationship_id is not null
         and v_source_buyer_id is distinct from new.buyer_relationship_id
       ) then
      raise exception 'Source legacy flower sale order is outside this flower relationship extension.'
        using errcode='23514';
    end if;
  end if;

  return new;
end
$function$;

create or replace function atlas.validate_legacy_reported_purchase_history_scope_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_farm_org uuid;
  v_relationship uuid;
begin
  select f.organization_id
  into v_farm_org
  from atlas.farms f
  where f.id=new.farm_id;

  if v_farm_org is null or v_farm_org is distinct from new.organization_id then
    raise exception 'Reported commercial history is outside the farm Organization.'
      using errcode='23514';
  end if;

  select m.external_relationship_id
  into v_relationship
  from atlas.legacy_buyer_relationship_external_mappings m
  where m.buyer_relationship_id=new.buyer_relationship_id;

  if v_relationship is null
     or v_relationship is distinct from new.external_relationship_id then
    raise exception 'Reported commercial history legacy pointer disagrees with generic relationship parent.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

drop trigger if exists buyer_reported_purchase_history_scope_v1
  on atlas.buyer_reported_purchase_history;

create trigger buyer_reported_purchase_history_scope_v1
before insert or update
on atlas.buyer_reported_purchase_history
for each row
execute function atlas.validate_legacy_reported_purchase_history_scope_v1();

comment on table atlas.flower_buyer_buying_profiles is
  'Flower-domain commercial extension scoped directly to an Atlas Organization external relationship. buyer_relationship_id is an optional legacy compatibility pointer, not the identity parent.';
comment on column atlas.flower_buyer_buying_profiles.buyer_relationship_id is
  'Optional pre-succession buyer compatibility pointer. external_relationship_id is the relationship parent.';
comment on table atlas.flower_buyer_product_preferences is
  'Flower-domain item-preference extension scoped directly to an Atlas Organization external relationship. buyer_relationship_id is an optional legacy compatibility pointer.';
comment on column atlas.flower_buyer_product_preferences.buyer_relationship_id is
  'Optional pre-succession buyer compatibility pointer. external_relationship_id is the relationship parent.';
comment on table atlas.buyer_reported_purchase_history is
  'Legacy reported-purchase-history compatibility table. Generic authority is atlas.external_relationship_reported_commercial_history; all legacy rows now carry explicit Organization/external-relationship parentage.';

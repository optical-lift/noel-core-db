begin;

-- Follow-on to universal commerce v1. These concepts were discovered under Elm/
-- flower names but are not agricultural concepts: relationship contact history,
-- reported commercial history, commercial fulfillment, recurring commitments, and
-- product price-book identity are reusable across Ledger types.

create table atlas.external_relationship_interactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  occurred_at timestamptz not null,
  interaction_kind text not null,
  channel text,
  outcome text,
  contact_label text,
  follow_up text,
  note text,
  source_task_id uuid references atlas.tasks(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_relationship_interactions_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint external_relationship_interactions_kind_check check (interaction_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);
create index external_relationship_interactions_relationship_time_idx on atlas.external_relationship_interactions(external_relationship_id,occurred_at desc,id);
comment on table atlas.external_relationship_interactions is 'Universal contact/interaction history for an organization external relationship. Sales outreach, supplier contact, partnership contact, support contact, and future interaction kinds share this spine.';

create table atlas.external_relationship_reported_commercial_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete restrict,
  evidence_key text not null,
  summary text not null,
  amount_min numeric(14,2),
  amount_max numeric(14,2),
  currency text,
  source_label text,
  source_date date,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_relationship_reported_history_amounts_check check (amount_min is null or amount_max is null or amount_max>=amount_min),
  constraint external_relationship_reported_history_currency_check check (currency is null or currency ~ '^[A-Z]{3}$'),
  unique(organization_id,evidence_key)
);
comment on table atlas.external_relationship_reported_commercial_history is 'Reported or reconstructed commercial history about an external relationship. This remains evidence and must not be summed as canonical orders or collected revenue.';

create table atlas.commercial_fulfillment_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  commercial_order_id uuid not null references atlas.commercial_orders(id) on delete restrict,
  event_kind text not null,
  fulfillment_method text,
  occurred_at timestamptz not null,
  effective_date date,
  source_task_id uuid references atlas.tasks(id) on delete set null,
  note text,
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_fulfillment_events_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_fulfillment_events_kind_check check (event_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);
create unique index commercial_fulfillment_events_idempotency_uq on atlas.commercial_fulfillment_events(organization_id,idempotency_key) where idempotency_key is not null;
create index commercial_fulfillment_events_order_time_idx on atlas.commercial_fulfillment_events(commercial_order_id,occurred_at,id);
comment on table atlas.commercial_fulfillment_events is 'Universal append-only evidence that a commercial commitment was fulfilled, delivered, handed off, completed, shipped, or otherwise satisfied. Domain production evidence remains in typed extensions.';

create table atlas.recurring_commercial_commitments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  customer_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  customer_subject_id uuid references atlas.identity_subjects(id) on delete restrict,
  commitment_kind text not null default 'recurring_order',
  channel text,
  recurrence_kind text not null,
  recurrence_interval integer not null default 1 check (recurrence_interval>0),
  first_due_date date not null,
  active_until date,
  fulfillment_method text,
  fulfillment_due_time time,
  status text not null default 'active' check (status in ('draft','active','paused','ended','cancelled')),
  note text,
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint recurring_commercial_commitments_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint recurring_commercial_commitments_dates_check check (active_until is null or active_until>=first_due_date)
);
create unique index recurring_commercial_commitments_idempotency_uq on atlas.recurring_commercial_commitments(organization_id,idempotency_key) where idempotency_key is not null;

create table atlas.recurring_commercial_commitment_lines (
  id uuid primary key default gen_random_uuid(),
  recurring_commitment_id uuid not null references atlas.recurring_commercial_commitments(id) on delete cascade,
  offering_id uuid references atlas.commercial_offerings(id) on delete restrict,
  description text not null,
  quantity numeric(14,3) not null check (quantity>0),
  unit text not null,
  target_unit_price numeric(14,2),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
comment on table atlas.recurring_commercial_commitments is 'Universal recurring customer commitment. Flower standing orders, recurring service visits, subscription deliveries, and similar Ledger-specific workflows extend this object.';

create table atlas.flower_price_book_commercial_extensions (
  flower_price_book_id uuid primary key references atlas.flower_product_price_book(id) on delete restrict,
  commercial_offering_id uuid not null references atlas.commercial_offerings(id) on delete restrict,
  commercial_offering_price_id uuid not null unique references atlas.commercial_offering_prices(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table atlas.flower_fulfillment_commercial_extensions (
  flower_fulfillment_event_id uuid primary key references atlas.flower_fulfillment_events(id) on delete restrict,
  commercial_fulfillment_event_id uuid not null unique references atlas.commercial_fulfillment_events(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table atlas.legacy_buyer_contact_external_interaction_mappings (
  buyer_contact_event_id uuid primary key references atlas.buyer_contact_events(id) on delete restrict,
  external_relationship_interaction_id uuid not null unique references atlas.external_relationship_interactions(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table atlas.legacy_buyer_reported_history_external_mappings (
  buyer_reported_history_id uuid primary key references atlas.buyer_reported_purchase_history(id) on delete restrict,
  external_relationship_reported_history_id uuid not null unique references atlas.external_relationship_reported_commercial_history(id) on delete restrict,
  created_at timestamptz not null default now()
);

create or replace function atlas.prevent_universal_relationship_history_mutation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  raise exception 'Universal relationship/commercial history is append-only; record a later fact or correcting event instead.' using errcode='55000';
end;
$function$;
create trigger external_relationship_interactions_append_only_v1 before update or delete on atlas.external_relationship_interactions for each row execute function atlas.prevent_universal_relationship_history_mutation_v1();
create trigger external_relationship_reported_history_append_only_v1 before update or delete on atlas.external_relationship_reported_commercial_history for each row execute function atlas.prevent_universal_relationship_history_mutation_v1();
create trigger commercial_fulfillment_events_append_only_v1 before update or delete on atlas.commercial_fulfillment_events for each row execute function atlas.prevent_universal_relationship_history_mutation_v1();

create or replace function atlas.guard_universal_relationship_scope_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if tg_table_name='external_relationship_interactions' or tg_table_name='external_relationship_reported_commercial_history' then
    if not exists(select 1 from atlas.external_relationships r where r.id=new.external_relationship_id and r.organization_id=new.organization_id) then
      raise exception 'External relationship must belong to the same organization.' using errcode='23514';
    end if;
  elsif tg_table_name='commercial_fulfillment_events' then
    if not exists(select 1 from atlas.commercial_orders o where o.id=new.commercial_order_id and o.organization_id=new.organization_id) then
      raise exception 'Commercial order must belong to the same organization.' using errcode='23514';
    end if;
  elsif tg_table_name='recurring_commercial_commitments' then
    if new.customer_relationship_id is not null and not exists(select 1 from atlas.external_relationships r where r.id=new.customer_relationship_id and r.organization_id=new.organization_id) then
      raise exception 'Recurring commitment relationship must belong to the same organization.' using errcode='23514';
    end if;
    if new.customer_subject_id is not null and not exists(select 1 from atlas.identity_subjects s where s.id=new.customer_subject_id and s.organization_id=new.organization_id) then
      raise exception 'Recurring commitment subject must belong to the same organization.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
create trigger external_relationship_interactions_scope_guard_v1 before insert or update of organization_id,external_relationship_id on atlas.external_relationship_interactions for each row execute function atlas.guard_universal_relationship_scope_v1();
create trigger external_relationship_reported_history_scope_guard_v1 before insert or update of organization_id,external_relationship_id on atlas.external_relationship_reported_commercial_history for each row execute function atlas.guard_universal_relationship_scope_v1();
create trigger commercial_fulfillment_events_scope_guard_v1 before insert or update of organization_id,commercial_order_id on atlas.commercial_fulfillment_events for each row execute function atlas.guard_universal_relationship_scope_v1();
create trigger recurring_commercial_commitments_scope_guard_v1 before insert or update of organization_id,customer_relationship_id,customer_subject_id on atlas.recurring_commercial_commitments for each row execute function atlas.guard_universal_relationship_scope_v1();

-- Contact events were generic CRM facts stored under a buyer/farm noun. Preserve all
-- flower-specific offer/quantity/quote details as metadata rather than putting them
-- into the universal interaction shape.
insert into atlas.external_relationship_interactions(
  organization_id,organization_unit_id,external_relationship_id,occurred_at,interaction_kind,channel,outcome,contact_label,follow_up,note,source_task_id,metadata,created_at
)
select f.organization_id,f.organization_unit_id,m.external_relationship_id,b.occurred_at,'contact',b.contact_method,b.outcome,b.contact_name,b.follow_up,b.notes,b.source_task_id,
  jsonb_build_object('sourceDomain','legacy_buyer_contact','legacyBuyerContactEventId',b.id,'contactDetails',b.contact_details,'salesChannel',b.sales_channel,'offerKey',b.offer_key,'quantity',b.quantity,'quotedWeeklyPrice',b.quoted_weekly_price,'agreedStartDate',b.agreed_start_date,'legacyRecordedByFarmMembershipId',b.recorded_by_membership_id,'legacyMetadata',b.metadata),b.created_at
from atlas.buyer_contact_events b join atlas.farms f on f.id=b.farm_id join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.buyer_relationship_id
where not exists(select 1 from atlas.legacy_buyer_contact_external_interaction_mappings x where x.buyer_contact_event_id=b.id);

insert into atlas.legacy_buyer_contact_external_interaction_mappings(buyer_contact_event_id,external_relationship_interaction_id)
select b.id,i.id from atlas.buyer_contact_events b join atlas.farms f on f.id=b.farm_id join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=b.buyer_relationship_id join atlas.external_relationship_interactions i on i.external_relationship_id=m.external_relationship_id and (i.metadata->>'legacyBuyerContactEventId')::uuid=b.id
on conflict do nothing;

insert into atlas.external_relationship_reported_commercial_history(organization_id,external_relationship_id,evidence_key,summary,amount_min,amount_max,currency,source_label,source_date,metadata,created_at)
select f.organization_id,m.external_relationship_id,'legacy_buyer_reported_purchase:'||h.id,h.summary,h.amount_min,h.amount_max,null,h.source_person,h.source_date,
  jsonb_build_object('sourceDomain','legacy_buyer_reported_purchase_history','legacyBuyerReportedPurchaseHistoryId',h.id,'legacyEvidenceKey',h.evidence_key,'legacyMetadata',h.metadata),h.created_at
from atlas.buyer_reported_purchase_history h join atlas.farms f on f.id=h.farm_id join atlas.legacy_buyer_relationship_external_mappings m on m.buyer_relationship_id=h.buyer_relationship_id
where not exists(select 1 from atlas.legacy_buyer_reported_history_external_mappings x where x.buyer_reported_history_id=h.id);
insert into atlas.legacy_buyer_reported_history_external_mappings(buyer_reported_history_id,external_relationship_reported_history_id)
select h.id,g.id from atlas.buyer_reported_purchase_history h join atlas.external_relationship_reported_commercial_history g on g.evidence_key='legacy_buyer_reported_purchase:'||h.id
on conflict do nothing;

-- The small Elm flower price book becomes real universal offering/price truth with a
-- flower extension pointing back to the original production-facing product identity.
do $backfill_flower_price_book$
declare p record;v_offering uuid;v_price uuid;begin
  for p in select fp.*,f.organization_id,f.organization_unit_id,cp.stable_key crop_key,cp.crop_label,cp.variety from atlas.flower_product_price_book fp join atlas.farms f on f.id=fp.farm_id left join atlas.crop_profiles cp on cp.id=fp.crop_profile_id order by fp.created_at,fp.id loop
    if exists(select 1 from atlas.flower_price_book_commercial_extensions x where x.flower_price_book_id=p.id) then continue; end if;
    insert into atlas.commercial_offerings(organization_id,organization_unit_id,stable_key,name,offering_kind,default_unit,status,metadata,created_at,updated_at)
    values(p.organization_id,p.organization_unit_id,'flower_price_'||replace(p.id::text,'-',''),coalesce(nullif(p.crop_label,''),initcap(replace(p.inventory_kind,'_',' '))),'flower_product',p.unit,'active',jsonb_build_object('sourceDomain','flower','legacyFlowerPriceBookId',p.id,'inventoryKind',p.inventory_kind,'cropProfileId',p.crop_profile_id,'cropKey',p.crop_key,'variety',p.variety,'legacyMetadata',p.metadata),p.created_at,p.created_at)
    returning id into v_offering;
    insert into atlas.commercial_offering_prices(offering_id,price_basis,unit_price,currency,effective_from,source,metadata,created_at)
    values(v_offering,'standard',p.unit_price,upper(p.currency),p.effective_from,p.source,jsonb_build_object('sourceDomain','flower','legacyFlowerPriceBookId',p.id,'note',p.note),p.created_at)
    returning id into v_price;
    insert into atlas.flower_price_book_commercial_extensions(flower_price_book_id,commercial_offering_id,commercial_offering_price_id,farm_id) values(p.id,v_offering,v_price,p.farm_id);
  end loop;
end;$backfill_flower_price_book$;

-- Fulfillment is universal; flower preparation/harvest remains domain evidence.
insert into atlas.commercial_fulfillment_events(organization_id,organization_unit_id,commercial_order_id,event_kind,fulfillment_method,occurred_at,effective_date,source_task_id,note,idempotency_key,metadata,created_at)
select f.organization_id,f.organization_unit_id,x.commercial_order_id,'fulfilled',e.fulfillment_method,e.fulfilled_at,e.effective_fulfillment_date,e.task_id,e.note,'legacy_flower_fulfillment:'||e.id,
  jsonb_build_object('sourceDomain','flower','legacyFlowerFulfillmentEventId',e.id,'legacyRecordedByFarmMembershipId',e.recorded_by_membership_id,'legacyMetadata',e.metadata),e.created_at
from atlas.flower_fulfillment_events e join atlas.farms f on f.id=e.farm_id join atlas.flower_commercial_order_extensions x on x.flower_sale_order_id=e.sale_order_id
where not exists(select 1 from atlas.flower_fulfillment_commercial_extensions fx where fx.flower_fulfillment_event_id=e.id);
insert into atlas.flower_fulfillment_commercial_extensions(flower_fulfillment_event_id,commercial_fulfillment_event_id,farm_id)
select e.id,g.id,e.farm_id from atlas.flower_fulfillment_events e join atlas.commercial_fulfillment_events g on g.idempotency_key='legacy_flower_fulfillment:'||e.id
on conflict do nothing;

-- Existing flower standing orders are currently empty, but establish the domain
-- bridge now so the next one does not create a second universal recurring-order model.
create table atlas.flower_recurring_commercial_commitment_extensions (
  flower_standing_order_id uuid primary key references atlas.flower_standing_orders(id) on delete restrict,
  recurring_commercial_commitment_id uuid not null unique references atlas.recurring_commercial_commitments(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table atlas.flower_recurring_commercial_commitment_line_extensions (
  flower_standing_order_line_id uuid primary key references atlas.flower_standing_order_lines(id) on delete restrict,
  recurring_commercial_commitment_line_id uuid not null unique references atlas.recurring_commercial_commitment_lines(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  crop_profile_id uuid references atlas.crop_profiles(id) on delete restrict,
  inventory_kind text,
  created_at timestamptz not null default now()
);

alter table atlas.external_relationship_interactions enable row level security;
alter table atlas.external_relationship_reported_commercial_history enable row level security;
alter table atlas.commercial_fulfillment_events enable row level security;
alter table atlas.recurring_commercial_commitments enable row level security;
alter table atlas.recurring_commercial_commitment_lines enable row level security;
alter table atlas.flower_price_book_commercial_extensions enable row level security;
alter table atlas.flower_fulfillment_commercial_extensions enable row level security;
alter table atlas.legacy_buyer_contact_external_interaction_mappings enable row level security;
alter table atlas.legacy_buyer_reported_history_external_mappings enable row level security;
alter table atlas.flower_recurring_commercial_commitment_extensions enable row level security;
alter table atlas.flower_recurring_commercial_commitment_line_extensions enable row level security;

revoke all on atlas.external_relationship_interactions,atlas.external_relationship_reported_commercial_history,atlas.commercial_fulfillment_events,atlas.recurring_commercial_commitments,atlas.recurring_commercial_commitment_lines,atlas.flower_price_book_commercial_extensions,atlas.flower_fulfillment_commercial_extensions,atlas.legacy_buyer_contact_external_interaction_mappings,atlas.legacy_buyer_reported_history_external_mappings,atlas.flower_recurring_commercial_commitment_extensions,atlas.flower_recurring_commercial_commitment_line_extensions from public,anon,authenticated;
grant select,insert on atlas.external_relationship_interactions,atlas.external_relationship_reported_commercial_history,atlas.commercial_fulfillment_events,atlas.recurring_commercial_commitments,atlas.recurring_commercial_commitment_lines,atlas.flower_price_book_commercial_extensions,atlas.flower_fulfillment_commercial_extensions,atlas.legacy_buyer_contact_external_interaction_mappings,atlas.legacy_buyer_reported_history_external_mappings,atlas.flower_recurring_commercial_commitment_extensions,atlas.flower_recurring_commercial_commitment_line_extensions to service_role;
grant update on atlas.recurring_commercial_commitments to service_role;
revoke all on function atlas.prevent_universal_relationship_history_mutation_v1(),atlas.guard_universal_relationship_scope_v1() from public,anon,authenticated;
grant execute on function atlas.prevent_universal_relationship_history_mutation_v1(),atlas.guard_universal_relationship_scope_v1() to service_role;

commit;

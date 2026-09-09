begin;

-- Atlas universal external relationship + commerce v1
--
-- Domain adapters (flowers, community registrations, future professional services,
-- retail, subscriptions, etc.) may extend these objects, but may not redefine the
-- organization-scoped external party, order, offering, payment, or source-evidence
-- concepts. Provider observations remain evidence until interpreted into these
-- canonical objects.

create table atlas.external_relationships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  stable_key text not null,
  relationship_state text not null default 'active'
    check (relationship_state in ('prospective','active','inactive','ended','unknown')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_relationships_stable_key_nonblank check (btrim(stable_key)<>''),
  constraint external_relationships_unit_org_fk foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict
);

create unique index external_relationships_org_key_uq
  on atlas.external_relationships(organization_id,stable_key)
  where organization_unit_id is null;
create unique index external_relationships_unit_key_uq
  on atlas.external_relationships(organization_id,organization_unit_id,stable_key)
  where organization_unit_id is not null;
create index external_relationships_subject_idx
  on atlas.external_relationships(organization_id,subject_id,relationship_state);

comment on table atlas.external_relationships is
  'Organization-scoped relationship to an external identity subject. Customer, supplier, partner, referral source, venue host, and similar meanings are roles on this relationship; no domain noun such as buyer or florist is part of the universal identity.';

create table atlas.external_relationship_roles (
  external_relationship_id uuid not null references atlas.external_relationships(id) on delete cascade,
  role_key text not null,
  role_state text not null default 'active' check (role_state in ('active','inactive','ended')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(external_relationship_id,role_key),
  constraint external_relationship_roles_key_check check (role_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);

comment on table atlas.external_relationship_roles is
  'Typed meanings carried by one external relationship. A single subject may simultaneously be customer, supplier, partner, host, or another governed role.';

create table atlas.identity_subject_external_identifiers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  subject_id uuid not null references atlas.identity_subjects(id) on delete cascade,
  provider_key text,
  identifier_type text not null,
  identifier_value text not null,
  identifier_normalized text not null,
  is_current boolean not null default true,
  priority smallint not null default 3 check (priority between 1 and 9),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint identity_subject_external_identifiers_type_check
    check (identifier_type ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  constraint identity_subject_external_identifiers_value_nonblank check (btrim(identifier_value)<>''),
  constraint identity_subject_external_identifiers_normalized_nonblank check (btrim(identifier_normalized)<>'')
);
create index identity_subject_external_identifiers_lookup_idx
  on atlas.identity_subject_external_identifiers(organization_id,provider_key,identifier_type,identifier_normalized)
  where is_current;
create unique index identity_subject_external_identifiers_subject_value_uq
  on atlas.identity_subject_external_identifiers(subject_id,coalesce(provider_key,''),identifier_type,identifier_normalized)
  where is_current;

comment on table atlas.identity_subject_external_identifiers is
  'Reusable external identity resolution keys for organization-scoped identity subjects: provider customer ids, emails, phones, vendor ids, legacy keys, names, and future source-specific identifiers. Identifier presence is evidence for resolution, not authority.';

create or replace function atlas.guard_external_subject_organization_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  if not exists(
    select 1 from atlas.identity_subjects s
    where s.id=new.subject_id and s.organization_id=new.organization_id
  ) then
    raise exception 'External relationship/identifier subject must belong to the same organization.' using errcode='23514';
  end if;
  return new;
end;
$function$;

create trigger external_relationships_subject_org_guard_v1
before insert or update of organization_id,subject_id on atlas.external_relationships
for each row execute function atlas.guard_external_subject_organization_v1();
create trigger identity_subject_external_identifiers_subject_org_guard_v1
before insert or update of organization_id,subject_id on atlas.identity_subject_external_identifiers
for each row execute function atlas.guard_external_subject_organization_v1();

create table atlas.commercial_offerings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  stable_key text not null,
  name text not null,
  offering_kind text not null default 'item',
  default_unit text,
  status text not null default 'active' check (status in ('draft','active','inactive','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commercial_offerings_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_offerings_stable_key_nonblank check (btrim(stable_key)<>''),
  constraint commercial_offerings_name_nonblank check (btrim(name)<>''),
  constraint commercial_offerings_kind_nonblank check (btrim(offering_kind)<>'')
);
create unique index commercial_offerings_org_key_uq on atlas.commercial_offerings(organization_id,stable_key)
  where organization_unit_id is null;
create unique index commercial_offerings_unit_key_uq on atlas.commercial_offerings(organization_id,organization_unit_id,stable_key)
  where organization_unit_id is not null;

comment on table atlas.commercial_offerings is
  'Universal thing/service/right an organization offers commercially. Flower crops, event registrations, consulting hours, venue rentals, subscriptions, and future domain products extend or reference this object.';

create table atlas.commercial_offering_prices (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references atlas.commercial_offerings(id) on delete restrict,
  price_basis text not null default 'standard',
  unit_price numeric(14,2) not null check (unit_price>=0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  effective_from date not null,
  effective_until date,
  source text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_offering_prices_basis_nonblank check (btrim(price_basis)<>''),
  constraint commercial_offering_prices_window_check check (effective_until is null or effective_until>=effective_from)
);
create index commercial_offering_prices_lookup_idx
  on atlas.commercial_offering_prices(offering_id,effective_from desc,created_at desc);

create table atlas.commercial_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  customer_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  customer_subject_id uuid references atlas.identity_subjects(id) on delete restrict,
  order_kind text not null default 'sale',
  order_date date not null,
  channel text,
  subtotal_amount numeric(14,2) not null default 0 check (subtotal_amount>=0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount>=0),
  tip_amount numeric(14,2) not null default 0 check (tip_amount>=0),
  total_amount numeric(14,2) not null default 0 check (total_amount>=0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  idempotency_key text,
  note text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_orders_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_orders_kind_nonblank check (btrim(order_kind)<>''),
  constraint commercial_orders_amount_shape check (total_amount=subtotal_amount+tax_amount+tip_amount)
);
create unique index commercial_orders_idempotency_uq
  on atlas.commercial_orders(organization_id,idempotency_key) where idempotency_key is not null;
create index commercial_orders_customer_idx
  on atlas.commercial_orders(organization_id,customer_relationship_id,order_date desc,created_at desc);

create table atlas.commercial_order_lines (
  id uuid primary key default gen_random_uuid(),
  commercial_order_id uuid not null references atlas.commercial_orders(id) on delete cascade,
  offering_id uuid references atlas.commercial_offerings(id) on delete restrict,
  description text not null,
  quantity numeric(14,3) not null check (quantity>0),
  unit text not null,
  unit_price numeric(14,2) not null check (unit_price>=0),
  line_total numeric(14,2) not null check (line_total>=0),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_order_lines_description_nonblank check (btrim(description)<>''),
  constraint commercial_order_lines_unit_nonblank check (btrim(unit)<>'')
);
create index commercial_order_lines_order_idx on atlas.commercial_order_lines(commercial_order_id,id);
create index commercial_order_lines_offering_idx on atlas.commercial_order_lines(offering_id) where offering_id is not null;

create table atlas.commercial_order_events (
  id uuid primary key default gen_random_uuid(),
  commercial_order_id uuid not null references atlas.commercial_orders(id) on delete cascade,
  event_kind text not null,
  occurred_at timestamptz not null default now(),
  reason_kind text,
  note text,
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_order_events_kind_check check (event_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);
create unique index commercial_order_events_idempotency_uq
  on atlas.commercial_order_events(commercial_order_id,idempotency_key) where idempotency_key is not null;
create index commercial_order_events_order_time_idx on atlas.commercial_order_events(commercial_order_id,occurred_at,id);

create table atlas.commercial_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  commercial_order_id uuid references atlas.commercial_orders(id) on delete restrict,
  payer_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  payer_subject_id uuid references atlas.identity_subjects(id) on delete restrict,
  provider_key text,
  provider_payment_key text,
  amount numeric(14,2) not null check (amount>=0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  observed_state text not null default 'unknown',
  paid_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_payments_unit_org_fk foreign key(organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  constraint commercial_payments_observed_state_check
    check (observed_state in ('unknown','pending','succeeded','failed','partially_refunded','refunded','disputed','cancelled'))
);
create unique index commercial_payments_provider_key_uq
  on atlas.commercial_payments(organization_id,provider_key,provider_payment_key)
  where provider_key is not null and provider_payment_key is not null;
create index commercial_payments_order_idx on atlas.commercial_payments(commercial_order_id,paid_at,created_at)
  where commercial_order_id is not null;
create index commercial_payments_payer_idx on atlas.commercial_payments(organization_id,payer_relationship_id,paid_at desc)
  where payer_relationship_id is not null;

create table atlas.commercial_payment_events (
  id uuid primary key default gen_random_uuid(),
  commercial_payment_id uuid not null references atlas.commercial_payments(id) on delete cascade,
  event_kind text not null,
  amount_delta numeric(14,2) not null,
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  occurred_at timestamptz not null,
  provider_event_key text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint commercial_payment_events_kind_check check (event_kind ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);
create unique index commercial_payment_events_provider_uq
  on atlas.commercial_payment_events(commercial_payment_id,provider_event_key)
  where provider_event_key is not null;
create index commercial_payment_events_payment_time_idx
  on atlas.commercial_payment_events(commercial_payment_id,occurred_at,id);

comment on table atlas.commercial_orders is
  'Universal commercial commitment/sale record. Domain-specific fulfillment, production, booking, registration, or service-delivery facts live in typed extensions rather than on the universal order.';
comment on table atlas.commercial_payments is
  'Universal observed payment identity and amount. Lifecycle changes are append-only commercial_payment_events; provider-specific records remain linked source evidence.';

create table atlas.commercial_source_links (
  id uuid primary key default gen_random_uuid(),
  connected_source_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  target_kind text not null check (target_kind in ('external_relationship','commercial_offering','commercial_order','commercial_order_line','commercial_payment','commercial_payment_event')),
  target_id uuid not null,
  interpretation_kind text not null default 'supports',
  interpretation_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(interpretation_basis)='object'),
  created_at timestamptz not null default now(),
  unique(connected_source_observation_id,target_kind,target_id)
);
comment on table atlas.commercial_source_links is
  'Explicit bridge from immutable provider observations to interpreted commercial truth. A source observation never becomes truth merely by existing.';

-- Domain-extension bridges. Existing domain records remain durable and addressable;
-- these rows state which universal commercial object carries their generic meaning.
create table atlas.flower_commercial_order_extensions (
  flower_sale_order_id uuid primary key references atlas.flower_sale_orders(id) on delete restrict,
  commercial_order_id uuid not null unique references atlas.commercial_orders(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
create table atlas.flower_commercial_order_line_extensions (
  flower_sale_order_line_id uuid primary key references atlas.flower_sale_order_lines(id) on delete restrict,
  commercial_order_line_id uuid not null unique references atlas.commercial_order_lines(id) on delete restrict,
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  ready_lot_id uuid references atlas.flower_ready_inventory_lots(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now()
);
create table atlas.community_registration_commercial_offering_extensions (
  registration_offering_id uuid primary key references atlas.community_registration_offerings(id) on delete restrict,
  commercial_offering_id uuid not null unique references atlas.commercial_offerings(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table atlas.community_registration_commercial_order_extensions (
  registration_id uuid primary key references atlas.community_registrations(id) on delete restrict,
  commercial_order_id uuid not null unique references atlas.commercial_orders(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table atlas.community_registration_commercial_payment_extensions (
  registration_payment_id uuid primary key references atlas.community_registration_payments(id) on delete restrict,
  commercial_payment_id uuid not null unique references atlas.commercial_payments(id) on delete restrict,
  created_at timestamptz not null default now()
);

-- Legacy buyer relationship mapping is explicit and reversible. No name-based merge is
-- performed because the reconstruction contains duplicate labels and mixed customer/
-- supplier semantics.
create table atlas.legacy_buyer_relationship_external_mappings (
  buyer_relationship_id uuid primary key references atlas.buyer_relationship_reconstruction(id) on delete restrict,
  external_relationship_id uuid not null unique references atlas.external_relationships(id) on delete restrict,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  created_at timestamptz not null default now()
);

-- Universal commercial history is append-only. Mutable relationship and offering
-- projections are intentionally excluded; later facts replace them through governed
-- relationship/price changes rather than rewriting transactional history.
create or replace function atlas.prevent_universal_commercial_truth_mutation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
begin
  raise exception 'Universal commercial transaction history is append-only; record a correcting event instead.' using errcode='55000';
end;
$function$;

create trigger commercial_offering_prices_append_only_v1 before update or delete on atlas.commercial_offering_prices
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_orders_append_only_v1 before update or delete on atlas.commercial_orders
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_order_lines_append_only_v1 before update or delete on atlas.commercial_order_lines
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_order_events_append_only_v1 before update or delete on atlas.commercial_order_events
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_payments_append_only_v1 before update or delete on atlas.commercial_payments
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_payment_events_append_only_v1 before update or delete on atlas.commercial_payment_events
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();
create trigger commercial_source_links_append_only_v1 before update or delete on atlas.commercial_source_links
for each row execute function atlas.prevent_universal_commercial_truth_mutation_v1();

-- Ensure customer/payer pointers cannot cross organization custody.
create or replace function atlas.guard_commercial_party_organization_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_relationship_id uuid; v_subject_id uuid;
begin
  if tg_table_name='commercial_orders' then
    v_relationship_id:=new.customer_relationship_id; v_subject_id:=new.customer_subject_id;
  else
    v_relationship_id:=new.payer_relationship_id; v_subject_id:=new.payer_subject_id;
  end if;
  if v_relationship_id is not null and not exists(
    select 1 from atlas.external_relationships r where r.id=v_relationship_id and r.organization_id=new.organization_id
  ) then raise exception 'Commercial relationship must belong to the same organization.' using errcode='23514'; end if;
  if v_subject_id is not null and not exists(
    select 1 from atlas.identity_subjects s where s.id=v_subject_id and s.organization_id=new.organization_id
  ) then raise exception 'Commercial subject must belong to the same organization.' using errcode='23514'; end if;
  if v_relationship_id is not null and v_subject_id is not null and not exists(
    select 1 from atlas.external_relationships r where r.id=v_relationship_id and r.subject_id=v_subject_id
  ) then raise exception 'Commercial relationship and subject must identify the same external party.' using errcode='23514'; end if;
  return new;
end;
$function$;
create trigger commercial_orders_party_org_guard_v1 before insert or update of organization_id,customer_relationship_id,customer_subject_id on atlas.commercial_orders
for each row execute function atlas.guard_commercial_party_organization_v1();
create trigger commercial_payments_party_org_guard_v1 before insert or update of organization_id,payer_relationship_id,payer_subject_id on atlas.commercial_payments
for each row execute function atlas.guard_commercial_party_organization_v1();

-- Backfill each legacy external relationship into its own identity subject. We
-- deliberately do not merge same-named rows: historical reconstruction evidence is
-- not sufficient to prove they are the same real-world party.
do $backfill_relationships$
declare r record; v_subject uuid; v_relationship uuid; v_state text; v_role text;
begin
  for r in
    select br.*,f.organization_id,f.organization_unit_id
    from atlas.buyer_relationship_reconstruction br
    join atlas.farms f on f.id=br.farm_id
    order by br.created_at,br.id
  loop
    if exists(select 1 from atlas.legacy_buyer_relationship_external_mappings m where m.buyer_relationship_id=r.id) then continue; end if;

    insert into atlas.identity_subjects(organization_id,state,created_by_user_id,creation_basis)
    values(r.organization_id,'active',null,jsonb_build_object(
      'source','atlas_universal_external_relationship_and_commerce_v1',
      'legacyDomain','buyer_relationship_reconstruction',
      'legacyId',r.id,
      'legacyBuyerType',r.buyer_type
    )) returning id into v_subject;

    insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis)
    values(
      v_subject,r.organization_id,
      case when r.buyer_type='individual' then 'person' else 'organization' end,
      r.business_name,
      jsonb_build_array(r.stable_key),
      '[]'::jsonb,false,null,
      jsonb_build_object('source','legacy_buyer_relationship_reconstruction','legacyId',r.id,'legacyBuyerType',r.buyer_type)
    );

    v_state:=case
      when r.relationship_status ilike '%never%bought%' or r.relationship_status ilike '%nonbuyer%' or r.relationship_status ilike '%pending%' or r.relationship_status ilike '%rebuild%' then 'prospective'
      when r.relationship_status ilike '%active%' or r.relationship_status ilike '%buyer%' or r.relationship_status ilike '%receptive%' then 'active'
      else 'unknown' end;

    insert into atlas.external_relationships(organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata)
    values(r.organization_id,r.organization_unit_id,v_subject,'legacy_'||replace(r.id::text,'-',''),v_state,
      jsonb_build_object(
        'source','buyer_relationship_reconstruction',
        'legacyBuyerRelationshipId',r.id,
        'legacyStableKey',r.stable_key,
        'legacyBuyerType',r.buyer_type,
        'legacyRelationshipStatus',r.relationship_status,
        'city',r.city,
        'primaryContactName',r.primary_contact_name,
        'priorityRank',r.priority_rank,
        'volumeTier',r.volume_tier,
        'productInterests',to_jsonb(r.product_interests),
        'buyingPreferences',to_jsonb(r.buying_preferences)
      )) returning id into v_relationship;

    -- Preserve the old table's mixed semantics while moving the universal role out
    -- of the misleading buyer noun.
    v_role:=case
      when r.buyer_type like '%input_source%' or r.buyer_type like '%clipping_source%' then 'supplier'
      when r.buyer_type in ('community_program') then 'partner'
      else 'customer' end;
    insert into atlas.external_relationship_roles(external_relationship_id,role_key,basis)
    values(v_relationship,v_role,jsonb_build_object('source','legacy_buyer_type','value',r.buyer_type));

    insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,priority,metadata)
    values(r.organization_id,v_subject,null,'legacy_relationship_key',r.stable_key,
      lower(regexp_replace(btrim(r.stable_key),'[^a-zA-Z0-9]+','','g')),2,
      jsonb_build_object('source','buyer_relationship_reconstruction','legacyId',r.id));
    insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,priority,metadata)
    values(r.organization_id,v_subject,null,'display_name',r.business_name,
      lower(regexp_replace(btrim(r.business_name),'[^a-zA-Z0-9]+','','g')),4,
      jsonb_build_object('source','buyer_relationship_reconstruction','legacyId',r.id));

    insert into atlas.legacy_buyer_relationship_external_mappings(buyer_relationship_id,external_relationship_id,identity_subject_id)
    values(r.id,v_relationship,v_subject);
  end loop;
end;
$backfill_relationships$;

-- Backfill existing flower sales into universal commercial orders while preserving
-- the flower sale row as a domain extension. No commercial payment is inferred from
-- an order: collection must be supported by payment evidence.
do $backfill_flower_sales$
declare s record; v_order uuid; v_line uuid; v_map record;
begin
  for s in
    select fs.*,f.organization_id,f.organization_unit_id
    from atlas.flower_sale_orders fs join atlas.farms f on f.id=fs.farm_id
    order by fs.created_at,fs.id
  loop
    if exists(select 1 from atlas.flower_commercial_order_extensions x where x.flower_sale_order_id=s.id) then continue; end if;
    select m.external_relationship_id,m.identity_subject_id into v_map
    from atlas.legacy_buyer_relationship_external_mappings m where m.buyer_relationship_id=s.buyer_relationship_id;

    insert into atlas.commercial_orders(
      organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,
      order_kind,order_date,channel,subtotal_amount,tax_amount,tip_amount,total_amount,currency,
      idempotency_key,note,metadata,created_at
    ) values(
      s.organization_id,s.organization_unit_id,v_map.external_relationship_id,v_map.identity_subject_id,
      'sale',s.sale_date,s.sales_channel,s.subtotal_amount,s.tax_amount,s.tip_amount,s.total_amount,upper(s.currency),
      'legacy_flower_sale_order:'||s.id,s.note,
      jsonb_build_object(
        'sourceDomain','flower','legacyFlowerSaleOrderId',s.id,'farmId',s.farm_id,
        'customerLabel',s.customer_label,'eventKey',s.event_key,
        'fulfillmentMode',s.fulfillment_mode,'fulfillmentDueDate',s.fulfillment_due_date,
        'fulfillmentDueTime',s.fulfillment_due_time,'legacyFulfillmentMembershipId',s.fulfillment_membership_id,
        'legacySourceTaskId',s.source_task_id,'legacyMetadata',s.metadata
      ),s.created_at
    ) returning id into v_order;

    insert into atlas.commercial_order_events(commercial_order_id,event_kind,occurred_at,idempotency_key,metadata)
    values(v_order,'recorded',s.created_at,'legacy_flower_sale_recorded:'||s.id,jsonb_build_object('source','flower_sale_orders'));

    insert into atlas.flower_commercial_order_extensions(flower_sale_order_id,commercial_order_id,farm_id,metadata)
    values(s.id,v_order,s.farm_id,jsonb_build_object('migration','atlas_universal_external_relationship_and_commerce_v1'));

    for v_map in select l.* from atlas.flower_sale_order_lines l where l.sale_order_id=s.id order by l.created_at,l.id loop
      insert into atlas.commercial_order_lines(commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,metadata,created_at)
      values(v_order,null,coalesce(nullif(v_map.inventory_kind,''),'Flower item'),v_map.quantity,v_map.unit,v_map.unit_price,v_map.line_total,
        jsonb_build_object('sourceDomain','flower','legacyFlowerSaleOrderLineId',v_map.id,'readyLotId',v_map.ready_lot_id,'inventoryKind',v_map.inventory_kind,'legacyMetadata',v_map.metadata),v_map.created_at)
      returning id into v_line;
      insert into atlas.flower_commercial_order_line_extensions(flower_sale_order_line_id,commercial_order_line_id,farm_id,ready_lot_id)
      values(v_map.id,v_line,s.farm_id,v_map.ready_lot_id);
    end loop;
  end loop;

  insert into atlas.commercial_order_events(commercial_order_id,event_kind,occurred_at,reason_kind,note,idempotency_key,metadata)
  select x.commercial_order_id,'cancelled',c.created_at,c.reason_kind,c.note,'legacy_flower_sale_cancel:'||c.id,
    jsonb_build_object('sourceDomain','flower','legacyCancellationEventId',c.id,'legacyMetadata',c.metadata)
  from atlas.flower_sale_order_cancellation_events c
  join atlas.flower_commercial_order_extensions x on x.flower_sale_order_id=c.sale_order_id
  where not exists(select 1 from atlas.commercial_order_events e where e.commercial_order_id=x.commercial_order_id and e.idempotency_key='legacy_flower_sale_cancel:'||c.id);
end;
$backfill_flower_sales$;

-- Community registration is a domain workflow, but its offering/order/payment
-- concepts are universal commerce. Backfill the current records without merging
-- registrants by name; email/phone become reusable resolution identifiers.
do $backfill_registration_commerce$
declare o record; r record; p record; v_offering uuid; v_subject uuid; v_relationship uuid; v_order uuid; v_payment uuid;
begin
  for o in
    select co.*,f.organization_id,f.organization_unit_id
    from atlas.community_registration_offerings co join atlas.farms f on f.id=co.farm_id
    order by co.created_at,co.id
  loop
    select x.commercial_offering_id into v_offering from atlas.community_registration_commercial_offering_extensions x where x.registration_offering_id=o.id;
    if v_offering is null then
      insert into atlas.commercial_offerings(organization_id,organization_unit_id,stable_key,name,offering_kind,default_unit,status,metadata,created_at,updated_at)
      values(o.organization_id,o.organization_unit_id,'registration_'||replace(o.id::text,'-',''),o.title,'registration',o.fee_basis,
        case when o.status='open' then 'active' when o.status='draft' then 'draft' when o.status='cancelled' then 'retired' else 'inactive' end,
        jsonb_build_object('sourceDomain','community_registration','legacyRegistrationOfferingId',o.id,'programId',o.program_id,'eventId',o.event_id,'registrationType',o.registration_type,'registrationScope',o.registration_scope,'legacyStableKey',o.stable_key,'legacyMetadata',o.metadata),o.created_at,o.updated_at)
      returning id into v_offering;
      insert into atlas.community_registration_commercial_offering_extensions(registration_offering_id,commercial_offering_id) values(o.id,v_offering);
      if o.fee_amount>0 then
        insert into atlas.commercial_offering_prices(offering_id,price_basis,unit_price,currency,effective_from,source,metadata,created_at)
        values(v_offering,o.fee_basis,o.fee_amount,upper(o.fee_currency),coalesce(o.opens_at::date,o.created_at::date),'community_registration_offerings',jsonb_build_object('legacyRegistrationOfferingId',o.id),o.created_at);
      end if;
    end if;

    for r in select cr.* from atlas.community_registrations cr where cr.offering_id=o.id order by cr.created_at,cr.id loop
      select x.commercial_order_id into v_order from atlas.community_registration_commercial_order_extensions x where x.registration_id=r.id;
      if v_order is null then
        insert into atlas.identity_subjects(organization_id,state,created_by_user_id,creation_basis)
        values(o.organization_id,'active',null,jsonb_build_object('source','community_registration','legacyRegistrationId',r.id)) returning id into v_subject;
        insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis)
        values(v_subject,o.organization_id,case when r.registrant_type='vendor' then 'organization' else 'person' end,
          r.primary_name,'[]'::jsonb,'[]'::jsonb,false,null,jsonb_build_object('source','community_registration','legacyRegistrationId',r.id));
        insert into atlas.external_relationships(organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata)
        values(o.organization_id,o.organization_unit_id,v_subject,'registration_'||replace(r.id::text,'-',''),
          case when r.status in ('cancelled','refunded') then 'inactive' else 'active' end,
          jsonb_build_object('sourceDomain','community_registration','legacyRegistrationId',r.id,'registrationNumber',r.registration_number,'registrantType',r.registrant_type,'householdName',r.household_name))
        returning id into v_relationship;
        insert into atlas.external_relationship_roles(external_relationship_id,role_key,basis)
        values(v_relationship,'customer',jsonb_build_object('source','community_registration'));
        if nullif(btrim(coalesce(r.primary_email,'')),'') is not null then
          insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,priority,metadata)
          values(o.organization_id,v_subject,null,'email',r.primary_email,lower(btrim(r.primary_email)),1,jsonb_build_object('source','community_registration','legacyRegistrationId',r.id));
        end if;
        if nullif(btrim(coalesce(r.primary_phone,'')),'') is not null then
          insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,priority,metadata)
          values(o.organization_id,v_subject,null,'phone',r.primary_phone,regexp_replace(r.primary_phone,'[^0-9]+','','g'),2,jsonb_build_object('source','community_registration','legacyRegistrationId',r.id));
        end if;

        insert into atlas.commercial_orders(organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,order_kind,order_date,channel,subtotal_amount,tax_amount,tip_amount,total_amount,currency,idempotency_key,metadata,created_at)
        values(o.organization_id,o.organization_unit_id,v_relationship,v_subject,'registration',coalesce(r.submitted_at::date,r.created_at::date),'registration',o.fee_amount,0,0,o.fee_amount,upper(o.fee_currency),
          'legacy_registration:'||r.id,jsonb_build_object('sourceDomain','community_registration','legacyRegistrationId',r.id,'registrationNumber',r.registration_number,'statusSnapshot',r.status),r.created_at)
        returning id into v_order;
        insert into atlas.commercial_order_lines(commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,metadata,created_at)
        values(v_order,v_offering,o.title,1,o.fee_basis,o.fee_amount,o.fee_amount,jsonb_build_object('sourceDomain','community_registration','legacyRegistrationId',r.id),r.created_at);
        insert into atlas.commercial_order_events(commercial_order_id,event_kind,occurred_at,idempotency_key,metadata)
        values(v_order,'recorded',coalesce(r.submitted_at,r.created_at),'legacy_registration_recorded:'||r.id,jsonb_build_object('source','community_registrations'));
        if r.cancelled_at is not null then
          insert into atlas.commercial_order_events(commercial_order_id,event_kind,occurred_at,idempotency_key,metadata)
          values(v_order,'cancelled',r.cancelled_at,'legacy_registration_cancelled:'||r.id,jsonb_build_object('source','community_registrations'));
        end if;
        insert into atlas.community_registration_commercial_order_extensions(registration_id,commercial_order_id) values(r.id,v_order);
      else
        select co.customer_relationship_id,co.customer_subject_id into v_relationship,v_subject from atlas.commercial_orders co where co.id=v_order;
      end if;

      for p in select cp.* from atlas.community_registration_payments cp where cp.registration_id=r.id order by cp.created_at,cp.id loop
        if exists(select 1 from atlas.community_registration_commercial_payment_extensions x where x.registration_payment_id=p.id) then continue; end if;
        insert into atlas.commercial_payments(organization_id,organization_unit_id,commercial_order_id,payer_relationship_id,payer_subject_id,provider_key,provider_payment_key,amount,currency,observed_state,paid_at,metadata,created_at)
        values(o.organization_id,o.organization_unit_id,v_order,v_relationship,v_subject,lower(nullif(btrim(coalesce(p.payment_processor,'')),'')),nullif(btrim(coalesce(p.external_payment_id,'')),''),p.amount,upper(p.currency),
          case p.status when 'paid' then 'succeeded' else p.status end,p.paid_at,
          jsonb_build_object('sourceDomain','community_registration','legacyRegistrationPaymentId',p.id,'legacyMetadata',p.metadata),p.created_at)
        returning id into v_payment;
        if p.paid_at is not null and p.status in ('paid','refunded','partially_refunded') then
          insert into atlas.commercial_payment_events(commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata)
          values(v_payment,'succeeded',p.amount,upper(p.currency),p.paid_at,
            case when p.external_payment_id is null then 'legacy_registration_paid:'||p.id else 'payment:'||p.external_payment_id end,
            jsonb_build_object('source','community_registration_payments'));
        end if;
        if p.status='refunded' and p.refunded_at is not null then
          insert into atlas.commercial_payment_events(commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata)
          values(v_payment,'refund',-p.amount,upper(p.currency),p.refunded_at,'legacy_registration_refund:'||p.id,jsonb_build_object('source','community_registration_payments','fullRefundInferredFromStatus',true));
        end if;
        insert into atlas.community_registration_commercial_payment_extensions(registration_payment_id,commercial_payment_id) values(p.id,v_payment);
      end loop;
    end loop;
  end loop;
end;
$backfill_registration_commerce$;

create or replace view atlas.v_commercial_relationship_order_summary_v1
with (security_invoker=true) as
with active_orders as (
  select o.* from atlas.commercial_orders o
  where o.customer_relationship_id is not null
    and not exists(select 1 from atlas.commercial_order_events e where e.commercial_order_id=o.id and e.event_kind='cancelled')
), last_order as (
  select distinct on (customer_relationship_id)
    customer_relationship_id,id as last_order_id,order_date as last_order_date,total_amount as last_order_amount,created_at as last_order_recorded_at
  from active_orders order by customer_relationship_id,order_date desc,created_at desc,id
)
select r.organization_id,r.organization_unit_id,r.id as external_relationship_id,r.subject_id,
  count(a.id)::integer as order_count,
  coalesce(round(sum(a.total_amount),2),0)::numeric(14,2) as gross_order_value,
  min(a.order_date) as first_order_date,max(a.order_date) as last_order_date,
  l.last_order_id,l.last_order_amount,l.last_order_recorded_at
from atlas.external_relationships r
left join active_orders a on a.customer_relationship_id=r.id
left join last_order l on l.customer_relationship_id=r.id
group by r.organization_id,r.organization_unit_id,r.id,r.subject_id,l.last_order_id,l.last_order_amount,l.last_order_recorded_at;

create or replace view atlas.v_commercial_relationship_revenue_summary_v1
with (security_invoker=true) as
select r.organization_id,r.organization_unit_id,r.id as external_relationship_id,r.subject_id,
  count(distinct p.id)::integer as payment_count,
  coalesce(round(sum(case when pe.event_kind='succeeded' then pe.amount_delta else 0 end),2),0)::numeric(14,2) as collected_amount,
  coalesce(round(abs(sum(case when pe.event_kind in ('refund','chargeback','adjustment') and pe.amount_delta<0 then pe.amount_delta else 0 end)),2),0)::numeric(14,2) as returned_amount,
  coalesce(round(sum(pe.amount_delta),2),0)::numeric(14,2) as net_collected_amount,
  min(pe.occurred_at) filter(where pe.amount_delta>0) as first_collection_at,
  max(pe.occurred_at) filter(where pe.amount_delta>0) as last_collection_at
from atlas.external_relationships r
left join atlas.commercial_payments p on p.payer_relationship_id=r.id
left join atlas.commercial_payment_events pe on pe.commercial_payment_id=p.id
group by r.organization_id,r.organization_unit_id,r.id,r.subject_id;

comment on view atlas.v_commercial_relationship_order_summary_v1 is
  'Universal relationship-level order value summary. It is not collected revenue: collection is reported separately from payment evidence.';
comment on view atlas.v_commercial_relationship_revenue_summary_v1 is
  'Universal relationship-level collected cash summary from append-only commercial payment events, including explicit returned amounts.';

-- Private-by-default canonical tables. Browser surfaces must use reviewed API membranes.
alter table atlas.external_relationships enable row level security;
alter table atlas.external_relationship_roles enable row level security;
alter table atlas.identity_subject_external_identifiers enable row level security;
alter table atlas.commercial_offerings enable row level security;
alter table atlas.commercial_offering_prices enable row level security;
alter table atlas.commercial_orders enable row level security;
alter table atlas.commercial_order_lines enable row level security;
alter table atlas.commercial_order_events enable row level security;
alter table atlas.commercial_payments enable row level security;
alter table atlas.commercial_payment_events enable row level security;
alter table atlas.commercial_source_links enable row level security;
alter table atlas.flower_commercial_order_extensions enable row level security;
alter table atlas.flower_commercial_order_line_extensions enable row level security;
alter table atlas.community_registration_commercial_offering_extensions enable row level security;
alter table atlas.community_registration_commercial_order_extensions enable row level security;
alter table atlas.community_registration_commercial_payment_extensions enable row level security;
alter table atlas.legacy_buyer_relationship_external_mappings enable row level security;

revoke all on atlas.external_relationships,atlas.external_relationship_roles,atlas.identity_subject_external_identifiers,
  atlas.commercial_offerings,atlas.commercial_offering_prices,atlas.commercial_orders,atlas.commercial_order_lines,
  atlas.commercial_order_events,atlas.commercial_payments,atlas.commercial_payment_events,atlas.commercial_source_links,
  atlas.flower_commercial_order_extensions,atlas.flower_commercial_order_line_extensions,
  atlas.community_registration_commercial_offering_extensions,atlas.community_registration_commercial_order_extensions,
  atlas.community_registration_commercial_payment_extensions,atlas.legacy_buyer_relationship_external_mappings
from public,anon,authenticated;
grant select,insert,update,delete on atlas.external_relationships,atlas.external_relationship_roles,atlas.identity_subject_external_identifiers,atlas.commercial_offerings to service_role;
grant select,insert on atlas.commercial_offering_prices,atlas.commercial_orders,atlas.commercial_order_lines,atlas.commercial_order_events,
  atlas.commercial_payments,atlas.commercial_payment_events,atlas.commercial_source_links,
  atlas.flower_commercial_order_extensions,atlas.flower_commercial_order_line_extensions,
  atlas.community_registration_commercial_offering_extensions,atlas.community_registration_commercial_order_extensions,
  atlas.community_registration_commercial_payment_extensions,atlas.legacy_buyer_relationship_external_mappings to service_role;
grant select on atlas.v_commercial_relationship_order_summary_v1,atlas.v_commercial_relationship_revenue_summary_v1 to service_role;

revoke all on function atlas.guard_external_subject_organization_v1() from public,anon,authenticated;
revoke all on function atlas.guard_commercial_party_organization_v1() from public,anon,authenticated;
revoke all on function atlas.prevent_universal_commercial_truth_mutation_v1() from public,anon,authenticated;
grant execute on function atlas.guard_external_subject_organization_v1(),atlas.guard_commercial_party_organization_v1(),atlas.prevent_universal_commercial_truth_mutation_v1() to service_role;

commit;

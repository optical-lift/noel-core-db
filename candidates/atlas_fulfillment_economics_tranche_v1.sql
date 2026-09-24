-- Atlas Fulfillment Economics Tranche v1 — disposable validation bundle
-- Candidate-only bundle. Not a canonical release migration.
-- Applies the current external-supply, qualification, neutral-composition, and price-evaluation candidates atomically.
-- Intended for the no-cost production-schema-clone harness / disposable local database only.

begin;

-- ============================================================================
-- BEGIN candidates/atlas_external_supply_offer_v1.sql
-- ============================================================================
create table if not exists atlas.external_supply_offerings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  supplier_relationship_id uuid not null
    references atlas.external_relationships(id) on delete restrict,
  stable_key text not null,
  source_item_key text,
  source_label text not null,
  offering_kind text not null default 'item',
  source_unit text,
  status text not null default 'active'
    check (status in ('active','inactive','retired')),
  specification jsonb not null default '{}'::jsonb
    check (jsonb_typeof(specification)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_supply_offerings_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict,
  constraint external_supply_offerings_stable_key_nonblank
    check (btrim(stable_key)<>''),
  constraint external_supply_offerings_source_item_key_nonblank
    check (source_item_key is null or btrim(source_item_key)<>''),
  constraint external_supply_offerings_source_label_nonblank
    check (btrim(source_label)<>''),
  constraint external_supply_offerings_kind_nonblank
    check (btrim(offering_kind)<>''),
  constraint external_supply_offerings_source_unit_nonblank
    check (source_unit is null or btrim(source_unit)<>'')
);

create unique index if not exists external_supply_offerings_org_key_uq
  on atlas.external_supply_offerings(
    organization_id,supplier_relationship_id,stable_key
  )
  where organization_unit_id is null;

create unique index if not exists external_supply_offerings_unit_key_uq
  on atlas.external_supply_offerings(
    organization_id,organization_unit_id,supplier_relationship_id,stable_key
  )
  where organization_unit_id is not null;

create unique index if not exists external_supply_offerings_org_source_item_uq
  on atlas.external_supply_offerings(
    organization_id,supplier_relationship_id,source_item_key
  )
  where organization_unit_id is null and source_item_key is not null;

create unique index if not exists external_supply_offerings_unit_source_item_uq
  on atlas.external_supply_offerings(
    organization_id,organization_unit_id,supplier_relationship_id,source_item_key
  )
  where organization_unit_id is not null and source_item_key is not null;

create index if not exists external_supply_offerings_supplier_idx
  on atlas.external_supply_offerings(
    supplier_relationship_id,status,source_label,id
  );

comment on table atlas.external_supply_offerings is
'Durable organization-scoped identity for a thing/service an external supplier offers this organization. It is not the organization''s sell-side Commercial Offering, inventory, purchase authority, Spend, or customer price.';


create table if not exists atlas.external_supply_offer_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  external_supply_offering_id uuid not null
    references atlas.external_supply_offerings(id) on delete restrict,
  observation_key text not null,
  observed_at timestamptz not null,
  effective_from date,
  effective_until date,
  price_amount numeric(14,4) not null
    check (price_amount>=0),
  currency text
    check (currency is null or currency ~ '^[A-Z]{3}$'),
  price_basis_state text not null default 'unknown'
    check (price_basis_state in ('source_explicit','confirmed','unknown')),
  price_quantity numeric(14,3)
    check (price_quantity is null or price_quantity>0),
  price_unit text,
  pack_quantity numeric(14,3)
    check (pack_quantity is null or pack_quantity>0),
  pack_unit text,
  minimum_order_quantity numeric(14,3)
    check (minimum_order_quantity is null or minimum_order_quantity>0),
  minimum_order_unit text,
  lead_time_value numeric(14,3)
    check (lead_time_value is null or lead_time_value>=0),
  lead_time_unit text,
  availability_state text not null default 'unknown'
    check (availability_state in ('unknown','available','limited','unavailable')),
  terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(terms)='object'),
  source_context jsonb not null default '{}'::jsonb
    check (jsonb_typeof(source_context)='object'),
  source_kind text not null
    check (source_kind in (
      'supplier_price_list',
      'supplier_quote',
      'supplier_portal',
      'supplier_message',
      'authorized_human_report',
      'imported_record'
    )),
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  observation_sha256 text not null
    check (observation_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_supply_offer_observations_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict,
  constraint external_supply_offer_observations_key_nonblank
    check (btrim(observation_key)<>''),
  constraint external_supply_offer_observations_price_pair
    check (
      (price_quantity is null and price_unit is null)
      or
      (
        price_quantity is not null
        and price_unit is not null
        and btrim(price_unit)<>''
      )
    ),
  constraint external_supply_offer_observations_price_basis
    check (
      (
        price_basis_state='unknown'
        and price_quantity is null
        and price_unit is null
      )
      or
      (
        price_basis_state in ('source_explicit','confirmed')
        and price_quantity is not null
        and price_unit is not null
      )
    ),
  constraint external_supply_offer_observations_pack_pair
    check (
      (pack_quantity is null and pack_unit is null)
      or
      (
        pack_quantity is not null
        and pack_unit is not null
        and btrim(pack_unit)<>''
      )
    ),
  constraint external_supply_offer_observations_minimum_pair
    check (
      (minimum_order_quantity is null and minimum_order_unit is null)
      or
      (
        minimum_order_quantity is not null
        and minimum_order_unit is not null
        and btrim(minimum_order_unit)<>''
      )
    ),
  constraint external_supply_offer_observations_lead_time_pair
    check (
      (lead_time_value is null and lead_time_unit is null)
      or
      (
        lead_time_value is not null
        and lead_time_unit is not null
        and btrim(lead_time_unit)<>''
      )
    ),
  constraint external_supply_offer_observations_window
    check (
      effective_until is null
      or effective_from is null
      or effective_until>=effective_from
    ),
  constraint external_supply_offer_observations_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  unique(external_supply_offering_id,observation_key)
);

create index if not exists external_supply_offer_observations_current_idx
  on atlas.external_supply_offer_observations(
    external_supply_offering_id,effective_from,effective_until,observed_at desc,id
  );

comment on table atlas.external_supply_offer_observations is
'Append-only source-backed commercial terms observed from an external supplier. Unknown currency, price denominator, freight, and availability remain unknown; an observation creates no purchase, Spend, owned inventory, or sell-side price.';


create or replace function atlas.guard_external_supply_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relationship atlas.external_relationships%rowtype;
  v_offering atlas.external_supply_offerings%rowtype;
begin
  if tg_table_name='external_supply_offerings' then
    select * into v_relationship
    from atlas.external_relationships r
    where r.id=new.supplier_relationship_id;

    if v_relationship.id is null
       or v_relationship.organization_id is distinct from new.organization_id
       or v_relationship.organization_unit_id is distinct from new.organization_unit_id then
      raise exception 'External supply offering must share the supplier relationship organization/unit scope.'
        using errcode='23514';
    end if;

    if not exists(
      select 1
      from atlas.external_relationship_roles rr
      where rr.external_relationship_id=new.supplier_relationship_id
        and rr.role_key='supplier'
        and rr.role_state='active'
    ) then
      raise exception 'External supply offering requires an active supplier relationship role.'
        using errcode='23514';
    end if;

    new.stable_key:=btrim(new.stable_key);
    new.source_item_key:=nullif(btrim(new.source_item_key),'');
    new.source_label:=btrim(new.source_label);
    new.offering_kind:=lower(btrim(new.offering_kind));
    new.source_unit:=nullif(lower(btrim(new.source_unit)),'');
    new.updated_at:=now();
    return new;
  end if;

  select * into v_offering
  from atlas.external_supply_offerings o
  where o.id=new.external_supply_offering_id;

  if v_offering.id is null
     or v_offering.organization_id is distinct from new.organization_id
     or v_offering.organization_unit_id is distinct from new.organization_unit_id then
    raise exception 'Supply offer observation must share the external supply offering organization/unit scope.'
      using errcode='23514';
  end if;

  if new.connected_source_observation_id is not null
     and not exists(
       select 1
       from atlas.connected_source_observations cso
       join atlas.connected_sources cs on cs.id=cso.connected_source_id
       where cso.id=new.connected_source_observation_id
         and cs.custodian_organization_id=new.organization_id
         and (
           cs.custodian_organization_unit_id is null
           or cs.custodian_organization_unit_id is not distinct from new.organization_unit_id
         )
     ) then
    raise exception 'Connected source observation must belong to the same organization/unit scope.'
      using errcode='23514';
  end if;

  new.observation_key:=btrim(new.observation_key);
  new.currency:=case
    when new.currency is null then null
    else nullif(upper(btrim(new.currency)),'')
  end;
  new.price_unit:=nullif(lower(btrim(new.price_unit)),'');
  new.pack_unit:=nullif(lower(btrim(new.pack_unit)),'');
  new.minimum_order_unit:=nullif(lower(btrim(new.minimum_order_unit)),'');
  new.lead_time_unit:=nullif(lower(btrim(new.lead_time_unit)),'');
  new.source_ref:=nullif(btrim(new.source_ref),'');
  return new;
end;
$function$;

drop trigger if exists external_supply_offerings_scope_guard_v1
  on atlas.external_supply_offerings;
create trigger external_supply_offerings_scope_guard_v1
before insert or update on atlas.external_supply_offerings
for each row execute function atlas.guard_external_supply_scope_v1();

drop trigger if exists external_supply_offer_observations_scope_guard_v1
  on atlas.external_supply_offer_observations;
create trigger external_supply_offer_observations_scope_guard_v1
before insert on atlas.external_supply_offer_observations
for each row execute function atlas.guard_external_supply_scope_v1();


create or replace function atlas.prevent_external_supply_observation_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'External supply offer observations are append-only; record a later observation instead.'
    using errcode='55000';
end;
$function$;

drop trigger if exists external_supply_offer_observations_append_only_v1
  on atlas.external_supply_offer_observations;
create trigger external_supply_offer_observations_append_only_v1
before update or delete on atlas.external_supply_offer_observations
for each row execute function atlas.prevent_external_supply_observation_mutation_v1();


create or replace function atlas.ensure_external_supply_offering_service_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_supplier_relationship_id uuid,
  p_stable_key text,
  p_source_item_key text,
  p_source_label text,
  p_offering_kind text default 'item',
  p_source_unit text default null,
  p_specification jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_existing atlas.external_supply_offerings%rowtype;
  v_id uuid;
  v_key text:=btrim(coalesce(p_stable_key,''));
  v_label text:=btrim(coalesce(p_source_label,''));
  v_kind text:=lower(btrim(coalesce(p_offering_kind,'item')));
  v_item_key text:=nullif(btrim(p_source_item_key),'');
begin
  if v_key='' or v_label='' or v_kind='' then
    raise exception 'Stable key, source label, and offering kind are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_specification,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Specification and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  select * into v_existing
  from atlas.external_supply_offerings o
  where o.organization_id=p_organization_id
    and o.organization_unit_id is not distinct from p_organization_unit_id
    and o.supplier_relationship_id=p_supplier_relationship_id
    and o.stable_key=v_key;

  if v_existing.id is not null then
    if v_item_key is not null
       and v_existing.source_item_key is not null
       and v_existing.source_item_key is distinct from v_item_key then
      raise exception 'External supply offering stable key already belongs to a different source item key.'
        using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.external_supply_offerings(
    organization_id,organization_unit_id,supplier_relationship_id,
    stable_key,source_item_key,source_label,offering_kind,source_unit,
    specification,metadata
  ) values (
    p_organization_id,p_organization_unit_id,p_supplier_relationship_id,
    v_key,v_item_key,v_label,v_kind,
    nullif(lower(btrim(p_source_unit)),''),
    coalesce(p_specification,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_id;

  return v_id;
end;
$function$;


create or replace function atlas.record_external_supply_offer_observation_service_v1(
  p_external_supply_offering_id uuid,
  p_observation_key text,
  p_observed_at timestamptz,
  p_effective_from date default null,
  p_effective_until date default null,
  p_price_amount numeric default null,
  p_currency text default null,
  p_price_basis_state text default 'unknown',
  p_price_quantity numeric default null,
  p_price_unit text default null,
  p_pack_quantity numeric default null,
  p_pack_unit text default null,
  p_minimum_order_quantity numeric default null,
  p_minimum_order_unit text default null,
  p_lead_time_value numeric default null,
  p_lead_time_unit text default null,
  p_availability_state text default 'unknown',
  p_terms jsonb default '{}'::jsonb,
  p_source_context jsonb default '{}'::jsonb,
  p_source_kind text default 'supplier_price_list',
  p_source_ref text default null,
  p_evidence_record_id uuid default null,
  p_connected_source_observation_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_offering atlas.external_supply_offerings%rowtype;
  v_existing atlas.external_supply_offer_observations%rowtype;
  v_key text:=btrim(coalesce(p_observation_key,''));
  v_basis text:=lower(btrim(coalesce(p_price_basis_state,'unknown')));
  v_availability text:=lower(btrim(coalesce(p_availability_state,'unknown')));
  v_source_kind text:=lower(btrim(coalesce(p_source_kind,'supplier_price_list')));
  v_currency text:=case
    when p_currency is null then null
    else nullif(upper(btrim(p_currency)),'')
  end;
  v_hash text;
  v_id uuid;
begin
  select * into v_offering
  from atlas.external_supply_offerings
  where id=p_external_supply_offering_id;

  if v_offering.id is null then
    raise exception 'External supply offering not found.'
      using errcode='P0002';
  end if;

  if v_key='' or p_observed_at is null or p_price_amount is null then
    raise exception 'Observation key, observed time, and price amount are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_terms,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_source_context,'{}'::jsonb))<>'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Terms, source context, and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  v_hash:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'externalSupplyOfferingId',p_external_supply_offering_id,
          'observedAt',p_observed_at,
          'effectiveFrom',p_effective_from,
          'effectiveUntil',p_effective_until,
          'priceAmount',p_price_amount,
          'currency',v_currency,
          'priceBasisState',v_basis,
          'priceQuantity',p_price_quantity,
          'priceUnit',nullif(lower(btrim(p_price_unit)),''),
          'packQuantity',p_pack_quantity,
          'packUnit',nullif(lower(btrim(p_pack_unit)),''),
          'minimumOrderQuantity',p_minimum_order_quantity,
          'minimumOrderUnit',nullif(lower(btrim(p_minimum_order_unit)),''),
          'leadTimeValue',p_lead_time_value,
          'leadTimeUnit',nullif(lower(btrim(p_lead_time_unit)),''),
          'availabilityState',v_availability,
          'terms',coalesce(p_terms,'{}'::jsonb),
          'sourceContext',coalesce(p_source_context,'{}'::jsonb),
          'sourceKind',v_source_kind,
          'sourceRef',nullif(btrim(p_source_ref),''),
          'evidenceRecordId',p_evidence_record_id,
          'connectedSourceObservationId',p_connected_source_observation_id,
          'metadata',coalesce(p_metadata,'{}'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into v_existing
  from atlas.external_supply_offer_observations o
  where o.external_supply_offering_id=p_external_supply_offering_id
    and o.observation_key=v_key;

  if v_existing.id is not null then
    if v_existing.observation_sha256 is distinct from v_hash then
      raise exception 'Observation key already exists with different source terms.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','record_external_supply_offer_observation_service_v1',
      'externalSupplyOfferObservationId',v_existing.id,
      'created',false,
      'observationSha256',v_existing.observation_sha256
    );
  end if;

  insert into atlas.external_supply_offer_observations(
    organization_id,organization_unit_id,external_supply_offering_id,
    observation_key,observed_at,effective_from,effective_until,
    price_amount,currency,price_basis_state,price_quantity,price_unit,
    pack_quantity,pack_unit,minimum_order_quantity,minimum_order_unit,
    lead_time_value,lead_time_unit,availability_state,
    terms,source_context,source_kind,source_ref,evidence_record_id,
    connected_source_observation_id,observation_sha256,metadata
  ) values (
    v_offering.organization_id,v_offering.organization_unit_id,v_offering.id,
    v_key,p_observed_at,p_effective_from,p_effective_until,
    p_price_amount,v_currency,v_basis,p_price_quantity,
    nullif(lower(btrim(p_price_unit)),''),
    p_pack_quantity,nullif(lower(btrim(p_pack_unit)),''),
    p_minimum_order_quantity,nullif(lower(btrim(p_minimum_order_unit)),''),
    p_lead_time_value,nullif(lower(btrim(p_lead_time_unit)),''),
    v_availability,
    coalesce(p_terms,'{}'::jsonb),
    coalesce(p_source_context,'{}'::jsonb),
    v_source_kind,
    nullif(btrim(p_source_ref),''),
    p_evidence_record_id,
    p_connected_source_observation_id,
    v_hash,
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning id into v_id;

  return jsonb_build_object(
    'contractVersion','record_external_supply_offer_observation_service_v1',
    'externalSupplyOfferObservationId',v_id,
    'created',true,
    'observationSha256',v_hash,
    'truthBoundary',jsonb_build_object(
      'createsPurchase',false,
      'createsSpend',false,
      'createsInventory',false,
      'createsSellSidePrice',false,
      'availabilityDefaultsUnknown',true
    )
  );
end;
$function$;


create or replace function atlas.external_supply_offers_for_supplier_service_v1(
  p_supplier_relationship_id uuid,
  p_at_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relationship atlas.external_relationships%rowtype;
  v_items jsonb;
  v_date date:=coalesce(p_at_date,current_date);
begin
  select * into v_relationship
  from atlas.external_relationships
  where id=p_supplier_relationship_id;

  if v_relationship.id is null then
    raise exception 'Supplier relationship not found.'
      using errcode='P0002';
  end if;

  if not exists(
    select 1
    from atlas.external_relationship_roles rr
    where rr.external_relationship_id=p_supplier_relationship_id
      and rr.role_key='supplier'
  ) then
    raise exception 'Relationship does not carry supplier meaning.'
      using errcode='23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalSupplyOfferingId',o.id,
        'stableKey',o.stable_key,
        'sourceItemKey',o.source_item_key,
        'sourceLabel',o.source_label,
        'offeringKind',o.offering_kind,
        'sourceUnit',o.source_unit,
        'specification',o.specification,
        'status',o.status,
        'currentObservation',
        case when x.id is null then null else jsonb_build_object(
          'externalSupplyOfferObservationId',x.id,
          'observationKey',x.observation_key,
          'observedAt',x.observed_at,
          'effectiveFrom',x.effective_from,
          'effectiveUntil',x.effective_until,
          'priceAmount',x.price_amount,
          'currency',x.currency,
          'priceBasisState',x.price_basis_state,
          'priceQuantity',x.price_quantity,
          'priceUnit',x.price_unit,
          'packQuantity',x.pack_quantity,
          'packUnit',x.pack_unit,
          'minimumOrderQuantity',x.minimum_order_quantity,
          'minimumOrderUnit',x.minimum_order_unit,
          'leadTimeValue',x.lead_time_value,
          'leadTimeUnit',x.lead_time_unit,
          'availabilityState',x.availability_state,
          'terms',x.terms,
          'sourceContext',x.source_context,
          'sourceKind',x.source_kind,
          'sourceRef',x.source_ref,
          'evidenceRecordId',x.evidence_record_id,
          'connectedSourceObservationId',x.connected_source_observation_id
        ) end
      )
      order by o.source_label,o.id
    ),
    '[]'::jsonb
  )
  into v_items
  from atlas.external_supply_offerings o
  left join lateral (
    select obs.*
    from atlas.external_supply_offer_observations obs
    where obs.external_supply_offering_id=o.id
      and (obs.effective_from is null or obs.effective_from<=v_date)
      and (obs.effective_until is null or obs.effective_until>=v_date)
    order by obs.observed_at desc,obs.created_at desc,obs.id desc
    limit 1
  ) x on true
  where o.supplier_relationship_id=p_supplier_relationship_id
    and o.status='active';

  return jsonb_build_object(
    'contractVersion','external_supply_offers_for_supplier_service_v1',
    'supplierRelationshipId',p_supplier_relationship_id,
    'organizationId',v_relationship.organization_id,
    'organizationUnitId',v_relationship.organization_unit_id,
    'atDate',v_date,
    'offers',v_items,
    'truthBoundary',jsonb_build_object(
      'sourceTermsOnly',true,
      'doesNotAuthorizePurchase',true,
      'doesNotAssertInventory',true,
      'doesNotCreateCustomerPrice',true
    )
  );
end;
$function$;


alter table atlas.external_supply_offerings enable row level security;
alter table atlas.external_supply_offer_observations enable row level security;

revoke all on atlas.external_supply_offerings
  from public,anon,authenticated,service_role;
revoke all on atlas.external_supply_offer_observations
  from public,anon,authenticated,service_role;

grant select,insert,update on atlas.external_supply_offerings
  to service_role;
grant select,insert on atlas.external_supply_offer_observations
  to service_role;

revoke all on function atlas.ensure_external_supply_offering_service_v1(
  uuid,uuid,uuid,text,text,text,text,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ensure_external_supply_offering_service_v1(
  uuid,uuid,uuid,text,text,text,text,text,jsonb,jsonb
) to service_role;

revoke all on function atlas.record_external_supply_offer_observation_service_v1(
  uuid,text,timestamptz,date,date,numeric,text,text,numeric,text,numeric,text,
  numeric,text,numeric,text,text,jsonb,jsonb,text,text,uuid,uuid,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_external_supply_offer_observation_service_v1(
  uuid,text,timestamptz,date,date,numeric,text,text,numeric,text,numeric,text,
  numeric,text,numeric,text,text,jsonb,jsonb,text,text,uuid,uuid,jsonb
) to service_role;

revoke all on function atlas.external_supply_offers_for_supplier_service_v1(uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.external_supply_offers_for_supplier_service_v1(uuid,date)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'external_supply_offer',
  'commercial_supply',
  'What source-backed commercial terms has a resolved external supplier offered this organization for an acquirable thing or service?',
  'external_supply_offerings + external_supply_offer_observations',
  'canonical',
  array[
    'atlas.external_supply_offerings',
    'atlas.external_supply_offer_observations'
  ],
  array[
    'atlas.ensure_external_supply_offering_service_v1',
    'atlas.record_external_supply_offer_observation_service_v1',
    'atlas.external_supply_offers_for_supplier_service_v1'
  ],
  array[
    'atlas.external_relationships',
    'atlas.external_relationship_roles',
    'atlas.evidence_records',
    'atlas.connected_sources',
    'atlas.connected_source_observations'
  ],
  array[]::text[],
  array[
    'atlas.commercial_offerings',
    'atlas.commercial_offering_prices',
    'atlas.organization_spend_occurrences'
  ],
  'External supplier terms remain source-side commercial truth. Sell-side Commercial Offering/price, actual Spend, inventory, procurement authority, and customer offer evidence retain their separate owners.',
  'Provides the missing source-side commercial observation needed for fulfillment economics without converting supplier terms into purchase, inventory, Spend, or sell-side price truth.',
  now()
)
on conflict(authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.ensure_external_supply_offering_service_v1(uuid,uuid,uuid,text,text,text,text,text,jsonb,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_supply_offer_v1","purpose":"Ensure durable supplier-side offering identity without creating purchase/inventory/sell-side price truth.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_supply_offer_observation_service_v1(uuid,text,timestamptz,date,date,numeric,text,text,numeric,text,numeric,text,numeric,text,numeric,text,text,jsonb,jsonb,text,text,uuid,uuid,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_supply_offer_v1","purpose":"Record one append-only source-backed supplier commercial observation.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_supply_offers_for_supplier_service_v1(uuid,date)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_supply_offer_v1","purpose":"Read current source-side commercial observations for one resolved supplier relationship.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();
-- ============================================================================
-- END candidates/atlas_external_supply_offer_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_fulfillment_candidate_qualification_v1.sql
-- ============================================================================
create or replace function atlas.requirement_set_evaluate_v2(
  p_requirements jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_node jsonb;
  v_key text;
  v_state text;
  v_required boolean;
  v_keys text[]:='{}'::text[];

  v_total integer:=0;
  v_required_total integer:=0;
  v_optional_total integer:=0;

  v_required_satisfied integer:=0;
  v_required_unsatisfied integer:=0;
  v_required_unresolved integer:=0;

  v_optional_satisfied integer:=0;
  v_optional_unsatisfied integer:=0;
  v_optional_unresolved integer:=0;

  v_result_state text;
begin
  if p_requirements is null
     or jsonb_typeof(p_requirements)<>'array' then
    raise exception 'Requirement set must be a JSON array.'
      using errcode='22023';
  end if;

  if jsonb_array_length(p_requirements)=0 then
    raise exception 'Requirement set must contain at least one requirement node.'
      using errcode='22023';
  end if;

  for v_node in
    select value
    from jsonb_array_elements(p_requirements)
  loop
    if jsonb_typeof(v_node)<>'object' then
      raise exception 'Each requirement node must be a JSON object.'
        using errcode='22023';
    end if;

    v_key:=nullif(btrim(coalesce(v_node->>'requirementKey','')),'');
    if v_key is null then
      raise exception 'Each requirement node requires requirementKey.'
        using errcode='22023';
    end if;

    if v_key=any(v_keys) then
      raise exception 'Requirement key % appears more than once.',v_key
        using errcode='22023';
    end if;
    v_keys:=array_append(v_keys,v_key);

    v_state:=lower(btrim(coalesce(v_node->>'state','')));
    if v_state not in ('satisfied','unsatisfied','unresolved') then
      raise exception 'Requirement % requires state satisfied, unsatisfied, or unresolved.',v_key
        using errcode='22023';
    end if;

    if v_node ? 'required' then
      if jsonb_typeof(v_node->'required')<>'boolean' then
        raise exception 'Requirement % required must be boolean.',v_key
          using errcode='22023';
      end if;
      v_required:=(v_node->>'required')::boolean;
    else
      v_required:=true;
    end if;

    if v_node ? 'evidence'
       and jsonb_typeof(v_node->'evidence')<>'array' then
      raise exception 'Requirement % evidence must be an array.',v_key
        using errcode='22023';
    end if;

    if v_node ? 'details'
       and jsonb_typeof(v_node->'details')<>'object' then
      raise exception 'Requirement % details must be an object.',v_key
        using errcode='22023';
    end if;

    v_total:=v_total+1;

    if v_required then
      v_required_total:=v_required_total+1;
      case v_state
        when 'satisfied' then v_required_satisfied:=v_required_satisfied+1;
        when 'unsatisfied' then v_required_unsatisfied:=v_required_unsatisfied+1;
        when 'unresolved' then v_required_unresolved:=v_required_unresolved+1;
      end case;
    else
      v_optional_total:=v_optional_total+1;
      case v_state
        when 'satisfied' then v_optional_satisfied:=v_optional_satisfied+1;
        when 'unsatisfied' then v_optional_unsatisfied:=v_optional_unsatisfied+1;
        when 'unresolved' then v_optional_unresolved:=v_optional_unresolved+1;
      end case;
    end if;
  end loop;

  if v_required_total=0 then
    raise exception 'Requirement set must contain at least one required node.'
      using errcode='22023';
  end if;

  v_result_state:=case
    when v_required_unsatisfied>0 then 'unsatisfied'
    when v_required_unresolved>0 then 'unresolved'
    else 'satisfied'
  end;

  return jsonb_build_object(
    'contractVersion','requirement_set_evaluation_v2',
    'aggregation','all_required_three_state',
    'state',v_result_state,
    'satisfied',(v_result_state='satisfied'),
    'requirementCount',v_total,
    'requiredCount',v_required_total,
    'optionalCount',v_optional_total,
    'requiredSatisfiedCount',v_required_satisfied,
    'requiredUnsatisfiedCount',v_required_unsatisfied,
    'requiredUnresolvedCount',v_required_unresolved,
    'optionalSatisfiedCount',v_optional_satisfied,
    'optionalUnsatisfiedCount',v_optional_unsatisfied,
    'optionalUnresolvedCount',v_optional_unresolved,
    'requirements',p_requirements,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'evidenceRemainsDomainOwned',true,
      'evaluationDoesNotCreateBoundaryEvent',true,
      'evaluationDoesNotExecuteEffects',true,
      'unresolvedRemainsUnresolved',true,
      'allRequiredNodesMustBeExplicit',true
    )
  );
end;
$function$;


create or replace function atlas.fulfillment_candidate_qualification_v1(
  p_requirement_ref jsonb,
  p_candidate_ref jsonb,
  p_requirements jsonb,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_evaluation jsonb;
  v_eval_state text;
  v_qualification_state text;
begin
  if p_requirement_ref is null
     or jsonb_typeof(p_requirement_ref)<>'object' then
    raise exception 'Requirement ref must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_requirement_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(p_requirement_ref->>'sourceRef','')),'') is null then
    raise exception 'Requirement ref requires sourceDomain and sourceRef.'
      using errcode='22023';
  end if;

  if p_candidate_ref is null
     or jsonb_typeof(p_candidate_ref)<>'object' then
    raise exception 'Candidate ref must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_candidate_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(p_candidate_ref->>'sourceRef','')),'') is null then
    raise exception 'Candidate ref requires sourceDomain and sourceRef.'
      using errcode='22023';
  end if;

  if p_context is null
     or jsonb_typeof(p_context)<>'object' then
    raise exception 'Qualification context must be a JSON object.'
      using errcode='22023';
  end if;

  v_evaluation:=atlas.requirement_set_evaluate_v2(p_requirements);
  v_eval_state:=v_evaluation->>'state';

  v_qualification_state:=case v_eval_state
    when 'satisfied' then 'qualified'
    when 'unsatisfied' then 'incompatible'
    else 'unresolved'
  end;

  return jsonb_build_object(
    'contractVersion','fulfillment_candidate_qualification_v1',
    'requirementRef',p_requirement_ref,
    'candidateRef',p_candidate_ref,
    'qualificationState',v_qualification_state,
    'mayEnterPlanning',(v_qualification_state='qualified'),
    'evaluation',v_evaluation,
    'context',p_context,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'requirementTruthRemainsSourceOwned',true,
      'candidateTruthRemainsSourceOwned',true,
      'qualificationIsDirectional',true,
      'qualificationDoesNotAssertIdentity',true,
      'qualificationDoesNotRankCandidates',true,
      'qualificationDoesNotReserveAvailability',true,
      'qualificationDoesNotCreateCoverage',true,
      'qualificationDoesNotAuthorizePurchase',true,
      'qualificationDoesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.requirement_set_evaluate_v2(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.requirement_set_evaluate_v2(jsonb)
  to service_role;

revoke all on function atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.requirement_set_evaluate_v2(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_fulfillment_candidate_qualification_v1","purpose":"Read-only three-state aggregation of explicit requirement nodes; evidence remains domain-owned.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.fulfillment_candidate_qualification_v1(jsonb,jsonb,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_fulfillment_candidate_qualification_v1","purpose":"Read-only directional candidate-to-requirement qualification wrapper for fulfillment planning.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();
-- ============================================================================
-- END candidates/atlas_fulfillment_candidate_qualification_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_neutral_fulfillment_composition_v1.sql
-- ============================================================================
create or replace function atlas.fulfillment_composition_validate_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_requirement jsonb;
  v_requirement_ref jsonb;
  v_allocation jsonb;
  v_cost jsonb;
  v_excess jsonb;
  v_candidate_ref jsonb;
  v_keys text[]:='{}'::text[];
  v_cost_keys text[];
  v_key text;
  v_cost_key text;
  v_state text;
  v_required boolean;
  v_req_qty numeric;
  v_req_unit text;
  v_out_qty numeric;
  v_out_unit text;
  v_source_qty numeric;
  v_source_unit text;
  v_amount numeric;
  v_currency text;
  v_allocation_count integer:=0;
  v_cost_count integer:=0;
  v_known_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_output_total numeric:=0;
begin
  if p_packet is null or jsonb_typeof(p_packet)<>'object' then
    return jsonb_build_object(
      'contractVersion','fulfillment_composition_validation_v1',
      'validationState','rejected',
      'violations',jsonb_build_array(jsonb_build_object(
        'key','packet_not_object',
        'message','Fulfillment composition packet must be a JSON object.'
      )),
      'warnings','[]'::jsonb
    );
  end if;

  if p_packet->>'contractVersion'<>'neutral_fulfillment_composition_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version',
      'message','contractVersion must be neutral_fulfillment_composition_v1.'
    ));
  end if;

  v_requirement_ref:=p_packet->'requirementRef';
  if v_requirement_ref is null
     or jsonb_typeof(v_requirement_ref)<>'object'
     or nullif(btrim(coalesce(v_requirement_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(v_requirement_ref->>'sourceRef','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement_ref',
      'message','requirementRef requires sourceDomain and sourceRef.'
    ));
  end if;

  if nullif(btrim(coalesce(p_packet->>'planKey','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_plan_key',
      'message','planKey is required.'
    ));
  end if;

  v_requirement:=p_packet->'requirement';
  if v_requirement is null or jsonb_typeof(v_requirement)<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement',
      'message','requirement must be a JSON object.'
    ));
  else
    if jsonb_typeof(v_requirement->'quantity')<>'number' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_quantity',
        'message','requirement.quantity must be numeric.'
      ));
    else
      v_req_qty:=(v_requirement->>'quantity')::numeric;
      if v_req_qty<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_requirement_quantity',
          'message','requirement.quantity must be greater than zero.'
        ));
      end if;
    end if;

    v_req_unit:=nullif(lower(btrim(coalesce(v_requirement->>'unit',''))),'');
    if v_req_unit is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_unit',
        'message','requirement.unit is required.'
      ));
    end if;
  end if;

  if p_packet ? 'constraints'
     and jsonb_typeof(p_packet->'constraints')<>'array' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_constraints',
      'message','constraints must be an array when present.'
    ));
  end if;

  if p_packet ? 'unresolved'
     and jsonb_typeof(p_packet->'unresolved')<>'array' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_unresolved',
      'message','unresolved must be an array when present.'
    ));
  end if;

  if p_packet ? 'metadata'
     and jsonb_typeof(p_packet->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata',
      'message','metadata must be an object when present.'
    ));
  end if;

  if jsonb_typeof(p_packet->'allocations')<>'array'
     or jsonb_array_length(coalesce(p_packet->'allocations','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_allocations',
      'message','allocations must be a non-empty array.'
    ));
  else
    for v_allocation in
      select value from jsonb_array_elements(p_packet->'allocations')
    loop
      v_allocation_count:=v_allocation_count+1;

      if jsonb_typeof(v_allocation)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocation_not_object',
          'allocationIndex',v_allocation_count
        ));
        continue;
      end if;

      v_key:=nullif(btrim(coalesce(v_allocation->>'allocationKey','')),'');
      if v_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','missing_allocation_key',
          'allocationIndex',v_allocation_count
        ));
      elsif v_key=any(v_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_allocation_key',
          'allocationKey',v_key
        ));
      else
        v_keys:=array_append(v_keys,v_key);
      end if;

      v_candidate_ref:=v_allocation->'candidateRef';
      if v_candidate_ref is null
         or jsonb_typeof(v_candidate_ref)<>'object'
         or nullif(btrim(coalesce(v_candidate_ref->>'sourceDomain','')),'') is null
         or nullif(btrim(coalesce(v_candidate_ref->>'sourceRef','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_candidate_ref',
          'allocationKey',v_key
        ));
      end if;

      if lower(btrim(coalesce(v_allocation->>'qualificationState','')))<>'qualified' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','candidate_not_qualified',
          'allocationKey',v_key,
          'qualificationState',v_allocation->>'qualificationState'
        ));
      end if;

      if jsonb_typeof(v_allocation->'outputQuantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_quantity',
          'allocationKey',v_key
        ));
      else
        v_out_qty:=(v_allocation->>'outputQuantity')::numeric;
        if v_out_qty<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_output_quantity',
            'allocationKey',v_key,
            'message','outputQuantity must be greater than zero.'
          ));
        else
          v_output_total:=v_output_total+v_out_qty;
        end if;
      end if;

      v_out_unit:=nullif(lower(btrim(coalesce(v_allocation->>'outputUnit',''))),'');
      if v_out_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_unit',
          'allocationKey',v_key
        ));
      elsif v_req_unit is not null and v_out_unit<>v_req_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_unit_mismatch',
          'allocationKey',v_key,
          'requirementUnit',v_req_unit,
          'outputUnit',v_out_unit,
          'message','V1 requires allocation outputUnit to equal requirement.unit; conversion must be explicit upstream.'
        ));
      end if;

      if (v_allocation ? 'sourceQuantity') or (v_allocation ? 'sourceUnit') then
        if jsonb_typeof(v_allocation->'sourceQuantity')<>'number' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_quantity',
            'allocationKey',v_key
          ));
        else
          v_source_qty:=(v_allocation->>'sourceQuantity')::numeric;
          if v_source_qty<=0 then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_source_quantity',
              'allocationKey',v_key
            ));
          end if;
        end if;

        v_source_unit:=nullif(lower(btrim(coalesce(v_allocation->>'sourceUnit',''))),'');
        if v_source_unit is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_unit',
            'allocationKey',v_key
          ));
        end if;
      end if;

      if v_allocation ? 'facts'
         and jsonb_typeof(v_allocation->'facts')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_allocation_facts',
          'allocationKey',v_key
        ));
      end if;

      if v_allocation ? 'excess' then
        v_excess:=v_allocation->'excess';
        if jsonb_typeof(v_excess)<>'object'
           or jsonb_typeof(v_excess->'quantity')<>'number'
           or (v_excess->>'quantity')::numeric<0
           or nullif(lower(btrim(coalesce(v_excess->>'unit',''))),'') is null
           or nullif(btrim(coalesce(v_excess->>'dispositionState','')),'') is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_excess',
            'allocationKey',v_key,
            'message','excess requires nonnegative quantity, unit, and dispositionState.'
          ));
        end if;
      end if;

      v_cost_keys:='{}'::text[];
      if v_allocation ? 'costComponents' then
        if jsonb_typeof(v_allocation->'costComponents')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_components',
            'allocationKey',v_key
          ));
        else
          for v_cost in
            select value from jsonb_array_elements(v_allocation->'costComponents')
          loop
            v_cost_count:=v_cost_count+1;
            if jsonb_typeof(v_cost)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','cost_component_not_object',
                'allocationKey',v_key
              ));
              continue;
            end if;

            v_cost_key:=nullif(btrim(coalesce(v_cost->>'componentKey','')),'');
            if v_cost_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','missing_cost_component_key',
                'allocationKey',v_key
              ));
            elsif v_cost_key=any(v_cost_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','duplicate_cost_component_key',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
            else
              v_cost_keys:=array_append(v_cost_keys,v_cost_key);
            end if;

            v_state:=lower(btrim(coalesce(v_cost->>'state','')));
            if v_state not in ('known','unresolved','not_applicable') then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_cost_state',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
              continue;
            end if;

            if v_cost ? 'required' then
              if jsonb_typeof(v_cost->'required')<>'boolean' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','invalid_cost_required',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
                v_required:=true;
              else
                v_required:=(v_cost->>'required')::boolean;
              end if;
            else
              v_required:=true;
            end if;

            if v_state='known' then
              v_known_cost_count:=v_known_cost_count+1;
              if jsonb_typeof(v_cost->'amount')<>'number' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','known_cost_without_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              else
                v_amount:=(v_cost->>'amount')::numeric;
                if v_amount<0 then
                  v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                    'key','negative_cost_amount',
                    'allocationKey',v_key,
                    'componentKey',v_cost_key
                  ));
                end if;
              end if;

              v_currency:=upper(btrim(coalesce(v_cost->>'currency','')));
              if v_currency !~ '^[A-Z]{3}$' then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','invalid_cost_currency',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
            elsif v_state='unresolved' then
              if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','unresolved_cost_has_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
              if v_required then
                v_unresolved_required_cost_count:=v_unresolved_required_cost_count+1;
              end if;
            else
              if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
                v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                  'key','not_applicable_cost_has_amount',
                  'allocationKey',v_key,
                  'componentKey',v_cost_key
                ));
              end if;
            end if;

            if v_cost ? 'details' and jsonb_typeof(v_cost->'details')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_cost_details',
                'allocationKey',v_key,
                'componentKey',v_cost_key
              ));
            end if;
          end loop;
        end if;
      end if;
    end loop;
  end if;

  if v_req_qty is not null and v_output_total>v_req_qty then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
      'key','allocated_output_exceeds_requirement',
      'requiredQuantity',v_req_qty,
      'outputQuantity',v_output_total,
      'message','Prefer representing pack/yield overage as source excess rather than allocated requirement output.'
    ));
  end if;

  return jsonb_build_object(
    'contractVersion','fulfillment_composition_validation_v1',
    'validationState',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'violations',v_violations,
    'warnings',v_warnings,
    'requirementQuantity',v_req_qty,
    'requirementUnit',v_req_unit,
    'allocationCount',v_allocation_count,
    'outputQuantity',v_output_total,
    'costComponentCount',v_cost_count,
    'knownCostComponentCount',v_known_cost_count,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotSelectCandidates',true,
      'doesNotReserveResources',true,
      'doesNotCreateCoverage',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


create or replace function atlas.fulfillment_composition_position_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_validation jsonb;
  v_req_qty numeric;
  v_req_unit text;
  v_output_qty numeric;
  v_coverage_state text;
  v_cost_totals jsonb:='{}'::jsonb;
  v_currency_count integer:=0;
  v_cost_count integer:=0;
  v_known_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_economic_state text;
  v_blocking_plan_unresolved_count integer:=0;
  v_complete boolean:=false;
begin
  v_validation:=atlas.fulfillment_composition_validate_v1(p_packet);

  if v_validation->>'validationState'<>'passed' then
    return jsonb_build_object(
      'contractVersion','fulfillment_composition_position_v1',
      'state','invalid',
      'validation',v_validation,
      'completeForPlanning',false,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidPacketCreatesNoTruth',true
      )
    );
  end if;

  v_req_qty:=(v_validation->>'requirementQuantity')::numeric;
  v_req_unit:=v_validation->>'requirementUnit';
  v_output_qty:=(v_validation->>'outputQuantity')::numeric;
  v_cost_count:=(v_validation->>'costComponentCount')::integer;
  v_known_cost_count:=(v_validation->>'knownCostComponentCount')::integer;
  v_unresolved_required_cost_count:=(v_validation->>'unresolvedRequiredCostComponentCount')::integer;

  v_coverage_state:=case
    when v_output_qty<v_req_qty then 'undercovered'
    when v_output_qty>v_req_qty then 'overcovered'
    else 'exact'
  end;

  select
    coalesce(jsonb_object_agg(q.currency,to_jsonb(q.total_amount) order by q.currency),'{}'::jsonb),
    count(*)
  into v_cost_totals,v_currency_count
  from (
    select
      upper(c->>'currency') as currency,
      sum((c->>'amount')::numeric) as total_amount
    from jsonb_array_elements(p_packet->'allocations') a
    cross join lateral jsonb_array_elements(coalesce(a->'costComponents','[]'::jsonb)) c
    where c->>'state'='known'
      and jsonb_typeof(c->'amount')='number'
      and upper(coalesce(c->>'currency','')) ~ '^[A-Z]{3}$'
    group by upper(c->>'currency')
  ) q;

  if v_cost_count=0 or (v_known_cost_count=0 and v_unresolved_required_cost_count=0) then
    v_economic_state:='no_cost_evidence';
  elsif v_unresolved_required_cost_count>0 then
    v_economic_state:='unresolved';
  elsif v_currency_count>1 then
    v_economic_state:='known_multi_currency';
  else
    v_economic_state:='known';
  end if;

  if jsonb_typeof(coalesce(p_packet->'unresolved','[]'::jsonb))='array' then
    select count(*)
    into v_blocking_plan_unresolved_count
    from jsonb_array_elements(coalesce(p_packet->'unresolved','[]'::jsonb)) u
    where jsonb_typeof(u)='object'
      and jsonb_typeof(coalesce(u->'blockingFor','[]'::jsonb))='array'
      and exists(
        select 1
        from jsonb_array_elements_text(coalesce(u->'blockingFor','[]'::jsonb)) x
        where x='planning'
      );
  end if;

  v_complete:=
    v_coverage_state='exact'
    and v_blocking_plan_unresolved_count=0;

  return jsonb_build_object(
    'contractVersion','fulfillment_composition_position_v1',
    'state','ready',
    'planKey',p_packet->>'planKey',
    'requirementRef',p_packet->'requirementRef',
    'coverageState',v_coverage_state,
    'requiredQuantity',v_req_qty,
    'outputQuantity',v_output_qty,
    'unit',v_req_unit,
    'allocationCount',(v_validation->>'allocationCount')::integer,
    'economicState',v_economic_state,
    'knownCostTotalsByCurrency',v_cost_totals,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'blockingPlanningUnresolvedCount',v_blocking_plan_unresolved_count,
    'completeForPlanning',v_complete,
    'validation',v_validation,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'physicalCoverageDoesNotMeanSecuredCoverage',true,
      'economicPositionIsDerived',true,
      'unknownCostIsNeverZero',true,
      'multiCurrencyIsNotAutoConverted',true,
      'doesNotCreateCommercialTerms',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotReserveResources',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.fulfillment_composition_validate_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_composition_validate_v1(jsonb)
  to service_role;

revoke all on function atlas.fulfillment_composition_position_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.fulfillment_composition_position_v1(jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.fulfillment_composition_validate_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_neutral_fulfillment_composition_v1","purpose":"Read-only validation of one proposed quantified fulfillment composition packet.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.fulfillment_composition_position_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_neutral_fulfillment_composition_v1","purpose":"Read-only coverage and economic position for one validated fulfillment composition packet.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();
-- ============================================================================
-- END candidates/atlas_neutral_fulfillment_composition_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_commercial_price_evaluation_v1.sql
-- ============================================================================
create or replace function atlas.commercial_price_evaluate_v1(
  p_fulfillment_packet jsonb,
  p_policy jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_position jsonb;
  v_currency text;
  v_total_cost numeric;
  v_quantity numeric;
  v_unit text;
  v_unit_cost numeric;

  v_method text;
  v_rate numeric;
  v_min_unit_price numeric:=null;
  v_rounding jsonb;
  v_round_mode text:=null;
  v_round_increment numeric:=null;

  v_raw_unit_price numeric;
  v_base_unit_price numeric;
  v_proposed_unit_price numeric;
  v_proposed_total numeric;
  v_gross_profit numeric;
  v_realized_margin numeric;
  v_realized_markup numeric;
begin
  v_position:=atlas.fulfillment_composition_position_v1(p_fulfillment_packet);

  if v_position->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','invalid_fulfillment_composition',
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'blockedCreatesNoCommercialTerms',true
      )
    );
  end if;

  if v_position->>'coverageState'<>'exact' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','fulfillment_not_exactly_covered',
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'underOrOverCoverageDoesNotBecomePrice',true
      )
    );
  end if;

  if v_position->>'economicState'<>'known' then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason',case v_position->>'economicState'
        when 'unresolved' then 'required_cost_unresolved'
        when 'known_multi_currency' then 'multi_currency_without_governed_conversion'
        when 'no_cost_evidence' then 'no_cost_evidence'
        else 'economic_position_not_known'
      end,
      'fulfillmentPosition',v_position,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'unknownCostIsNeverZero',true,
        'noImplicitFxConversion',true
      )
    );
  end if;

  select key,(value)::numeric
  into v_currency,v_total_cost
  from jsonb_each_text(v_position->'knownCostTotalsByCurrency')
  order by key
  limit 1;

  if v_currency is null or v_total_cost is null then
    return jsonb_build_object(
      'contractVersion','commercial_price_evaluation_v1',
      'state','blocked',
      'reason','known_economic_position_missing_single_currency_total',
      'fulfillmentPosition',v_position
    );
  end if;

  v_quantity:=(v_position->>'requiredQuantity')::numeric;
  v_unit:=v_position->>'unit';

  if v_quantity is null or v_quantity<=0 then
    raise exception 'Fulfillment position requires positive quantity for price evaluation.'
      using errcode='22023';
  end if;

  if p_policy is null or jsonb_typeof(p_policy)<>'object' then
    raise exception 'Pricing policy input must be a JSON object.'
      using errcode='22023';
  end if;

  if p_policy->>'contractVersion'<>'commercial_price_policy_input_v1' then
    raise exception 'Pricing policy contractVersion must be commercial_price_policy_input_v1.'
      using errcode='22023';
  end if;

  v_method:=lower(btrim(coalesce(p_policy->>'method','')));
  if v_method not in ('gross_margin','markup') then
    raise exception 'Pricing method must be gross_margin or markup.'
      using errcode='22023';
  end if;

  if jsonb_typeof(p_policy->'rate')<>'number' then
    raise exception 'Pricing policy rate must be numeric.'
      using errcode='22023';
  end if;
  v_rate:=(p_policy->>'rate')::numeric;

  if v_method='gross_margin' and (v_rate<0 or v_rate>=1) then
    raise exception 'Gross-margin rate must be >= 0 and < 1.'
      using errcode='22023';
  end if;

  if v_method='markup' and v_rate<0 then
    raise exception 'Markup rate must be >= 0.'
      using errcode='22023';
  end if;

  if p_policy ? 'minimumUnitPrice' then
    if jsonb_typeof(p_policy->'minimumUnitPrice')<>'number' then
      raise exception 'minimumUnitPrice must be numeric when present.'
        using errcode='22023';
    end if;
    v_min_unit_price:=(p_policy->>'minimumUnitPrice')::numeric;
    if v_min_unit_price<0 then
      raise exception 'minimumUnitPrice must be nonnegative.'
        using errcode='22023';
    end if;
  end if;

  if p_policy ? 'currency' then
    if upper(btrim(coalesce(p_policy->>'currency','')))<>v_currency then
      raise exception 'Policy currency % does not match known fulfillment currency %.',
        p_policy->>'currency',v_currency
        using errcode='22023';
    end if;
  end if;

  if p_policy ? 'rounding' then
    v_rounding:=p_policy->'rounding';
    if jsonb_typeof(v_rounding)<>'object' then
      raise exception 'rounding must be an object when present.'
        using errcode='22023';
    end if;

    v_round_mode:=lower(btrim(coalesce(v_rounding->>'mode','')));
    if v_round_mode<>'ceil' then
      raise exception 'V1 rounding mode must be ceil.'
        using errcode='22023';
    end if;

    if jsonb_typeof(v_rounding->'increment')<>'number' then
      raise exception 'rounding.increment must be numeric.'
        using errcode='22023';
    end if;
    v_round_increment:=(v_rounding->>'increment')::numeric;
    if v_round_increment<=0 then
      raise exception 'rounding.increment must be greater than zero.'
        using errcode='22023';
    end if;
  end if;

  v_unit_cost:=v_total_cost/v_quantity;

  if v_method='gross_margin' then
    v_raw_unit_price:=v_unit_cost/(1-v_rate);
  else
    v_raw_unit_price:=v_unit_cost*(1+v_rate);
  end if;

  v_base_unit_price:=greatest(
    v_raw_unit_price,
    coalesce(v_min_unit_price,v_raw_unit_price)
  );

  if v_round_increment is not null then
    v_proposed_unit_price:=ceil(v_base_unit_price/v_round_increment)*v_round_increment;
  else
    v_proposed_unit_price:=v_base_unit_price;
  end if;

  v_proposed_total:=v_proposed_unit_price*v_quantity;
  v_gross_profit:=v_proposed_total-v_total_cost;

  if v_proposed_total<>0 then
    v_realized_margin:=v_gross_profit/v_proposed_total;
  end if;

  if v_total_cost<>0 then
    v_realized_markup:=v_gross_profit/v_total_cost;
  end if;

  return jsonb_build_object(
    'contractVersion','commercial_price_evaluation_v1',
    'state','priced',
    'currency',v_currency,
    'quantity',v_quantity,
    'unit',v_unit,
    'totalKnownFulfillmentCost',v_total_cost,
    'costPerUnit',v_unit_cost,
    'policy',jsonb_build_object(
      'contractVersion','commercial_price_policy_input_v1',
      'method',v_method,
      'rate',v_rate,
      'minimumUnitPrice',v_min_unit_price,
      'rounding',case
        when v_round_increment is null then null
        else jsonb_build_object('mode','ceil','increment',v_round_increment)
      end
    ),
    'rawUnitPrice',v_raw_unit_price,
    'proposedUnitPrice',v_proposed_unit_price,
    'proposedTotal',v_proposed_total,
    'grossProfit',v_gross_profit,
    'realizedGrossMargin',v_realized_margin,
    'realizedMarkup',v_realized_markup,
    'fulfillmentPosition',v_position,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'derivedTermsOnly',true,
      'doesNotPersistPricingPolicy',true,
      'doesNotCreateStandingPrice',true,
      'doesNotCreateCommercialOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotAuthorizePurchase',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.commercial_price_evaluate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_price_evaluate_v1(jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.commercial_price_evaluate_v1(jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_price_evaluation_v1","purpose":"Read-only deterministic price evaluation from exact known fulfillment economics and explicit policy input.","classificationRuleVersion":3}'::jsonb,
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();
-- ============================================================================
-- END candidates/atlas_commercial_price_evaluation_v1.sql
-- ============================================================================

commit;

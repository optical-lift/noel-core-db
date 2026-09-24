-- Atlas Fulfillment Economics Tranche v1 — disposable validation bundle
-- Candidate-only bundle. Not a canonical release migration.
-- Applies supplier observation, qualification, composition, pricing,
-- Commercial Order -> Company Work, coverage position, pooled/break-bulk planning,
-- pooled price protection, External Acquisition Commitment, and quantitative
-- External Acquisition Fulfillment Intake with partial coverage handoff.
-- Intended only for the no-cost production-schema-clone harness / disposable local database.

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
-- BEGIN candidates/atlas_commercial_price_from_cost_basis_v1.sql
-- ============================================================================
create or replace function atlas.commercial_price_from_cost_basis_v1(
  p_quantity numeric,
  p_unit text,
  p_total_cost numeric,
  p_currency text,
  p_policy jsonb,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,atlas
as $function$
declare
  v_unit text;
  v_currency text;
  v_method text;
  v_rate numeric;
  v_min_unit_price numeric:=null;
  v_rounding jsonb;
  v_round_mode text:=null;
  v_round_increment numeric:=null;

  v_unit_cost numeric;
  v_raw_unit_price numeric;
  v_base_unit_price numeric;
  v_proposed_unit_price numeric;
  v_proposed_total numeric;
  v_gross_profit numeric;
  v_realized_margin numeric;
  v_realized_markup numeric;
begin
  if p_quantity is null or p_quantity<=0 then
    raise exception 'Pricing quantity must be greater than zero.'
      using errcode='22023';
  end if;

  v_unit:=nullif(btrim(coalesce(p_unit,'')),'');
  if v_unit is null then
    raise exception 'Pricing unit is required.'
      using errcode='22023';
  end if;

  if p_total_cost is null or p_total_cost<0 then
    raise exception 'Pricing total cost basis must be nonnegative.'
      using errcode='22023';
  end if;

  v_currency:=upper(btrim(coalesce(p_currency,'')));
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Pricing currency must be a three-letter uppercase code.'
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

  if p_context is null or jsonb_typeof(p_context)<>'object' then
    raise exception 'Pricing context must be a JSON object.'
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
      raise exception 'Policy currency % does not match cost-basis currency %.',
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

  v_unit_cost:=p_total_cost/p_quantity;

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

  v_proposed_total:=v_proposed_unit_price*p_quantity;
  v_gross_profit:=v_proposed_total-p_total_cost;

  if v_proposed_total<>0 then
    v_realized_margin:=v_gross_profit/v_proposed_total;
  end if;

  if p_total_cost<>0 then
    v_realized_markup:=v_gross_profit/p_total_cost;
  end if;

  return jsonb_build_object(
    'contractVersion','commercial_price_from_cost_basis_v1',
    'state','priced',
    'currency',v_currency,
    'quantity',p_quantity,
    'unit',v_unit,
    'totalCostBasis',p_total_cost,
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
    'grossProfitAgainstCostBasis',v_gross_profit,
    'realizedGrossMarginAgainstCostBasis',v_realized_margin,
    'realizedMarkupAgainstCostBasis',v_realized_markup,
    'context',p_context,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'costBasisMustBeGovernedUpstream',true,
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


revoke all on function atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.commercial_price_from_cost_basis_v1(numeric,text,numeric,text,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_pooled_commercial_price_protection_v1","purpose":"Shared pure pricing law from an explicit governed cost basis and explicit pricing policy.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_commercial_price_from_cost_basis_v1.sql
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
  v_price jsonb;
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

  v_price:=atlas.commercial_price_from_cost_basis_v1(
    v_quantity,
    v_unit,
    v_total_cost,
    v_currency,
    p_policy,
    jsonb_build_object(
      'source','fulfillment_composition_position_v1',
      'planKey',v_position->>'planKey'
    )
  );

  return jsonb_build_object(
    'contractVersion','commercial_price_evaluation_v1',
    'state','priced',
    'currency',v_price->>'currency',
    'quantity',(v_price->>'quantity')::numeric,
    'unit',v_price->>'unit',
    'totalKnownFulfillmentCost',(v_price->>'totalCostBasis')::numeric,
    'costPerUnit',(v_price->>'costPerUnit')::numeric,
    'policy',v_price->'policy',
    'rawUnitPrice',(v_price->>'rawUnitPrice')::numeric,
    'proposedUnitPrice',(v_price->>'proposedUnitPrice')::numeric,
    'proposedTotal',(v_price->>'proposedTotal')::numeric,
    'grossProfit',(v_price->>'grossProfitAgainstCostBasis')::numeric,
    'realizedGrossMargin',
      case when v_price->>'realizedGrossMarginAgainstCostBasis' is null then null
           else (v_price->>'realizedGrossMarginAgainstCostBasis')::numeric end,
    'realizedMarkup',
      case when v_price->>'realizedMarkupAgainstCostBasis' is null then null
           else (v_price->>'realizedMarkupAgainstCostBasis')::numeric end,
    'sharedPriceResult',v_price,
    'fulfillmentPosition',v_position,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sharedPricingLaw',true,
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

-- ============================================================================
-- BEGIN candidates/atlas_commercial_commitment_to_company_work_v1.sql
-- ============================================================================
create or replace function atlas.commercial_order_fulfillment_requirements_preview_v1(
  p_commercial_order_id uuid,
  p_requirements jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_order atlas.commercial_orders%rowtype;
  v_req jsonb;
  v_existing atlas.work_requirements%rowtype;
  v_line_id uuid;
  v_line atlas.commercial_order_lines%rowtype;

  v_key text;
  v_class text;
  v_summary text;
  v_jurisdiction text;
  v_stable_key text;
  v_source_type text;
  v_source_id uuid;

  v_quantity numeric;
  v_unit text;
  v_specification jsonb;
  v_domain_metadata jsonb;
  v_consequence jsonb;
  v_expected_metadata jsonb;

  v_requirement_began_at timestamptz;
  v_earliest_relevant_at timestamptz;
  v_latest_satisfactory_at timestamptz;

  v_keys text[]:='{}'::text[];
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_normalized jsonb:='[]'::jsonb;

  v_cancelled boolean:=false;
  v_commitment_at timestamptz;
  v_commitment_time_basis text;
  v_compatible boolean;
  v_would_create integer:=0;
  v_existing_count integer:=0;
begin
  if p_requirements is null or jsonb_typeof(p_requirements)<>'array' then
    raise exception 'Requirements must be a JSON array.'
      using errcode='22023';
  end if;

  if p_interpretation_basis is null or jsonb_typeof(p_interpretation_basis)<>'object' then
    raise exception 'Interpretation basis must be a JSON object.'
      using errcode='22023';
  end if;

  if nullif(btrim(coalesce(p_interpretation_basis->>'adapterKey','')),'') is null
     or nullif(btrim(coalesce(p_interpretation_basis->>'adapterVersion','')),'') is null then
    raise exception 'Interpretation basis requires adapterKey and adapterVersion.'
      using errcode='22023';
  end if;

  select * into v_order
  from atlas.commercial_orders
  where id=p_commercial_order_id;

  if v_order.id is null then
    raise exception 'Commercial Order not found.'
      using errcode='P0002';
  end if;

  select min(e.occurred_at)
  into v_commitment_at
  from atlas.commercial_order_events e
  where e.commercial_order_id=v_order.id
    and e.event_kind='recorded';

  if v_commitment_at is null then
    v_commitment_at:=v_order.created_at;
    v_commitment_time_basis:='order_created_at_fallback';
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
      'key','commitment_time_fallback',
      'message','No recorded Commercial Order event exists; using order.created_at as commitment timestamp fallback.'
    ));
  else
    v_commitment_time_basis:='commercial_order_event_recorded';
  end if;

  select exists(
    select 1
    from atlas.commercial_order_events e
    where e.commercial_order_id=v_order.id
      and e.event_kind='cancelled'
  ) into v_cancelled;

  if v_cancelled then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','commercial_order_cancelled',
      'message','Cancelled Commercial Order cannot establish new active fulfillment requirements.'
    ));
  end if;

  for v_req in
    select value
    from jsonb_array_elements(p_requirements)
  loop
    v_line_id:=null;
    v_line:=null;
    v_quantity:=null;
    v_unit:=null;
    v_requirement_began_at:=v_commitment_at;
    v_earliest_relevant_at:=v_commitment_at;
    v_latest_satisfactory_at:=null;
    v_existing:=null;

    if jsonb_typeof(v_req)<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','requirement_not_object',
        'message','Each fulfillment requirement must be a JSON object.'
      ));
      continue;
    end if;

    v_key:=nullif(btrim(coalesce(v_req->>'requirementKey','')),'');
    if v_key is null or v_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_key',
        'requirementKey',v_req->>'requirementKey',
        'message','requirementKey must be a stable 1-128 character identifier.'
      ));
      continue;
    end if;

    if v_key=any(v_keys) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','duplicate_requirement_key',
        'requirementKey',v_key
      ));
      continue;
    end if;
    v_keys:=array_append(v_keys,v_key);

    v_class:=nullif(btrim(coalesce(v_req->>'requirementClass','')),'');
    if v_class is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_requirement_class',
        'requirementKey',v_key
      ));
    end if;

    v_summary:=nullif(btrim(coalesce(v_req->>'summary','')),'');
    if v_summary is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_summary',
        'requirementKey',v_key
      ));
    end if;

    v_jurisdiction:=nullif(btrim(coalesce(v_req->>'jurisdictionKey','')),'');
    if v_jurisdiction is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_jurisdiction',
        'requirementKey',v_key
      ));
    end if;

    if v_req ? 'sourceOrderLineId' and v_req->>'sourceOrderLineId' is not null then
      begin
        v_line_id:=nullif(btrim(v_req->>'sourceOrderLineId'),'')::uuid;
      exception when invalid_text_representation then
        v_line_id:=null;
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_source_order_line_id',
          'requirementKey',v_key
        ));
      end;

      if v_line_id is not null then
        select * into v_line
        from atlas.commercial_order_lines
        where id=v_line_id;

        if v_line.id is null or v_line.commercial_order_id is distinct from v_order.id then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','source_order_line_outside_order',
            'requirementKey',v_key,
            'sourceOrderLineId',v_line_id
          ));
        end if;
      end if;
    end if;

    if v_line_id is null then
      v_source_type:='commercial_order';
      v_source_id:=v_order.id;
    else
      v_source_type:='commercial_order_line';
      v_source_id:=v_line_id;
    end if;

    if v_req ? 'quantity' then
      if jsonb_typeof(v_req->'quantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_quantity',
          'requirementKey',v_key
        ));
      else
        v_quantity:=(v_req->>'quantity')::numeric;
        if v_quantity<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_quantity',
            'requirementKey',v_key,
            'message','quantity must be greater than zero.'
          ));
        end if;
      end if;

      v_unit:=nullif(btrim(coalesce(v_req->>'unit','')),'');
      if v_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','quantity_without_unit',
          'requirementKey',v_key
        ));
      end if;
    elsif v_req ? 'unit' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','unit_without_quantity',
        'requirementKey',v_key
      ));
    end if;

    if v_req ? 'specification' then
      if jsonb_typeof(v_req->'specification')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_specification',
          'requirementKey',v_key
        ));
        v_specification:='{}'::jsonb;
      else
        v_specification:=v_req->'specification';
      end if;
    else
      v_specification:='{}'::jsonb;
    end if;

    if v_req ? 'metadata' then
      if jsonb_typeof(v_req->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_metadata',
          'requirementKey',v_key
        ));
        v_domain_metadata:='{}'::jsonb;
      else
        v_domain_metadata:=v_req->'metadata';
      end if;
    else
      v_domain_metadata:='{}'::jsonb;
    end if;

    if not (v_req ? 'consequenceOfDelay')
       or jsonb_typeof(v_req->'consequenceOfDelay')<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_consequence_of_delay',
        'requirementKey',v_key,
        'message','consequenceOfDelay must be an explicit JSON object.'
      ));
      v_consequence:='{}'::jsonb;
    else
      v_consequence:=v_req->'consequenceOfDelay';
    end if;

    if v_req ? 'requirementBeganAt' and nullif(btrim(coalesce(v_req->>'requirementBeganAt','')),'') is not null then
      begin
        v_requirement_began_at:=(v_req->>'requirementBeganAt')::timestamptz;
      exception when others then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_requirement_began_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    v_earliest_relevant_at:=v_requirement_began_at;
    if v_req ? 'earliestRelevantAt' and nullif(btrim(coalesce(v_req->>'earliestRelevantAt','')),'') is not null then
      begin
        v_earliest_relevant_at:=(v_req->>'earliestRelevantAt')::timestamptz;
      exception when others then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_earliest_relevant_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    if not (v_req ? 'latestSatisfactoryAt')
       or nullif(btrim(coalesce(v_req->>'latestSatisfactoryAt','')),'') is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','missing_latest_satisfactory_at',
        'requirementKey',v_key
      ));
    else
      begin
        v_latest_satisfactory_at:=(v_req->>'latestSatisfactoryAt')::timestamptz;
      exception when others then
        v_latest_satisfactory_at:=null;
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_latest_satisfactory_at',
          'requirementKey',v_key
        ));
      end;
    end if;

    if v_latest_satisfactory_at is not null
       and v_earliest_relevant_at is not null
       and v_latest_satisfactory_at<v_earliest_relevant_at then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_window',
        'requirementKey',v_key,
        'message','latestSatisfactoryAt cannot precede earliestRelevantAt.'
      ));
    end if;

    v_stable_key:='commercial_order:'||v_order.id::text||':fulfillment:'||v_key;

    v_expected_metadata:=jsonb_build_object(
      'commercialFulfillment',jsonb_build_object(
        'contractVersion','commercial_order_fulfillment_requirements_v1',
        'commercialOrderId',v_order.id,
        'commercialOrderLineId',v_line_id,
        'requirementKey',v_key,
        'requirementClass',v_class,
        'quantity',v_quantity,
        'unit',v_unit,
        'specification',coalesce(v_specification,'{}'::jsonb),
        'interpretationBasis',p_interpretation_basis
      ),
      'domain',coalesce(v_domain_metadata,'{}'::jsonb)
    );

    select * into v_existing
    from atlas.work_requirements wr
    where wr.organization_id=v_order.organization_id
      and wr.stable_key=v_stable_key;

    if v_existing.id is not null then
      v_existing_count:=v_existing_count+1;
      v_compatible:=
        v_existing.organization_unit_id is not distinct from v_order.organization_unit_id
        and v_existing.requirement_kind='fulfillment_coverage'
        and v_existing.summary is not distinct from v_summary
        and v_existing.source_object_type=v_source_type
        and v_existing.source_object_id=v_source_id
        and v_existing.established_at=v_commitment_at
        and v_existing.requirement_began_at is not distinct from v_requirement_began_at
        and v_existing.earliest_relevant_at is not distinct from v_earliest_relevant_at
        and v_existing.latest_satisfactory_at is not distinct from v_latest_satisfactory_at
        and v_existing.consequence_of_delay=v_consequence
        and v_existing.jurisdiction_key is not distinct from v_jurisdiction
        and v_existing.metadata->'commercialFulfillment'=v_expected_metadata->'commercialFulfillment'
        and coalesce(v_existing.metadata->'domain','{}'::jsonb)=v_expected_metadata->'domain';

      if not v_compatible then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','existing_requirement_conflicts',
          'requirementKey',v_key,
          'stableKey',v_stable_key,
          'existingWorkRequirementId',v_existing.id
        ));
      end if;
    else
      v_compatible:=true;
      v_would_create:=v_would_create+1;
    end if;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'requirementKey',v_key,
      'requirementClass',v_class,
      'stableKey',v_stable_key,
      'summary',v_summary,
      'organizationId',v_order.organization_id,
      'organizationUnitId',v_order.organization_unit_id,
      'requirementKind','fulfillment_coverage',
      'sourceObjectType',v_source_type,
      'sourceObjectId',v_source_id,
      'sourceOrderLineId',v_line_id,
      'establishedAt',v_commitment_at,
      'requirementBeganAt',v_requirement_began_at,
      'earliestRelevantAt',v_earliest_relevant_at,
      'latestSatisfactoryAt',v_latest_satisfactory_at,
      'consequenceOfDelay',v_consequence,
      'jurisdictionKey',v_jurisdiction,
      'metadata',v_expected_metadata,
      'existingWorkRequirementId',v_existing.id,
      'existingState',v_existing.state,
      'compatibleWithExisting',v_compatible,
      'wouldCreate',(v_existing.id is null)
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','commercial_order_fulfillment_requirements_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'commercialOrderId',v_order.id,
    'organizationId',v_order.organization_id,
    'organizationUnitId',v_order.organization_unit_id,
    'orderCreatedAt',v_order.created_at,
    'commitmentOccurredAt',v_commitment_at,
    'commitmentTimeBasis',v_commitment_time_basis,
    'orderCancelled',v_cancelled,
    'requirementCount',jsonb_array_length(p_requirements),
    'wouldCreateCount',v_would_create,
    'existingCompatibleCount',v_existing_count,
    'requirements',v_normalized,
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'commercialOrderIsCommitmentAuthority',true,
      'domainAdapterOwnsRequirementMeaning',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCreateWorkItem',true,
      'doesNotChooseCarrier',true,
      'doesNotPurchase',true,
      'doesNotReserve',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true
    )
  );
end;
$function$;


create or replace function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(
  p_commercial_order_id uuid,
  p_requirements jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_req jsonb;
  v_existing atlas.work_requirements%rowtype;
  v_requirement_id uuid;
  v_results jsonb:='[]'::jsonb;
  v_created_count integer:=0;
  v_existing_count integer:=0;
  v_expected_metadata jsonb;
  v_compatible boolean;
  v_created boolean;
begin
  v_preview:=atlas.commercial_order_fulfillment_requirements_preview_v1(
    p_commercial_order_id,
    p_requirements,
    p_interpretation_basis
  );

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1
      from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_requirement_conflicts'
    ) then
      raise exception 'Commercial Order fulfillment requirement conflicts with existing structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'Commercial Order fulfillment requirements are blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  for v_req in
    select value
    from jsonb_array_elements(v_preview->'requirements')
  loop
    v_requirement_id:=null;
    v_created:=false;
    v_expected_metadata:=v_req->'metadata';

    if nullif(v_req->>'existingWorkRequirementId','') is not null then
      v_requirement_id:=(v_req->>'existingWorkRequirementId')::uuid;
      v_existing_count:=v_existing_count+1;
    else
      insert into atlas.work_requirements(
        organization_id,
        organization_unit_id,
        stable_key,
        requirement_kind,
        summary,
        source_object_type,
        source_object_id,
        state,
        established_at,
        requirement_began_at,
        earliest_relevant_at,
        latest_satisfactory_at,
        consequence_of_delay,
        jurisdiction_key,
        metadata
      ) values (
        (v_req->>'organizationId')::uuid,
        nullif(v_req->>'organizationUnitId','')::uuid,
        v_req->>'stableKey',
        'fulfillment_coverage',
        v_req->>'summary',
        v_req->>'sourceObjectType',
        (v_req->>'sourceObjectId')::uuid,
        'active',
        (v_req->>'establishedAt')::timestamptz,
        nullif(v_req->>'requirementBeganAt','')::timestamptz,
        nullif(v_req->>'earliestRelevantAt','')::timestamptz,
        (v_req->>'latestSatisfactoryAt')::timestamptz,
        v_req->'consequenceOfDelay',
        v_req->>'jurisdictionKey',
        v_expected_metadata
      )
      on conflict (organization_id,stable_key)
        where stable_key is not null
      do nothing
      returning id into v_requirement_id;

      if v_requirement_id is not null then
        v_created:=true;
        v_created_count:=v_created_count+1;
      else
        select * into v_existing
        from atlas.work_requirements wr
        where wr.organization_id=(v_req->>'organizationId')::uuid
          and wr.stable_key=v_req->>'stableKey';

        if v_existing.id is null then
          raise exception 'Work Requirement stable-key conflict could not be resolved.'
            using errcode='23505';
        end if;

        v_compatible:=
          v_existing.organization_unit_id is not distinct from nullif(v_req->>'organizationUnitId','')::uuid
          and v_existing.requirement_kind='fulfillment_coverage'
          and v_existing.summary is not distinct from v_req->>'summary'
          and v_existing.source_object_type=v_req->>'sourceObjectType'
          and v_existing.source_object_id=(v_req->>'sourceObjectId')::uuid
          and v_existing.established_at=(v_req->>'establishedAt')::timestamptz
          and v_existing.requirement_began_at is not distinct from nullif(v_req->>'requirementBeganAt','')::timestamptz
          and v_existing.earliest_relevant_at is not distinct from nullif(v_req->>'earliestRelevantAt','')::timestamptz
          and v_existing.latest_satisfactory_at is not distinct from (v_req->>'latestSatisfactoryAt')::timestamptz
          and v_existing.consequence_of_delay=v_req->'consequenceOfDelay'
          and v_existing.jurisdiction_key is not distinct from v_req->>'jurisdictionKey'
          and v_existing.metadata->'commercialFulfillment'=v_expected_metadata->'commercialFulfillment'
          and coalesce(v_existing.metadata->'domain','{}'::jsonb)=coalesce(v_expected_metadata->'domain','{}'::jsonb);

        if not v_compatible then
          raise exception 'Work Requirement stable key already exists with different structural truth: %',
            v_req->>'stableKey'
            using errcode='23505';
        end if;

        v_requirement_id:=v_existing.id;
        v_existing_count:=v_existing_count+1;
      end if;
    end if;

    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'requirementKey',v_req->>'requirementKey',
      'stableKey',v_req->>'stableKey',
      'workRequirementId',v_requirement_id,
      'created',v_created,
      'sourceObjectType',v_req->>'sourceObjectType',
      'sourceObjectId',v_req->>'sourceObjectId'
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','ensure_commercial_order_fulfillment_requirements_service_v1',
    'commercialOrderId',p_commercial_order_id,
    'createdCount',v_created_count,
    'existingCount',v_existing_count,
    'requirements',v_results,
    'truthBoundary',jsonb_build_object(
      'establishesOnlyCompanyWorkRequirement',true,
      'doesNotCreateWorkItem',true,
      'doesNotChooseCarrier',true,
      'doesNotCreatePurchase',true,
      'doesNotReserveResource',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateFulfillmentEvent',true
    )
  );
end;
$function$;


revoke all on function atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)
  to service_role;

revoke all on function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.commercial_order_fulfillment_requirements_preview_v1(uuid,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_commitment_to_company_work_v1","purpose":"Read-only preview of explicit domain fulfillment requirements that a committed Commercial Order would establish in Company Work.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.ensure_commercial_order_fulfillment_requirements_service_v1(uuid,jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_commercial_commitment_to_company_work_v1","purpose":"Idempotently establish explicit domain-interpreted fulfillment coverage as existing Company Work Requirements; creates no execution carrier.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_commercial_commitment_to_company_work_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_company_work_coverage_position_v1.sql
-- ============================================================================
create or replace function atlas.work_requirement_coverage_position_v1(
  p_work_requirement_id uuid,
  p_coverage_facts jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_requirement atlas.work_requirements%rowtype;
  v_fact jsonb;
  v_key text;
  v_state text;
  v_extent text;
  v_quantity numeric;
  v_unit text;
  v_required_quantity numeric;
  v_required_unit text;
  v_quantified boolean:=false;
  v_keys text[]:='{}'::text[];
  v_violations jsonb:='[]'::jsonb;
  v_normalized jsonb:='[]'::jsonb;

  v_secured_quantity numeric:=0;
  v_provisional_quantity numeric:=0;

  v_secured_count integer:=0;
  v_provisional_count integer:=0;
  v_released_count integer:=0;
  v_failed_count integer:=0;
  v_unresolved_count integer:=0;

  v_secured_full_count integer:=0;
  v_secured_partial_count integer:=0;
  v_provisional_full_count integer:=0;
  v_provisional_partial_count integer:=0;

  v_hard_state text;
  v_fully_secured boolean:=false;
begin
  if p_coverage_facts is null or jsonb_typeof(p_coverage_facts)<>'array' then
    raise exception 'Coverage facts must be a JSON array.'
      using errcode='22023';
  end if;

  select * into v_requirement
  from atlas.work_requirements
  where id=p_work_requirement_id;

  if v_requirement.id is null then
    raise exception 'Work Requirement not found.'
      using errcode='P0002';
  end if;

  if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')='number'
     and nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is not null then
    v_required_quantity:=(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric;
    v_required_unit:=btrim(v_requirement.metadata->'commercialFulfillment'->>'unit');
    v_quantified:=true;
    if v_required_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_requirement_quantity_metadata',
        'message','Quantified Work Requirement quantity must be greater than zero.'
      ));
    end if;
  elsif (v_requirement.metadata->'commercialFulfillment' ? 'quantity')
     or (v_requirement.metadata->'commercialFulfillment' ? 'unit') then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_requirement_quantity_metadata',
      'message','Quantified Work Requirement metadata must contain numeric quantity and nonblank unit.'
    ));
  end if;

  for v_fact in
    select value
    from jsonb_array_elements(p_coverage_facts)
  loop
    if jsonb_typeof(v_fact)<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','coverage_fact_not_object'
      ));
      continue;
    end if;

    v_key:=nullif(btrim(coalesce(v_fact->>'coverageKey','')),'');
    if v_key is null or v_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_key',
        'coverageKey',v_fact->>'coverageKey'
      ));
      continue;
    end if;

    if v_key=any(v_keys) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','duplicate_coverage_key',
        'coverageKey',v_key
      ));
      continue;
    end if;
    v_keys:=array_append(v_keys,v_key);

    if jsonb_typeof(v_fact->'sourceRef')<>'object'
       or nullif(btrim(coalesce(v_fact->'sourceRef'->>'sourceDomain','')),'') is null
       or nullif(btrim(coalesce(v_fact->'sourceRef'->>'sourceRef','')),'') is null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_source_ref',
        'coverageKey',v_key
      ));
    end if;

    if v_fact ? 'metadata'
       and jsonb_typeof(v_fact->'metadata')<>'object' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_metadata',
        'coverageKey',v_key
      ));
    end if;

    if v_fact ? 'evidence'
       and jsonb_typeof(v_fact->'evidence')<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_evidence',
        'coverageKey',v_key
      ));
    end if;

    v_state:=lower(btrim(coalesce(v_fact->>'state','')));
    if v_state not in ('secured','provisional','released','failed','unresolved') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_coverage_state',
        'coverageKey',v_key,
        'state',v_fact->>'state'
      ));
      continue;
    end if;

    v_quantity:=null;
    v_unit:=null;
    v_extent:=null;

    if v_quantified then
      if v_state in ('secured','provisional') then
        if jsonb_typeof(v_fact->'quantity')<>'number' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','missing_coverage_quantity',
            'coverageKey',v_key,
            'state',v_state
          ));
        else
          v_quantity:=(v_fact->>'quantity')::numeric;
          if v_quantity<=0 then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_coverage_quantity',
              'coverageKey',v_key
            ));
          end if;
        end if;

        v_unit:=nullif(btrim(coalesce(v_fact->>'unit','')),'');
        if v_unit is null or v_unit<>v_required_unit then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','coverage_unit_mismatch',
            'coverageKey',v_key,
            'requiredUnit',v_required_unit,
            'coverageUnit',v_unit
          ));
        end if;
      elsif (v_fact ? 'quantity') or (v_fact ? 'unit') then
        if jsonb_typeof(v_fact->'quantity')='number' then
          v_quantity:=(v_fact->>'quantity')::numeric;
        end if;
        v_unit:=nullif(btrim(coalesce(v_fact->>'unit','')),'');
        if v_quantity is not null and v_quantity<0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_noncurrent_coverage_quantity',
            'coverageKey',v_key
          ));
        end if;
        if v_unit is not null and v_unit<>v_required_unit then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','coverage_unit_mismatch',
            'coverageKey',v_key,
            'requiredUnit',v_required_unit,
            'coverageUnit',v_unit
          ));
        end if;
      end if;

      if v_state='secured' and v_quantity is not null and v_quantity>0 and v_unit=v_required_unit then
        v_secured_quantity:=v_secured_quantity+v_quantity;
      elsif v_state='provisional' and v_quantity is not null and v_quantity>0 and v_unit=v_required_unit then
        v_provisional_quantity:=v_provisional_quantity+v_quantity;
      end if;
    else
      if v_state in ('secured','provisional') then
        v_extent:=lower(btrim(coalesce(v_fact->>'extent','')));
        if v_extent not in ('full','partial') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_coverage_extent',
            'coverageKey',v_key,
            'state',v_state
          ));
        end if;
      elsif v_fact ? 'extent' then
        v_extent:=lower(btrim(coalesce(v_fact->>'extent','')));
        if v_extent not in ('full','partial') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_coverage_extent',
            'coverageKey',v_key,
            'state',v_state
          ));
        end if;
      end if;

      if v_state='secured' and v_extent='full' then
        v_secured_full_count:=v_secured_full_count+1;
      elsif v_state='secured' and v_extent='partial' then
        v_secured_partial_count:=v_secured_partial_count+1;
      elsif v_state='provisional' and v_extent='full' then
        v_provisional_full_count:=v_provisional_full_count+1;
      elsif v_state='provisional' and v_extent='partial' then
        v_provisional_partial_count:=v_provisional_partial_count+1;
      end if;
    end if;

    case v_state
      when 'secured' then v_secured_count:=v_secured_count+1;
      when 'provisional' then v_provisional_count:=v_provisional_count+1;
      when 'released' then v_released_count:=v_released_count+1;
      when 'failed' then v_failed_count:=v_failed_count+1;
      when 'unresolved' then v_unresolved_count:=v_unresolved_count+1;
    end case;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'coverageKey',v_key,
      'sourceRef',v_fact->'sourceRef',
      'state',v_state,
      'quantity',v_quantity,
      'unit',v_unit,
      'extent',v_extent,
      'evidence',coalesce(v_fact->'evidence','[]'::jsonb),
      'metadata',coalesce(v_fact->'metadata','{}'::jsonb)
    ));
  end loop;

  if jsonb_array_length(v_violations)>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_coverage_position_v1',
      'state','invalid',
      'workRequirementId',v_requirement.id,
      'requirementState',v_requirement.state,
      'quantified',v_quantified,
      'violations',v_violations,
      'coverageFacts',v_normalized,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidCoverageFactsCreateNoTruth',true
      )
    );
  end if;

  if v_quantified then
    v_hard_state:=case
      when v_secured_quantity=0 then 'none'
      when v_secured_quantity<v_required_quantity then 'partial'
      when v_secured_quantity=v_required_quantity then 'exact'
      else 'overcovered'
    end;
    v_fully_secured:=v_secured_quantity>=v_required_quantity;
  else
    v_hard_state:=case
      when v_secured_full_count>0 then 'full'
      when v_secured_partial_count>0 then 'partial'
      else 'none'
    end;
    v_fully_secured:=v_secured_full_count>0;
  end if;

  return jsonb_build_object(
    'contractVersion','work_requirement_coverage_position_v1',
    'state','ready',
    'workRequirementId',v_requirement.id,
    'organizationId',v_requirement.organization_id,
    'requirementState',v_requirement.state,
    'responsibilityActive',(v_requirement.state='active'),
    'quantified',v_quantified,
    'requiredQuantity',v_required_quantity,
    'requiredUnit',v_required_unit,
    'securedQuantity',case when v_quantified then v_secured_quantity else null end,
    'provisionalQuantity',case when v_quantified then v_provisional_quantity else null end,
    'hardCoverageState',v_hard_state,
    'fullySecured',v_fully_secured,
    'securedFactCount',v_secured_count,
    'provisionalFactCount',v_provisional_count,
    'releasedFactCount',v_released_count,
    'failedFactCount',v_failed_count,
    'unresolvedFactCount',v_unresolved_count,
    'securedFullFactCount',case when v_quantified then null else v_secured_full_count end,
    'securedPartialFactCount',case when v_quantified then null else v_secured_partial_count end,
    'provisionalFullFactCount',case when v_quantified then null else v_provisional_full_count end,
    'provisionalPartialFactCount',case when v_quantified then null else v_provisional_partial_count end,
    'coverageFacts',v_normalized,
    'violations','[]'::jsonb,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'workRequirementRemainsAuthorityForResponsibility',true,
      'sourceObjectsRemainAuthorityForSecuringFacts',true,
      'coverageDoesNotMeanFulfillment',true,
      'coverageDoesNotCloseWorkRequirement',true,
      'provisionalDoesNotCountAsSecured',true,
      'unresolvedDoesNotBecomeZeroOrFailure',true,
      'doesNotCreateAllocation',true,
      'doesNotCreateReservation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_coverage_position_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_coverage_position_v1(uuid,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_coverage_position_v1(uuid,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_company_work_coverage_position_v1","purpose":"Read-only normalized coverage position over explicit source-owned allocation/reservation/assignment/acquisition facts for one Company Work Requirement.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_company_work_coverage_position_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_work_requirement_pool_position_v1.sql
-- ============================================================================
create or replace function atlas.work_requirement_pool_position_v1(
  p_packet jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_source_ref jsonb;
  v_use jsonb;
  v_cost jsonb;
  v_requirement atlas.work_requirements%rowtype;
  v_coverage jsonb;
  v_organization_id uuid;

  v_pool_key text;
  v_source_quantity numeric;
  v_source_unit text;
  v_output_quantity numeric;
  v_output_unit text;

  v_use_key text;
  v_work_requirement_id uuid;
  v_qualification_state text;
  v_planned_quantity numeric;
  v_use_unit text;
  v_required_quantity numeric;
  v_required_unit text;
  v_already_secured numeric;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_use_state text;

  v_use_keys text[]:='{}'::text[];
  v_requirement_ids uuid[]:='{}'::uuid[];
  v_cost_keys text[]:='{}'::text[];

  v_cost_key text;
  v_cost_state text;
  v_cost_required boolean;
  v_cost_amount numeric;
  v_cost_currency text;

  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_requirement_positions jsonb:='[]'::jsonb;

  v_planned_output_quantity numeric:=0;
  v_aggregate_outstanding_before numeric:=0;
  v_unallocated_demand_quantity numeric:=0;
  v_excess_output_quantity numeric:=0;

  v_known_cost_count integer:=0;
  v_unresolved_required_cost_count integer:=0;
  v_cost_component_count integer:=0;
  v_currency_count integer:=0;
  v_known_cost_totals jsonb:='{}'::jsonb;
  v_economic_state text;
  v_known_pool_cost numeric;
  v_known_currency text;
  v_source_basis_unit_cost numeric;
  v_allocated_output_cost_basis numeric;
  v_excess_output_cost_basis numeric;
  v_full_cost_burden_per_planned_unit numeric;

  v_pool_utilization_state text;
  v_demand_position text;
begin
  if p_packet is null or jsonb_typeof(p_packet)<>'object' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_position_v1',
      'state','invalid',
      'violations',jsonb_build_array(jsonb_build_object(
        'key','packet_not_object',
        'message','Pool packet must be a JSON object.'
      )),
      'warnings','[]'::jsonb
    );
  end if;

  if p_packet->>'contractVersion'<>'work_requirement_pool_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version',
      'message','contractVersion must be work_requirement_pool_v1.'
    ));
  end if;

  v_pool_key:=nullif(btrim(coalesce(p_packet->>'poolKey','')),'');
  if v_pool_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_pool_key'
    ));
  end if;

  v_source_ref:=p_packet->'sourceRef';
  if v_source_ref is null
     or jsonb_typeof(v_source_ref)<>'object'
     or nullif(btrim(coalesce(v_source_ref->>'sourceDomain','')),'') is null
     or nullif(btrim(coalesce(v_source_ref->>'sourceRef','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_ref'
    ));
  end if;

  if jsonb_typeof(p_packet->'sourceQuantity')<>'number' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_quantity'
    ));
  else
    v_source_quantity:=(p_packet->>'sourceQuantity')::numeric;
    if v_source_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_source_quantity',
        'message','sourceQuantity must be greater than zero.'
      ));
    end if;
  end if;

  v_source_unit:=nullif(btrim(coalesce(p_packet->>'sourceUnit','')),'');
  if v_source_unit is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source_unit'
    ));
  end if;

  if jsonb_typeof(p_packet->'outputQuantity')<>'number' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_output_quantity'
    ));
  else
    v_output_quantity:=(p_packet->>'outputQuantity')::numeric;
    if v_output_quantity<=0 then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_output_quantity',
        'message','outputQuantity must be greater than zero.'
      ));
    end if;
  end if;

  v_output_unit:=nullif(btrim(coalesce(p_packet->>'outputUnit','')),'');
  if v_output_unit is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_output_unit'
    ));
  end if;

  if p_packet ? 'metadata'
     and jsonb_typeof(p_packet->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata'
    ));
  end if;

  if jsonb_typeof(p_packet->'plannedUses')<>'array'
     or jsonb_array_length(coalesce(p_packet->'plannedUses','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_planned_uses',
      'message','plannedUses must be a non-empty array.'
    ));
  else
    for v_use in
      select value
      from jsonb_array_elements(p_packet->'plannedUses')
    loop
      if jsonb_typeof(v_use)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_use_not_object'
        ));
        continue;
      end if;

      v_use_key:=nullif(btrim(coalesce(v_use->>'useKey','')),'');
      if v_use_key is null or v_use_key !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_use_key',
          'useKey',v_use->>'useKey'
        ));
        continue;
      end if;

      if v_use_key=any(v_use_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_use_key',
          'useKey',v_use_key
        ));
        continue;
      end if;
      v_use_keys:=array_append(v_use_keys,v_use_key);

      begin
        v_work_requirement_id:=nullif(btrim(coalesce(v_use->>'workRequirementId','')),'')::uuid;
      exception when invalid_text_representation then
        v_work_requirement_id:=null;
      end;

      if v_work_requirement_id is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_work_requirement_id',
          'useKey',v_use_key
        ));
        continue;
      end if;

      if v_work_requirement_id=any(v_requirement_ids) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_work_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;
      v_requirement_ids:=array_append(v_requirement_ids,v_work_requirement_id);

      select * into v_requirement
      from atlas.work_requirements
      where id=v_work_requirement_id;

      if v_requirement.id is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_found',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      if v_organization_id is null then
        v_organization_id:=v_requirement.organization_id;
      elsif v_requirement.organization_id is distinct from v_organization_id then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','cross_organization_pool',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'expectedOrganizationId',v_organization_id,
          'actualOrganizationId',v_requirement.organization_id
        ));
      end if;

      if v_requirement.state<>'active' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_active',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'requirementState',v_requirement.state
        ));
      end if;

      if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
         or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','work_requirement_not_quantified',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      v_required_quantity:=(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric;
      v_required_unit:=btrim(v_requirement.metadata->'commercialFulfillment'->>'unit');

      if v_required_quantity<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_work_requirement_quantity',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id
        ));
        continue;
      end if;

      if v_required_unit<>v_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','requirement_pool_unit_mismatch',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'requirementUnit',v_required_unit,
          'poolOutputUnit',v_output_unit
        ));
      end if;

      v_qualification_state:=lower(btrim(coalesce(v_use->>'qualificationState','')));
      if v_qualification_state<>'qualified' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','source_not_qualified_for_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'qualificationState',v_use->>'qualificationState'
        ));
      end if;

      if jsonb_typeof(v_use->'plannedQuantity')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_planned_quantity',
          'useKey',v_use_key
        ));
        continue;
      end if;

      v_planned_quantity:=(v_use->>'plannedQuantity')::numeric;
      if v_planned_quantity<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_planned_quantity',
          'useKey',v_use_key,
          'message','plannedQuantity must be greater than zero.'
        ));
      end if;

      v_use_unit:=nullif(btrim(coalesce(v_use->>'unit','')),'');
      if v_use_unit is null
         or v_use_unit<>v_required_unit
         or v_use_unit<>v_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_use_unit_mismatch',
          'useKey',v_use_key,
          'plannedUnit',v_use_unit,
          'requirementUnit',v_required_unit,
          'poolOutputUnit',v_output_unit
        ));
      end if;

      if v_use ? 'existingCoverageFacts'
         and jsonb_typeof(v_use->'existingCoverageFacts')<>'array' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_existing_coverage_facts',
          'useKey',v_use_key
        ));
        v_coverage:=null;
      else
        v_coverage:=atlas.work_requirement_coverage_position_v1(
          v_work_requirement_id,
          coalesce(v_use->'existingCoverageFacts','[]'::jsonb)
        );
      end if;

      if v_coverage is null or v_coverage->>'state'<>'ready' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','existing_coverage_invalid',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'coveragePosition',v_coverage
        ));
        v_already_secured:=0;
      else
        v_already_secured:=coalesce((v_coverage->>'securedQuantity')::numeric,0);
      end if;

      v_outstanding_before:=greatest(v_required_quantity-v_already_secured,0);

      if v_planned_quantity>v_outstanding_before then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','planned_quantity_exceeds_outstanding_requirement',
          'useKey',v_use_key,
          'workRequirementId',v_work_requirement_id,
          'plannedQuantity',v_planned_quantity,
          'outstandingBeforePool',v_outstanding_before
        ));
      end if;

      v_outstanding_after:=greatest(v_outstanding_before-v_planned_quantity,0);

      v_use_state:=case
        when v_outstanding_before=0 then 'already_secured'
        when v_planned_quantity=0 then 'uncovered'
        when v_planned_quantity<v_outstanding_before then 'partial'
        when v_planned_quantity=v_outstanding_before then 'exact'
        else 'overplanned'
      end;

      v_planned_output_quantity:=v_planned_output_quantity+greatest(v_planned_quantity,0);
      v_aggregate_outstanding_before:=v_aggregate_outstanding_before+v_outstanding_before;
      v_unallocated_demand_quantity:=v_unallocated_demand_quantity+v_outstanding_after;

      v_requirement_positions:=v_requirement_positions||jsonb_build_array(jsonb_build_object(
        'useKey',v_use_key,
        'workRequirementId',v_work_requirement_id,
        'requirementStableKey',v_requirement.stable_key,
        'requirementSummary',v_requirement.summary,
        'requiredQuantity',v_required_quantity,
        'unit',v_required_unit,
        'alreadySecuredQuantity',v_already_secured,
        'outstandingBeforePool',v_outstanding_before,
        'plannedFromPool',v_planned_quantity,
        'outstandingAfterPool',v_outstanding_after,
        'plannedCoverageState',v_use_state,
        'qualificationState',v_qualification_state,
        'existingCoveragePosition',v_coverage
      ));
    end loop;
  end if;

  if v_output_quantity is not null and v_planned_output_quantity>v_output_quantity then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','planned_output_exceeds_pool_output',
      'plannedOutputQuantity',v_planned_output_quantity,
      'poolOutputQuantity',v_output_quantity
    ));
  end if;

  if p_packet ? 'costComponents' then
    if jsonb_typeof(p_packet->'costComponents')<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','invalid_cost_components'
      ));
    else
      for v_cost in
        select value
        from jsonb_array_elements(p_packet->'costComponents')
      loop
        v_cost_component_count:=v_cost_component_count+1;

        if jsonb_typeof(v_cost)<>'object' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','cost_component_not_object'
          ));
          continue;
        end if;

        v_cost_key:=nullif(btrim(coalesce(v_cost->>'componentKey','')),'');
        if v_cost_key is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','missing_cost_component_key'
          ));
        elsif v_cost_key=any(v_cost_keys) then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','duplicate_cost_component_key',
            'componentKey',v_cost_key
          ));
        else
          v_cost_keys:=array_append(v_cost_keys,v_cost_key);
        end if;

        v_cost_state:=lower(btrim(coalesce(v_cost->>'state','')));
        if v_cost_state not in ('known','unresolved','not_applicable') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_state',
            'componentKey',v_cost_key
          ));
          continue;
        end if;

        if v_cost ? 'required' then
          if jsonb_typeof(v_cost->'required')<>'boolean' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_cost_required',
              'componentKey',v_cost_key
            ));
            v_cost_required:=true;
          else
            v_cost_required:=(v_cost->>'required')::boolean;
          end if;
        else
          v_cost_required:=true;
        end if;

        if v_cost_state='known' then
          if jsonb_typeof(v_cost->'amount')<>'number' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','known_cost_without_amount',
              'componentKey',v_cost_key
            ));
          else
            v_cost_amount:=(v_cost->>'amount')::numeric;
            if v_cost_amount<0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','negative_cost_amount',
                'componentKey',v_cost_key
              ));
            end if;
          end if;

          v_cost_currency:=upper(btrim(coalesce(v_cost->>'currency','')));
          if v_cost_currency !~ '^[A-Z]{3}$' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_cost_currency',
              'componentKey',v_cost_key
            ));
          else
            v_known_cost_count:=v_known_cost_count+1;
          end if;
        elsif v_cost_state='unresolved' then
          if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','unresolved_cost_has_amount',
              'componentKey',v_cost_key
            ));
          end if;
          if v_cost_required then
            v_unresolved_required_cost_count:=v_unresolved_required_cost_count+1;
          end if;
        else
          if v_cost ? 'amount' and v_cost->'amount'<>'null'::jsonb then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','not_applicable_cost_has_amount',
              'componentKey',v_cost_key
            ));
          end if;
        end if;

        if v_cost ? 'details'
           and jsonb_typeof(v_cost->'details')<>'object' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_details',
            'componentKey',v_cost_key
          ));
        end if;
      end loop;
    end if;
  end if;

  if jsonb_array_length(v_violations)>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_position_v1',
      'state','invalid',
      'poolKey',v_pool_key,
      'sourceRef',v_source_ref,
      'violations',v_violations,
      'warnings',v_warnings,
      'requirementPositions',v_requirement_positions,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'invalidPoolCreatesNoTruth',true
      )
    );
  end if;

  select
    coalesce(jsonb_object_agg(q.currency,to_jsonb(q.total_amount) order by q.currency),'{}'::jsonb),
    count(*)
  into v_known_cost_totals,v_currency_count
  from (
    select
      upper(c->>'currency') as currency,
      sum((c->>'amount')::numeric) as total_amount
    from jsonb_array_elements(coalesce(p_packet->'costComponents','[]'::jsonb)) c
    where c->>'state'='known'
      and jsonb_typeof(c->'amount')='number'
      and upper(coalesce(c->>'currency','')) ~ '^[A-Z]{3}$'
    group by upper(c->>'currency')
  ) q;

  if v_cost_component_count=0
     or (v_known_cost_count=0 and v_unresolved_required_cost_count=0) then
    v_economic_state:='no_cost_evidence';
  elsif v_unresolved_required_cost_count>0 then
    v_economic_state:='unresolved';
  elsif v_currency_count>1 then
    v_economic_state:='known_multi_currency';
  else
    v_economic_state:='known';
  end if;

  v_excess_output_quantity:=greatest(v_output_quantity-v_planned_output_quantity,0);

  v_pool_utilization_state:=case
    when v_planned_output_quantity<v_output_quantity then 'partial_use'
    else 'fully_used'
  end;

  v_demand_position:=case
    when v_unallocated_demand_quantity=0 then 'all_covered'
    else 'partially_covered'
  end;

  if v_economic_state='known' then
    select key,(value)::numeric
    into v_known_currency,v_known_pool_cost
    from jsonb_each_text(v_known_cost_totals)
    order by key
    limit 1;

    v_source_basis_unit_cost:=v_known_pool_cost/v_output_quantity;
    v_allocated_output_cost_basis:=v_source_basis_unit_cost*v_planned_output_quantity;
    v_excess_output_cost_basis:=v_source_basis_unit_cost*v_excess_output_quantity;

    if v_planned_output_quantity>0 then
      v_full_cost_burden_per_planned_unit:=v_known_pool_cost/v_planned_output_quantity;
    end if;

    select coalesce(
      jsonb_agg(
        rp.value || jsonb_build_object(
          'proportionalCostBasis',
          (rp.value->>'plannedFromPool')::numeric * v_source_basis_unit_cost,
          'costCurrency',
          v_known_currency
        )
        order by rp.value->>'useKey'
      ),
      '[]'::jsonb
    )
    into v_requirement_positions
    from jsonb_array_elements(v_requirement_positions) as rp(value);
  end if;

  return jsonb_build_object(
    'contractVersion','work_requirement_pool_position_v1',
    'state','ready',
    'poolKey',v_pool_key,
    'organizationId',v_organization_id,
    'sourceRef',v_source_ref,
    'sourceQuantity',v_source_quantity,
    'sourceUnit',v_source_unit,
    'outputQuantity',v_output_quantity,
    'outputUnit',v_output_unit,
    'plannedOutputQuantity',v_planned_output_quantity,
    'excessOutputQuantity',v_excess_output_quantity,
    'poolUtilizationState',v_pool_utilization_state,
    'aggregateOutstandingBeforePool',v_aggregate_outstanding_before,
    'unallocatedDemandQuantity',v_unallocated_demand_quantity,
    'demandPosition',v_demand_position,
    'requirementCount',jsonb_array_length(v_requirement_positions),
    'requirementPositions',v_requirement_positions,
    'economicState',v_economic_state,
    'knownCostTotalsByCurrency',v_known_cost_totals,
    'unresolvedRequiredCostComponentCount',v_unresolved_required_cost_count,
    'knownPoolCost',v_known_pool_cost,
    'knownCostCurrency',v_known_currency,
    'sourceBasisUnitCost',v_source_basis_unit_cost,
    'allocatedOutputCostBasis',v_allocated_output_cost_basis,
    'excessOutputCostBasis',v_excess_output_cost_basis,
    'fullCostBurdenPerPlannedUnit',v_full_cost_burden_per_planned_unit,
    'metadata',coalesce(p_packet->'metadata','{}'::jsonb),
    'violations','[]'::jsonb,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sourcePoolMayBeOnlyProposed',true,
      'plannedUseIsNotAllocation',true,
      'plannedUseIsNotSecuredCoverage',true,
      'sourceEconomicsRemainSourceBacked',true,
      'excessRemainsExplicit',true,
      'proportionalCostBasisIsDerivedScenario',true,
      'fullCostBurdenIsConservativeScenario',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCreateAllocation',true,
      'doesNotCreateReservation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreatePayment',true,
      'doesNotFulfill',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_pool_position_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_pool_position_v1(jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_pool_position_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_work_requirement_pool_position_v1","purpose":"Read-only break-bulk position for one proposed source pool across several quantified Company Work Requirements, preserving residual demand, source excess, and shared economics.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_work_requirement_pool_position_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_pooled_commercial_price_protection_v1.sql
-- ============================================================================
create or replace function atlas.work_requirement_pool_price_evaluate_v1(
  p_pool_packet jsonb,
  p_policy jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_pool jsonb;
  v_basis text;
  v_pricing_policy jsonb;

  v_known_pool_cost numeric;
  v_currency text;
  v_output_quantity numeric;
  v_planned_quantity numeric;
  v_excess_quantity numeric;
  v_unit text;

  v_source_price jsonb;
  v_full_price jsonb;
  v_selected_price jsonb;

  v_source_current_revenue numeric;
  v_source_whole_pool_profit numeric;
  v_source_whole_pool_margin numeric;

  v_full_current_revenue numeric;
  v_full_whole_pool_profit numeric;
  v_full_whole_pool_margin numeric;

  v_selected_current_revenue numeric;
  v_selected_whole_pool_profit numeric;
  v_selected_whole_pool_margin numeric;

  v_requirement_prices jsonb:='[]'::jsonb;
begin
  v_pool:=atlas.work_requirement_pool_position_v1(p_pool_packet);

  if v_pool->>'state'<>'ready' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','invalid_pool_position',
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'blockedCreatesNoCommercialTerms',true
      )
    );
  end if;

  if v_pool->>'demandPosition'<>'all_covered' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','aggregate_demand_not_fully_covered',
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'incompleteFulfillmentDoesNotBecomeCustomerPrice',true
      )
    );
  end if;

  if v_pool->>'economicState'<>'known' then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason',case v_pool->>'economicState'
        when 'unresolved' then 'required_pool_cost_unresolved'
        when 'known_multi_currency' then 'multi_currency_without_governed_conversion'
        when 'no_cost_evidence' then 'no_pool_cost_evidence'
        else 'pool_economic_position_not_known'
      end,
      'poolPosition',v_pool,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'unknownCostIsNeverZero',true,
        'noImplicitFxConversion',true
      )
    );
  end if;

  if p_policy is null or jsonb_typeof(p_policy)<>'object' then
    raise exception 'Pooled pricing policy must be a JSON object.'
      using errcode='22023';
  end if;

  if p_policy->>'contractVersion'<>'work_requirement_pool_price_policy_v1' then
    raise exception 'Pooled pricing policy contractVersion must be work_requirement_pool_price_policy_v1.'
      using errcode='22023';
  end if;

  v_basis:=lower(btrim(coalesce(p_policy->>'costRecoveryBasis','')));
  if v_basis not in ('full_pool_on_planned_output','source_output') then
    raise exception 'costRecoveryBasis must be full_pool_on_planned_output or source_output.'
      using errcode='22023';
  end if;

  v_pricing_policy:=p_policy->'pricingPolicy';
  if v_pricing_policy is null or jsonb_typeof(v_pricing_policy)<>'object' then
    raise exception 'pricingPolicy must be an explicit JSON object.'
      using errcode='22023';
  end if;

  v_known_pool_cost:=(v_pool->>'knownPoolCost')::numeric;
  v_currency:=v_pool->>'knownCostCurrency';
  v_output_quantity:=(v_pool->>'outputQuantity')::numeric;
  v_planned_quantity:=(v_pool->>'plannedOutputQuantity')::numeric;
  v_excess_quantity:=(v_pool->>'excessOutputQuantity')::numeric;
  v_unit:=v_pool->>'outputUnit';

  if v_planned_quantity<=0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','no_planned_output',
      'poolPosition',v_pool
    );
  end if;

  v_source_price:=atlas.commercial_price_from_cost_basis_v1(
    v_output_quantity,
    v_unit,
    v_known_pool_cost,
    v_currency,
    v_pricing_policy,
    jsonb_build_object(
      'source','work_requirement_pool_position_v1',
      'poolKey',v_pool->>'poolKey',
      'costRecoveryBasis','source_output',
      'scenarioOnly',(v_excess_quantity>0)
    )
  );

  v_full_price:=atlas.commercial_price_from_cost_basis_v1(
    v_planned_quantity,
    v_unit,
    v_known_pool_cost,
    v_currency,
    v_pricing_policy,
    jsonb_build_object(
      'source','work_requirement_pool_position_v1',
      'poolKey',v_pool->>'poolKey',
      'costRecoveryBasis','full_pool_on_planned_output',
      'scenarioOnly',false
    )
  );

  v_source_current_revenue:=(v_source_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_source_whole_pool_profit:=v_source_current_revenue-v_known_pool_cost;
  if v_source_current_revenue<>0 then
    v_source_whole_pool_margin:=v_source_whole_pool_profit/v_source_current_revenue;
  end if;

  v_full_current_revenue:=(v_full_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_full_whole_pool_profit:=v_full_current_revenue-v_known_pool_cost;
  if v_full_current_revenue<>0 then
    v_full_whole_pool_margin:=v_full_whole_pool_profit/v_full_current_revenue;
  end if;

  if v_basis='source_output' and v_excess_quantity>0 then
    return jsonb_build_object(
      'contractVersion','work_requirement_pool_price_evaluation_v1',
      'state','blocked',
      'reason','excess_recovery_not_established',
      'selectedCostRecoveryBasis',v_basis,
      'poolPosition',v_pool,
      'scenarioComparison',jsonb_build_object(
        'sourceOutput',jsonb_build_object(
          'protectionState','unprotected_without_excess_recovery',
          'priceResult',v_source_price,
          'currentPlannedRevenue',v_source_current_revenue,
          'wholePoolGrossProfitIfExcessRecoversZero',v_source_whole_pool_profit,
          'wholePoolGrossMarginIfExcessRecoversZero',v_source_whole_pool_margin
        ),
        'fullPoolOnPlannedOutput',jsonb_build_object(
          'protectionState','protected_against_zero_excess_recovery',
          'priceResult',v_full_price,
          'currentPlannedRevenue',v_full_current_revenue,
          'wholePoolGrossProfit',v_full_whole_pool_profit,
          'wholePoolGrossMargin',v_full_whole_pool_margin
        )
      ),
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'futureExcessSaleIsNotRecoveryEvidence',true,
        'blockedCreatesNoCommercialTerms',true,
        'doesNotCreateOfferSnapshot',true,
        'doesNotCreateOrder',true,
        'doesNotPurchase',true
      )
    );
  end if;

  if v_basis='source_output' then
    v_selected_price:=v_source_price;
  else
    v_selected_price:=v_full_price;
  end if;

  v_selected_current_revenue:=(v_selected_price->>'proposedUnitPrice')::numeric*v_planned_quantity;
  v_selected_whole_pool_profit:=v_selected_current_revenue-v_known_pool_cost;
  if v_selected_current_revenue<>0 then
    v_selected_whole_pool_margin:=v_selected_whole_pool_profit/v_selected_current_revenue;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'useKey',rp.value->>'useKey',
        'workRequirementId',rp.value->>'workRequirementId',
        'plannedQuantity',(rp.value->>'plannedFromPool')::numeric,
        'unit',rp.value->>'unit',
        'proposedUnitPrice',(v_selected_price->>'proposedUnitPrice')::numeric,
        'proposedTotal',
          (rp.value->>'plannedFromPool')::numeric*(v_selected_price->>'proposedUnitPrice')::numeric
      )
      order by rp.value->>'useKey'
    ),
    '[]'::jsonb
  )
  into v_requirement_prices
  from jsonb_array_elements(v_pool->'requirementPositions') as rp(value);

  return jsonb_build_object(
    'contractVersion','work_requirement_pool_price_evaluation_v1',
    'state','priced',
    'organizationId',v_pool->'organizationId',
    'poolKey',v_pool->>'poolKey',
    'selectedCostRecoveryBasis',v_basis,
    'currency',v_currency,
    'unit',v_unit,
    'knownPoolCost',v_known_pool_cost,
    'plannedOutputQuantity',v_planned_quantity,
    'excessOutputQuantity',v_excess_quantity,
    'protectedCostBasisQuantity',(v_selected_price->>'quantity')::numeric,
    'protectedCostBasis',(v_selected_price->>'totalCostBasis')::numeric,
    'protectedCostPerUnit',(v_selected_price->>'costPerUnit')::numeric,
    'protectedProposedUnitPrice',(v_selected_price->>'proposedUnitPrice')::numeric,
    'protectedProposedRevenueOnPlannedOutput',v_selected_current_revenue,
    'protectedWholePoolGrossProfit',v_selected_whole_pool_profit,
    'protectedWholePoolGrossMargin',v_selected_whole_pool_margin,
    'selectedPriceResult',v_selected_price,
    'requirementPrices',v_requirement_prices,
    'scenarioComparison',jsonb_build_object(
      'sourceOutput',jsonb_build_object(
        'protectionState',case
          when v_excess_quantity=0 then 'protected_no_excess'
          else 'unprotected_without_excess_recovery'
        end,
        'priceResult',v_source_price,
        'currentPlannedRevenue',v_source_current_revenue,
        'wholePoolGrossProfitIfExcessRecoversZero',v_source_whole_pool_profit,
        'wholePoolGrossMarginIfExcessRecoversZero',v_source_whole_pool_margin
      ),
      'fullPoolOnPlannedOutput',jsonb_build_object(
        'protectionState','protected_against_zero_excess_recovery',
        'priceResult',v_full_price,
        'currentPlannedRevenue',v_full_current_revenue,
        'wholePoolGrossProfit',v_full_whole_pool_profit,
        'wholePoolGrossMargin',v_full_whole_pool_margin
      )
    ),
    'poolPosition',v_pool,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'costRecoveryBasisIsExplicit',true,
      'futureExcessSaleIsNotRecoveryEvidence',true,
      'onePoolWidePolicyEvaluated',true,
      'requirementPricesAreDerivedNotOffers',true,
      'doesNotPersistPricingPolicy',true,
      'doesNotCreateStandingPrice',true,
      'doesNotCreateOfferSnapshot',true,
      'doesNotCreateOrder',true,
      'doesNotCreateAllocation',true,
      'doesNotCreatePurchase',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotExecute',true
    )
  );
end;
$function$;


revoke all on function atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)
  to service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.work_requirement_pool_price_evaluate_v1(jsonb,jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_pooled_commercial_price_protection_v1","purpose":"Read-only protected pooled pricing from explicit break-bulk economics, explicit cost-recovery basis, and shared pricing law.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_pooled_commercial_price_protection_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_external_acquisition_commitment_v1.sql
-- ============================================================================
create table if not exists atlas.external_acquisition_commitments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  supplier_relationship_id uuid not null
    references atlas.external_relationships(id) on delete restrict,
  commitment_key text not null,
  commitment_kind text not null default 'supplier_order',
  committed_at timestamptz not null,
  expected_fulfillment_from_at timestamptz,
  expected_fulfillment_by_at timestamptz,
  economic_state text not null
    check (economic_state in ('known','partially_known','unresolved')),
  known_committed_amount numeric(14,4)
    check (known_committed_amount is null or known_committed_amount>=0),
  currency text
    check (currency is null or currency ~ '^[A-Z]{3}$'),
  cost_components jsonb not null default '[]'::jsonb
    check (jsonb_typeof(cost_components)='array'),
  accepted_terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(accepted_terms)='object'),
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  authorization_basis jsonb not null
    check (jsonb_typeof(authorization_basis)='object'),
  commitment_sha256 text not null
    check (commitment_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitments_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict,
  constraint external_acquisition_commitments_key_nonblank
    check (btrim(commitment_key)<>''),
  constraint external_acquisition_commitments_kind_nonblank
    check (btrim(commitment_kind)<>''),
  constraint external_acquisition_commitments_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_commitments_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  constraint external_acquisition_commitments_window
    check (
      expected_fulfillment_by_at is null
      or expected_fulfillment_from_at is null
      or expected_fulfillment_by_at>=expected_fulfillment_from_at
    ),
  constraint external_acquisition_commitments_economics_shape
    check (
      (
        economic_state in ('known','partially_known')
        and known_committed_amount is not null
        and currency is not null
      )
      or
      (
        economic_state='unresolved'
        and known_committed_amount is null
      )
    ),
  unique(organization_id,commitment_key)
);

create index if not exists external_acquisition_commitments_supplier_idx
  on atlas.external_acquisition_commitments(
    supplier_relationship_id,committed_at desc,id
  );

comment on table atlas.external_acquisition_commitments is
'Immutable organization buy-side commitment to an external supplier. It records accepted acquisition terms and financial-obligation position but is not Organization Spend, payment, received inventory, sell-side Commercial Order, or supplier execution authority.';


create table if not exists atlas.external_acquisition_commitment_lines (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  line_key text not null,
  external_supply_offering_id uuid not null
    references atlas.external_supply_offerings(id) on delete restrict,
  external_supply_offer_observation_id uuid
    references atlas.external_supply_offer_observations(id) on delete restrict,
  source_line_key text,
  description text not null,
  ordered_quantity numeric(14,3) not null
    check (ordered_quantity>0),
  ordered_unit text not null,
  coverage_output_quantity numeric(14,3) not null
    check (coverage_output_quantity>0),
  coverage_output_unit text not null,
  known_line_amount numeric(14,4)
    check (known_line_amount is null or known_line_amount>=0),
  currency text
    check (currency is null or currency ~ '^[A-Z]{3}$'),
  accepted_terms jsonb not null default '{}'::jsonb
    check (jsonb_typeof(accepted_terms)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitment_lines_key_nonblank
    check (btrim(line_key)<>''),
  constraint external_acquisition_commitment_lines_source_line_nonblank
    check (source_line_key is null or btrim(source_line_key)<>''),
  constraint external_acquisition_commitment_lines_description_nonblank
    check (btrim(description)<>''),
  constraint external_acquisition_commitment_lines_ordered_unit_nonblank
    check (btrim(ordered_unit)<>''),
  constraint external_acquisition_commitment_lines_output_unit_nonblank
    check (btrim(coverage_output_unit)<>''),
  constraint external_acquisition_commitment_lines_amount_currency_pair
    check (
      (known_line_amount is null and currency is null)
      or
      (known_line_amount is not null and currency is not null)
    ),
  unique(external_acquisition_commitment_id,line_key)
);

create index if not exists external_acquisition_commitment_lines_offering_idx
  on atlas.external_acquisition_commitment_lines(
    external_supply_offering_id,external_acquisition_commitment_id
  );

comment on table atlas.external_acquisition_commitment_lines is
'Immutable accepted line of an External Acquisition Commitment. Ordered source quantity remains distinct from planned coverage-output quantity; neither quantity is received inventory.';


create table if not exists atlas.external_acquisition_requirement_allocations (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_line_id uuid not null
    references atlas.external_acquisition_commitment_lines(id) on delete restrict,
  allocation_key text not null,
  work_requirement_id uuid not null
    references atlas.work_requirements(id) on delete restrict,
  coverage_quantity numeric(14,3) not null
    check (coverage_quantity>0),
  coverage_unit text not null,
  qualification_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(qualification_basis)='object'),
  planning_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(planning_basis)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_requirement_allocations_key_nonblank
    check (btrim(allocation_key)<>''),
  constraint external_acquisition_requirement_allocations_unit_nonblank
    check (btrim(coverage_unit)<>''),
  unique(external_acquisition_commitment_line_id,allocation_key),
  unique(external_acquisition_commitment_line_id,work_requirement_id)
);

create index if not exists external_acquisition_requirement_allocations_requirement_idx
  on atlas.external_acquisition_requirement_allocations(
    work_requirement_id,external_acquisition_commitment_line_id
  );

comment on table atlas.external_acquisition_requirement_allocations is
'Immutable source-owned allocation from one committed external acquisition line to one Company Work Requirement. It creates secured external-source coverage while the supplier commitment remains active; it is not a generic coverage row.';


create table if not exists atlas.external_acquisition_commitment_events (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  event_key text not null,
  event_kind text not null
    check (event_kind in ('cancelled','closed')),
  occurred_at timestamptz not null,
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  event_sha256 text not null
    check (event_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_commitment_events_key_nonblank
    check (btrim(event_key)<>''),
  constraint external_acquisition_commitment_events_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_commitment_events_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  unique(external_acquisition_commitment_id,event_key)
);

create index if not exists external_acquisition_commitment_events_position_idx
  on atlas.external_acquisition_commitment_events(
    external_acquisition_commitment_id,occurred_at desc,created_at desc,id
  );

comment on table atlas.external_acquisition_commitment_events is
'Append-only lifecycle evidence for one External Acquisition Commitment. V1 supports cancelled, received, and closed; received hands current coverage to receiving/inventory/performance truth rather than asserting inventory itself.';


create or replace function atlas.guard_external_acquisition_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_relationship atlas.external_relationships%rowtype;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_offering atlas.external_supply_offerings%rowtype;
  v_observation atlas.external_supply_offer_observations%rowtype;
  v_line atlas.external_acquisition_commitment_lines%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_total numeric;
begin
  if tg_table_name='external_acquisition_commitments' then
    select * into v_relationship
    from atlas.external_relationships
    where id=new.supplier_relationship_id;

    if v_relationship.id is null
       or v_relationship.organization_id is distinct from new.organization_id
       or v_relationship.organization_unit_id is distinct from new.organization_unit_id then
      raise exception 'External Acquisition Commitment must share supplier relationship organization/unit scope.'
        using errcode='23514';
    end if;

    if not exists(
      select 1
      from atlas.external_relationship_roles rr
      where rr.external_relationship_id=new.supplier_relationship_id
        and rr.role_key='supplier'
        and rr.role_state='active'
    ) then
      raise exception 'External Acquisition Commitment requires an active supplier relationship role.'
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

    if nullif(btrim(coalesce(new.authorization_basis->>'authorityRef','')),'') is null
       or nullif(btrim(coalesce(new.authorization_basis->>'decisionRef','')),'') is null
       or nullif(btrim(coalesce(new.authorization_basis->>'authorizedAt','')),'') is null then
      raise exception 'External Acquisition Commitment requires authorityRef, decisionRef, and authorizedAt.'
        using errcode='23514';
    end if;

    begin
      perform (new.authorization_basis->>'authorizedAt')::timestamptz;
    exception when others then
      raise exception 'authorizationBasis.authorizedAt must be a valid timestamp.'
        using errcode='23514';
    end;

    new.commitment_key:=btrim(new.commitment_key);
    new.commitment_kind:=lower(btrim(new.commitment_kind));
    new.currency:=case when new.currency is null then null else upper(btrim(new.currency)) end;
    new.source_kind:=lower(btrim(new.source_kind));
    new.source_ref:=nullif(btrim(new.source_ref),'');
    return new;
  end if;

  if tg_table_name='external_acquisition_commitment_lines' then
    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=new.external_acquisition_commitment_id;

    select * into v_offering
    from atlas.external_supply_offerings
    where id=new.external_supply_offering_id;

    if v_commitment.id is null or v_offering.id is null
       or v_offering.organization_id is distinct from v_commitment.organization_id
       or v_offering.organization_unit_id is distinct from v_commitment.organization_unit_id
       or v_offering.supplier_relationship_id is distinct from v_commitment.supplier_relationship_id then
      raise exception 'Acquisition line offering must belong to the same supplier and organization/unit scope.'
        using errcode='23514';
    end if;

    if new.external_supply_offer_observation_id is not null then
      select * into v_observation
      from atlas.external_supply_offer_observations
      where id=new.external_supply_offer_observation_id;

      if v_observation.id is null
         or v_observation.external_supply_offering_id is distinct from new.external_supply_offering_id then
        raise exception 'Accepted supplier observation must belong to the acquisition line offering.'
          using errcode='23514';
      end if;
    end if;

    new.line_key:=btrim(new.line_key);
    new.source_line_key:=nullif(btrim(new.source_line_key),'');
    new.description:=btrim(new.description);
    new.ordered_unit:=lower(btrim(new.ordered_unit));
    new.coverage_output_unit:=lower(btrim(new.coverage_output_unit));
    new.currency:=case when new.currency is null then null else upper(btrim(new.currency)) end;

    if new.currency is not null
       and v_commitment.currency is not null
       and new.currency is distinct from v_commitment.currency then
      raise exception 'Acquisition line currency must match commitment currency in V1.'
        using errcode='23514';
    end if;

    return new;
  end if;

  if tg_table_name='external_acquisition_requirement_allocations' then
    select * into v_line
    from atlas.external_acquisition_commitment_lines
    where id=new.external_acquisition_commitment_line_id;

    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=v_line.external_acquisition_commitment_id;

    select * into v_requirement
    from atlas.work_requirements
    where id=new.work_requirement_id;

    if v_line.id is null or v_commitment.id is null or v_requirement.id is null
       or v_requirement.organization_id is distinct from v_commitment.organization_id
       or (
         v_commitment.organization_unit_id is not null
         and v_requirement.organization_unit_id is distinct from v_commitment.organization_unit_id
       ) then
      raise exception 'Acquisition allocation must remain inside the commitment organization scope.'
        using errcode='23514';
    end if;

    if v_requirement.state<>'active' then
      raise exception 'Acquisition allocation requires an active Company Work Requirement.'
        using errcode='23514';
    end if;

    if jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
       or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
      raise exception 'Acquisition allocation requires a quantified Company Work Requirement.'
        using errcode='23514';
    end if;

    new.allocation_key:=btrim(new.allocation_key);
    new.coverage_unit:=lower(btrim(new.coverage_unit));

    if new.coverage_unit is distinct from v_line.coverage_output_unit
       or new.coverage_unit is distinct from lower(btrim(v_requirement.metadata->'commercialFulfillment'->>'unit')) then
      raise exception 'Acquisition allocation unit must match both line coverage-output unit and Work Requirement unit.'
        using errcode='23514';
    end if;

    if new.coverage_quantity>(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric then
      raise exception 'Acquisition allocation cannot exceed the Work Requirement total quantity.'
        using errcode='23514';
    end if;

    select coalesce(sum(a.coverage_quantity),0)
    into v_total
    from atlas.external_acquisition_requirement_allocations a
    where a.external_acquisition_commitment_line_id=new.external_acquisition_commitment_line_id;

    if v_total+new.coverage_quantity>v_line.coverage_output_quantity then
      raise exception 'Acquisition allocations cannot exceed line coverage-output quantity.'
        using errcode='23514';
    end if;

    return new;
  end if;

  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=new.external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  if new.connected_source_observation_id is not null
     and not exists(
       select 1
       from atlas.connected_source_observations cso
       join atlas.connected_sources cs on cs.id=cso.connected_source_id
       where cso.id=new.connected_source_observation_id
         and cs.custodian_organization_id=v_commitment.organization_id
         and (
           cs.custodian_organization_unit_id is null
           or cs.custodian_organization_unit_id is not distinct from v_commitment.organization_unit_id
         )
     ) then
    raise exception 'Commitment event connected-source observation must share organization/unit scope.'
      using errcode='23514';
  end if;

  new.event_key:=btrim(new.event_key);
  new.source_kind:=lower(btrim(new.source_kind));
  new.source_ref:=nullif(btrim(new.source_ref),'');
  return new;
end;
$function$;


drop trigger if exists external_acquisition_commitments_scope_guard_v1
  on atlas.external_acquisition_commitments;
create trigger external_acquisition_commitments_scope_guard_v1
before insert on atlas.external_acquisition_commitments
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_commitment_lines_scope_guard_v1
  on atlas.external_acquisition_commitment_lines;
create trigger external_acquisition_commitment_lines_scope_guard_v1
before insert on atlas.external_acquisition_commitment_lines
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_requirement_allocations_scope_guard_v1
  on atlas.external_acquisition_requirement_allocations;
create trigger external_acquisition_requirement_allocations_scope_guard_v1
before insert on atlas.external_acquisition_requirement_allocations
for each row execute function atlas.guard_external_acquisition_scope_v1();

drop trigger if exists external_acquisition_commitment_events_scope_guard_v1
  on atlas.external_acquisition_commitment_events;
create trigger external_acquisition_commitment_events_scope_guard_v1
before insert on atlas.external_acquisition_commitment_events
for each row execute function atlas.guard_external_acquisition_scope_v1();


create or replace function atlas.prevent_external_acquisition_history_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'External Acquisition Commitment history is immutable; record later lifecycle evidence instead.'
    using errcode='55000';
end;
$function$;

drop trigger if exists external_acquisition_commitments_immutable_v1
  on atlas.external_acquisition_commitments;
create trigger external_acquisition_commitments_immutable_v1
before update or delete on atlas.external_acquisition_commitments
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_commitment_lines_immutable_v1
  on atlas.external_acquisition_commitment_lines;
create trigger external_acquisition_commitment_lines_immutable_v1
before update or delete on atlas.external_acquisition_commitment_lines
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_requirement_allocations_immutable_v1
  on atlas.external_acquisition_requirement_allocations;
create trigger external_acquisition_requirement_allocations_immutable_v1
before update or delete on atlas.external_acquisition_requirement_allocations
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();

drop trigger if exists external_acquisition_commitment_events_immutable_v1
  on atlas.external_acquisition_commitment_events;
create trigger external_acquisition_commitment_events_immutable_v1
before update or delete on atlas.external_acquisition_commitment_events
for each row execute function atlas.prevent_external_acquisition_history_mutation_v1();


create or replace function atlas.external_acquisition_commitment_preview_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_org_id uuid;
  v_unit_id uuid;
  v_supplier_id uuid;
  v_relationship atlas.external_relationships%rowtype;
  v_commitment_key text;
  v_commitment_kind text;
  v_committed_at timestamptz;
  v_from_at timestamptz;
  v_by_at timestamptz;
  v_authorized_at timestamptz;
  v_economics jsonb;
  v_economic_state text;
  v_known_amount numeric;
  v_currency text;
  v_cost_components jsonb;
  v_cost jsonb;
  v_cost_state text;
  v_cost_required boolean;
  v_unresolved_required_cost_count integer:=0;
  v_source jsonb;
  v_source_kind text;
  v_line jsonb;
  v_alloc jsonb;
  v_offering atlas.external_supply_offerings%rowtype;
  v_observation atlas.external_supply_offer_observations%rowtype;
  v_requirement atlas.work_requirements%rowtype;
  v_line_keys text[]:='{}'::text[];
  v_alloc_keys text[];
  v_alloc_requirement_ids uuid[];
  v_line_key text;
  v_alloc_key text;
  v_offering_id uuid;
  v_observation_id uuid;
  v_requirement_id uuid;
  v_ordered_quantity numeric;
  v_ordered_unit text;
  v_output_quantity numeric;
  v_output_unit text;
  v_alloc_quantity numeric;
  v_alloc_unit text;
  v_alloc_total numeric;
  v_line_count integer:=0;
  v_allocation_count integer:=0;
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_hash text;
  v_existing atlas.external_acquisition_commitments%rowtype;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    return jsonb_build_object(
      'contractVersion','external_acquisition_commitment_preview_v1',
      'state','blocked',
      'violations',jsonb_build_array(jsonb_build_object('key','input_not_object'))
    );
  end if;

  if p_input->>'contractVersion'<>'external_acquisition_commitment_input_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version'
    ));
  end if;

  begin
    v_org_id:=(p_input->>'organizationId')::uuid;
  exception when others then
    v_org_id:=null;
  end;

  begin
    v_unit_id:=nullif(btrim(coalesce(p_input->>'organizationUnitId','')),'')::uuid;
  exception when others then
    v_unit_id:=null;
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_organization_unit_id'
    ));
  end;

  begin
    v_supplier_id:=(p_input->>'supplierRelationshipId')::uuid;
  exception when others then
    v_supplier_id:=null;
  end;

  if v_org_id is null or not exists(select 1 from atlas.organizations where id=v_org_id) then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_organization_id'
    ));
  end if;

  select * into v_relationship
  from atlas.external_relationships
  where id=v_supplier_id;

  if v_relationship.id is null
     or v_relationship.organization_id is distinct from v_org_id
     or v_relationship.organization_unit_id is distinct from v_unit_id
     or not exists(
       select 1 from atlas.external_relationship_roles rr
       where rr.external_relationship_id=v_supplier_id
         and rr.role_key='supplier'
         and rr.role_state='active'
     ) then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_supplier_scope_or_role'
    ));
  end if;

  v_commitment_key:=nullif(btrim(coalesce(p_input->>'commitmentKey','')),'');
  v_commitment_kind:=nullif(lower(btrim(coalesce(p_input->>'commitmentKind','supplier_order'))),'');
  if v_commitment_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_commitment_key'));
  end if;
  if v_commitment_kind is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_commitment_kind'));
  end if;

  begin
    v_committed_at:=(p_input->>'committedAt')::timestamptz;
  exception when others then
    v_committed_at:=null;
  end;
  if v_committed_at is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_committed_at'));
  end if;

  if nullif(btrim(coalesce(p_input->>'expectedFulfillmentFromAt','')),'') is not null then
    begin
      v_from_at:=(p_input->>'expectedFulfillmentFromAt')::timestamptz;
    exception when others then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_expected_fulfillment_from'));
    end;
  end if;

  if nullif(btrim(coalesce(p_input->>'expectedFulfillmentByAt','')),'') is not null then
    begin
      v_by_at:=(p_input->>'expectedFulfillmentByAt')::timestamptz;
    exception when others then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_expected_fulfillment_by'));
    end;
  end if;

  if v_from_at is not null and v_by_at is not null and v_by_at<v_from_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_fulfillment_window'));
  end if;

  if jsonb_typeof(p_input->'acceptedTerms')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_accepted_terms'));
  end if;

  if jsonb_typeof(p_input->'authorizationBasis')<>'object'
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'authorityRef','')),'') is null
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'decisionRef','')),'') is null
     or nullif(btrim(coalesce(p_input->'authorizationBasis'->>'authorizedAt','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_authorization_basis'));
  else
    begin
      v_authorized_at:=(p_input->'authorizationBasis'->>'authorizedAt')::timestamptz;
    exception when others then
      v_authorized_at:=null;
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_authorized_at'));
    end;
  end if;

  if v_authorized_at is not null
     and v_committed_at is not null
     and v_authorized_at>v_committed_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','authorization_after_commitment',
      'authorizedAt',v_authorized_at,
      'committedAt',v_committed_at
    ));
  end if;

  v_economics:=p_input->'economics';
  if v_economics is null or jsonb_typeof(v_economics)<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_economics'));
  else
    v_economic_state:=lower(btrim(coalesce(v_economics->>'state','')));
    if v_economic_state not in ('known','partially_known','unresolved') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_economic_state'));
    end if;

    if v_economics ? 'knownCommittedAmount' and v_economics->'knownCommittedAmount'<>'null'::jsonb then
      if jsonb_typeof(v_economics->'knownCommittedAmount')<>'number' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_known_committed_amount'));
      else
        v_known_amount:=(v_economics->>'knownCommittedAmount')::numeric;
        if v_known_amount<0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','negative_known_committed_amount'));
        end if;
      end if;
    end if;

    v_currency:=nullif(upper(btrim(coalesce(v_economics->>'currency',''))),'');
    if v_currency is not null and v_currency !~ '^[A-Z]{3}$' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_currency'));
    end if;

    if v_economic_state in ('known','partially_known')
       and (v_known_amount is null or v_currency is null) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','known_economics_missing_amount_or_currency'));
    end if;

    if v_economic_state='unresolved' and v_known_amount is not null then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','unresolved_economics_has_amount'));
    end if;

    v_cost_components:=coalesce(v_economics->'costComponents','[]'::jsonb);
    if jsonb_typeof(v_cost_components)<>'array' then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_cost_components'));
    else
      for v_cost in select value from jsonb_array_elements(v_cost_components)
      loop
        if jsonb_typeof(v_cost)<>'object'
           or nullif(btrim(coalesce(v_cost->>'componentKey','')),'') is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_cost_component'));
          continue;
        end if;

        v_cost_state:=lower(btrim(coalesce(v_cost->>'state','')));
        if v_cost_state not in ('known','unresolved','not_applicable') then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_cost_component_state',
            'componentKey',v_cost->>'componentKey'
          ));
          continue;
        end if;

        if v_cost ? 'required' then
          if jsonb_typeof(v_cost->'required')<>'boolean' then
            v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
              'key','invalid_cost_component_required',
              'componentKey',v_cost->>'componentKey'
            ));
            v_cost_required:=true;
          else
            v_cost_required:=(v_cost->>'required')::boolean;
          end if;
        else
          v_cost_required:=true;
        end if;

        if v_cost_state='known' then
          if jsonb_typeof(v_cost->'amount')<>'number'
             or (v_cost->>'amount')::numeric<0
             or upper(btrim(coalesce(v_cost->>'currency',''))) !~ '^[A-Z]{3}
  end if;

  v_source:=p_input->'source';
  if v_source is null or jsonb_typeof(v_source)<>'object'
     or nullif(btrim(coalesce(v_source->>'kind','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_source'));
  else
    v_source_kind:=lower(btrim(v_source->>'kind'));
  end if;

  if p_input ? 'metadata' and jsonb_typeof(p_input->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_metadata'));
  end if;

  if jsonb_typeof(p_input->'lines')<>'array'
     or jsonb_array_length(coalesce(p_input->'lines','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_lines'));
  else
    for v_line in select value from jsonb_array_elements(p_input->'lines')
    loop
      v_line_count:=v_line_count+1;
      v_alloc_total:=0;
      v_alloc_keys:='{}'::text[];
      v_alloc_requirement_ids:='{}'::uuid[];
      v_offering_id:=null;
      v_observation_id:=null;
      v_ordered_quantity:=null;
      v_ordered_unit:=null;
      v_output_quantity:=null;
      v_output_unit:=null;

      if jsonb_typeof(v_line)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_not_object','lineIndex',v_line_count));
        continue;
      end if;

      v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
      if v_line_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_line_key','lineIndex',v_line_count));
        continue;
      elsif v_line_key=any(v_line_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_line_key','lineKey',v_line_key));
        continue;
      else
        v_line_keys:=array_append(v_line_keys,v_line_key);
      end if;

      begin
        v_offering_id:=(v_line->>'externalSupplyOfferingId')::uuid;
      exception when others then
        v_offering_id:=null;
      end;

      select * into v_offering
      from atlas.external_supply_offerings
      where id=v_offering_id;

      if v_offering.id is null
         or v_offering.organization_id is distinct from v_org_id
         or v_offering.organization_unit_id is distinct from v_unit_id
         or v_offering.supplier_relationship_id is distinct from v_supplier_id then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_offering','lineKey',v_line_key));
      end if;

      v_observation_id:=null;
      if nullif(btrim(coalesce(v_line->>'externalSupplyOfferObservationId','')),'') is not null then
        begin
          v_observation_id:=(v_line->>'externalSupplyOfferObservationId')::uuid;
        exception when others then
          v_observation_id:=null;
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_observation_id','lineKey',v_line_key));
        end;

        select * into v_observation
        from atlas.external_supply_offer_observations
        where id=v_observation_id;

        if v_observation.id is null
           or v_observation.external_supply_offering_id is distinct from v_offering_id then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_observation_wrong_offering','lineKey',v_line_key));
        end if;
      end if;

      if jsonb_typeof(v_line->'orderedQuantity')<>'number'
         or (v_line->>'orderedQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_ordered_quantity','lineKey',v_line_key));
      else
        v_ordered_quantity:=(v_line->>'orderedQuantity')::numeric;
      end if;

      v_ordered_unit:=nullif(lower(btrim(coalesce(v_line->>'orderedUnit',''))),'');
      if v_ordered_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_ordered_unit','lineKey',v_line_key));
      end if;

      if jsonb_typeof(v_line->'coverageOutputQuantity')<>'number'
         or (v_line->>'coverageOutputQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_coverage_output_quantity','lineKey',v_line_key));
      else
        v_output_quantity:=(v_line->>'coverageOutputQuantity')::numeric;
      end if;

      v_output_unit:=nullif(lower(btrim(coalesce(v_line->>'coverageOutputUnit',''))),'');
      if v_output_unit is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_coverage_output_unit','lineKey',v_line_key));
      end if;

      if nullif(btrim(coalesce(v_line->>'description','')),'') is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_line_description','lineKey',v_line_key));
      end if;

      if v_line ? 'knownLineAmount' and v_line->'knownLineAmount'<>'null'::jsonb then
        if jsonb_typeof(v_line->'knownLineAmount')<>'number'
           or (v_line->>'knownLineAmount')::numeric<0
           or nullif(upper(btrim(coalesce(v_line->>'currency',''))),'') is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_amount','lineKey',v_line_key));
        elsif v_currency is not null
           and upper(btrim(v_line->>'currency'))<>v_currency then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_currency_mismatch','lineKey',v_line_key));
        end if;
      elsif v_line ? 'currency' and nullif(btrim(coalesce(v_line->>'currency','')),'') is not null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','line_currency_without_amount','lineKey',v_line_key));
      end if;

      if v_line ? 'acceptedTerms' and jsonb_typeof(v_line->'acceptedTerms')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_terms','lineKey',v_line_key));
      end if;
      if v_line ? 'metadata' and jsonb_typeof(v_line->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_line_metadata','lineKey',v_line_key));
      end if;

      if v_line ? 'allocations' then
        if jsonb_typeof(v_line->'allocations')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocations','lineKey',v_line_key));
        else
          for v_alloc in select value from jsonb_array_elements(v_line->'allocations')
          loop
            v_allocation_count:=v_allocation_count+1;
            v_requirement_id:=null;
            v_alloc_quantity:=null;
            v_alloc_unit:=null;
            if jsonb_typeof(v_alloc)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_not_object','lineKey',v_line_key));
              continue;
            end if;

            v_alloc_key:=nullif(btrim(coalesce(v_alloc->>'allocationKey','')),'');
            if v_alloc_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','missing_allocation_key','lineKey',v_line_key));
              continue;
            elsif v_alloc_key=any(v_alloc_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_allocation_key','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            else
              v_alloc_keys:=array_append(v_alloc_keys,v_alloc_key);
            end if;

            begin
              v_requirement_id:=(v_alloc->>'workRequirementId')::uuid;
            exception when others then
              v_requirement_id:=null;
            end;

            if v_requirement_id is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_work_requirement_id','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            elsif v_requirement_id=any(v_alloc_requirement_ids) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','duplicate_line_work_requirement','lineKey',v_line_key,'workRequirementId',v_requirement_id));
              continue;
            else
              v_alloc_requirement_ids:=array_append(v_alloc_requirement_ids,v_requirement_id);
            end if;

            select * into v_requirement
            from atlas.work_requirements
            where id=v_requirement_id;

            if v_requirement.id is null
               or v_requirement.organization_id is distinct from v_org_id
               or (
                 v_unit_id is not null
                 and v_requirement.organization_unit_id is distinct from v_unit_id
               )
               or v_requirement.state<>'active'
               or jsonb_typeof(v_requirement.metadata->'commercialFulfillment'->'quantity')<>'number'
               or nullif(btrim(coalesce(v_requirement.metadata->'commercialFulfillment'->>'unit','')),'') is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_requirement','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            end if;

            if jsonb_typeof(v_alloc->'coverageQuantity')<>'number'
               or (v_alloc->>'coverageQuantity')::numeric<=0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_quantity','lineKey',v_line_key,'allocationKey',v_alloc_key));
              continue;
            else
              v_alloc_quantity:=(v_alloc->>'coverageQuantity')::numeric;
            end if;

            v_alloc_unit:=nullif(lower(btrim(coalesce(v_alloc->>'coverageUnit',''))),'');
            if v_alloc_unit is null
               or v_alloc_unit is distinct from v_output_unit
               or v_alloc_unit is distinct from lower(btrim(v_requirement.metadata->'commercialFulfillment'->>'unit')) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_unit_mismatch','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            if v_alloc_quantity>(v_requirement.metadata->'commercialFulfillment'->>'quantity')::numeric then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','allocation_exceeds_requirement','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            if v_alloc ? 'qualificationBasis' and jsonb_typeof(v_alloc->'qualificationBasis')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_qualification_basis','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;
            if v_alloc ? 'planningBasis' and jsonb_typeof(v_alloc->'planningBasis')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_planning_basis','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;
            if v_alloc ? 'metadata' and jsonb_typeof(v_alloc->'metadata')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invalid_allocation_metadata','lineKey',v_line_key,'allocationKey',v_alloc_key));
            end if;

            v_alloc_total:=v_alloc_total+v_alloc_quantity;
          end loop;
        end if;
      end if;

      if v_output_quantity is not null and v_alloc_total>v_output_quantity then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocations_exceed_line_output',
          'lineKey',v_line_key,
          'allocatedQuantity',v_alloc_total,
          'coverageOutputQuantity',v_output_quantity
        ));
      end if;
    end loop;
  end if;

  v_hash:=encode(
    extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_org_id is not null and v_commitment_key is not null then
    select * into v_existing
    from atlas.external_acquisition_commitments
    where organization_id=v_org_id
      and commitment_key=v_commitment_key;

    if v_existing.id is not null
       and v_existing.commitment_sha256 is distinct from v_hash then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','existing_commitment_conflicts',
        'existingExternalAcquisitionCommitmentId',v_existing.id
      ));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'organizationId',v_org_id,
    'organizationUnitId',v_unit_id,
    'supplierRelationshipId',v_supplier_id,
    'commitmentKey',v_commitment_key,
    'commitmentKind',v_commitment_kind,
    'committedAt',v_committed_at,
    'economicState',v_economic_state,
    'knownCommittedAmount',v_known_amount,
    'currency',v_currency,
    'lineCount',v_line_count,
    'allocationCount',v_allocation_count,
    'commitmentSha256',v_hash,
    'existingExternalAcquisitionCommitmentId',v_existing.id,
    'existingCompatible',(v_existing.id is not null and v_existing.commitment_sha256=v_hash),
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotCreateCommitment',true,
      'doesNotCreateSpend',true,
      'doesNotCreateInventory',true,
      'doesNotCreatePayment',true,
      'doesNotExecuteSupplierAction',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_commitment_service_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_commitment_id uuid;
  v_line_id uuid;
  v_line jsonb;
  v_alloc jsonb;
  v_economics jsonb;
  v_source jsonb;
begin
  v_preview:=atlas.external_acquisition_commitment_preview_v1(p_input);

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1 from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_commitment_conflicts'
    ) then
      raise exception 'External Acquisition Commitment key conflicts with different structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'External Acquisition Commitment input is blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  if nullif(v_preview->>'existingExternalAcquisitionCommitmentId','') is not null then
    return jsonb_build_object(
      'contractVersion','record_external_acquisition_commitment_service_v1',
      'externalAcquisitionCommitmentId',(v_preview->>'existingExternalAcquisitionCommitmentId')::uuid,
      'created',false,
      'commitmentSha256',v_preview->>'commitmentSha256'
    );
  end if;

  v_economics:=p_input->'economics';
  v_source:=p_input->'source';

  insert into atlas.external_acquisition_commitments(
    organization_id,organization_unit_id,supplier_relationship_id,
    commitment_key,commitment_kind,committed_at,
    expected_fulfillment_from_at,expected_fulfillment_by_at,
    economic_state,known_committed_amount,currency,cost_components,
    accepted_terms,source_kind,source_ref,evidence_record_id,
    connected_source_observation_id,authorization_basis,
    commitment_sha256,metadata
  ) values (
    (p_input->>'organizationId')::uuid,
    nullif(p_input->>'organizationUnitId','')::uuid,
    (p_input->>'supplierRelationshipId')::uuid,
    btrim(p_input->>'commitmentKey'),
    lower(btrim(coalesce(p_input->>'commitmentKind','supplier_order'))),
    (p_input->>'committedAt')::timestamptz,
    nullif(p_input->>'expectedFulfillmentFromAt','')::timestamptz,
    nullif(p_input->>'expectedFulfillmentByAt','')::timestamptz,
    lower(btrim(v_economics->>'state')),
    case when v_economics->'knownCommittedAmount' is null
              or v_economics->'knownCommittedAmount'='null'::jsonb
         then null else (v_economics->>'knownCommittedAmount')::numeric end,
    nullif(upper(btrim(coalesce(v_economics->>'currency',''))),''),
    coalesce(v_economics->'costComponents','[]'::jsonb),
    coalesce(p_input->'acceptedTerms','{}'::jsonb),
    lower(btrim(v_source->>'kind')),
    nullif(btrim(v_source->>'ref'),''),
    nullif(v_source->>'evidenceRecordId','')::uuid,
    nullif(v_source->>'connectedSourceObservationId','')::uuid,
    p_input->'authorizationBasis',
    v_preview->>'commitmentSha256',
    coalesce(p_input->'metadata','{}'::jsonb)
  )
  returning id into v_commitment_id;

  for v_line in select value from jsonb_array_elements(p_input->'lines')
  loop
    insert into atlas.external_acquisition_commitment_lines(
      external_acquisition_commitment_id,line_key,
      external_supply_offering_id,external_supply_offer_observation_id,
      source_line_key,description,ordered_quantity,ordered_unit,
      coverage_output_quantity,coverage_output_unit,
      known_line_amount,currency,accepted_terms,metadata
    ) values (
      v_commitment_id,
      btrim(v_line->>'lineKey'),
      (v_line->>'externalSupplyOfferingId')::uuid,
      nullif(v_line->>'externalSupplyOfferObservationId','')::uuid,
      nullif(btrim(v_line->>'sourceLineKey'),''),
      btrim(v_line->>'description'),
      (v_line->>'orderedQuantity')::numeric,
      lower(btrim(v_line->>'orderedUnit')),
      (v_line->>'coverageOutputQuantity')::numeric,
      lower(btrim(v_line->>'coverageOutputUnit')),
      case when v_line->'knownLineAmount' is null
                or v_line->'knownLineAmount'='null'::jsonb
           then null else (v_line->>'knownLineAmount')::numeric end,
      nullif(upper(btrim(coalesce(v_line->>'currency',''))),''),
      coalesce(v_line->'acceptedTerms','{}'::jsonb),
      coalesce(v_line->'metadata','{}'::jsonb)
    )
    returning id into v_line_id;

    if jsonb_typeof(coalesce(v_line->'allocations','[]'::jsonb))='array' then
      for v_alloc in select value from jsonb_array_elements(coalesce(v_line->'allocations','[]'::jsonb))
      loop
        insert into atlas.external_acquisition_requirement_allocations(
          external_acquisition_commitment_line_id,allocation_key,
          work_requirement_id,coverage_quantity,coverage_unit,
          qualification_basis,planning_basis,metadata
        ) values (
          v_line_id,
          btrim(v_alloc->>'allocationKey'),
          (v_alloc->>'workRequirementId')::uuid,
          (v_alloc->>'coverageQuantity')::numeric,
          lower(btrim(v_alloc->>'coverageUnit')),
          coalesce(v_alloc->'qualificationBasis','{}'::jsonb),
          coalesce(v_alloc->'planningBasis','{}'::jsonb),
          coalesce(v_alloc->'metadata','{}'::jsonb)
        );
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_commitment_service_v1',
    'externalAcquisitionCommitmentId',v_commitment_id,
    'created',true,
    'commitmentSha256',v_preview->>'commitmentSha256',
    'position',atlas.external_acquisition_commitment_position_v1(v_commitment_id),
    'truthBoundary',jsonb_build_object(
      'createsBuySideCommitment',true,
      'createsRequirementAllocations',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateInventory',true,
      'doesNotCreateCommercialOrder',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotExecuteSupplierAction',true
    )
  );
end;
$function$;


create or replace function atlas.external_acquisition_commitment_position_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_event atlas.external_acquisition_commitment_events%rowtype;
  v_state text;
  v_lines jsonb;
  v_events jsonb;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  select * into v_latest_event
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id
  order by e.occurred_at desc,e.created_at desc,e.id desc
  limit 1;

  v_state:=coalesce(v_latest_event.event_kind,'committed');

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentLineId',l.id,
        'lineKey',l.line_key,
        'externalSupplyOfferingId',l.external_supply_offering_id,
        'externalSupplyOfferObservationId',l.external_supply_offer_observation_id,
        'sourceLineKey',l.source_line_key,
        'description',l.description,
        'orderedQuantity',l.ordered_quantity,
        'orderedUnit',l.ordered_unit,
        'coverageOutputQuantity',l.coverage_output_quantity,
        'coverageOutputUnit',l.coverage_output_unit,
        'knownLineAmount',l.known_line_amount,
        'currency',l.currency,
        'acceptedTerms',l.accepted_terms,
        'committedAllocatedCoverageQuantity',coalesce(x.allocated_quantity,0),
        'unallocatedCoverageOutputQuantity',
          l.coverage_output_quantity-coalesce(x.allocated_quantity,0),
        'allocations',coalesce(x.allocations,'[]'::jsonb)
      )
      order by l.line_key,l.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_commitment_lines l
  left join lateral (
    select
      sum(a.coverage_quantity) as allocated_quantity,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionRequirementAllocationId',a.id,
          'allocationKey',a.allocation_key,
          'workRequirementId',a.work_requirement_id,
          'coverageQuantity',a.coverage_quantity,
          'coverageUnit',a.coverage_unit,
          'qualificationBasis',a.qualification_basis,
          'planningBasis',a.planning_basis,
          'metadata',a.metadata
        )
        order by a.allocation_key,a.id
      ) as allocations
    from atlas.external_acquisition_requirement_allocations a
    where a.external_acquisition_commitment_line_id=l.id
  ) x on true
  where l.external_acquisition_commitment_id=v_commitment.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentEventId',e.id,
        'eventKey',e.event_key,
        'eventKind',e.event_kind,
        'occurredAt',e.occurred_at,
        'sourceKind',e.source_kind,
        'sourceRef',e.source_ref,
        'metadata',e.metadata
      )
      order by e.occurred_at,e.created_at,e.id
    ),
    '[]'::jsonb
  )
  into v_events
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_position_v1',
    'externalAcquisitionCommitmentId',v_commitment.id,
    'organizationId',v_commitment.organization_id,
    'organizationUnitId',v_commitment.organization_unit_id,
    'supplierRelationshipId',v_commitment.supplier_relationship_id,
    'commitmentKey',v_commitment.commitment_key,
    'commitmentKind',v_commitment.commitment_kind,
    'committedAt',v_commitment.committed_at,
    'expectedFulfillmentFromAt',v_commitment.expected_fulfillment_from_at,
    'expectedFulfillmentByAt',v_commitment.expected_fulfillment_by_at,
    'state',v_state,
    'terminalBasis',case
      when v_state in ('cancelled','closed') then 'cancelled'
      else null
    end,
    'economicState',v_commitment.economic_state,
    'knownCommittedAmount',v_commitment.known_committed_amount,
    'currency',v_commitment.currency,
    'costComponents',v_commitment.cost_components,
    'acceptedTerms',v_commitment.accepted_terms,
    'authorizationBasis',v_commitment.authorization_basis,
    'source',jsonb_build_object(
      'kind',v_commitment.source_kind,
      'ref',v_commitment.source_ref,
      'evidenceRecordId',v_commitment.evidence_record_id,
      'connectedSourceObservationId',v_commitment.connected_source_observation_id
    ),
    'lines',v_lines,
    'events',v_events,
    'metadata',v_commitment.metadata,
    'truthBoundary',jsonb_build_object(
      'buySideCommitment',true,
      'actualFulfillmentOwnedByLaterFulfillmentAuthority',true,
      'notSpend',true,
      'notPayment',true,
      'notInventory',true,
      'notCommercialOrder',true
    )
  );
end;
$function$;

create or replace function atlas.record_external_acquisition_commitment_event_service_v1(
  p_external_acquisition_commitment_id uuid,
  p_event_key text,
  p_event_kind text,
  p_occurred_at timestamptz,
  p_source jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_position jsonb;
  v_current_state text;
  v_kind text:=lower(btrim(coalesce(p_event_kind,'')));
  v_key text:=btrim(coalesce(p_event_key,''));
  v_source_kind text;
  v_hash text;
  v_existing atlas.external_acquisition_commitment_events%rowtype;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_at timestamptz;
  v_id uuid;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  if v_key='' or v_kind not in ('cancelled','closed') or p_occurred_at is null then
    raise exception 'Event key, cancelled/closed event kind, and occurred time are required.'
      using errcode='22023';
  end if;

  if p_source is null or jsonb_typeof(p_source)<>'object'
     or nullif(btrim(coalesce(p_source->>'kind','')),'') is null then
    raise exception 'Event source requires a nonblank kind.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Event metadata must be an object.'
      using errcode='22023';
  end if;

  v_source_kind:=lower(btrim(p_source->>'kind'));

  v_hash:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
          'eventKey',v_key,
          'eventKind',v_kind,
          'occurredAt',p_occurred_at,
          'source',p_source,
          'metadata',p_metadata
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into v_existing
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id
    and e.event_key=v_key;

  if v_existing.id is not null then
    if v_existing.event_sha256 is distinct from v_hash then
      raise exception 'External Acquisition Commitment event key conflicts with different truth.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','record_external_acquisition_commitment_event_service_v1',
      'externalAcquisitionCommitmentEventId',v_existing.id,
      'created',false,
      'position',atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id)
    );
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id);
  v_current_state:=v_position->>'state';

  if not (
    (v_current_state='committed' and v_kind='cancelled')
    or
    (v_current_state='cancelled' and v_kind='closed')
  ) then
    raise exception 'Invalid External Acquisition Commitment transition: % -> %.',
      v_current_state,v_kind
      using errcode='23514';
  end if;

  select max(e.occurred_at)
  into v_latest_at
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id;

  if p_occurred_at<v_commitment.committed_at
     or (v_latest_at is not null and p_occurred_at<v_latest_at) then
    raise exception 'External Acquisition Commitment events must not precede commitment time or prior lifecycle evidence.'
      using errcode='23514';
  end if;

  insert into atlas.external_acquisition_commitment_events(
    external_acquisition_commitment_id,event_key,event_kind,occurred_at,
    source_kind,source_ref,evidence_record_id,connected_source_observation_id,
    event_sha256,metadata
  ) values (
    p_external_acquisition_commitment_id,v_key,v_kind,p_occurred_at,
    v_source_kind,
    nullif(btrim(p_source->>'ref'),''),
    nullif(p_source->>'evidenceRecordId','')::uuid,
    nullif(p_source->>'connectedSourceObservationId','')::uuid,
    v_hash,p_metadata
  )
  returning id into v_id;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_commitment_event_service_v1',
    'externalAcquisitionCommitmentEventId',v_id,
    'created',true,
    'position',atlas.external_acquisition_commitment_position_v1(p_external_acquisition_commitment_id)
  );
end;
$function$;

create or replace function atlas.external_acquisition_commitment_coverage_facts_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_position jsonb;
  v_state text;
  v_facts jsonb;
begin
  v_position:=atlas.external_acquisition_commitment_position_v1(
    p_external_acquisition_commitment_id
  );
  v_state:=v_position->>'state';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'workRequirementId',a.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition_commitment_residual:'||a.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_requirement_allocation',
            'sourceRef',a.id::text
          ),
          'state',case when v_state in ('cancelled','closed')
            then 'released'
            else 'secured'
          end,
          'quantity',a.coverage_quantity,
          'unit',a.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_commitment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionCommitmentLineId',
              a.external_acquisition_commitment_line_id,
            'externalAcquisitionRequirementAllocationId',a.id
          )),
          'metadata',jsonb_build_object(
            'coverageLayer','remaining_supplier_commitment',
            'commitmentState',v_state
          )
        )
      )
      order by a.work_requirement_id,a.allocation_key,a.id
    ),
    '[]'::jsonb
  )
  into v_facts
  from atlas.external_acquisition_requirement_allocations a
  join atlas.external_acquisition_commitment_lines l
    on l.id=a.external_acquisition_commitment_line_id
  where l.external_acquisition_commitment_id=p_external_acquisition_commitment_id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_coverage_facts_v1',
    'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
    'commitmentState',v_state,
    'coverageMode','split_commitment_and_accepted_fulfillment',
    'facts',v_facts,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'preFulfillmentCoverageIsResidualSupplierCommitmentOnly',true,
      'actualFulfillmentOwnedByLaterFulfillmentAuthority',true,
      'doesNotCreateCoverageRow',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true
    )
  );
end;
$function$;

alter table atlas.external_acquisition_commitments enable row level security;
alter table atlas.external_acquisition_commitment_lines enable row level security;
alter table atlas.external_acquisition_requirement_allocations enable row level security;
alter table atlas.external_acquisition_commitment_events enable row level security;

revoke all on atlas.external_acquisition_commitments
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_commitment_lines
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_requirement_allocations
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_commitment_events
  from public,anon,authenticated,service_role;

grant select on atlas.external_acquisition_commitments to service_role;
grant select on atlas.external_acquisition_commitment_lines to service_role;
grant select on atlas.external_acquisition_requirement_allocations to service_role;
grant select on atlas.external_acquisition_commitment_events to service_role;

revoke all on function atlas.external_acquisition_commitment_preview_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_preview_v1(jsonb)
  to service_role;

revoke all on function atlas.record_external_acquisition_commitment_service_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_commitment_service_v1(jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_commitment_position_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_position_v1(uuid)
  to service_role;

revoke all on function atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_commitment_coverage_facts_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_commitment_coverage_facts_v1(uuid)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'external_acquisition_commitment',
  'commercial_supply',
  'What external acquisition has this organization actually committed to, on what accepted terms, for what financial obligation, and which Company Work requirements does it currently secure?',
  'external_acquisition_commitments + lines + requirement allocations + events',
  'canonical',
  array[
    'atlas.external_acquisition_commitments',
    'atlas.external_acquisition_commitment_lines',
    'atlas.external_acquisition_requirement_allocations',
    'atlas.external_acquisition_commitment_events'
  ],
  array[
    'atlas.external_acquisition_commitment_preview_v1',
    'atlas.record_external_acquisition_commitment_service_v1',
    'atlas.external_acquisition_commitment_position_v1',
    'atlas.record_external_acquisition_commitment_event_service_v1',
    'atlas.external_acquisition_commitment_coverage_facts_v1'
  ],
  array[
    'atlas.external_relationships',
    'atlas.external_relationship_roles',
    'atlas.external_supply_offerings',
    'atlas.external_supply_offer_observations',
    'atlas.work_requirements',
    'atlas.evidence_records',
    'atlas.connected_source_observations'
  ],
  array[]::text[],
  array[
    'atlas.commercial_orders',
    'atlas.organization_spend_occurrences',
    'atlas.flower_ready_inventory_lots',
    'atlas.production_capacity_reservations'
  ],
  'External Acquisition Commitment owns accepted buy-side supplier commitment and source-owned requirement allocation. Supplier observations remain proposed source terms; Organization Spend remains occurred outlay; receiving/inventory remains post-receipt truth.',
  'Fills the missing buy-side commitment seam needed to turn an authorized fulfillment plan into secured source coverage without pretending planning is purchasing or purchasing is Spend.',
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
  'atlas.external_acquisition_commitment_preview_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Read-only validation of an authorized buy-side supplier commitment packet before persistence.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_commitment_service_v1(jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Persist immutable external supplier acquisition commitment, lines, and source-owned Company Work allocations; creates no Spend or inventory.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_commitment_position_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Read current lifecycle/economic position for one External Acquisition Commitment.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_commitment_event_service_v1(uuid,text,text,timestamptz,jsonb,jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Append governed cancellation/receipt/closure lifecycle evidence to one External Acquisition Commitment.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_commitment_coverage_facts_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_commitment_v1","purpose":"Emit normalized source-owned Company Work coverage facts from committed external acquisition allocations.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_external_acquisition_commitment_v1.sql
-- ============================================================================

-- ============================================================================
-- BEGIN candidates/atlas_external_acquisition_fulfillment_intake_v1.sql
-- ============================================================================
create table if not exists atlas.external_acquisition_fulfillments (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_commitment_id uuid not null
    references atlas.external_acquisition_commitments(id) on delete restrict,
  fulfillment_key text not null,
  fulfillment_kind text not null
    check (fulfillment_kind in ('delivery','service_performance','other')),
  occurred_at timestamptz not null,
  source_kind text not null,
  source_ref text,
  evidence_record_id uuid
    references atlas.evidence_records(id) on delete restrict,
  connected_source_observation_id uuid
    references atlas.connected_source_observations(id) on delete restrict,
  fulfillment_sha256 text not null
    check (fulfillment_sha256 ~ '^[0-9a-f]{64}$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillments_key_nonblank
    check (btrim(fulfillment_key)<>''),
  constraint external_acquisition_fulfillments_source_kind_nonblank
    check (btrim(source_kind)<>''),
  constraint external_acquisition_fulfillments_source_ref_nonblank
    check (source_ref is null or btrim(source_ref)<>''),
  unique(external_acquisition_commitment_id,fulfillment_key)
);

create index if not exists external_acquisition_fulfillments_commitment_idx
  on atlas.external_acquisition_fulfillments(
    external_acquisition_commitment_id,occurred_at,id
  );

comment on table atlas.external_acquisition_fulfillments is
'Immutable actual external supplier delivery/performance occurrence against one External Acquisition Commitment. It is not inventory, Spend, payment, internal Company Work execution, or customer fulfillment.';


create table if not exists atlas.external_acquisition_fulfillment_lines (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_fulfillment_id uuid not null
    references atlas.external_acquisition_fulfillments(id) on delete restrict,
  line_key text not null,
  external_acquisition_commitment_line_id uuid not null
    references atlas.external_acquisition_commitment_lines(id) on delete restrict,
  source_quantity numeric(14,3)
    check (source_quantity is null or source_quantity>0),
  source_unit text,
  delivered_output_quantity numeric(14,3) not null
    check (delivered_output_quantity>0),
  accepted_output_quantity numeric(14,3) not null default 0
    check (accepted_output_quantity>=0),
  rejected_output_quantity numeric(14,3) not null default 0
    check (rejected_output_quantity>=0),
  unresolved_output_quantity numeric(14,3) not null default 0
    check (unresolved_output_quantity>=0),
  coverage_output_unit text not null,
  condition jsonb not null default '{}'::jsonb
    check (jsonb_typeof(condition)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillment_lines_key_nonblank
    check (btrim(line_key)<>''),
  constraint external_acquisition_fulfillment_lines_source_pair
    check (
      (source_quantity is null and source_unit is null)
      or
      (
        source_quantity is not null
        and source_unit is not null
        and btrim(source_unit)<>''
      )
    ),
  constraint external_acquisition_fulfillment_lines_output_unit_nonblank
    check (btrim(coverage_output_unit)<>''),
  constraint external_acquisition_fulfillment_lines_partition
    check (
      delivered_output_quantity =
        accepted_output_quantity
        + rejected_output_quantity
        + unresolved_output_quantity
    ),
  unique(external_acquisition_fulfillment_id,line_key)
);

create index if not exists external_acquisition_fulfillment_lines_commitment_line_idx
  on atlas.external_acquisition_fulfillment_lines(
    external_acquisition_commitment_line_id,external_acquisition_fulfillment_id
  );

comment on table atlas.external_acquisition_fulfillment_lines is
'Actual delivered/performed coverage-output quantity and receiving assessment against one acquisition commitment line. Accepted, rejected, and unresolved quantities partition delivered output. Actual overdelivery is preserved rather than capped.';


create table if not exists atlas.external_acquisition_fulfillment_allocations (
  id uuid primary key default gen_random_uuid(),
  external_acquisition_fulfillment_line_id uuid not null
    references atlas.external_acquisition_fulfillment_lines(id) on delete restrict,
  allocation_key text not null,
  external_acquisition_requirement_allocation_id uuid not null
    references atlas.external_acquisition_requirement_allocations(id) on delete restrict,
  accepted_coverage_quantity numeric(14,3) not null
    check (accepted_coverage_quantity>0),
  coverage_unit text not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  constraint external_acquisition_fulfillment_allocations_key_nonblank
    check (btrim(allocation_key)<>''),
  constraint external_acquisition_fulfillment_allocations_unit_nonblank
    check (btrim(coverage_unit)<>''),
  unique(external_acquisition_fulfillment_line_id,allocation_key),
  unique(
    external_acquisition_fulfillment_line_id,
    external_acquisition_requirement_allocation_id
  )
);

create index if not exists external_acquisition_fulfillment_allocations_commitment_allocation_idx
  on atlas.external_acquisition_fulfillment_allocations(
    external_acquisition_requirement_allocation_id,
    external_acquisition_fulfillment_line_id
  );

comment on table atlas.external_acquisition_fulfillment_allocations is
'Immutable allocation of accepted external supplier output to one prior External Acquisition Requirement Allocation. It transfers only accepted quantity from supplier-commitment coverage to actual-fulfillment coverage.';


create or replace function atlas.guard_external_acquisition_fulfillment_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_fulfillment atlas.external_acquisition_fulfillments%rowtype;
  v_commitment_line atlas.external_acquisition_commitment_lines%rowtype;
  v_fulfillment_line atlas.external_acquisition_fulfillment_lines%rowtype;
  v_commitment_allocation atlas.external_acquisition_requirement_allocations%rowtype;
  v_current_state text;
  v_total_line_allocated numeric;
  v_total_commitment_allocated numeric;
begin
  if tg_table_name='external_acquisition_fulfillments' then
    select * into v_commitment
    from atlas.external_acquisition_commitments
    where id=new.external_acquisition_commitment_id;

    if v_commitment.id is null then
      raise exception 'External Acquisition Commitment not found.'
        using errcode='P0002';
    end if;

    v_current_state:=atlas.external_acquisition_commitment_position_v1(v_commitment.id)->>'state';

    if v_current_state in ('cancelled','closed') then
      raise exception 'Cannot record supplier fulfillment against a cancelled or closed acquisition commitment.'
        using errcode='23514';
    end if;

    if new.occurred_at<v_commitment.committed_at then
      raise exception 'External supplier fulfillment cannot predate acquisition commitment.'
        using errcode='23514';
    end if;

    if new.connected_source_observation_id is not null
       and not exists(
         select 1
         from atlas.connected_source_observations cso
         join atlas.connected_sources cs on cs.id=cso.connected_source_id
         where cso.id=new.connected_source_observation_id
           and cs.custodian_organization_id=v_commitment.organization_id
           and (
             cs.custodian_organization_unit_id is null
             or cs.custodian_organization_unit_id
                is not distinct from v_commitment.organization_unit_id
           )
       ) then
      raise exception 'Fulfillment connected-source observation must share commitment organization/unit scope.'
        using errcode='23514';
    end if;

    new.fulfillment_key:=btrim(new.fulfillment_key);
    new.fulfillment_kind:=lower(btrim(new.fulfillment_kind));
    new.source_kind:=lower(btrim(new.source_kind));
    new.source_ref:=nullif(btrim(new.source_ref),'');
    return new;
  end if;

  if tg_table_name='external_acquisition_fulfillment_lines' then
    select * into v_fulfillment
    from atlas.external_acquisition_fulfillments
    where id=new.external_acquisition_fulfillment_id;

    select * into v_commitment_line
    from atlas.external_acquisition_commitment_lines
    where id=new.external_acquisition_commitment_line_id;

    if v_fulfillment.id is null
       or v_commitment_line.id is null
       or v_commitment_line.external_acquisition_commitment_id
          is distinct from v_fulfillment.external_acquisition_commitment_id then
      raise exception 'External fulfillment line must belong to a commitment line from the same acquisition commitment.'
        using errcode='23514';
    end if;

    new.line_key:=btrim(new.line_key);
    new.source_unit:=nullif(lower(btrim(new.source_unit)),'');
    new.coverage_output_unit:=lower(btrim(new.coverage_output_unit));

    if new.coverage_output_unit is distinct from v_commitment_line.coverage_output_unit then
      raise exception 'External fulfillment line output unit must match acquisition commitment line output unit.'
        using errcode='23514';
    end if;

    return new;
  end if;

  select * into v_fulfillment_line
  from atlas.external_acquisition_fulfillment_lines
  where id=new.external_acquisition_fulfillment_line_id;

  select * into v_commitment_allocation
  from atlas.external_acquisition_requirement_allocations
  where id=new.external_acquisition_requirement_allocation_id;

  if v_fulfillment_line.id is null
     or v_commitment_allocation.id is null
     or v_commitment_allocation.external_acquisition_commitment_line_id
        is distinct from v_fulfillment_line.external_acquisition_commitment_line_id then
    raise exception 'Fulfillment allocation must reference a requirement allocation from the same acquisition commitment line.'
      using errcode='23514';
  end if;

  new.allocation_key:=btrim(new.allocation_key);
  new.coverage_unit:=lower(btrim(new.coverage_unit));

  if new.coverage_unit is distinct from v_fulfillment_line.coverage_output_unit
     or new.coverage_unit is distinct from v_commitment_allocation.coverage_unit then
    raise exception 'Fulfillment allocation unit must match both fulfillment output and commitment allocation unit.'
      using errcode='23514';
  end if;

  select coalesce(sum(a.accepted_coverage_quantity),0)
  into v_total_line_allocated
  from atlas.external_acquisition_fulfillment_allocations a
  where a.external_acquisition_fulfillment_line_id=new.external_acquisition_fulfillment_line_id;

  if v_total_line_allocated+new.accepted_coverage_quantity
     >v_fulfillment_line.accepted_output_quantity then
    raise exception 'Fulfillment allocations cannot exceed accepted output quantity.'
      using errcode='23514';
  end if;

  select coalesce(sum(a.accepted_coverage_quantity),0)
  into v_total_commitment_allocated
  from atlas.external_acquisition_fulfillment_allocations a
  where a.external_acquisition_requirement_allocation_id
        =new.external_acquisition_requirement_allocation_id;

  if v_total_commitment_allocated+new.accepted_coverage_quantity
     >v_commitment_allocation.coverage_quantity then
    raise exception 'Cumulative accepted fulfillment allocation cannot exceed original acquisition requirement allocation.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;


drop trigger if exists external_acquisition_fulfillments_scope_guard_v1
  on atlas.external_acquisition_fulfillments;
create trigger external_acquisition_fulfillments_scope_guard_v1
before insert on atlas.external_acquisition_fulfillments
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();

drop trigger if exists external_acquisition_fulfillment_lines_scope_guard_v1
  on atlas.external_acquisition_fulfillment_lines;
create trigger external_acquisition_fulfillment_lines_scope_guard_v1
before insert on atlas.external_acquisition_fulfillment_lines
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();

drop trigger if exists external_acquisition_fulfillment_allocations_scope_guard_v1
  on atlas.external_acquisition_fulfillment_allocations;
create trigger external_acquisition_fulfillment_allocations_scope_guard_v1
before insert on atlas.external_acquisition_fulfillment_allocations
for each row execute function atlas.guard_external_acquisition_fulfillment_scope_v1();


create or replace function atlas.prevent_external_acquisition_fulfillment_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'External Acquisition Fulfillment history is immutable; record later source truth instead.'
    using errcode='55000';
end;
$function$;

drop trigger if exists external_acquisition_fulfillments_immutable_v1
  on atlas.external_acquisition_fulfillments;
create trigger external_acquisition_fulfillments_immutable_v1
before update or delete on atlas.external_acquisition_fulfillments
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();

drop trigger if exists external_acquisition_fulfillment_lines_immutable_v1
  on atlas.external_acquisition_fulfillment_lines;
create trigger external_acquisition_fulfillment_lines_immutable_v1
before update or delete on atlas.external_acquisition_fulfillment_lines
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();

drop trigger if exists external_acquisition_fulfillment_allocations_immutable_v1
  on atlas.external_acquisition_fulfillment_allocations;
create trigger external_acquisition_fulfillment_allocations_immutable_v1
before update or delete on atlas.external_acquisition_fulfillment_allocations
for each row execute function atlas.prevent_external_acquisition_fulfillment_mutation_v1();


create or replace function atlas.external_acquisition_fulfillment_position_v1(
  p_external_acquisition_fulfillment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_f atlas.external_acquisition_fulfillments%rowtype;
  v_lines jsonb;
begin
  select * into v_f
  from atlas.external_acquisition_fulfillments
  where id=p_external_acquisition_fulfillment_id;

  if v_f.id is null then
    raise exception 'External Acquisition Fulfillment not found.'
      using errcode='P0002';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionFulfillmentLineId',fl.id,
        'lineKey',fl.line_key,
        'externalAcquisitionCommitmentLineId',fl.external_acquisition_commitment_line_id,
        'sourceQuantity',fl.source_quantity,
        'sourceUnit',fl.source_unit,
        'deliveredOutputQuantity',fl.delivered_output_quantity,
        'acceptedOutputQuantity',fl.accepted_output_quantity,
        'rejectedOutputQuantity',fl.rejected_output_quantity,
        'unresolvedOutputQuantity',fl.unresolved_output_quantity,
        'coverageOutputUnit',fl.coverage_output_unit,
        'conditionState',case
          when fl.unresolved_output_quantity>0 then 'unresolved'
          when fl.accepted_output_quantity>0 and fl.rejected_output_quantity>0 then 'mixed'
          when fl.rejected_output_quantity>0 then 'rejected'
          else 'accepted'
        end,
        'condition',fl.condition,
        'acceptedAllocatedQuantity',coalesce(x.allocated_quantity,0),
        'acceptedUnallocatedQuantity',
          fl.accepted_output_quantity-coalesce(x.allocated_quantity,0),
        'allocations',coalesce(x.allocations,'[]'::jsonb),
        'metadata',fl.metadata
      )
      order by fl.line_key,fl.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_fulfillment_lines fl
  left join lateral (
    select
      sum(fa.accepted_coverage_quantity) as allocated_quantity,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionFulfillmentAllocationId',fa.id,
          'allocationKey',fa.allocation_key,
          'externalAcquisitionRequirementAllocationId',
            fa.external_acquisition_requirement_allocation_id,
          'acceptedCoverageQuantity',fa.accepted_coverage_quantity,
          'coverageUnit',fa.coverage_unit,
          'metadata',fa.metadata
        )
        order by fa.allocation_key,fa.id
      ) as allocations
    from atlas.external_acquisition_fulfillment_allocations fa
    where fa.external_acquisition_fulfillment_line_id=fl.id
  ) x on true
  where fl.external_acquisition_fulfillment_id=v_f.id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_position_v1',
    'externalAcquisitionFulfillmentId',v_f.id,
    'externalAcquisitionCommitmentId',v_f.external_acquisition_commitment_id,
    'fulfillmentKey',v_f.fulfillment_key,
    'fulfillmentKind',v_f.fulfillment_kind,
    'occurredAt',v_f.occurred_at,
    'source',jsonb_build_object(
      'kind',v_f.source_kind,
      'ref',v_f.source_ref,
      'evidenceRecordId',v_f.evidence_record_id,
      'connectedSourceObservationId',v_f.connected_source_observation_id
    ),
    'lines',v_lines,
    'metadata',v_f.metadata,
    'truthBoundary',jsonb_build_object(
      'actualExternalFulfillment',true,
      'notInventory',true,
      'notSpend',true,
      'notPayment',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.external_acquisition_commitment_position_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_event atlas.external_acquisition_commitment_events%rowtype;
  v_has_cancelled boolean:=false;
  v_has_closed boolean:=false;
  v_state text;
  v_terminal_basis text;
  v_lines jsonb;
  v_events jsonb;
  v_fulfillments jsonb;
  v_fulfillment_count integer:=0;
  v_any_unresolved boolean:=false;
  v_any_remaining boolean:=false;
  v_any_rejected boolean:=false;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  select exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='cancelled'
  ) into v_has_cancelled;

  select exists(
    select 1 from atlas.external_acquisition_commitment_events e
    where e.external_acquisition_commitment_id=v_commitment.id
      and e.event_kind='closed'
  ) into v_has_closed;

  select * into v_latest_event
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id
  order by e.occurred_at desc,e.created_at desc,e.id desc
  limit 1;

  select count(*) into v_fulfillment_count
  from atlas.external_acquisition_fulfillments f
  where f.external_acquisition_commitment_id=v_commitment.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentLineId',l.id,
        'lineKey',l.line_key,
        'externalSupplyOfferingId',l.external_supply_offering_id,
        'externalSupplyOfferObservationId',l.external_supply_offer_observation_id,
        'sourceLineKey',l.source_line_key,
        'description',l.description,
        'orderedQuantity',l.ordered_quantity,
        'orderedUnit',l.ordered_unit,
        'coverageOutputQuantity',l.coverage_output_quantity,
        'coverageOutputUnit',l.coverage_output_unit,
        'knownLineAmount',l.known_line_amount,
        'currency',l.currency,
        'acceptedTerms',l.accepted_terms,
        'committedAllocatedCoverageQuantity',coalesce(a.committed_allocated,0),
        'deliveredOutputQuantity',coalesce(f.delivered,0),
        'acceptedOutputQuantity',coalesce(f.accepted,0),
        'rejectedOutputQuantity',coalesce(f.rejected,0),
        'unresolvedOutputQuantity',coalesce(f.unresolved,0),
        'acceptedAllocatedQuantity',coalesce(f.accepted_allocated,0),
        'acceptedUnallocatedQuantity',
          greatest(coalesce(f.accepted,0)-coalesce(f.accepted_allocated,0),0),
        'remainingExpectedOutputQuantity',
          greatest(l.coverage_output_quantity-coalesce(f.delivered,0),0),
        'overdeliveredOutputQuantity',
          greatest(coalesce(f.delivered,0)-l.coverage_output_quantity,0),
        'fulfillmentState',case
          when coalesce(f.unresolved,0)>0 then 'unresolved'
          when coalesce(f.delivered,0)<l.coverage_output_quantity then
            case when coalesce(f.delivered,0)=0 then 'not_fulfilled' else 'partial' end
          when coalesce(f.rejected,0)>0 then 'fulfilled_with_exception'
          else 'fulfilled'
        end,
        'allocations',coalesce(a.allocations,'[]'::jsonb)
      )
      order by l.line_key,l.id
    ),
    '[]'::jsonb
  )
  into v_lines
  from atlas.external_acquisition_commitment_lines l
  left join lateral (
    select
      sum(ra.coverage_quantity) as committed_allocated,
      jsonb_agg(
        jsonb_build_object(
          'externalAcquisitionRequirementAllocationId',ra.id,
          'allocationKey',ra.allocation_key,
          'workRequirementId',ra.work_requirement_id,
          'coverageQuantity',ra.coverage_quantity,
          'coverageUnit',ra.coverage_unit,
          'acceptedFulfilledQuantity',coalesce(ff.accepted_fulfilled,0),
          'remainingSupplierCommitmentQuantity',
            greatest(ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),0)
        )
        order by ra.allocation_key,ra.id
      ) as allocations
    from atlas.external_acquisition_requirement_allocations ra
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_fulfilled
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_requirement_allocation_id=ra.id
    ) ff on true
    where ra.external_acquisition_commitment_line_id=l.id
  ) a on true
  left join lateral (
    select
      sum(fl.delivered_output_quantity) as delivered,
      sum(fl.accepted_output_quantity) as accepted,
      sum(fl.rejected_output_quantity) as rejected,
      sum(fl.unresolved_output_quantity) as unresolved,
      sum(coalesce(z.accepted_allocated,0)) as accepted_allocated
    from atlas.external_acquisition_fulfillment_lines fl
    join atlas.external_acquisition_fulfillments ef
      on ef.id=fl.external_acquisition_fulfillment_id
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_allocated
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_fulfillment_line_id=fl.id
    ) z on true
    where ef.external_acquisition_commitment_id=v_commitment.id
      and fl.external_acquisition_commitment_line_id=l.id
  ) f on true
  where l.external_acquisition_commitment_id=v_commitment.id;

  select
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'unresolvedOutputQuantity')::numeric>0
    ),
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'remainingExpectedOutputQuantity')::numeric>0
    ),
    exists(
      select 1 from jsonb_array_elements(v_lines) x
      where (x->>'rejectedOutputQuantity')::numeric>0
    )
  into v_any_unresolved,v_any_remaining,v_any_rejected;

  if v_has_closed then
    v_state:='closed';
    v_terminal_basis:=case when v_has_cancelled then 'cancelled' else 'fulfilled' end;
  elsif v_has_cancelled then
    v_state:='cancelled';
    v_terminal_basis:='cancelled';
  elsif v_fulfillment_count=0 then
    v_state:='committed';
  elsif v_any_unresolved then
    v_state:='fulfillment_unresolved';
  elsif v_any_remaining then
    v_state:='partially_fulfilled';
  elsif v_any_rejected then
    v_state:='fulfilled_with_exception';
  else
    v_state:='fulfilled';
    v_terminal_basis:='fulfilled';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionCommitmentEventId',e.id,
        'eventKey',e.event_key,
        'eventKind',e.event_kind,
        'occurredAt',e.occurred_at,
        'sourceKind',e.source_kind,
        'sourceRef',e.source_ref,
        'metadata',e.metadata
      )
      order by e.occurred_at,e.created_at,e.id
    ),
    '[]'::jsonb
  )
  into v_events
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=v_commitment.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'externalAcquisitionFulfillmentId',f.id,
        'fulfillmentKey',f.fulfillment_key,
        'fulfillmentKind',f.fulfillment_kind,
        'occurredAt',f.occurred_at
      )
      order by f.occurred_at,f.id
    ),
    '[]'::jsonb
  )
  into v_fulfillments
  from atlas.external_acquisition_fulfillments f
  where f.external_acquisition_commitment_id=v_commitment.id;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_position_v1',
    'externalAcquisitionCommitmentId',v_commitment.id,
    'organizationId',v_commitment.organization_id,
    'organizationUnitId',v_commitment.organization_unit_id,
    'supplierRelationshipId',v_commitment.supplier_relationship_id,
    'commitmentKey',v_commitment.commitment_key,
    'commitmentKind',v_commitment.commitment_kind,
    'committedAt',v_commitment.committed_at,
    'expectedFulfillmentFromAt',v_commitment.expected_fulfillment_from_at,
    'expectedFulfillmentByAt',v_commitment.expected_fulfillment_by_at,
    'state',v_state,
    'terminalBasis',v_terminal_basis,
    'economicState',v_commitment.economic_state,
    'knownCommittedAmount',v_commitment.known_committed_amount,
    'currency',v_commitment.currency,
    'costComponents',v_commitment.cost_components,
    'acceptedTerms',v_commitment.accepted_terms,
    'authorizationBasis',v_commitment.authorization_basis,
    'source',jsonb_build_object(
      'kind',v_commitment.source_kind,
      'ref',v_commitment.source_ref,
      'evidenceRecordId',v_commitment.evidence_record_id,
      'connectedSourceObservationId',v_commitment.connected_source_observation_id
    ),
    'lines',v_lines,
    'fulfillments',v_fulfillments,
    'events',v_events,
    'metadata',v_commitment.metadata,
    'truthBoundary',jsonb_build_object(
      'buySideCommitment',true,
      'fulfillmentStateDerivedFromActualIntake',true,
      'notSpend',true,
      'notPayment',true,
      'notInventory',true,
      'notCommercialOrder',true
    )
  );
end;
$function$;


create or replace function atlas.external_acquisition_fulfillment_preview_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_commitment_id uuid;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_commitment_position jsonb;
  v_key text;
  v_kind text;
  v_occurred_at timestamptz;
  v_source jsonb;
  v_source_kind text;
  v_line jsonb;
  v_alloc jsonb;
  v_commitment_line atlas.external_acquisition_commitment_lines%rowtype;
  v_commitment_allocation atlas.external_acquisition_requirement_allocations%rowtype;
  v_line_key text;
  v_line_id uuid;
  v_alloc_key text;
  v_alloc_id uuid;
  v_source_quantity numeric;
  v_source_unit text;
  v_delivered numeric;
  v_accepted numeric;
  v_rejected numeric;
  v_unresolved numeric;
  v_output_unit text;
  v_alloc_quantity numeric;
  v_alloc_unit text;
  v_line_allocated numeric;
  v_prior_allocation_quantity numeric;
  v_prior_delivered numeric;
  v_line_keys text[]:='{}'::text[];
  v_alloc_keys text[];
  v_alloc_ids uuid[];
  v_line_count integer:=0;
  v_allocation_count integer:=0;
  v_violations jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_hash text;
  v_existing atlas.external_acquisition_fulfillments%rowtype;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    return jsonb_build_object(
      'contractVersion','external_acquisition_fulfillment_preview_v1',
      'state','blocked',
      'violations',jsonb_build_array(jsonb_build_object('key','input_not_object'))
    );
  end if;

  if p_input->>'contractVersion'<>'external_acquisition_fulfillment_input_v1' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version'
    ));
  end if;

  begin
    v_commitment_id:=(p_input->>'externalAcquisitionCommitmentId')::uuid;
  exception when others then
    v_commitment_id:=null;
  end;

  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=v_commitment_id;

  if v_commitment.id is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_external_acquisition_commitment_id'
    ));
  else
    v_commitment_position:=atlas.external_acquisition_commitment_position_v1(v_commitment.id);
    if v_commitment_position->>'state' in ('cancelled','closed') then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','commitment_not_open',
        'commitmentState',v_commitment_position->>'state'
      ));
    end if;
  end if;

  v_key:=nullif(btrim(coalesce(p_input->>'fulfillmentKey','')),'');
  if v_key is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_fulfillment_key'
    ));
  end if;

  v_kind:=lower(btrim(coalesce(p_input->>'fulfillmentKind','')));
  if v_kind not in ('delivery','service_performance','other') then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_fulfillment_kind'
    ));
  end if;

  begin
    v_occurred_at:=(p_input->>'occurredAt')::timestamptz;
  exception when others then
    v_occurred_at:=null;
  end;

  if v_occurred_at is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_occurred_at'
    ));
  elsif v_commitment.id is not null
     and v_occurred_at<v_commitment.committed_at then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','fulfillment_predates_commitment'
    ));
  end if;

  v_source:=p_input->'source';
  if v_source is null
     or jsonb_typeof(v_source)<>'object'
     or nullif(btrim(coalesce(v_source->>'kind','')),'') is null then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_source'
    ));
  else
    v_source_kind:=lower(btrim(v_source->>'kind'));
  end if;

  if p_input ? 'metadata' and jsonb_typeof(p_input->'metadata')<>'object' then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','invalid_metadata'
    ));
  end if;

  if jsonb_typeof(p_input->'lines')<>'array'
     or jsonb_array_length(coalesce(p_input->'lines','[]'::jsonb))=0 then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
      'key','missing_lines'
    ));
  else
    for v_line in select value from jsonb_array_elements(p_input->'lines')
    loop
      v_line_count:=v_line_count+1;
      v_line_allocated:=0;
      v_alloc_keys:='{}'::text[];
      v_alloc_ids:='{}'::uuid[];
      v_line_id:=null;
      v_source_quantity:=null;
      v_source_unit:=null;
      v_delivered:=null;
      v_accepted:=null;
      v_rejected:=null;
      v_unresolved:=null;
      v_output_unit:=null;

      if jsonb_typeof(v_line)<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','line_not_object',
          'lineIndex',v_line_count
        ));
        continue;
      end if;

      v_line_key:=nullif(btrim(coalesce(v_line->>'lineKey','')),'');
      if v_line_key is null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','missing_line_key',
          'lineIndex',v_line_count
        ));
        continue;
      elsif v_line_key=any(v_line_keys) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','duplicate_line_key',
          'lineKey',v_line_key
        ));
        continue;
      end if;
      v_line_keys:=array_append(v_line_keys,v_line_key);

      begin
        v_line_id:=(v_line->>'externalAcquisitionCommitmentLineId')::uuid;
      exception when others then
        v_line_id:=null;
      end;

      select * into v_commitment_line
      from atlas.external_acquisition_commitment_lines
      where id=v_line_id;

      if v_commitment_line.id is null
         or v_commitment_line.external_acquisition_commitment_id
            is distinct from v_commitment_id then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_commitment_line',
          'lineKey',v_line_key
        ));
        continue;
      end if;

      if v_line ? 'sourceQuantity'
         and v_line->'sourceQuantity'<>'null'::jsonb then
        if jsonb_typeof(v_line->'sourceQuantity')<>'number'
           or (v_line->>'sourceQuantity')::numeric<=0 then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_source_quantity',
            'lineKey',v_line_key
          ));
        else
          v_source_quantity:=(v_line->>'sourceQuantity')::numeric;
        end if;
        v_source_unit:=nullif(lower(btrim(coalesce(v_line->>'sourceUnit',''))),'');
        if v_source_unit is null then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','source_quantity_without_unit',
            'lineKey',v_line_key
          ));
        end if;
      elsif nullif(btrim(coalesce(v_line->>'sourceUnit','')),'') is not null then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','source_unit_without_quantity',
          'lineKey',v_line_key
        ));
      end if;

      if jsonb_typeof(v_line->'deliveredOutputQuantity')<>'number'
         or (v_line->>'deliveredOutputQuantity')::numeric<=0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_delivered_output_quantity',
          'lineKey',v_line_key
        ));
        continue;
      end if;
      v_delivered:=(v_line->>'deliveredOutputQuantity')::numeric;

      if jsonb_typeof(v_line->'acceptedOutputQuantity')<>'number'
         or (v_line->>'acceptedOutputQuantity')::numeric<0
         or jsonb_typeof(v_line->'rejectedOutputQuantity')<>'number'
         or (v_line->>'rejectedOutputQuantity')::numeric<0
         or jsonb_typeof(v_line->'unresolvedOutputQuantity')<>'number'
         or (v_line->>'unresolvedOutputQuantity')::numeric<0 then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_output_partition',
          'lineKey',v_line_key
        ));
        continue;
      end if;

      v_accepted:=(v_line->>'acceptedOutputQuantity')::numeric;
      v_rejected:=(v_line->>'rejectedOutputQuantity')::numeric;
      v_unresolved:=(v_line->>'unresolvedOutputQuantity')::numeric;

      if v_accepted+v_rejected+v_unresolved<>v_delivered then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_partition_mismatch',
          'lineKey',v_line_key,
          'deliveredOutputQuantity',v_delivered,
          'partitionTotal',v_accepted+v_rejected+v_unresolved
        ));
      end if;

      v_output_unit:=nullif(lower(btrim(coalesce(v_line->>'coverageOutputUnit',''))),'');
      if v_output_unit is null
         or v_output_unit is distinct from v_commitment_line.coverage_output_unit then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','output_unit_mismatch',
          'lineKey',v_line_key
        ));
      end if;

      if v_line ? 'condition' and jsonb_typeof(v_line->'condition')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_condition',
          'lineKey',v_line_key
        ));
      end if;

      if v_line ? 'metadata' and jsonb_typeof(v_line->'metadata')<>'object' then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','invalid_line_metadata',
          'lineKey',v_line_key
        ));
      end if;

      select coalesce(sum(fl.delivered_output_quantity),0)
      into v_prior_delivered
      from atlas.external_acquisition_fulfillment_lines fl
      join atlas.external_acquisition_fulfillments f
        on f.id=fl.external_acquisition_fulfillment_id
      where f.external_acquisition_commitment_id=v_commitment_id
        and fl.external_acquisition_commitment_line_id=v_line_id;

      if v_prior_delivered+v_delivered
         >v_commitment_line.coverage_output_quantity then
        v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object(
          'key','actual_overdelivery',
          'lineKey',v_line_key,
          'committedCoverageOutputQuantity',
            v_commitment_line.coverage_output_quantity,
          'cumulativeDeliveredOutputQuantity',
            v_prior_delivered+v_delivered
        ));
      end if;

      if v_line ? 'allocations' then
        if jsonb_typeof(v_line->'allocations')<>'array' then
          v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
            'key','invalid_allocations',
            'lineKey',v_line_key
          ));
        else
          for v_alloc in
            select value from jsonb_array_elements(v_line->'allocations')
          loop
            v_allocation_count:=v_allocation_count+1;
            v_alloc_id:=null;
            v_alloc_quantity:=null;
            v_alloc_unit:=null;

            if jsonb_typeof(v_alloc)<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','allocation_not_object',
                'lineKey',v_line_key
              ));
              continue;
            end if;

            v_alloc_key:=nullif(btrim(coalesce(v_alloc->>'allocationKey','')),'');
            if v_alloc_key is null then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','missing_allocation_key',
                'lineKey',v_line_key
              ));
              continue;
            elsif v_alloc_key=any(v_alloc_keys) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','duplicate_allocation_key',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_keys:=array_append(v_alloc_keys,v_alloc_key);

            begin
              v_alloc_id:=(v_alloc->>'externalAcquisitionRequirementAllocationId')::uuid;
            exception when others then
              v_alloc_id:=null;
            end;

            if v_alloc_id is null or v_alloc_id=any(v_alloc_ids) then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key',case when v_alloc_id is null
                  then 'invalid_commitment_allocation_id'
                  else 'duplicate_commitment_allocation_in_fulfillment_line'
                end,
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_ids:=array_append(v_alloc_ids,v_alloc_id);

            select * into v_commitment_allocation
            from atlas.external_acquisition_requirement_allocations
            where id=v_alloc_id;

            if v_commitment_allocation.id is null
               or v_commitment_allocation.external_acquisition_commitment_line_id
                  is distinct from v_line_id then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','commitment_allocation_wrong_line',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;

            if jsonb_typeof(v_alloc->'acceptedCoverageQuantity')<>'number'
               or (v_alloc->>'acceptedCoverageQuantity')::numeric<=0 then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_accepted_coverage_quantity',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
              continue;
            end if;
            v_alloc_quantity:=(v_alloc->>'acceptedCoverageQuantity')::numeric;

            v_alloc_unit:=nullif(lower(btrim(coalesce(v_alloc->>'coverageUnit',''))),'');
            if v_alloc_unit is null
               or v_alloc_unit is distinct from v_output_unit
               or v_alloc_unit is distinct from v_commitment_allocation.coverage_unit then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','allocation_unit_mismatch',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
            end if;

            select coalesce(sum(fa.accepted_coverage_quantity),0)
            into v_prior_allocation_quantity
            from atlas.external_acquisition_fulfillment_allocations fa
            where fa.external_acquisition_requirement_allocation_id=v_alloc_id;

            if v_prior_allocation_quantity+v_alloc_quantity
               >v_commitment_allocation.coverage_quantity then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','cumulative_fulfillment_exceeds_commitment_allocation',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key,
                'priorAcceptedFulfillmentQuantity',v_prior_allocation_quantity,
                'proposedAcceptedFulfillmentQuantity',v_alloc_quantity,
                'committedAllocationQuantity',v_commitment_allocation.coverage_quantity
              ));
            end if;

            if v_alloc ? 'metadata'
               and jsonb_typeof(v_alloc->'metadata')<>'object' then
              v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
                'key','invalid_allocation_metadata',
                'lineKey',v_line_key,
                'allocationKey',v_alloc_key
              ));
            end if;

            v_line_allocated:=v_line_allocated+v_alloc_quantity;
          end loop;
        end if;
      end if;

      if v_line_allocated>v_accepted then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','allocations_exceed_accepted_output',
          'lineKey',v_line_key,
          'acceptedOutputQuantity',v_accepted,
          'allocatedQuantity',v_line_allocated
        ));
      end if;
    end loop;
  end if;

  v_hash:=encode(
    extensions.digest(convert_to(p_input::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_commitment_id is not null and v_key is not null then
    select * into v_existing
    from atlas.external_acquisition_fulfillments
    where external_acquisition_commitment_id=v_commitment_id
      and fulfillment_key=v_key;

    if v_existing.id is not null
       and v_existing.fulfillment_sha256 is distinct from v_hash then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
        'key','existing_fulfillment_conflicts',
        'existingExternalAcquisitionFulfillmentId',v_existing.id
      ));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','external_acquisition_fulfillment_preview_v1',
    'state',case when jsonb_array_length(v_violations)=0 then 'ready' else 'blocked' end,
    'externalAcquisitionCommitmentId',v_commitment_id,
    'fulfillmentKey',v_key,
    'fulfillmentKind',v_kind,
    'occurredAt',v_occurred_at,
    'lineCount',v_line_count,
    'allocationCount',v_allocation_count,
    'fulfillmentSha256',v_hash,
    'existingExternalAcquisitionFulfillmentId',v_existing.id,
    'existingCompatible',(v_existing.id is not null and v_existing.fulfillment_sha256=v_hash),
    'violations',v_violations,
    'warnings',v_warnings,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'actualOverdeliveryIsWarningNotSuppressed',true,
      'doesNotCreateFulfillment',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_fulfillment_service_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_preview jsonb;
  v_fulfillment_id uuid;
  v_fulfillment_line_id uuid;
  v_line jsonb;
  v_alloc jsonb;
  v_source jsonb;
begin
  v_preview:=atlas.external_acquisition_fulfillment_preview_v1(p_input);

  if v_preview->>'state'<>'ready' then
    if exists(
      select 1 from jsonb_array_elements(v_preview->'violations') x
      where x->>'key'='existing_fulfillment_conflicts'
    ) then
      raise exception 'External Acquisition Fulfillment key conflicts with different structural truth: %',
        (v_preview->'violations')::text
        using errcode='23505';
    end if;

    raise exception 'External Acquisition Fulfillment input is blocked: %',
      (v_preview->'violations')::text
      using errcode='22023';
  end if;

  if nullif(v_preview->>'existingExternalAcquisitionFulfillmentId','') is not null then
    return jsonb_build_object(
      'contractVersion','record_external_acquisition_fulfillment_service_v1',
      'externalAcquisitionFulfillmentId',
        (v_preview->>'existingExternalAcquisitionFulfillmentId')::uuid,
      'created',false,
      'fulfillmentSha256',v_preview->>'fulfillmentSha256',
      'commitmentPosition',
        atlas.external_acquisition_commitment_position_v1(
          (v_preview->>'externalAcquisitionCommitmentId')::uuid
        )
    );
  end if;

  v_source:=p_input->'source';

  insert into atlas.external_acquisition_fulfillments(
    external_acquisition_commitment_id,fulfillment_key,fulfillment_kind,
    occurred_at,source_kind,source_ref,evidence_record_id,
    connected_source_observation_id,fulfillment_sha256,metadata
  ) values (
    (p_input->>'externalAcquisitionCommitmentId')::uuid,
    btrim(p_input->>'fulfillmentKey'),
    lower(btrim(p_input->>'fulfillmentKind')),
    (p_input->>'occurredAt')::timestamptz,
    lower(btrim(v_source->>'kind')),
    nullif(btrim(v_source->>'ref'),''),
    nullif(v_source->>'evidenceRecordId','')::uuid,
    nullif(v_source->>'connectedSourceObservationId','')::uuid,
    v_preview->>'fulfillmentSha256',
    coalesce(p_input->'metadata','{}'::jsonb)
  )
  returning id into v_fulfillment_id;

  for v_line in select value from jsonb_array_elements(p_input->'lines')
  loop
    insert into atlas.external_acquisition_fulfillment_lines(
      external_acquisition_fulfillment_id,line_key,
      external_acquisition_commitment_line_id,
      source_quantity,source_unit,
      delivered_output_quantity,accepted_output_quantity,
      rejected_output_quantity,unresolved_output_quantity,
      coverage_output_unit,condition,metadata
    ) values (
      v_fulfillment_id,
      btrim(v_line->>'lineKey'),
      (v_line->>'externalAcquisitionCommitmentLineId')::uuid,
      case when v_line->'sourceQuantity' is null
                or v_line->'sourceQuantity'='null'::jsonb
           then null else (v_line->>'sourceQuantity')::numeric end,
      nullif(lower(btrim(coalesce(v_line->>'sourceUnit',''))),''),
      (v_line->>'deliveredOutputQuantity')::numeric,
      (v_line->>'acceptedOutputQuantity')::numeric,
      (v_line->>'rejectedOutputQuantity')::numeric,
      (v_line->>'unresolvedOutputQuantity')::numeric,
      lower(btrim(v_line->>'coverageOutputUnit')),
      coalesce(v_line->'condition','{}'::jsonb),
      coalesce(v_line->'metadata','{}'::jsonb)
    )
    returning id into v_fulfillment_line_id;

    if jsonb_typeof(coalesce(v_line->'allocations','[]'::jsonb))='array' then
      for v_alloc in
        select value from jsonb_array_elements(coalesce(v_line->'allocations','[]'::jsonb))
      loop
        insert into atlas.external_acquisition_fulfillment_allocations(
          external_acquisition_fulfillment_line_id,allocation_key,
          external_acquisition_requirement_allocation_id,
          accepted_coverage_quantity,coverage_unit,metadata
        ) values (
          v_fulfillment_line_id,
          btrim(v_alloc->>'allocationKey'),
          (v_alloc->>'externalAcquisitionRequirementAllocationId')::uuid,
          (v_alloc->>'acceptedCoverageQuantity')::numeric,
          lower(btrim(v_alloc->>'coverageUnit')),
          coalesce(v_alloc->'metadata','{}'::jsonb)
        );
      end loop;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_fulfillment_service_v1',
    'externalAcquisitionFulfillmentId',v_fulfillment_id,
    'created',true,
    'fulfillmentSha256',v_preview->>'fulfillmentSha256',
    'position',atlas.external_acquisition_fulfillment_position_v1(v_fulfillment_id),
    'commitmentPosition',
      atlas.external_acquisition_commitment_position_v1(
        (p_input->>'externalAcquisitionCommitmentId')::uuid
      ),
    'truthBoundary',jsonb_build_object(
      'createsExternalFulfillmentTruth',true,
      'createsAcceptedCoverageAllocations',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCreatePayment',true,
      'doesNotCreateCommercialOrder',true,
      'doesNotCreateWorkRequirement',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


create or replace function atlas.record_external_acquisition_commitment_event_service_v1(
  p_external_acquisition_commitment_id uuid,
  p_event_key text,
  p_event_kind text,
  p_occurred_at timestamptz,
  p_source jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_position jsonb;
  v_current_state text;
  v_kind text:=lower(btrim(coalesce(p_event_kind,'')));
  v_key text:=btrim(coalesce(p_event_key,''));
  v_source_kind text;
  v_hash text;
  v_existing atlas.external_acquisition_commitment_events%rowtype;
  v_commitment atlas.external_acquisition_commitments%rowtype;
  v_latest_at timestamptz;
  v_id uuid;
begin
  select * into v_commitment
  from atlas.external_acquisition_commitments
  where id=p_external_acquisition_commitment_id;

  if v_commitment.id is null then
    raise exception 'External Acquisition Commitment not found.'
      using errcode='P0002';
  end if;

  if v_key='' or v_kind not in ('cancelled','closed') or p_occurred_at is null then
    raise exception 'Event key, cancelled/closed event kind, and occurred time are required.'
      using errcode='22023';
  end if;

  if p_source is null or jsonb_typeof(p_source)<>'object'
     or nullif(btrim(coalesce(p_source->>'kind','')),'') is null then
    raise exception 'Event source requires a nonblank kind.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Event metadata must be an object.'
      using errcode='22023';
  end if;

  v_source_kind:=lower(btrim(p_source->>'kind'));

  v_hash:=encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
          'eventKey',v_key,
          'eventKind',v_kind,
          'occurredAt',p_occurred_at,
          'source',p_source,
          'metadata',p_metadata
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into v_existing
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id
    and e.event_key=v_key;

  if v_existing.id is not null then
    if v_existing.event_sha256 is distinct from v_hash then
      raise exception 'External Acquisition Commitment event key conflicts with different truth.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','record_external_acquisition_commitment_event_service_v1',
      'externalAcquisitionCommitmentEventId',v_existing.id,
      'created',false,
      'position',
        atlas.external_acquisition_commitment_position_v1(
          p_external_acquisition_commitment_id
        )
    );
  end if;

  v_position:=atlas.external_acquisition_commitment_position_v1(
    p_external_acquisition_commitment_id
  );
  v_current_state:=v_position->>'state';

  if not (
    (
      v_kind='cancelled'
      and v_current_state in (
        'committed',
        'partially_fulfilled',
        'fulfillment_unresolved',
        'fulfilled_with_exception'
      )
    )
    or
    (
      v_kind='closed'
      and v_current_state in (
        'cancelled',
        'fulfilled',
        'fulfilled_with_exception'
      )
    )
  ) then
    raise exception 'Invalid External Acquisition Commitment transition: % -> %.',
      v_current_state,v_kind
      using errcode='23514';
  end if;

  select max(e.occurred_at)
  into v_latest_at
  from atlas.external_acquisition_commitment_events e
  where e.external_acquisition_commitment_id=p_external_acquisition_commitment_id;

  if p_occurred_at<v_commitment.committed_at
     or (v_latest_at is not null and p_occurred_at<v_latest_at) then
    raise exception 'External Acquisition Commitment events must not precede commitment time or prior lifecycle evidence.'
      using errcode='23514';
  end if;

  insert into atlas.external_acquisition_commitment_events(
    external_acquisition_commitment_id,event_key,event_kind,occurred_at,
    source_kind,source_ref,evidence_record_id,connected_source_observation_id,
    event_sha256,metadata
  ) values (
    p_external_acquisition_commitment_id,v_key,v_kind,p_occurred_at,
    v_source_kind,
    nullif(btrim(p_source->>'ref'),''),
    nullif(p_source->>'evidenceRecordId','')::uuid,
    nullif(p_source->>'connectedSourceObservationId','')::uuid,
    v_hash,p_metadata
  )
  returning id into v_id;

  return jsonb_build_object(
    'contractVersion','record_external_acquisition_commitment_event_service_v1',
    'externalAcquisitionCommitmentEventId',v_id,
    'created',true,
    'position',
      atlas.external_acquisition_commitment_position_v1(
        p_external_acquisition_commitment_id
      )
  );
end;
$function$;


create or replace function atlas.external_acquisition_commitment_coverage_facts_v1(
  p_external_acquisition_commitment_id uuid
)
returns jsonb
language plpgsql
stable
set search_path=pg_catalog,atlas
as $function$
declare
  v_position jsonb;
  v_state text;
  v_release_residual boolean:=false;
  v_facts jsonb;
begin
  v_position:=atlas.external_acquisition_commitment_position_v1(
    p_external_acquisition_commitment_id
  );
  v_state:=v_position->>'state';
  v_release_residual:=v_state in ('cancelled','closed');

  select coalesce(
    jsonb_agg(x.fact order by x.sort_key,x.fact->>'workRequirementId'),
    '[]'::jsonb
  )
  into v_facts
  from (
    select
      '1:'||fa.id::text as sort_key,
      jsonb_build_object(
        'workRequirementId',ra.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition_fulfillment:'||fa.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_fulfillment_allocation',
            'sourceRef',fa.id::text
          ),
          'state','secured',
          'quantity',fa.accepted_coverage_quantity,
          'unit',fa.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_fulfillment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionFulfillmentId',f.id,
            'externalAcquisitionFulfillmentLineId',fl.id,
            'externalAcquisitionFulfillmentAllocationId',fa.id
          )),
          'metadata',jsonb_build_object(
            'coverageLayer','accepted_external_fulfillment',
            'commitmentState',v_state
          )
        )
      ) as fact
    from atlas.external_acquisition_fulfillment_allocations fa
    join atlas.external_acquisition_fulfillment_lines fl
      on fl.id=fa.external_acquisition_fulfillment_line_id
    join atlas.external_acquisition_fulfillments f
      on f.id=fl.external_acquisition_fulfillment_id
    join atlas.external_acquisition_requirement_allocations ra
      on ra.id=fa.external_acquisition_requirement_allocation_id
    where f.external_acquisition_commitment_id=p_external_acquisition_commitment_id

    union all

    select
      '2:'||ra.id::text as sort_key,
      jsonb_build_object(
        'workRequirementId',ra.work_requirement_id,
        'coverageFact',jsonb_build_object(
          'coverageKey','external_acquisition_commitment_residual:'||ra.id::text,
          'sourceRef',jsonb_build_object(
            'sourceDomain','external_acquisition_requirement_allocation',
            'sourceRef',ra.id::text
          ),
          'state',case when v_release_residual then 'released' else 'secured' end,
          'quantity',
            greatest(
              ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),
              0
            ),
          'unit',ra.coverage_unit,
          'evidence',jsonb_build_array(jsonb_build_object(
            'source','external_acquisition_commitment',
            'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
            'externalAcquisitionCommitmentLineId',
              ra.external_acquisition_commitment_line_id,
            'externalAcquisitionRequirementAllocationId',ra.id
          )),
          'metadata',jsonb_build_object(
            'coverageLayer','remaining_supplier_commitment',
            'commitmentState',v_state
          )
        )
      ) as fact
    from atlas.external_acquisition_requirement_allocations ra
    join atlas.external_acquisition_commitment_lines cl
      on cl.id=ra.external_acquisition_commitment_line_id
    left join lateral (
      select sum(fa.accepted_coverage_quantity) as accepted_fulfilled
      from atlas.external_acquisition_fulfillment_allocations fa
      where fa.external_acquisition_requirement_allocation_id=ra.id
    ) ff on true
    where cl.external_acquisition_commitment_id=p_external_acquisition_commitment_id
      and greatest(
        ra.coverage_quantity-coalesce(ff.accepted_fulfilled,0),
        0
      )>0
  ) x;

  return jsonb_build_object(
    'contractVersion','external_acquisition_commitment_coverage_facts_v1',
    'externalAcquisitionCommitmentId',p_external_acquisition_commitment_id,
    'commitmentState',v_state,
    'coverageMode','split_commitment_and_accepted_fulfillment',
    'facts',v_facts,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'acceptedFulfillmentAndResidualCommitmentDoNotOverlap',true,
      'cancelOrCloseReleasesOnlyResidualCommitmentCoverage',true,
      'rejectedOutputCreatesNoCoverage',true,
      'unresolvedOutputCreatesNoCoverage',true,
      'doesNotCreateCoverageRow',true,
      'doesNotCreateInventory',true,
      'doesNotCreateSpend',true,
      'doesNotCloseCompanyWork',true
    )
  );
end;
$function$;


alter table atlas.external_acquisition_fulfillments enable row level security;
alter table atlas.external_acquisition_fulfillment_lines enable row level security;
alter table atlas.external_acquisition_fulfillment_allocations enable row level security;

revoke all on atlas.external_acquisition_fulfillments
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_fulfillment_lines
  from public,anon,authenticated,service_role;
revoke all on atlas.external_acquisition_fulfillment_allocations
  from public,anon,authenticated,service_role;

grant select on atlas.external_acquisition_fulfillments to service_role;
grant select on atlas.external_acquisition_fulfillment_lines to service_role;
grant select on atlas.external_acquisition_fulfillment_allocations to service_role;

revoke all on function atlas.external_acquisition_fulfillment_preview_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_fulfillment_preview_v1(jsonb)
  to service_role;

revoke all on function atlas.record_external_acquisition_fulfillment_service_v1(jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_external_acquisition_fulfillment_service_v1(jsonb)
  to service_role;

revoke all on function atlas.external_acquisition_fulfillment_position_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.external_acquisition_fulfillment_position_v1(uuid)
  to service_role;


insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,
  consumer_surfaces,known_competitors,source_custody,rationale,updated_at
) values (
  'external_acquisition_fulfillment',
  'commercial_supply',
  'What did an external supplier actually deliver or perform against an acquisition commitment, in what quantity and condition, and what accepted output now secures Company Work?',
  'external_acquisition_fulfillments + lines + accepted requirement allocations',
  'canonical',
  array[
    'atlas.external_acquisition_fulfillments',
    'atlas.external_acquisition_fulfillment_lines',
    'atlas.external_acquisition_fulfillment_allocations'
  ],
  array[
    'atlas.external_acquisition_fulfillment_preview_v1',
    'atlas.record_external_acquisition_fulfillment_service_v1',
    'atlas.external_acquisition_fulfillment_position_v1',
    'atlas.external_acquisition_commitment_position_v1',
    'atlas.external_acquisition_commitment_coverage_facts_v1'
  ],
  array[
    'atlas.external_acquisition_commitments',
    'atlas.external_acquisition_commitment_lines',
    'atlas.external_acquisition_requirement_allocations',
    'atlas.work_requirements',
    'atlas.evidence_records',
    'atlas.connected_source_observations'
  ],
  array[]::text[],
  array[
    'atlas.flower_external_intakes',
    'atlas.flower_ready_inventory_lots',
    'atlas.work_execution_results',
    'atlas.work_result_acceptances',
    'atlas.organization_spend_occurrences'
  ],
  'Actual supplier fulfillment remains separate from source commitment, inventory, internal work execution, and occurred Spend. Accepted output may feed those domains later through explicit adapters.',
  'Provides a partial, quantitative, source-owned handoff from outstanding supplier commitment coverage to actual accepted delivery/performance coverage without double counting.',
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
  'atlas.external_acquisition_fulfillment_preview_v1(jsonb)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Read-only validation of actual external supplier delivery/performance intake.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.record_external_acquisition_fulfillment_service_v1(jsonb)',
  'service_internal','verified','active',
  false,true,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Persist immutable actual external supplier delivery/performance and accepted Company Work allocations; creates no inventory or Spend.","classificationRuleVersion":3}'::jsonb,
  false
),
(
  'atlas.external_acquisition_fulfillment_position_v1(uuid)',
  'service_internal','verified','active',
  false,false,true,0,1,
  '{"source":"atlas_external_acquisition_fulfillment_intake_v1","purpose":"Read one external supplier fulfillment occurrence with accepted/rejected/unresolved output and accepted allocations.","classificationRuleVersion":3}'::jsonb,
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
-- END candidates/atlas_external_acquisition_fulfillment_intake_v1.sql
-- ============================================================================

commit;

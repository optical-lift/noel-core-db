begin;

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
         and cs.custodian_organization_unit_id is not distinct from new.organization_unit_id
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

commit;

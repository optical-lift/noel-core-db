-- Atlas public commitment membrane v1
-- Source-custody checkpoint for live authority established 2026-09-27.
--
-- Governing boundary:
--   public interaction expresses a request;
--   Atlas evaluates current canonical resources, policy, pricing and commitment requirements;
--   submission materializes a canonical Ledger booking request plus frozen commercial quote;
--   availability, agreement, payment and approval remain distinct facts and none alone means booking.

create table atlas.public_commitment_surfaces (
  id uuid primary key default gen_random_uuid(),
  surface_key text not null unique check (btrim(surface_key) <> ''),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  title text not null check (btrim(title) <> ''),
  description text,
  surface_state text not null default 'draft' check (surface_state in ('draft','active','paused','retired')),
  adapter_kind text not null check (btrim(adapter_kind) <> ''),
  ledger_id uuid references ledger.ledgers(id) on delete restrict,
  booking_offering_id uuid references ledger.booking_offerings(id) on delete restrict,
  commercial_offering_id uuid references atlas.commercial_offerings(id) on delete restrict,
  public_config jsonb not null default '{}'::jsonb check (jsonb_typeof(public_config)='object'),
  adapter_config jsonb not null default '{}'::jsonb check (jsonb_typeof(adapter_config)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict
);

create table atlas.public_commitment_sessions (
  id uuid primary key default gen_random_uuid(),
  surface_id uuid not null references atlas.public_commitment_surfaces(id) on delete restrict,
  public_token_sha256 text not null unique check (public_token_sha256 ~ '^[0-9a-f]{64}$'),
  requester_entity_id uuid references reality.entities(id) on delete restrict,
  identity_resolution_state text not null check (identity_resolution_state in ('matched','created','ambiguous','unresolved')),
  identity_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(identity_snapshot)='object'),
  literal_request text,
  session_state text not null default 'draft' check (session_state in ('draft','materialized','withdrawn','expired')),
  current_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(current_payload)='object'),
  domain_object_kind text,
  domain_object_id uuid,
  quote_snapshot_id uuid references atlas.commercial_offer_snapshots(id) on delete restrict,
  idempotency_key text check (idempotency_key is null or btrim(idempotency_key)<>''),
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  materialized_at timestamptz,
  withdrawn_at timestamptz
);

create unique index public_commitment_sessions_surface_idempotency_uq
  on atlas.public_commitment_sessions(surface_id,idempotency_key)
  where idempotency_key is not null;
create index public_commitment_sessions_surface_state_idx
  on atlas.public_commitment_sessions(surface_id,session_state,created_at desc);
create index public_commitment_sessions_domain_idx
  on atlas.public_commitment_sessions(domain_object_kind,domain_object_id)
  where domain_object_id is not null;

create table atlas.public_commitment_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references atlas.public_commitment_sessions(id) on delete cascade,
  event_kind text not null check (btrim(event_kind)<>''),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text check (idempotency_key is null or btrim(idempotency_key)<>''),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index public_commitment_events_session_idem_uq
  on atlas.public_commitment_events(session_id,idempotency_key)
  where idempotency_key is not null;
create index public_commitment_events_session_time_idx
  on atlas.public_commitment_events(session_id,occurred_at,id);

create or replace function atlas.guard_public_commitment_surface_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_ledger uuid;
  v_org uuid;
  v_unit uuid;
begin
  if new.adapter_kind='ledger_booking' then
    if new.ledger_id is null or new.booking_offering_id is null or new.commercial_offering_id is null then
      raise exception 'ledger_booking public surface requires Ledger, booking offering, and commercial offering.' using errcode='23514';
    end if;
    select o.ledger_id into v_ledger from ledger.booking_offerings o where o.id=new.booking_offering_id;
    if v_ledger is null or v_ledger<>new.ledger_id then
      raise exception 'Public surface booking offering must belong to the configured Ledger.' using errcode='23514';
    end if;
    select c.organization_id,c.organization_unit_id into v_org,v_unit
    from atlas.commercial_offerings c where c.id=new.commercial_offering_id;
    if v_org is null or v_org<>new.organization_id or v_unit is distinct from new.organization_unit_id then
      raise exception 'Public surface commercial offering must belong to the configured organization scope.' using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger guard_public_commitment_surface_v1
before insert or update on atlas.public_commitment_surfaces
for each row execute function atlas.guard_public_commitment_surface_v1();

create or replace function atlas.prevent_public_commitment_event_mutation_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  raise exception 'Public commitment event history is append-only.' using errcode='23514';
end;
$function$;

create trigger prevent_public_commitment_event_mutation_v1
before delete or update on atlas.public_commitment_events
for each row execute function atlas.prevent_public_commitment_event_mutation_v1();

create or replace function atlas.resolve_public_commitment_person_v1(
  p_name text,
  p_email text,
  p_phone text,
  p_surface_key text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text:=btrim(coalesce(p_name,''));
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_phone text:=nullif(btrim(coalesce(p_phone,'')),'');
  v_ids uuid[];
  v_count integer:=0;
  v_entity_id uuid;
  v_state text;
  v_normalized_phone text;
begin
  if length(v_name)<2 or length(v_name)>160 then
    raise exception 'Name is required.' using errcode='22023';
  end if;
  if length(v_email)<5 or length(v_email)>254 or position('@' in v_email)<2 then
    raise exception 'A valid email address is required.' using errcode='22023';
  end if;
  if v_phone is not null and length(v_phone)>60 then
    raise exception 'Phone number is too long.' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email,0));

  select array_agg(distinct e.id order by e.id),count(distinct e.id)
  into v_ids,v_count
  from reality.contact_routes c
  join reality.entities e on e.id=c.entity_id
  where c.route_kind='email'
    and lower(coalesce(c.normalized_value,c.route_value))=v_email
    and c.route_state in ('observed','verified')
    and e.identity_state='canonical'
    and e.entity_kind='person';

  if v_count=1 then
    v_entity_id:=v_ids[1];
    v_state:='matched';
  elsif v_count=0 then
    v_entity_id:=gen_random_uuid();
    insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
    values(
      v_entity_id,
      'public_person_'||replace(v_entity_id::text,'-',''),
      'person',v_name,'canonical',
      jsonb_build_object(
        'admittedFrom','public_commitment_surface',
        'admissionBasis',jsonb_build_object(
          'basis','Direct self-supplied public request identity',
          'surfaceKey',p_surface_key
        ),
        'identityEvidenceState','self_supplied_direct_contact'
      )
    );
    insert into reality.contact_routes(
      entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
    ) values(
      v_entity_id,'email',v_email,v_email,'observed',false,
      jsonb_build_object('sourceSystem','public_commitment_surface','verificationState','self_supplied','visibility','private','surfaceKey',p_surface_key),
      jsonb_build_object('contactScope','direct','context','public commitment request')
    );
    v_state:='created';
  else
    v_entity_id:=null;
    v_state:='ambiguous';
  end if;

  if v_entity_id is not null and v_phone is not null then
    v_normalized_phone:=regexp_replace(v_phone,'[^0-9+]','','g');
    insert into reality.contact_routes(
      entity_id,route_kind,route_value,normalized_value,route_state,public_disclosure,evidence,metadata
    ) values(
      v_entity_id,'phone',v_phone,nullif(v_normalized_phone,''),'observed',false,
      jsonb_build_object('sourceSystem','public_commitment_surface','verificationState','self_supplied','visibility','private','surfaceKey',p_surface_key),
      jsonb_build_object('contactScope','direct','context','public commitment request')
    )
    on conflict(entity_id,route_kind,normalized_value) do nothing;
  end if;

  return jsonb_build_object('entityId',v_entity_id,'resolutionState',v_state,'email',v_email);
end;
$function$;

create or replace function atlas.public_commitment_surface_v1(p_surface_key text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_resources jsonb:='[]'::jsonb;
  v_prices jsonb:='[]'::jsonb;
  v_commitment jsonb:='{}'::jsonb;
  v_approval_required boolean:=false;
  v_min_minutes numeric:=null;
begin
  select * into v_surface
  from atlas.public_commitment_surfaces s
  where s.surface_key=btrim(p_surface_key) and s.surface_state='active';
  if v_surface.id is null then
    raise exception 'Public commitment surface not found or not active.' using errcode='P0002';
  end if;

  if v_surface.adapter_kind='ledger_booking' then
    select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'key',r.stable_key,'label',r.label,'resourceKind',r.resource_kind,'capacityMode',r.capacity_mode
    ) order by r.label,r.id),'[]'::jsonb)
    into v_resources
    from reality.resources r
    where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
      and r.resource_state='active' and r.reservable
      and r.stable_key in (
        select value from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicResourceKeys','[]'::jsonb))
      );

    select coalesce(jsonb_agg(jsonb_build_object(
      'priceBasis',p.price_basis,'amount',p.unit_price,'currency',p.currency,
      'componentType',p.metadata->>'componentType','scope',p.metadata->>'scope'
    ) order by p.price_basis),'[]'::jsonb)
    into v_prices
    from atlas.commercial_offering_prices p
    where p.offering_id=v_surface.commercial_offering_id
      and p.effective_from<=current_date
      and (p.effective_until is null or p.effective_until>=current_date)
      and p.price_basis in (
        select value from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicPriceBasisKeys','[]'::jsonb))
      );

    select coalesce(p.config,'{}'::jsonb) into v_commitment
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='commitment'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind)
    order by p.priority desc,p.id limit 1;

    select coalesce(bool_or(coalesce((p.config->>'required')::boolean,false)),false)
    into v_approval_required
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='approval'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind);

    select max((p.config->>'minMinutes')::numeric)
    into v_min_minutes
    from ledger.booking_policies p
    where p.ledger_id=v_surface.ledger_id and p.policy_state='active'
      and p.policy_kind='duration' and p.config ? 'minMinutes'
      and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind);
  end if;

  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_surface_v1',
    'surfaceKey',v_surface.surface_key,
    'title',v_surface.title,
    'description',v_surface.description,
    'adapterKind',v_surface.adapter_kind,
    'publicConfig',v_surface.public_config,
    'offering',case when v_surface.adapter_kind='ledger_booking' then jsonb_build_object(
      'name',v_booking.name,'bookingKind',v_booking.booking_kind,'occurrenceType',v_booking.occurrence_type,
      'defaultDurationMinutes',v_booking.default_duration_minutes,'minimumDurationMinutes',v_min_minutes
    ) else null end,
    'resourceOptions',v_resources,
    'pricingComponents',v_prices,
    'commitmentRequirements',jsonb_build_object(
      'approvalRequired',v_approval_required,
      'agreementRequired',coalesce((v_commitment->>'agreementRequired')::boolean,false),
      'paymentRequiredBeforeConfirmation',coalesce((v_commitment->>'paymentRequiredBeforeConfirmation')::boolean,false),
      'paymentRule',jsonb_build_object(
        'currency',coalesce(v_commitment->>'currency','USD'),
        'fullPaymentAtOrBelowAmount',case when v_commitment ? 'fullPaymentAtOrBelowAmount' then (v_commitment->>'fullPaymentAtOrBelowAmount')::numeric else null end,
        'fullPaymentPercentAtOrBelowThreshold',case when v_commitment ? 'fullPaymentPercentAtOrBelowThreshold' then (v_commitment->>'fullPaymentPercentAtOrBelowThreshold')::numeric else null end,
        'depositPercentAboveThreshold',case when v_commitment ? 'depositPercentAboveThreshold' then (v_commitment->>'depositPercentAboveThreshold')::numeric else null end,
        'remainingBalanceDueTimingState',v_commitment->>'remainingBalanceDueTimingState'
      )
    ),
    'allowedActions',jsonb_build_array('begin_request','evaluate_selection','submit_request')
  );
end;
$function$;

create or replace function atlas.public_commitment_quote_for_selection_v1(p_surface_id uuid,p_selection jsonb)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_duration_minutes numeric;
  v_guest_count integer;
  v_resource_keys text[];
  v_addon_keys text[];
  v_resource_ids uuid[];
  v_requested_count integer;
  v_resolved_count integer;
  v_policy jsonb;
  v_availability jsonb:='[]'::jsonb;
  v_all_available boolean:=true;
  v_rec record;
  v_av jsonb;
  v_reasons jsonb:='[]'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_total numeric:=0;
  v_currency text:='USD';
  v_duration_cfg jsonb;
  v_primary_key text;
  v_base_minutes integer;
  v_increment_minutes integer;
  v_base_basis text;
  v_additional_basis text;
  v_base_price numeric;
  v_additional_price numeric;
  v_extra_increments integer:=0;
  v_basis text;
  v_price numeric;
  v_key text;
  v_mapping jsonb;
  v_commitment jsonb:='{}'::jsonb;
  v_threshold numeric;
  v_deposit_percent numeric;
  v_due_now numeric;
  v_balance numeric;
  v_custom boolean:=false;
  v_submission_allowed boolean:=false;
  v_public_max_minutes integer;
  v_guest_max integer;
  v_require_guest boolean:=false;
begin
  if p_selection is null or jsonb_typeof(p_selection)<>'object' then
    raise exception 'Selection must be a JSON object.' using errcode='22023';
  end if;
  select * into v_surface from atlas.public_commitment_surfaces s where s.id=p_surface_id and s.surface_state='active';
  if v_surface.id is null then raise exception 'Active public surface not found.' using errcode='P0002'; end if;
  if v_surface.adapter_kind<>'ledger_booking' then raise exception 'Surface adapter does not support booking selection.' using errcode='23514'; end if;
  select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id and o.offering_state='active';
  if v_booking.id is null then raise exception 'Active booking offering not found.' using errcode='P0002'; end if;

  begin
    v_start:=(p_selection->>'startsAt')::timestamptz;
    v_end:=(p_selection->>'endsAt')::timestamptz;
  exception when others then
    raise exception 'Selection requires valid startsAt and endsAt timestamps.' using errcode='22023';
  end;
  if v_start is null or v_end is null or v_end<=v_start then
    raise exception 'Selection requires startsAt < endsAt.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_selection->'resourceKeys','null'::jsonb))<>'array' or jsonb_array_length(p_selection->'resourceKeys')=0 then
    raise exception 'Selection requires at least one resource key.' using errcode='22023';
  end if;
  if p_selection ? 'addOnKeys' and jsonb_typeof(p_selection->'addOnKeys')<>'array' then
    raise exception 'addOnKeys must be an array.' using errcode='22023';
  end if;

  select array_agg(value order by value),count(*) into v_resource_keys,v_requested_count
  from jsonb_array_elements_text(p_selection->'resourceKeys');
  if (select count(distinct x) from unnest(v_resource_keys) x)<>v_requested_count then
    raise exception 'Resource keys may not be duplicated.' using errcode='22023';
  end if;
  select array_agg(value order by value) into v_addon_keys
  from jsonb_array_elements_text(coalesce(p_selection->'addOnKeys','[]'::jsonb));
  v_addon_keys:=coalesce(v_addon_keys,'{}'::text[]);
  if (select count(distinct x) from unnest(v_addon_keys) x)<>cardinality(v_addon_keys) then
    raise exception 'Add-on keys may not be duplicated.' using errcode='22023';
  end if;

  if exists(
    select 1 from unnest(v_resource_keys) k
    where not exists(
      select 1 from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicResourceKeys','[]'::jsonb)) a where a.value=k
    )
  ) then
    raise exception 'Selection includes a Resource that is not exposed by this public surface.' using errcode='23514';
  end if;

  select array_agg(r.id order by r.id),count(*) into v_resource_ids,v_resolved_count
  from reality.resources r
  where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
    and r.resource_state='active' and r.reservable and r.stable_key=any(v_resource_keys);
  if v_resolved_count<>v_requested_count then
    raise exception 'One or more selected Resources are unavailable as canonical reservable Resources.' using errcode='23514';
  end if;

  v_duration_minutes:=extract(epoch from (v_end-v_start))/60.0;
  v_guest_count:=case when nullif(p_selection->>'guestCount','') is null then null else (p_selection->>'guestCount')::integer end;
  if v_guest_count is not null and v_guest_count<=0 then raise exception 'guestCount must be positive.' using errcode='22023'; end if;

  v_policy:=ledger.evaluate_booking_policies_v1(v_surface.ledger_id,v_resource_ids,v_booking.booking_kind,v_start,v_end,false,now());

  for v_rec in
    select r.id,r.stable_key,r.label from reality.resources r where r.id=any(v_resource_ids) order by r.label,r.id
  loop
    v_av:=ledger.resource_claim_availability_v1(v_surface.ledger_id,v_rec.id,v_start,v_end,'exclusive',null,null,null);
    v_availability:=v_availability||jsonb_build_array(jsonb_build_object(
      'resourceId',v_rec.id,'resourceKey',v_rec.stable_key,'resourceLabel',v_rec.label,'availability',v_av
    ));
    if not coalesce((v_av->>'available')::boolean,false) then v_all_available:=false; end if;
  end loop;

  v_duration_cfg:=coalesce(v_surface.adapter_config->'durationPricing','{}'::jsonb);
  v_primary_key:=v_duration_cfg->>'resourceKey';
  v_base_minutes:=coalesce((v_duration_cfg->>'baseIncludedMinutes')::integer,0);
  v_increment_minutes:=coalesce((v_duration_cfg->>'incrementMinutes')::integer,0);
  v_base_basis:=v_duration_cfg->>'basePriceBasis';
  v_additional_basis:=v_duration_cfg->>'additionalPriceBasis';
  v_public_max_minutes:=case when v_surface.adapter_config ? 'selfServiceMaxMinutes' then (v_surface.adapter_config->>'selfServiceMaxMinutes')::integer else null end;
  v_guest_max:=case when v_surface.adapter_config ? 'selfServiceGuestCountMax' then (v_surface.adapter_config->>'selfServiceGuestCountMax')::integer else null end;
  v_require_guest:=coalesce((v_surface.adapter_config->>'requireGuestCount')::boolean,false);

  if v_require_guest and v_guest_count is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','guest_count_required_for_standard_quote'));
  end if;
  if v_primary_key is null or not (v_primary_key=any(v_resource_keys)) then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','primary_resource_required_for_standard_quote','resourceKey',v_primary_key));
  end if;
  if v_public_max_minutes is not null and v_duration_minutes>v_public_max_minutes then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_requires_custom_quote','maxStandardMinutes',v_public_max_minutes));
  end if;
  if v_guest_max is not null and v_guest_count is not null and v_guest_count>v_guest_max then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','guest_count_requires_custom_quote','maxStandardGuests',v_guest_max));
  end if;
  if v_base_minutes<=0 or v_increment_minutes<=0 then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_pricing_not_configured'));
  else
    if v_duration_minutes<v_base_minutes
       or v_duration_minutes<>floor(v_duration_minutes)
       or mod((v_duration_minutes-v_base_minutes)::integer,v_increment_minutes)<>0 then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_not_standard_pricing_increment','baseMinutes',v_base_minutes,'incrementMinutes',v_increment_minutes));
    end if;
  end if;

  select p.unit_price,p.currency into v_base_price,v_currency
  from atlas.commercial_offering_prices p
  where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_base_basis
    and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
  order by p.effective_from desc,p.created_at desc limit 1;
  select p.unit_price into v_additional_price
  from atlas.commercial_offering_prices p
  where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_additional_basis
    and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
  order by p.effective_from desc,p.created_at desc limit 1;
  if v_base_price is null or v_additional_price is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','basePriceBasis',v_base_basis,'additionalPriceBasis',v_additional_basis));
  else
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'lineKey','base_rental','description','Base venue rental','priceBasis',v_base_basis,'quantity',1,'unitPrice',v_base_price,'lineTotal',v_base_price
    ));
    v_total:=v_total+v_base_price;
    if v_base_minutes>0 and v_increment_minutes>0 and v_duration_minutes>=v_base_minutes
       and v_duration_minutes=floor(v_duration_minutes)
       and mod((v_duration_minutes-v_base_minutes)::integer,v_increment_minutes)=0 then
      v_extra_increments:=((v_duration_minutes-v_base_minutes)/v_increment_minutes)::integer;
      if v_extra_increments>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineKey','duration_extension','description','Additional rental time','priceBasis',v_additional_basis,
          'quantity',v_extra_increments,'unitPrice',v_additional_price,'lineTotal',v_extra_increments*v_additional_price
        ));
        v_total:=v_total+(v_extra_increments*v_additional_price);
      end if;
    end if;
  end if;

  v_mapping:=coalesce(v_surface.adapter_config->'resourcePriceBasis','{}'::jsonb);
  foreach v_key in array v_resource_keys loop
    if v_key<>v_primary_key and v_mapping ? v_key then
      v_basis:=v_mapping->>v_key;
      select p.unit_price into v_price
      from atlas.commercial_offering_prices p
      where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_basis
        and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
      order by p.effective_from desc,p.created_at desc limit 1;
      if v_price is null then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','priceBasis',v_basis));
      else
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineKey','resource_'||v_key,'description','Resource add-on: '||v_key,'priceBasis',v_basis,'quantity',1,'unitPrice',v_price,'lineTotal',v_price
        ));
        v_total:=v_total+v_price;
      end if;
    end if;
  end loop;

  v_mapping:=coalesce(v_surface.adapter_config->'addOnPriceBasis','{}'::jsonb);
  foreach v_key in array v_addon_keys loop
    if not (v_mapping ? v_key) then
      raise exception 'Selection includes an add-on that is not exposed by this public surface.' using errcode='23514';
    end if;
    v_basis:=v_mapping->>v_key;
    select p.unit_price into v_price
    from atlas.commercial_offering_prices p
    where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_basis
      and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
    order by p.effective_from desc,p.created_at desc limit 1;
    if v_price is null then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','priceBasis',v_basis));
    else
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
        'lineKey','addon_'||v_key,'description','Add-on: '||replace(v_key,'_',' '),'priceBasis',v_basis,'quantity',1,'unitPrice',v_price,'lineTotal',v_price
      ));
      v_total:=v_total+v_price;
    end if;
  end loop;

  v_custom:=jsonb_array_length(v_reasons)>0;
  select coalesce(p.config,'{}'::jsonb) into v_commitment
  from ledger.booking_policies p
  where p.ledger_id=v_surface.ledger_id and p.policy_state='active' and p.policy_kind='commitment'
    and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind)
  order by p.priority desc,p.id limit 1;
  v_threshold:=case when v_commitment ? 'fullPaymentAtOrBelowAmount' then (v_commitment->>'fullPaymentAtOrBelowAmount')::numeric else null end;
  v_deposit_percent:=case when v_commitment ? 'depositPercentAboveThreshold' then (v_commitment->>'depositPercentAboveThreshold')::numeric else null end;

  if not v_custom then
    v_total:=round(v_total,2);
    if coalesce((v_commitment->>'paymentRequiredBeforeConfirmation')::boolean,false) then
      if v_threshold is not null and v_total<=v_threshold then
        v_due_now:=v_total;
      elsif v_deposit_percent is not null then
        v_due_now:=round(v_total*v_deposit_percent/100.0,2);
      end if;
    else
      v_due_now:=0;
    end if;
    v_balance:=case when v_due_now is null then null else round(v_total-v_due_now,2) end;
  else
    v_total:=null;
    v_due_now:=null;
    v_balance:=null;
  end if;

  v_submission_allowed:=not v_custom
    and coalesce((v_policy->>'allowed')::boolean,false)
    and v_all_available;

  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_quote_v1',
    'surfaceId',v_surface.id,
    'selection',jsonb_build_object(
      'startsAt',v_start,'endsAt',v_end,'durationMinutes',v_duration_minutes,
      'guestCount',v_guest_count,'resourceKeys',to_jsonb(v_resource_keys),'addOnKeys',to_jsonb(v_addon_keys),
      'eventType',p_selection->>'eventType'
    ),
    'policyEvaluation',v_policy,
    'resourceAvailability',v_availability,
    'allResourcesAvailable',v_all_available,
    'customQuoteRequired',v_custom,
    'customQuoteReasons',v_reasons,
    'quote',jsonb_build_object(
      'currency',v_currency,'lines',v_lines,'totalAmount',v_total,
      'requiredBeforeConfirmation',v_due_now,'remainingBalance',v_balance,
      'remainingBalanceDueTimingState',v_commitment->>'remainingBalanceDueTimingState'
    ),
    'submissionAllowed',v_submission_allowed
  );
end;
$function$;

create or replace function atlas.public_commitment_session_v1(p_access_token text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_session atlas.public_commitment_sessions%rowtype;
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_name text;
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  select * into v_surface from atlas.public_commitment_surfaces s where s.id=v_session.surface_id;
  v_name:=coalesce(v_session.identity_snapshot->>'name',(select e.display_name from reality.entities e where e.id=v_session.requester_entity_id));
  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_session_v1',
    'sessionId',v_session.id,
    'surfaceKey',v_surface.surface_key,
    'title',v_surface.title,
    'sessionState',v_session.session_state,
    'identity',jsonb_build_object('name',v_name,'resolutionState',v_session.identity_resolution_state),
    'currentPayload',v_session.current_payload,
    'domainObjectKind',v_session.domain_object_kind,
    'domainObjectId',v_session.domain_object_id,
    'quoteSnapshotId',v_session.quote_snapshot_id,
    'createdAt',v_session.created_at,
    'materializedAt',v_session.materialized_at,
    'nextActions',case
      when v_session.session_state='draft' and not (v_session.current_payload ? 'selectionEvaluation') then jsonb_build_array('evaluate_selection')
      when v_session.session_state='draft' and coalesce((v_session.current_payload->'selectionEvaluation'->>'submissionAllowed')::boolean,false) then jsonb_build_array('submit_request')
      when v_session.session_state='draft' then jsonb_build_array('revise_selection')
      when v_session.session_state='materialized' then jsonb_build_array('await_commitment_requirements')
      else '[]'::jsonb end
  );
end;
$function$;

create or replace function atlas.begin_public_commitment_session_v1(
  p_surface_key text,
  p_name text,
  p_email text,
  p_phone text default null,
  p_literal_request text default null,
  p_idempotency_key text default null,
  p_client_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_identity jsonb;
  v_entity_id uuid;
  v_resolution text;
  v_token text;
  v_hash text;
  v_session_id uuid;
  v_existing atlas.public_commitment_sessions%rowtype;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_literal text:=nullif(btrim(coalesce(p_literal_request,'')),'');
begin
  select * into v_surface from atlas.public_commitment_surfaces s
  where s.surface_key=btrim(p_surface_key) and s.surface_state='active';
  if v_surface.id is null then raise exception 'Public commitment surface not found or not active.' using errcode='P0002'; end if;

  if v_idem is not null then
    select * into v_existing from atlas.public_commitment_sessions s where s.surface_id=v_surface.id and s.idempotency_key=v_idem;
    if v_existing.id is not null then
      if p_client_token is null or encode(extensions.digest(p_client_token,'sha256'),'hex')<>v_existing.public_token_sha256 then
        raise exception 'Existing public request requires its original client token.' using errcode='42501';
      end if;
      return jsonb_build_object('accessToken',p_client_token,'session',atlas.public_commitment_session_v1(p_client_token),'idempotentReplay',true);
    end if;
  end if;

  v_identity:=atlas.resolve_public_commitment_person_v1(p_name,p_email,p_phone,v_surface.surface_key);
  v_entity_id:=case when v_identity->>'entityId' is null then null else (v_identity->>'entityId')::uuid end;
  v_resolution:=v_identity->>'resolutionState';

  v_token:=coalesce(nullif(p_client_token,''),encode(extensions.gen_random_bytes(32),'hex'));
  if length(v_token)<32 then raise exception 'Client token must contain at least 32 characters.' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(v_token,'sha256'),'hex');

  insert into atlas.public_commitment_sessions(
    surface_id,public_token_sha256,requester_entity_id,identity_resolution_state,identity_snapshot,
    literal_request,session_state,current_payload,idempotency_key,metadata,provenance
  ) values(
    v_surface.id,v_hash,v_entity_id,v_resolution,
    jsonb_build_object('name',btrim(p_name),'email',lower(btrim(p_email)),'phone',nullif(btrim(coalesce(p_phone,'')),'')),
    v_literal,'draft','{}'::jsonb,v_idem,
    jsonb_build_object('channel','public_web'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key)
  ) returning id into v_session_id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session_id,'session.started',
    jsonb_build_object('identityResolutionState',v_resolution,'literalRequest',v_literal),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),
    case when v_idem is null then null else v_idem||':started' end
  );

  return jsonb_build_object('accessToken',v_token,'session',atlas.public_commitment_session_v1(v_token),'idempotentReplay',false);
end;
$function$;

create or replace function atlas.set_public_commitment_selection_v1(
  p_access_token text,
  p_selection jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_session atlas.public_commitment_sessions%rowtype;
  v_eval jsonb;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash for update;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  if v_session.session_state<>'draft' then raise exception 'Only draft public commitment sessions may revise selection.' using errcode='23514'; end if;
  if v_idem is not null and exists(select 1 from atlas.public_commitment_events e where e.session_id=v_session.id and e.idempotency_key=v_idem) then
    return atlas.public_commitment_session_v1(p_access_token);
  end if;

  v_eval:=atlas.public_commitment_quote_for_selection_v1(v_session.surface_id,p_selection);
  update atlas.public_commitment_sessions
  set current_payload=jsonb_build_object('bookingSelection',p_selection,'selectionEvaluation',v_eval),updated_at=now()
  where id=v_session.id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session.id,'selection.evaluated',
    jsonb_build_object('selection',p_selection,'evaluation',v_eval),
    jsonb_build_object('sourceAuthority','direct_self_submission'),v_idem
  );
  return atlas.public_commitment_session_v1(p_access_token);
end;
$function$;

create or replace function atlas.submit_public_commitment_session_v1(
  p_access_token text,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_session atlas.public_commitment_sessions%rowtype;
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_selection jsonb;
  v_eval jsonb;
  v_resources jsonb:='[]'::jsonb;
  v_key text;
  v_resource reality.resources%rowtype;
  v_request jsonb;
  v_request_id uuid;
  v_snapshot_id uuid;
  v_snapshot_key text;
  v_snapshot_hash text;
  v_line jsonb;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_label text;
  v_purpose text;
  v_business_model_key text;
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash for update;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  if v_session.session_state='materialized' then
    return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'idempotentReplay',true);
  end if;
  if v_session.session_state<>'draft' then raise exception 'Public commitment session is not submit-able.' using errcode='23514'; end if;
  if v_session.requester_entity_id is null then
    raise exception 'Canonical identity resolution is required before request materialization.' using errcode='23514';
  end if;
  if v_idem is not null and exists(select 1 from atlas.public_commitment_events e where e.session_id=v_session.id and e.idempotency_key=v_idem) then
    return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'idempotentReplay',true);
  end if;

  select * into v_surface from atlas.public_commitment_surfaces s where s.id=v_session.surface_id and s.surface_state='active';
  if v_surface.id is null or v_surface.adapter_kind<>'ledger_booking' then raise exception 'Active ledger-booking public surface required.' using errcode='23514'; end if;
  select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id and o.offering_state='active';
  if v_booking.id is null then raise exception 'Active booking offering required.' using errcode='23514'; end if;

  v_selection:=v_session.current_payload->'bookingSelection';
  if v_selection is null then raise exception 'A booking selection must be evaluated before submission.' using errcode='23514'; end if;
  v_eval:=atlas.public_commitment_quote_for_selection_v1(v_surface.id,v_selection);
  if not coalesce((v_eval->>'submissionAllowed')::boolean,false) then
    update atlas.public_commitment_sessions
    set current_payload=jsonb_build_object('bookingSelection',v_selection,'selectionEvaluation',v_eval),updated_at=now()
    where id=v_session.id;
    raise exception 'Current selection is not available for standard public submission.' using errcode='23514';
  end if;

  v_snapshot_key:='public_commitment:'||v_session.id::text||':quote:v1';
  v_snapshot_hash:=encode(extensions.digest((v_eval->'quote')::text,'sha256'),'hex');
  insert into atlas.commercial_offer_snapshots(
    organization_id,organization_unit_id,snapshot_key,title,offer_state,valid_from,valid_until,
    snapshot_sha256,source_kind,source_ref,metadata
  ) values(
    v_surface.organization_id,v_surface.organization_unit_id,v_snapshot_key,
    coalesce(v_session.identity_snapshot->>'name','Customer')||' — '||v_surface.title||' quote',
    'complete',now(),null,v_snapshot_hash,'domain_snapshot',v_session.id::text,
    jsonb_build_object(
      'sourceDomain','public_commitment_surface','surfaceKey',v_surface.surface_key,'sessionId',v_session.id,
      'pricingPolicyKey',v_surface.adapter_config->>'pricingPolicyKey','selection',v_eval->'selection',
      'requiredBeforeConfirmation',v_eval->'quote'->'requiredBeforeConfirmation',
      'remainingBalance',v_eval->'quote'->'remainingBalance'
    )
  ) returning id into v_snapshot_id;

  for v_line in select value from jsonb_array_elements(v_eval->'quote'->'lines')
  loop
    insert into atlas.commercial_offer_snapshot_lines(
      offer_snapshot_id,line_key,commercial_offering_id,description,unit_price,currency,price_basis,terms,source_ref,metadata
    ) values(
      v_snapshot_id,v_line->>'lineKey',v_surface.commercial_offering_id,v_line->>'description',
      (v_line->>'lineTotal')::numeric,v_eval->'quote'->>'currency',v_line->>'priceBasis',
      jsonb_build_object('quantity',(v_line->>'quantity')::numeric,'componentUnitPrice',(v_line->>'unitPrice')::numeric),
      v_session.id::text,
      jsonb_build_object('publicCommitmentSessionId',v_session.id)
    );
  end loop;

  for v_key in select value from jsonb_array_elements_text(v_selection->'resourceKeys')
  loop
    select * into v_resource from reality.resources r
    where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
      and r.stable_key=v_key and r.resource_state='active' and r.reservable;
    if v_resource.id is null then raise exception 'Selected Resource is no longer available as a canonical Resource.' using errcode='23514'; end if;
    v_resources:=v_resources||jsonb_build_array(jsonb_build_object(
      'resourceId',v_resource.id,'claimKind','exclusive',
      'startsAt',v_selection->>'startsAt','endsAt',v_selection->>'endsAt','applyPolicyBuffers',true,
      'metadata',jsonb_build_object('sourceSurfaceKey',v_surface.surface_key,'publicCommitmentSessionId',v_session.id),
      'provenance',jsonb_build_object('sourceAuthority','direct_self_submission','publicCommitmentSessionId',v_session.id)
    ));
  end loop;

  v_label:=coalesce(v_session.identity_snapshot->>'name','Customer')||' — '||coalesce(nullif(v_selection->>'eventType',''),'private venue request');
  v_purpose:=coalesce(v_session.literal_request,
    'Public request for '||coalesce(nullif(v_selection->>'eventType',''),'private venue rental')||
    case when v_selection ? 'guestCount' then ' for approximately '||(v_selection->>'guestCount')||' guests' else '' end
  );
  v_business_model_key:=coalesce(v_surface.adapter_config->>'businessModelKey',v_surface.public_config->>'businessModelKey');

  v_request:=ledger.submit_booking_request_service_v1(
    v_surface.ledger_id,null,v_session.requester_entity_id,null,v_session.requester_entity_id,
    v_booking.booking_kind,v_business_model_key,v_label,v_purpose,v_resources,
    jsonb_build_object(
      'sourceType','public_commitment_surface','sourceDomain','venue','surfaceKey',v_surface.surface_key,
      'publicCommitmentSessionId',v_session.id,'quoteSnapshotId',v_snapshot_id,
      'eventType',v_selection->>'eventType','expectedGuestCount',case when nullif(v_selection->>'guestCount','') is null then null else (v_selection->>'guestCount')::integer end,
      'pricingPolicyKey',v_surface.adapter_config->>'pricingPolicyKey','truthState','public_request_submitted_not_booking'
    ),
    jsonb_build_object('sourceAuthority','direct_self_submission','publicCommitmentSessionId',v_session.id,'surfaceKey',v_surface.surface_key),
    coalesce(v_idem,'public-session:'||v_session.id::text)
  );
  v_request_id:=(v_request->>'requestId')::uuid;

  perform ledger.append_booking_request_event_v1(
    v_request_id,'public_surface.quote_frozen',v_session.requester_entity_id,null,
    jsonb_build_object('publicCommitmentSessionId',v_session.id,'offerSnapshotId',v_snapshot_id,'quote',v_eval->'quote'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),
    'public-session:'||v_session.id::text||':quote-frozen',now()
  );

  update atlas.public_commitment_sessions
  set session_state='materialized',domain_object_kind='ledger_booking_request',domain_object_id=v_request_id,
      quote_snapshot_id=v_snapshot_id,current_payload=jsonb_build_object('bookingSelection',v_selection,'selectionEvaluation',v_eval),
      materialized_at=now(),updated_at=now()
  where id=v_session.id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session.id,'session.materialized',
    jsonb_build_object('domainObjectKind','ledger_booking_request','bookingRequestId',v_request_id,'offerSnapshotId',v_snapshot_id,'quote',v_eval->'quote'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),v_idem
  );

  return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'bookingRequestId',v_request_id,'offerSnapshotId',v_snapshot_id,'idempotentReplay',false);
end;
$function$;

-- Preserve the public membrane: no browser/authenticated direct execution.
revoke all on function atlas.public_commitment_surface_v1(text) from public,anon,authenticated;
revoke all on function atlas.begin_public_commitment_session_v1(text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function atlas.public_commitment_session_v1(text) from public,anon,authenticated;
revoke all on function atlas.set_public_commitment_selection_v1(text,jsonb,text) from public,anon,authenticated;
revoke all on function atlas.submit_public_commitment_session_v1(text,text) from public,anon,authenticated;
revoke all on function atlas.public_commitment_quote_for_selection_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.resolve_public_commitment_person_v1(text,text,text,text) from public,anon,authenticated;

grant execute on function atlas.public_commitment_surface_v1(text) to service_role;
grant execute on function atlas.begin_public_commitment_session_v1(text,text,text,text,text,text,text) to service_role;
grant execute on function atlas.public_commitment_session_v1(text) to service_role;
grant execute on function atlas.set_public_commitment_selection_v1(text,jsonb,text) to service_role;
grant execute on function atlas.submit_public_commitment_session_v1(text,text) to service_role;
grant execute on function atlas.public_commitment_quote_for_selection_v1(uuid,jsonb) to service_role;
grant execute on function atlas.resolve_public_commitment_person_v1(text,text,text,text) to service_role;

-- Elm Farm Venue is the first adopter. Resolve all foreign keys by durable stable keys.
insert into atlas.public_commitment_surfaces(
  surface_key,organization_id,organization_unit_id,title,description,surface_state,adapter_kind,
  ledger_id,booking_offering_id,commercial_offering_id,public_config,adapter_config,metadata,provenance
)
select
  'elm_private_venue_booking_v1',
  o.id,
  u.id,
  'Book Elm Farm',
  'Public request surface for private use of Elm Farm venue resources. Atlas evaluates current resources, policy, price, and commitment requirements before a request can become a booking.',
  'active',
  'ledger_booking',
  l.id,
  b.id,
  c.id,
  jsonb_build_object(
    'brand','Elm Farm',
    'requestKind','private_venue_rental',
    'timezoneName','America/Chicago',
    'publicTruthBoundary',jsonb_build_object(
      'requestIsNotBooking',true,
      'paymentIsNotApproval',true,
      'agreementIsNotApproval',true,
      'availabilityIsNotCommitment',true
    ),
    'standardGuestCountMax',30,
    'standardDurationHoursMax',8
  ),
  jsonb_build_object(
    'addOnPriceBasis',jsonb_build_object(
      'bridal_lounge','bridal_lounge_add_on',
      'stocked_coffee_refreshments','stocked_coffee_refreshments_add_on',
      'wedding_planner_coordinator','wedding_planner_coordinator_add_on'
    ),
    'durationPricing',jsonb_build_object(
      'resourceKey','event_center',
      'basePriceBasis','indoor_house_base_2_hours',
      'incrementMinutes',60,
      'baseIncludedMinutes',120,
      'additionalPriceBasis','indoor_house_additional_hour'
    ),
    'businessModelKey','private_venue_rental_v1',
    'pricingPolicyKey','elm_venue_private_rental_pricing_v1',
    'requireGuestCount',true,
    'nestedResourceRule',jsonb_build_object(
      'bridal_lounge','Commercial/event-plan designation inside an exclusive Event Center reservation; do not create a second overlapping Lounge resource claim.'
    ),
    'publicResourceKeys',jsonb_build_array('event_center','grounds'),
    'resourcePriceBasis',jsonb_build_object('grounds','outdoor_property_add_on'),
    'publicPriceBasisKeys',jsonb_build_array(
      'indoor_house_base_2_hours','indoor_house_additional_hour','indoor_house_8_hours','outdoor_property_add_on',
      'bridal_lounge_add_on','stocked_coffee_refreshments_add_on','wedding_planner_coordinator_add_on',
      'full_elm_wedding_8_hours_up_to_30_guests'
    ),
    'selfServiceMaxMinutes',480,
    'selfServiceGuestCountMax',30
  ),
  jsonb_build_object('firstAdopter','Elm Farm Venue','universalArchitecture','public_commitment_membrane_v1'),
  jsonb_build_object('sourceAuthority','user_directed_atlas_build','sourceConversationDate','2026-09-27')
from atlas.organizations o
join atlas.organization_units u on u.organization_id=o.id and u.stable_key='elm'
join ledger.ledgers l on l.stable_key='elm-farm:venue'
join ledger.booking_offerings b on b.ledger_id=l.id and b.stable_key='elm_private_venue_rental_v1'
join atlas.commercial_offerings c on c.organization_id=o.id and c.organization_unit_id=u.id and c.stable_key='elm_venue_private_rental'
where o.stable_key='elm_farm';

do $proof$
begin
  if not exists(select 1 from atlas.public_commitment_surfaces where surface_key='elm_private_venue_booking_v1' and surface_state='active') then
    raise exception 'Elm public commitment surface failed to resolve its stable-key dependencies.';
  end if;
  if exists(
    select 1
    from information_schema.routine_privileges
    where routine_schema='atlas'
      and routine_name in ('public_commitment_surface_v1','begin_public_commitment_session_v1','public_commitment_session_v1','set_public_commitment_selection_v1','submit_public_commitment_session_v1')
      and grantee in ('PUBLIC','anon','authenticated')
  ) then
    raise exception 'Public commitment gateway RPCs must not be directly executable by public browser roles.';
  end if;
end;
$proof$;


create table reality.resources (
  id uuid primary key default gen_random_uuid(),
  owner_entity_id uuid not null references reality.entities(id) on delete restrict,
  parent_resource_id uuid null references reality.resources(id) on delete restrict,
  stable_key text not null,
  label text not null,
  resource_kind text not null,
  resource_state text not null default 'active' check (resource_state in ('active','inactive','retired')),
  reservable boolean not null default true,
  capacity_mode text not null default 'exclusive' check (capacity_mode in ('exclusive','shared','quantity')),
  capacity_quantity numeric null check (capacity_quantity is null or capacity_quantity > 0),
  capacity_unit text null,
  timezone_name text null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key) <> ''),
  check (btrim(label) <> ''),
  check (btrim(resource_kind) <> ''),
  check (capacity_mode <> 'quantity' or (capacity_quantity is not null and nullif(btrim(capacity_unit),'') is not null)),
  unique(owner_entity_id,stable_key)
);
create index resources_owner_state_idx on reality.resources(owner_entity_id,resource_state,label);
create index resources_parent_idx on reality.resources(parent_resource_id) where parent_resource_id is not null;
alter table reality.resources enable row level security;
create trigger resources_set_updated_at before update on reality.resources for each row execute function atlas.set_updated_at();

create or replace function reality.guard_resource_hierarchy_v1()
returns trigger language plpgsql set search_path='' as $$
declare v_parent_owner uuid;
begin
  if not exists (select 1 from reality.entities e where e.id=new.owner_entity_id and e.identity_state='canonical') then
    raise exception 'Resource owner must be a canonical Reality Entity.' using errcode='23514';
  end if;
  if new.timezone_name is not null and not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=new.timezone_name) then
    raise exception 'Unknown resource timezone: %',new.timezone_name using errcode='22023';
  end if;
  if new.parent_resource_id is not null then
    if new.parent_resource_id=new.id then raise exception 'Resource cannot be its own parent.' using errcode='23514'; end if;
    select r.owner_entity_id into v_parent_owner from reality.resources r where r.id=new.parent_resource_id;
    if v_parent_owner is null then raise exception 'Parent resource not found.' using errcode='23503'; end if;
    if v_parent_owner<>new.owner_entity_id then
      raise exception 'Parent and child resources must have the same owner Entity.' using errcode='23514';
    end if;
    if exists (
      with recursive ancestors as (
        select r.id,r.parent_resource_id from reality.resources r where r.id=new.parent_resource_id
        union all
        select r.id,r.parent_resource_id from reality.resources r join ancestors a on r.id=a.parent_resource_id
      )
      select 1 from ancestors where id=new.id
    ) then
      raise exception 'Resource hierarchy cannot contain a cycle.' using errcode='23514';
    end if;
  end if;
  if tg_op='UPDATE' and new.owner_entity_id is distinct from old.owner_entity_id
     and exists(select 1 from reality.resources r where r.parent_resource_id=old.id) then
    raise exception 'Resource owner cannot change while child resources exist.' using errcode='23514';
  end if;
  return new;
end;
$$;
create trigger resources_guard_hierarchy before insert or update of owner_entity_id,parent_resource_id,timezone_name
on reality.resources for each row execute function reality.guard_resource_hierarchy_v1();

create table ledger.bookings (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  occurrence_id uuid not null references local_intel.occurrences(id) on delete restrict,
  customer_entity_id uuid null references reality.entities(id) on delete restrict,
  booking_kind text not null,
  business_model_key text null,
  booking_label text null,
  booking_state text not null default 'hold' check (booking_state in ('hold','confirmed','cancelled','completed','no_show')),
  created_by_seat_id uuid null references ledger.seats(id) on delete set null,
  confirmed_at timestamptz null,
  cancelled_at timestamptz null,
  completed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(booking_kind) <> '')
);
create unique index bookings_ledger_idempotency_uq on ledger.bookings(ledger_id,idempotency_key) where idempotency_key is not null;
create index bookings_ledger_occurrence_idx on ledger.bookings(ledger_id,occurrence_id,booking_state);
create index bookings_customer_idx on ledger.bookings(customer_entity_id,booking_state) where customer_entity_id is not null;
alter table ledger.bookings enable row level security;
create trigger bookings_set_updated_at before update on ledger.bookings for each row execute function atlas.set_updated_at();

create or replace function ledger.guard_booking_v1()
returns trigger language plpgsql set search_path='' as $$
declare v_seat_ledger uuid; v_seat_state text;
begin
  if not exists (select 1 from ledger.ledgers l where l.id=new.ledger_id and l.ledger_state='active') then
    raise exception 'Booking requires an active Ledger.' using errcode='23514';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=new.occurrence_id) then
    raise exception 'Booking occurrence not found.' using errcode='23503';
  end if;
  if new.customer_entity_id is not null then
    if not exists (select 1 from reality.entities e where e.id=new.customer_entity_id and e.identity_state='canonical') then
      raise exception 'Booking customer must be a canonical Reality Entity.' using errcode='23514';
    end if;
    if not exists (
      select 1 from ledger.entity_contexts c
      where c.ledger_id=new.ledger_id and c.entity_id=new.customer_entity_id and c.context_state='active'
    ) then
      raise exception 'Booking customer requires an active context in this Ledger.' using errcode='23514';
    end if;
  end if;
  if new.created_by_seat_id is not null then
    select s.ledger_id,s.seat_state into v_seat_ledger,v_seat_state from ledger.seats s where s.id=new.created_by_seat_id;
    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id or v_seat_state<>'active' then
      raise exception 'Booking author Seat must be active in the same Ledger.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger bookings_guard before insert or update of ledger_id,occurrence_id,customer_entity_id,created_by_seat_id
on ledger.bookings for each row execute function ledger.guard_booking_v1();

create table ledger.booking_events (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references ledger.bookings(id) on delete cascade,
  event_kind text not null,
  occurred_at timestamptz not null default now(),
  performed_by_entity_id uuid null references reality.entities(id) on delete restrict,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  check (btrim(event_kind) <> '')
);
create unique index booking_events_idempotency_uq on ledger.booking_events(booking_id,idempotency_key) where idempotency_key is not null;
create index booking_events_booking_time_idx on ledger.booking_events(booking_id,occurred_at,id);
alter table ledger.booking_events enable row level security;

create or replace function ledger.prevent_booking_event_mutation_v1()
returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Booking events are append-only.' using errcode='55000'; end;
$$;
create trigger booking_events_append_only before update or delete on ledger.booking_events
for each row execute function ledger.prevent_booking_event_mutation_v1();

create table ledger.booking_references (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references ledger.bookings(id) on delete cascade,
  reference_kind text not null,
  system_key text not null,
  reference_key text not null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  check (btrim(reference_kind) <> ''),
  check (btrim(system_key) <> ''),
  check (btrim(reference_key) <> ''),
  unique(booking_id,reference_kind,system_key,reference_key)
);
create index booking_references_lookup_idx on ledger.booking_references(system_key,reference_kind,reference_key);
alter table ledger.booking_references enable row level security;

create table ledger.occurrence_resource_claims (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  occurrence_id uuid not null references local_intel.occurrences(id) on delete restrict,
  booking_id uuid null references ledger.bookings(id) on delete cascade,
  resource_id uuid not null references reality.resources(id) on delete restrict,
  claim_kind text not null check (claim_kind in ('exclusive','shared','capacity')),
  claim_state text not null default 'tentative' check (claim_state in ('tentative','confirmed','released','cancelled')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  quantity numeric null check (quantity is null or quantity > 0),
  quantity_unit text null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create unique index occurrence_resource_claims_ledger_idempotency_uq on ledger.occurrence_resource_claims(ledger_id,idempotency_key) where idempotency_key is not null;
create index occurrence_resource_claims_resource_window_idx on ledger.occurrence_resource_claims(resource_id,starts_at,ends_at) where claim_state in ('tentative','confirmed');
create index occurrence_resource_claims_occurrence_idx on ledger.occurrence_resource_claims(ledger_id,occurrence_id,claim_state);
create index occurrence_resource_claims_booking_idx on ledger.occurrence_resource_claims(booking_id,claim_state) where booking_id is not null;
alter table ledger.occurrence_resource_claims enable row level security;
create trigger occurrence_resource_claims_set_updated_at before update on ledger.occurrence_resource_claims for each row execute function atlas.set_updated_at();

create or replace function ledger.guard_occurrence_resource_claim_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_subject uuid; v_resource_owner uuid; v_resource_state text; v_reservable boolean; v_capacity_mode text;
  v_booking_ledger uuid; v_booking_occurrence uuid; v_booking_state text;
begin
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=new.ledger_id and l.ledger_state='active';
  if v_subject is null then raise exception 'Resource claim requires an active Ledger.' using errcode='23514'; end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=new.occurrence_id) then
    raise exception 'Resource claim occurrence not found.' using errcode='23503';
  end if;
  select r.owner_entity_id,r.resource_state,r.reservable,r.capacity_mode
  into v_resource_owner,v_resource_state,v_reservable,v_capacity_mode
  from reality.resources r where r.id=new.resource_id;
  if v_resource_owner is null then raise exception 'Resource not found.' using errcode='23503'; end if;
  if v_resource_owner<>v_subject then
    raise exception 'V1 resource claims may reserve only resources owned by the Ledger subject Entity.' using errcode='23514';
  end if;
  if v_resource_state<>'active' or not v_reservable then
    raise exception 'Resource is not currently reservable.' using errcode='23514';
  end if;
  if v_capacity_mode='quantity' and new.claim_kind not in ('capacity','exclusive') then
    raise exception 'Quantity-governed resources require capacity or exclusive claims.' using errcode='23514';
  end if;
  if new.claim_kind='capacity' and (new.quantity is null or nullif(btrim(new.quantity_unit),'') is null) then
    raise exception 'Capacity claims require quantity and quantity_unit.' using errcode='23514';
  end if;
  if new.booking_id is not null then
    select b.ledger_id,b.occurrence_id,b.booking_state
    into v_booking_ledger,v_booking_occurrence,v_booking_state
    from ledger.bookings b where b.id=new.booking_id;
    if v_booking_ledger is null or v_booking_ledger<>new.ledger_id or v_booking_occurrence<>new.occurrence_id then
      raise exception 'Resource claim booking must belong to the same Ledger and occurrence.' using errcode='23514';
    end if;
    if v_booking_state='cancelled' and new.claim_state in ('tentative','confirmed') then
      raise exception 'Cancelled booking cannot hold an active resource claim.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger occurrence_resource_claims_guard before insert or update of ledger_id,occurrence_id,booking_id,resource_id,claim_kind,claim_state,quantity,quantity_unit
on ledger.occurrence_resource_claims for each row execute function ledger.guard_occurrence_resource_claim_v1();

create or replace function reality.upsert_resource_service_v1(
  p_owner_entity_id uuid,p_parent_resource_id uuid,p_stable_key text,p_label text,p_resource_kind text,
  p_resource_state text default 'active',p_reservable boolean default true,p_capacity_mode text default 'exclusive',
  p_capacity_quantity numeric default null,p_capacity_unit text default null,p_timezone_name text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_resource reality.resources%rowtype;
begin
  if nullif(btrim(p_stable_key),'') is null or nullif(btrim(p_label),'') is null or nullif(btrim(p_resource_kind),'') is null then
    raise exception 'Resource stable_key, label, and resource_kind are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Resource metadata must be a JSON object.' using errcode='22023'; end if;
  insert into reality.resources(owner_entity_id,parent_resource_id,stable_key,label,resource_kind,resource_state,reservable,capacity_mode,capacity_quantity,capacity_unit,timezone_name,metadata)
  values(p_owner_entity_id,p_parent_resource_id,btrim(p_stable_key),btrim(p_label),btrim(p_resource_kind),p_resource_state,p_reservable,p_capacity_mode,p_capacity_quantity,nullif(btrim(p_capacity_unit),''),nullif(btrim(p_timezone_name),''),p_metadata)
  on conflict(owner_entity_id,stable_key) do update
  set parent_resource_id=excluded.parent_resource_id,label=excluded.label,resource_kind=excluded.resource_kind,
      resource_state=excluded.resource_state,reservable=excluded.reservable,capacity_mode=excluded.capacity_mode,
      capacity_quantity=excluded.capacity_quantity,capacity_unit=excluded.capacity_unit,timezone_name=excluded.timezone_name,
      metadata=reality.resources.metadata||excluded.metadata,updated_at=now()
  returning * into v_resource;
  return jsonb_build_object('contractVersion','reality_resource_v1','resourceId',v_resource.id,'ownerEntityId',v_resource.owner_entity_id,'parentResourceId',v_resource.parent_resource_id,'stableKey',v_resource.stable_key,'label',v_resource.label,'resourceKind',v_resource.resource_kind,'resourceState',v_resource.resource_state,'reservable',v_resource.reservable,'capacityMode',v_resource.capacity_mode);
end;
$$;

create or replace function ledger.resource_claim_availability_v1(
  p_ledger_id uuid,p_resource_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,
  p_requested_claim_kind text default 'exclusive',p_requested_quantity numeric default null,
  p_exclude_claim_id uuid default null,p_exclude_occurrence_id uuid default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_subject uuid; v_resource reality.resources%rowtype; v_blockers jsonb;
  v_capacity_used numeric:=0; v_capacity_exceeded boolean:=false; v_available boolean:=false;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then raise exception 'Availability window must have starts_at < ends_at.' using errcode='22023'; end if;
  if p_requested_claim_kind not in ('exclusive','shared','capacity') then raise exception 'Unknown requested claim kind: %',p_requested_claim_kind using errcode='22023'; end if;
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';
  if v_subject is null then raise exception 'Active Ledger required.' using errcode='23514'; end if;
  select * into v_resource from reality.resources r where r.id=p_resource_id;
  if v_resource.id is null or v_resource.owner_entity_id<>v_subject then raise exception 'Resource is outside this Ledger subject.' using errcode='23514'; end if;
  if v_resource.capacity_mode='quantity' and p_requested_claim_kind='capacity' and (p_requested_quantity is null or p_requested_quantity<=0) then
    raise exception 'Quantity-governed capacity request requires requested_quantity > 0.' using errcode='22023';
  end if;

  with recursive ancestors as (
    select r.id,r.parent_resource_id from reality.resources r where r.id=p_resource_id
    union all
    select p.id,p.parent_resource_id from reality.resources p join ancestors a on p.id=a.parent_resource_id
  ), descendants as (
    select r.id from reality.resources r where r.id=p_resource_id
    union all
    select c.id from reality.resources c join descendants d on c.parent_resource_id=d.id
  ), related as (select id from ancestors union select id from descendants)
  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,'occurrenceId',c.occurrence_id,'bookingId',c.booking_id,'resourceId',c.resource_id,
    'resourceLabel',rr.label,'claimKind',c.claim_kind,'claimState',c.claim_state,'startsAt',c.starts_at,'endsAt',c.ends_at
  ) order by c.starts_at,c.id),'[]'::jsonb)
  into v_blockers
  from ledger.occurrence_resource_claims c join reality.resources rr on rr.id=c.resource_id
  where c.ledger_id=p_ledger_id and c.claim_state in ('tentative','confirmed')
    and c.starts_at<p_ends_at and c.ends_at>p_starts_at
    and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
    and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id)
    and c.resource_id in (select id from related)
    and (p_requested_claim_kind='exclusive' or c.claim_kind='exclusive');

  if v_resource.capacity_mode='quantity' and p_requested_claim_kind='capacity' then
    select coalesce(sum(c.quantity),0) into v_capacity_used
    from ledger.occurrence_resource_claims c
    where c.ledger_id=p_ledger_id and c.resource_id=p_resource_id
      and c.claim_state in ('tentative','confirmed') and c.claim_kind='capacity'
      and c.starts_at<p_ends_at and c.ends_at>p_starts_at
      and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
      and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id);
    v_capacity_exceeded:=v_capacity_used+p_requested_quantity>v_resource.capacity_quantity;
  end if;

  v_available:=v_resource.resource_state='active' and v_resource.reservable and jsonb_array_length(v_blockers)=0 and not v_capacity_exceeded;
  return jsonb_build_object(
    'contractVersion','ledger_resource_availability_v1','ledgerId',p_ledger_id,'resourceId',v_resource.id,
    'resourceLabel',v_resource.label,'windowStart',p_starts_at,'windowEnd',p_ends_at,
    'requestedClaimKind',p_requested_claim_kind,'requestedQuantity',p_requested_quantity,'available',v_available,
    'resourceState',v_resource.resource_state,'reservable',v_resource.reservable,'capacityMode',v_resource.capacity_mode,
    'capacityQuantity',v_resource.capacity_quantity,'capacityUnit',v_resource.capacity_unit,'capacityUsed',v_capacity_used,
    'capacityExceeded',v_capacity_exceeded,'blockingClaims',v_blockers
  );
end;
$$;

create or replace function ledger.establish_booking_service_v1(
  p_ledger_id uuid,p_occurrence_id uuid,p_booking_kind text,p_customer_entity_id uuid default null,
  p_business_model_key text default null,p_booking_label text default null,p_booking_state text default 'hold',
  p_created_by_seat_id uuid default null,p_metadata jsonb default '{}'::jsonb,p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_booking ledger.bookings%rowtype;
begin
  if nullif(btrim(p_booking_kind),'') is null then raise exception 'booking_kind is required.' using errcode='22023'; end if;
  if p_booking_state not in ('hold','confirmed','cancelled','completed','no_show') then raise exception 'Unknown booking_state: %',p_booking_state using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then raise exception 'Booking metadata and provenance must be JSON objects.' using errcode='22023'; end if;

  insert into ledger.bookings(ledger_id,occurrence_id,customer_entity_id,booking_kind,business_model_key,booking_label,booking_state,created_by_seat_id,confirmed_at,cancelled_at,completed_at,metadata,provenance,idempotency_key)
  values(p_ledger_id,p_occurrence_id,p_customer_entity_id,btrim(p_booking_kind),nullif(btrim(p_business_model_key),''),nullif(btrim(p_booking_label),''),p_booking_state,p_created_by_seat_id,
         case when p_booking_state='confirmed' then now() end,case when p_booking_state='cancelled' then now() end,case when p_booking_state='completed' then now() end,
         p_metadata,p_provenance,nullif(btrim(p_idempotency_key),''))
  on conflict(ledger_id,idempotency_key) where idempotency_key is not null do nothing returning * into v_booking;

  if v_booking.id is null then
    select * into v_booking from ledger.bookings b
    where b.ledger_id=p_ledger_id and b.idempotency_key=nullif(btrim(p_idempotency_key),'')
    order by b.created_at desc,b.id limit 1;
    if v_booking.id is null or v_booking.occurrence_id<>p_occurrence_id or v_booking.booking_kind<>btrim(p_booking_kind)
       or v_booking.customer_entity_id is distinct from p_customer_entity_id then
      raise exception 'Booking idempotency key collides with a different booking.' using errcode='23505';
    end if;
  else
    insert into ledger.booking_events(booking_id,event_kind,occurred_at,payload,provenance,idempotency_key)
    values(v_booking.id,'established',now(),jsonb_build_object('bookingState',v_booking.booking_state,'occurrenceId',v_booking.occurrence_id,'customerEntityId',v_booking.customer_entity_id,'bookingKind',v_booking.booking_kind),p_provenance,
           case when v_booking.idempotency_key is null then null else v_booking.idempotency_key||':established' end);
  end if;

  return jsonb_build_object('contractVersion','ledger_booking_v1','bookingId',v_booking.id,'ledgerId',v_booking.ledger_id,'occurrenceId',v_booking.occurrence_id,'customerEntityId',v_booking.customer_entity_id,'bookingKind',v_booking.booking_kind,'bookingState',v_booking.booking_state);
end;
$$;

create or replace function ledger.transition_booking_state_service_v1(
  p_booking_id uuid,p_new_state text,p_performed_by_entity_id uuid default null,p_occurred_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb,p_provenance jsonb default '{}'::jsonb,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_booking ledger.bookings%rowtype; v_old_state text;
begin
  if p_new_state not in ('hold','confirmed','cancelled','completed','no_show') then raise exception 'Unknown booking state: %',p_new_state using errcode='22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then raise exception 'Booking event payload and provenance must be JSON objects.' using errcode='22023'; end if;
  select * into v_booking from ledger.bookings b where b.id=p_booking_id for update;
  if v_booking.id is null then raise exception 'Booking not found.' using errcode='P0002'; end if;
  v_old_state:=v_booking.booking_state;
  if v_old_state<>p_new_state then
    if not ((v_old_state='hold' and p_new_state in ('confirmed','cancelled')) or (v_old_state='confirmed' and p_new_state in ('cancelled','completed','no_show'))) then
      raise exception 'Invalid booking state transition: % -> %',v_old_state,p_new_state using errcode='23514';
    end if;
    update ledger.bookings
    set booking_state=p_new_state,
        confirmed_at=case when p_new_state='confirmed' then coalesce(confirmed_at,p_occurred_at) else confirmed_at end,
        cancelled_at=case when p_new_state='cancelled' then coalesce(cancelled_at,p_occurred_at) else cancelled_at end,
        completed_at=case when p_new_state='completed' then coalesce(completed_at,p_occurred_at) else completed_at end
    where id=p_booking_id returning * into v_booking;
    if p_new_state='cancelled' then
      update ledger.occurrence_resource_claims
      set claim_state='released',metadata=metadata||jsonb_build_object('releasedByBookingState','cancelled','releasedAt',p_occurred_at)
      where booking_id=p_booking_id and claim_state in ('tentative','confirmed');
    end if;
  end if;
  insert into ledger.booking_events(booking_id,event_kind,occurred_at,performed_by_entity_id,payload,provenance,idempotency_key)
  values(p_booking_id,'state.'||p_new_state,p_occurred_at,p_performed_by_entity_id,jsonb_build_object('fromState',v_old_state,'toState',p_new_state)||p_payload,p_provenance,nullif(btrim(p_idempotency_key),''))
  on conflict(booking_id,idempotency_key) where idempotency_key is not null do nothing;
  return jsonb_build_object('contractVersion','ledger_booking_state_v1','bookingId',v_booking.id,'previousState',v_old_state,'bookingState',v_booking.booking_state);
end;
$$;

create or replace function ledger.add_booking_reference_service_v1(
  p_booking_id uuid,p_reference_kind text,p_system_key text,p_reference_key text,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_ref ledger.booking_references%rowtype;
begin
  if nullif(btrim(p_reference_kind),'') is null or nullif(btrim(p_system_key),'') is null or nullif(btrim(p_reference_key),'') is null then
    raise exception 'Booking reference kind, system, and key are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Booking reference metadata must be a JSON object.' using errcode='22023'; end if;
  if not exists(select 1 from ledger.bookings b where b.id=p_booking_id) then raise exception 'Booking not found.' using errcode='P0002'; end if;
  insert into ledger.booking_references(booking_id,reference_kind,system_key,reference_key,metadata)
  values(p_booking_id,btrim(p_reference_kind),btrim(p_system_key),btrim(p_reference_key),p_metadata)
  on conflict(booking_id,reference_kind,system_key,reference_key) do update
  set metadata=ledger.booking_references.metadata||excluded.metadata returning * into v_ref;
  return jsonb_build_object('contractVersion','ledger_booking_reference_v1','referenceId',v_ref.id,'bookingId',v_ref.booking_id,'referenceKind',v_ref.reference_kind,'systemKey',v_ref.system_key,'referenceKey',v_ref.reference_key);
end;
$$;

create or replace function ledger.establish_occurrence_resource_claim_service_v1(
  p_ledger_id uuid,p_occurrence_id uuid,p_resource_id uuid,p_claim_kind text,p_starts_at timestamptz,p_ends_at timestamptz,
  p_booking_id uuid default null,p_claim_state text default 'tentative',p_quantity numeric default null,p_quantity_unit text default null,
  p_metadata jsonb default '{}'::jsonb,p_provenance jsonb default '{}'::jsonb,p_idempotency_key text default null,p_allow_conflict boolean default false
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_claim ledger.occurrence_resource_claims%rowtype; v_availability jsonb;
begin
  if p_claim_kind not in ('exclusive','shared','capacity') then raise exception 'Unknown claim kind: %',p_claim_kind using errcode='22023'; end if;
  if p_claim_state not in ('tentative','confirmed','released','cancelled') then raise exception 'Unknown claim state: %',p_claim_state using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then raise exception 'Claim metadata and provenance must be JSON objects.' using errcode='22023'; end if;
  if p_claim_state in ('tentative','confirmed') then
    v_availability:=ledger.resource_claim_availability_v1(p_ledger_id,p_resource_id,p_starts_at,p_ends_at,p_claim_kind,p_quantity,null,p_occurrence_id);
    if coalesce((v_availability->>'available')::boolean,false)=false and not p_allow_conflict then
      raise exception 'Resource claim conflicts with current occupancy: %',v_availability using errcode='23P01';
    end if;
  else v_availability:='{}'::jsonb; end if;

  insert into ledger.occurrence_resource_claims(ledger_id,occurrence_id,booking_id,resource_id,claim_kind,claim_state,starts_at,ends_at,quantity,quantity_unit,metadata,provenance,idempotency_key)
  values(p_ledger_id,p_occurrence_id,p_booking_id,p_resource_id,p_claim_kind,p_claim_state,p_starts_at,p_ends_at,p_quantity,nullif(btrim(p_quantity_unit),''),
         p_metadata||case when p_allow_conflict then jsonb_build_object('conflictOverride',true) else '{}'::jsonb end,p_provenance,nullif(btrim(p_idempotency_key),''))
  on conflict(ledger_id,idempotency_key) where idempotency_key is not null do nothing returning * into v_claim;

  if v_claim.id is null then
    select * into v_claim from ledger.occurrence_resource_claims c
    where c.ledger_id=p_ledger_id and c.idempotency_key=nullif(btrim(p_idempotency_key),'')
    order by c.created_at desc,c.id limit 1;
    if v_claim.id is null or v_claim.occurrence_id<>p_occurrence_id or v_claim.resource_id<>p_resource_id or v_claim.claim_kind<>p_claim_kind then
      raise exception 'Resource claim idempotency key collides with a different claim.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object('contractVersion','ledger_occurrence_resource_claim_v1','claimId',v_claim.id,'ledgerId',v_claim.ledger_id,'occurrenceId',v_claim.occurrence_id,'bookingId',v_claim.booking_id,'resourceId',v_claim.resource_id,'claimKind',v_claim.claim_kind,'claimState',v_claim.claim_state,'startsAt',v_claim.starts_at,'endsAt',v_claim.ends_at,'availabilityAtEstablishment',v_availability);
end;
$$;

create or replace function atlas.ledger_resource_availability_service_v1(
  p_ledger_id uuid,p_resource_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,
  p_requested_claim_kind text default 'exclusive',p_requested_quantity numeric default null
) returns jsonb language sql security definer set search_path='' as $$
  select ledger.resource_claim_availability_v1(p_ledger_id,p_resource_id,p_starts_at,p_ends_at,p_requested_claim_kind,p_requested_quantity,null,null)
$$;

create or replace function atlas.ledger_resource_calendar_service_v1(
  p_ledger_id uuid,p_window_start timestamptz,p_window_end timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  if p_window_start is null or p_window_end is null or p_window_end<=p_window_start then
    raise exception 'Calendar window must have window_start < window_end.' using errcode='22023';
  end if;
  if not exists (select 1 from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active') then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;

  with calendar_occurrences as (
    select distinct o.id,o.title,o.occurrence_type,o.start_at,o.end_at,o.status,o.venue_name,o.city,o.state
    from local_intel.occurrences o
    where o.start_at<p_window_end
      and coalesce(o.end_at,o.start_at+interval '1 minute')>p_window_start
      and (
        exists(select 1 from ledger.occurrence_resource_claims c where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed'))
        or exists(select 1 from ledger.bookings b where b.ledger_id=p_ledger_id and b.occurrence_id=o.id and b.booking_state<>'cancelled')
      )
  )
  select jsonb_build_object(
    'contractVersion','ledger_resource_calendar_v1','ledgerId',p_ledger_id,'windowStart',p_window_start,'windowEnd',p_window_end,
    'items',coalesce(jsonb_agg(item order by item->>'startAt',item->>'title'),'[]'::jsonb)
  )
  into v_result
  from (
    select jsonb_build_object(
      'occurrenceId',o.id,'title',o.title,'occurrenceType',o.occurrence_type,'startAt',o.start_at,'endAt',o.end_at,
      'occurrenceState',o.status,'venueName',o.venue_name,'city',o.city,'state',o.state,
      'bookings',coalesce((
        select jsonb_agg(jsonb_build_object(
          'bookingId',b.id,'bookingKind',b.booking_kind,'bookingState',b.booking_state,'bookingLabel',b.booking_label,
          'businessModelKey',b.business_model_key,'customerEntityId',b.customer_entity_id,'customerDisplayName',ce.display_name,
          'references',coalesce((select jsonb_agg(jsonb_build_object('referenceKind',br.reference_kind,'systemKey',br.system_key,'referenceKey',br.reference_key,'metadata',br.metadata) order by br.reference_kind,br.system_key,br.reference_key) from ledger.booking_references br where br.booking_id=b.id),'[]'::jsonb),
          'commercialSnapshot',(
            select jsonb_build_object('orderId',co.id,'orderKind',co.order_kind,'totalAmount',co.total_amount,'currency',co.currency,'paymentState',cp.observed_state,'paidAt',cp.paid_at)
            from ledger.booking_references obr
            join atlas.commercial_orders co on obr.system_key='atlas_commercial' and obr.reference_kind='commercial_order' and obr.reference_key=co.id::text
            left join lateral (
              select p.observed_state,p.paid_at from atlas.commercial_payments p
              where p.commercial_order_id=co.id order by p.paid_at desc nulls last,p.created_at desc limit 1
            ) cp on true
            where obr.booking_id=b.id limit 1
          )
        ) order by b.created_at,b.id)
        from ledger.bookings b left join reality.entities ce on ce.id=b.customer_entity_id
        where b.ledger_id=p_ledger_id and b.occurrence_id=o.id
      ),'[]'::jsonb),
      'resourceClaims',coalesce((
        select jsonb_agg(jsonb_build_object(
          'claimId',c.id,'resourceId',r.id,'resourceLabel',r.label,'resourceKind',r.resource_kind,'parentResourceId',r.parent_resource_id,
          'claimKind',c.claim_kind,'claimState',c.claim_state,'startsAt',c.starts_at,'endsAt',c.ends_at,'quantity',c.quantity,
          'quantityUnit',c.quantity_unit,'classificationState',coalesce(c.metadata->>'classificationState','classified')
        ) order by c.starts_at,r.label,c.id)
        from ledger.occurrence_resource_claims c join reality.resources r on r.id=c.resource_id
        where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
      ),'[]'::jsonb),
      'occupancyState',case
        when not exists(select 1 from ledger.occurrence_resource_claims c where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')) then 'unclassified'
        when exists(
          select 1 from ledger.occurrence_resource_claims c
          cross join lateral (select ledger.resource_claim_availability_v1(p_ledger_id,c.resource_id,c.starts_at,c.ends_at,c.claim_kind,c.quantity,c.id,c.occurrence_id) as availability) a
          where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
            and coalesce((a.availability->>'available')::boolean,false)=false
        ) then 'conflict' else 'clear' end,
      'conflicts',coalesce((
        select jsonb_agg(jsonb_build_object('claimId',c.id,'resourceId',c.resource_id,'availability',a.availability))
        from ledger.occurrence_resource_claims c
        cross join lateral (select ledger.resource_claim_availability_v1(p_ledger_id,c.resource_id,c.starts_at,c.ends_at,c.claim_kind,c.quantity,c.id,c.occurrence_id) as availability) a
        where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
          and coalesce((a.availability->>'available')::boolean,false)=false
      ),'[]'::jsonb)
    ) as item
    from calendar_occurrences o
  ) q;

  return coalesce(v_result,jsonb_build_object('contractVersion','ledger_resource_calendar_v1','ledgerId',p_ledger_id,'windowStart',p_window_start,'windowEnd',p_window_end,'items','[]'::jsonb));
end;
$$;

comment on table reality.resources is 'Universal resources owned by a canonical Reality Entity. Resources may be physical spaces, zones, rooms, equipment, vehicles, capacity pools, or other reservable institutional things. Not farm-specific and not Ledger-owned.';
comment on table ledger.bookings is 'Ledger-scoped current booking commitments tied to canonical occurrences. Commercial/payment truth remains outside this table and may be linked through typed booking references.';
comment on table ledger.occurrence_resource_claims is 'Time-bounded claims by occurrences against universal Reality resources. Claims make occupancy and schedule conflicts deterministic rather than prose-derived.';
comment on table ledger.booking_references is 'Typed references from a booking to external or compatibility systems such as commercial orders, payments, Stripe, Amelia, or other schedulers.';
comment on function atlas.ledger_resource_calendar_service_v1(uuid,timestamptz,timestamptz) is 'Universal resource-aware calendar projection for a Ledger, combining occurrences, bookings, resource occupancy, conflicts, customer identity, and compatible commercial snapshots.';

revoke all on reality.resources from public,anon,authenticated;
revoke all on ledger.bookings from public,anon,authenticated;
revoke all on ledger.booking_events from public,anon,authenticated;
revoke all on ledger.booking_references from public,anon,authenticated;
revoke all on ledger.occurrence_resource_claims from public,anon,authenticated;
revoke execute on function reality.upsert_resource_service_v1(uuid,uuid,text,text,text,text,boolean,text,numeric,text,text,jsonb) from public,anon,authenticated;
revoke execute on function ledger.resource_claim_availability_v1(uuid,uuid,timestamptz,timestamptz,text,numeric,uuid,uuid) from public,anon,authenticated;
revoke execute on function ledger.establish_booking_service_v1(uuid,uuid,text,uuid,text,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.transition_booking_state_service_v1(uuid,text,uuid,timestamptz,jsonb,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.add_booking_reference_service_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke execute on function ledger.establish_occurrence_resource_claim_service_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text,numeric,text,jsonb,jsonb,text,boolean) from public,anon,authenticated;
revoke execute on function atlas.ledger_resource_availability_service_v1(uuid,uuid,timestamptz,timestamptz,text,numeric) from public,anon,authenticated;
revoke execute on function atlas.ledger_resource_calendar_service_v1(uuid,timestamptz,timestamptz) from public,anon,authenticated;

create table ledger.booking_offerings (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  stable_key text not null,
  name text not null,
  description text null,
  booking_kind text not null,
  occurrence_type text not null,
  default_duration_minutes integer not null,
  offering_state text not null default 'draft'
    check (offering_state in ('draft','active','inactive','retired')),
  created_by_seat_id uuid null references ledger.seats(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key)<>''),
  check (btrim(name)<>''),
  check (btrim(booking_kind)<>''),
  check (btrim(occurrence_type)<>''),
  check (default_duration_minutes>0)
);
create unique index booking_offerings_ledger_stable_key_uq
  on ledger.booking_offerings(ledger_id,stable_key);
create index booking_offerings_ledger_state_idx
  on ledger.booking_offerings(ledger_id,offering_state,name);
alter table ledger.booking_offerings enable row level security;
create trigger booking_offerings_set_updated_at
before update on ledger.booking_offerings
for each row execute function atlas.set_updated_at();

create table ledger.booking_offering_requirement_groups (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references ledger.booking_offerings(id) on delete cascade,
  parent_group_id uuid null references ledger.booking_offering_requirement_groups(id) on delete cascade,
  stable_key text not null,
  label text null,
  satisfaction_mode text not null default 'all'
    check (satisfaction_mode in ('all','any','minimum')),
  minimum_satisfied integer null,
  group_state text not null default 'active'
    check (group_state in ('active','inactive')),
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key)<>''),
  check (
    (satisfaction_mode='minimum' and minimum_satisfied is not null and minimum_satisfied>0)
    or (satisfaction_mode<>'minimum' and minimum_satisfied is null)
  )
);
create unique index booking_offering_requirement_groups_stable_key_uq
  on ledger.booking_offering_requirement_groups(offering_id,stable_key);
create unique index booking_offering_requirement_groups_root_uq
  on ledger.booking_offering_requirement_groups(offering_id)
  where parent_group_id is null;
create index booking_offering_requirement_groups_parent_idx
  on ledger.booking_offering_requirement_groups(parent_group_id,sort_order,id)
  where parent_group_id is not null;
alter table ledger.booking_offering_requirement_groups enable row level security;
create trigger booking_offering_requirement_groups_set_updated_at
before update on ledger.booking_offering_requirement_groups
for each row execute function atlas.set_updated_at();

create table ledger.booking_offering_requirements (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references ledger.booking_offerings(id) on delete cascade,
  group_id uuid not null references ledger.booking_offering_requirement_groups(id) on delete cascade,
  stable_key text not null,
  label text null,
  requirement_kind text not null
    check (requirement_kind in ('resource','seat_responsibility')),
  requirement_state text not null default 'active'
    check (requirement_state in ('active','inactive')),
  required_units integer not null default 1 check (required_units>0),
  resource_id uuid null references reality.resources(id) on delete restrict,
  resource_kind text null,
  claim_kind text null check (claim_kind is null or claim_kind in ('exclusive','shared','capacity')),
  claim_quantity numeric null,
  claim_quantity_unit text null,
  seat_responsibility_key text null,
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key)<>''),
  check (
    (
      requirement_kind='resource'
      and ((resource_id is not null) <> (nullif(btrim(resource_kind),'') is not null))
      and claim_kind is not null
      and seat_responsibility_key is null
      and (
        (claim_kind='capacity' and claim_quantity is not null and claim_quantity>0)
        or (claim_kind<>'capacity' and claim_quantity is null and claim_quantity_unit is null)
      )
    )
    or
    (
      requirement_kind='seat_responsibility'
      and resource_id is null
      and resource_kind is null
      and claim_kind is null
      and claim_quantity is null
      and claim_quantity_unit is null
      and nullif(btrim(seat_responsibility_key),'') is not null
    )
  )
);
create unique index booking_offering_requirements_stable_key_uq
  on ledger.booking_offering_requirements(offering_id,stable_key);
create index booking_offering_requirements_group_idx
  on ledger.booking_offering_requirements(group_id,requirement_state,sort_order,id);
create index booking_offering_requirements_resource_idx
  on ledger.booking_offering_requirements(resource_id)
  where resource_id is not null;
alter table ledger.booking_offering_requirements enable row level security;
create trigger booking_offering_requirements_set_updated_at
before update on ledger.booking_offering_requirements
for each row execute function atlas.set_updated_at();

create table ledger.booking_offering_routing_policies (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references ledger.booking_offerings(id) on delete cascade,
  requirement_id uuid not null references ledger.booking_offering_requirements(id) on delete cascade,
  routing_mode text not null default 'manual'
    check (routing_mode in ('manual','requester_choice','first_eligible','ordered_priority')),
  policy_state text not null default 'active'
    check (policy_state in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index booking_offering_routing_policies_requirement_uq
  on ledger.booking_offering_routing_policies(requirement_id);
create index booking_offering_routing_policies_offering_idx
  on ledger.booking_offering_routing_policies(offering_id,policy_state,requirement_id);
alter table ledger.booking_offering_routing_policies enable row level security;
create trigger booking_offering_routing_policies_set_updated_at
before update on ledger.booking_offering_routing_policies
for each row execute function atlas.set_updated_at();

create table ledger.booking_offering_routing_candidates (
  id uuid primary key default gen_random_uuid(),
  routing_policy_id uuid not null references ledger.booking_offering_routing_policies(id) on delete cascade,
  candidate_kind text not null check (candidate_kind in ('resource','seat')),
  resource_id uuid null references reality.resources(id) on delete restrict,
  seat_id uuid null references ledger.seats(id) on delete restrict,
  priority integer not null default 100,
  candidate_state text not null default 'active'
    check (candidate_state in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (candidate_kind='resource' and resource_id is not null and seat_id is null)
    or (candidate_kind='seat' and seat_id is not null and resource_id is null)
  )
);
create unique index booking_offering_routing_candidates_resource_uq
  on ledger.booking_offering_routing_candidates(routing_policy_id,resource_id)
  where resource_id is not null;
create unique index booking_offering_routing_candidates_seat_uq
  on ledger.booking_offering_routing_candidates(routing_policy_id,seat_id)
  where seat_id is not null;
create index booking_offering_routing_candidates_policy_idx
  on ledger.booking_offering_routing_candidates(routing_policy_id,candidate_state,priority,id);
alter table ledger.booking_offering_routing_candidates enable row level security;
create trigger booking_offering_routing_candidates_set_updated_at
before update on ledger.booking_offering_routing_candidates
for each row execute function atlas.set_updated_at();

revoke all on ledger.booking_offerings from public,anon,authenticated;
revoke all on ledger.booking_offering_requirement_groups from public,anon,authenticated;
revoke all on ledger.booking_offering_requirements from public,anon,authenticated;
revoke all on ledger.booking_offering_routing_policies from public,anon,authenticated;
revoke all on ledger.booking_offering_routing_candidates from public,anon,authenticated;

create or replace function ledger.guard_booking_offering_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_seat_ledger uuid;
begin
  if not exists(select 1 from ledger.ledgers l where l.id=new.ledger_id and l.ledger_state='active') then
    raise exception 'Booking offering requires an active Ledger.' using errcode='23514';
  end if;
  if new.created_by_seat_id is not null then
    select s.ledger_id into v_seat_ledger from ledger.seats s where s.id=new.created_by_seat_id;
    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id then
      raise exception 'Booking offering creator Seat must belong to the offering Ledger.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_offerings_guard
before insert or update on ledger.booking_offerings
for each row execute function ledger.guard_booking_offering_v1();

create or replace function ledger.guard_booking_offering_requirement_group_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_parent_offering uuid;
  v_cycle boolean:=false;
begin
  if new.parent_group_id is not null then
    if new.parent_group_id=new.id then
      raise exception 'Requirement group cannot parent itself.' using errcode='23514';
    end if;
    select g.offering_id into v_parent_offering
    from ledger.booking_offering_requirement_groups g
    where g.id=new.parent_group_id;
    if v_parent_offering is null or v_parent_offering<>new.offering_id then
      raise exception 'Requirement group parent must belong to the same offering.' using errcode='23514';
    end if;
    with recursive ancestors(id,parent_group_id) as (
      select g.id,g.parent_group_id from ledger.booking_offering_requirement_groups g where g.id=new.parent_group_id
      union all
      select g.id,g.parent_group_id
      from ledger.booking_offering_requirement_groups g
      join ancestors a on g.id=a.parent_group_id
    )
    select exists(select 1 from ancestors where id=new.id) into v_cycle;
    if v_cycle then
      raise exception 'Requirement group hierarchy cannot contain a cycle.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_offering_requirement_groups_guard
before insert or update on ledger.booking_offering_requirement_groups
for each row execute function ledger.guard_booking_offering_requirement_group_v1();

create or replace function ledger.guard_booking_offering_requirement_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_group_offering uuid;
  v_ledger_id uuid;
  v_subject_entity_id uuid;
  v_resource_owner uuid;
begin
  select g.offering_id into v_group_offering
  from ledger.booking_offering_requirement_groups g
  where g.id=new.group_id;
  if v_group_offering is null or v_group_offering<>new.offering_id then
    raise exception 'Requirement group must belong to the same offering.' using errcode='23514';
  end if;

  if new.requirement_kind='resource' and new.resource_id is not null then
    select o.ledger_id,l.subject_entity_id into v_ledger_id,v_subject_entity_id
    from ledger.booking_offerings o
    join ledger.ledgers l on l.id=o.ledger_id
    where o.id=new.offering_id;
    select r.owner_entity_id into v_resource_owner
    from reality.resources r where r.id=new.resource_id;
    if v_resource_owner is null or v_resource_owner<>v_subject_entity_id then
      raise exception 'Specific Resource requirement must belong to the offering Ledger subject.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_offering_requirements_guard
before insert or update on ledger.booking_offering_requirements
for each row execute function ledger.guard_booking_offering_requirement_v1();

create or replace function ledger.guard_booking_offering_routing_policy_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_requirement_offering uuid;
begin
  select r.offering_id into v_requirement_offering
  from ledger.booking_offering_requirements r
  where r.id=new.requirement_id;
  if v_requirement_offering is null or v_requirement_offering<>new.offering_id then
    raise exception 'Routing policy requirement must belong to the same offering.' using errcode='23514';
  end if;
  return new;
end;
$$;
create trigger booking_offering_routing_policies_guard
before insert or update on ledger.booking_offering_routing_policies
for each row execute function ledger.guard_booking_offering_routing_policy_v1();

create or replace function ledger.guard_booking_offering_routing_candidate_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_requirement ledger.booking_offering_requirements%rowtype;
  v_ledger_id uuid;
  v_subject_entity_id uuid;
  v_resource_kind text;
  v_resource_owner uuid;
  v_seat_ledger uuid;
begin
  select r.* into v_requirement
  from ledger.booking_offering_routing_policies p
  join ledger.booking_offering_requirements r on r.id=p.requirement_id
  where p.id=new.routing_policy_id;
  if v_requirement.id is null then
    raise exception 'Routing candidate requires a valid requirement.' using errcode='23514';
  end if;

  select o.ledger_id,l.subject_entity_id into v_ledger_id,v_subject_entity_id
  from ledger.booking_offerings o
  join ledger.ledgers l on l.id=o.ledger_id
  where o.id=v_requirement.offering_id;

  if v_requirement.requirement_kind='resource' then
    if new.candidate_kind<>'resource' then
      raise exception 'Resource requirement routing candidates must be Resources.' using errcode='23514';
    end if;
    select r.owner_entity_id,r.resource_kind into v_resource_owner,v_resource_kind
    from reality.resources r where r.id=new.resource_id;
    if v_resource_owner is null or v_resource_owner<>v_subject_entity_id then
      raise exception 'Routing Resource must belong to the offering Ledger subject.' using errcode='23514';
    end if;
    if v_requirement.resource_id is not null and new.resource_id<>v_requirement.resource_id then
      raise exception 'Routing Resource must match the specific Resource requirement.' using errcode='23514';
    end if;
    if v_requirement.resource_kind is not null and v_resource_kind<>v_requirement.resource_kind then
      raise exception 'Routing Resource must match the required Resource kind.' using errcode='23514';
    end if;
  else
    if new.candidate_kind<>'seat' then
      raise exception 'Seat responsibility routing candidates must be Seats.' using errcode='23514';
    end if;
    select s.ledger_id into v_seat_ledger from ledger.seats s where s.id=new.seat_id;
    if v_seat_ledger is null or v_seat_ledger<>v_ledger_id then
      raise exception 'Routing Seat must belong to the offering Ledger.' using errcode='23514';
    end if;
    if not exists(
      select 1 from ledger.seat_responsibilities sr
      where sr.seat_id=new.seat_id
        and sr.responsibility_key=v_requirement.seat_responsibility_key
        and sr.responsibility_state='active'
        and (sr.ended_at is null or sr.ended_at>now())
    ) then
      raise exception 'Routing Seat must currently satisfy the required responsibility.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_offering_routing_candidates_guard
before insert or update on ledger.booking_offering_routing_candidates
for each row execute function ledger.guard_booking_offering_routing_candidate_v1();

revoke execute on function ledger.guard_booking_offering_v1() from public,anon,authenticated;
revoke execute on function ledger.guard_booking_offering_requirement_group_v1() from public,anon,authenticated;
revoke execute on function ledger.guard_booking_offering_requirement_v1() from public,anon,authenticated;
revoke execute on function ledger.guard_booking_offering_routing_policy_v1() from public,anon,authenticated;
revoke execute on function ledger.guard_booking_offering_routing_candidate_v1() from public,anon,authenticated;

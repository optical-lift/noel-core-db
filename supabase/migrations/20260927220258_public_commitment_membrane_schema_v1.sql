create table if not exists atlas.public_commitment_surfaces (
  id uuid primary key default gen_random_uuid(),
  surface_key text not null unique check (btrim(surface_key) <> ''),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid null,
  title text not null check (btrim(title) <> ''),
  description text null,
  surface_state text not null default 'draft' check (surface_state in ('draft','active','paused','retired')),
  adapter_kind text not null check (btrim(adapter_kind) <> ''),
  ledger_id uuid null references ledger.ledgers(id) on delete restrict,
  booking_offering_id uuid null references ledger.booking_offerings(id) on delete restrict,
  commercial_offering_id uuid null references atlas.commercial_offerings(id) on delete restrict,
  public_config jsonb not null default '{}'::jsonb check (jsonb_typeof(public_config)='object'),
  adapter_config jsonb not null default '{}'::jsonb check (jsonb_typeof(adapter_config)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict
);

create table if not exists atlas.public_commitment_sessions (
  id uuid primary key default gen_random_uuid(),
  surface_id uuid not null references atlas.public_commitment_surfaces(id) on delete restrict,
  public_token_sha256 text not null unique check (public_token_sha256 ~ '^[0-9a-f]{64}$'),
  requester_entity_id uuid null references reality.entities(id) on delete restrict,
  identity_resolution_state text not null check (identity_resolution_state in ('matched','created','ambiguous','unresolved')),
  identity_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(identity_snapshot)='object'),
  literal_request text null,
  session_state text not null default 'draft' check (session_state in ('draft','materialized','withdrawn','expired')),
  current_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(current_payload)='object'),
  domain_object_kind text null,
  domain_object_id uuid null,
  quote_snapshot_id uuid null references atlas.commercial_offer_snapshots(id) on delete restrict,
  idempotency_key text null check (idempotency_key is null or btrim(idempotency_key)<>''),
  expires_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  materialized_at timestamptz null,
  withdrawn_at timestamptz null
);

create unique index if not exists public_commitment_sessions_surface_idempotency_uq
  on atlas.public_commitment_sessions(surface_id,idempotency_key)
  where idempotency_key is not null;
create index if not exists public_commitment_sessions_surface_state_idx
  on atlas.public_commitment_sessions(surface_id,session_state,created_at desc);
create index if not exists public_commitment_sessions_domain_idx
  on atlas.public_commitment_sessions(domain_object_kind,domain_object_id)
  where domain_object_id is not null;

create table if not exists atlas.public_commitment_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references atlas.public_commitment_sessions(id) on delete cascade,
  event_kind text not null check (btrim(event_kind)<>''),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null check (idempotency_key is null or btrim(idempotency_key)<>''),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists public_commitment_events_session_idem_uq
  on atlas.public_commitment_events(session_id,idempotency_key)
  where idempotency_key is not null;
create index if not exists public_commitment_events_session_time_idx
  on atlas.public_commitment_events(session_id,occurred_at,id);

create or replace function atlas.guard_public_commitment_surface_v1()
returns trigger
language plpgsql
set search_path=''
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

drop trigger if exists guard_public_commitment_surface_v1 on atlas.public_commitment_surfaces;
create trigger guard_public_commitment_surface_v1
before insert or update on atlas.public_commitment_surfaces
for each row execute function atlas.guard_public_commitment_surface_v1();

create or replace function atlas.prevent_public_commitment_event_mutation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  raise exception 'Public commitment event history is append-only.' using errcode='23514';
end;
$function$;

drop trigger if exists prevent_public_commitment_event_mutation_v1 on atlas.public_commitment_events;
create trigger prevent_public_commitment_event_mutation_v1
before update or delete on atlas.public_commitment_events
for each row execute function atlas.prevent_public_commitment_event_mutation_v1();

alter table atlas.public_commitment_surfaces enable row level security;
alter table atlas.public_commitment_sessions enable row level security;
alter table atlas.public_commitment_events enable row level security;
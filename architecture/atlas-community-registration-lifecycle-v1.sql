BEGIN;

-- Atlas Community Registration Lifecycle v1 schema proof.
--
-- Executable reviewed source only. This is NOT a canonical migration.
-- Final migration identity must be generated through the governed Supabase CLI.
--
-- Birth registration state remains historical source evidence.
-- Later lifecycle changes are append-only and current state is read through
-- one effective-position authority.

create table atlas.community_registration_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references atlas.community_registrations(id) on delete restrict,
  from_status text not null
    check (from_status in ('started','submitted','payment_pending','confirmed','cancelled','refunded')),
  to_status text not null
    check (to_status in ('submitted','payment_pending','confirmed','cancelled','refunded')),
  event_kind text not null check (btrim(event_kind) <> ''),
  authority_domain text not null check (btrim(authority_domain) <> ''),
  authority_kind text not null check (btrim(authority_kind) <> ''),
  authority_reference text not null check (btrim(authority_reference) <> ''),
  effective_at timestamptz not null default now(),
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (from_status <> to_status),
  unique (registration_id, idempotency_key)
);

create index community_registration_lifecycle_registration_idx
  on atlas.community_registration_lifecycle_events (registration_id, created_at, id);

alter table atlas.community_registration_lifecycle_events enable row level security;
revoke all on atlas.community_registration_lifecycle_events from anon, authenticated;

create view atlas.community_registration_position_v1
with (security_invoker = true)
as
with latest as (
  select distinct on (e.registration_id)
    e.registration_id,
    e.id as lifecycle_event_id,
    e.to_status,
    e.event_kind,
    e.authority_domain,
    e.authority_kind,
    e.authority_reference,
    e.effective_at,
    e.created_at as lifecycle_event_created_at
  from atlas.community_registration_lifecycle_events e
  order by e.registration_id, e.created_at desc, e.id desc
), milestones as (
  select
    e.registration_id,
    min(e.effective_at) filter (where e.to_status = 'confirmed') as lifecycle_confirmed_at,
    min(e.effective_at) filter (where e.to_status = 'cancelled') as lifecycle_cancelled_at,
    min(e.effective_at) filter (where e.to_status = 'refunded') as lifecycle_refunded_at
  from atlas.community_registration_lifecycle_events e
  group by e.registration_id
)
select
  r.id as registration_id,
  r.offering_id,
  r.registration_number,
  r.registrant_type,
  r.status as birth_status,
  coalesce(l.to_status, r.status) as effective_status,
  r.submitted_at,
  coalesce(r.confirmed_at, m.lifecycle_confirmed_at) as effective_confirmed_at,
  coalesce(r.cancelled_at, m.lifecycle_cancelled_at) as effective_cancelled_at,
  m.lifecycle_refunded_at as effective_refunded_at,
  l.lifecycle_event_id,
  l.event_kind as current_event_kind,
  l.authority_domain as current_authority_domain,
  l.authority_kind as current_authority_kind,
  l.authority_reference as current_authority_reference,
  l.effective_at as current_effective_at,
  r.created_at
from atlas.community_registrations r
left join latest l on l.registration_id = r.id
left join milestones m on m.registration_id = r.id;

revoke all on atlas.community_registration_position_v1 from anon, authenticated;

-- The canonical transition command must take a registration row lock or
-- advisory lock and validate `from_status` against this effective position.
-- It must never trust caller-supplied payment/provider state.
--
-- Minimum governed adapters:
--
-- 1. Payment satisfaction:
--    payment_pending -> confirmed
--    authority must be canonical money-obligation paid position.
--
-- 2. Registration cancellation:
--    payment_pending|confirmed -> cancelled
--    authority must be explicit registration-domain actor/policy.
--
-- 3. Registration refund state where product semantics require it:
--    confirmed|cancelled -> refunded
--    authority must include canonical money reversal/refund evidence.
--
-- The transition command is idempotent on (registration_id,idempotency_key)
-- and rejects an idempotency collision whose requested transition differs.
--
-- submit_public_household_registration_v1 remains the birth command. Once the
-- lifecycle migration is canonical, later code must stop treating the birth
-- `community_registrations.status` column as current state.

ROLLBACK;

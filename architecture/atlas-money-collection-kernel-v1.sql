BEGIN;

-- Atlas Money Collection Kernel v1 schema proof.
--
-- Executable reviewed source only. This is NOT a canonical migration.
-- The final migration identity must be generated with the governed Supabase CLI
-- and released through the noel-core-db production lane.
--
-- Governing order:
-- domain transaction -> money obligation -> collection evidence -> receipt
-- -> receipt allocation -> effective money position -> domain-owned reaction
--
-- This file deliberately contains no Stripe objects and no domain-specific
-- registration/flower columns.

create table atlas.money_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id text not null check (btrim(source_id) <> ''),
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  due_at timestamptz,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  created_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, source_domain, source_kind, source_id, obligation_kind),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, currency)
);

-- v1 source domains only need a durable void/cancellation consequence.
-- Future amount-adjustment vocabulary must be added only when a real domain
-- requires it; do not mutate the obligation birth amount.
create table atlas.money_obligation_void_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  obligation_id uuid not null references atlas.money_obligations(id) on delete restrict,
  reason_kind text not null check (btrim(reason_kind) <> ''),
  source_event_kind text,
  source_event_id text,
  note text,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (obligation_id),
  unique (organization_id, idempotency_key)
);

create table atlas.money_collection_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  requested_amount numeric(14,2) not null check (requested_amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  created_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id, currency)
);

-- Requested application of an attempt to obligations. This is not payment.
create table atlas.money_collection_attempt_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  collection_attempt_id uuid not null references atlas.money_collection_attempts(id) on delete restrict,
  obligation_id uuid not null references atlas.money_obligations(id) on delete restrict,
  requested_amount numeric(14,2) not null check (requested_amount > 0),
  created_at timestamptz not null default now(),
  unique (collection_attempt_id, obligation_id)
);

-- Provider object identifiers are evidence attached to an Atlas attempt.
-- They are not the canonical attempt identity.
create table atlas.money_collection_provider_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  collection_attempt_id uuid not null references atlas.money_collection_attempts(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_object_kind text not null check (btrim(provider_object_kind) <> ''),
  provider_object_key text not null check (btrim(provider_object_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (connected_source_id, provider_object_kind, provider_object_key),
  unique (collection_attempt_id, provider_object_kind)
);

-- Signed/webhook/API payloads arrive as evidence. The application edge verifies
-- provider authenticity first; this table preserves provider-event custody.
create table atlas.money_provider_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  collection_attempt_id uuid references atlas.money_collection_attempts(id) on delete restrict,
  provider_event_key text not null check (btrim(provider_event_key) <> ''),
  event_kind text not null check (btrim(event_kind) <> ''),
  provider_object_kind text,
  provider_object_key text,
  occurred_at timestamptz,
  received_at timestamptz not null default now(),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  normalized_evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  unique (connected_source_id, provider_event_key),
  unique (id, organization_id)
);

create table atlas.money_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  received_at timestamptz not null,
  evidence_kind text not null check (evidence_kind in ('provider_event','manual')),
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  provider_event_id uuid references atlas.money_provider_events(id) on delete restrict,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (provider_event_id),
  unique (id, organization_id, currency),
  check (
    (evidence_kind = 'provider_event' and connected_source_id is not null and provider_event_id is not null)
    or
    (evidence_kind = 'manual' and provider_event_id is null and connected_source_id is null and recorded_by_user_id is not null)
  )
);

-- Actual application of received money to an obligation.
create table atlas.money_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null references atlas.money_receipts(id) on delete restrict,
  obligation_id uuid not null references atlas.money_obligations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (receipt_id, obligation_id, idempotency_key),
  unique (id, receipt_id, organization_id)
);

-- A reversal/refund preserves the historical fact that the receipt existed.
create table atlas.money_receipt_reversal_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null references atlas.money_receipts(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  reversal_kind text not null check (btrim(reversal_kind) <> ''),
  provider_event_id uuid references atlas.money_provider_events(id) on delete restrict,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (provider_event_id)
);

-- Reversal application is explicit so a receipt that covered several
-- obligations does not make Atlas guess which paid position reopened.
create table atlas.money_receipt_allocation_reversal_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_reversal_event_id uuid not null references atlas.money_receipt_reversal_events(id) on delete restrict,
  receipt_allocation_id uuid not null references atlas.money_receipt_allocations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (receipt_reversal_event_id, receipt_allocation_id)
);

create index money_obligations_source_idx
  on atlas.money_obligations (organization_id, source_domain, source_kind, source_id);
create index money_collection_attempts_source_idx
  on atlas.money_collection_attempts (organization_id, connected_source_id, created_at desc);
create index money_provider_events_attempt_idx
  on atlas.money_provider_events (collection_attempt_id, occurred_at, id);
create index money_receipt_allocations_obligation_idx
  on atlas.money_receipt_allocations (obligation_id, created_at, id);
create index money_receipt_allocations_receipt_idx
  on atlas.money_receipt_allocations (receipt_id, created_at, id);
create index money_receipt_reversals_receipt_idx
  on atlas.money_receipt_reversal_events (receipt_id, occurred_at, id);

-- Defense in depth: shared money tables are not direct application APIs.
alter table atlas.money_obligations enable row level security;
alter table atlas.money_obligation_void_events enable row level security;
alter table atlas.money_collection_attempts enable row level security;
alter table atlas.money_collection_attempt_obligations enable row level security;
alter table atlas.money_collection_provider_bindings enable row level security;
alter table atlas.money_provider_events enable row level security;
alter table atlas.money_receipts enable row level security;
alter table atlas.money_receipt_allocations enable row level security;
alter table atlas.money_receipt_reversal_events enable row level security;
alter table atlas.money_receipt_allocation_reversal_events enable row level security;

revoke all on atlas.money_obligations from anon, authenticated;
revoke all on atlas.money_obligation_void_events from anon, authenticated;
revoke all on atlas.money_collection_attempts from anon, authenticated;
revoke all on atlas.money_collection_attempt_obligations from anon, authenticated;
revoke all on atlas.money_collection_provider_bindings from anon, authenticated;
revoke all on atlas.money_provider_events from anon, authenticated;
revoke all on atlas.money_receipts from anon, authenticated;
revoke all on atlas.money_receipt_allocations from anon, authenticated;
revoke all on atlas.money_receipt_reversal_events from anon, authenticated;
revoke all on atlas.money_receipt_allocation_reversal_events from anon, authenticated;

create view atlas.money_receipt_position_v1
with (security_invoker = true)
as
with reversal as (
  select r.receipt_id, sum(r.amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_reversal_events r
  group by r.receipt_id
), allocation as (
  select a.receipt_id, sum(a.amount)::numeric(14,2) as allocated_amount
  from atlas.money_receipt_allocations a
  group by a.receipt_id
), allocation_reversal as (
  select a.receipt_id, sum(ar.amount)::numeric(14,2) as allocation_reversed_amount
  from atlas.money_receipt_allocation_reversal_events ar
  join atlas.money_receipt_allocations a on a.id = ar.receipt_allocation_id
  group by a.receipt_id
)
select
  r.id as receipt_id,
  r.organization_id,
  r.amount as gross_received_amount,
  coalesce(rv.reversed_amount,0)::numeric(14,2) as reversed_amount,
  greatest(r.amount - coalesce(rv.reversed_amount,0),0)::numeric(14,2) as net_received_amount,
  coalesce(a.allocated_amount,0)::numeric(14,2) as gross_allocated_amount,
  coalesce(ar.allocation_reversed_amount,0)::numeric(14,2) as allocation_reversed_amount,
  greatest(coalesce(a.allocated_amount,0)-coalesce(ar.allocation_reversed_amount,0),0)::numeric(14,2) as net_allocated_amount,
  greatest(
    r.amount - coalesce(rv.reversed_amount,0)
      - greatest(coalesce(a.allocated_amount,0)-coalesce(ar.allocation_reversed_amount,0),0),
    0
  )::numeric(14,2) as available_amount,
  r.currency,
  r.evidence_kind,
  r.connected_source_id,
  r.provider_event_id,
  r.received_at,
  r.created_at
from atlas.money_receipts r
left join reversal rv on rv.receipt_id = r.id
left join allocation a on a.receipt_id = r.id
left join allocation_reversal ar on ar.receipt_id = r.id;

create view atlas.money_obligation_position_v1
with (security_invoker = true)
as
with voided as (
  select v.obligation_id, min(v.created_at) as voided_at
  from atlas.money_obligation_void_events v
  group by v.obligation_id
), allocation as (
  select a.obligation_id, sum(a.amount)::numeric(14,2) as allocated_amount
  from atlas.money_receipt_allocations a
  group by a.obligation_id
), allocation_reversal as (
  select a.obligation_id, sum(ar.amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_allocation_reversal_events ar
  join atlas.money_receipt_allocations a on a.id = ar.receipt_allocation_id
  group by a.obligation_id
), position as (
  select
    o.*,
    v.voided_at,
    case when v.obligation_id is null then o.amount else 0::numeric end::numeric(14,2) as effective_obligated_amount,
    coalesce(a.allocated_amount,0)::numeric(14,2) as gross_paid_amount,
    coalesce(ar.reversed_amount,0)::numeric(14,2) as reversed_paid_amount,
    greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)::numeric(14,2) as net_paid_amount
  from atlas.money_obligations o
  left join voided v on v.obligation_id = o.id
  left join allocation a on a.obligation_id = o.id
  left join allocation_reversal ar on ar.obligation_id = o.id
)
select
  p.id as obligation_id,
  p.organization_id,
  p.source_domain,
  p.source_kind,
  p.source_id,
  p.obligation_kind,
  p.amount as original_obligated_amount,
  p.effective_obligated_amount,
  p.gross_paid_amount,
  p.reversed_paid_amount,
  p.net_paid_amount,
  greatest(p.effective_obligated_amount-p.net_paid_amount,0)::numeric(14,2) as open_amount,
  case
    when p.voided_at is not null and p.net_paid_amount > 0 then 'voided_with_unreversed_receipt'
    when p.voided_at is not null then 'voided'
    when p.net_paid_amount = 0 then 'open'
    when p.net_paid_amount < p.effective_obligated_amount then 'partially_paid'
    when p.net_paid_amount = p.effective_obligated_amount then 'paid'
    else 'overpaid'
  end as effective_state,
  p.currency,
  p.due_at,
  p.voided_at,
  p.created_at
from position p;

-- Views are internal projections. No direct anonymous/authenticated read grant.
revoke all on atlas.money_receipt_position_v1 from anon, authenticated;
revoke all on atlas.money_obligation_position_v1 from anon, authenticated;

-- The production migration must add governed core functions that enforce:
-- 1. organization/source custody and domain adapter legitimacy;
-- 2. organization-owned connected_sources with moneyCollection capability;
-- 3. requested-attempt allocations sum exactly to attempt requested amount;
-- 4. provider-event idempotency and conflicting-payload rejection;
-- 5. receipt evidence belongs to the same organization/source custody;
-- 6. receipt allocation cannot exceed effective receipt availability;
-- 7. receipt allocation cannot exceed effective obligation open amount;
-- 8. currencies match throughout one allocation path;
-- 9. reversal amounts cannot exceed effective receipt/allocation amounts;
-- 10. every retry converges on one logical object.
--
-- Domain adapters remain separate:
-- Community Registration: registration -> participation_fee obligation.
-- Flower commerce: flower_sale_order -> sale_total obligation.

ROLLBACK;

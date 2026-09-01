BEGIN;

-- Atlas Money Collection Kernel v1 executable architecture proof.
-- Reviewed source only. NOT a canonical migration.
-- The release migration must be generated with `supabase migration new`.
-- This proof intentionally contains no Stripe objects.

create table atlas.money_source_adapter_coverage (
  id uuid primary key default gen_random_uuid(),
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  adapter_contract text not null check (btrim(adapter_contract) <> ''),
  activated_at timestamptz not null,
  retired_at timestamptz,
  status text not null check (status in ('active','retired')),
  migration_provenance text not null check (btrim(migration_provenance) <> ''),
  source_lower_bound text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (source_domain, source_kind, obligation_kind, adapter_contract),
  check (
    (status='active' and retired_at is null)
    or
    (status='retired' and retired_at is not null and retired_at >= activated_at)
  )
);

create unique index money_source_adapter_one_active_idx
  on atlas.money_source_adapter_coverage (source_domain, source_kind, obligation_kind)
  where status='active';

create table atlas.money_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id text not null check (btrim(source_id) <> ''),
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  adapter_contract text not null check (btrim(adapter_contract) <> ''),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  due_at timestamptz,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  created_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, source_domain, source_kind, source_id, obligation_kind),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  unique (id, organization_id, currency)
);

create table atlas.money_obligation_void_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  obligation_id uuid not null,
  reason_kind text not null check (btrim(reason_kind) <> ''),
  source_event_kind text,
  source_event_id text,
  note text,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (obligation_id),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (obligation_id, organization_id)
    references atlas.money_obligations(id, organization_id) on delete restrict,
  check (
    (source_event_kind is null and source_event_id is null)
    or
    (nullif(btrim(source_event_kind),'') is not null and nullif(btrim(source_event_id),'') is not null)
  )
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
  unique (id, organization_id),
  unique (id, organization_id, currency)
);

create table atlas.money_collection_attempt_obligations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  collection_attempt_id uuid not null,
  obligation_id uuid not null,
  requested_amount numeric(14,2) not null check (requested_amount > 0),
  created_at timestamptz not null default now(),
  unique (collection_attempt_id, obligation_id),
  foreign key (collection_attempt_id, organization_id)
    references atlas.money_collection_attempts(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references atlas.money_obligations(id, organization_id) on delete restrict
);

create table atlas.money_collection_provider_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  collection_attempt_id uuid not null,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_object_kind text not null check (btrim(provider_object_kind) <> ''),
  provider_object_key text not null check (btrim(provider_object_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (connected_source_id, provider_object_kind, provider_object_key),
  unique (collection_attempt_id, provider_object_kind),
  foreign key (collection_attempt_id, organization_id)
    references atlas.money_collection_attempts(id, organization_id) on delete restrict
);

create table atlas.money_provider_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  collection_attempt_id uuid,
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
  unique (id, organization_id),
  foreign key (collection_attempt_id, organization_id)
    references atlas.money_collection_attempts(id, organization_id) on delete restrict,
  check (
    (provider_object_kind is null and provider_object_key is null)
    or
    (nullif(btrim(provider_object_kind),'') is not null and nullif(btrim(provider_object_key),'') is not null)
  )
);

create table atlas.money_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  received_at timestamptz not null,
  evidence_kind text not null check (evidence_kind in ('provider_event','manual')),
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  provider_event_id uuid,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (provider_event_id),
  unique (id, organization_id),
  unique (id, organization_id, currency),
  foreign key (provider_event_id, organization_id)
    references atlas.money_provider_events(id, organization_id) on delete restrict,
  check (
    (evidence_kind='provider_event' and connected_source_id is not null and provider_event_id is not null)
    or
    (evidence_kind='manual' and provider_event_id is null and connected_source_id is null and recorded_by_user_id is not null)
  )
);

create table atlas.money_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null,
  obligation_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (id, organization_id),
  foreign key (receipt_id, organization_id)
    references atlas.money_receipts(id, organization_id) on delete restrict,
  foreign key (obligation_id, organization_id)
    references atlas.money_obligations(id, organization_id) on delete restrict
);

create table atlas.money_receipt_reversal_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  reversal_kind text not null check (btrim(reversal_kind) <> ''),
  provider_event_id uuid,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (provider_event_id),
  unique (id, organization_id),
  foreign key (receipt_id, organization_id)
    references atlas.money_receipts(id, organization_id) on delete restrict,
  foreign key (provider_event_id, organization_id)
    references atlas.money_provider_events(id, organization_id) on delete restrict
);

create table atlas.money_receipt_allocation_reversal_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_reversal_event_id uuid not null,
  receipt_allocation_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (organization_id, idempotency_key),
  unique (receipt_reversal_event_id, receipt_allocation_id),
  foreign key (receipt_reversal_event_id, organization_id)
    references atlas.money_receipt_reversal_events(id, organization_id) on delete restrict,
  foreign key (receipt_allocation_id, organization_id)
    references atlas.money_receipt_allocations(id, organization_id) on delete restrict
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

alter table atlas.money_source_adapter_coverage enable row level security;
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

revoke all on atlas.money_source_adapter_coverage from public, anon, authenticated, service_role;
revoke all on atlas.money_obligations from public, anon, authenticated, service_role;
revoke all on atlas.money_obligation_void_events from public, anon, authenticated, service_role;
revoke all on atlas.money_collection_attempts from public, anon, authenticated, service_role;
revoke all on atlas.money_collection_attempt_obligations from public, anon, authenticated, service_role;
revoke all on atlas.money_collection_provider_bindings from public, anon, authenticated, service_role;
revoke all on atlas.money_provider_events from public, anon, authenticated, service_role;
revoke all on atlas.money_receipts from public, anon, authenticated, service_role;
revoke all on atlas.money_receipt_allocations from public, anon, authenticated, service_role;
revoke all on atlas.money_receipt_reversal_events from public, anon, authenticated, service_role;
revoke all on atlas.money_receipt_allocation_reversal_events from public, anon, authenticated, service_role;

create view atlas.money_receipt_position_v1
with (security_invoker=true)
as
with receipt_reversal as (
  select receipt_id, sum(amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_reversal_events
  group by receipt_id
), allocation as (
  select receipt_id, sum(amount)::numeric(14,2) as allocated_amount
  from atlas.money_receipt_allocations
  group by receipt_id
), allocation_reversal as (
  select a.receipt_id, sum(ar.amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_allocation_reversal_events ar
  join atlas.money_receipt_allocations a on a.id=ar.receipt_allocation_id
  group by a.receipt_id
)
select
  r.id as receipt_id,
  r.organization_id,
  r.amount as gross_received_amount,
  coalesce(rr.reversed_amount,0)::numeric(14,2) as reversed_amount,
  greatest(r.amount-coalesce(rr.reversed_amount,0),0)::numeric(14,2) as net_received_amount,
  coalesce(a.allocated_amount,0)::numeric(14,2) as gross_allocated_amount,
  coalesce(ar.reversed_amount,0)::numeric(14,2) as allocation_reversed_amount,
  greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)::numeric(14,2) as net_allocated_amount,
  greatest(
    greatest(r.amount-coalesce(rr.reversed_amount,0),0)
      - greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0),
    0
  )::numeric(14,2) as available_amount,
  r.currency,
  r.evidence_kind,
  r.connected_source_id,
  r.provider_event_id,
  r.received_at,
  r.created_at
from atlas.money_receipts r
left join receipt_reversal rr on rr.receipt_id=r.id
left join allocation a on a.receipt_id=r.id
left join allocation_reversal ar on ar.receipt_id=r.id;

create view atlas.money_obligation_position_v1
with (security_invoker=true)
as
with voided as (
  select obligation_id, min(created_at) as voided_at
  from atlas.money_obligation_void_events
  group by obligation_id
), allocation as (
  select obligation_id, sum(amount)::numeric(14,2) as allocated_amount
  from atlas.money_receipt_allocations
  group by obligation_id
), allocation_reversal as (
  select a.obligation_id, sum(ar.amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_allocation_reversal_events ar
  join atlas.money_receipt_allocations a on a.id=ar.receipt_allocation_id
  group by a.obligation_id
)
select
  o.id as obligation_id,
  o.organization_id,
  o.source_domain,
  o.source_kind,
  o.source_id,
  o.obligation_kind,
  o.adapter_contract,
  o.amount as original_obligated_amount,
  case when v.obligation_id is null then o.amount else 0::numeric end::numeric(14,2) as effective_obligated_amount,
  coalesce(a.allocated_amount,0)::numeric(14,2) as gross_paid_amount,
  coalesce(ar.reversed_amount,0)::numeric(14,2) as reversed_paid_amount,
  greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)::numeric(14,2) as net_paid_amount,
  greatest(
    (case when v.obligation_id is null then o.amount else 0::numeric end)
      - greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0),
    0
  )::numeric(14,2) as open_amount,
  case
    when v.obligation_id is not null and greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)>0
      then 'voided_with_unreversed_receipt'
    when v.obligation_id is not null then 'voided'
    when greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)=0 then 'open'
    when greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)<o.amount then 'partially_paid'
    when greatest(coalesce(a.allocated_amount,0)-coalesce(ar.reversed_amount,0),0)=o.amount then 'paid'
    else 'overpaid'
  end as effective_state,
  o.currency,
  o.due_at,
  v.voided_at,
  o.created_at
from atlas.money_obligations o
left join voided v on v.obligation_id=o.id
left join allocation a on a.obligation_id=o.id
left join allocation_reversal ar on ar.obligation_id=o.id;

revoke all on atlas.money_receipt_position_v1 from public, anon, authenticated, service_role;
revoke all on atlas.money_obligation_position_v1 from public, anon, authenticated, service_role;

create or replace function atlas.money_create_obligation_core_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_adapter_contract text,
  p_amount numeric,
  p_currency text,
  p_due_at timestamptz,
  p_idempotency_key text,
  p_created_by_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $$
declare
  v_existing atlas.money_obligations%rowtype;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_domain text:=lower(nullif(btrim(coalesce(p_source_domain,'')),''));
  v_kind text:=lower(nullif(btrim(coalesce(p_source_kind,'')),''));
  v_obligation_kind text:=lower(nullif(btrim(coalesce(p_obligation_kind,'')),''));
  v_contract text:=nullif(btrim(coalesce(p_adapter_contract,'')),'');
  v_source_id text:=nullif(btrim(coalesce(p_source_id,'')),'');
  v_currency text:=upper(nullif(btrim(coalesce(p_currency,'')),''));
begin
  if p_organization_id is null or v_key is null or v_domain is null or v_kind is null
     or v_obligation_kind is null or v_contract is null or v_source_id is null
     or p_amount is null or p_amount<=0 or v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid money obligation input.' using errcode='22023';
  end if;

  if not exists (
    select 1 from atlas.money_source_adapter_coverage c
    where c.source_domain=v_domain
      and c.source_kind=v_kind
      and c.obligation_kind=v_obligation_kind
      and c.adapter_contract=v_contract
      and c.status='active'
      and c.activated_at<=now()
  ) then
    raise exception 'Money source adapter is not active.' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':'||v_domain||':'||v_kind||':'||v_source_id||':'||v_obligation_kind,0
  ));

  select * into v_existing
  from atlas.money_obligations o
  where o.organization_id=p_organization_id
    and o.source_domain=v_domain
    and o.source_kind=v_kind
    and o.source_id=v_source_id
    and o.obligation_kind=v_obligation_kind;

  if v_existing.id is not null then
    if v_existing.amount is distinct from round(p_amount,2)
       or v_existing.currency is distinct from v_currency
       or v_existing.adapter_contract is distinct from v_contract then
      raise exception 'Existing obligation conflicts with canonical source truth.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select * into v_existing
  from atlas.money_obligations o
  where o.organization_id=p_organization_id and o.idempotency_key=v_key;

  if v_existing.id is not null then
    raise exception 'Money obligation idempotency key is already bound to another source.' using errcode='23505';
  end if;

  insert into atlas.money_obligations(
    organization_id,source_domain,source_kind,source_id,obligation_kind,adapter_contract,
    amount,currency,due_at,idempotency_key,created_by_user_id,metadata
  ) values (
    p_organization_id,v_domain,v_kind,v_source_id,v_obligation_kind,v_contract,
    round(p_amount,2),v_currency,p_due_at,v_key,p_created_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_source_position_core_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_source_created_at timestamptz,
  p_source_amount numeric,
  p_source_currency text
) returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_activation timestamptz;
  v_contract text;
  v_position record;
  v_domain text:=lower(nullif(btrim(coalesce(p_source_domain,'')),''));
  v_kind text:=lower(nullif(btrim(coalesce(p_source_kind,'')),''));
  v_obligation_kind text:=lower(nullif(btrim(coalesce(p_obligation_kind,'')),''));
  v_source_id text:=nullif(btrim(coalesce(p_source_id,'')),'');
  v_currency text:=upper(nullif(btrim(coalesce(p_source_currency,'')),''));
begin
  if p_organization_id is null or v_domain is null or v_kind is null
     or v_obligation_kind is null or v_source_id is null
     or p_source_created_at is null or p_source_amount is null
     or v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid money source position input.' using errcode='22023';
  end if;

  if round(p_source_amount,2)=0 then
    return jsonb_build_object(
      'coverageState','payment_not_required',
      'sourceDomain',v_domain,'sourceKind',v_kind,'sourceId',v_source_id,
      'obligationId',null,'effectiveState',null,'openAmount',0,'currency',v_currency
    );
  end if;

  if p_source_amount<0 then
    raise exception 'Receivable source amount cannot be negative.' using errcode='22023';
  end if;

  select min(c.activated_at) into v_activation
  from atlas.money_source_adapter_coverage c
  where c.source_domain=v_domain
    and c.source_kind=v_kind
    and c.obligation_kind=v_obligation_kind;

  if v_activation is null or p_source_created_at < v_activation then
    return jsonb_build_object(
      'coverageState','pre_kernel_unknown',
      'sourceDomain',v_domain,'sourceKind',v_kind,'sourceId',v_source_id,
      'obligationId',null,'effectiveState',null,'openAmount',null,'currency',v_currency
    );
  end if;

  select c.adapter_contract into v_contract
  from atlas.money_source_adapter_coverage c
  where c.source_domain=v_domain
    and c.source_kind=v_kind
    and c.obligation_kind=v_obligation_kind
    and c.activated_at<=p_source_created_at
    and (c.retired_at is null or p_source_created_at<c.retired_at)
  order by c.activated_at desc
  limit 1;

  if v_contract is null then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_domain,'sourceKind',v_kind,'sourceId',v_source_id,
      'obligationId',null,'effectiveState',null,'openAmount',null,'currency',v_currency,
      'truthBoundary','source_created_outside_active_adapter_interval'
    );
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1 p
  where p.organization_id=p_organization_id
    and p.source_domain=v_domain
    and p.source_kind=v_kind
    and p.source_id=v_source_id
    and p.obligation_kind=v_obligation_kind;

  if v_position.obligation_id is null then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_domain,'sourceKind',v_kind,'sourceId',v_source_id,
      'obligationId',null,'effectiveState',null,'openAmount',null,'currency',v_currency
    );
  end if;

  if v_position.original_obligated_amount is distinct from round(p_source_amount,2)
     or v_position.currency is distinct from v_currency
     or v_position.adapter_contract is distinct from v_contract then
    raise exception 'Money obligation no longer matches canonical source snapshot.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'coverageState','covered',
    'sourceDomain',v_domain,'sourceKind',v_kind,'sourceId',v_source_id,
    'obligationId',v_position.obligation_id,
    'effectiveState',v_position.effective_state,
    'openAmount',v_position.open_amount,
    'originalObligatedAmount',v_position.original_obligated_amount,
    'netPaidAmount',v_position.net_paid_amount,
    'currency',v_position.currency
  );
end;
$$;

create or replace function atlas.money_create_collection_attempt_core_v1(
  p_connected_source_id uuid,
  p_obligations jsonb,
  p_idempotency_key text,
  p_created_by_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_org uuid;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_attempt atlas.money_collection_attempts%rowtype;
  v_item jsonb;
  v_obligation atlas.money_obligations%rowtype;
  v_position record;
  v_obligation_id uuid;
  v_amount numeric(14,2);
  v_total numeric(14,2):=0;
  v_currency text;
  v_normalized jsonb;
  v_existing_normalized jsonb;
begin
  if p_connected_source_id is null or v_key is null
     or p_obligations is null or jsonb_typeof(p_obligations)<>'array'
     or jsonb_array_length(p_obligations)<1 or jsonb_array_length(p_obligations)>50 then
    raise exception 'Collection attempt requires 1-50 obligation applications.' using errcode='22023';
  end if;

  select s.custodian_organization_id into v_org
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id is not null
    and s.authorization_state='connected'
    and s.revoked_at is null
    and s.capabilities @> '{"moneyCollection":true}'::jsonb;

  if v_org is null then
    raise exception 'Connected source lacks organization-owned money collection custody.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'obligationId',(e.value->>'obligationId')::uuid,
      'amount',round((e.value->>'amount')::numeric,2)
    )
    order by (e.value->>'obligationId')::uuid
  ),'[]'::jsonb)
  into v_normalized
  from jsonb_array_elements(p_obligations) e;

  if jsonb_array_length(v_normalized)<>
     (select count(distinct (e.value->>'obligationId')::uuid) from jsonb_array_elements(p_obligations) e) then
    raise exception 'An obligation may appear only once in a collection attempt.' using errcode='22023';
  end if;

  select * into v_attempt
  from atlas.money_collection_attempts a
  where a.organization_id=v_org and a.idempotency_key=v_key;

  if v_attempt.id is not null then
    select coalesce(jsonb_agg(
      jsonb_build_object('obligationId',ao.obligation_id,'amount',ao.requested_amount)
      order by ao.obligation_id
    ),'[]'::jsonb)
    into v_existing_normalized
    from atlas.money_collection_attempt_obligations ao
    where ao.collection_attempt_id=v_attempt.id;

    if v_attempt.connected_source_id is distinct from p_connected_source_id
       or v_existing_normalized is distinct from v_normalized then
      raise exception 'Collection attempt retry conflicts with existing logical attempt.' using errcode='23505';
    end if;
    return v_attempt.id;
  end if;

  for v_item in
    select value from jsonb_array_elements(p_obligations)
    order by (value->>'obligationId')::uuid
  loop
    begin
      v_obligation_id:=(v_item->>'obligationId')::uuid;
      v_amount:=round((v_item->>'amount')::numeric,2);
    exception when others then
      raise exception 'Collection attempt item has invalid obligationId or amount.' using errcode='22023';
    end;
    if v_amount<=0 then
      raise exception 'Collection attempt item amount must be positive.' using errcode='22023';
    end if;

    select * into v_obligation
    from atlas.money_obligations o
    where o.id=v_obligation_id
    for update;

    if v_obligation.id is null or v_obligation.organization_id is distinct from v_org then
      raise exception 'Collection attempt obligation is outside connected-source organization custody.' using errcode='42501';
    end if;

    select * into v_position
    from atlas.money_obligation_position_v1 p
    where p.obligation_id=v_obligation.id;

    if v_position.effective_state in ('voided','voided_with_unreversed_receipt')
       or v_amount>v_position.open_amount then
      raise exception 'Collection attempt exceeds effective obligation open amount.' using errcode='23514';
    end if;

    if v_currency is null then
      v_currency:=v_obligation.currency;
    elsif v_currency is distinct from v_obligation.currency then
      raise exception 'A collection attempt cannot mix currencies.' using errcode='22023';
    end if;

    v_total:=v_total+v_amount;
  end loop;

  insert into atlas.money_collection_attempts(
    organization_id,connected_source_id,requested_amount,currency,idempotency_key,created_by_user_id,metadata
  ) values (
    v_org,p_connected_source_id,v_total,v_currency,v_key,p_created_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_attempt;

  for v_item in select value from jsonb_array_elements(v_normalized)
  loop
    insert into atlas.money_collection_attempt_obligations(
      organization_id,collection_attempt_id,obligation_id,requested_amount
    ) values (
      v_org,v_attempt.id,(v_item->>'obligationId')::uuid,(v_item->>'amount')::numeric
    );
  end loop;

  return v_attempt.id;
end;
$$;

create or replace function atlas.money_bind_provider_object_core_v1(
  p_collection_attempt_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_attempt atlas.money_collection_attempts%rowtype;
  v_existing atlas.money_collection_provider_bindings%rowtype;
  v_kind text:=lower(nullif(btrim(coalesce(p_provider_object_kind,'')),'');
  v_key text:=nullif(btrim(coalesce(p_provider_object_key,'')),'');
begin
  if p_collection_attempt_id is null or v_kind is null or v_key is null then
    raise exception 'Provider binding requires attempt, object kind, and object key.' using errcode='22023';
  end if;

  select * into v_attempt from atlas.money_collection_attempts where id=p_collection_attempt_id;
  if v_attempt.id is null then raise exception 'Collection attempt not found.' using errcode='P0002'; end if;

  select * into v_existing from atlas.money_collection_provider_bindings b
  where b.collection_attempt_id=v_attempt.id and b.provider_object_kind=v_kind;

  if v_existing.id is not null then
    if v_existing.connected_source_id is distinct from v_attempt.connected_source_id
       or v_existing.provider_object_key is distinct from v_key then
      raise exception 'Provider object binding conflicts with existing attempt binding.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists (
    select 1 from atlas.money_collection_provider_bindings b
    where b.connected_source_id=v_attempt.connected_source_id
      and b.provider_object_kind=v_kind and b.provider_object_key=v_key
  ) then
    raise exception 'Provider object is already bound to another Atlas attempt.' using errcode='23505';
  end if;

  insert into atlas.money_collection_provider_bindings(
    organization_id,collection_attempt_id,connected_source_id,provider_object_kind,provider_object_key,metadata
  ) values (
    v_attempt.organization_id,v_attempt.id,v_attempt.connected_source_id,v_kind,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_admit_provider_event_core_v1(
  p_connected_source_id uuid,
  p_provider_event_key text,
  p_event_kind text,
  p_payload_sha256 text,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_collection_attempt_id uuid,
  p_occurred_at timestamptz,
  p_normalized_evidence jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_org uuid;
  v_attempt_id uuid:=p_collection_attempt_id;
  v_existing atlas.money_provider_events%rowtype;
  v_event_key text:=nullif(btrim(coalesce(p_provider_event_key,'')),'');
  v_event_kind text:=lower(nullif(btrim(coalesce(p_event_kind,'')),''));
  v_hash text:=lower(nullif(btrim(coalesce(p_payload_sha256,'')),''));
  v_object_kind text:=lower(nullif(btrim(coalesce(p_provider_object_kind,'')),''));
  v_object_key text:=nullif(btrim(coalesce(p_provider_object_key,'')),'');
begin
  if p_connected_source_id is null or v_event_key is null or v_event_kind is null
     or v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider event custody input.' using errcode='22023';
  end if;
  if (v_object_kind is null) is distinct from (v_object_key is null) then
    raise exception 'Provider object kind and key must be supplied together.' using errcode='22023';
  end if;

  select s.custodian_organization_id into v_org
  from atlas.connected_sources s
  where s.id=p_connected_source_id and s.custodian_organization_id is not null;
  if v_org is null then raise exception 'Provider event source is not organization-owned.' using errcode='42501'; end if;

  select * into v_existing from atlas.money_provider_events e
  where e.connected_source_id=p_connected_source_id and e.provider_event_key=v_event_key;

  if v_existing.id is not null then
    if v_existing.payload_sha256 is distinct from v_hash then
      raise exception 'Provider event key was redelivered with conflicting payload.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if v_attempt_id is null and v_object_kind is not null then
    select b.collection_attempt_id into v_attempt_id
    from atlas.money_collection_provider_bindings b
    where b.connected_source_id=p_connected_source_id
      and b.provider_object_kind=v_object_kind and b.provider_object_key=v_object_key;
  end if;

  if v_attempt_id is null then
    raise exception 'Provider event cannot be reconciled to a known Atlas collection attempt.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.money_collection_attempts a
    where a.id=v_attempt_id and a.organization_id=v_org and a.connected_source_id=p_connected_source_id
  ) then
    raise exception 'Provider event attempt is outside connected-source custody.' using errcode='42501';
  end if;

  insert into atlas.money_provider_events(
    organization_id,connected_source_id,collection_attempt_id,provider_event_key,event_kind,
    provider_object_kind,provider_object_key,occurred_at,payload_sha256,normalized_evidence,metadata
  ) values (
    v_org,p_connected_source_id,v_attempt_id,v_event_key,v_event_kind,
    v_object_kind,v_object_key,p_occurred_at,v_hash,
    coalesce(p_normalized_evidence,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_record_provider_receipt_core_v1(
  p_provider_event_id uuid,
  p_amount numeric,
  p_currency text,
  p_received_at timestamptz,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_event atlas.money_provider_events%rowtype;
  v_receipt atlas.money_receipts%rowtype;
  v_currency text:=upper(nullif(btrim(coalesce(p_currency,'')),''));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if p_provider_event_id is null or p_amount is null or p_amount<=0
     or v_currency is null or v_currency !~ '^[A-Z]{3}$' or p_received_at is null or v_key is null then
    raise exception 'Invalid provider receipt input.' using errcode='22023';
  end if;

  select * into v_event from atlas.money_provider_events where id=p_provider_event_id;
  if v_event.id is null then raise exception 'Provider event not found.' using errcode='P0002'; end if;

  if exists (select 1 from atlas.money_receipt_reversal_events rr where rr.provider_event_id=v_event.id) then
    raise exception 'Provider event is already used as reversal evidence.' using errcode='23505';
  end if;

  select * into v_receipt from atlas.money_receipts where provider_event_id=v_event.id;
  if v_receipt.id is not null then
    if v_receipt.amount is distinct from round(p_amount,2) or v_receipt.currency is distinct from v_currency
       or v_receipt.received_at is distinct from p_received_at then
      raise exception 'Provider receipt retry conflicts with existing receipt.' using errcode='23505';
    end if;
    return v_receipt.id;
  end if;

  if exists (select 1 from atlas.money_receipts r where r.organization_id=v_event.organization_id and r.idempotency_key=v_key) then
    raise exception 'Receipt idempotency key is already bound to another receipt.' using errcode='23505';
  end if;

  insert into atlas.money_receipts(
    organization_id,amount,currency,received_at,evidence_kind,connected_source_id,
    provider_event_id,idempotency_key,metadata
  ) values (
    v_event.organization_id,round(p_amount,2),v_currency,p_received_at,'provider_event',
    v_event.connected_source_id,v_event.id,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_receipt;

  return v_receipt.id;
end;
$$;

create or replace function atlas.money_record_manual_receipt_core_v1(
  p_organization_id uuid,
  p_amount numeric,
  p_currency text,
  p_received_at timestamptz,
  p_recorded_by_user_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_receipt atlas.money_receipts%rowtype;
  v_currency text:=upper(nullif(btrim(coalesce(p_currency,'')),''));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if p_organization_id is null or p_amount is null or p_amount<=0
     or v_currency is null or v_currency !~ '^[A-Z]{3}$' or p_received_at is null
     or p_recorded_by_user_id is null or v_key is null then
    raise exception 'Invalid manual receipt input.' using errcode='22023';
  end if;

  select * into v_receipt from atlas.money_receipts r
  where r.organization_id=p_organization_id and r.idempotency_key=v_key;

  if v_receipt.id is not null then
    if v_receipt.evidence_kind is distinct from 'manual'
       or v_receipt.amount is distinct from round(p_amount,2)
       or v_receipt.currency is distinct from v_currency
       or v_receipt.received_at is distinct from p_received_at
       or v_receipt.recorded_by_user_id is distinct from p_recorded_by_user_id then
      raise exception 'Manual receipt retry conflicts with existing receipt.' using errcode='23505';
    end if;
    return v_receipt.id;
  end if;

  insert into atlas.money_receipts(
    organization_id,amount,currency,received_at,evidence_kind,recorded_by_user_id,idempotency_key,metadata
  ) values (
    p_organization_id,round(p_amount,2),v_currency,p_received_at,'manual',
    p_recorded_by_user_id,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_receipt;

  return v_receipt.id;
end;
$$;

create or replace function atlas.money_allocate_receipt_core_v1(
  p_receipt_id uuid,
  p_obligation_id uuid,
  p_amount numeric,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_receipt atlas.money_receipts%rowtype;
  v_obligation atlas.money_obligations%rowtype;
  v_receipt_position record;
  v_obligation_position record;
  v_existing atlas.money_receipt_allocations%rowtype;
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_amount numeric(14,2):=round(p_amount,2);
begin
  if p_receipt_id is null or p_obligation_id is null or p_amount is null or v_amount<=0 or v_key is null then
    raise exception 'Invalid receipt allocation input.' using errcode='22023';
  end if;

  select * into v_obligation from atlas.money_obligations where id=p_obligation_id for update;
  select * into v_receipt from atlas.money_receipts where id=p_receipt_id for update;
  if v_obligation.id is null or v_receipt.id is null then raise exception 'Receipt or obligation not found.' using errcode='P0002'; end if;

  if v_obligation.organization_id is distinct from v_receipt.organization_id
     or v_obligation.currency is distinct from v_receipt.currency then
    raise exception 'Receipt allocation crosses organization or currency custody.' using errcode='42501';
  end if;

  select * into v_existing from atlas.money_receipt_allocations a
  where a.organization_id=v_receipt.organization_id and a.idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from p_receipt_id
       or v_existing.obligation_id is distinct from p_obligation_id
       or v_existing.amount is distinct from v_amount then
      raise exception 'Receipt allocation retry conflicts with existing allocation.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select * into v_receipt_position from atlas.money_receipt_position_v1 where receipt_id=v_receipt.id;
  select * into v_obligation_position from atlas.money_obligation_position_v1 where obligation_id=v_obligation.id;

  if v_amount>v_receipt_position.available_amount then
    raise exception 'Receipt allocation exceeds effective receipt availability.' using errcode='23514';
  end if;
  if v_obligation_position.effective_state in ('voided','voided_with_unreversed_receipt')
     or v_amount>v_obligation_position.open_amount then
    raise exception 'Receipt allocation exceeds effective obligation open amount.' using errcode='23514';
  end if;

  insert into atlas.money_receipt_allocations(
    organization_id,receipt_id,obligation_id,amount,idempotency_key,metadata
  ) values (
    v_receipt.organization_id,v_receipt.id,v_obligation.id,v_amount,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_void_obligation_core_v1(
  p_obligation_id uuid,
  p_reason_kind text,
  p_source_event_kind text,
  p_source_event_id text,
  p_note text,
  p_recorded_by_user_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_obligation atlas.money_obligations%rowtype;
  v_existing atlas.money_obligation_void_events%rowtype;
  v_reason text:=lower(nullif(btrim(coalesce(p_reason_kind,'')),''));
  v_event_kind text:=lower(nullif(btrim(coalesce(p_source_event_kind,'')),''));
  v_event_id text:=nullif(btrim(coalesce(p_source_event_id,'')),'');
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if p_obligation_id is null or v_reason is null or v_key is null
     or ((v_event_kind is null) is distinct from (v_event_id is null)) then
    raise exception 'Invalid obligation void input.' using errcode='22023';
  end if;

  select * into v_obligation from atlas.money_obligations where id=p_obligation_id for update;
  if v_obligation.id is null then raise exception 'Obligation not found.' using errcode='P0002'; end if;

  select * into v_existing from atlas.money_obligation_void_events where obligation_id=v_obligation.id;
  if v_existing.id is not null then
    if v_existing.reason_kind is distinct from v_reason
       or v_existing.source_event_kind is distinct from v_event_kind
       or v_existing.source_event_id is distinct from v_event_id then
      raise exception 'Obligation already has conflicting void evidence.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists (select 1 from atlas.money_obligation_void_events e where e.organization_id=v_obligation.organization_id and e.idempotency_key=v_key) then
    raise exception 'Obligation void idempotency key is already bound.' using errcode='23505';
  end if;

  insert into atlas.money_obligation_void_events(
    organization_id,obligation_id,reason_kind,source_event_kind,source_event_id,note,
    idempotency_key,recorded_by_user_id,metadata
  ) values (
    v_obligation.organization_id,v_obligation.id,v_reason,v_event_kind,v_event_id,
    nullif(btrim(coalesce(p_note,'')),''),v_key,p_recorded_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_reverse_receipt_core_v1(
  p_receipt_id uuid,
  p_amount numeric,
  p_reversal_kind text,
  p_provider_event_id uuid,
  p_recorded_by_user_id uuid,
  p_occurred_at timestamptz,
  p_allocation_reversals jsonb,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $$
declare
  v_receipt atlas.money_receipts%rowtype;
  v_position record;
  v_existing atlas.money_receipt_reversal_events%rowtype;
  v_event atlas.money_provider_events%rowtype;
  v_item jsonb;
  v_allocation atlas.money_receipt_allocations%rowtype;
  v_amount numeric(14,2):=round(p_amount,2);
  v_kind text:=lower(nullif(btrim(coalesce(p_reversal_kind,'')),''));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_allocation_total numeric(14,2):=0;
  v_required_allocation_reversal numeric(14,2);
  v_line_amount numeric(14,2);
  v_allocation_id uuid;
  v_effective_allocation numeric(14,2);
begin
  if p_receipt_id is null or p_amount is null or v_amount<=0 or v_kind is null
     or p_occurred_at is null or v_key is null
     or p_allocation_reversals is null or jsonb_typeof(p_allocation_reversals)<>'array' then
    raise exception 'Invalid receipt reversal input.' using errcode='22023';
  end if;

  select * into v_receipt from atlas.money_receipts where id=p_receipt_id for update;
  if v_receipt.id is null then raise exception 'Receipt not found.' using errcode='P0002'; end if;

  select * into v_existing from atlas.money_receipt_reversal_events r
  where r.organization_id=v_receipt.organization_id and r.idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from v_receipt.id
       or v_existing.amount is distinct from v_amount
       or v_existing.reversal_kind is distinct from v_kind
       or v_existing.provider_event_id is distinct from p_provider_event_id then
      raise exception 'Receipt reversal retry conflicts with existing reversal.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select * into v_position from atlas.money_receipt_position_v1 where receipt_id=v_receipt.id;
  if v_amount>v_position.net_received_amount then
    raise exception 'Receipt reversal exceeds effective received amount.' using errcode='23514';
  end if;

  if p_provider_event_id is not null then
    select * into v_event from atlas.money_provider_events where id=p_provider_event_id;
    if v_event.id is null or v_event.organization_id is distinct from v_receipt.organization_id
       or v_event.connected_source_id is distinct from v_receipt.connected_source_id then
      raise exception 'Reversal provider event is outside receipt custody.' using errcode='42501';
    end if;
    if exists (select 1 from atlas.money_receipts r where r.provider_event_id=v_event.id) then
      raise exception 'Provider event is already used as receipt evidence.' using errcode='23505';
    end if;
  elsif p_recorded_by_user_id is null then
    raise exception 'Manual reversal requires recorder identity.' using errcode='22023';
  end if;

  if jsonb_array_length(p_allocation_reversals)<>
     (select count(distinct (e.value->>'allocationId')::uuid) from jsonb_array_elements(p_allocation_reversals) e) then
    raise exception 'A receipt allocation may appear only once in a reversal.' using errcode='22023';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_allocation_reversals)
    order by (value->>'allocationId')::uuid
  loop
    begin
      v_allocation_id:=(v_item->>'allocationId')::uuid;
      v_line_amount:=round((v_item->>'amount')::numeric,2);
    exception when others then
      raise exception 'Receipt reversal allocation item is invalid.' using errcode='22023';
    end;
    if v_line_amount<=0 then raise exception 'Allocation reversal amount must be positive.' using errcode='22023'; end if;

    select * into v_allocation from atlas.money_receipt_allocations a where a.id=v_allocation_id for update;
    if v_allocation.id is null or v_allocation.receipt_id is distinct from v_receipt.id then
      raise exception 'Allocation reversal is outside receipt custody.' using errcode='42501';
    end if;

    select greatest(v_allocation.amount-coalesce(sum(ar.amount),0),0)::numeric(14,2)
    into v_effective_allocation
    from atlas.money_receipt_allocation_reversal_events ar
    where ar.receipt_allocation_id=v_allocation.id;

    if v_line_amount>v_effective_allocation then
      raise exception 'Allocation reversal exceeds effective allocation amount.' using errcode='23514';
    end if;
    v_allocation_total:=v_allocation_total+v_line_amount;
  end loop;

  v_required_allocation_reversal:=greatest(v_amount-v_position.available_amount,0);
  if v_allocation_total is distinct from v_required_allocation_reversal then
    raise exception 'Allocation reversals must exactly cover the allocated portion of the receipt reversal.' using errcode='23514';
  end if;

  insert into atlas.money_receipt_reversal_events(
    organization_id,receipt_id,amount,reversal_kind,provider_event_id,recorded_by_user_id,
    occurred_at,idempotency_key,metadata
  ) values (
    v_receipt.organization_id,v_receipt.id,v_amount,v_kind,p_provider_event_id,p_recorded_by_user_id,
    p_occurred_at,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  for v_item in select value from jsonb_array_elements(p_allocation_reversals)
  loop
    insert into atlas.money_receipt_allocation_reversal_events(
      organization_id,receipt_reversal_event_id,receipt_allocation_id,amount,idempotency_key,metadata
    ) values (
      v_receipt.organization_id,v_existing.id,(v_item->>'allocationId')::uuid,
      round((v_item->>'amount')::numeric,2),
      v_key||':allocation:'||(v_item->>'allocationId'),
      jsonb_build_object('receiptReversalId',v_existing.id)
    );
  end loop;

  return v_existing.id;
end;
$$;

revoke all on function atlas.money_create_obligation_core_v1(uuid,text,text,text,text,text,numeric,text,timestamptz,text,uuid,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_source_position_core_v1(uuid,text,text,text,text,timestamptz,numeric,text)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_create_collection_attempt_core_v1(uuid,jsonb,text,uuid,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_bind_provider_object_core_v1(uuid,text,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_admit_provider_event_core_v1(uuid,text,text,text,text,text,uuid,timestamptz,jsonb,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_record_provider_receipt_core_v1(uuid,numeric,text,timestamptz,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_record_manual_receipt_core_v1(uuid,numeric,text,timestamptz,uuid,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_allocate_receipt_core_v1(uuid,uuid,numeric,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_void_obligation_core_v1(uuid,text,text,text,text,uuid,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function atlas.money_reverse_receipt_core_v1(uuid,numeric,text,uuid,uuid,timestamptz,jsonb,text,jsonb)
  from public, anon, authenticated, service_role;

ROLLBACK;

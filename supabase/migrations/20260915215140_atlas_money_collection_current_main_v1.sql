begin;

-- Package 5 / Money + Financial Reality
-- Money Collection current-main foundation v1.
--
-- Governing order:
-- source transaction -> monetary obligation -> received-money evidence
-- -> receipt -> allocation -> effective paid/open position.
--
-- This tranche deliberately does not make Stripe, commercial payment rows,
-- fulfillment, or a mutable provider status the canonical Money clock.

create table atlas.money_obligations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id text not null check (btrim(source_id) <> ''),
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  due_at timestamptz,
  source_occurred_at timestamptz,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (ledger_id, source_domain, source_kind, source_id, obligation_kind),
  unique (ledger_id, idempotency_key),
  unique (id, ledger_id, organization_id, currency)
);

create table atlas.money_obligation_void_events (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  obligation_id uuid not null references atlas.money_obligations(id) on delete restrict,
  reason_kind text not null check (btrim(reason_kind) <> ''),
  evidence_domain text,
  evidence_kind text,
  evidence_id text,
  note text,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (obligation_id),
  unique (ledger_id, idempotency_key)
);

create table atlas.money_receipts (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  received_at timestamptz not null,
  evidence_domain text not null check (btrim(evidence_domain) <> ''),
  evidence_kind text not null check (btrim(evidence_kind) <> ''),
  evidence_id text not null check (btrim(evidence_id) <> ''),
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (ledger_id, evidence_domain, evidence_kind, evidence_id),
  unique (ledger_id, idempotency_key),
  unique (id, ledger_id, organization_id, currency)
);

create table atlas.money_receipt_allocations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null references atlas.money_receipts(id) on delete restrict,
  obligation_id uuid not null references atlas.money_obligations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (ledger_id, idempotency_key),
  unique (receipt_id, obligation_id, idempotency_key),
  unique (id, receipt_id, obligation_id)
);

create table atlas.money_receipt_reversals (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  receipt_id uuid not null references atlas.money_receipts(id) on delete restrict,
  allocation_id uuid references atlas.money_receipt_allocations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  reversal_kind text not null check (btrim(reversal_kind) <> ''),
  evidence_domain text not null check (btrim(evidence_domain) <> ''),
  evidence_kind text not null check (btrim(evidence_kind) <> ''),
  evidence_id text not null check (btrim(evidence_id) <> ''),
  occurred_at timestamptz not null,
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (ledger_id, evidence_domain, evidence_kind, evidence_id),
  unique (ledger_id, idempotency_key)
);

create index money_obligations_source_idx
  on atlas.money_obligations(ledger_id,source_domain,source_kind,source_id);
create index money_receipt_allocations_obligation_idx
  on atlas.money_receipt_allocations(obligation_id,created_at,id);
create index money_receipt_allocations_receipt_idx
  on atlas.money_receipt_allocations(receipt_id,created_at,id);
create index money_receipt_reversals_receipt_idx
  on atlas.money_receipt_reversals(receipt_id,occurred_at,id);
create index money_receipt_reversals_allocation_idx
  on atlas.money_receipt_reversals(allocation_id,occurred_at,id)
  where allocation_id is not null;

alter table atlas.money_obligations enable row level security;
alter table atlas.money_obligation_void_events enable row level security;
alter table atlas.money_receipts enable row level security;
alter table atlas.money_receipt_allocations enable row level security;
alter table atlas.money_receipt_reversals enable row level security;

revoke all on atlas.money_obligations from public,anon,authenticated,service_role;
revoke all on atlas.money_obligation_void_events from public,anon,authenticated,service_role;
revoke all on atlas.money_receipts from public,anon,authenticated,service_role;
revoke all on atlas.money_receipt_allocations from public,anon,authenticated,service_role;
revoke all on atlas.money_receipt_reversals from public,anon,authenticated,service_role;

create or replace function atlas.prevent_money_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Money history is append-only; record a governed consequence instead.'
    using errcode='55000';
end;
$function$;

create trigger money_obligations_append_only_v1
before update or delete on atlas.money_obligations
for each row execute function atlas.prevent_money_history_mutation_v1();

create trigger money_obligation_void_events_append_only_v1
before update or delete on atlas.money_obligation_void_events
for each row execute function atlas.prevent_money_history_mutation_v1();

create trigger money_receipts_append_only_v1
before update or delete on atlas.money_receipts
for each row execute function atlas.prevent_money_history_mutation_v1();

create trigger money_receipt_allocations_append_only_v1
before update or delete on atlas.money_receipt_allocations
for each row execute function atlas.prevent_money_history_mutation_v1();

create trigger money_receipt_reversals_append_only_v1
before update or delete on atlas.money_receipt_reversals
for each row execute function atlas.prevent_money_history_mutation_v1();

create or replace view atlas.money_receipt_position_v1
with (security_invoker=true)
as
with allocation as (
  select a.receipt_id,
         sum(a.amount)::numeric(14,2) as gross_allocated_amount
  from atlas.money_receipt_allocations a
  group by a.receipt_id
),
reversal as (
  select r.receipt_id,
         sum(r.amount)::numeric(14,2) as reversed_amount,
         sum(r.amount) filter (where r.allocation_id is not null)::numeric(14,2)
           as allocation_reversed_amount
  from atlas.money_receipt_reversals r
  group by r.receipt_id
)
select
  r.id as receipt_id,
  r.ledger_id,
  r.organization_id,
  r.amount as gross_received_amount,
  coalesce(rv.reversed_amount,0)::numeric(14,2) as reversed_amount,
  greatest(r.amount-coalesce(rv.reversed_amount,0),0)::numeric(14,2) as net_received_amount,
  coalesce(a.gross_allocated_amount,0)::numeric(14,2) as gross_allocated_amount,
  coalesce(rv.allocation_reversed_amount,0)::numeric(14,2) as allocation_reversed_amount,
  greatest(coalesce(a.gross_allocated_amount,0)-coalesce(rv.allocation_reversed_amount,0),0)::numeric(14,2)
    as net_allocated_amount,
  greatest(
    r.amount-coalesce(rv.reversed_amount,0)
    - greatest(coalesce(a.gross_allocated_amount,0)-coalesce(rv.allocation_reversed_amount,0),0),
    0
  )::numeric(14,2) as available_amount,
  r.currency,
  r.evidence_domain,
  r.evidence_kind,
  r.evidence_id,
  r.connected_source_id,
  r.received_at,
  r.created_at
from atlas.money_receipts r
left join allocation a on a.receipt_id=r.id
left join reversal rv on rv.receipt_id=r.id;

create or replace view atlas.money_obligation_position_v1
with (security_invoker=true)
as
with allocation as (
  select a.obligation_id,
         sum(a.amount)::numeric(14,2) as gross_applied_amount
  from atlas.money_receipt_allocations a
  group by a.obligation_id
),
reversal as (
  select a.obligation_id,
         sum(r.amount)::numeric(14,2) as reversed_applied_amount
  from atlas.money_receipt_reversals r
  join atlas.money_receipt_allocations a on a.id=r.allocation_id
  where r.allocation_id is not null
  group by a.obligation_id
),
voided as (
  select v.obligation_id,min(v.created_at) as voided_at
  from atlas.money_obligation_void_events v
  group by v.obligation_id
)
select
  o.id as obligation_id,
  o.ledger_id,
  o.organization_id,
  o.source_domain,
  o.source_kind,
  o.source_id,
  o.obligation_kind,
  o.amount as original_amount,
  case when v.obligation_id is not null then 0 else o.amount end::numeric(14,2)
    as effective_obligated_amount,
  coalesce(a.gross_applied_amount,0)::numeric(14,2) as gross_applied_amount,
  coalesce(ar.reversed_applied_amount,0)::numeric(14,2) as reversed_applied_amount,
  greatest(coalesce(a.gross_applied_amount,0)-coalesce(ar.reversed_applied_amount,0),0)::numeric(14,2)
    as net_applied_amount,
  case
    when v.obligation_id is not null then 0
    else greatest(
      o.amount-greatest(coalesce(a.gross_applied_amount,0)-coalesce(ar.reversed_applied_amount,0),0),
      0
    )
  end::numeric(14,2) as open_amount,
  case
    when v.obligation_id is not null then 'voided'
    when greatest(coalesce(a.gross_applied_amount,0)-coalesce(ar.reversed_applied_amount,0),0)>=o.amount then 'paid'
    when greatest(coalesce(a.gross_applied_amount,0)-coalesce(ar.reversed_applied_amount,0),0)>0 then
      case when coalesce(ar.reversed_applied_amount,0)>0 then 'reopened' else 'partially_paid' end
    when coalesce(ar.reversed_applied_amount,0)>0 then 'reopened'
    else 'open'
  end as effective_state,
  o.currency,
  o.due_at,
  o.source_occurred_at,
  v.voided_at,
  o.created_at
from atlas.money_obligations o
left join allocation a on a.obligation_id=o.id
left join reversal ar on ar.obligation_id=o.id
left join voided v on v.obligation_id=o.id;

revoke all on atlas.money_receipt_position_v1 from public,anon,authenticated,service_role;
revoke all on atlas.money_obligation_position_v1 from public,anon,authenticated,service_role;

-- Resolve a farm-scoped source into current canonical institutional custody.
-- Archived/test sources intentionally resolve without a canonical Money address.
create or replace function atlas.money_source_farm_custody_v1(p_farm_id uuid)
returns table(
  physical_organization_id uuid,
  effective_organization_id uuid,
  effective_ledger_id uuid,
  disposition text,
  evidence_basis text
)
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_farm atlas.farms%rowtype;
  v_custody record;
  v_ledger uuid;
begin
  select * into v_farm
  from atlas.farms f
  where f.id=p_farm_id;

  if v_farm.id is null then
    return;
  end if;

  select * into v_custody
  from atlas.effective_institutional_custody_v1(
    'atlas','farms',v_farm.id::text,v_farm.organization_id,null
  );

  if v_custody.disposition in ('archived','unresolved') then
    physical_organization_id:=v_farm.organization_id;
    effective_organization_id:=null;
    effective_ledger_id:=null;
    disposition:=v_custody.disposition;
    evidence_basis:=v_custody.evidence_basis;
    return next;
    return;
  end if;

  effective_organization_id:=v_custody.effective_organization_id;
  v_ledger:=v_custody.effective_ledger_id;

  if effective_organization_id is null then
    effective_organization_id:=v_farm.organization_id;
  end if;

  if v_ledger is null and effective_organization_id is not null then
    v_ledger:=atlas.primary_ledger_for_organization_v1(effective_organization_id);
  end if;

  if v_ledger is not null and not exists(
    select 1
    from atlas.ledgers l
    where l.id=v_ledger and l.status='active'
  ) then
    v_ledger:=null;
  end if;

  if v_ledger is not null and effective_organization_id is not null
     and not exists(
       select 1
       from atlas.ledger_organization_participations p
       where p.ledger_id=v_ledger
         and p.organization_id=effective_organization_id
         and p.status='active'
         and p.ended_at is null
     ) then
    v_ledger:=null;
  end if;

  physical_organization_id:=v_farm.organization_id;
  effective_ledger_id:=v_ledger;
  disposition:=coalesce(v_custody.disposition,'direct');
  evidence_basis:=coalesce(v_custody.evidence_basis,'physical_farm_current_custody');
  return next;
end;
$function$;

create or replace function atlas.ensure_money_obligation_core_v1(
  p_ledger_id uuid,
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_amount numeric,
  p_currency text,
  p_due_at timestamptz,
  p_source_occurred_at timestamptz,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_amount numeric(14,2):=round(p_amount,2);
  v_currency text:=upper(nullif(btrim(p_currency),''));
  v_domain text:=lower(nullif(btrim(p_source_domain),''));
  v_kind text:=lower(nullif(btrim(p_source_kind),''));
  v_source_id text:=nullif(btrim(p_source_id),'');
  v_obligation_kind text:=lower(nullif(btrim(p_obligation_kind),''));
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_obligations%rowtype;
begin
  if p_ledger_id is null or p_organization_id is null or v_domain is null
     or v_kind is null or v_source_id is null or v_obligation_kind is null or v_key is null then
    raise exception 'Money obligation identity is incomplete.' using errcode='22023';
  end if;
  if v_amount is null or v_amount<=0 then
    raise exception 'Money obligation amount must be positive.' using errcode='22023';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Money obligation currency must be a three-letter code.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.ledger_organization_participations p
    join atlas.ledgers l on l.id=p.ledger_id
    join atlas.organizations o on o.id=p.organization_id
    where p.ledger_id=p_ledger_id
      and p.organization_id=p_organization_id
      and p.status='active' and p.ended_at is null
      and l.status='active' and o.status='active'
  ) then
    raise exception 'Money obligation requires active Organization participation in the governing Ledger.'
      using errcode='23514';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_ledger_id::text||':money-obligation:'||v_domain||':'||v_kind||':'||v_source_id||':'||v_obligation_kind,0
  ));

  select * into v_existing
  from atlas.money_obligations o
  where o.ledger_id=p_ledger_id
    and o.source_domain=v_domain
    and o.source_kind=v_kind
    and o.source_id=v_source_id
    and o.obligation_kind=v_obligation_kind;

  if v_existing.id is not null then
    if v_existing.organization_id is distinct from p_organization_id
       or v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency then
      raise exception 'Money obligation retry conflicts with existing source truth.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.money_obligations(
    ledger_id,organization_id,source_domain,source_kind,source_id,obligation_kind,
    amount,currency,due_at,source_occurred_at,idempotency_key,metadata
  ) values (
    p_ledger_id,p_organization_id,v_domain,v_kind,v_source_id,v_obligation_kind,
    v_amount,v_currency,p_due_at,p_source_occurred_at,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$function$;

create or replace function atlas.void_money_obligation_core_v1(
  p_obligation_id uuid,
  p_reason_kind text,
  p_evidence_domain text,
  p_evidence_kind text,
  p_evidence_id text,
  p_note text,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_obligation atlas.money_obligations%rowtype;
  v_existing atlas.money_obligation_void_events%rowtype;
  v_position record;
  v_key text:=nullif(btrim(p_idempotency_key),'');
begin
  if p_obligation_id is null or nullif(btrim(p_reason_kind),'') is null or v_key is null then
    raise exception 'Money obligation void identity is incomplete.' using errcode='22023';
  end if;

  select * into v_obligation from atlas.money_obligations where id=p_obligation_id for update;
  if v_obligation.id is null then
    raise exception 'Money obligation not found.' using errcode='P0002';
  end if;

  select * into v_position from atlas.money_obligation_position_v1 where obligation_id=v_obligation.id;
  if v_position.net_applied_amount>0 then
    raise exception 'A paid or partially paid obligation cannot be voided; preserve receipt/reversal history.'
      using errcode='23514';
  end if;

  select * into v_existing from atlas.money_obligation_void_events where obligation_id=v_obligation.id;
  if v_existing.id is not null then
    return v_existing.id;
  end if;

  insert into atlas.money_obligation_void_events(
    ledger_id,organization_id,obligation_id,reason_kind,
    evidence_domain,evidence_kind,evidence_id,note,idempotency_key,metadata
  ) values (
    v_obligation.ledger_id,v_obligation.organization_id,v_obligation.id,btrim(p_reason_kind),
    nullif(btrim(coalesce(p_evidence_domain,'')),''),
    nullif(btrim(coalesce(p_evidence_kind,'')),''),
    nullif(btrim(coalesce(p_evidence_id,'')),''),
    nullif(btrim(coalesce(p_note,'')),''),
    v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$function$;

create or replace function atlas.record_money_receipt_core_v1(
  p_ledger_id uuid,
  p_organization_id uuid,
  p_amount numeric,
  p_currency text,
  p_received_at timestamptz,
  p_evidence_domain text,
  p_evidence_kind text,
  p_evidence_id text,
  p_connected_source_id uuid,
  p_recorded_by_user_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_amount numeric(14,2):=round(p_amount,2);
  v_currency text:=upper(nullif(btrim(p_currency),''));
  v_domain text:=lower(nullif(btrim(p_evidence_domain),''));
  v_kind text:=lower(nullif(btrim(p_evidence_kind),''));
  v_evidence_id text:=nullif(btrim(p_evidence_id),'');
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_receipts%rowtype;
begin
  if p_ledger_id is null or p_organization_id is null or p_received_at is null
     or v_domain is null or v_kind is null or v_evidence_id is null or v_key is null then
    raise exception 'Money receipt identity is incomplete.' using errcode='22023';
  end if;
  if v_amount is null or v_amount<=0 then
    raise exception 'Money receipt amount must be positive.' using errcode='22023';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Money receipt currency must be a three-letter code.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=p_ledger_id and p.organization_id=p_organization_id
      and p.status='active' and p.ended_at is null
  ) then
    raise exception 'Money receipt crosses Ledger/Organization custody.' using errcode='23514';
  end if;

  if p_connected_source_id is not null and not exists(
    select 1 from atlas.connected_sources s
    where s.id=p_connected_source_id
      and s.authorization_state='connected'
      and s.revoked_at is null
  ) then
    raise exception 'Connected source is not currently active.' using errcode='23514';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_ledger_id::text||':money-receipt:'||v_domain||':'||v_kind||':'||v_evidence_id,0
  ));

  select * into v_existing
  from atlas.money_receipts r
  where r.ledger_id=p_ledger_id
    and r.evidence_domain=v_domain
    and r.evidence_kind=v_kind
    and r.evidence_id=v_evidence_id;

  if v_existing.id is not null then
    if v_existing.organization_id is distinct from p_organization_id
       or v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency
       or v_existing.received_at is distinct from p_received_at then
      raise exception 'Money receipt retry conflicts with admitted evidence.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.money_receipts(
    ledger_id,organization_id,amount,currency,received_at,
    evidence_domain,evidence_kind,evidence_id,connected_source_id,
    recorded_by_user_id,idempotency_key,metadata
  ) values (
    p_ledger_id,p_organization_id,v_amount,v_currency,p_received_at,
    v_domain,v_kind,v_evidence_id,p_connected_source_id,
    p_recorded_by_user_id,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$function$;

create or replace function atlas.allocate_money_receipt_core_v1(
  p_receipt_id uuid,
  p_obligation_id uuid,
  p_amount numeric,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_receipt atlas.money_receipts%rowtype;
  v_obligation atlas.money_obligations%rowtype;
  v_amount numeric(14,2):=round(p_amount,2);
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_receipt_allocations%rowtype;
  v_receipt_position record;
  v_obligation_position record;
begin
  if p_receipt_id is null or p_obligation_id is null or v_key is null
     or v_amount is null or v_amount<=0 then
    raise exception 'Money allocation identity or amount is invalid.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('money-receipt:'||p_receipt_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('money-obligation:'||p_obligation_id::text,0));

  select * into v_receipt from atlas.money_receipts where id=p_receipt_id;
  select * into v_obligation from atlas.money_obligations where id=p_obligation_id;

  if v_receipt.id is null or v_obligation.id is null then
    raise exception 'Money receipt or obligation not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.money_receipt_allocations a
  where a.ledger_id=v_receipt.ledger_id and a.idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from v_receipt.id
       or v_existing.obligation_id is distinct from v_obligation.id
       or v_existing.amount is distinct from v_amount then
      raise exception 'Money allocation retry conflicts with existing allocation.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if v_receipt.ledger_id is distinct from v_obligation.ledger_id
     or v_receipt.organization_id is distinct from v_obligation.organization_id
     or v_receipt.currency is distinct from v_obligation.currency then
    raise exception 'Money allocation crosses Ledger, Organization, or currency custody.' using errcode='23514';
  end if;

  select * into v_receipt_position
  from atlas.money_receipt_position_v1 where receipt_id=v_receipt.id;
  select * into v_obligation_position
  from atlas.money_obligation_position_v1 where obligation_id=v_obligation.id;

  if v_obligation_position.effective_state='voided' then
    raise exception 'A voided obligation cannot receive money.' using errcode='23514';
  end if;
  if v_amount>v_receipt_position.available_amount then
    raise exception 'Money allocation exceeds available receipt amount.' using errcode='23514';
  end if;
  if v_amount>v_obligation_position.open_amount then
    raise exception 'Money allocation exceeds obligation open amount.' using errcode='23514';
  end if;

  insert into atlas.money_receipt_allocations(
    ledger_id,organization_id,receipt_id,obligation_id,amount,idempotency_key,metadata
  ) values (
    v_receipt.ledger_id,v_receipt.organization_id,v_receipt.id,v_obligation.id,
    v_amount,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$function$;

create or replace function atlas.reverse_money_receipt_core_v1(
  p_receipt_id uuid,
  p_allocation_id uuid,
  p_amount numeric,
  p_reversal_kind text,
  p_evidence_domain text,
  p_evidence_kind text,
  p_evidence_id text,
  p_occurred_at timestamptz,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_receipt atlas.money_receipts%rowtype;
  v_allocation atlas.money_receipt_allocations%rowtype;
  v_amount numeric(14,2):=round(p_amount,2);
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_receipt_reversals%rowtype;
  v_reversed numeric(14,2);
begin
  if p_receipt_id is null or v_amount is null or v_amount<=0
     or nullif(btrim(p_reversal_kind),'') is null
     or nullif(btrim(p_evidence_domain),'') is null
     or nullif(btrim(p_evidence_kind),'') is null
     or nullif(btrim(p_evidence_id),'') is null
     or p_occurred_at is null or v_key is null then
    raise exception 'Money reversal identity or amount is invalid.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('money-receipt:'||p_receipt_id::text,0));

  select * into v_receipt from atlas.money_receipts where id=p_receipt_id;
  if v_receipt.id is null then
    raise exception 'Money receipt not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.money_receipt_reversals r
  where r.ledger_id=v_receipt.ledger_id and r.idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from v_receipt.id
       or v_existing.allocation_id is distinct from p_allocation_id
       or v_existing.amount is distinct from v_amount then
      raise exception 'Money reversal retry conflicts with existing reversal.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select coalesce(sum(r.amount),0)::numeric(14,2)
  into v_reversed
  from atlas.money_receipt_reversals r
  where r.receipt_id=v_receipt.id;

  if v_amount>v_receipt.amount-v_reversed then
    raise exception 'Money reversal exceeds remaining received amount.' using errcode='23514';
  end if;

  if p_allocation_id is not null then
    select * into v_allocation
    from atlas.money_receipt_allocations a
    where a.id=p_allocation_id and a.receipt_id=v_receipt.id;
    if v_allocation.id is null then
      raise exception 'Money reversal allocation does not belong to this receipt.' using errcode='23514';
    end if;

    select coalesce(sum(r.amount),0)::numeric(14,2)
    into v_reversed
    from atlas.money_receipt_reversals r
    where r.allocation_id=v_allocation.id;

    if v_amount>v_allocation.amount-v_reversed then
      raise exception 'Money reversal exceeds remaining allocation amount.' using errcode='23514';
    end if;
  end if;

  insert into atlas.money_receipt_reversals(
    ledger_id,organization_id,receipt_id,allocation_id,amount,reversal_kind,
    evidence_domain,evidence_kind,evidence_id,occurred_at,idempotency_key,metadata
  ) values (
    v_receipt.ledger_id,v_receipt.organization_id,v_receipt.id,p_allocation_id,v_amount,
    lower(btrim(p_reversal_kind)),lower(btrim(p_evidence_domain)),lower(btrim(p_evidence_kind)),
    btrim(p_evidence_id),p_occurred_at,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_existing.id;

  return v_existing.id;
end;
$function$;

-- Flower Sale is the authoritative commercial event. Money observes its committed
-- total after birth; it does not replace the Flower Sale writer.
create or replace function atlas.ensure_money_obligation_for_flower_sale_v1(p_sale_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_sale atlas.flower_sale_orders%rowtype;
  v_custody record;
begin
  select * into v_sale from atlas.flower_sale_orders where id=p_sale_order_id;
  if v_sale.id is null then
    return null;
  end if;
  if round(v_sale.total_amount,2)<=0 then
    return null;
  end if;

  select * into v_custody from atlas.money_source_farm_custody_v1(v_sale.farm_id);
  if v_custody.effective_organization_id is null or v_custody.effective_ledger_id is null then
    return null;
  end if;

  return atlas.ensure_money_obligation_core_v1(
    v_custody.effective_ledger_id,
    v_custody.effective_organization_id,
    'flower',
    'flower_sale_order',
    v_sale.id::text,
    'sale_total',
    v_sale.total_amount,
    v_sale.currency,
    case
      when v_sale.fulfillment_due_date is null then null
      when v_sale.fulfillment_due_time is null then
        (v_sale.fulfillment_due_date::timestamp at time zone 'America/Chicago')
      else
        ((v_sale.fulfillment_due_date+v_sale.fulfillment_due_time) at time zone 'America/Chicago')
    end,
    v_sale.created_at,
    'flower_sale_order:'||v_sale.id::text||':sale_total',
    jsonb_build_object(
      'source','flower_sale_orders',
      'farmId',v_sale.farm_id,
      'physicalOrganizationId',v_custody.physical_organization_id,
      'custodyDisposition',v_custody.disposition,
      'custodyBasis',v_custody.evidence_basis,
      'saleIdempotencyKey',v_sale.idempotency_key
    )
  );
end;
$function$;

create or replace function atlas.ensure_money_obligation_for_registration_v1(p_registration_id uuid)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_registration atlas.community_registrations%rowtype;
  v_offering atlas.community_registration_offerings%rowtype;
  v_farm_id uuid;
  v_amount numeric(14,2);
  v_currency text;
  v_commercial_order_id uuid;
  v_custody record;
begin
  select * into v_registration
  from atlas.community_registrations where id=p_registration_id;
  if v_registration.id is null then
    return null;
  end if;

  select * into v_offering
  from atlas.community_registration_offerings where id=v_registration.offering_id;
  if v_offering.id is null then
    return null;
  end if;

  v_farm_id:=v_offering.farm_id;

  select x.commercial_order_id,co.total_amount,co.currency
  into v_commercial_order_id,v_amount,v_currency
  from atlas.community_registration_commercial_order_extensions x
  join atlas.commercial_orders co on co.id=x.commercial_order_id
  where x.registration_id=v_registration.id;

  if v_commercial_order_id is null then
    v_amount:=v_offering.fee_amount;
    v_currency:=v_offering.fee_currency;
  end if;

  if round(coalesce(v_amount,0),2)<=0 then
    return null;
  end if;

  select * into v_custody from atlas.money_source_farm_custody_v1(v_farm_id);
  if v_custody.effective_organization_id is null or v_custody.effective_ledger_id is null then
    return null;
  end if;

  return atlas.ensure_money_obligation_core_v1(
    v_custody.effective_ledger_id,
    v_custody.effective_organization_id,
    'community_registration',
    'registration',
    v_registration.id::text,
    'participation_fee',
    v_amount,
    v_currency,
    null,
    coalesce(v_registration.submitted_at,v_registration.created_at),
    'community_registration:'||v_registration.id::text||':participation_fee',
    jsonb_strip_nulls(jsonb_build_object(
      'source','community_registrations',
      'farmId',v_farm_id,
      'offeringId',v_offering.id,
      'commercialOrderId',v_commercial_order_id,
      'amountBasis',case when v_commercial_order_id is null then 'offering_fee_at_registration_birth' else 'commercial_order_snapshot' end,
      'physicalOrganizationId',v_custody.physical_organization_id,
      'custodyDisposition',v_custody.disposition,
      'custodyBasis',v_custody.evidence_basis
    ))
  );
end;
$function$;

create or replace function atlas.reconcile_money_from_registration_payment_v1(p_registration_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_payment atlas.community_registration_payments%rowtype;
  v_obligation_id uuid;
  v_obligation atlas.money_obligations%rowtype;
  v_receipt_id uuid;
  v_allocation_id uuid;
  v_existing_allocation atlas.money_receipt_allocations%rowtype;
  v_commercial_payment_id uuid;
  v_refund_amount numeric(14,2):=0;
  v_position record;
  v_allocate_amount numeric(14,2);
begin
  select * into v_payment
  from atlas.community_registration_payments p
  where p.id=p_registration_payment_id;
  if v_payment.id is null then
    return jsonb_build_object('state','missing');
  end if;

  v_obligation_id:=atlas.ensure_money_obligation_for_registration_v1(v_payment.registration_id);
  if v_obligation_id is null then
    return jsonb_build_object('state','no_canonical_obligation');
  end if;

  select * into v_obligation from atlas.money_obligations where id=v_obligation_id;

  if v_payment.status not in ('paid','refunded','partially_refunded')
     or v_payment.paid_at is null or round(v_payment.amount,2)<=0 then
    return jsonb_build_object('state','no_received_money','obligationId',v_obligation_id);
  end if;

  select x.commercial_payment_id into v_commercial_payment_id
  from atlas.community_registration_commercial_payment_extensions x
  where x.registration_payment_id=v_payment.id;

  v_receipt_id:=atlas.record_money_receipt_core_v1(
    v_obligation.ledger_id,
    v_obligation.organization_id,
    v_payment.amount,
    v_payment.currency,
    v_payment.paid_at,
    'community_registration',
    'registration_payment',
    v_payment.id::text,
    null,
    null,
    'community_registration_payment:'||v_payment.id::text||':received',
    jsonb_strip_nulls(jsonb_build_object(
      'registrationId',v_payment.registration_id,
      'commercialPaymentId',v_commercial_payment_id,
      'providerKey',nullif(lower(btrim(coalesce(v_payment.payment_processor,''))),''),
      'providerPaymentKey',nullif(btrim(coalesce(v_payment.external_payment_id,'')),''),
      'sourceStatus',v_payment.status,
      'historicalEvidenceAlreadyAdmitted',true
    ))
  );

  select * into v_existing_allocation
  from atlas.money_receipt_allocations a
  where a.ledger_id=v_obligation.ledger_id
    and a.idempotency_key='community_registration_payment:'||v_payment.id::text||':allocation';

  if v_existing_allocation.id is null then
    select * into v_position
    from atlas.money_obligation_position_v1 p
    where p.obligation_id=v_obligation.id;

    v_allocate_amount:=least(round(v_payment.amount,2),v_position.open_amount);
    if v_allocate_amount>0 then
      v_allocation_id:=atlas.allocate_money_receipt_core_v1(
        v_receipt_id,v_obligation.id,v_allocate_amount,
        'community_registration_payment:'||v_payment.id::text||':allocation',
        jsonb_build_object('source','community_registration_payments')
      );
    end if;
  else
    v_allocation_id:=v_existing_allocation.id;
  end if;

  if v_allocation_id is not null then
    if v_commercial_payment_id is not null then
      select coalesce(abs(sum(e.amount_delta)) filter (
        where e.amount_delta<0 and e.event_kind in ('refund','chargeback','adjustment')
      ),0)::numeric(14,2)
      into v_refund_amount
      from atlas.commercial_payment_events e
      where e.commercial_payment_id=v_commercial_payment_id;
    end if;

    if coalesce(v_refund_amount,0)=0
       and v_payment.status='refunded'
       and v_payment.refunded_at is not null then
      v_refund_amount:=least(v_existing_allocation.amount,round(v_payment.amount,2));
      if v_existing_allocation.id is null then
        select * into v_existing_allocation
        from atlas.money_receipt_allocations where id=v_allocation_id;
        v_refund_amount:=least(v_existing_allocation.amount,round(v_payment.amount,2));
      end if;
    end if;

    if coalesce(v_refund_amount,0)>0 then
      v_refund_amount:=least(v_refund_amount,(select amount from atlas.money_receipt_allocations where id=v_allocation_id));
      perform atlas.reverse_money_receipt_core_v1(
        v_receipt_id,v_allocation_id,v_refund_amount,'refund',
        'community_registration','registration_payment_refund',v_payment.id::text,
        coalesce(v_payment.refunded_at,now()),
        'community_registration_payment:'||v_payment.id::text||':refund',
        jsonb_build_object(
          'commercialPaymentId',v_commercial_payment_id,
          'refundAmountBasis',case when v_commercial_payment_id is null then 'legacy_full_refund_status' else 'commercial_payment_negative_events' end
        )
      );
    end if;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'state','reconciled',
    'obligationId',v_obligation.id,
    'receiptId',v_receipt_id,
    'allocationId',v_allocation_id,
    'refundAmount',v_refund_amount
  ));
end;
$function$;

create or replace function atlas.reconcile_flower_sale_money_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.ensure_money_obligation_for_flower_sale_v1(new.id);
  return new;
end;
$function$;

create trigger flower_sale_money_obligation_v1
after insert on atlas.flower_sale_orders
for each row execute function atlas.reconcile_flower_sale_money_trigger_v1();

create or replace function atlas.reconcile_registration_money_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.ensure_money_obligation_for_registration_v1(new.id);
  return new;
end;
$function$;

create trigger community_registration_money_obligation_v1
after insert on atlas.community_registrations
for each row execute function atlas.reconcile_registration_money_trigger_v1();

create or replace function atlas.reconcile_registration_payment_money_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  perform atlas.reconcile_money_from_registration_payment_v1(new.id);
  return new;
end;
$function$;

create trigger community_registration_payment_money_v1
after insert or update of status,amount,currency,paid_at,refunded_at,payment_processor,external_payment_id
on atlas.community_registration_payments
for each row execute function atlas.reconcile_registration_payment_money_trigger_v1();

create or replace function atlas.reconcile_flower_sale_cancellation_money_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_obligation atlas.money_obligations%rowtype;
  v_position record;
begin
  select o.* into v_obligation
  from atlas.money_obligations o
  where o.source_domain='flower'
    and o.source_kind='flower_sale_order'
    and o.source_id=new.sale_order_id::text
    and o.obligation_kind='sale_total'
  limit 1;

  if v_obligation.id is null then
    return new;
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1 p
  where p.obligation_id=v_obligation.id;

  if v_position.net_applied_amount=0 and v_position.effective_state<>'voided' then
    perform atlas.void_money_obligation_core_v1(
      v_obligation.id,new.reason_kind,'flower','flower_sale_cancellation',
      new.id::text,new.note,
      'flower_sale_cancellation:'||new.id::text,
      jsonb_build_object('saleOrderId',new.sale_order_id,'farmId',new.farm_id)
    );
  end if;

  return new;
end;
$function$;

create trigger flower_sale_cancellation_money_v1
after insert on atlas.flower_sale_order_cancellation_events
for each row execute function atlas.reconcile_flower_sale_cancellation_money_trigger_v1();

create or replace function atlas.reconcile_registration_cancellation_money_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_obligation atlas.money_obligations%rowtype;
  v_position record;
begin
  if new.status not in ('cancelled','refunded') then
    return new;
  end if;

  select o.* into v_obligation
  from atlas.money_obligations o
  where o.source_domain='community_registration'
    and o.source_kind='registration'
    and o.source_id=new.id::text
    and o.obligation_kind='participation_fee'
  limit 1;

  if v_obligation.id is null then
    return new;
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1 p
  where p.obligation_id=v_obligation.id;

  if v_position.net_applied_amount=0 and v_position.effective_state<>'voided' then
    perform atlas.void_money_obligation_core_v1(
      v_obligation.id,new.status,'community_registration','registration_status',
      new.id::text,null,
      'community_registration:'||new.id::text||':void:'||new.status,
      jsonb_build_object('cancelledAt',new.cancelled_at)
    );
  end if;

  return new;
end;
$function$;

create trigger community_registration_cancellation_money_v1
after update of status,cancelled_at on atlas.community_registrations
for each row
when (new.status in ('cancelled','refunded'))
execute function atlas.reconcile_registration_cancellation_money_trigger_v1();

-- Backfill current source truth only after the governed adapters exist.
do $backfill_money_v1$
declare
  v_id uuid;
begin
  for v_id in select id from atlas.flower_sale_orders order by created_at,id loop
    perform atlas.ensure_money_obligation_for_flower_sale_v1(v_id);
  end loop;

  for v_id in select id from atlas.community_registrations order by created_at,id loop
    perform atlas.ensure_money_obligation_for_registration_v1(v_id);
  end loop;

  for v_id in select id from atlas.community_registration_payments order by created_at,id loop
    perform atlas.reconcile_money_from_registration_payment_v1(v_id);
  end loop;
end;
$backfill_money_v1$;

create or replace function atlas.money_positions_self_api_v1(p_ledger_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_ledger_id is null then
    raise exception 'Ledger required.' using errcode='22023';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null
     or not atlas.principal_has_ledger_authority_v1(v_principal_id,p_ledger_id) then
    raise exception 'Ledger authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'obligationId',p.obligation_id,
    'ledgerId',p.ledger_id,
    'organizationId',p.organization_id,
    'sourceDomain',p.source_domain,
    'sourceKind',p.source_kind,
    'sourceId',p.source_id,
    'obligationKind',p.obligation_kind,
    'originalAmount',p.original_amount,
    'effectiveObligatedAmount',p.effective_obligated_amount,
    'netAppliedAmount',p.net_applied_amount,
    'openAmount',p.open_amount,
    'state',p.effective_state,
    'currency',p.currency,
    'dueAt',p.due_at,
    'sourceOccurredAt',p.source_occurred_at,
    'createdAt',p.created_at
  )) order by p.source_occurred_at nulls last,p.created_at,p.obligation_id),'[]'::jsonb)
  into v_items
  from atlas.money_obligation_position_v1 p
  where p.ledger_id=p_ledger_id;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','money_positions_v1',
    'ledgerId',p_ledger_id,
    'items',v_items
  );
end;
$function$;

create or replace function public.money_positions_self_api_v1(p_ledger_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.money_positions_self_api_v1(p_ledger_id);
$function$;

revoke all on function atlas.prevent_money_history_mutation_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.money_source_farm_custody_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.ensure_money_obligation_core_v1(uuid,uuid,text,text,text,text,numeric,text,timestamptz,timestamptz,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.void_money_obligation_core_v1(uuid,text,text,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.record_money_receipt_core_v1(uuid,uuid,numeric,text,timestamptz,text,text,text,uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.allocate_money_receipt_core_v1(uuid,uuid,numeric,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.reverse_money_receipt_core_v1(uuid,uuid,numeric,text,text,text,text,timestamptz,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function atlas.ensure_money_obligation_for_flower_sale_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.ensure_money_obligation_for_registration_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_money_from_registration_payment_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_flower_sale_money_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_registration_money_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_registration_payment_money_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_flower_sale_cancellation_money_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.reconcile_registration_cancellation_money_trigger_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.money_positions_self_api_v1(uuid) from public,anon,authenticated,service_role;

revoke all on function public.money_positions_self_api_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.money_positions_self_api_v1(uuid) to authenticated;

comment on table atlas.money_obligations is
  'Canonical Ledger-custodied receivable obligation created by a source transaction. Source price remains domain-owned.';
comment on table atlas.money_receipts is
  'Canonical statement that money was received according to admitted evidence. Receipt is not provider authorization, fulfillment, or bank settlement.';
comment on table atlas.money_receipt_allocations is
  'Application of received Money to a Money obligation; distinct from inventory allocation.';
comment on view atlas.money_obligation_position_v1 is
  'Derived current Money position from immutable obligation, allocation, void, and reversal evidence.';
comment on function atlas.money_source_farm_custody_v1(uuid) is
  'Resolves farm-scoped source reality to canonical Organization/Ledger custody. Archived/unresolved test or portfolio scope does not establish canonical Money.';
comment on function atlas.ensure_money_obligation_for_flower_sale_v1(uuid) is
  'Projects a positive governed Flower Sale into Money obligation truth without replacing the Flower Sale writer. Archived/noncanonical farm scope produces no Money obligation.';
comment on function atlas.ensure_money_obligation_for_registration_v1(uuid) is
  'Projects a positive Community Registration into Money obligation truth. Existing immutable commercial-order snapshot is preferred when present; otherwise the offering fee is snapshotted at registration birth.';
comment on function atlas.reconcile_money_from_registration_payment_v1(uuid) is
  'Admits already-observed Community Registration payment evidence into canonical receipt/allocation/reversal truth without requiring retroactive provider connection custody.';

commit;

BEGIN;

-- Atlas Money Collection Kernel v1 — executable foundation proof only.
-- NOT a canonical migration. The release filename must come from
-- `supabase migration new` in the governed noel-core-db environment.
-- This tranche proves global adapter coverage, immutable obligations,
-- effective position, and the trusted internal obligation constructor.

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
  foreign key (obligation_id, organization_id)
    references atlas.money_obligations(id, organization_id) on delete restrict,
  check (
    (source_event_kind is null and source_event_id is null)
    or
    (nullif(btrim(source_event_kind),'') is not null and nullif(btrim(source_event_id),'') is not null)
  )
);

create index money_obligations_source_idx
  on atlas.money_obligations (organization_id, source_domain, source_kind, source_id);

alter table atlas.money_source_adapter_coverage enable row level security;
alter table atlas.money_obligations enable row level security;
alter table atlas.money_obligation_void_events enable row level security;

revoke all on atlas.money_source_adapter_coverage from public, anon, authenticated, service_role;
revoke all on atlas.money_obligations from public, anon, authenticated, service_role;
revoke all on atlas.money_obligation_void_events from public, anon, authenticated, service_role;

create view atlas.money_obligation_position_v1
with (security_invoker=true)
as
with voided as (
  select obligation_id, min(created_at) as voided_at
  from atlas.money_obligation_void_events
  group by obligation_id
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
  case when v.obligation_id is null then o.amount else 0::numeric end::numeric(14,2)
    as effective_obligated_amount,
  0::numeric(14,2) as gross_paid_amount,
  0::numeric(14,2) as reversed_paid_amount,
  0::numeric(14,2) as net_paid_amount,
  case when v.obligation_id is null then o.amount else 0::numeric end::numeric(14,2)
    as open_amount,
  case when v.obligation_id is null then 'open' else 'voided' end as effective_state,
  o.currency,
  o.due_at,
  v.voided_at,
  o.created_at
from atlas.money_obligations o
left join voided v on v.obligation_id=o.id;

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
  if p_organization_id is null
     or v_key is null
     or v_domain is null
     or v_kind is null
     or v_obligation_kind is null
     or v_contract is null
     or v_source_id is null
     or p_amount is null
     or p_amount<=0
     or v_currency is null
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid money obligation input.' using errcode='22023';
  end if;

  if not exists (
    select 1
    from atlas.money_source_adapter_coverage c
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
    p_organization_id::text||':'||v_domain||':'||v_kind||':'||v_source_id||':'||v_obligation_kind,
    0
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
  where o.organization_id=p_organization_id
    and o.idempotency_key=v_key;

  if v_existing.id is not null then
    raise exception 'Money obligation idempotency key is already bound to another source.' using errcode='23505';
  end if;

  insert into atlas.money_obligations(
    organization_id,
    source_domain,
    source_kind,
    source_id,
    obligation_kind,
    adapter_contract,
    amount,
    currency,
    due_at,
    idempotency_key,
    created_by_user_id,
    metadata
  ) values (
    p_organization_id,
    v_domain,
    v_kind,
    v_source_id,
    v_obligation_kind,
    v_contract,
    round(p_amount,2),
    v_currency,
    p_due_at,
    v_key,
    p_created_by_user_id,
    coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

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
  v_first_activation timestamptz;
  v_contract text;
  v_position record;
  v_domain text:=lower(nullif(btrim(coalesce(p_source_domain,'')),''));
  v_kind text:=lower(nullif(btrim(coalesce(p_source_kind,'')),''));
  v_obligation_kind text:=lower(nullif(btrim(coalesce(p_obligation_kind,'')),''));
  v_source_id text:=nullif(btrim(coalesce(p_source_id,'')),'');
  v_currency text:=upper(nullif(btrim(coalesce(p_source_currency,'')),''));
begin
  if p_organization_id is null
     or v_domain is null
     or v_kind is null
     or v_obligation_kind is null
     or v_source_id is null
     or p_source_created_at is null
     or p_source_amount is null
     or v_currency is null
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Invalid money source position input.' using errcode='22023';
  end if;

  if p_source_amount<0 then
    raise exception 'Receivable source amount cannot be negative.' using errcode='22023';
  end if;

  if round(p_source_amount,2)=0 then
    return jsonb_build_object(
      'coverageState','payment_not_required',
      'sourceDomain',v_domain,
      'sourceKind',v_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',0,
      'currency',v_currency
    );
  end if;

  select min(c.activated_at) into v_first_activation
  from atlas.money_source_adapter_coverage c
  where c.source_domain=v_domain
    and c.source_kind=v_kind
    and c.obligation_kind=v_obligation_kind;

  if v_first_activation is null or p_source_created_at<v_first_activation then
    return jsonb_build_object(
      'coverageState','pre_kernel_unknown',
      'sourceDomain',v_domain,
      'sourceKind',v_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_currency
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
      'sourceDomain',v_domain,
      'sourceKind',v_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_currency,
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
      'sourceDomain',v_domain,
      'sourceKind',v_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null,
      'currency',v_currency
    );
  end if;

  if v_position.original_obligated_amount is distinct from round(p_source_amount,2)
     or v_position.currency is distinct from v_currency
     or v_position.adapter_contract is distinct from v_contract then
    raise exception 'Money obligation no longer matches canonical source snapshot.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'coverageState','covered',
    'sourceDomain',v_domain,
    'sourceKind',v_kind,
    'sourceId',v_source_id,
    'obligationId',v_position.obligation_id,
    'effectiveState',v_position.effective_state,
    'openAmount',v_position.open_amount,
    'originalObligatedAmount',v_position.original_obligated_amount,
    'netPaidAmount',v_position.net_paid_amount,
    'currency',v_position.currency
  );
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
  if p_obligation_id is null
     or v_reason is null
     or v_key is null
     or ((v_event_kind is null) is distinct from (v_event_id is null)) then
    raise exception 'Invalid obligation void input.' using errcode='22023';
  end if;

  select * into v_obligation
  from atlas.money_obligations
  where id=p_obligation_id
  for update;

  if v_obligation.id is null then
    raise exception 'Obligation not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.money_obligation_void_events
  where obligation_id=v_obligation.id;

  if v_existing.id is not null then
    if v_existing.reason_kind is distinct from v_reason
       or v_existing.source_event_kind is distinct from v_event_kind
       or v_existing.source_event_id is distinct from v_event_id then
      raise exception 'Obligation already has conflicting void evidence.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists (
    select 1
    from atlas.money_obligation_void_events e
    where e.organization_id=v_obligation.organization_id
      and e.idempotency_key=v_key
  ) then
    raise exception 'Obligation void idempotency key is already bound.' using errcode='23505';
  end if;

  insert into atlas.money_obligation_void_events(
    organization_id,
    obligation_id,
    reason_kind,
    source_event_kind,
    source_event_id,
    note,
    idempotency_key,
    recorded_by_user_id,
    metadata
  ) values (
    v_obligation.organization_id,
    v_obligation.id,
    v_reason,
    v_event_kind,
    v_event_id,
    nullif(btrim(coalesce(p_note,'')),''),
    v_key,
    p_recorded_by_user_id,
    coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

revoke all on function atlas.money_create_obligation_core_v1(
  uuid,text,text,text,text,text,numeric,text,timestamptz,text,uuid,jsonb
) from public, anon, authenticated, service_role;

revoke all on function atlas.money_source_position_core_v1(
  uuid,text,text,text,text,timestamptz,numeric,text
) from public, anon, authenticated, service_role;

revoke all on function atlas.money_void_obligation_core_v1(
  uuid,text,text,text,text,uuid,text,jsonb
) from public, anon, authenticated, service_role;

ROLLBACK;

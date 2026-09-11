-- Atlas Money Collection Kernel v1 — coverage + obligation executable tranche.
--
-- This is reviewed migration-source SQL, not a canonical migration. It is
-- intentionally split from atlas-money-collection-kernel-v1.sql so the draft
-- can finish executable contracts without fabricating a Supabase migration
-- identity. The generated migration must assemble the reviewed tranches in one
-- transaction after `supabase migration new` creates the governed filename.
--
-- No provider-specific vocabulary belongs here.

create table atlas.money_source_adapter_coverage (
  id uuid primary key default gen_random_uuid(),
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  obligation_kind text not null check (btrim(obligation_kind) <> ''),
  adapter_contract text not null check (btrim(adapter_contract) <> ''),
  coverage_started_at timestamptz not null,
  coverage_ended_at timestamptz,
  status text not null default 'active' check (status in ('active','retired')),
  release_provenance text not null check (btrim(release_provenance) <> ''),
  source_lower_bound text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (coverage_ended_at is null or coverage_ended_at > coverage_started_at),
  check (
    (status='active' and coverage_ended_at is null)
    or
    (status='retired' and coverage_ended_at is not null)
  ),
  unique (source_domain, source_kind, obligation_kind, adapter_contract)
);

create unique index money_source_adapter_one_active_contract_idx
  on atlas.money_source_adapter_coverage(source_domain,source_kind,obligation_kind)
  where status='active';

alter table atlas.money_source_adapter_coverage enable row level security;
revoke all on atlas.money_source_adapter_coverage from anon, authenticated, service_role;

-- The base schema proof already gives money_obligations the logical source key.
-- The generated migration must additionally carry these composite identities so
-- downstream custody can be enforced structurally as well as in commands.
alter table atlas.money_obligations
  add constraint money_obligations_id_org_unique unique (id, organization_id);

create or replace function atlas.ensure_money_obligation_core_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_amount numeric,
  p_currency text,
  p_due_at timestamptz,
  p_idempotency_key text,
  p_created_by_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_domain text := lower(nullif(btrim(p_source_domain),''));
  v_source_kind text := lower(nullif(btrim(p_source_kind),''));
  v_source_id text := nullif(btrim(p_source_id),'');
  v_obligation_kind text := lower(nullif(btrim(p_obligation_kind),''));
  v_currency text := upper(nullif(btrim(p_currency),''));
  v_key text := nullif(btrim(p_idempotency_key),'');
  v_amount numeric(14,2) := round(p_amount,2);
  v_existing atlas.money_obligations%rowtype;
begin
  if p_organization_id is null
     or v_source_domain is null
     or v_source_kind is null
     or v_source_id is null
     or v_obligation_kind is null
     or v_key is null then
    raise exception 'Money obligation identity is incomplete.' using errcode='22023';
  end if;
  if v_amount is null or v_amount<=0 then
    raise exception 'Money obligation amount must be positive.' using errcode='22023';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Money obligation currency must be a three-letter code.' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id) then
    raise exception 'Money obligation organization does not exist.' using errcode='23503';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_organization_id::text||':'||v_source_domain||':'||v_source_kind||':'||v_source_id||':'||v_obligation_kind,
      0
    )
  );

  select * into v_existing
  from atlas.money_obligations o
  where o.organization_id=p_organization_id
    and o.source_domain=v_source_domain
    and o.source_kind=v_source_kind
    and o.source_id=v_source_id
    and o.obligation_kind=v_obligation_kind;

  if v_existing.id is not null then
    if v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency
       or v_existing.idempotency_key is distinct from v_key then
      raise exception 'Money obligation retry conflicts with existing source truth.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists(
    select 1 from atlas.money_obligations o
    where o.organization_id=p_organization_id
      and o.idempotency_key=v_key
  ) then
    raise exception 'Money obligation idempotency key is already bound to another source.' using errcode='23505';
  end if;

  insert into atlas.money_obligations(
    organization_id,source_domain,source_kind,source_id,obligation_kind,
    amount,currency,due_at,idempotency_key,created_by_user_id,metadata
  ) values (
    p_organization_id,v_source_domain,v_source_kind,v_source_id,v_obligation_kind,
    v_amount,v_currency,p_due_at,v_key,p_created_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.money_source_coverage_state_core_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_obligation_kind text,
  p_source_created_at timestamptz,
  p_source_amount numeric
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source_domain text := lower(nullif(btrim(p_source_domain),''));
  v_source_kind text := lower(nullif(btrim(p_source_kind),''));
  v_source_id text := nullif(btrim(p_source_id),'');
  v_obligation_kind text := lower(nullif(btrim(p_obligation_kind),''));
  v_obligation atlas.money_obligations%rowtype;
  v_position record;
  v_covered boolean;
begin
  if p_organization_id is null
     or v_source_domain is null
     or v_source_kind is null
     or v_source_id is null
     or v_obligation_kind is null
     or p_source_created_at is null
     or p_source_amount is null
     or p_source_amount<0 then
    raise exception 'Money coverage source facts are incomplete.' using errcode='22023';
  end if;

  if p_source_amount=0 then
    return jsonb_build_object(
      'coverageState','payment_not_required',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',0
    );
  end if;

  select exists(
    select 1
    from atlas.money_source_adapter_coverage c
    where c.source_domain=v_source_domain
      and c.source_kind=v_source_kind
      and c.obligation_kind=v_obligation_kind
      and c.coverage_started_at<=p_source_created_at
      and (c.coverage_ended_at is null or p_source_created_at<c.coverage_ended_at)
  ) into v_covered;

  select * into v_obligation
  from atlas.money_obligations o
  where o.organization_id=p_organization_id
    and o.source_domain=v_source_domain
    and o.source_kind=v_source_kind
    and o.source_id=v_source_id
    and o.obligation_kind=v_obligation_kind;

  if not v_covered then
    if v_obligation.id is not null then
      raise exception 'Pre-coverage source unexpectedly has canonical money obligation.' using errcode='23514';
    end if;
    return jsonb_build_object(
      'coverageState','pre_kernel_unknown',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null
    );
  end if;

  if v_obligation.id is null then
    return jsonb_build_object(
      'coverageState','invariant_gap',
      'sourceDomain',v_source_domain,
      'sourceKind',v_source_kind,
      'sourceId',v_source_id,
      'obligationId',null,
      'effectiveState',null,
      'openAmount',null
    );
  end if;

  select * into v_position
  from atlas.money_obligation_position_v1 p
  where p.obligation_id=v_obligation.id;

  return jsonb_build_object(
    'coverageState','covered',
    'sourceDomain',v_source_domain,
    'sourceKind',v_source_kind,
    'sourceId',v_source_id,
    'obligationId',v_obligation.id,
    'effectiveState',v_position.effective_state,
    'openAmount',v_position.open_amount,
    'currency',v_position.currency
  );
end;
$$;

create or replace function atlas.void_money_obligation_core_v1(
  p_obligation_id uuid,
  p_reason_kind text,
  p_source_event_kind text,
  p_source_event_id text,
  p_note text,
  p_idempotency_key text,
  p_recorded_by_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text := lower(nullif(btrim(p_reason_kind),''));
  v_key text := nullif(btrim(p_idempotency_key),'');
  v_obligation atlas.money_obligations%rowtype;
  v_existing atlas.money_obligation_void_events%rowtype;
begin
  if p_obligation_id is null or v_reason is null or v_key is null then
    raise exception 'Money obligation void identity is incomplete.' using errcode='22023';
  end if;

  select * into v_obligation
  from atlas.money_obligations o
  where o.id=p_obligation_id
  for update;
  if v_obligation.id is null then
    raise exception 'Money obligation not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.money_obligation_void_events v
  where v.obligation_id=p_obligation_id;
  if v_existing.id is not null then
    if v_existing.reason_kind is distinct from v_reason
       or v_existing.idempotency_key is distinct from v_key then
      raise exception 'Money obligation already has a different void event.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists(
    select 1 from atlas.money_obligation_void_events v
    where v.organization_id=v_obligation.organization_id
      and v.idempotency_key=v_key
  ) then
    raise exception 'Money obligation void idempotency key is already bound.' using errcode='23505';
  end if;

  insert into atlas.money_obligation_void_events(
    organization_id,obligation_id,reason_kind,source_event_kind,source_event_id,note,
    idempotency_key,recorded_by_user_id,metadata
  ) values (
    v_obligation.organization_id,v_obligation.id,v_reason,
    nullif(btrim(coalesce(p_source_event_kind,'')),''),
    nullif(btrim(coalesce(p_source_event_id,'')),''),
    nullif(btrim(coalesce(p_note,'')),''),
    v_key,p_recorded_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

revoke execute on function atlas.ensure_money_obligation_core_v1(uuid,text,text,text,text,numeric,text,timestamptz,text,uuid,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.money_source_coverage_state_core_v1(uuid,text,text,text,text,timestamptz,numeric)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.void_money_obligation_core_v1(uuid,text,text,text,text,text,uuid,jsonb)
  from public,anon,authenticated,service_role;

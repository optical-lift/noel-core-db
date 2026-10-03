-- Atlas Money Collection Kernel v1 — receipt/allocation/reversal tranche.
-- Reviewed migration-source SQL only; not a generated Supabase migration.

alter table atlas.money_receipts
  add constraint money_receipts_provider_event_custody_fkey
    foreign key (provider_event_id,organization_id,connected_source_id)
    references atlas.money_provider_events(id,organization_id,connected_source_id)
    on delete restrict;

alter table atlas.money_receipt_allocations
  add column currency text not null check (currency ~ '^[A-Z]{3}$'),
  add constraint money_receipt_allocations_id_receipt_org_currency_unique
    unique (id,receipt_id,organization_id,currency),
  add constraint money_receipt_allocations_receipt_fkey
    foreign key (receipt_id,organization_id,currency)
    references atlas.money_receipts(id,organization_id,currency)
    on delete restrict,
  add constraint money_receipt_allocations_obligation_fkey
    foreign key (obligation_id,organization_id,currency)
    references atlas.money_obligations(id,organization_id,currency)
    on delete restrict;

alter table atlas.money_receipt_reversal_events
  add column currency text not null check (currency ~ '^[A-Z]{3}$'),
  add constraint money_receipt_reversal_events_id_receipt_org_currency_unique
    unique (id,receipt_id,organization_id,currency),
  add constraint money_receipt_reversal_events_receipt_fkey
    foreign key (receipt_id,organization_id,currency)
    references atlas.money_receipts(id,organization_id,currency)
    on delete restrict,
  add constraint money_receipt_reversal_evidence_check check (
    (provider_event_id is not null and recorded_by_user_id is null)
    or
    (provider_event_id is null and recorded_by_user_id is not null)
  );

alter table atlas.money_receipt_allocation_reversal_events
  add column receipt_id uuid not null,
  add column currency text not null check (currency ~ '^[A-Z]{3}$'),
  add constraint money_receipt_allocation_reversal_receipt_event_fkey
    foreign key (receipt_reversal_event_id,receipt_id,organization_id,currency)
    references atlas.money_receipt_reversal_events(id,receipt_id,organization_id,currency)
    on delete restrict,
  add constraint money_receipt_allocation_reversal_allocation_fkey
    foreign key (receipt_allocation_id,receipt_id,organization_id,currency)
    references atlas.money_receipt_allocations(id,receipt_id,organization_id,currency)
    on delete restrict;

create or replace function atlas.record_money_receipt_from_provider_event_core_v1(
  p_provider_event_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_event atlas.money_provider_events%rowtype;
  v_attempt atlas.money_collection_attempts%rowtype;
  v_existing atlas.money_receipts%rowtype;
  v_amount numeric(14,2);
  v_currency text;
  v_received_at timestamptz;
  v_prior_gross numeric(14,2);
begin
  if p_provider_event_id is null or v_key is null then
    raise exception 'Provider receipt identity is incomplete.' using errcode='22023';
  end if;

  select * into v_event from atlas.money_provider_events e
  where e.id=p_provider_event_id for update;
  if v_event.id is null or v_event.collection_attempt_id is null then
    raise exception 'Provider event is not attached to a collection attempt.' using errcode='P0002';
  end if;
  if not (v_event.normalized_evidence @> '{"moneyReceived":true}'::jsonb) then
    raise exception 'Provider event does not carry admitted money-received evidence.' using errcode='23514';
  end if;

  begin
    v_amount:=round((v_event.normalized_evidence->>'amount')::numeric,2);
    v_currency:=upper(btrim(v_event.normalized_evidence->>'currency'));
    v_received_at:=coalesce(
      nullif(v_event.normalized_evidence->>'receivedAt','')::timestamptz,
      v_event.occurred_at,v_event.received_at
    );
  exception when others then
    raise exception 'Provider event money evidence is malformed.' using errcode='22023';
  end;
  if v_amount is null or v_amount<=0 or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Provider receipt amount/currency is invalid.' using errcode='22023';
  end if;

  select * into v_attempt from atlas.money_collection_attempts a
  where a.id=v_event.collection_attempt_id
    and a.organization_id=v_event.organization_id
    and a.connected_source_id=v_event.connected_source_id
  for update;
  if v_attempt.id is null or v_attempt.currency is distinct from v_currency then
    raise exception 'Provider receipt crosses attempt currency or custody.' using errcode='42501';
  end if;

  select * into v_existing from atlas.money_receipts r where r.provider_event_id=v_event.id;
  if v_existing.id is not null then
    if v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency
       or v_existing.idempotency_key is distinct from v_key then
      raise exception 'Provider receipt replay conflicts with existing receipt.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if exists(select 1 from atlas.money_receipts r
            where r.organization_id=v_attempt.organization_id and r.idempotency_key=v_key) then
    raise exception 'Receipt idempotency key is already bound to different evidence.' using errcode='23505';
  end if;

  select coalesce(sum(r.amount),0)::numeric(14,2) into v_prior_gross
  from atlas.money_receipts r
  join atlas.money_provider_events e on e.id=r.provider_event_id
  where e.collection_attempt_id=v_attempt.id;
  if v_prior_gross+v_amount>v_attempt.requested_amount then
    raise exception 'Provider receipts would exceed the collection attempt requested amount.' using errcode='23514';
  end if;

  insert into atlas.money_receipts(
    organization_id,amount,currency,received_at,evidence_kind,connected_source_id,
    provider_event_id,recorded_by_user_id,idempotency_key,metadata
  ) values (
    v_attempt.organization_id,v_amount,v_currency,v_received_at,'provider_event',
    v_attempt.connected_source_id,v_event.id,null,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;
  return v_existing.id;
end;
$$;

create or replace function atlas.record_manual_money_receipt_core_v1(
  p_organization_id uuid,
  p_amount numeric,
  p_currency text,
  p_received_at timestamptz,
  p_recorded_by_user_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_amount numeric(14,2):=round(p_amount,2);
  v_currency text:=upper(nullif(btrim(p_currency),''));
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_receipts%rowtype;
begin
  if p_organization_id is null or p_recorded_by_user_id is null or p_received_at is null or v_key is null then
    raise exception 'Manual receipt identity/evidence is incomplete.' using errcode='22023';
  end if;
  if v_amount is null or v_amount<=0 or v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Manual receipt amount/currency is invalid.' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id) then
    raise exception 'Manual receipt organization does not exist.' using errcode='23503';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_organization_id::text||':manual-receipt:'||v_key,0)
  );
  select * into v_existing from atlas.money_receipts r
  where r.organization_id=p_organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.evidence_kind is distinct from 'manual'
       or v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency
       or v_existing.received_at is distinct from p_received_at
       or v_existing.recorded_by_user_id is distinct from p_recorded_by_user_id then
      raise exception 'Manual receipt retry conflicts with existing receipt.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.money_receipts(
    organization_id,amount,currency,received_at,evidence_kind,connected_source_id,
    provider_event_id,recorded_by_user_id,idempotency_key,metadata
  ) values (
    p_organization_id,v_amount,v_currency,p_received_at,'manual',null,null,
    p_recorded_by_user_id,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;
  return v_existing.id;
end;
$$;

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
set search_path=''
as $$
declare
  v_amount numeric(14,2):=round(p_amount,2);
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_receipt atlas.money_receipts%rowtype;
  v_obligation atlas.money_obligations%rowtype;
  v_receipt_position record;
  v_obligation_position record;
  v_existing atlas.money_receipt_allocations%rowtype;
begin
  if p_receipt_id is null or p_obligation_id is null or v_key is null or v_amount is null or v_amount<=0 then
    raise exception 'Receipt allocation identity/amount is invalid.' using errcode='22023';
  end if;

  -- Advisory locking provides one deterministic cross-table lock key; the row
  -- locks then protect the concrete receipt and obligation values.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      least(p_receipt_id::text,p_obligation_id::text)||':'||greatest(p_receipt_id::text,p_obligation_id::text),0
    )
  );
  select * into v_receipt from atlas.money_receipts r where r.id=p_receipt_id for update;
  select * into v_obligation from atlas.money_obligations o where o.id=p_obligation_id for update;
  if v_receipt.id is null or v_obligation.id is null then
    raise exception 'Receipt or obligation not found.' using errcode='P0002';
  end if;
  if v_receipt.organization_id is distinct from v_obligation.organization_id
     or v_receipt.currency is distinct from v_obligation.currency then
    raise exception 'Receipt allocation crosses organization or currency custody.' using errcode='42501';
  end if;

  select * into v_existing from atlas.money_receipt_allocations a
  where a.organization_id=v_receipt.organization_id and a.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from v_receipt.id
       or v_existing.obligation_id is distinct from v_obligation.id
       or v_existing.amount is distinct from v_amount
       or v_existing.currency is distinct from v_receipt.currency then
      raise exception 'Receipt allocation retry conflicts with existing allocation.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select * into v_receipt_position from atlas.money_receipt_position_v1 p where p.receipt_id=v_receipt.id;
  select * into v_obligation_position from atlas.money_obligation_position_v1 p where p.obligation_id=v_obligation.id;
  if v_receipt_position.allocation_exceeds_net_received then
    raise exception 'Receipt is already in an invalid allocation position.' using errcode='23514';
  end if;
  if v_amount>v_receipt_position.available_amount then
    raise exception 'Receipt allocation exceeds effective receipt availability.' using errcode='23514';
  end if;
  if v_amount>v_obligation_position.open_amount then
    raise exception 'Receipt allocation exceeds effective obligation open amount.' using errcode='23514';
  end if;

  insert into atlas.money_receipt_allocations(
    organization_id,receipt_id,obligation_id,amount,currency,idempotency_key,metadata
  ) values (
    v_receipt.organization_id,v_receipt.id,v_obligation.id,v_amount,v_receipt.currency,
    v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;
  return v_existing.id;
end;
$$;

create or replace function atlas.reverse_money_receipt_core_v1(
  p_receipt_id uuid,
  p_amount numeric,
  p_reversal_kind text,
  p_provider_event_id uuid,
  p_recorded_by_user_id uuid,
  p_occurred_at timestamptz,
  p_allocation_reversals jsonb,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_amount numeric(14,2):=round(p_amount,2);
  v_kind text:=lower(nullif(btrim(p_reversal_kind),''));
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_receipt atlas.money_receipts%rowtype;
  v_event atlas.money_provider_events%rowtype;
  v_original_event atlas.money_provider_events%rowtype;
  v_existing atlas.money_receipt_reversal_events%rowtype;
  v_receipt_position record;
  v_item jsonb;
  v_allocation atlas.money_receipt_allocations%rowtype;
  v_allocation_id uuid;
  v_reverse_amount numeric(14,2);
  v_effective_allocated numeric(14,2);
  v_supplied_reopen numeric(14,2):=0;
  v_required_reopen numeric(14,2);
  v_count integer;
  v_distinct_count integer;
begin
  if p_receipt_id is null or v_amount is null or v_amount<=0 or v_kind is null
     or p_occurred_at is null or v_key is null then
    raise exception 'Receipt reversal identity/evidence is incomplete.' using errcode='22023';
  end if;
  if (p_provider_event_id is not null)=(p_recorded_by_user_id is not null) then
    raise exception 'Receipt reversal requires exactly one provider-event or manual recorder evidence source.' using errcode='22023';
  end if;
  if p_allocation_reversals is null or jsonb_typeof(p_allocation_reversals)<>'array' then
    raise exception 'Allocation reversal applications must be a JSON array.' using errcode='22023';
  end if;

  select * into v_receipt from atlas.money_receipts r where r.id=p_receipt_id for update;
  if v_receipt.id is null then raise exception 'Receipt not found.' using errcode='P0002'; end if;

  select * into v_existing from atlas.money_receipt_reversal_events r
  where r.organization_id=v_receipt.organization_id and r.idempotency_key=v_key;
  if v_existing.id is not null then
    if v_existing.receipt_id is distinct from v_receipt.id
       or v_existing.amount is distinct from v_amount
       or v_existing.reversal_kind is distinct from v_kind
       or v_existing.provider_event_id is distinct from p_provider_event_id
       or v_existing.recorded_by_user_id is distinct from p_recorded_by_user_id
       or v_existing.currency is distinct from v_receipt.currency
       or jsonb_array_length(p_allocation_reversals) is distinct from (
         select count(*)::integer from atlas.money_receipt_allocation_reversal_events ar
         where ar.receipt_reversal_event_id=v_existing.id
       )
       or exists(
         select 1
         from jsonb_array_elements(p_allocation_reversals) supplied
         left join atlas.money_receipt_allocation_reversal_events ar
           on ar.receipt_reversal_event_id=v_existing.id
          and ar.receipt_allocation_id=(supplied->>'allocationId')::uuid
          and ar.amount=round((supplied->>'amount')::numeric,2)
         where ar.id is null
       ) then
      raise exception 'Receipt reversal retry conflicts with existing evidence.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  if p_provider_event_id is not null then
    select * into v_event from atlas.money_provider_events e where e.id=p_provider_event_id for update;
    if v_event.id is null
       or v_receipt.connected_source_id is null
       or v_event.organization_id is distinct from v_receipt.organization_id
       or v_event.connected_source_id is distinct from v_receipt.connected_source_id then
      raise exception 'Provider reversal event crosses receipt custody.' using errcode='42501';
    end if;
    if v_receipt.provider_event_id is null then
      raise exception 'Provider reversal cannot be attached to a manual receipt.' using errcode='42501';
    end if;
    select * into v_original_event from atlas.money_provider_events e where e.id=v_receipt.provider_event_id;
    if v_original_event.collection_attempt_id is distinct from v_event.collection_attempt_id then
      raise exception 'Provider reversal event belongs to a different collection attempt.' using errcode='42501';
    end if;
    if not (v_event.normalized_evidence @> '{"moneyReversed":true}'::jsonb) then
      raise exception 'Provider event does not carry admitted money-reversal evidence.' using errcode='23514';
    end if;
    begin
      if round((v_event.normalized_evidence->>'amount')::numeric,2) is distinct from v_amount
         or upper(btrim(v_event.normalized_evidence->>'currency')) is distinct from v_receipt.currency then
        raise exception 'Provider reversal amount/currency conflicts with admitted evidence.' using errcode='23514';
      end if;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Provider reversal money evidence is malformed.' using errcode='22023';
    end;
    if exists(select 1 from atlas.money_receipts r where r.provider_event_id=v_event.id)
       or exists(select 1 from atlas.money_receipt_reversal_events r where r.provider_event_id=v_event.id) then
      raise exception 'Provider event is already consumed as money evidence.' using errcode='23505';
    end if;
  end if;

  select * into v_receipt_position from atlas.money_receipt_position_v1 p where p.receipt_id=v_receipt.id;
  if v_receipt_position.allocation_exceeds_net_received then
    raise exception 'Receipt is already in an invalid allocation position.' using errcode='23514';
  end if;
  if v_amount>v_receipt_position.net_received_amount then
    raise exception 'Receipt reversal exceeds effective received amount.' using errcode='23514';
  end if;

  v_required_reopen:=greatest(v_amount-v_receipt_position.available_amount,0)::numeric(14,2);
  v_count:=jsonb_array_length(p_allocation_reversals);
  select count(distinct value->>'allocationId') into v_distinct_count
  from jsonb_array_elements(p_allocation_reversals);
  if v_count<>v_distinct_count then
    raise exception 'An allocation may appear only once in a receipt reversal.' using errcode='22023';
  end if;

  for v_allocation_id in
    select a.id from atlas.money_receipt_allocations a
    where a.id in (select (value->>'allocationId')::uuid from jsonb_array_elements(p_allocation_reversals))
    order by a.id for update
  loop null; end loop;
  if (select count(*) from atlas.money_receipt_allocations a
      where a.id in (select (value->>'allocationId')::uuid from jsonb_array_elements(p_allocation_reversals)))<>v_count then
    raise exception 'One or more receipt allocations were not found.' using errcode='P0002';
  end if;

  for v_item in select value from jsonb_array_elements(p_allocation_reversals)
  loop
    begin
      v_allocation_id:=(v_item->>'allocationId')::uuid;
      v_reverse_amount:=round((v_item->>'amount')::numeric,2);
    exception when others then
      raise exception 'Each allocation reversal requires a valid allocationId and amount.' using errcode='22023';
    end;
    if v_reverse_amount is null or v_reverse_amount<=0 then
      raise exception 'Allocation reversal amount must be positive.' using errcode='22023';
    end if;
    select * into v_allocation from atlas.money_receipt_allocations a where a.id=v_allocation_id;
    if v_allocation.receipt_id is distinct from v_receipt.id
       or v_allocation.organization_id is distinct from v_receipt.organization_id
       or v_allocation.currency is distinct from v_receipt.currency then
      raise exception 'Allocation reversal crosses receipt custody.' using errcode='42501';
    end if;
    select greatest(v_allocation.amount-coalesce(sum(ar.amount),0),0)::numeric(14,2)
    into v_effective_allocated
    from atlas.money_receipt_allocation_reversal_events ar
    where ar.receipt_allocation_id=v_allocation.id;
    if v_reverse_amount>v_effective_allocated then
      raise exception 'Allocation reversal exceeds effective allocated amount.' using errcode='23514';
    end if;
    v_supplied_reopen:=v_supplied_reopen+v_reverse_amount;
  end loop;

  if v_supplied_reopen is distinct from v_required_reopen then
    raise exception 'Allocation reversals must exactly match the paid position reopened by this receipt reversal.' using errcode='23514';
  end if;

  insert into atlas.money_receipt_reversal_events(
    organization_id,receipt_id,amount,currency,reversal_kind,provider_event_id,
    recorded_by_user_id,occurred_at,idempotency_key,metadata
  ) values (
    v_receipt.organization_id,v_receipt.id,v_amount,v_receipt.currency,v_kind,
    p_provider_event_id,p_recorded_by_user_id,p_occurred_at,v_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  for v_item in select value from jsonb_array_elements(p_allocation_reversals)
  loop
    v_allocation_id:=(v_item->>'allocationId')::uuid;
    v_reverse_amount:=round((v_item->>'amount')::numeric,2);
    insert into atlas.money_receipt_allocation_reversal_events(
      organization_id,receipt_reversal_event_id,receipt_allocation_id,receipt_id,
      amount,currency,idempotency_key,metadata
    ) values (
      v_receipt.organization_id,v_existing.id,v_allocation_id,v_receipt.id,
      v_reverse_amount,v_receipt.currency,v_key||':allocation:'||v_allocation_id::text,
      jsonb_build_object('receiptReversalId',v_existing.id)
    );
  end loop;
  return v_existing.id;
end;
$$;

create or replace view atlas.money_receipt_position_v1
with (security_invoker=true)
as
with reversal as (
  select r.receipt_id,sum(r.amount)::numeric(14,2) as reversed_amount
  from atlas.money_receipt_reversal_events r group by r.receipt_id
), allocation as (
  select a.receipt_id,sum(a.amount)::numeric(14,2) as allocated_amount
  from atlas.money_receipt_allocations a group by a.receipt_id
), allocation_reversal as (
  select a.receipt_id,sum(ar.amount)::numeric(14,2) as allocation_reversed_amount
  from atlas.money_receipt_allocation_reversal_events ar
  join atlas.money_receipt_allocations a on a.id=ar.receipt_allocation_id
  group by a.receipt_id
), position as (
  select r.*,
    coalesce(rv.reversed_amount,0)::numeric(14,2) as reversed_amount,
    coalesce(a.allocated_amount,0)::numeric(14,2) as gross_allocated_amount,
    coalesce(ar.allocation_reversed_amount,0)::numeric(14,2) as allocation_reversed_amount
  from atlas.money_receipts r
  left join reversal rv on rv.receipt_id=r.id
  left join allocation a on a.receipt_id=r.id
  left join allocation_reversal ar on ar.receipt_id=r.id
)
select
  p.id as receipt_id,p.organization_id,p.amount as gross_received_amount,p.reversed_amount,
  greatest(p.amount-p.reversed_amount,0)::numeric(14,2) as net_received_amount,
  p.gross_allocated_amount,p.allocation_reversed_amount,
  greatest(p.gross_allocated_amount-p.allocation_reversed_amount,0)::numeric(14,2) as net_allocated_amount,
  greatest(
    greatest(p.amount-p.reversed_amount,0)-greatest(p.gross_allocated_amount-p.allocation_reversed_amount,0),0
  )::numeric(14,2) as available_amount,
  greatest(p.gross_allocated_amount-p.allocation_reversed_amount,0)
    > greatest(p.amount-p.reversed_amount,0) as allocation_exceeds_net_received,
  p.currency,p.evidence_kind,p.connected_source_id,p.provider_event_id,p.received_at,p.created_at
from position p;

revoke execute on function atlas.record_money_receipt_from_provider_event_core_v1(uuid,text,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.record_manual_money_receipt_core_v1(uuid,numeric,text,timestamptz,uuid,text,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.allocate_money_receipt_core_v1(uuid,uuid,numeric,text,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.reverse_money_receipt_core_v1(uuid,numeric,text,uuid,uuid,timestamptz,jsonb,text,jsonb)
  from public,anon,authenticated,service_role;
revoke all on atlas.money_receipt_position_v1 from anon,authenticated,service_role;

-- Atlas financial inflow review v1
--
-- Purpose:
--   extend Principal financial-source review to source credits without making
--   the bank feed a second sales ledger. Existing commercial payments may be
--   reconciled to a source credit. Unmatched business credits may be established
--   as Organization Receipts without inventing an order or tax treatment.
--
-- Truth boundary:
--   source credit != revenue;
--   Organization Receipt != commercial order;
--   receipt kind != tax treatment;
--   existing commercial truth is reconciled, not duplicated.

create table atlas.financial_commercial_reconciliations (
  id uuid primary key default gen_random_uuid(),
  financial_source_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  commercial_payment_event_id uuid not null references atlas.commercial_payment_events(id) on delete restrict,
  amount numeric not null check (amount>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  reconciliation_state text not null default 'confirmed' check (reconciliation_state in ('confirmed','superseded')),
  confirmed_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  client_event_key text not null check (btrim(client_event_key)<>''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  unique (confirmed_by_principal_id,client_event_key),
  unique (financial_source_transaction_id,commercial_payment_event_id),
  check ((reconciliation_state='superseded')=(superseded_at is not null))
);

create index financial_commercial_reconciliations_tx_idx
  on atlas.financial_commercial_reconciliations(financial_source_transaction_id,reconciliation_state);
create index financial_commercial_reconciliations_event_idx
  on atlas.financial_commercial_reconciliations(commercial_payment_event_id,reconciliation_state);

create table atlas.financial_inflow_allocation_events (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  actor_principal_id uuid not null references atlas.principals(id) on delete restrict,
  event_kind text not null check (event_kind='allocations_replaced'),
  client_event_key text not null check (btrim(client_event_key)<>''),
  reason text,
  before_state jsonb,
  after_state jsonb not null default '{}'::jsonb check (jsonb_typeof(after_state)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (actor_principal_id,client_event_key),
  check (before_state is null or jsonb_typeof(before_state)='object')
);

create table atlas.financial_inflow_allocations (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  established_by_event_id uuid not null references atlas.financial_inflow_allocation_events(id) on delete restrict,
  allocation_kind text not null check (allocation_kind in ('organization_receipt','personal','household','nonbusiness','other')),
  allocated_amount numeric not null check (allocated_amount>0),
  receipt_kind text check (receipt_kind in ('operating_receipt','owner_contribution','loan_proceeds','refund','reimbursement','other_receipt')),
  target_ledger_id uuid references ledger.ledgers(id) on delete restrict,
  target_organization_id uuid references atlas.organizations(id) on delete restrict,
  operational_purpose text,
  allocation_state text not null default 'active' check (allocation_state in ('active','superseded')),
  confirmed_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  superseded_by_event_id uuid references atlas.financial_inflow_allocation_events(id) on delete restrict,
  check (operational_purpose is null or btrim(operational_purpose)<>''),
  check (
    (allocation_kind='organization_receipt' and target_ledger_id is not null and target_organization_id is not null and receipt_kind is not null)
    or
    (allocation_kind<>'organization_receipt' and target_ledger_id is null and target_organization_id is null and receipt_kind is null)
  ),
  check ((allocation_state='superseded')=(superseded_at is not null))
);

create index financial_inflow_allocations_tx_idx
  on atlas.financial_inflow_allocations(transaction_id,allocation_state);
create index financial_inflow_allocations_ledger_idx
  on atlas.financial_inflow_allocations(target_ledger_id,allocation_state)
  where target_ledger_id is not null;

create table atlas.organization_receipt_occurrences (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  financial_source_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  financial_inflow_allocation_id uuid not null unique references atlas.financial_inflow_allocations(id) on delete restrict,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  received_on date not null,
  received_at timestamptz,
  gross_amount numeric not null check (gross_amount>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  receipt_kind text not null check (receipt_kind in ('operating_receipt','owner_contribution','loan_proceeds','refund','reimbursement','other_receipt')),
  counterparty_label text,
  source_label text,
  operational_purpose text,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  created_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  check (counterparty_label is null or btrim(counterparty_label)<>''),
  check (source_label is null or btrim(source_label)<>''),
  check (operational_purpose is null or btrim(operational_purpose)<>'')
);

create index organization_receipt_occurrences_ledger_date_idx
  on atlas.organization_receipt_occurrences(ledger_id,received_on desc,id);
create index organization_receipt_occurrences_org_date_idx
  on atlas.organization_receipt_occurrences(organization_id,received_on desc,id);

alter table atlas.financial_commercial_reconciliations enable row level security;
alter table atlas.financial_inflow_allocation_events enable row level security;
alter table atlas.financial_inflow_allocations enable row level security;
alter table atlas.organization_receipt_occurrences enable row level security;

revoke all on table atlas.financial_commercial_reconciliations from public,anon,authenticated;
revoke all on table atlas.financial_inflow_allocation_events from public,anon,authenticated;
revoke all on table atlas.financial_inflow_allocations from public,anon,authenticated;
revoke all on table atlas.organization_receipt_occurrences from public,anon,authenticated;

create or replace function atlas.financial_assert_ledger_organization_routing_v1(
  p_ledger_id uuid,
  p_organization_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','ledger'
as $function$
begin
  if p_ledger_id is null or p_organization_id is null or not exists(
    select 1
    from ledger.ledgers l
    join atlas.ledger_organization_participations p
      on p.ledger_id=l.id
     and p.organization_id=p_organization_id
     and p.status='active'
     and p.ended_at is null
    where l.id=p_ledger_id
      and l.ledger_state='active'
      and l.retired_at is null
  ) then
    raise exception 'Financial routing requires an active native Ledger and active Organization compatibility participation.' using errcode='23503';
  end if;
end;
$function$;

create or replace function atlas.financial_inflow_allocation_snapshot_v1(p_transaction_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select jsonb_build_object(
    'transactionId',p_transaction_id,
    'allocations',coalesce(jsonb_agg(jsonb_build_object(
      'allocationId',a.id,
      'allocationKind',a.allocation_kind,
      'amount',a.allocated_amount,
      'receiptKind',a.receipt_kind,
      'targetLedgerId',a.target_ledger_id,
      'targetOrganizationId',a.target_organization_id,
      'operationalPurpose',a.operational_purpose,
      'receiptOccurrenceId',r.id
    ) order by a.created_at,a.id) filter(where a.id is not null),'[]'::jsonb)
  )
  from atlas.financial_inflow_allocations a
  left join atlas.organization_receipt_occurrences r on r.financial_inflow_allocation_id=a.id
  where a.transaction_id=p_transaction_id and a.allocation_state='active'
$function$;

create or replace function atlas.financial_commercial_collection_candidates_self_api_v1(
  p_start_on date,
  p_end_on date,
  p_max_day_distance integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','ledger'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_person uuid:=atlas.current_person_id_v1();
begin
  if auth.uid() is null or v_principal is null or v_person is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid commercial reconciliation window required.' using errcode='22023'; end if;
  if p_max_day_distance is null or p_max_day_distance<0 or p_max_day_distance>14 then raise exception 'Commercial candidate day distance must be between 0 and 14.' using errcode='22023'; end if;

  return jsonb_build_object(
    'contractVersion','financial_commercial_collection_candidates_self_v1',
    'startOn',p_start_on,
    'endOn',p_end_on,
    'maxDayDistance',p_max_day_distance,
    'items',coalesce((
      with credit_remaining as (
        select c.*,
          c.amount
          - coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=c.id and r.reconciliation_state='confirmed'),0)
          - coalesce((select sum(a.allocated_amount) from atlas.financial_inflow_allocations a where a.transaction_id=c.id and a.allocation_state='active'),0)
          - coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.financial_source_transaction_id=c.id and r.reconciliation_state='confirmed'),0) as remaining_amount
        from atlas.financial_source_transactions c
        where c.direction='credit'
          and c.truth_state='observed'
          and c.transaction_date between p_start_on and p_end_on
          and atlas.financial_source_authorized_self_v1(c.connected_source_id)
      ),
      event_remaining as (
        select e.id as commercial_payment_event_id,
          e.commercial_payment_id,
          p.commercial_order_id,
          e.amount_delta
          - coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.commercial_payment_event_id=e.id and r.reconciliation_state='confirmed'),0) as remaining_amount,
          e.currency,
          e.occurred_at,
          p.provider_key,
          p.provider_payment_key,
          fp.effective_ledger_id,
          fp.effective_organization_id,
          fp.order_kind,
          fp.order_date,
          fp.source_domain,
          fp.source_kind,
          fp.source_id
        from atlas.commercial_payment_events e
        join atlas.commercial_payments p on p.id=e.commercial_payment_id
        join atlas.commercial_financial_position_v1 fp on fp.commercial_order_id=p.commercial_order_id
        where e.event_kind='succeeded'
          and e.amount_delta>0
          and e.occurred_at::date between p_start_on-p_max_day_distance and p_end_on+p_max_day_distance
          and fp.effective_ledger_id is not null
          and exists(
            select 1 from ledger.seats s
            where s.ledger_id=fp.effective_ledger_id
              and s.person_entity_id=v_person
              and s.seat_state='active'
              and s.ended_at is null
          )
      )
      select jsonb_agg(jsonb_build_object(
        'transactionId',c.id,
        'commercialPaymentEventId',e.commercial_payment_event_id,
        'commercialPaymentId',e.commercial_payment_id,
        'commercialOrderId',e.commercial_order_id,
        'amount',c.remaining_amount,
        'currency',c.currency,
        'dayDistance',abs(c.transaction_date-e.occurred_at::date),
        'transactionDate',c.transaction_date,
        'paymentOccurredAt',e.occurred_at,
        'transactionDescription',c.description,
        'source',jsonb_build_object(
          'sourceId',s.id,'displayLabel',s.display_label,'accountHint',s.account_hint,'providerKey',s.provider_key
        ),
        'ledgerId',e.effective_ledger_id,
        'organizationId',e.effective_organization_id,
        'orderKind',e.order_kind,
        'orderDate',e.order_date,
        'commercialSource',jsonb_build_object('domain',e.source_domain,'kind',e.source_kind,'id',e.source_id),
        'paymentProvider',e.provider_key,
        'paymentProviderKey',e.provider_payment_key,
        'basis',jsonb_build_object('sameRemainingAmount',true,'sameCurrency',true,'nearbyDate',true,'existingCommercialTruth',true)
      ) order by abs(c.transaction_date-e.occurred_at::date),c.transaction_date,c.id,e.commercial_payment_event_id)
      from credit_remaining c
      join event_remaining e
        on e.currency=c.currency
       and e.remaining_amount=c.remaining_amount
       and e.remaining_amount>0
       and abs(c.transaction_date-e.occurred_at::date)<=p_max_day_distance
      join atlas.connected_sources s on s.id=c.connected_source_id
      where c.remaining_amount>0
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'suggestionOnly',true,
      'commercialTruthAlreadyExists',true,
      'merchantTextNotUsedAsAuthority',true,
      'noRevenueCreated',true,
      'noReconciliationWritten',true
    )
  );
end;
$function$;

create or replace function atlas.confirm_financial_commercial_collection_self_api_v1(
  p_transaction_id uuid,
  p_commercial_payment_event_id uuid,
  p_amount numeric,
  p_client_event_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_tx atlas.financial_source_transactions%rowtype;
  v_event atlas.commercial_payment_events%rowtype;
  v_payment atlas.commercial_payments%rowtype;
  v_position atlas.commercial_financial_position_v1%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_tx_used numeric:=0;
  v_event_used numeric:=0;
  v_id uuid;
  v_existing atlas.financial_commercial_reconciliations%rowtype;
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_amount is null or p_amount<=0 then raise exception 'Client event key and positive reconciliation amount are required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Commercial reconciliation metadata must be an object.' using errcode='22023'; end if;

  select * into v_existing from atlas.financial_commercial_reconciliations r
  where r.confirmed_by_principal_id=v_principal and r.client_event_key=v_key;
  if v_existing.id is not null then
    if v_existing.financial_source_transaction_id is distinct from p_transaction_id
       or v_existing.commercial_payment_event_id is distinct from p_commercial_payment_event_id
       or v_existing.amount is distinct from p_amount then
      raise exception 'Client event key already belongs to a different commercial reconciliation.' using errcode='23514';
    end if;
    return jsonb_build_object('contractVersion','confirm_financial_commercial_collection_self_v1','state','unchanged','reconciliationId',v_existing.id);
  end if;

  select * into v_tx from atlas.financial_source_transactions where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Financial source transaction not found.' using errcode='P0002'; end if;
  if v_tx.truth_state<>'observed' or v_tx.direction<>'credit' then raise exception 'Commercial collection reconciliation requires an observed source credit.' using errcode='23514'; end if;
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then raise exception 'Financial source custody required.' using errcode='42501'; end if;

  select * into v_event from atlas.commercial_payment_events where id=p_commercial_payment_event_id for update;
  if v_event.id is null or v_event.event_kind<>'succeeded' or v_event.amount_delta<=0 then raise exception 'A succeeded positive commercial payment event is required.' using errcode='23514'; end if;
  select * into v_payment from atlas.commercial_payments where id=v_event.commercial_payment_id;
  if v_payment.id is null or v_payment.commercial_order_id is null then raise exception 'Commercial payment must belong to an established commercial order.' using errcode='23514'; end if;
  select * into v_position from atlas.commercial_financial_position_v1 where commercial_order_id=v_payment.commercial_order_id;
  if v_position.commercial_order_id is null or v_position.effective_ledger_id is null or v_position.effective_organization_id is null then
    raise exception 'Commercial payment is outside canonical Ledger custody.' using errcode='23514';
  end if;
  perform atlas.current_active_ledger_seat_v1(v_position.effective_ledger_id);
  if atlas.current_organization_membership_v1(v_position.effective_organization_id) is null then
    raise exception 'Organization membership required to reconcile commercial collection.' using errcode='42501';
  end if;
  if v_tx.currency<>v_event.currency then raise exception 'Source credit and commercial payment must use the same currency.' using errcode='23514'; end if;

  select
    coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=v_tx.id and r.reconciliation_state='confirmed'),0)
    + coalesce((select sum(a.allocated_amount) from atlas.financial_inflow_allocations a where a.transaction_id=v_tx.id and a.allocation_state='active'),0)
    + coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.financial_source_transaction_id=v_tx.id and r.reconciliation_state='confirmed'),0)
  into v_tx_used;
  select coalesce(sum(r.amount),0) into v_event_used
  from atlas.financial_commercial_reconciliations r
  where r.commercial_payment_event_id=v_event.id and r.reconciliation_state='confirmed';

  if v_tx_used+p_amount>v_tx.amount then raise exception 'Commercial reconciliation exceeds the unresolved source credit.' using errcode='23514'; end if;
  if v_event_used+p_amount>v_event.amount_delta then raise exception 'Commercial reconciliation exceeds the unresolved payment event.' using errcode='23514'; end if;

  insert into atlas.financial_commercial_reconciliations(
    financial_source_transaction_id,commercial_payment_event_id,amount,currency,
    confirmed_by_principal_id,client_event_key,metadata
  ) values(
    v_tx.id,v_event.id,p_amount,v_tx.currency,v_principal,v_key,p_metadata
  ) returning id into v_id;

  return jsonb_build_object(
    'contractVersion','confirm_financial_commercial_collection_self_v1',
    'state','confirmed',
    'reconciliationId',v_id,
    'transactionId',v_tx.id,
    'commercialPaymentEventId',v_event.id,
    'commercialOrderId',v_payment.commercial_order_id,
    'ledgerId',v_position.effective_ledger_id,
    'truthBoundary',jsonb_build_object(
      'commercialTruthCreated',false,
      'sourceEvidenceMutated',false,
      'reconciliationOnly',true,
      'revenueNotDuplicated',true
    )
  );
end;
$function$;

create or replace function atlas.replace_financial_credit_allocations_self_api_v1(
  p_transaction_id uuid,
  p_client_event_key text,
  p_allocations jsonb,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
  v_tx atlas.financial_source_transactions%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_key text:=btrim(coalesce(p_client_event_key,''));
  v_event atlas.financial_inflow_allocation_events%rowtype;
  v_item jsonb;
  v_kind text;
  v_receipt_kind text;
  v_amount numeric;
  v_total numeric:=0;
  v_committed numeric:=0;
  v_ledger_id uuid;
  v_organization_id uuid;
  v_purpose text;
  v_item_metadata jsonb;
  v_membership uuid;
  v_allocation_id uuid;
  v_receipt_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if v_key='' or p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception 'Client event key and allocation array are required.' using errcode='22023'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Inflow allocation metadata must be an object.' using errcode='22023'; end if;

  select * into v_event from atlas.financial_inflow_allocation_events e
  where e.actor_principal_id=v_principal and e.client_event_key=v_key;
  if v_event.id is not null then
    return jsonb_build_object('contractVersion','replace_financial_credit_allocations_self_v1','state','unchanged','eventId',v_event.id,'afterState',v_event.after_state);
  end if;

  select * into v_tx from atlas.financial_source_transactions where id=p_transaction_id for update;
  if v_tx.id is null then raise exception 'Financial source transaction not found.' using errcode='P0002'; end if;
  if v_tx.truth_state<>'observed' or v_tx.direction<>'credit' then raise exception 'Inflow allocations apply only to observed source credits.' using errcode='23514'; end if;
  if not atlas.financial_source_authorized_self_v1(v_tx.connected_source_id) then raise exception 'Financial source custody required.' using errcode='42501'; end if;
  if exists(
    select 1
    from atlas.financial_inflow_allocations a
    join atlas.organization_receipt_occurrences r on r.financial_inflow_allocation_id=a.id
    where a.transaction_id=v_tx.id and a.allocation_state='active'
  ) then
    raise exception 'A promoted Organization Receipt cannot be silently replaced; correct the receipt through a governed correction flow.' using errcode='55000';
  end if;

  select * into v_source from atlas.connected_sources where id=v_tx.connected_source_id;
  select
    coalesce((select sum(r.amount) from atlas.financial_transfer_reconciliations r where r.to_transaction_id=v_tx.id and r.reconciliation_state='confirmed'),0)
    + coalesce((select sum(r.amount) from atlas.financial_commercial_reconciliations r where r.financial_source_transaction_id=v_tx.id and r.reconciliation_state='confirmed'),0)
  into v_committed;

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each inflow allocation must be an object.' using errcode='22023'; end if;
    v_kind:=lower(btrim(coalesce(v_item->>'allocationKind','')));
    begin v_amount:=(v_item->>'amount')::numeric; exception when others then raise exception 'Each inflow allocation requires numeric amount.' using errcode='22023'; end;
    if v_kind not in ('organization_receipt','personal','household','nonbusiness','other') or v_amount is null or v_amount<=0 then
      raise exception 'Each inflow allocation requires a supported kind and positive amount.' using errcode='22023';
    end if;
    v_total:=v_total+v_amount;
    if v_kind='organization_receipt' then
      begin
        v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
        v_organization_id:=nullif(v_item->>'organizationId','')::uuid;
      exception when others then
        raise exception 'Organization Receipt Ledger and Organization IDs must be UUIDs.' using errcode='22023';
      end;
      v_receipt_kind:=lower(btrim(coalesce(v_item->>'receiptKind','')));
      if v_ledger_id is null or v_organization_id is null then raise exception 'Organization Receipt requires Ledger and Organization.' using errcode='22023'; end if;
      if v_receipt_kind not in ('operating_receipt','owner_contribution','loan_proceeds','refund','reimbursement','other_receipt') then
        raise exception 'Organization Receipt requires a supported receipt kind.' using errcode='22023';
      end if;
      perform atlas.current_active_ledger_seat_v1(v_ledger_id);
      perform atlas.financial_assert_ledger_organization_routing_v1(v_ledger_id,v_organization_id);
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      if v_membership is null then raise exception 'Organization membership required to establish an Organization Receipt.' using errcode='42501'; end if;
    end if;
  end loop;

  if v_committed+v_total>v_tx.amount then raise exception 'Transfer, commercial reconciliation, and inflow allocations exceed the source credit amount.' using errcode='23514'; end if;

  v_before:=atlas.financial_inflow_allocation_snapshot_v1(v_tx.id);
  insert into atlas.financial_inflow_allocation_events(
    transaction_id,actor_principal_id,event_kind,client_event_key,reason,before_state,metadata
  ) values(
    v_tx.id,v_principal,'allocations_replaced',v_key,nullif(btrim(coalesce(p_reason,'')),''),v_before,p_metadata
  ) returning * into v_event;

  update atlas.financial_inflow_allocations
  set allocation_state='superseded',superseded_at=now(),superseded_by_event_id=v_event.id
  where transaction_id=v_tx.id and allocation_state='active';

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    v_kind:=lower(btrim(v_item->>'allocationKind'));
    v_amount:=(v_item->>'amount')::numeric;
    v_purpose:=nullif(btrim(coalesce(v_item->>'operationalPurpose','')),'');
    v_item_metadata:=coalesce(v_item->'metadata','{}'::jsonb);
    if jsonb_typeof(v_item_metadata)<>'object' then raise exception 'Inflow allocation metadata must be an object.' using errcode='22023'; end if;

    v_ledger_id:=null;
    v_organization_id:=null;
    v_receipt_kind:=null;
    if v_kind='organization_receipt' then
      v_ledger_id:=nullif(v_item->>'ledgerId','')::uuid;
      v_organization_id:=nullif(v_item->>'organizationId','')::uuid;
      v_receipt_kind:=lower(btrim(v_item->>'receiptKind'));
    end if;

    insert into atlas.financial_inflow_allocations(
      transaction_id,established_by_event_id,allocation_kind,allocated_amount,receipt_kind,
      target_ledger_id,target_organization_id,operational_purpose,confirmed_by_principal_id,metadata
    ) values(
      v_tx.id,v_event.id,v_kind,v_amount,v_receipt_kind,
      v_ledger_id,v_organization_id,v_purpose,v_principal,v_item_metadata
    ) returning id into v_allocation_id;

    if v_kind='organization_receipt' then
      v_membership:=atlas.current_organization_membership_v1(v_organization_id);
      insert into atlas.organization_receipt_occurrences(
        ledger_id,organization_id,financial_source_transaction_id,financial_inflow_allocation_id,evidence_record_id,
        received_on,received_at,gross_amount,currency,receipt_kind,counterparty_label,source_label,operational_purpose,
        created_by_principal_id,created_by_membership_id,metadata
      ) values(
        v_ledger_id,v_organization_id,v_tx.id,v_allocation_id,v_tx.evidence_record_id,
        v_tx.transaction_date,v_tx.posted_at,v_amount,v_tx.currency,v_receipt_kind,
        coalesce(v_tx.counterparty_label,v_tx.description),coalesce(v_source.display_label,v_source.provider_key),v_purpose,
        v_principal,v_membership,
        jsonb_build_object(
          'financialSourceTransactionId',v_tx.id,
          'financialInflowAllocationId',v_allocation_id,
          'connectedSourceId',v_tx.connected_source_id,
          'evidenceRecordId',v_tx.evidence_record_id,
          'receiptKindIsNotTaxTreatment',true
        )||v_item_metadata
      ) returning id into v_receipt_id;
    end if;
  end loop;

  v_after:=atlas.financial_inflow_allocation_snapshot_v1(v_tx.id);
  update atlas.financial_inflow_allocation_events set after_state=v_after where id=v_event.id;

  return jsonb_build_object(
    'contractVersion','replace_financial_credit_allocations_self_v1',
    'state','replaced',
    'eventId',v_event.id,
    'transactionId',v_tx.id,
    'afterState',v_after,
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceMutated',false,
      'commercialTruthCreated',false,
      'organizationReceiptCreatedOnlyForConfirmedOrganizationAllocation',true,
      'receiptKindIsNotTaxTreatment',true,
      'nonbusinessAllocationsDoNotCreateOrganizationReceipt',true
    )
  );
end;
$function$;

create or replace function atlas.organization_receipt_window_self_api_v1(
  p_ledger_id uuid,
  p_start_on date,
  p_end_on date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid Receipt date window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'schemaVersion','atlas_organization_receipt_window_v1',
    'ledgerId',p_ledger_id,
    'startOn',p_start_on,
    'endOn',p_end_on,
    'receipts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'receiptOccurrenceId',r.id,
        'organizationId',r.organization_id,
        'financialSourceTransactionId',r.financial_source_transaction_id,
        'financialInflowAllocationId',r.financial_inflow_allocation_id,
        'evidenceRecordId',r.evidence_record_id,
        'receivedOn',r.received_on,
        'receivedAt',r.received_at,
        'grossAmount',r.gross_amount,
        'currency',r.currency,
        'receiptKind',r.receipt_kind,
        'counterpartyLabel',r.counterparty_label,
        'sourceLabel',r.source_label,
        'operationalPurpose',r.operational_purpose,
        'metadata',r.metadata
      ) order by r.received_on desc,r.created_at desc,r.id)
      from atlas.organization_receipt_occurrences r
      where r.ledger_id=p_ledger_id
        and r.received_on between p_start_on and p_end_on
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'receiptIsCashRealityNotOrder',true,
      'receiptKindIsNotTaxTreatment',true
    )
  );
end;
$function$;

create or replace function atlas.financial_review_self_api_v1(p_start_on date,p_end_on date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_principal uuid:=atlas.current_principal_id_v1();
begin
  if auth.uid() is null or v_principal is null then raise exception 'Signed-in Principal required.' using errcode='42501'; end if;
  if p_start_on is null or p_end_on is null or p_end_on<p_start_on then raise exception 'Valid financial review window required.' using errcode='22023'; end if;

  return jsonb_build_object(
    'contractVersion','financial_review_self_v2',
    'startOn',p_start_on,
    'endOn',p_end_on,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'transactionId',t.id,
        'source',jsonb_build_object(
          'sourceId',s.id,
          'custodyKind',case when s.custodian_user_id is not null then 'human' else 'organization' end,
          'custodianOrganizationId',s.custodian_organization_id,
          'providerKey',s.provider_key,
          'providerAccountKey',s.provider_account_key,
          'displayLabel',s.display_label,
          'accountHint',s.account_hint,
          'capabilities',s.capabilities,
          'metadata',s.metadata
        ),
        'transactionDate',t.transaction_date,
        'postedAt',t.posted_at,
        'direction',t.direction,
        'amount',t.amount,
        'currency',t.currency,
        'description',t.description,
        'counterpartyLabel',t.counterparty_label,
        'sourceTransactionKind',t.source_transaction_kind,
        'truthState',t.truth_state,
        'evidenceRecordId',t.evidence_record_id,
        'confirmedTransferAmount',coalesce(x.transfer_amount,0),
        'commercialReconciliationAmount',coalesce(c.commercial_amount,0),
        'activeAllocationAmount',coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0),
        'resolutionState',case
          when coalesce(x.transfer_amount,0)+coalesce(c.commercial_amount,0)+coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0)=0 then 'unresolved'
          when coalesce(x.transfer_amount,0)+coalesce(c.commercial_amount,0)+coalesce(a.allocation_amount,0)+coalesce(i.allocation_amount,0)<t.amount then 'partial'
          else 'resolved' end,
        'transfers',coalesce(x.transfers,'[]'::jsonb),
        'commercialReconciliations',coalesce(c.reconciliations,'[]'::jsonb),
        'allocations',coalesce(a.allocations,'[]'::jsonb)||coalesce(i.allocations,'[]'::jsonb)
      ) order by t.transaction_date desc,t.id)
      from atlas.financial_source_transactions t
      join atlas.connected_sources s on s.id=t.connected_source_id
      left join lateral (
        select sum(r.amount) as transfer_amount,
               jsonb_agg(jsonb_build_object(
                 'reconciliationId',r.id,
                 'fromTransactionId',r.from_transaction_id,
                 'toTransactionId',r.to_transaction_id,
                 'amount',r.amount,
                 'currency',r.currency,
                 'transferKind',r.transfer_kind,
                 'state',r.reconciliation_state
               ) order by r.created_at,r.id) as transfers
        from atlas.financial_transfer_reconciliations r
        where r.reconciliation_state='confirmed' and (r.from_transaction_id=t.id or r.to_transaction_id=t.id)
      ) x on true
      left join lateral (
        select sum(r.amount) as commercial_amount,
               jsonb_agg(jsonb_build_object(
                 'reconciliationId',r.id,
                 'commercialPaymentEventId',r.commercial_payment_event_id,
                 'amount',r.amount,
                 'currency',r.currency,
                 'state',r.reconciliation_state
               ) order by r.created_at,r.id) as reconciliations
        from atlas.financial_commercial_reconciliations r
        where r.financial_source_transaction_id=t.id and r.reconciliation_state='confirmed'
      ) c on true
      left join lateral (
        select sum(fa.allocated_amount) as allocation_amount,
               jsonb_agg(jsonb_build_object(
                 'allocationId',fa.id,
                 'allocationKind',fa.allocation_kind,
                 'amount',fa.allocated_amount,
                 'subjectDomain',fa.subject_domain,
                 'subjectKind',fa.subject_kind,
                 'subjectId',fa.subject_id,
                 'targetLedgerId',fa.target_ledger_id,
                 'targetOrganizationId',fa.target_organization_id,
                 'operationalPurpose',fa.operational_purpose,
                 'promotedSpendOccurrenceId',fa.promoted_spend_occurrence_id
               ) order by fa.created_at,fa.id) as allocations
        from atlas.financial_transaction_allocations fa
        where fa.transaction_id=t.id and fa.allocation_state='active'
      ) a on true
      left join lateral (
        select sum(fi.allocated_amount) as allocation_amount,
               jsonb_agg(jsonb_build_object(
                 'allocationId',fi.id,
                 'allocationKind',fi.allocation_kind,
                 'amount',fi.allocated_amount,
                 'receiptKind',fi.receipt_kind,
                 'targetLedgerId',fi.target_ledger_id,
                 'targetOrganizationId',fi.target_organization_id,
                 'operationalPurpose',fi.operational_purpose,
                 'receiptOccurrenceId',ro.id
               ) order by fi.created_at,fi.id) as allocations
        from atlas.financial_inflow_allocations fi
        left join atlas.organization_receipt_occurrences ro on ro.financial_inflow_allocation_id=fi.id
        where fi.transaction_id=t.id and fi.allocation_state='active'
      ) i on true
      where t.transaction_date between p_start_on and p_end_on
        and atlas.financial_source_authorized_self_v1(t.connected_source_id)
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sourceCustodyIsNotPurpose',true,
      'transferIsNotExpenseOrIncome',true,
      'commercialReconciliationDoesNotDuplicateRevenue',true,
      'allocationRequiresHumanConfirmation',true,
      'organizationSpendPromotionIsSeparateFromSourceEvidence',true,
      'organizationReceiptIsNotCommercialOrderOrTaxTreatment',true
    )
  );
end;
$function$;

revoke all on function atlas.financial_assert_ledger_organization_routing_v1(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.financial_inflow_allocation_snapshot_v1(uuid) from public,anon,authenticated,service_role;
revoke all on function atlas.financial_commercial_collection_candidates_self_api_v1(date,date,integer) from public,anon,service_role;
revoke all on function atlas.confirm_financial_commercial_collection_self_api_v1(uuid,uuid,numeric,text,jsonb) from public,anon,service_role;
revoke all on function atlas.replace_financial_credit_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) from public,anon,service_role;
revoke all on function atlas.organization_receipt_window_self_api_v1(uuid,date,date) from public,anon,service_role;

grant execute on function atlas.financial_commercial_collection_candidates_self_api_v1(date,date,integer) to authenticated;
grant execute on function atlas.confirm_financial_commercial_collection_self_api_v1(uuid,uuid,numeric,text,jsonb) to authenticated;
grant execute on function atlas.replace_financial_credit_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) to authenticated;
grant execute on function atlas.organization_receipt_window_self_api_v1(uuid,date,date) to authenticated;

comment on table atlas.financial_commercial_reconciliations is
  'Human-confirmed settlement links between an observed source credit and commercial payment truth that already exists. Reconciliation does not create revenue.';
comment on table atlas.financial_inflow_allocations is
  'Human-confirmed meaning allocations for source credits not consumed by transfers or existing commercial truth.';
comment on table atlas.organization_receipt_occurrences is
  'Canonical cash-receipt facts for an Organization. Receipt kind describes why money arrived but does not establish a commercial order or tax treatment.';
comment on function atlas.confirm_financial_commercial_collection_self_api_v1(uuid,uuid,numeric,text,jsonb) is
  'Reconciles a source credit to an existing succeeded commercial payment event without creating or duplicating commercial truth.';
comment on function atlas.replace_financial_credit_allocations_self_api_v1(uuid,text,jsonb,text,jsonb) is
  'Principal-confirmed meaning for unresolved source credits. Organization allocations create Receipt truth, never a sales order or tax treatment.';
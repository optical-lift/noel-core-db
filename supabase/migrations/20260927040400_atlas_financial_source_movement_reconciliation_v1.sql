-- Atlas financial source movement reconciliation v1
--
-- Multiple source transactions can be evidence of one money movement. This layer answers only
-- the source-custody question "which rows are the same movement?" It does not decide why the
-- movement happened, whether it is income/expense, whether it settles an obligation, or how it
-- should be posted to accounting.
--
-- Examples:
--   personal checking -> personal savings
--   checking -> credit-card account payment
--   personal checking -> business checking owner funding
--   processor payout -> bank deposit
--
-- Economic meaning remains downstream in obligation/settlement and accounting interpretation.

create table if not exists atlas.financial_source_movement_matches (
  id uuid primary key default gen_random_uuid(),
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  match_key text not null,
  movement_on date not null,
  movement_amount numeric not null,
  currency text not null,
  match_state text not null default 'confirmed',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_source_movement_matches_key_nonempty check (btrim(match_key)<>''),
  constraint financial_source_movement_matches_amount_check check (movement_amount>0),
  constraint financial_source_movement_matches_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_source_movement_matches_state_check check (match_state in ('confirmed','voided')),
  constraint financial_source_movement_matches_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_movement_matches_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(created_by_principal_id,match_key)
);

create index if not exists financial_source_movement_matches_date_idx
  on atlas.financial_source_movement_matches(created_by_principal_id,movement_on,match_state,id);

create table if not exists atlas.financial_source_movement_match_members (
  id uuid primary key default gen_random_uuid(),
  movement_match_id uuid not null references atlas.financial_source_movement_matches(id) on delete restrict,
  financial_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  movement_role text not null,
  matched_amount numeric not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_source_movement_match_members_role_check check (movement_role in ('outflow','inflow')),
  constraint financial_source_movement_match_members_amount_check check (matched_amount>0),
  constraint financial_source_movement_match_members_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_movement_match_members_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(movement_match_id,financial_transaction_id)
);

create index if not exists financial_source_movement_match_members_transaction_idx
  on atlas.financial_source_movement_match_members(financial_transaction_id,movement_match_id);

alter table atlas.financial_source_movement_matches enable row level security;
alter table atlas.financial_source_movement_match_members enable row level security;
revoke all on table atlas.financial_source_movement_matches from public,anon,authenticated;
revoke all on table atlas.financial_source_movement_match_members from public,anon,authenticated;

create or replace function atlas.guard_financial_source_movement_match_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'Source movement matches are retained evidence history; void rather than delete.' using errcode='55000';
  end if;

  if old.created_by_principal_id is distinct from new.created_by_principal_id
     or old.match_key is distinct from new.match_key
     or old.movement_on is distinct from new.movement_on
     or old.movement_amount is distinct from new.movement_amount
     or old.currency is distinct from new.currency
     or old.created_by_user_id is distinct from new.created_by_user_id
     or old.provenance is distinct from new.provenance
     or old.metadata is distinct from new.metadata then
    raise exception 'Confirmed source movement identity is immutable; void and establish a new match to correct it.' using errcode='55000';
  end if;

  if old.match_state='voided' and new.match_state<>'voided' then
    raise exception 'Voided source movement match cannot be revived.' using errcode='55000';
  end if;
  if old.match_state='confirmed' and new.match_state not in ('confirmed','voided') then
    raise exception 'Unsupported source movement match transition.' using errcode='55000';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function atlas.guard_financial_source_movement_match_mutation_v1() from public,anon,authenticated;

drop trigger if exists financial_source_movement_matches_mutation_guard_v1 on atlas.financial_source_movement_matches;
create trigger financial_source_movement_matches_mutation_guard_v1
before update or delete on atlas.financial_source_movement_matches
for each row execute function atlas.guard_financial_source_movement_match_mutation_v1();

create or replace function atlas.prevent_financial_source_movement_member_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Source movement match members are append-only; void the parent match to correct them.' using errcode='55000';
end;
$$;
revoke all on function atlas.prevent_financial_source_movement_member_mutation_v1() from public,anon,authenticated;

drop trigger if exists financial_source_movement_match_members_immutable_v1 on atlas.financial_source_movement_match_members;
create trigger financial_source_movement_match_members_immutable_v1
before update or delete on atlas.financial_source_movement_match_members
for each row execute function atlas.prevent_financial_source_movement_member_mutation_v1();

-- Once a source row participates in a confirmed movement match, a provider refresh may not make
-- that reconciliation impossible. The source row can still refresh descriptions/observations and
-- even amount when the confirmed matched amount remains valid. Void the match before a conflicting
-- provider correction.
create or replace function atlas.guard_financial_source_transaction_reconciliation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_confirmed_matched numeric;
begin
  select coalesce(sum(member.matched_amount),0)
    into v_confirmed_matched
  from atlas.financial_source_movement_match_members member
  join atlas.financial_source_movement_matches movement
    on movement.id=member.movement_match_id
   and movement.match_state='confirmed'
  where member.financial_transaction_id=old.id;

  if v_confirmed_matched>0 then
    if new.transaction_state='voided' and old.transaction_state<>'voided' then
      raise exception 'Void source movement reconciliations before voiding a matched source transaction.' using errcode='55000';
    end if;
    if new.currency<>old.currency then
      raise exception 'A matched source transaction cannot change currency; void the reconciliation first.' using errcode='55000';
    end if;
    if v_confirmed_matched>abs(new.source_amount) then
      raise exception 'Provider refresh would reduce a source transaction below its confirmed reconciled amount.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_source_transaction_reconciliation_v1() from public,anon,authenticated;

drop trigger if exists financial_source_transactions_reconciliation_guard_v1 on atlas.financial_source_transactions;
create trigger financial_source_transactions_reconciliation_guard_v1
before update on atlas.financial_source_transactions
for each row execute function atlas.guard_financial_source_transaction_reconciliation_v1();

create or replace function atlas.reconcile_financial_source_movement_self_api_v1(
  p_match_key text,
  p_movement_on date,
  p_currency text,
  p_members jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_principal uuid;
  v_key text:=btrim(coalesce(p_match_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_outflow numeric;
  v_inflow numeric;
  v_match atlas.financial_source_movement_matches%rowtype;
  v_existing_members jsonb;
  v_requested_members jsonb;
  v_member jsonb;
  v_transaction_id uuid;
  v_role text;
  v_amount numeric;
  v_source_amount numeric;
  v_transaction_currency text;
  v_transaction_state text;
  v_connected_source_id uuid;
  v_already_matched numeric;
  v_inserted boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then raise exception 'Canonical Principal context required.' using errcode='42501'; end if;
  if v_key='' or p_movement_on is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Movement match key, date, and three-letter currency are required.' using errcode='22023';
  end if;
  if p_members is null or jsonb_typeof(p_members)<>'array' or jsonb_array_length(p_members)<2 then
    raise exception 'At least two source transaction members are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Movement provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  -- Normalize the request once for deterministic idempotency comparison.
  select jsonb_agg(
    jsonb_build_object(
      'financialTransactionId',(item->>'financialTransactionId')::uuid,
      'movementRole',lower(btrim(item->>'movementRole')),
      'matchedAmount',(item->>'matchedAmount')::numeric
    ) order by (item->>'financialTransactionId')::uuid
  ) into v_requested_members
  from jsonb_array_elements(p_members) item;

  if exists (
    select 1
    from jsonb_array_elements(p_members) item
    where nullif(btrim(item->>'financialTransactionId'),'') is null
       or nullif(btrim(item->>'movementRole'),'') is null
       or nullif(btrim(item->>'matchedAmount'),'') is null
       or lower(btrim(item->>'movementRole')) not in ('outflow','inflow')
       or (item->>'matchedAmount')::numeric<=0
  ) then
    raise exception 'Each movement member requires financialTransactionId, outflow/inflow role, and positive matchedAmount.' using errcode='22023';
  end if;

  if (select count(*) from jsonb_array_elements(p_members)) <>
     (select count(distinct (item->>'financialTransactionId')::uuid) from jsonb_array_elements(p_members) item) then
    raise exception 'A source transaction may appear only once in one movement match.' using errcode='22023';
  end if;

  select coalesce(sum((item->>'matchedAmount')::numeric),0) into v_outflow
  from jsonb_array_elements(p_members) item
  where lower(btrim(item->>'movementRole'))='outflow';
  select coalesce(sum((item->>'matchedAmount')::numeric),0) into v_inflow
  from jsonb_array_elements(p_members) item
  where lower(btrim(item->>'movementRole'))='inflow';

  if v_outflow<=0 or v_inflow<=0 or v_outflow<>v_inflow then
    raise exception 'Confirmed source movement must contain balanced outflow and inflow matched amounts.' using errcode='23514';
  end if;

  -- Serialize all source rows in deterministic UUID order before checking available capacity.
  perform 1
  from atlas.financial_source_transactions transaction
  where transaction.id in (
    select (item->>'financialTransactionId')::uuid from jsonb_array_elements(p_members) item
  )
  order by transaction.id
  for update;

  for v_member in select item from jsonb_array_elements(p_members) item loop
    v_transaction_id:=(v_member->>'financialTransactionId')::uuid;
    v_role:=lower(btrim(v_member->>'movementRole'));
    v_amount:=(v_member->>'matchedAmount')::numeric;

    select transaction.source_amount,transaction.currency,transaction.transaction_state,transaction.connected_source_id
      into v_source_amount,v_transaction_currency,v_transaction_state,v_connected_source_id
    from atlas.financial_source_transactions transaction
    where transaction.id=v_transaction_id;

    if v_connected_source_id is null then raise exception 'Source transaction not found.' using errcode='23503'; end if;
    if not atlas.financial_connected_source_authorized_self_v1(v_connected_source_id) then
      raise exception 'Authority over every reconciled financial source is required.' using errcode='42501';
    end if;
    if v_transaction_state<>'observed' then raise exception 'Only observed source transactions may be reconciled.' using errcode='23514'; end if;
    if v_transaction_currency<>v_currency then raise exception 'All movement members must share one currency.' using errcode='23514'; end if;
    if (v_role='outflow' and v_source_amount>=0) or (v_role='inflow' and v_source_amount<=0) then
      raise exception 'Movement role must agree with the normalized source amount sign.' using errcode='23514';
    end if;
    if v_amount>abs(v_source_amount) then raise exception 'Matched amount may not exceed its source transaction magnitude.' using errcode='23514'; end if;

    select coalesce(sum(member.matched_amount),0) into v_already_matched
    from atlas.financial_source_movement_match_members member
    join atlas.financial_source_movement_matches movement
      on movement.id=member.movement_match_id
     and movement.match_state='confirmed'
    where member.financial_transaction_id=v_transaction_id;

    if v_already_matched+v_amount>abs(v_source_amount) then
      raise exception 'Confirmed movement matches may not over-allocate a source transaction.' using errcode='23514';
    end if;
  end loop;

  select * into v_match
  from atlas.financial_source_movement_matches movement
  where movement.created_by_principal_id=v_principal and movement.match_key=v_key
  for update;

  if v_match.id is not null then
    select jsonb_agg(
      jsonb_build_object(
        'financialTransactionId',member.financial_transaction_id,
        'movementRole',member.movement_role,
        'matchedAmount',member.matched_amount
      ) order by member.financial_transaction_id
    ) into v_existing_members
    from atlas.financial_source_movement_match_members member
    where member.movement_match_id=v_match.id;

    if v_match.movement_on<>p_movement_on or v_match.currency<>v_currency or v_match.movement_amount<>v_outflow
       or v_match.match_state<>'confirmed' or coalesce(v_existing_members,'[]'::jsonb)<>coalesce(v_requested_members,'[]'::jsonb) then
      raise exception 'Movement match key already exists with different immutable source facts.' using errcode='23505';
    end if;
  else
    insert into atlas.financial_source_movement_matches(
      created_by_principal_id,match_key,movement_on,movement_amount,currency,match_state,
      provenance,metadata,created_by_user_id
    ) values (
      v_principal,v_key,p_movement_on,v_outflow,v_currency,'confirmed',
      p_provenance||jsonb_build_object(
        'authority','reconcile_financial_source_movement_self_api_v1',
        'economicMeaningEstablished',false,
        'obligationSettlementEstablished',false,
        'journalPosted',false
      ),p_metadata,auth.uid()
    ) returning * into v_match;
    v_inserted:=true;

    insert into atlas.financial_source_movement_match_members(
      movement_match_id,financial_transaction_id,movement_role,matched_amount,provenance
    )
    select v_match.id,
           (item->>'financialTransactionId')::uuid,
           lower(btrim(item->>'movementRole')),
           (item->>'matchedAmount')::numeric,
           jsonb_build_object('authority','reconcile_financial_source_movement_self_api_v1')
    from jsonb_array_elements(p_members) item;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_movement_match_v1',
    'movementMatchId',v_match.id,
    'created',v_inserted,
    'matchKey',v_match.match_key,
    'movementOn',v_match.movement_on,
    'movementAmount',v_match.movement_amount,
    'currency',v_match.currency,
    'matchState',v_match.match_state,
    'members',v_requested_members,
    'truthBoundary',jsonb_build_object(
      'sourceRowsMerged',false,
      'economicMeaningEstablished',false,
      'obligationSettlementEstablished',false,
      'accountingTreatmentEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;
revoke all on function atlas.reconcile_financial_source_movement_self_api_v1(text,date,text,jsonb,jsonb,jsonb) from public,anon;
grant execute on function atlas.reconcile_financial_source_movement_self_api_v1(text,date,text,jsonb,jsonb,jsonb) to authenticated;

create or replace function atlas.void_financial_source_movement_match_self_api_v1(
  p_movement_match_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_match atlas.financial_source_movement_matches%rowtype;
  v_connected_source_id uuid;
begin
  select * into v_match from atlas.financial_source_movement_matches where id=p_movement_match_id for update;
  if v_match.id is null then raise exception 'Source movement match not found.' using errcode='P0002'; end if;

  for v_connected_source_id in
    select distinct transaction.connected_source_id
    from atlas.financial_source_movement_match_members member
    join atlas.financial_source_transactions transaction on transaction.id=member.financial_transaction_id
    where member.movement_match_id=p_movement_match_id
  loop
    if not atlas.financial_connected_source_authorized_self_v1(v_connected_source_id) then
      raise exception 'Authority over every reconciled financial source is required.' using errcode='42501';
    end if;
  end loop;

  if v_match.match_state='confirmed' then
    update atlas.financial_source_movement_matches
    set match_state='voided'
    where id=p_movement_match_id
    returning * into v_match;
  end if;

  return jsonb_build_object(
    'contractVersion','financial_source_movement_match_void_v1',
    'movementMatchId',v_match.id,
    'matchState',v_match.match_state,
    'reason',nullif(btrim(coalesce(p_reason,'')),''),
    'truthBoundary',jsonb_build_object('sourceTransactionsChanged',false,'economicTruthChanged',false,'journalPosted',false)
  );
end;
$$;
revoke all on function atlas.void_financial_source_movement_match_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.void_financial_source_movement_match_self_api_v1(uuid,text) to authenticated;

create or replace function atlas.financial_source_movement_match_self_api_v1(p_movement_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_match atlas.financial_source_movement_matches%rowtype;
  v_connected_source_id uuid;
begin
  select * into v_match from atlas.financial_source_movement_matches where id=p_movement_match_id;
  if v_match.id is null then raise exception 'Source movement match not found.' using errcode='P0002'; end if;

  for v_connected_source_id in
    select distinct transaction.connected_source_id
    from atlas.financial_source_movement_match_members member
    join atlas.financial_source_transactions transaction on transaction.id=member.financial_transaction_id
    where member.movement_match_id=p_movement_match_id
  loop
    if not atlas.financial_connected_source_authorized_self_v1(v_connected_source_id) then
      raise exception 'Authority over every reconciled financial source is required.' using errcode='42501';
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','financial_source_movement_match_position_v1',
    'movementMatchId',v_match.id,
    'matchKey',v_match.match_key,
    'movementOn',v_match.movement_on,
    'movementAmount',v_match.movement_amount,
    'currency',v_match.currency,
    'matchState',v_match.match_state,
    'members',coalesce((
      select jsonb_agg(jsonb_build_object(
        'financialTransactionId',transaction.id,
        'connectedSourceId',transaction.connected_source_id,
        'occurredOn',transaction.occurred_on,
        'sourceAmount',transaction.source_amount,
        'currency',transaction.currency,
        'rawDescription',transaction.raw_description,
        'sourcePartyLabel',transaction.source_party_label,
        'movementRole',member.movement_role,
        'matchedAmount',member.matched_amount
      ) order by member.movement_role,transaction.occurred_on,transaction.id)
      from atlas.financial_source_movement_match_members member
      join atlas.financial_source_transactions transaction on transaction.id=member.financial_transaction_id
      where member.movement_match_id=v_match.id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'sameMovementEvidenceOnly',true,
      'economicMeaningEstablished',false,
      'journalPostingIsSeparate',true
    )
  );
end;
$$;
revoke all on function atlas.financial_source_movement_match_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_source_movement_match_self_api_v1(uuid) to authenticated;

create or replace function atlas.financial_source_transaction_movement_position_self_api_v1(p_financial_transaction_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
  v_matched numeric;
begin
  select * into v_transaction from atlas.financial_source_transactions where id=p_financial_transaction_id;
  if v_transaction.id is null then raise exception 'Financial source transaction not found.' using errcode='P0002'; end if;
  if not atlas.financial_connected_source_authorized_self_v1(v_transaction.connected_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;

  select coalesce(sum(member.matched_amount),0) into v_matched
  from atlas.financial_source_movement_match_members member
  join atlas.financial_source_movement_matches movement
    on movement.id=member.movement_match_id
   and movement.match_state='confirmed'
  where member.financial_transaction_id=p_financial_transaction_id;

  return jsonb_build_object(
    'contractVersion','financial_source_transaction_movement_position_v1',
    'financialTransactionId',v_transaction.id,
    'connectedSourceId',v_transaction.connected_source_id,
    'occurredOn',v_transaction.occurred_on,
    'sourceAmount',v_transaction.source_amount,
    'currency',v_transaction.currency,
    'confirmedMatchedAmount',v_matched,
    'unmatchedAmount',greatest(abs(v_transaction.source_amount)-v_matched,0),
    'matches',coalesce((
      select jsonb_agg(jsonb_build_object(
        'movementMatchId',movement.id,
        'matchKey',movement.match_key,
        'movementOn',movement.movement_on,
        'movementAmount',movement.movement_amount,
        'matchState',movement.match_state,
        'movementRole',member.movement_role,
        'matchedAmount',member.matched_amount
      ) order by movement.movement_on,movement.id)
      from atlas.financial_source_movement_match_members member
      join atlas.financial_source_movement_matches movement on movement.id=member.movement_match_id
      where member.financial_transaction_id=p_financial_transaction_id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'sourceTransactionPreserved',true,
      'movementReconciliationIsNotClassification',true,
      'settlementAndAccountingRemainDownstream',true
    )
  );
end;
$$;
revoke all on function atlas.financial_source_transaction_movement_position_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_source_transaction_movement_position_self_api_v1(uuid) to authenticated;

comment on table atlas.financial_source_movement_matches is
  'Reconciliation identity for multiple financial source rows that evidence one normalized money movement. It establishes source equivalence, not economic or accounting meaning.';
comment on table atlas.financial_source_movement_match_members is
  'Append-only source rows participating in one movement reconciliation. Outflow and inflow matched amounts must balance when established through the governed service.';
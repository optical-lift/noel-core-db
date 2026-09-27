-- Atlas account-centered financial transaction + statement intake v2
--
-- Extends the existing stable transaction/statement identities so they may be backed either
-- by externally authorized connected-source observations (v1) or by canonical financial
-- account evidence observations (v2). The v1 path remains intact for live connectors.

alter table atlas.financial_source_transactions
  add column if not exists financial_source_account_id uuid references atlas.financial_source_accounts(id) on delete restrict,
  add column if not exists first_financial_evidence_observation_id uuid references atlas.financial_source_evidence_observations(id) on delete restrict,
  add column if not exists current_financial_evidence_observation_id uuid references atlas.financial_source_evidence_observations(id) on delete restrict;

alter table atlas.financial_source_transactions
  alter column connected_source_id drop not null,
  alter column first_observation_id drop not null,
  alter column current_observation_id drop not null;

alter table atlas.financial_source_transactions
  add constraint financial_source_transactions_evidence_path_check
  check (
    (
      financial_source_account_id is not null
      and first_financial_evidence_observation_id is not null
      and current_financial_evidence_observation_id is not null
    )
    or (
      connected_source_id is not null
      and first_observation_id is not null
      and current_observation_id is not null
    )
  );

create unique index if not exists financial_source_transactions_account_key_uq
  on atlas.financial_source_transactions(financial_source_account_id,provider_transaction_key)
  where financial_source_account_id is not null;

create index if not exists financial_source_transactions_account_date_idx
  on atlas.financial_source_transactions(financial_source_account_id,occurred_on desc,id)
  where financial_source_account_id is not null;

create or replace function atlas.guard_financial_source_transaction_account_v2()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_first atlas.financial_source_evidence_observations%rowtype;
  v_current atlas.financial_source_evidence_observations%rowtype;
begin
  if new.financial_source_account_id is null then
    return new;
  end if;

  select * into v_first
  from atlas.financial_source_evidence_observations observation
  where observation.id=new.first_financial_evidence_observation_id;
  select * into v_current
  from atlas.financial_source_evidence_observations observation
  where observation.id=new.current_financial_evidence_observation_id;

  if v_first.id is null or v_current.id is null
     or v_first.financial_source_account_id<>new.financial_source_account_id
     or v_current.financial_source_account_id<>new.financial_source_account_id
     or v_first.observation_kind<>'financial_transaction'
     or v_current.observation_kind<>'financial_transaction'
     or v_first.source_object_key<>new.provider_transaction_key
     or v_current.source_object_key<>new.provider_transaction_key then
    raise exception 'Financial transaction evidence observations must match the stable financial account transaction identity.' using errcode='23514';
  end if;

  if tg_op='UPDATE' and (
    new.financial_source_account_id is distinct from old.financial_source_account_id
    or new.provider_transaction_key is distinct from old.provider_transaction_key
    or new.first_financial_evidence_observation_id is distinct from old.first_financial_evidence_observation_id
  ) then
    raise exception 'Financial account transaction identity and first evidence observation are immutable.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_financial_source_transaction_account_v2() from public,anon,authenticated;
drop trigger if exists financial_source_transactions_account_guard_v2 on atlas.financial_source_transactions;
create trigger financial_source_transactions_account_guard_v2
before insert or update on atlas.financial_source_transactions
for each row execute function atlas.guard_financial_source_transaction_account_v2();

create or replace function atlas.record_financial_source_transaction_service_v2(
  p_financial_source_account_id uuid,
  p_provider_transaction_key text,
  p_financial_evidence_observation_id uuid,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_source_amount numeric,
  p_currency text,
  p_raw_description text default null,
  p_source_party_label text default null,
  p_normalization_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_key text:=btrim(coalesce(p_provider_transaction_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_description text:=nullif(btrim(coalesce(p_raw_description,'')),'');
  v_party text:=nullif(btrim(coalesce(p_source_party_label,'')),'');
  v_evidence atlas.financial_source_evidence_observations%rowtype;
  v_existing atlas.financial_source_transactions%rowtype;
  v_transaction atlas.financial_source_transactions%rowtype;
  v_state text;
begin
  if p_financial_source_account_id is null or p_financial_evidence_observation_id is null
     or v_key='' or p_occurred_on is null or p_source_amount is null or p_source_amount=0
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Financial account, evidence observation, transaction key, date, nonzero amount, and three-letter currency are required.' using errcode='22023';
  end if;
  if p_normalization_provenance is null or jsonb_typeof(p_normalization_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Normalization provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.financial_source_accounts account
    where account.id=p_financial_source_account_id and account.source_state='active'
  ) then
    raise exception 'Active financial source account required.' using errcode='23503';
  end if;

  select * into v_evidence
  from atlas.financial_source_evidence_observations observation
  where observation.id=p_financial_evidence_observation_id
    and observation.financial_source_account_id=p_financial_source_account_id
    and observation.observation_kind='financial_transaction'
    and observation.source_object_key=v_key;
  if v_evidence.id is null then
    raise exception 'Financial transaction evidence observation does not match the account and stable transaction key.' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_source_transaction_v2:'||p_financial_source_account_id::text||':'||v_key,0
  ));

  select * into v_existing
  from atlas.financial_source_transactions transaction
  where transaction.financial_source_account_id=p_financial_source_account_id
    and transaction.provider_transaction_key=v_key
  for update;

  if v_existing.id is null then
    insert into atlas.financial_source_transactions(
      connected_source_id,provider_transaction_key,first_observation_id,current_observation_id,
      financial_source_account_id,first_financial_evidence_observation_id,current_financial_evidence_observation_id,
      occurred_on,occurred_at,source_amount,currency,raw_description,source_party_label,
      normalization_provenance,metadata
    ) values (
      null,v_key,null,null,
      p_financial_source_account_id,p_financial_evidence_observation_id,p_financial_evidence_observation_id,
      p_occurred_on,p_occurred_at,p_source_amount,v_currency,v_description,v_party,
      p_normalization_provenance,p_metadata
    ) returning * into v_transaction;
    v_state:='admitted';
  else
    if v_existing.current_financial_evidence_observation_id=p_financial_evidence_observation_id
       and v_existing.occurred_on=p_occurred_on
       and v_existing.occurred_at is not distinct from p_occurred_at
       and v_existing.source_amount=p_source_amount
       and v_existing.currency=v_currency
       and v_existing.raw_description is not distinct from v_description
       and v_existing.source_party_label is not distinct from v_party then
      return jsonb_build_object(
        'contractVersion','record_financial_source_transaction_service_v2',
        'state','unchanged',
        'financialTransactionId',v_existing.id,
        'financialSourceAccountId',v_existing.financial_source_account_id,
        'currentFinancialEvidenceObservationId',v_existing.current_financial_evidence_observation_id
      );
    end if;

    update atlas.financial_source_transactions transaction
    set current_financial_evidence_observation_id=p_financial_evidence_observation_id,
        occurred_on=p_occurred_on,
        occurred_at=p_occurred_at,
        source_amount=p_source_amount,
        currency=v_currency,
        raw_description=v_description,
        source_party_label=v_party,
        normalization_provenance=p_normalization_provenance,
        metadata=transaction.metadata||p_metadata,
        updated_at=now()
    where transaction.id=v_existing.id
    returning * into v_transaction;
    v_state:='refreshed';
  end if;

  return jsonb_build_object(
    'contractVersion','record_financial_source_transaction_service_v2',
    'state',v_state,
    'financialTransactionId',v_transaction.id,
    'financialSourceAccountId',v_transaction.financial_source_account_id,
    'firstFinancialEvidenceObservationId',v_transaction.first_financial_evidence_observation_id,
    'currentFinancialEvidenceObservationId',v_transaction.current_financial_evidence_observation_id,
    'sourceAmount',v_transaction.source_amount,
    'currency',v_transaction.currency
  );
end;
$$;

revoke all on function atlas.record_financial_source_transaction_service_v2(
  uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_transaction_service_v2(
  uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb
) to service_role;

-- Statement identity gains the same account-centered evidence path.
alter table atlas.financial_source_statements
  add column if not exists financial_source_account_id uuid references atlas.financial_source_accounts(id) on delete restrict,
  add column if not exists first_financial_evidence_observation_id uuid references atlas.financial_source_evidence_observations(id) on delete restrict,
  add column if not exists current_financial_evidence_observation_id uuid references atlas.financial_source_evidence_observations(id) on delete restrict;

alter table atlas.financial_source_statements
  alter column connected_source_id drop not null,
  alter column first_observation_id drop not null,
  alter column current_observation_id drop not null;

alter table atlas.financial_source_statements
  add constraint financial_source_statements_evidence_path_check
  check (
    (
      financial_source_account_id is not null
      and first_financial_evidence_observation_id is not null
      and current_financial_evidence_observation_id is not null
    )
    or (
      connected_source_id is not null
      and first_observation_id is not null
      and current_observation_id is not null
    )
  );

create unique index if not exists financial_source_statements_account_key_uq
  on atlas.financial_source_statements(financial_source_account_id,provider_statement_key)
  where financial_source_account_id is not null;
create index if not exists financial_source_statements_account_period_idx
  on atlas.financial_source_statements(financial_source_account_id,period_start_on,period_end_on,id)
  where financial_source_account_id is not null;

create or replace function atlas.guard_financial_source_statement_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_first_source_id uuid;
  v_first_kind text;
  v_first_key text;
  v_current_source_id uuid;
  v_current_kind text;
  v_current_key text;
  v_first_evidence atlas.financial_source_evidence_observations%rowtype;
  v_current_evidence atlas.financial_source_evidence_observations%rowtype;
begin
  if new.financial_source_account_id is not null then
    select * into v_first_evidence
    from atlas.financial_source_evidence_observations observation
    where observation.id=new.first_financial_evidence_observation_id;
    select * into v_current_evidence
    from atlas.financial_source_evidence_observations observation
    where observation.id=new.current_financial_evidence_observation_id;

    if v_first_evidence.id is null or v_current_evidence.id is null
       or v_first_evidence.financial_source_account_id<>new.financial_source_account_id
       or v_current_evidence.financial_source_account_id<>new.financial_source_account_id
       or v_first_evidence.observation_kind<>'financial_statement'
       or v_current_evidence.observation_kind<>'financial_statement'
       or v_first_evidence.source_object_key<>new.provider_statement_key
       or v_current_evidence.source_object_key<>new.provider_statement_key then
      raise exception 'Financial statement evidence observations must match the stable financial account statement identity.' using errcode='23514';
    end if;

    if tg_op='UPDATE' and (
      new.financial_source_account_id is distinct from old.financial_source_account_id
      or new.provider_statement_key is distinct from old.provider_statement_key
      or new.first_financial_evidence_observation_id is distinct from old.first_financial_evidence_observation_id
    ) then
      raise exception 'Financial account statement identity and first evidence observation are immutable.' using errcode='23514';
    end if;

    new.updated_at:=now();
    return new;
  end if;

  select observation.connected_source_id,observation.provider_object_kind,observation.provider_object_key
  into v_first_source_id,v_first_kind,v_first_key
  from atlas.connected_source_observations observation
  where observation.id=new.first_observation_id;
  select observation.connected_source_id,observation.provider_object_kind,observation.provider_object_key
  into v_current_source_id,v_current_kind,v_current_key
  from atlas.connected_source_observations observation
  where observation.id=new.current_observation_id;

  if v_first_source_id is null or v_current_source_id is null
     or v_first_source_id<>new.connected_source_id
     or v_current_source_id<>new.connected_source_id
     or v_first_kind<>'financial_statement'
     or v_current_kind<>'financial_statement'
     or v_first_key<>new.provider_statement_key
     or v_current_key<>new.provider_statement_key then
    raise exception 'Financial statement observations must match the stable connected-source statement identity.' using errcode='23514';
  end if;

  if tg_op='UPDATE' and (
    new.connected_source_id is distinct from old.connected_source_id
    or new.provider_statement_key is distinct from old.provider_statement_key
    or new.first_observation_id is distinct from old.first_observation_id
  ) then
    raise exception 'Connected-source financial statement identity and first observation are immutable.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

create or replace function atlas.record_financial_source_statement_service_v2(
  p_financial_source_account_id uuid,
  p_provider_statement_key text,
  p_financial_evidence_observation_id uuid,
  p_period_start_on date,
  p_period_end_on date,
  p_currency text,
  p_opening_balance numeric default null,
  p_closing_balance numeric default null,
  p_reported_inflow_total numeric default null,
  p_reported_outflow_total numeric default null,
  p_reported_inflow_count integer default null,
  p_reported_outflow_count integer default null,
  p_reported_transaction_count integer default null,
  p_balance_check_kind text default 'none',
  p_normalization_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_key text:=btrim(coalesce(p_provider_statement_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_balance_kind text:=lower(btrim(coalesce(p_balance_check_kind,'none')));
  v_evidence atlas.financial_source_evidence_observations%rowtype;
  v_existing atlas.financial_source_statements%rowtype;
  v_statement atlas.financial_source_statements%rowtype;
  v_state text;
begin
  if p_financial_source_account_id is null or p_financial_evidence_observation_id is null
     or v_key='' or p_period_start_on is null or p_period_end_on is null or p_period_end_on<p_period_start_on
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Financial account, evidence observation, statement key, valid period, and three-letter currency are required.' using errcode='22023';
  end if;
  if v_balance_kind not in ('none','source_amount_delta') then
    raise exception 'Unsupported financial statement balance check kind.' using errcode='22023';
  end if;
  if v_balance_kind='source_amount_delta' and (p_opening_balance is null or p_closing_balance is null) then
    raise exception 'Source-amount balance reconciliation requires opening and closing balances.' using errcode='22023';
  end if;
  if p_reported_inflow_total<0 or p_reported_outflow_total<0
     or p_reported_inflow_count<0 or p_reported_outflow_count<0 or p_reported_transaction_count<0 then
    raise exception 'Reported financial statement totals and counts may not be negative.' using errcode='22023';
  end if;
  if p_normalization_provenance is null or jsonb_typeof(p_normalization_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Statement normalization provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_evidence
  from atlas.financial_source_evidence_observations observation
  where observation.id=p_financial_evidence_observation_id
    and observation.financial_source_account_id=p_financial_source_account_id
    and observation.observation_kind='financial_statement'
    and observation.source_object_key=v_key;
  if v_evidence.id is null then
    raise exception 'Financial statement evidence observation does not match the account and stable statement key.' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_source_statement_v2:'||p_financial_source_account_id::text||':'||v_key,0
  ));

  select * into v_existing
  from atlas.financial_source_statements statement
  where statement.financial_source_account_id=p_financial_source_account_id
    and statement.provider_statement_key=v_key
  for update;

  if v_existing.id is null then
    insert into atlas.financial_source_statements(
      connected_source_id,provider_statement_key,first_observation_id,current_observation_id,
      financial_source_account_id,first_financial_evidence_observation_id,current_financial_evidence_observation_id,
      period_start_on,period_end_on,currency,opening_balance,closing_balance,
      reported_inflow_total,reported_outflow_total,reported_inflow_count,reported_outflow_count,
      reported_transaction_count,balance_check_kind,normalization_provenance,metadata
    ) values (
      null,v_key,null,null,
      p_financial_source_account_id,p_financial_evidence_observation_id,p_financial_evidence_observation_id,
      p_period_start_on,p_period_end_on,v_currency,p_opening_balance,p_closing_balance,
      p_reported_inflow_total,p_reported_outflow_total,p_reported_inflow_count,p_reported_outflow_count,
      p_reported_transaction_count,v_balance_kind,p_normalization_provenance,p_metadata
    ) returning * into v_statement;
    v_state:='admitted';
  else
    if v_existing.current_financial_evidence_observation_id=p_financial_evidence_observation_id
       and v_existing.period_start_on=p_period_start_on
       and v_existing.period_end_on=p_period_end_on
       and v_existing.currency=v_currency
       and v_existing.opening_balance is not distinct from p_opening_balance
       and v_existing.closing_balance is not distinct from p_closing_balance
       and v_existing.reported_inflow_total is not distinct from p_reported_inflow_total
       and v_existing.reported_outflow_total is not distinct from p_reported_outflow_total
       and v_existing.reported_inflow_count is not distinct from p_reported_inflow_count
       and v_existing.reported_outflow_count is not distinct from p_reported_outflow_count
       and v_existing.reported_transaction_count is not distinct from p_reported_transaction_count
       and v_existing.balance_check_kind=v_balance_kind then
      return jsonb_build_object(
        'contractVersion','record_financial_source_statement_service_v2',
        'state','unchanged','statementId',v_existing.id,
        'financialSourceAccountId',v_existing.financial_source_account_id,
        'currentFinancialEvidenceObservationId',v_existing.current_financial_evidence_observation_id
      );
    end if;

    update atlas.financial_source_statements statement
    set current_financial_evidence_observation_id=p_financial_evidence_observation_id,
        period_start_on=p_period_start_on,
        period_end_on=p_period_end_on,
        currency=v_currency,
        opening_balance=p_opening_balance,
        closing_balance=p_closing_balance,
        reported_inflow_total=p_reported_inflow_total,
        reported_outflow_total=p_reported_outflow_total,
        reported_inflow_count=p_reported_inflow_count,
        reported_outflow_count=p_reported_outflow_count,
        reported_transaction_count=p_reported_transaction_count,
        balance_check_kind=v_balance_kind,
        normalization_provenance=p_normalization_provenance,
        metadata=statement.metadata||p_metadata,
        updated_at=now()
    where statement.id=v_existing.id
    returning * into v_statement;
    v_state:='refreshed';
  end if;

  return jsonb_build_object(
    'contractVersion','record_financial_source_statement_service_v2',
    'state',v_state,'statementId',v_statement.id,
    'financialSourceAccountId',v_statement.financial_source_account_id,
    'firstFinancialEvidenceObservationId',v_statement.first_financial_evidence_observation_id,
    'currentFinancialEvidenceObservationId',v_statement.current_financial_evidence_observation_id,
    'periodStartOn',v_statement.period_start_on,'periodEndOn',v_statement.period_end_on,
    'currency',v_statement.currency
  );
end;
$$;

revoke all on function atlas.record_financial_source_statement_service_v2(
  uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_statement_service_v2(
  uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) to service_role;

alter table atlas.financial_source_statement_transaction_links
  add column if not exists statement_evidence_observation_id uuid references atlas.financial_source_evidence_observations(id) on delete restrict;
alter table atlas.financial_source_statement_transaction_links
  alter column statement_observation_id drop not null;
alter table atlas.financial_source_statement_transaction_links
  add constraint financial_source_statement_links_evidence_path_check
  check (statement_observation_id is not null or statement_evidence_observation_id is not null);

create unique index if not exists financial_source_statement_links_account_observation_uq
  on atlas.financial_source_statement_transaction_links(statement_id,statement_evidence_observation_id,financial_transaction_id)
  where statement_evidence_observation_id is not null;

create or replace function atlas.guard_financial_source_statement_transaction_link_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_statement atlas.financial_source_statements%rowtype;
  v_evidence atlas.financial_source_evidence_observations%rowtype;
  v_transaction atlas.financial_source_transactions%rowtype;
  v_observation_source_id uuid;
  v_observation_kind text;
begin
  select * into v_statement from atlas.financial_source_statements where id=new.statement_id;
  select * into v_transaction from atlas.financial_source_transactions where id=new.financial_transaction_id;

  if new.statement_evidence_observation_id is not null then
    select * into v_evidence
    from atlas.financial_source_evidence_observations
    where id=new.statement_evidence_observation_id;

    if v_statement.id is null or v_transaction.id is null or v_evidence.id is null
       or v_statement.financial_source_account_id is null
       or v_transaction.financial_source_account_id<>v_statement.financial_source_account_id
       or v_evidence.financial_source_account_id<>v_statement.financial_source_account_id
       or v_evidence.observation_kind<>'financial_statement'
       or new.statement_evidence_observation_id<>v_statement.current_financial_evidence_observation_id then
      raise exception 'Account-centered statement transaction link must remain within one financial account and current statement evidence observation.' using errcode='23514';
    end if;
    return new;
  end if;

  select observation.connected_source_id,observation.provider_object_kind
  into v_observation_source_id,v_observation_kind
  from atlas.connected_source_observations observation
  where observation.id=new.statement_observation_id;

  if v_statement.id is null or v_transaction.id is null or v_observation_source_id is null
     or v_observation_kind<>'financial_statement'
     or v_statement.connected_source_id<>v_observation_source_id
     or v_transaction.connected_source_id<>v_statement.connected_source_id
     or new.statement_observation_id<>v_statement.current_observation_id then
    raise exception 'Connected-source statement transaction link must remain within one source and current statement observation.' using errcode='23514';
  end if;
  return new;
end;
$$;

create or replace function atlas.link_financial_source_statement_transactions_service_v2(
  p_statement_id uuid,
  p_statement_evidence_observation_id uuid,
  p_provider_transaction_keys text[],
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_statement atlas.financial_source_statements%rowtype;
  v_requested_count integer;
  v_distinct_count integer;
  v_found_count integer;
  v_inserted_count integer:=0;
begin
  if p_statement_id is null or p_statement_evidence_observation_id is null
     or p_provider_transaction_keys is null or coalesce(array_length(p_provider_transaction_keys,1),0)=0 then
    raise exception 'Statement, statement evidence observation, and transaction keys are required.' using errcode='22023';
  end if;
  if array_length(p_provider_transaction_keys,1)>2000 then
    raise exception 'A statement may link at most 2000 transaction keys in one call.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Statement-link provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  select * into v_statement
  from atlas.financial_source_statements statement
  where statement.id=p_statement_id
  for update;
  if v_statement.id is null or v_statement.financial_source_account_id is null then
    raise exception 'Account-centered financial source statement not found.' using errcode='23503';
  end if;
  if v_statement.current_financial_evidence_observation_id<>p_statement_evidence_observation_id then
    raise exception 'Transaction links must target the current statement evidence observation.' using errcode='23514';
  end if;

  select count(*),count(distinct btrim(key))
  into v_requested_count,v_distinct_count
  from unnest(p_provider_transaction_keys) as keys(key);
  if v_requested_count<>v_distinct_count
     or exists(select 1 from unnest(p_provider_transaction_keys) as keys(key) where nullif(btrim(key),'') is null) then
    raise exception 'Transaction keys must be nonempty and unique within a statement link batch.' using errcode='22023';
  end if;

  select count(*)::integer into v_found_count
  from atlas.financial_source_transactions transaction
  where transaction.financial_source_account_id=v_statement.financial_source_account_id
    and transaction.provider_transaction_key=any(p_provider_transaction_keys);
  if v_found_count<>v_requested_count then
    raise exception 'Every statement transaction key must already exist on the same financial account.' using errcode='23503';
  end if;

  insert into atlas.financial_source_statement_transaction_links(
    statement_id,statement_observation_id,statement_evidence_observation_id,
    financial_transaction_id,provenance,metadata
  )
  select v_statement.id,null,p_statement_evidence_observation_id,transaction.id,
    p_provenance||jsonb_build_object(
      'authority','link_financial_source_statement_transactions_service_v2',
      'providerTransactionKey',transaction.provider_transaction_key
    ),p_metadata
  from atlas.financial_source_transactions transaction
  where transaction.financial_source_account_id=v_statement.financial_source_account_id
    and transaction.provider_transaction_key=any(p_provider_transaction_keys)
  on conflict do nothing;
  get diagnostics v_inserted_count=row_count;

  return jsonb_build_object(
    'contractVersion','link_financial_source_statement_transactions_service_v2',
    'statementId',v_statement.id,
    'statementEvidenceObservationId',p_statement_evidence_observation_id,
    'requestedCount',v_requested_count,'insertedCount',v_inserted_count,
    'unchangedCount',v_requested_count-v_inserted_count
  );
end;
$$;

revoke all on function atlas.link_financial_source_statement_transactions_service_v2(uuid,uuid,text[],jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.link_financial_source_statement_transactions_service_v2(uuid,uuid,text[],jsonb,jsonb)
  to service_role;

create or replace function atlas.financial_source_statement_reconciliation_core_v2(p_statement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_statement atlas.financial_source_statements%rowtype;
  v_linked_count integer:=0;
  v_inflow_count integer:=0;
  v_outflow_count integer:=0;
  v_inflow_total numeric:=0;
  v_outflow_total numeric:=0;
  v_net_source_amount numeric:=0;
  v_configured_checks integer:=0;
  v_failed_checks integer:=0;
  v_count_match boolean;
  v_inflow_count_match boolean;
  v_outflow_count_match boolean;
  v_inflow_total_match boolean;
  v_outflow_total_match boolean;
  v_balance_match boolean;
  v_state text;
begin
  select * into v_statement
  from atlas.financial_source_statements statement
  where statement.id=p_statement_id
    and statement.financial_source_account_id is not null;
  if v_statement.id is null then
    raise exception 'Account-centered financial source statement not found.' using errcode='23503';
  end if;

  select count(*)::integer,
         count(*) filter(where transaction.source_amount>0)::integer,
         count(*) filter(where transaction.source_amount<0)::integer,
         coalesce(sum(transaction.source_amount) filter(where transaction.source_amount>0),0),
         coalesce(sum(abs(transaction.source_amount)) filter(where transaction.source_amount<0),0),
         coalesce(sum(transaction.source_amount),0)
  into v_linked_count,v_inflow_count,v_outflow_count,v_inflow_total,v_outflow_total,v_net_source_amount
  from atlas.financial_source_statement_transaction_links link
  join atlas.financial_source_transactions transaction on transaction.id=link.financial_transaction_id
  where link.statement_id=v_statement.id
    and link.statement_evidence_observation_id=v_statement.current_financial_evidence_observation_id;

  if v_statement.reported_transaction_count is not null then
    v_configured_checks:=v_configured_checks+1;
    v_count_match:=v_linked_count=v_statement.reported_transaction_count;
    if not v_count_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;
  if v_statement.reported_inflow_count is not null then
    v_configured_checks:=v_configured_checks+1;
    v_inflow_count_match:=v_inflow_count=v_statement.reported_inflow_count;
    if not v_inflow_count_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;
  if v_statement.reported_outflow_count is not null then
    v_configured_checks:=v_configured_checks+1;
    v_outflow_count_match:=v_outflow_count=v_statement.reported_outflow_count;
    if not v_outflow_count_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;
  if v_statement.reported_inflow_total is not null then
    v_configured_checks:=v_configured_checks+1;
    v_inflow_total_match:=v_inflow_total=v_statement.reported_inflow_total;
    if not v_inflow_total_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;
  if v_statement.reported_outflow_total is not null then
    v_configured_checks:=v_configured_checks+1;
    v_outflow_total_match:=v_outflow_total=v_statement.reported_outflow_total;
    if not v_outflow_total_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;
  if v_statement.balance_check_kind='source_amount_delta' then
    v_configured_checks:=v_configured_checks+1;
    v_balance_match=(v_statement.opening_balance+v_net_source_amount)=v_statement.closing_balance;
    if not v_balance_match then v_failed_checks:=v_failed_checks+1; end if;
  end if;

  v_state:=case
    when v_configured_checks=0 then 'unverifiable'
    when v_failed_checks=0 then 'reconciled'
    else 'open'
  end;

  return jsonb_build_object(
    'contractVersion','financial_source_statement_reconciliation_core_v2',
    'statementId',v_statement.id,
    'financialSourceAccountId',v_statement.financial_source_account_id,
    'currentFinancialEvidenceObservationId',v_statement.current_financial_evidence_observation_id,
    'state',v_state,
    'configuredCheckCount',v_configured_checks,'failedCheckCount',v_failed_checks,
    'actual',jsonb_build_object(
      'transactionCount',v_linked_count,'inflowCount',v_inflow_count,'outflowCount',v_outflow_count,
      'inflowTotal',v_inflow_total,'outflowTotal',v_outflow_total,'netSourceAmount',v_net_source_amount
    ),
    'expected',jsonb_strip_nulls(jsonb_build_object(
      'transactionCount',v_statement.reported_transaction_count,
      'inflowCount',v_statement.reported_inflow_count,'outflowCount',v_statement.reported_outflow_count,
      'inflowTotal',v_statement.reported_inflow_total,'outflowTotal',v_statement.reported_outflow_total,
      'openingBalance',v_statement.opening_balance,'closingBalance',v_statement.closing_balance,
      'balanceCheckKind',v_statement.balance_check_kind
    )),
    'checks',jsonb_strip_nulls(jsonb_build_object(
      'transactionCount',v_count_match,'inflowCount',v_inflow_count_match,'outflowCount',v_outflow_count_match,
      'inflowTotal',v_inflow_total_match,'outflowTotal',v_outflow_total_match,'balance',v_balance_match
    )),
    'truthBoundary',jsonb_build_object(
      'reconciledMeansExtractionCompleteNotBookkeepingClassified',true,
      'bookkeepingInterpretationCreated',false
    )
  );
end;
$$;

revoke all on function atlas.financial_source_statement_reconciliation_core_v2(uuid)
  from public,anon,authenticated,service_role;

create or replace function atlas.financial_source_statement_reconciliation_self_api_v2(p_statement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_account_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  select statement.financial_source_account_id into v_account_id
  from atlas.financial_source_statements statement
  where statement.id=p_statement_id;
  if v_account_id is null then
    raise exception 'Account-centered financial source statement not found.' using errcode='23503';
  end if;
  if not atlas.financial_source_account_authorized_self_v2(v_account_id) then
    raise exception 'Financial source account authority required.' using errcode='42501';
  end if;
  return atlas.financial_source_statement_reconciliation_core_v2(p_statement_id);
end;
$$;

revoke all on function atlas.financial_source_statement_reconciliation_self_api_v2(uuid) from public,anon;
grant execute on function atlas.financial_source_statement_reconciliation_self_api_v2(uuid) to authenticated;

comment on function atlas.record_financial_source_transaction_service_v2(uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb) is
  'Admits or refreshes a stable financial transaction under a canonical financial source account using universal financial evidence observations; no connector authorization is required.';
comment on function atlas.record_financial_source_statement_service_v2(uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb) is
  'Admits or refreshes a stable financial statement under a canonical financial source account using universal financial evidence observations.';
comment on function atlas.financial_source_statement_reconciliation_self_api_v2(uuid) is
  'Shows whether the current account-centered statement extraction reconciles to statement-reported facts. Reconciliation does not classify transactions.';

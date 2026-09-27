-- Financial source statement reconciliation v1
--
-- A transaction list is not complete bookkeeping evidence merely because rows were parsed.
-- This layer preserves one stable statement identity over versioned raw source observations,
-- records which stable transactions were extracted from each exact statement observation,
-- and computes whether the current extraction reconciles to the statement-reported totals.
--
-- The model is provider-neutral. Balance math is opt-in because not every account type uses
-- the same balance orientation. `source_amount_delta` is appropriate only where the normalized
-- signed source amounts are expected to explain closing_balance - opening_balance directly.

create table if not exists atlas.financial_source_statements (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_statement_key text not null,
  first_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  current_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  period_start_on date not null,
  period_end_on date not null,
  currency text not null,
  opening_balance numeric,
  closing_balance numeric,
  reported_inflow_total numeric,
  reported_outflow_total numeric,
  reported_inflow_count integer,
  reported_outflow_count integer,
  reported_transaction_count integer,
  balance_check_kind text not null default 'none',
  normalization_provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_source_statements_key_nonempty check (btrim(provider_statement_key)<>''),
  constraint financial_source_statements_period_check check (period_end_on>=period_start_on),
  constraint financial_source_statements_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_source_statements_inflow_total_check check (reported_inflow_total is null or reported_inflow_total>=0),
  constraint financial_source_statements_outflow_total_check check (reported_outflow_total is null or reported_outflow_total>=0),
  constraint financial_source_statements_inflow_count_check check (reported_inflow_count is null or reported_inflow_count>=0),
  constraint financial_source_statements_outflow_count_check check (reported_outflow_count is null or reported_outflow_count>=0),
  constraint financial_source_statements_transaction_count_check check (reported_transaction_count is null or reported_transaction_count>=0),
  constraint financial_source_statements_balance_kind_check check (balance_check_kind in ('none','source_amount_delta')),
  constraint financial_source_statements_balance_fields_check check (
    balance_check_kind<>'source_amount_delta' or (opening_balance is not null and closing_balance is not null)
  ),
  constraint financial_source_statements_provenance_object check (jsonb_typeof(normalization_provenance)='object'),
  constraint financial_source_statements_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(connected_source_id,provider_statement_key)
);

create index if not exists financial_source_statements_source_period_idx
  on atlas.financial_source_statements(connected_source_id,period_start_on,period_end_on,id);

create table if not exists atlas.financial_source_statement_transaction_links (
  id uuid primary key default gen_random_uuid(),
  statement_id uuid not null references atlas.financial_source_statements(id) on delete restrict,
  statement_observation_id uuid not null references atlas.connected_source_observations(id) on delete restrict,
  financial_transaction_id uuid not null references atlas.financial_source_transactions(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  linked_at timestamptz not null default now(),
  constraint financial_source_statement_links_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_source_statement_links_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(statement_id,statement_observation_id,financial_transaction_id)
);

create index if not exists financial_source_statement_links_current_idx
  on atlas.financial_source_statement_transaction_links(statement_id,statement_observation_id,financial_transaction_id);
create index if not exists financial_source_statement_links_transaction_idx
  on atlas.financial_source_statement_transaction_links(financial_transaction_id,statement_id);

alter table atlas.financial_source_statements enable row level security;
alter table atlas.financial_source_statement_transaction_links enable row level security;
revoke all on table atlas.financial_source_statements from public,anon,authenticated;
revoke all on table atlas.financial_source_statement_transaction_links from public,anon,authenticated;

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
begin
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
    raise exception 'Financial source statement identity and first observation are immutable.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_financial_source_statement_v1() from public,anon,authenticated;
drop trigger if exists financial_source_statements_guard_v1 on atlas.financial_source_statements;
create trigger financial_source_statements_guard_v1
before insert or update on atlas.financial_source_statements
for each row execute function atlas.guard_financial_source_statement_v1();

create or replace function atlas.guard_financial_source_statement_transaction_link_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_statement_source_id uuid;
  v_current_observation_id uuid;
  v_observation_source_id uuid;
  v_observation_kind text;
  v_transaction_source_id uuid;
begin
  select statement.connected_source_id,statement.current_observation_id
  into v_statement_source_id,v_current_observation_id
  from atlas.financial_source_statements statement
  where statement.id=new.statement_id;

  select observation.connected_source_id,observation.provider_object_kind
  into v_observation_source_id,v_observation_kind
  from atlas.connected_source_observations observation
  where observation.id=new.statement_observation_id;

  select transaction.connected_source_id
  into v_transaction_source_id
  from atlas.financial_source_transactions transaction
  where transaction.id=new.financial_transaction_id;

  if v_statement_source_id is null or v_transaction_source_id is null
     or v_observation_source_id is null or v_observation_kind<>'financial_statement'
     or v_statement_source_id<>v_observation_source_id
     or v_statement_source_id<>v_transaction_source_id then
    raise exception 'Statement transaction link must remain within one connected financial source.' using errcode='23514';
  end if;
  if new.statement_observation_id<>v_current_observation_id then
    raise exception 'New statement transaction links must target the statement current observation.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_financial_source_statement_transaction_link_v1() from public,anon,authenticated;
drop trigger if exists financial_source_statement_transaction_links_guard_v1 on atlas.financial_source_statement_transaction_links;
create trigger financial_source_statement_transaction_links_guard_v1
before insert on atlas.financial_source_statement_transaction_links
for each row execute function atlas.guard_financial_source_statement_transaction_link_v1();

create or replace function atlas.prevent_financial_source_statement_link_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
begin
  raise exception 'Financial statement transaction-link history is append-only.' using errcode='55000';
end;
$$;

revoke all on function atlas.prevent_financial_source_statement_link_mutation_v1() from public,anon,authenticated;
drop trigger if exists financial_source_statement_transaction_links_immutable_v1 on atlas.financial_source_statement_transaction_links;
create trigger financial_source_statement_transaction_links_immutable_v1
before update or delete on atlas.financial_source_statement_transaction_links
for each row execute function atlas.prevent_financial_source_statement_link_mutation_v1();

create or replace function atlas.record_financial_source_statement_service_v1(
  p_connected_source_id uuid,
  p_provider_statement_key text,
  p_observation_id uuid,
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
  v_existing atlas.financial_source_statements%rowtype;
  v_statement atlas.financial_source_statements%rowtype;
  v_state text;
begin
  if p_connected_source_id is null or p_observation_id is null or v_key=''
     or p_period_start_on is null or p_period_end_on is null or p_period_end_on<p_period_start_on
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Connected source, observation, statement key, valid period, and three-letter currency are required.' using errcode='22023';
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

  if not exists(
    select 1 from atlas.connected_sources source
    where source.id=p_connected_source_id and source.authorization_state='connected'
  ) then
    raise exception 'Financial statement intake requires a connected source.' using errcode='55000';
  end if;
  if not exists(
    select 1 from atlas.connected_source_observations observation
    where observation.id=p_observation_id
      and observation.connected_source_id=p_connected_source_id
      and observation.provider_object_kind='financial_statement'
      and observation.provider_object_key=v_key
  ) then
    raise exception 'Financial statement observation does not match the connected source and provider key.' using errcode='23503';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_source_statement:'||p_connected_source_id::text||':'||v_key,0
  ));

  select * into v_existing
  from atlas.financial_source_statements statement
  where statement.connected_source_id=p_connected_source_id
    and statement.provider_statement_key=v_key
  for update;

  if v_existing.id is null then
    insert into atlas.financial_source_statements(
      connected_source_id,provider_statement_key,first_observation_id,current_observation_id,
      period_start_on,period_end_on,currency,opening_balance,closing_balance,
      reported_inflow_total,reported_outflow_total,reported_inflow_count,reported_outflow_count,
      reported_transaction_count,balance_check_kind,normalization_provenance,metadata
    ) values (
      p_connected_source_id,v_key,p_observation_id,p_observation_id,
      p_period_start_on,p_period_end_on,v_currency,p_opening_balance,p_closing_balance,
      p_reported_inflow_total,p_reported_outflow_total,p_reported_inflow_count,p_reported_outflow_count,
      p_reported_transaction_count,v_balance_kind,p_normalization_provenance,p_metadata
    ) returning * into v_statement;
    v_state:='admitted';
  else
    if v_existing.current_observation_id=p_observation_id
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
        'contractVersion','record_financial_source_statement_service_v1',
        'state','unchanged',
        'statementId',v_existing.id,
        'connectedSourceId',v_existing.connected_source_id,
        'currentObservationId',v_existing.current_observation_id
      );
    end if;

    update atlas.financial_source_statements statement
    set current_observation_id=p_observation_id,
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
    'contractVersion','record_financial_source_statement_service_v1',
    'state',v_state,
    'statementId',v_statement.id,
    'connectedSourceId',v_statement.connected_source_id,
    'firstObservationId',v_statement.first_observation_id,
    'currentObservationId',v_statement.current_observation_id,
    'periodStartOn',v_statement.period_start_on,
    'periodEndOn',v_statement.period_end_on,
    'currency',v_statement.currency
  );
end;
$$;

revoke all on function atlas.record_financial_source_statement_service_v1(
  uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_statement_service_v1(
  uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) to service_role;

create or replace function atlas.record_financial_source_statement_observation_service_v1(
  p_connected_source_id uuid,
  p_provider_statement_key text,
  p_raw_payload jsonb,
  p_provider_created_at timestamptz,
  p_observed_at timestamptz,
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
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $$
declare
  v_key text:=btrim(coalesce(p_provider_statement_key,''));
  v_payload jsonb:=coalesce(p_raw_payload,'{}'::jsonb);
  v_provenance jsonb:=coalesce(p_provenance,'{}'::jsonb);
  v_batch jsonb;
  v_hash text;
  v_observation_id uuid;
  v_statement jsonb;
begin
  if p_connected_source_id is null or v_key='' or jsonb_typeof(v_payload)<>'object' then
    raise exception 'Connected source, provider statement key, and raw object payload are required.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(v_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Financial statement provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  v_batch:=atlas.record_connected_source_observation_batch_service_v1(
    p_connected_source_id,
    'financial_statement',
    jsonb_build_array(jsonb_build_object(
      'key',v_key,
      'providerCreatedAt',p_provider_created_at,
      'payload',v_payload
    )),
    coalesce(p_observed_at,now()),
    v_provenance||jsonb_build_object(
      'financialStatementContract','record_financial_source_statement_observation_service_v1'
    )
  );

  v_hash:=encode(extensions.digest(convert_to(v_payload::text,'utf8'),'sha256'),'hex');
  select observation.id into v_observation_id
  from atlas.connected_source_observations observation
  where observation.connected_source_id=p_connected_source_id
    and observation.provider_object_kind='financial_statement'
    and observation.provider_object_key=v_key
    and observation.payload_sha256=v_hash
  order by observation.observed_at desc,observation.id desc
  limit 1;
  if v_observation_id is null then
    raise exception 'Connected-source observation was not established for the financial statement.' using errcode='55000';
  end if;

  v_statement:=atlas.record_financial_source_statement_service_v1(
    p_connected_source_id,v_key,v_observation_id,p_period_start_on,p_period_end_on,p_currency,
    p_opening_balance,p_closing_balance,p_reported_inflow_total,p_reported_outflow_total,
    p_reported_inflow_count,p_reported_outflow_count,p_reported_transaction_count,p_balance_check_kind,
    v_provenance||jsonb_build_object('sourceObservationId',v_observation_id,'payloadSha256',v_hash),
    p_metadata
  );

  return jsonb_build_object(
    'contractVersion','record_financial_source_statement_observation_service_v1',
    'connectedSourceId',p_connected_source_id,
    'providerStatementKey',v_key,
    'sourceObservationId',v_observation_id,
    'payloadSha256',v_hash,
    'observationBatch',v_batch,
    'statement',v_statement
  );
end;
$$;

revoke all on function atlas.record_financial_source_statement_observation_service_v1(
  uuid,text,jsonb,timestamptz,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.record_financial_source_statement_observation_service_v1(
  uuid,text,jsonb,timestamptz,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) to service_role;

create or replace function atlas.link_financial_source_statement_transactions_service_v1(
  p_statement_id uuid,
  p_statement_observation_id uuid,
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
  if p_statement_id is null or p_statement_observation_id is null or p_provider_transaction_keys is null
     or coalesce(array_length(p_provider_transaction_keys,1),0)=0 then
    raise exception 'Statement, statement observation, and provider transaction keys are required.' using errcode='22023';
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
  if v_statement.id is null then
    raise exception 'Financial source statement not found.' using errcode='23503';
  end if;
  if v_statement.current_observation_id<>p_statement_observation_id then
    raise exception 'Transaction links must target the current statement observation.' using errcode='23514';
  end if;

  select count(*),count(distinct btrim(key))
  into v_requested_count,v_distinct_count
  from unnest(p_provider_transaction_keys) key;
  if v_requested_count<>v_distinct_count
     or exists(select 1 from unnest(p_provider_transaction_keys) key where nullif(btrim(key),'') is null) then
    raise exception 'Provider transaction keys must be nonempty and unique within a statement link batch.' using errcode='22023';
  end if;

  select count(*)::integer into v_found_count
  from atlas.financial_source_transactions transaction
  where transaction.connected_source_id=v_statement.connected_source_id
    and transaction.provider_transaction_key=any(p_provider_transaction_keys);
  if v_found_count<>v_requested_count then
    raise exception 'Every statement transaction key must already exist as a stable financial source transaction.' using errcode='23503';
  end if;

  insert into atlas.financial_source_statement_transaction_links(
    statement_id,statement_observation_id,financial_transaction_id,provenance,metadata
  )
  select
    v_statement.id,
    p_statement_observation_id,
    transaction.id,
    p_provenance||jsonb_build_object(
      'authority','link_financial_source_statement_transactions_service_v1',
      'providerTransactionKey',transaction.provider_transaction_key
    ),
    p_metadata
  from atlas.financial_source_transactions transaction
  where transaction.connected_source_id=v_statement.connected_source_id
    and transaction.provider_transaction_key=any(p_provider_transaction_keys)
  on conflict(statement_id,statement_observation_id,financial_transaction_id) do nothing;
  get diagnostics v_inserted_count=row_count;

  return jsonb_build_object(
    'contractVersion','link_financial_source_statement_transactions_service_v1',
    'statementId',v_statement.id,
    'statementObservationId',p_statement_observation_id,
    'requestedCount',v_requested_count,
    'insertedCount',v_inserted_count,
    'unchangedCount',v_requested_count-v_inserted_count
  );
end;
$$;

revoke all on function atlas.link_financial_source_statement_transactions_service_v1(uuid,uuid,text[],jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.link_financial_source_statement_transactions_service_v1(uuid,uuid,text[],jsonb,jsonb)
  to service_role;

create or replace function atlas.financial_source_statement_reconciliation_core_v1(p_statement_id uuid)
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
  where statement.id=p_statement_id;
  if v_statement.id is null then
    raise exception 'Financial source statement not found.' using errcode='23503';
  end if;

  select
    count(*)::integer,
    count(*) filter(where transaction.source_amount>0)::integer,
    count(*) filter(where transaction.source_amount<0)::integer,
    coalesce(sum(transaction.source_amount) filter(where transaction.source_amount>0),0),
    coalesce(sum(abs(transaction.source_amount)) filter(where transaction.source_amount<0),0),
    coalesce(sum(transaction.source_amount),0)
  into v_linked_count,v_inflow_count,v_outflow_count,v_inflow_total,v_outflow_total,v_net_source_amount
  from atlas.financial_source_statement_transaction_links link
  join atlas.financial_source_transactions transaction on transaction.id=link.financial_transaction_id
  where link.statement_id=v_statement.id
    and link.statement_observation_id=v_statement.current_observation_id;

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
    'contractVersion','financial_source_statement_reconciliation_core_v1',
    'statementId',v_statement.id,
    'connectedSourceId',v_statement.connected_source_id,
    'providerStatementKey',v_statement.provider_statement_key,
    'currentObservationId',v_statement.current_observation_id,
    'periodStartOn',v_statement.period_start_on,
    'periodEndOn',v_statement.period_end_on,
    'currency',v_statement.currency,
    'state',v_state,
    'configuredCheckCount',v_configured_checks,
    'failedCheckCount',v_failed_checks,
    'reported',jsonb_strip_nulls(jsonb_build_object(
      'openingBalance',v_statement.opening_balance,
      'closingBalance',v_statement.closing_balance,
      'inflowTotal',v_statement.reported_inflow_total,
      'outflowTotal',v_statement.reported_outflow_total,
      'inflowCount',v_statement.reported_inflow_count,
      'outflowCount',v_statement.reported_outflow_count,
      'transactionCount',v_statement.reported_transaction_count,
      'balanceCheckKind',v_statement.balance_check_kind
    )),
    'linked',jsonb_build_object(
      'transactionCount',v_linked_count,
      'inflowCount',v_inflow_count,
      'outflowCount',v_outflow_count,
      'inflowTotal',v_inflow_total,
      'outflowTotal',v_outflow_total,
      'netSourceAmount',v_net_source_amount,
      'balanceImpliedClosing',case when v_statement.opening_balance is null then null else v_statement.opening_balance+v_net_source_amount end
    ),
    'checks',jsonb_strip_nulls(jsonb_build_object(
      'transactionCountMatches',v_count_match,
      'inflowCountMatches',v_inflow_count_match,
      'outflowCountMatches',v_outflow_count_match,
      'inflowTotalMatches',v_inflow_total_match,
      'outflowTotalMatches',v_outflow_total_match,
      'balanceMatches',v_balance_match
    )),
    'truthBoundary',jsonb_build_object(
      'reconciliationProvesExtractionCoverageNotAccountingTreatment',true,
      'statementDoesNotDetermineOperationalBeneficiary',true,
      'statementDoesNotDetermineRevenueOrExpenseTreatment',true,
      'currentObservationControlsCurrentRowMembership',true
    )
  );
end;
$$;

revoke all on function atlas.financial_source_statement_reconciliation_core_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.financial_source_statement_reconciliation_core_v1(uuid) to service_role;

create or replace function atlas.financial_source_statement_reconciliation_self_api_v1(p_statement_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_source_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;
  select statement.connected_source_id into v_source_id
  from atlas.financial_source_statements statement
  where statement.id=p_statement_id;
  if v_source_id is null then
    raise exception 'Financial source statement not found.' using errcode='23503';
  end if;
  if not atlas.financial_connected_source_authorized_self_v1(v_source_id) then
    raise exception 'Financial source authority required.' using errcode='42501';
  end if;
  return atlas.financial_source_statement_reconciliation_core_v1(p_statement_id);
end;
$$;

revoke all on function atlas.financial_source_statement_reconciliation_self_api_v1(uuid) from public,anon;
grant execute on function atlas.financial_source_statement_reconciliation_self_api_v1(uuid) to authenticated;

comment on table atlas.financial_source_statements is
  'Stable normalized financial-statement identity over versioned connected-source observations. Reported totals prove extraction coverage only; they do not establish accounting treatment.';
comment on table atlas.financial_source_statement_transaction_links is
  'Append-only membership of stable financial transactions in an exact financial-statement observation. Current reconciliation uses only links for the statement current observation.';
comment on function atlas.financial_source_statement_reconciliation_self_api_v1(uuid) is
  'Shows whether the current extracted transaction membership reconciles to configured statement-reported counts, totals, and optional source-amount balance delta. Reconciliation is evidence coverage, not bookkeeping classification.';

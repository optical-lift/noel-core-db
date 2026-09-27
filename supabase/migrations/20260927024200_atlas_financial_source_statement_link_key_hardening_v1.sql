-- Financial statement transaction-link key hardening v1
--
-- Provider transaction keys are stable source identity. Reject hidden whitespace and unpack
-- array values explicitly so exact source keys are used for lookup and linkage.

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
  from atlas.financial_source_statements source_statement
  where source_statement.id=p_statement_id
  for update;
  if v_statement.id is null then
    raise exception 'Financial source statement not found.' using errcode='23503';
  end if;
  if v_statement.current_observation_id<>p_statement_observation_id then
    raise exception 'Transaction links must target the current statement observation.' using errcode='23514';
  end if;

  if exists(
    select 1
    from unnest(p_provider_transaction_keys) as supplied(provider_key)
    where provider_key is null
       or nullif(btrim(provider_key),'') is null
       or provider_key<>btrim(provider_key)
  ) then
    raise exception 'Provider transaction keys must be nonempty exact source keys without surrounding whitespace.' using errcode='22023';
  end if;

  select count(*)::integer,count(distinct supplied.provider_key)::integer
  into v_requested_count,v_distinct_count
  from unnest(p_provider_transaction_keys) as supplied(provider_key);
  if v_requested_count<>v_distinct_count then
    raise exception 'Provider transaction keys must be unique within a statement link batch.' using errcode='22023';
  end if;

  select count(*)::integer into v_found_count
  from atlas.financial_source_transactions source_transaction
  where source_transaction.connected_source_id=v_statement.connected_source_id
    and source_transaction.provider_transaction_key=any(p_provider_transaction_keys);
  if v_found_count<>v_requested_count then
    raise exception 'Every statement transaction key must already exist as a stable financial source transaction.' using errcode='23503';
  end if;

  insert into atlas.financial_source_statement_transaction_links(
    statement_id,statement_observation_id,financial_transaction_id,provenance,metadata
  )
  select
    v_statement.id,
    p_statement_observation_id,
    source_transaction.id,
    p_provenance||jsonb_build_object(
      'authority','link_financial_source_statement_transactions_service_v1',
      'providerTransactionKey',source_transaction.provider_transaction_key
    ),
    p_metadata
  from atlas.financial_source_transactions source_transaction
  where source_transaction.connected_source_id=v_statement.connected_source_id
    and source_transaction.provider_transaction_key=any(p_provider_transaction_keys)
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

comment on function atlas.link_financial_source_statement_transactions_service_v1(uuid,uuid,text[],jsonb,jsonb) is
  'Links exact stable provider transaction keys to the current financial-statement observation. Keys with hidden surrounding whitespace or duplicates are rejected before lookup.';

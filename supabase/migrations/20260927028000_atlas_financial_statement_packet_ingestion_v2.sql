-- Atlas financial statement packet ingestion v2
--
-- Provider-neutral, service-side orchestration for one complete statement extraction.
-- One packet atomically records:
--   statement evidence -> transaction evidence -> stable transactions -> stable statement
--   -> statement/transaction membership -> reconciliation result.
--
-- It never classifies bookkeeping meaning, allocates transactions, or promotes Spend.
-- Stable transaction keys are required from the ingestion adapter; this function does not
-- invent identity from mutable description text or row order.

create or replace function atlas.ingest_financial_statement_packet_service_v2(
  p_financial_source_account_id uuid,
  p_statement_key text,
  p_source_kind text,
  p_statement_payload jsonb,
  p_transactions jsonb,
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
set search_path=pg_catalog,atlas
as $$
declare
  v_statement_key text:=btrim(coalesce(p_statement_key,''));
  v_source_kind text:=lower(btrim(coalesce(p_source_kind,'')));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_transactions jsonb:=coalesce(p_transactions,'[]'::jsonb);
  v_statement_evidence jsonb;
  v_statement_evidence_observation_id uuid;
  v_statement jsonb;
  v_statement_id uuid;
  v_item jsonb;
  v_item_key text;
  v_item_payload jsonb;
  v_item_provenance jsonb;
  v_item_metadata jsonb;
  v_item_evidence jsonb;
  v_item_evidence_observation_id uuid;
  v_item_transaction jsonb;
  v_occurred_on date;
  v_occurred_at timestamptz;
  v_amount numeric;
  v_item_currency text;
  v_raw_description text;
  v_source_party_label text;
  v_keys text[]:='{}'::text[];
  v_transaction_count integer:=0;
  v_distinct_key_count integer:=0;
  v_link_result jsonb;
  v_reconciliation jsonb;
begin
  if p_financial_source_account_id is null or v_statement_key='' or v_source_kind=''
     or p_statement_payload is null or jsonb_typeof(p_statement_payload)<>'object'
     or jsonb_typeof(v_transactions)<>'array'
     or p_period_start_on is null or p_period_end_on is null or p_period_end_on<p_period_start_on
     or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Financial account, statement/source identity, statement object payload, transaction array, valid period, and three-letter currency are required.' using errcode='22023';
  end if;
  if jsonb_array_length(v_transactions)>2000 then
    raise exception 'A financial statement packet may contain at most 2000 transactions.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Statement packet provenance and metadata must be JSON objects.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.financial_source_accounts account
    where account.id=p_financial_source_account_id and account.source_state='active'
  ) then
    raise exception 'Active financial source account required.' using errcode='23503';
  end if;

  -- Validate all transaction shapes and stable keys before writing any evidence.
  for v_item in select value from jsonb_array_elements(v_transactions)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'Every statement transaction must be a JSON object.' using errcode='22023';
    end if;
    v_item_key:=btrim(coalesce(v_item->>'key',''));
    if v_item_key='' then
      raise exception 'Every statement transaction requires a stable source transaction key.' using errcode='22023';
    end if;
    if v_item_key<>btrim(v_item_key) then
      raise exception 'Statement transaction keys may not contain hidden leading or trailing whitespace.' using errcode='22023';
    end if;
    v_item_payload:=v_item->'sourcePayload';
    if v_item_payload is null or jsonb_typeof(v_item_payload)<>'object' then
      raise exception 'Every statement transaction requires an object sourcePayload preserving the observed row snapshot.' using errcode='22023';
    end if;
    begin
      v_occurred_on:=(v_item->>'occurredOn')::date;
      v_amount:=(v_item->>'sourceAmount')::numeric;
    exception when others then
      raise exception 'Every statement transaction requires valid occurredOn and numeric sourceAmount.' using errcode='22023';
    end;
    if v_occurred_on is null or v_amount is null or v_amount=0 then
      raise exception 'Every statement transaction requires a date and nonzero sourceAmount.' using errcode='22023';
    end if;
    v_item_currency:=upper(btrim(coalesce(v_item->>'currency',v_currency)));
    if v_item_currency !~ '^[A-Z]{3}$' then
      raise exception 'Every transaction currency must be a three-letter code.' using errcode='22023';
    end if;
    if v_item->'provenance' is not null and jsonb_typeof(v_item->'provenance')<>'object' then
      raise exception 'Transaction provenance must be a JSON object when supplied.' using errcode='22023';
    end if;
    if v_item->'metadata' is not null and jsonb_typeof(v_item->'metadata')<>'object' then
      raise exception 'Transaction metadata must be a JSON object when supplied.' using errcode='22023';
    end if;
    v_keys:=array_append(v_keys,v_item_key);
  end loop;

  v_transaction_count:=coalesce(array_length(v_keys,1),0);
  if v_transaction_count>0 then
    select count(distinct key)::integer into v_distinct_key_count
    from unnest(v_keys) as keys(key);
    if v_distinct_key_count<>v_transaction_count then
      raise exception 'Statement transaction keys must be unique within a packet.' using errcode='22023';
    end if;
  end if;

  v_statement_evidence:=atlas.record_financial_source_evidence_service_v2(
    p_financial_source_account_id,
    'financial_statement',
    v_source_kind,
    v_statement_key,
    p_statement_payload,
    p_observed_at,
    null,
    p_provenance||jsonb_build_object(
      'ingestionContract','ingest_financial_statement_packet_service_v2',
      'packetRole','statement'
    ),
    p_metadata
  );
  v_statement_evidence_observation_id:=(v_statement_evidence->>'financialEvidenceObservationId')::uuid;

  v_statement:=atlas.record_financial_source_statement_service_v2(
    p_financial_source_account_id,v_statement_key,v_statement_evidence_observation_id,
    p_period_start_on,p_period_end_on,v_currency,p_opening_balance,p_closing_balance,
    p_reported_inflow_total,p_reported_outflow_total,p_reported_inflow_count,p_reported_outflow_count,
    p_reported_transaction_count,p_balance_check_kind,
    p_provenance||jsonb_build_object(
      'ingestionContract','ingest_financial_statement_packet_service_v2',
      'statementEvidenceObservationId',v_statement_evidence_observation_id
    ),p_metadata
  );
  v_statement_id:=(v_statement->>'statementId')::uuid;

  for v_item in select value from jsonb_array_elements(v_transactions)
  loop
    v_item_key:=btrim(v_item->>'key');
    v_item_payload:=v_item->'sourcePayload';
    v_item_provenance:=coalesce(v_item->'provenance','{}'::jsonb);
    v_item_metadata:=coalesce(v_item->'metadata','{}'::jsonb);
    v_occurred_on:=(v_item->>'occurredOn')::date;
    v_occurred_at:=null;
    if nullif(btrim(coalesce(v_item->>'occurredAt','')),'') is not null then
      begin v_occurred_at:=(v_item->>'occurredAt')::timestamptz;
      exception when others then
        raise exception 'Transaction occurredAt must be a valid timestamp when supplied.' using errcode='22023';
      end;
    end if;
    v_amount:=(v_item->>'sourceAmount')::numeric;
    v_item_currency:=upper(btrim(coalesce(v_item->>'currency',v_currency)));
    v_raw_description:=nullif(btrim(coalesce(v_item->>'rawDescription','')),'');
    v_source_party_label:=nullif(btrim(coalesce(v_item->>'sourcePartyLabel','')),'');

    v_item_evidence:=atlas.record_financial_source_evidence_service_v2(
      p_financial_source_account_id,
      'financial_transaction',
      v_source_kind,
      v_item_key,
      v_item_payload,
      coalesce(v_occurred_at,p_observed_at),
      null,
      p_provenance||v_item_provenance||jsonb_build_object(
        'ingestionContract','ingest_financial_statement_packet_service_v2',
        'packetRole','transaction',
        'statementKey',v_statement_key
      ),
      v_item_metadata
    );
    v_item_evidence_observation_id:=(v_item_evidence->>'financialEvidenceObservationId')::uuid;

    v_item_transaction:=atlas.record_financial_source_transaction_service_v2(
      p_financial_source_account_id,v_item_key,v_item_evidence_observation_id,
      v_occurred_on,v_occurred_at,v_amount,v_item_currency,
      v_raw_description,v_source_party_label,
      p_provenance||v_item_provenance||jsonb_build_object(
        'ingestionContract','ingest_financial_statement_packet_service_v2',
        'statementKey',v_statement_key,
        'financialEvidenceObservationId',v_item_evidence_observation_id
      ),v_item_metadata
    );
  end loop;

  if v_transaction_count>0 then
    v_link_result:=atlas.link_financial_source_statement_transactions_service_v2(
      v_statement_id,v_statement_evidence_observation_id,v_keys,
      p_provenance||jsonb_build_object(
        'ingestionContract','ingest_financial_statement_packet_service_v2'
      ),p_metadata
    );
  else
    v_link_result:=jsonb_build_object(
      'contractVersion','link_financial_source_statement_transactions_service_v2',
      'statementId',v_statement_id,
      'statementEvidenceObservationId',v_statement_evidence_observation_id,
      'requestedCount',0,'insertedCount',0,'unchangedCount',0
    );
  end if;

  v_reconciliation:=atlas.financial_source_statement_reconciliation_core_v2(v_statement_id);

  return jsonb_build_object(
    'contractVersion','financial_statement_packet_ingestion_v2',
    'financialSourceAccountId',p_financial_source_account_id,
    'statementKey',v_statement_key,
    'statementId',v_statement_id,
    'statementEvidenceObservationId',v_statement_evidence_observation_id,
    'transactionCount',v_transaction_count,
    'statement',v_statement,
    'transactionLinks',v_link_result,
    'reconciliation',v_reconciliation,
    'truthBoundary',jsonb_build_object(
      'atomicPacket',true,
      'stableTransactionKeysSuppliedByAdapter',true,
      'sourceEvidencePreservedBeforeNormalization',true,
      'reconciliationDoesNotClassifyBookkeepingMeaning',true,
      'reviewCreated',false,
      'spendCreated',false
    )
  );
end;
$$;

revoke all on function atlas.ingest_financial_statement_packet_service_v2(
  uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) from public,anon,authenticated;
grant execute on function atlas.ingest_financial_statement_packet_service_v2(
  uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) to service_role;

comment on function atlas.ingest_financial_statement_packet_service_v2(
  uuid,text,text,jsonb,jsonb,timestamptz,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb
) is
  'Atomically ingests one provider-neutral financial statement extraction into account-scoped evidence, stable statement/transaction identities, statement membership, and reconciliation. It does not create bookkeeping review, classification, or Spend.';

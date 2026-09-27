-- Contract validation: account-centered transaction + statement intake v2

begin;

do $$
declare
  v_def text;
  v_nullable text;
begin
  if to_regprocedure('atlas.record_financial_source_transaction_service_v2(uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb)') is null then
    raise exception 'Missing record_financial_source_transaction_service_v2';
  end if;
  if to_regprocedure('atlas.record_financial_source_statement_service_v2(uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)') is null then
    raise exception 'Missing record_financial_source_statement_service_v2';
  end if;
  if to_regprocedure('atlas.link_financial_source_statement_transactions_service_v2(uuid,uuid,text[],jsonb,jsonb)') is null then
    raise exception 'Missing link_financial_source_statement_transactions_service_v2';
  end if;
  if to_regprocedure('atlas.financial_source_statement_reconciliation_core_v2(uuid)') is null then
    raise exception 'Missing financial_source_statement_reconciliation_core_v2';
  end if;
  if to_regprocedure('atlas.financial_source_statement_reconciliation_self_api_v2(uuid)') is null then
    raise exception 'Missing financial_source_statement_reconciliation_self_api_v2';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='financial_source_transactions'
      and column_name='financial_source_account_id'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='financial_source_transactions'
      and column_name='current_financial_evidence_observation_id'
  ) then
    raise exception 'Financial transactions must expose account-centered evidence identity';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='financial_source_statements'
      and column_name='financial_source_account_id'
  ) or not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='financial_source_statements'
      and column_name='current_financial_evidence_observation_id'
  ) then
    raise exception 'Financial statements must expose account-centered evidence identity';
  end if;

  select is_nullable into v_nullable
  from information_schema.columns
  where table_schema='atlas' and table_name='financial_source_transactions' and column_name='connected_source_id';
  if v_nullable<>'YES' then
    raise exception 'V2 financial transactions must not require an externally authorized connected source';
  end if;

  select is_nullable into v_nullable
  from information_schema.columns
  where table_schema='atlas' and table_name='financial_source_statements' and column_name='connected_source_id';
  if v_nullable<>'YES' then
    raise exception 'V2 financial statements must not require an externally authorized connected source';
  end if;

  select pg_get_functiondef('atlas.record_financial_source_transaction_service_v2(uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('financial_source_evidence_observations' in v_def)=0
     or position('authorization_state' in v_def)>0 then
    raise exception 'V2 transaction intake must depend on account evidence, not connected-source authorization';
  end if;

  select pg_get_functiondef('atlas.record_financial_source_statement_service_v2(uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)'::regprocedure)
  into v_def;
  if position('financial_source_evidence_observations' in v_def)=0
     or position('authorization_state' in v_def)>0 then
    raise exception 'V2 statement intake must depend on account evidence, not connected-source authorization';
  end if;

  select pg_get_functiondef('atlas.financial_source_statement_reconciliation_core_v2(uuid)'::regprocedure)
  into v_def;
  if position('reconciledMeansExtractionCompleteNotBookkeepingClassified' in v_def)=0
     or position('bookkeepingInterpretationCreated' in v_def)=0 then
    raise exception 'Statement reconciliation must preserve the extraction/classification boundary';
  end if;

  if to_regprocedure('atlas.record_financial_source_transaction_service_v1(uuid,text,uuid,date,timestamptz,numeric,text,text,text,jsonb,jsonb)') is null
     or to_regprocedure('atlas.record_financial_source_statement_service_v1(uuid,text,uuid,date,date,text,numeric,numeric,numeric,numeric,integer,integer,integer,text,jsonb,jsonb)') is null then
    raise exception 'Account-centered V2 must not remove the existing live-connector V1 path';
  end if;
end;
$$;

rollback;

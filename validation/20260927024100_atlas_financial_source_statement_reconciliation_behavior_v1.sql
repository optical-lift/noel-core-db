begin;

-- Rollback-only behavioral validation for statement extraction completeness.
-- This test does not impersonate an application user and does not touch durable production data.
do $validation$
declare
  v_user_id uuid;
  v_source_id uuid;
  v_statement_key text:='validation-statement-'||gen_random_uuid()::text;
  v_inflow_key text:='validation-inflow-'||gen_random_uuid()::text;
  v_outflow_key text:='validation-outflow-'||gen_random_uuid()::text;
  v_statement jsonb;
  v_inflow jsonb;
  v_outflow jsonb;
  v_link jsonb;
  v_reconciliation jsonb;
  v_statement_id uuid;
  v_statement_observation_id uuid;
begin
  select user_row.id into v_user_id
  from auth.users user_row
  where user_row.deleted_at is null
  order by user_row.created_at,user_row.id
  limit 1;
  if v_user_id is null then
    raise exception 'Statement behavior validation requires one existing auth user for synthetic connected-source custody.';
  end if;

  insert into atlas.connected_sources(
    custodian_user_id,provider_key,provider_account_key,display_label,
    authorization_state,capabilities,metadata
  ) values (
    v_user_id,
    'validation_financial_statement',
    gen_random_uuid()::text,
    'Synthetic statement validation source',
    'connected',
    jsonb_build_object('financialStatements',true,'financialTransactions',true),
    jsonb_build_object('validationOnly',true)
  ) returning id into v_source_id;

  v_statement:=atlas.record_financial_source_statement_observation_service_v1(
    v_source_id,
    v_statement_key,
    jsonb_build_object(
      'openingBalance','100.00',
      'closingBalance','150.00',
      'reportedInflows','100.00',
      'reportedOutflows','50.00',
      'reportedTransactionCount',2,
      'providerRevision',1
    ),
    '2001-01-31 12:00:00+00'::timestamptz,
    '2001-02-01 12:00:00+00'::timestamptz,
    '2001-01-01'::date,
    '2001-01-31'::date,
    'USD',
    100.00,
    150.00,
    100.00,
    50.00,
    1,
    1,
    2,
    'source_amount_delta',
    jsonb_build_object('validationOnly',true),
    jsonb_build_object('validationOnly',true)
  );
  v_statement_id:=(v_statement->'statement'->>'statementId')::uuid;
  v_statement_observation_id:=(v_statement->>'sourceObservationId')::uuid;

  v_inflow:=atlas.record_financial_source_transaction_observation_service_v1(
    v_source_id,v_inflow_key,
    jsonb_build_object('description','Synthetic inflow','amount','100.00'),
    '2001-01-10 12:00:00+00'::timestamptz,
    '2001-02-01 12:00:00+00'::timestamptz,
    '2001-01-10'::date,'2001-01-10 12:00:00+00'::timestamptz,
    100.00,'USD','Synthetic inflow','Synthetic source',
    jsonb_build_object('validationOnly',true),jsonb_build_object('validationOnly',true)
  );
  v_outflow:=atlas.record_financial_source_transaction_observation_service_v1(
    v_source_id,v_outflow_key,
    jsonb_build_object('description','Synthetic outflow','amount','-50.00'),
    '2001-01-20 12:00:00+00'::timestamptz,
    '2001-02-01 12:00:00+00'::timestamptz,
    '2001-01-20'::date,'2001-01-20 12:00:00+00'::timestamptz,
    -50.00,'USD','Synthetic outflow','Synthetic merchant',
    jsonb_build_object('validationOnly',true),jsonb_build_object('validationOnly',true)
  );

  v_link:=atlas.link_financial_source_statement_transactions_service_v1(
    v_statement_id,
    v_statement_observation_id,
    array[v_inflow_key,v_outflow_key],
    jsonb_build_object('validationOnly',true),
    jsonb_build_object('validationOnly',true)
  );
  if (v_link->>'requestedCount')::integer<>2 then
    raise exception 'Synthetic statement did not link both transaction identities: %',v_link;
  end if;

  v_reconciliation:=atlas.financial_source_statement_reconciliation_core_v1(v_statement_id);
  if v_reconciliation->>'state'<>'reconciled'
     or coalesce((v_reconciliation->>'failedCheckCount')::integer,-1)<>0
     or (v_reconciliation->'linked'->>'transactionCount')::integer<>2
     or (v_reconciliation->'linked'->>'inflowTotal')::numeric<>100.00
     or (v_reconciliation->'linked'->>'outflowTotal')::numeric<>50.00
     or coalesce((v_reconciliation->'checks'->>'balanceMatches')::boolean,false) is not true then
    raise exception 'Complete synthetic statement did not reconcile: %',v_reconciliation;
  end if;

  -- A new statement observation is a new extraction version. Old membership must not silently carry forward.
  v_statement:=atlas.record_financial_source_statement_observation_service_v1(
    v_source_id,
    v_statement_key,
    jsonb_build_object(
      'openingBalance','100.00',
      'closingBalance','140.00',
      'reportedInflows','100.00',
      'reportedOutflows','60.00',
      'reportedTransactionCount',2,
      'providerRevision',2
    ),
    '2001-01-31 12:00:00+00'::timestamptz,
    '2001-02-02 12:00:00+00'::timestamptz,
    '2001-01-01'::date,
    '2001-01-31'::date,
    'USD',
    100.00,
    140.00,
    100.00,
    60.00,
    1,
    1,
    2,
    'source_amount_delta',
    jsonb_build_object('validationOnly',true,'providerRevision',2),
    jsonb_build_object('validationOnly',true)
  );
  if (v_statement->'statement'->>'statementId')::uuid is distinct from v_statement_id then
    raise exception 'Statement refresh duplicated stable statement identity.';
  end if;
  v_statement_observation_id:=(v_statement->>'sourceObservationId')::uuid;

  v_reconciliation:=atlas.financial_source_statement_reconciliation_core_v1(v_statement_id);
  if v_reconciliation->>'state'<>'open'
     or (v_reconciliation->'linked'->>'transactionCount')::integer<>0 then
    raise exception 'New statement observation incorrectly inherited prior extraction membership: %',v_reconciliation;
  end if;

  -- Relink the same stable transactions to the new extraction. The changed reported amount must remain open.
  perform atlas.link_financial_source_statement_transactions_service_v1(
    v_statement_id,v_statement_observation_id,array[v_inflow_key,v_outflow_key],
    jsonb_build_object('validationOnly',true,'providerRevision',2),
    jsonb_build_object('validationOnly',true)
  );
  v_reconciliation:=atlas.financial_source_statement_reconciliation_core_v1(v_statement_id);
  if v_reconciliation->>'state'<>'open'
     or coalesce((v_reconciliation->'checks'->>'transactionCountMatches')::boolean,false) is not true
     or coalesce((v_reconciliation->'checks'->>'outflowTotalMatches')::boolean,true) is not false
     or coalesce((v_reconciliation->'checks'->>'balanceMatches')::boolean,true) is not false then
    raise exception 'Statement mismatch was not surfaced after current-version relink: %',v_reconciliation;
  end if;

  -- Refresh the stable outflow transaction to the corrected source amount. Reconciliation should close.
  v_outflow:=atlas.record_financial_source_transaction_observation_service_v1(
    v_source_id,v_outflow_key,
    jsonb_build_object('description','Synthetic outflow corrected','amount','-60.00','providerRevision',2),
    '2001-01-20 12:00:00+00'::timestamptz,
    '2001-02-02 12:00:00+00'::timestamptz,
    '2001-01-20'::date,'2001-01-20 12:00:00+00'::timestamptz,
    -60.00,'USD','Synthetic outflow corrected','Synthetic merchant',
    jsonb_build_object('validationOnly',true,'providerRevision',2),jsonb_build_object('validationOnly',true)
  );

  v_reconciliation:=atlas.financial_source_statement_reconciliation_core_v1(v_statement_id);
  if v_reconciliation->>'state'<>'reconciled'
     or coalesce((v_reconciliation->>'failedCheckCount')::integer,-1)<>0
     or (v_reconciliation->'linked'->>'outflowTotal')::numeric<>60.00
     or coalesce((v_reconciliation->'checks'->>'balanceMatches')::boolean,false) is not true then
    raise exception 'Corrected stable transaction did not close current statement reconciliation: %',v_reconciliation;
  end if;
end;
$validation$;

rollback;

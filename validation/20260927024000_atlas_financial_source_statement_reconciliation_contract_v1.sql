begin;

-- Read-only contract validation for financial source statement reconciliation v1.
do $validation$
declare
  v_missing integer;
  v_bad_rls integer;
  v_direct_grants integer;
  v_definition text;
begin
  select count(*)::integer into v_missing
  from (values
    ('financial_source_statements'),
    ('financial_source_statement_transaction_links')
  ) expected(table_name)
  where to_regclass('atlas.'||expected.table_name) is null;
  if v_missing<>0 then
    raise exception '% financial statement reconciliation tables are missing',v_missing;
  end if;

  select count(*)::integer into v_bad_rls
  from pg_class relation
  join pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='atlas'
    and relation.relname in ('financial_source_statements','financial_source_statement_transaction_links')
    and relation.relrowsecurity is not true;
  if v_bad_rls<>0 then
    raise exception '% financial statement reconciliation tables are missing RLS',v_bad_rls;
  end if;

  select count(*)::integer into v_direct_grants
  from information_schema.role_table_grants grant_row
  where grant_row.table_schema='atlas'
    and grant_row.table_name in ('financial_source_statements','financial_source_statement_transaction_links')
    and grant_row.grantee in ('anon','authenticated');
  if v_direct_grants<>0 then
    raise exception 'Financial statement reconciliation tables unexpectedly grant direct anon/authenticated access';
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    join pg_class relation on relation.oid=constraint_row.conrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='atlas'
      and relation.relname='financial_source_statements'
      and constraint_row.contype='u'
      and pg_get_constraintdef(constraint_row.oid) ilike '%connected_source_id%provider_statement_key%'
  ) then
    raise exception 'Stable financial statement identity uniqueness is missing';
  end if;

  if not exists(
    select 1 from pg_trigger trigger_row
    join pg_class relation on relation.oid=trigger_row.tgrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='atlas'
      and relation.relname='financial_source_statements'
      and trigger_row.tgname='financial_source_statements_guard_v1'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'Financial statement identity guard trigger is missing';
  end if;

  if not exists(
    select 1 from pg_trigger trigger_row
    join pg_class relation on relation.oid=trigger_row.tgrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='atlas'
      and relation.relname='financial_source_statement_transaction_links'
      and trigger_row.tgname='financial_source_statement_transaction_links_immutable_v1'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'Financial statement transaction membership is not append-only';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='record_financial_source_statement_observation_service_v1';
  if v_definition is null
     or v_definition not ilike '%record_connected_source_observation_batch_service_v1%'
     or v_definition not ilike '%financial_statement%'
     or v_definition not ilike '%record_financial_source_statement_service_v1%' then
    raise exception 'Financial statement intake does not preserve raw observation before normalization';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='link_financial_source_statement_transactions_service_v1';
  if v_definition is null
     or v_definition not ilike '%current_observation_id%'
     or v_definition not ilike '%connected_source_id%'
     or v_definition not ilike '%financial_source_transactions%' then
    raise exception 'Statement transaction linking does not preserve current-version and same-source custody';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='financial_source_statement_reconciliation_core_v1';
  if v_definition is null
     or v_definition not ilike '%reported_transaction_count%'
     or v_definition not ilike '%reported_inflow_total%'
     or v_definition not ilike '%reported_outflow_total%'
     or v_definition not ilike '%source_amount_delta%'
     or v_definition not ilike '%statement_observation_id=v_statement.current_observation_id%' then
    raise exception 'Statement reconciliation does not compare current extraction against configured statement evidence';
  end if;

  if v_definition not ilike '%reconciliationProvesExtractionCoverageNotAccountingTreatment%'
     or v_definition not ilike '%statementDoesNotDetermineOperationalBeneficiary%'
     or v_definition not ilike '%statementDoesNotDetermineRevenueOrExpenseTreatment%' then
    raise exception 'Statement reconciliation truth boundary is missing';
  end if;

  if not exists(
    select 1 from information_schema.routine_privileges privilege
    where privilege.routine_schema='atlas'
      and privilege.routine_name='record_financial_source_statement_observation_service_v1'
      and privilege.grantee='service_role'
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'Financial statement observation intake is not service-only executable';
  end if;

  if exists(
    select 1 from information_schema.routine_privileges privilege
    where privilege.routine_schema='atlas'
      and privilege.routine_name in (
        'record_financial_source_statement_observation_service_v1',
        'record_financial_source_statement_service_v1',
        'link_financial_source_statement_transactions_service_v1',
        'financial_source_statement_reconciliation_core_v1'
      )
      and privilege.grantee in ('anon','authenticated')
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'Internal financial statement functions are unexpectedly executable by anon/authenticated';
  end if;

  if not exists(
    select 1 from information_schema.routine_privileges privilege
    where privilege.routine_schema='atlas'
      and privilege.routine_name='financial_source_statement_reconciliation_self_api_v1'
      and privilege.grantee='authenticated'
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'Authenticated statement reconciliation read API is missing';
  end if;
end;
$validation$;

rollback;

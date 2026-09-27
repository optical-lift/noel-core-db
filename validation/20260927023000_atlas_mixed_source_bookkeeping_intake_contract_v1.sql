begin;

-- Read-only contract validation for mixed-source bookkeeping intake v1.
do $validation$
declare
  v_missing integer;
  v_bad_rls integer;
  v_direct_grants integer;
  v_definition text;
begin
  select count(*)::integer into v_missing
  from (values
    ('financial_source_transactions'),
    ('financial_source_transaction_review_events'),
    ('financial_source_transaction_allocations'),
    ('financial_source_transaction_spend_promotions'),
    ('financial_source_account_holders')
  ) expected(table_name)
  where to_regclass('atlas.'||expected.table_name) is null;
  if v_missing<>0 then
    raise exception '% mixed-source bookkeeping tables are missing',v_missing;
  end if;

  select count(*)::integer into v_bad_rls
  from pg_class relation
  join pg_namespace namespace on namespace.oid=relation.relnamespace
  where namespace.nspname='atlas'
    and relation.relname in (
      'financial_source_transactions',
      'financial_source_transaction_review_events',
      'financial_source_transaction_allocations',
      'financial_source_transaction_spend_promotions',
      'financial_source_account_holders'
    )
    and relation.relrowsecurity is not true;
  if v_bad_rls<>0 then
    raise exception '% mixed-source bookkeeping tables are missing RLS',v_bad_rls;
  end if;

  select count(*)::integer into v_direct_grants
  from information_schema.role_table_grants grant_row
  where grant_row.table_schema='atlas'
    and grant_row.table_name in (
      'financial_source_transactions',
      'financial_source_transaction_review_events',
      'financial_source_transaction_allocations',
      'financial_source_transaction_spend_promotions',
      'financial_source_account_holders'
    )
    and grant_row.grantee in ('anon','authenticated');
  if v_direct_grants<>0 then
    raise exception 'Mixed-source bookkeeping tables unexpectedly grant direct anon/authenticated access';
  end if;

  if not exists(
    select 1 from pg_constraint constraint_row
    join pg_class relation on relation.oid=constraint_row.conrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='atlas'
      and relation.relname='financial_source_transactions'
      and constraint_row.contype='u'
      and pg_get_constraintdef(constraint_row.oid) ilike '%connected_source_id%provider_transaction_key%'
  ) then
    raise exception 'Stable financial transaction identity uniqueness is missing';
  end if;

  if not exists(
    select 1 from pg_trigger trigger_row
    join pg_class relation on relation.oid=trigger_row.tgrelid
    join pg_namespace namespace on namespace.oid=relation.relnamespace
    where namespace.nspname='atlas'
      and relation.relname='financial_source_transactions'
      and trigger_row.tgname='financial_source_transactions_guard_v1'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'Financial transaction identity guard trigger is missing';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='promote_financial_source_transaction_expense_self_api_v1';

  if v_definition is null then
    raise exception 'Financial transaction Spend promotion function is missing';
  end if;
  if v_definition not ilike '%ledger.ledgers%'
     or v_definition not ilike '%subject_entity_id%'
     or v_definition not ilike '%financial_source_account_holders%'
     or v_definition not ilike '%ledger_organization_participations%'
     or v_definition not ilike '%compatibility.legacy_bindings%' then
    raise exception 'Spend promotion is not using canonical Ledger subject, account-holder evidence, and compatibility routing as required';
  end if;
  if v_definition ilike '%custodian_user_id=auth.uid()%'
     or v_definition ilike '%custodian_organization_id=v_ledger.organization_id%' then
    raise exception 'Spend funding inference still depends on connector custody or legacy Ledger ownership';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='record_financial_source_transaction_observation_service_v1';
  if v_definition is null
     or v_definition not ilike '%record_connected_source_observation_batch_service_v1%'
     or v_definition not ilike '%record_financial_source_transaction_service_v1%' then
    raise exception 'Financial observation intake does not preserve raw connected-source evidence before normalization';
  end if;

  select pg_get_functiondef(proc.oid) into v_definition
  from pg_proc proc
  join pg_namespace namespace on namespace.oid=proc.pronamespace
  where namespace.nspname='atlas'
    and proc.proname='replace_financial_source_transaction_review_self_api_v1';
  if v_definition is null
     or v_definition not ilike '%abs(v_transaction.source_amount)%'
     or v_definition not ilike '%source_observation_id%'
     or v_definition not ilike '%operating_expense%'
     or v_definition not ilike '%owner_funding%' then
    raise exception 'Financial review contract is missing full-amount accounting, observation snapshot, or treatment separation';
  end if;

  if not exists(
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema='atlas'
      and privilege.routine_name='record_financial_source_transaction_observation_service_v1'
      and privilege.grantee='service_role'
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'Financial observation intake is not service-only executable';
  end if;

  if exists(
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema='atlas'
      and privilege.routine_name='record_financial_source_transaction_observation_service_v1'
      and privilege.grantee in ('anon','authenticated')
      and privilege.privilege_type='EXECUTE'
  ) then
    raise exception 'Financial observation intake is unexpectedly executable by anon/authenticated';
  end if;
end;
$validation$;

rollback;

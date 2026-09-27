-- Contract validation: shared V1/V2 transaction and review guards

begin;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('atlas.guard_financial_source_transaction_v1()'::regprocedure)
  into v_def;
  if position('financial_source_evidence_observations' in v_def)=0
     or position('connected_source_observations' in v_def)=0
     or position('financial_source_account_id is not null' in lower(v_def))=0 then
    raise exception 'Shared transaction guard must validate both account-evidence V2 and connector V1 paths';
  end if;

  select pg_get_functiondef('atlas.guard_financial_source_review_event_v1()'::regprocedure)
  into v_def;
  if position('financial_evidence_observation_id' in v_def)=0
     or position('source_observation_id' in v_def)=0
     or position('current_financial_evidence_observation_id' in v_def)=0
     or position('current_observation_id' in v_def)=0 then
    raise exception 'Shared review guard must validate the current evidence version on both V2 and V1 paths';
  end if;

  if not exists(
    select 1
    from pg_trigger trigger
    join pg_class table_class on table_class.oid=trigger.tgrelid
    join pg_namespace namespace on namespace.oid=table_class.relnamespace
    where namespace.nspname='atlas'
      and table_class.relname='financial_source_transactions'
      and trigger.tgname='financial_source_transactions_guard_v1'
      and not trigger.tgisinternal
  ) then
    raise exception 'Shared financial transaction guard trigger must remain installed';
  end if;

  if not exists(
    select 1
    from pg_trigger trigger
    join pg_class table_class on table_class.oid=trigger.tgrelid
    join pg_namespace namespace on namespace.oid=table_class.relnamespace
    where namespace.nspname='atlas'
      and table_class.relname='financial_source_transaction_review_events'
      and trigger.tgname='financial_source_transaction_review_event_guard_v1'
      and not trigger.tgisinternal
  ) then
    raise exception 'Shared financial review guard trigger must remain installed';
  end if;
end;
$$;

rollback;

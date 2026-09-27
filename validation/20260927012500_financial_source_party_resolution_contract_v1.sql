-- Financial source party resolution v1 structural contract validation.
-- Synthetic/schema-only; contains no user financial data.

do $$
begin
  if to_regclass('atlas.financial_source_transactions') is null then
    raise exception 'atlas.financial_source_transactions is required';
  end if;
  if to_regclass('reality.entities') is null then
    raise exception 'reality.entities is required';
  end if;
  if to_regclass('atlas.financial_source_transaction_party_resolutions') is null then
    raise exception 'financial source party resolution table is missing';
  end if;

  if to_regprocedure('atlas.financial_source_transaction_party_resolution_v1(uuid,text)') is null
     or to_regprocedure('atlas.resolve_financial_source_transaction_party_self_api_v1(uuid,uuid,text,jsonb,jsonb)') is null then
    raise exception 'financial source party resolution functions are incomplete';
  end if;

  if not exists(
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='financial_source_transaction_party_resolutions'
      and c.relrowsecurity
  ) then
    raise exception 'financial source party resolutions must have row level security enabled';
  end if;

  if not exists(
    select 1
    from pg_indexes
    where schemaname='atlas'
      and tablename='financial_source_transaction_party_resolutions'
      and indexname='financial_source_transaction_party_active_idx'
  ) then
    raise exception 'active source-party resolution uniqueness index is missing';
  end if;

  if not exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='financial_source_transaction_party_resolutions'
      and column_name='literal_label'
      and is_nullable='NO'
  ) or not exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='financial_source_transaction_party_resolutions'
      and column_name='entity_id'
      and data_type='uuid'
  ) then
    raise exception 'source-party evidence/entity reference contract is incomplete';
  end if;
end;
$$;

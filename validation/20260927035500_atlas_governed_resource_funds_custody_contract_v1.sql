-- Structural contract for governed resource funds / custody v1.
-- Run after migrations on an isolated database. No production identifiers are embedded here.

begin;

do $$
declare
  v_rls boolean;
  v_target regclass;
begin
  if to_regclass('atlas.accounting_resource_pools') is null
     or to_regclass('atlas.accounting_resource_constraints') is null
     or to_regclass('atlas.accounting_resource_interests') is null
     or to_regclass('atlas.accounting_resource_movements') is null
     or to_regclass('atlas.accounting_custody_reconciliations') is null then
    raise exception 'Governed resource/custody tables are missing.';
  end if;

  if to_regprocedure('atlas.upsert_accounting_resource_pool_self_api_v1(uuid,text,text,text,text,text,uuid,uuid,uuid[],jsonb,jsonb)') is null
     or to_regprocedure('atlas.upsert_accounting_resource_constraint_self_api_v1(uuid,text,text,uuid,text,date,date,uuid,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('atlas.upsert_accounting_resource_interest_self_api_v1(uuid,text,text,uuid,uuid,text,text,jsonb,jsonb)') is null
     or to_regprocedure('atlas.add_accounting_resource_movement_self_api_v1(uuid,uuid,uuid,text,numeric,jsonb,jsonb)') is null
     or to_regprocedure('atlas.reconcile_accounting_custody_pool_self_api_v1(uuid,date,numeric,uuid,jsonb)') is null
     or to_regprocedure('atlas.accounting_custody_interest_ledger_self_api_v1(uuid,date,date)') is null then
    raise exception 'Governed resource/custody service functions are missing.';
  end if;

  if not exists(
    select 1 from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on kcu.constraint_name=tc.constraint_name and kcu.constraint_schema=tc.constraint_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name=tc.constraint_name and ccu.constraint_schema=tc.constraint_schema
    where tc.table_schema='atlas' and tc.table_name='accounting_resource_interests'
      and tc.constraint_type='FOREIGN KEY' and kcu.column_name='holder_entity_id'
      and ccu.table_schema='reality' and ccu.table_name='entities' and ccu.column_name='id'
  ) then
    raise exception 'Resource-interest holder must be foreign-keyed to canonical Reality entities.';
  end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name in (
      'accounting_resource_interests','accounting_resource_source_links','accounting_custody_reconciliations'
    ) and lower(column_name) in ('name','email','phone','address','donor_name','client_name','tenant_name')
  ) then
    raise exception 'Governed resource/custody tables must not own copied party identity fields.';
  end if;

  if not exists(
    select 1 from pg_indexes
    where schemaname='atlas' and indexname='accounting_resource_pools_custody_liability_uq'
  ) or not exists(
    select 1 from pg_indexes
    where schemaname='atlas' and indexname='accounting_resource_pools_custody_asset_uq'
  ) then
    raise exception 'Custody control accounts must be unique per accounting book.';
  end if;

  if not exists(
    select 1 from pg_trigger
    where tgrelid='atlas.accounting_journal_entries'::regclass
      and tgname='accounting_resource_posting_guard_v1' and not tgisinternal
  ) then
    raise exception 'Journal posting must be guarded by governed-resource checks.';
  end if;

  if not exists(
    select 1 from pg_trigger
    where tgrelid='atlas.accounting_resource_movements'::regclass
      and tgname='accounting_resource_movement_guard_v1' and not tgisinternal
  ) then
    raise exception 'Resource movements must be guarded.';
  end if;

  if not exists(
    select 1 from pg_trigger
    where tgrelid='atlas.accounting_custody_reconciliations'::regclass
      and tgname='accounting_custody_reconciliation_immutable_v1' and not tgisinternal
  ) then
    raise exception 'Custody reconciliation history must be append-only.';
  end if;

  foreach v_target in array array[
    'atlas.accounting_resource_pools'::regclass,
    'atlas.accounting_resource_constraints'::regclass,
    'atlas.accounting_resource_pool_ledger_scopes'::regclass,
    'atlas.accounting_resource_interests'::regclass,
    'atlas.accounting_resource_source_links'::regclass,
    'atlas.accounting_resource_movements'::regclass,
    'atlas.accounting_custody_reconciliations'::regclass
  ] loop
    select relrowsecurity into v_rls from pg_class where oid=v_target;
    if not coalesce(v_rls,false) then
      raise exception 'RLS must be enabled on %',v_target;
    end if;
  end loop;

  if has_table_privilege('authenticated','atlas.accounting_resource_pools','INSERT')
     or has_table_privilege('authenticated','atlas.accounting_resource_movements','INSERT')
     or has_table_privilege('authenticated','atlas.accounting_custody_reconciliations','UPDATE') then
    raise exception 'Authenticated browser role must not have direct governed-resource table writes.';
  end if;
end;
$$;

rollback;

-- Canonical postconditions for Atlas First-Class Ledger v1.
-- Runs only against the disposable production-schema clone after the candidate migration.

do $proof$
declare
  v_def text;
  v_is_nullable text;
begin
  if to_regclass('atlas.ledgers') is null
     or to_regclass('atlas.principal_ledger_authorities') is null then
    raise exception 'First-class Ledger canonical tables are missing.';
  end if;

  if to_regprocedure('atlas.primary_ledger_for_organization_v1(uuid)') is null
     or to_regprocedure('atlas.principal_has_ledger_authority_v1(uuid,uuid)') is null
     or to_regprocedure('atlas.principal_ledgers_self_api_v1()') is null then
    raise exception 'First-class Ledger function membrane is incomplete.';
  end if;

  -- The data fixture must be present so data-dependent backfill proofs are meaningful.
  if not exists (
    select 1 from atlas.organizations o where o.stable_key = 'feast_guild'
  ) or not exists (
    select 1 from atlas.organizations o where o.stable_key = 'ledger_validation_company'
  ) or not exists (
    select 1 from atlas.principals p where p.stable_key = 'ledger_validation_principal'
  ) then
    raise exception 'First-class Ledger production-shaped validation fixture is incomplete.';
  end if;

  if exists (
    select 1
    from atlas.organizations o
    left join atlas.ledgers l
      on l.organization_id = o.id
     and l.ledger_kind = 'organization_governing'
     and l.status = 'active'
    group by o.id
    having count(l.id) <> 1
  ) then
    raise exception 'Every Organization must have exactly one active governing Ledger after backfill.';
  end if;

  if exists (
    select 1
    from atlas.organization_ledger_entries e
    left join atlas.ledgers l on l.id = e.ledger_id
    where e.ledger_id is null
       or l.id is null
       or l.organization_id is distinct from e.organization_id
  ) then
    raise exception 'Organization Ledger entries are not canonically attached to their Organization Ledger.';
  end if;

  if not exists (
    select 1
    from atlas.organization_ledger_entries e
    where e.id = '33333333-3333-4333-8333-333333333333'::uuid
      and e.event_key = 'ledger-validation-existing-entry'
      and e.revision = 4242
      and e.organization_id = '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and e.ledger_id = atlas.primary_ledger_for_organization_v1(e.organization_id)
  ) then
    raise exception 'Existing Organization Ledger entry identity/revision did not survive canonical Ledger backfill.';
  end if;

  select c.is_nullable
  into v_is_nullable
  from information_schema.columns c
  where c.table_schema = 'atlas'
    and c.table_name = 'organization_ledger_entries'
    and c.column_name = 'ledger_id';

  if v_is_nullable is distinct from 'NO' then
    raise exception 'Organization Ledger entry canonical ledger_id is not required.';
  end if;

  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'atlas'
      and c.table_name = 'ledger_entitlement_bindings'
      and c.column_name = 'ledger_id'
  ) then
    raise exception 'Commercial Ledger entitlement binding cannot refer to canonical Ledger.';
  end if;

  if exists (
    select 1
    from atlas.ledger_entitlement_bindings b
    join atlas.ledgers l on l.id = b.ledger_id
    where b.ledger_id is not null
      and b.organization_id is not null
      and l.organization_id is distinct from b.organization_id
  ) then
    raise exception 'Ledger entitlement binding has Organization / Ledger contradiction.';
  end if;

  if exists (
    select 1
    from atlas.principals p
    join atlas.ledgers l
      on l.organization_id = p.organization_id
     and l.ledger_kind = 'organization_governing'
     and l.status = 'active'
    left join atlas.principal_ledger_authorities a
      on a.principal_id = p.id
     and a.ledger_id = l.id
     and a.authority_kind = 'root_governing'
     and a.status = 'active'
    where p.status = 'active'
      and p.organization_id is not null
      and a.id is null
  ) then
    raise exception 'Legacy Principal Organization compatibility did not establish root Ledger authority.';
  end if;

  if not exists (
    select 1
    from atlas.principals p
    join atlas.principal_ledger_authorities a
      on a.principal_id = p.id
     and a.authority_kind = 'root_governing'
     and a.status = 'active'
    join atlas.ledgers l on l.id = a.ledger_id
    where p.stable_key = 'ledger_validation_principal'
      and p.person_id is not null
      and l.organization_id = p.organization_id
      and a.basis = 'legacy_principal_organization_compatibility'
  ) then
    raise exception 'Fixture Principal did not establish canonical Person-backed root Ledger authority.';
  end if;

  if not exists (
    select 1
    from atlas.ledgers l
    join atlas.organizations o on o.id = l.organization_id
    where o.stable_key = 'feast_guild'
      and l.metadata->>'scope_state' = 'legacy_mixed_pending_adjudication'
  ) then
    raise exception 'Historical Feast Guild scope was incorrectly presented as already adjudicated.';
  end if;

  if not exists (
    select 1
    from atlas.ledgers l
    join atlas.organizations o on o.id = l.organization_id
    where o.stable_key = 'ledger_validation_company'
      and l.metadata->>'scope_state' = 'canonical'
  ) then
    raise exception 'Ordinary Organization Ledger was not established as canonical scope.';
  end if;

  if exists (
    select 1
    from atlas.ledgers l
    join atlas.organizations o on o.id = l.organization_id
    where o.stable_key <> 'feast_guild'
      and l.metadata->>'scope_state' = 'legacy_mixed_pending_adjudication'
  ) then
    raise exception 'Legacy mixed scope marker leaked to an unrelated Organization Ledger.';
  end if;

  if not exists (
    select 1
    from atlas.organizations o
    join atlas.ledgers l on l.organization_id = o.id
    where not exists (
      select 1
      from atlas.ledger_entitlement_bindings b
      where b.ledger_id = l.id
    )
  ) then
    raise exception 'Ledger existence appears to depend on commercial entitlement bindings.';
  end if;

  select pg_get_functiondef('atlas.principal_ledgers_self_api_v1()'::regprocedure)
  into v_def;
  if position('atlas.current_principal_id_v1()' in v_def) = 0
     or position('principal_ledger_authorities' in v_def) = 0 then
    raise exception 'Principal Ledger self projection does not resolve through Person-first Principal plus explicit Ledger authority.';
  end if;

  select pg_get_functiondef('atlas.organization_ledger_scope_compatibility_v1()'::regprocedure)
  into v_def;
  if position('atlas.primary_ledger_for_organization_v1' in v_def) = 0
     or position('Organization / Ledger scope contradiction' in v_def) = 0 then
    raise exception 'Organization/Ledger compatibility guard is not installed.';
  end if;

  if has_table_privilege('anon','atlas.ledgers','SELECT')
     or has_table_privilege('authenticated','atlas.ledgers','SELECT')
     or has_table_privilege('anon','atlas.principal_ledger_authorities','SELECT')
     or has_table_privilege('authenticated','atlas.principal_ledger_authorities','SELECT') then
    raise exception 'First-class Ledger widened direct browser table access.';
  end if;

  if has_function_privilege('anon','atlas.primary_ledger_for_organization_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.primary_ledger_for_organization_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.principal_has_ledger_authority_v1(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.principal_has_ledger_authority_v1(uuid,uuid)','EXECUTE') then
    raise exception 'Internal Ledger authority helpers became directly browser-callable.';
  end if;

  if has_function_privilege('anon','atlas.principal_ledgers_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','atlas.principal_ledgers_self_api_v1()','EXECUTE') then
    raise exception 'Principal Ledger self API grants are incorrect.';
  end if;

  if to_regprocedure('atlas.organization_ledger_owner_recent_api_v1(uuid,integer)') is null
     or to_regprocedure('atlas.organization_ledger_owner_window_api_v1(uuid,timestamp with time zone,timestamp with time zone,bigint,integer)') is null then
    raise exception 'Existing Organization Ledger read compatibility APIs were removed.';
  end if;

  if exists (
    select 1
    from pg_indexes i
    where i.schemaname = 'atlas'
      and i.tablename = 'principal_ledger_authorities'
      and i.indexdef ilike 'create unique index% (principal_id)%'
      and i.indexdef not ilike '%ledger_id%'
  ) then
    raise exception 'Schema incorrectly restricts one Principal to one Ledger.';
  end if;
end;
$proof$;

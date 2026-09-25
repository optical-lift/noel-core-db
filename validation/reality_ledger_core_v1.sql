-- Atlas Reality / Ledger clean-room core validation v1.
-- Read-only checks; expected production state before first real cutover.

select
  to_regclass('reality.entities') as reality_entities,
  to_regclass('reality.auth_person_bindings') as auth_person_bindings,
  to_regclass('personal.atlases') as personal_atlases,
  to_regclass('ledger.onboarding_cases') as onboarding_cases,
  to_regclass('ledger.ledgers') as ledgers,
  to_regclass('ledger.seats') as seats,
  to_regclass('ledger.actions') as actions,
  to_regclass('ledger.observations') as observations,
  to_regclass('ledger.summaries') as summaries,
  to_regclass('ledger.connections') as connections,
  to_regclass('ledger.exposures') as exposures,
  to_regclass('compatibility.legacy_bindings') as legacy_bindings;

with legacy_fks as (
  select c.oid
  from pg_constraint c
  join pg_class src on src.oid=c.conrelid
  join pg_namespace sn on sn.oid=src.relnamespace
  join pg_class dst on dst.oid=c.confrelid
  join pg_namespace dn on dn.oid=dst.relnamespace
  where c.contype='f'
    and sn.nspname in ('reality','personal','ledger','compatibility')
    and dn.nspname in ('atlas','local_intel')
),
bad_grants as (
  select 1
  from information_schema.role_table_grants
  where table_schema in ('reality','personal','ledger','compatibility')
    and grantee in ('anon','authenticated','PUBLIC')
),
bad_function_exec as (
  select 1
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  cross join pg_roles r
  where n.nspname in ('reality','personal','ledger','compatibility')
    and r.rolname in ('anon','authenticated')
    and has_function_privilege(r.rolname,p.oid,'EXECUTE')
)
select
  (select count(*) from legacy_fks) as forbidden_legacy_fk_dependencies,
  (select count(*) from bad_grants) as direct_anon_authenticated_table_grants,
  (select count(*) from bad_function_exec) as anon_authenticated_function_exec,
  (select count(*) from reality.entities) as admitted_reality_entities,
  (select count(*) from ledger.ledgers) as activated_new_ledgers,
  (select count(*) from personal.atlases) as activated_personal_atlases;

-- Counts are informational after the first real cutover. The invariant is that the new core has no forbidden legacy foreign-key dependencies or direct anon/authenticated grants.

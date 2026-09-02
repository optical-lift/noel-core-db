-- Atlas security surface manifest generator
-- Baseline date: 2026-09-02
-- Project: noel-core (zirqkouammpwxlqfbsvf)
-- Run after migration 20260902223739_atlas_security_immediate_surface_hardening_v1.

with funcs as (
  select
    p.oid::regprocedure::text as signature,
    p.prosecdef,
    has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_exec
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
    )
), function_manifest as (
  select string_agg(
    format('function,%s,%s,%s,%s,%s', signature, prosecdef, anon_exec, auth_exec, service_exec),
    E'\n' order by signature
  ) as manifest
  from funcs
), rels as (
  select
    case c.relkind
      when 'r' then 'table'
      when 'p' then 'partitioned_table'
      when 'v' then 'view'
      when 'm' then 'materialized_view'
      else c.relkind::text
    end as kind,
    c.relname,
    has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
    has_table_privilege('anon', c.oid, 'INSERT') as anon_insert,
    has_table_privilege('anon', c.oid, 'UPDATE') as anon_update,
    has_table_privilege('anon', c.oid, 'DELETE') as anon_delete,
    has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
    has_table_privilege('authenticated', c.oid, 'INSERT') as auth_insert,
    has_table_privilege('authenticated', c.oid, 'UPDATE') as auth_update,
    has_table_privilege('authenticated', c.oid, 'DELETE') as auth_delete
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'atlas'
    and c.relkind in ('r','p','v','m')
    and (
      has_table_privilege('anon', c.oid, 'SELECT')
      or has_table_privilege('anon', c.oid, 'INSERT')
      or has_table_privilege('anon', c.oid, 'UPDATE')
      or has_table_privilege('anon', c.oid, 'DELETE')
      or has_table_privilege('authenticated', c.oid, 'SELECT')
      or has_table_privilege('authenticated', c.oid, 'INSERT')
      or has_table_privilege('authenticated', c.oid, 'UPDATE')
      or has_table_privilege('authenticated', c.oid, 'DELETE')
    )
), relation_manifest as (
  select string_agg(
    format('%s,atlas.%s,%s,%s,%s,%s,%s,%s,%s,%s',
      kind, relname,
      anon_select, anon_insert, anon_update, anon_delete,
      auth_select, auth_insert, auth_update, auth_delete
    ),
    E'\n' order by kind, relname
  ) as manifest
  from rels
)
select jsonb_build_object(
  'functionRows', (select count(*) from funcs),
  'functionSha256', (
    select encode(extensions.digest(convert_to(manifest, 'UTF8'), 'sha256'), 'hex')
    from function_manifest
  ),
  'relationRows', (select count(*) from rels),
  'relationSha256', (
    select encode(extensions.digest(convert_to(manifest, 'UTF8'), 'sha256'), 'hex')
    from relation_manifest
  ),
  'combinedSha256', (
    select encode(
      extensions.digest(
        convert_to(
          (select manifest from function_manifest)
          || E'\n--RELATIONS--\n'
          || (select manifest from relation_manifest),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    )
  ),
  'functionManifest', (select manifest from function_manifest),
  'relationManifest', (select manifest from relation_manifest)
) as atlas_security_surface_manifest;

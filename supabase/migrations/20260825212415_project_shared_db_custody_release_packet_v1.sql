create or replace function public.shared_db_custody_release_packet_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
with migration_rows as (
  select
    version,
    name,
    array_to_string(statements, E'\n') as body
  from supabase_migrations.schema_migrations
),
prefix_rows as (
  select
    version,
    name,
    body,
    encode(extensions.digest(convert_to(body, 'UTF8'), 'sha256'), 'hex') as body_sha256
  from migration_rows
  where version <= '20260825203448'
),
prefix as (
  select
    count(*)::int as migration_count,
    min(version) as first_version,
    max(version) as through_version,
    encode(
      extensions.digest(
        convert_to(
          string_agg(
            version || E'\t' || coalesce(name, '') || E'\t' || body_sha256,
            E'\n'
            order by version
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ) as ledger_sha256
  from prefix_rows
),
post_fence as (
  select
    version,
    name,
    encode(
      extensions.digest(
        convert_to('blob ' || octet_length(convert_to(body, 'UTF8'))::text, 'UTF8')
        || decode('00', 'hex')
        || convert_to(body, 'UTF8'),
        'sha1'
      ),
      'hex'
    ) as git_blob_sha1
  from migration_rows
  where version > '20260825203448'
),
current_ledger as (
  select
    count(*)::int as migration_count,
    max(version) as latest_version
  from migration_rows
)
select jsonb_build_object(
  'contractVersion', 1,
  'projectRef', 'zirqkouammpwxlqfbsvf',
  'fence', jsonb_build_object(
    'migrationCount', prefix.migration_count,
    'firstVersion', prefix.first_version,
    'throughVersion', prefix.through_version,
    'ledgerSha256', prefix.ledger_sha256
  ),
  'current', jsonb_build_object(
    'migrationCount', current_ledger.migration_count,
    'latestVersion', current_ledger.latest_version
  ),
  'postFence', coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'version', version,
          'name', name,
          'gitBlobSha1', git_blob_sha1
        )
        order by version
      )
      from post_fence
    ),
    '[]'::jsonb
  )
)
from prefix
cross join current_ledger;
$$;
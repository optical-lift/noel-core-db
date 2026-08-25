with migrations as (
  select
    version,
    name,
    array_to_string(statements, E'\n') as body
  from supabase_migrations.schema_migrations
),
row_hashes as (
  select
    version,
    name,
    encode(extensions.digest(convert_to(body, 'UTF8'), 'sha256'), 'hex') as body_sha256
  from migrations
),
ledger as (
  select
    count(*)::int as migration_count,
    min(version) as first_version,
    max(version) as latest_version,
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
  from row_hashes
),
latest as (
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
    ) as git_blob_sha1,
    encode(extensions.digest(convert_to(body, 'UTF8'), 'sha256'), 'hex') as body_sha256
  from migrations
  order by version desc
  limit 1
)
select jsonb_build_object(
  'projectRef', 'zirqkouammpwxlqfbsvf',
  'postgresVersion', current_setting('server_version'),
  'migrationCount', ledger.migration_count,
  'firstVersion', ledger.first_version,
  'throughVersion', ledger.latest_version,
  'throughName', latest.name,
  'throughBodyGitBlobSha1', latest.git_blob_sha1,
  'throughBodySha256', latest.body_sha256,
  'ledgerSha256', ledger.ledger_sha256
) as production_baseline
from ledger
cross join latest;

#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"

if [ -z "${NOEL_CORE_DATABASE_URL:-}" ]; then
  echo "NOEL_CORE_DATABASE_URL is required for live production custody verification."
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required for live production custody verification."
  exit 2
fi

readarray -t expected < <(python3 - <<'PY'
import json
from pathlib import Path

data = json.loads(Path('custody/production-baseline-v1.json').read_text())
print(data['inheritedHistory']['migrationCount'])
print(data['inheritedHistory']['firstVersion'])
print(data['inheritedHistory']['throughVersion'])
print(data['inheritedHistory']['ledgerSha256'])
PY
)

expected_count="${expected[0]}"
expected_first="${expected[1]}"
fence_version="${expected[2]}"
expected_prefix_hash="${expected[3]}"

prefix_row="$({
  psql "$NOEL_CORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -At -F '|' <<SQL
with migrations as (
  select
    version,
    name,
    array_to_string(statements, E'\\n') as body
  from supabase_migrations.schema_migrations
  where version <= '$fence_version'
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
            version || E'\\t' || coalesce(name, '') || E'\\t' || body_sha256,
            E'\\n'
            order by version
          ),
          'UTF8'
        ),
        'sha256'
      ),
      'hex'
    ) as ledger_sha256
  from row_hashes
)
select migration_count, first_version, latest_version, ledger_sha256
from ledger;
SQL
} | tr -d '\r')"

IFS='|' read -r live_count live_first live_fence live_prefix_hash <<< "$prefix_row"

if [ "$live_count" != "$expected_count" ] || \
   [ "$live_first" != "$expected_first" ] || \
   [ "$live_fence" != "$fence_version" ] || \
   [ "$live_prefix_hash" != "$expected_prefix_hash" ]; then
  echo "Inherited production migration fence no longer matches the frozen baseline."
  echo "Expected: count=$expected_count first=$expected_first fence=$fence_version hash=$expected_prefix_hash"
  echo "Live:     count=$live_count first=$live_first fence=$live_fence hash=$live_prefix_hash"
  exit 1
fi

bad=0
while IFS='|' read -r version name production_blob_sha; do
  [ -z "$version" ] && continue

  file="supabase/migrations/${version}_${name}.sql"
  if [ ! -f "$file" ]; then
    echo "Unauthorized or uncustodied live post-fence migration: ${version}_${name}"
    echo "Expected canonical source file: $file"
    bad=1
    continue
  fi

  repository_blob_sha="$(git hash-object "$file")"
  if [ "$repository_blob_sha" != "$production_blob_sha" ]; then
    echo "Live post-fence migration bytes do not match canonical source: $file"
    echo "Repository Git blob: $repository_blob_sha"
    echo "Production Git blob: $production_blob_sha"
    bad=1
  fi
done < <(
  psql "$NOEL_CORE_DATABASE_URL" -X -v ON_ERROR_STOP=1 -At -F '|' <<SQL
with migrations as (
  select
    version,
    name,
    array_to_string(statements, E'\\n') as body
  from supabase_migrations.schema_migrations
  where version > '$fence_version'
)
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
from migrations
order by version;
SQL
)

if [ "$bad" -ne 0 ]; then
  exit 1
fi

echo "Live production custody passed: inherited fence is unchanged and every post-fence live migration has exact canonical source in noel-core-db."

#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]{14}$ ]]; then
  echo "Usage: $0 <14-digit-migration-version>" >&2
  exit 2
fi

if [ -z "${NOEL_CORE_DATABASE_URL:-}" ]; then
  echo "NOEL_CORE_DATABASE_URL is required." >&2
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required for production migration release." >&2
  exit 2
fi

shopt -s nullglob
matches=(supabase/migrations/"${version}"_*.sql)
shopt -u nullglob

if [ "${#matches[@]}" -ne 1 ]; then
  echo "Expected exactly one canonical migration for version $version; found ${#matches[@]}." >&2
  exit 1
fi

migration="${matches[0]}"
base="$(basename "$migration")"
name="${base#${version}_}"
name="${name%.sql}"

if [[ ! "$name" =~ ^[a-z0-9_]+$ ]]; then
  echo "Migration name is not safe for governed release: $name" >&2
  exit 1
fi

repository_blob="$(git hash-object "$migration")"
if [[ ! "$repository_blob" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Unable to compute canonical Git blob for $migration." >&2
  exit 1
fi

export PGAPPNAME="noel-core-db-production-release"

read_live_row() {
  psql "$NOEL_CORE_DATABASE_URL" \
    -X -v ON_ERROR_STOP=1 -A -t -F '|' \
    -c "select coalesce(name,''), encode(extensions.digest(convert_to('blob ' || octet_length(convert_to(array_to_string(statements, E'\\n'),'UTF8'))::text,'UTF8') || decode('00','hex') || convert_to(array_to_string(statements, E'\\n'),'UTF8'),'sha1'),'hex') from supabase_migrations.schema_migrations where version='${version}';"
}

existing="$(read_live_row)"
if [ -n "$existing" ]; then
  existing_name="${existing%%|*}"
  existing_blob="${existing#*|}"
  if [ "$existing_name" = "$name" ] && [ "$existing_blob" = "$repository_blob" ]; then
    echo "Already released exactly: ${version}_${name} (${repository_blob})."
    exit 0
  fi

  echo "Production already contains migration version $version with different custody." >&2
  echo "Expected: name=$name blob=$repository_blob" >&2
  echo "Live:     name=$existing_name blob=$existing_blob" >&2
  exit 1
fi

name_collision="$(
  psql "$NOEL_CORE_DATABASE_URL" \
    -X -v ON_ERROR_STOP=1 -A -t \
    -c "select version from supabase_migrations.schema_migrations where name='${name}' order by version limit 1;"
)"
if [ -n "$name_collision" ]; then
  echo "Production already contains migration name $name at version $name_collision; refusing a duplicate name." >&2
  exit 1
fi

release_sha="${GITHUB_RELEASE_SHA:-manual}"
if [[ "$release_sha" != "manual" && ! "$release_sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "GITHUB_RELEASE_SHA must be a 40-character Git SHA when supplied." >&2
  exit 1
fi
created_by="github-actions:noel-core-db@${release_sha}"

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

python3 - "$migration" "$version" "$name" "$created_by" "$tmp_sql" <<'PY'
import hashlib
import re
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
version = sys.argv[2]
name = sys.argv[3]
created_by = sys.argv[4]
out_path = Path(sys.argv[5])

raw = source_path.read_bytes()
try:
    body = raw.decode('utf-8')
except UnicodeDecodeError as exc:
    raise SystemExit(f"Migration must be UTF-8: {exc}")

# The current noel-core-db convention makes each canonical migration own its
# transaction. Keep that boundary and place the ledger receipt immediately
# before the terminal COMMIT so schema change + custody receipt are atomic.
without_line_comments = re.sub(r'(?m)^\s*--.*$', '', body).lstrip()
if not re.match(r'(?i)^begin\s*;', without_line_comments):
    raise SystemExit('Governed production release requires the migration to begin with BEGIN;')

terminal = re.search(r'(?is)\bcommit\s*;\s*\Z', body)
if terminal is None:
    raise SystemExit('Governed production release requires a terminal COMMIT;')

sha = hashlib.sha256(raw).hexdigest()
tag_name = f"noel_core_migration_{sha}"
tag = f"${tag_name}$"
if tag in body:
    raise SystemExit('Generated migration-body dollar quote unexpectedly occurs in source body')

# Inputs are already constrained by the shell to digits / [a-z0-9_] / a fixed
# created-by prefix plus a Git SHA or literal "manual".
receipt = (
    "insert into supabase_migrations.schema_migrations "
    "(version, statements, name, created_by) values (\n"
    f"  '{version}',\n"
    f"  array[{tag}{body}{tag}],\n"
    f"  '{name}',\n"
    f"  '{created_by}'\n"
    ");\n"
    "commit;\n"
)

governed_sql = body[:terminal.start()] + receipt
out_path.write_text(governed_sql, encoding='utf-8', newline='')
PY

# ON_ERROR_STOP turns any SQL error into a failed release. The migration's own
# transaction now also contains the exact canonical ledger receipt.
psql "$NOEL_CORE_DATABASE_URL" \
  -X -v ON_ERROR_STOP=1 \
  --file "$tmp_sql"

released="$(read_live_row)"
if [ -z "$released" ]; then
  echo "Migration executed but no production custody row was found for $version." >&2
  exit 1
fi

released_name="${released%%|*}"
released_blob="${released#*|}"
if [ "$released_name" != "$name" ] || [ "$released_blob" != "$repository_blob" ]; then
  echo "Production release receipt does not match canonical source." >&2
  echo "Expected: name=$name blob=$repository_blob" >&2
  echo "Live:     name=$released_name blob=$released_blob" >&2
  exit 1
fi

echo "Released exactly: ${version}_${name} (${repository_blob})."

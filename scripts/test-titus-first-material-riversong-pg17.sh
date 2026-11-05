#!/usr/bin/env bash
# Titus original Course material and revisions — single disposable PG17 proof.
# request.jwt.claims are unsigned synthetic values, NOT genuine GoTrue proof.
# No local Atlas clone, real GoTrue instance or Supabase connection.
set -Eeuo pipefail
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]] || {
  echo "This proof is restricted to the Intel macOS RiverSong runner." >&2
  exit 2
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_dir="$root/candidates/titus-customer-workspace-first-course-v1"
sql_dir="$root/candidates/titus-first-draft-material-v1"
for f in "$source_dir/fixture.sql" "$source_dir/candidate.sql" "$sql_dir/candidate.sql" "$sql_dir/clone_validation.sql" "$sql_dir/postconditions.sql"; do
  test -s "$f" || { echo "Missing $f" >&2; exit 2; }
done
bin=""
for choice in \
  "/Applications/Postgres.app/Contents/Versions/17/bin" \
  "$HOME/Applications/Postgres.app/Contents/Versions/17/bin" \
  "/Applications/Postgres.app/Contents/Versions/latest/bin"; do
  if [[ -x "$choice/initdb" && -x "$choice/psql" && -x "$choice/pg_ctl" ]]; then
    bin="$choice"
    break
  fi
done
[[ -n "$bin" && "$("$bin/pg_ctl" --version)" == *"PostgreSQL) 17."* ]] || {
  echo "Postgres.app 17 unavailable, refusing protected-clone fallback" >&2
  exit 2
}
scratch="$(mktemp -d /tmp/noel-titus-first-material.XXXXXXXX)"
chmod 700 "$scratch"
real_scratch="$(cd "$scratch" && pwd -P)"
data="$real_scratch/data"
socket="$real_scratch/socket"
log="$real_scratch/server.log"
port=55449
started=false
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    "$bin/pg_ctl" -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/noel-titus-first-material.* && -d "$scratch" ]]; then
    rm -rf -- "$scratch"
  else
    echo "Unsafe scratch path, refusing deletion." >&2
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM
mkdir -p "$socket"
chmod 700 "$socket"
"$bin/initdb" -D "$data" -U postgres -A trust --no-instructions >/dev/null
cat >>"$data/postgresql.conf" <<EOF
listen_addresses = ''
unix_socket_directories = '$socket'
port = $port
max_connections = 16
shared_buffers = '64MB'
fsync = off
EOF
"$bin/pg_ctl" -D "$data" -l "$log" -w start >/dev/null
started=true
unset PGHOST PGHOSTADDR PGPORT PGUSER PGDATABASE PGOPTIONS PGSSLMODE
unset DATABASE_URL NOEL_CORE_DATABASE_URL SUPABASE_DB_URL || true
psql_local() {
  "$bin/psql" -X -v ON_ERROR_STOP=1 \
    -h "$socket" -p "$port" -U postgres -d postgres "$@"
}
actual="$(psql_local -Atqc "SELECT current_setting('data_directory'),
  inet_server_addr() IS NULL,
  current_setting('server_version_num')::integer >= 170000;")"
expected="$data|t|t"
[[ "$actual" == "$expected" ]] || {
  echo "Refusing database identity mismatch." >&2
  exit 3
}
echo "Verified NEW RiverSong PG17 on private socket 55449, not Atlas protected 55432."
psql_local -f "$source_dir/fixture.sql"
psql_local -f "$source_dir/candidate.sql"
psql_local -f "$sql_dir/candidate.sql"
psql_local -f "$sql_dir/clone_validation.sql"
psql_local -f "$sql_dir/postconditions.sql"
echo "PASS: synthetic owner creates original Course material, reopens and revises without overwriting; replay idempotency, stale/outside/revoked/expired denial, no direct grants. Unsigned synthetic Auth fixture only, no live writes."

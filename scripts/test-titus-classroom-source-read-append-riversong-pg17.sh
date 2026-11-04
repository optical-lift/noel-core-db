#!/usr/bin/env bash
# Noel-owned source candidate: RiverSong disposable PostgreSQL 17 only.
# No local Atlas clone, real GoTrue instance or Supabase connection.
set -Eeuo pipefail
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]] || {
  echo "This proof is restricted to the Intel macOS RiverSong runner." >&2
  exit 2
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
sql_dir="$root/candidates/titus-classroom-source-read-append-v1"
for name in fixture.sql frozen_titus_event_core.sql thread_seed.sql candidate.sql postconditions.sql; do
  test -s "$sql_dir/$name" || { echo "Missing $name" >&2; exit 2; }
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
scratch="$(mktemp -d /tmp/noel-titus-read-append.XXXXXXXX)"
chmod 700 "$scratch"
real_scratch="$(cd "$scratch" && pwd -P)"
data="$real_scratch/data"
socket="$real_scratch/socket"
log="$real_scratch/server.log"
port=55439
started=false
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    "$bin/pg_ctl" -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/noel-titus-read-append.* && -d "$scratch" ]]; then
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
echo "Verified NEW RiverSong PG17 on private socket 55439, not Atlas protected 55432."
test -s "$root/candidates/titus-classroom-pilot-signed-participation-v1/candidate.sql"
psql_local -f "$sql_dir/fixture.sql"
psql_local -f "$sql_dir/frozen_titus_event_core.sql"
psql_local -f "$sql_dir/thread_seed.sql"
psql_local -f "$root/candidates/titus-classroom-pilot-signed-participation-v1/candidate.sql"
psql_local -f "$sql_dir/candidate.sql"
psql_local -f "$sql_dir/postconditions.sql"
closed="$(psql_local -Atqc "SELECT titus.classroom_pilot_assignment_issued_v1(
  '00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000202','teacher',
  '00000000-0000-4000-8000-000000000302');")"
[[ "$closed" == "f" ]] || {
  echo "FATAL: source issuer not restored to hard false." >&2
  exit 3
}
[[ "$(psql_local -Atqc 'SELECT titus.classroom_authority_gate_v1();')" == "f" ]] || {
  echo "FATAL: event writer source gate remains open." >&2; exit 3;
}
echo "PASS: exact source read/append, six-event original/revision history, stale/idempotent/role denials; both gates closed."

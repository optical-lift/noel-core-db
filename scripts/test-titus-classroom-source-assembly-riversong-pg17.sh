#!/usr/bin/env bash
# Noel source release ASSEMBLY proof: ONE fresh RiverSong PG17 only.
# request.jwt.claims are unsigned synthetic values, NOT genuine GoTrue proof.
# No local Atlas clone, real GoTrue instance or Supabase connection.
set -Eeuo pipefail
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]] || {
  echo "This proof is restricted to the Intel macOS RiverSong runner." >&2
  exit 2
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
sql_dir="$root/candidates/titus-classroom-source-assembly-v1"
session="$root/candidates/titus-classroom-session-binding-1g-b"
for name in candidate.sql fixture_atlas_before_bundle.sql fixture_parts_after_bundle.sql; do
  test -s "$sql_dir/$name" || { echo "Missing $name" >&2; exit 2; }
done
for name in fixture_session_tables.sql postconditions.sql; do
  test -s "$session/$name" || { echo "Missing inherited $name" >&2; exit 2; }
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
scratch="$(mktemp -d /tmp/noel-titus-source-bundle.XXXXXXXX)"
chmod 700 "$scratch"
real_scratch="$(cd "$scratch" && pwd -P)"
data="$real_scratch/data"
socket="$real_scratch/socket"
log="$real_scratch/server.log"
port=55445
started=false
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    "$bin/pg_ctl" -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/noel-titus-source-bundle.* && -d "$scratch" ]]; then
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
echo "Verified NEW RiverSong PG17 on private socket 55445, not Atlas protected 55432."
base="$root/candidates/titus-classroom-source-read-append-v1"
test -s "$base/fixture.sql"
test -s "$base/thread_seed.sql"
psql_local -f "$base/fixture.sql"
# The governed Atlas Teaching fixture must exist before the source bundle
# declares its actual Atlas foreign-key references. Its classroom part rows
# are separated because the parts table does not exist until the bundle.
psql_local -f "$sql_dir/fixture_atlas_before_bundle.sql"
# Actual single transaction candidate; not four separate PG17 source copies.
psql_local -f "$sql_dir/candidate.sql"
psql_local -f "$base/thread_seed.sql"
psql_local -f "$sql_dir/fixture_parts_after_bundle.sql"
# Claims remain UNVERIFIED synthetic inputs; no real GoTrue users are minted.
psql_local -f "$session/fixture_session_tables.sql"
psql_local -f "$session/postconditions.sql"
closed="$(psql_local -Atqc "SELECT titus.classroom_pilot_assignment_issued_v1(
  '00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000202','teacher',
  (SELECT assignment_receipt_id FROM titus.classroom_pilot_participation_v1
   WHERE actor_role='teacher' AND thread_id='00000000-0000-4000-8000-000000000100'));")"
[[ "$closed" == "f" ]] || {
 echo "FATAL: withdrawn sample learner retained teacher authority." >&2
 exit 3
}
[[ "$(psql_local -Atqc 'SELECT titus.classroom_authority_gate_v1();')" == "f" ]] || {
 echo "FATAL: source writer gate open." >&2; exit 3;
}
echo "PASS: one assembled source DDL transaction loaded and signed-Person source-shape fixture tests passed; writer stays false; JWT claims UNVERIFIED; no Teaching activation or owner created."

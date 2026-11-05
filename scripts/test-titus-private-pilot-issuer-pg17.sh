#!/usr/bin/env bash
# Titus private-pilot issuer — single disposable PG17 proof.
# request.jwt.claims are unsigned synthetic values, NOT genuine GoTrue proof.
# No local Atlas clone, real GoTrue instance or Supabase connection.
set -Eeuo pipefail
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]] || {
  echo "This proof is restricted to the Intel macOS RiverSong runner." >&2
  exit 2
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_dir="$root/candidates/titus-customer-workspace-first-course-v1"
issuer="$root/scripts/titus-private-pilot-issue.sql"
for f in "$source_dir/fixture.sql" "$source_dir/candidate.sql" "$issuer"; do
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
scratch="$(mktemp -d /tmp/noel-titus-private-pilot.XXXXXXXX)"
chmod 700 "$scratch"
real_scratch="$(cd "$scratch" && pwd -P)"
data="$real_scratch/data"
socket="$real_scratch/socket"
log="$real_scratch/server.log"
port=55452
started=false
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    "$bin/pg_ctl" -D "$data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/noel-titus-private-pilot.* && -d "$scratch" ]]; then
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
echo "Verified NEW RiverSong PG17 on private socket 55452, not Atlas protected 55432."
psql_local -f "$source_dir/fixture.sql"
psql_local -f "$source_dir/candidate.sql"
psql_local -q -c "
UPDATE auth.users SET email='lexprjct@gmail.com'
 WHERE id='00000000-0000-4000-8000-000000000101';
UPDATE auth.users SET email='outsider@example.test'
 WHERE id='00000000-0000-4000-8000-000000000102';
"
receipt='github:optical-lift/noel-core-db/issues/2489#titus-private-pilot-v1'
issue_as_pilot() {
  psql_local -Atq -v pilot_email="$1" -v pilot_receipt="$2" -v pilot_days="$3" -f "$issuer"
}
# Exactly one existing verified Auth target, no seeded university or Course.
before="$(psql_local -Atqc 'select count(*) from titus.customer_workspace_entitlements_v1;')"
[[ "$before" == '0' ]] || { echo "Issuer test fixture wasn't empty." >&2; exit 3; }
proof="$(issue_as_pilot 'lexprjct@gmail.com' "$receipt" '180')"
[[ "$proof" == *'1|1|0|0'* ]] || {
 echo "First issuer receipt mismatch (no details printed)." >&2; exit 3;
}
# Reissuing exact owner receipt must be idempotent; no second grant.
proof="$(issue_as_pilot 'lexprjct@gmail.com' "$receipt" '180')"
[[ "$proof" == *'1|1|0|0'* ]] || { echo "Pilot replay changed state." >&2; exit 3; }

deny() {
  if issue_as_pilot "$1" "$2" "$3" >"$real_scratch/denied.log" 2>&1; then
    echo "Unauthorized pilot request was accepted." >&2
    exit 4
  fi
}
deny 'unknown@example.test' 'github:optical-lift/noel-core-db/issues/2490#titus-private-pilot-v1' 180
deny 'outsider@example.test' "$receipt" 180
deny 'lexprjct@gmail.com' 'github:optical-lift/noel-core-db/issues/2491#titus-private-pilot-v1' 180
deny 'lexprjct@gmail.com' 'not-source-approved' 180
deny 'lexprjct@gmail.com' "$receipt" 365
# Missing confirmation / deleted users are not eligible.
psql_local -q -c "UPDATE auth.users SET email_confirmed_at=NULL,deleted_at=now()
 WHERE id='00000000-0000-4000-8000-000000000102';"
deny 'outsider@example.test' 'github:optical-lift/noel-core-db/issues/2492#titus-private-pilot-v1' 180
# Withdrawn grant cannot be resurrected just by replaying old receipt.
psql_local -q -c "UPDATE titus.customer_workspace_entitlements_v1 SET state='revoked'
 WHERE grant_source_receipt='$receipt';"
deny 'lexprjct@gmail.com' "$receipt" 180

count="$(psql_local -Atqc 'select count(*) from titus.customer_workspace_entitlements_v1;')"
state="$(psql_local -Atqc "select state from titus.customer_workspace_entitlements_v1 where grant_source_receipt='$receipt';")"
[[ "$count" == '1' && "$state" == 'revoked' ]] || {
 echo "Failed cases changed unauthorized grants." >&2; exit 4;
}
echo "PASS: approved owner private-pilot grant, exact eligible Auth target, idempotent receipt, other-user/unknown/conflict/invalid/expired/deleted denials, revoked replay denial; all in disposable PG17; no production mutations."

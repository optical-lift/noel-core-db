#!/usr/bin/env bash
# Manual smoke test of the exact draft against a DISPOSABLE LOCAL Supabase DB.
# Never runs against a production URL or creates a versioned migration receipt.
# Requires a production-SCHEMA-SHAPED local clone already started on 54322.
# This script applies candidate + postconditions inside ONE transaction,
# then ROLLBACK; it never commits the draft and never changes live Noel data.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
candidate="$here/release_candidate.sql"
validation="$here/release_postconditions.sql"
port=54322
host=127.0.0.1
test -s "$candidate" || { echo "FAIL: Missing exact candidate SQL" >&2; exit 2; }
test -s "$validation" || { echo "FAIL: Missing exact postconditions" >&2; exit 2; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed" >&2; exit 2; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not installed" >&2; exit 2; }
if [ "$(head -n 1 "$candidate")" != 'BEGIN;' ] ||
   [ "$(tail -n 1 "$candidate")" != 'COMMIT;' ]; then
  echo "FAIL: unexpected candidate transaction boundaries" >&2
  exit 2
fi
if ! python3 - "$host" "$port" <<'PY'
import socket,sys
try:
    sock=socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=2)
    sock.close()
except OSError:
    sys.exit(1)
PY
then
  echo "FAIL: no disposable local Supabase Postgres on 127.0.0.1:54322" >&2
  exit 2
fi
umask 077
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
export PGCONNECT_TIMEOUT=5
if ! psql "$url" -X -A -t -v ON_ERROR_STOP=1 -c \
  "SELECT CASE WHEN to_regclass('atlas.work_items') IS NOT NULL
     AND to_regclass('atlas.rhythm_state') IS NOT NULL
     AND to_regclass('atlas.care_result_events') IS NOT NULL
     AND to_regclass('atlas.household_need_occurrences_v1') IS NOT NULL
     THEN 'ready' ELSE 'missing' END" > "$tmpdir/schema.txt" 2>&1; then
  echo "FAIL: local database unavailable or authentication differs from standard local Supabase" >&2
  exit 2
fi
if [ "$(tail -n 1 "$tmpdir/schema.txt")" != ready ]; then
  echo "FAIL: local database lacks required existing Atlas source schemas" >&2
  exit 2
fi
# Run every statement in a single local PostgreSQL transaction. Remove only
# the exact candidate's BEGIN and COMMIT sentinel lines.
{
  printf 'BEGIN;\n'
  sed '1d;$d' "$candidate"
  cat "$validation"
  printf '\nROLLBACK;\n'
} > "$tmpdir/test.sql"
echo 'Running draft DDL and pre-release postconditions in one LOCAL rollback transaction...'
if psql "$url" -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose \
    -f "$tmpdir/test.sql" > "$tmpdir/test.log" 2>&1; then
  echo 'PASS: candidate and postconditions executed on local schema; transaction ROLLED BACK.'
  echo 'NOTE: this is NOT real signed governor/worker/outsider or Today-browser acceptance.'
else
  echo 'FAIL: candidate compile/postcondition failed; no draft DDL committed.'
  echo 'Relevant end of local log (review before sharing):'
  tail -n 22 "$tmpdir/test.log"
  exit 1
fi

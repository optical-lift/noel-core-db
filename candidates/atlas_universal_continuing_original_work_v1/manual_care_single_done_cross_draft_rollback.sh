#!/usr/bin/env bash
# Held two-draft integration proof; protected local schema clone ONLY.
# Usage: bash manual_care_single_done_cross_draft_rollback.sh /path/to/noel-pr2368-checkout
# Must NOT be run against live Noel, real Elm records, or a production URL.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
other="${1:-}"
if [[ -z "$other" || ! -f "$other/candidates/atlas_universal_work_lifecycle_v1/04_shadow_release_candidate.sql" ]]; then
  echo "Provide a local checkout of the exact held PR #2368 source" >&2
  exit 2
fi
shadow="$other/candidates/atlas_universal_work_lifecycle_v1"
continuing="$here/release_candidate.sql"
port=54322
host=127.0.0.1
command -v psql >/dev/null || { echo "psql required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }
if [[ "$(head -n 1 "$continuing")" != 'BEGIN;' ||
      "$(tail -n 1 "$continuing")" != 'COMMIT;' ||
      "$(tail -n 1 "$shadow/04_shadow_release_candidate.sql")" != 'COMMIT;' ]]; then
  echo "Unknown transaction boundaries; refusing" >&2
  exit 2
fi
python3 - "$host" "$port" <<'PY'
import socket,sys
try:
    with socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=2):
        pass
except OSError:
    sys.exit('No local disposable Supabase PostgreSQL on 127.0.0.1:54322')
PY
url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{
  echo 'BEGIN;'
  # Exact source snapshot before mutation; all changes rolled back.
  sed '1d;$d' "$shadow/04_shadow_release_candidate.sql"
  cat "$shadow/06_single_transition_authority_private.sql"
  sed '1d;$d' "$continuing"
  cat "$here/10_care_actual_single_done_cutover_candidate.sql"
  cat "$here/11_care_single_done_cross_draft_postconditions.sql"
  echo 'ROLLBACK;'
} > "$tmp/integration.sql"
echo 'Running two draft candidates in ONE local transaction; final ROLLBACK...'
if psql "$url" -X -v ON_ERROR_STOP=1 -v VERBOSITY=terse -f "$tmp/integration.sql" > "$tmp/run.log" 2>&1; then
  echo 'PASS: two candidates compiled and source postconditions passed; ALL ROLLED BACK'
  echo 'NOT PROVEN: signed positive GoTrue worker, negative outsider, Today, or successor release'
else
  echo 'FAIL: no schema or Work retained; inspect bounded error log' >&2
  tail -n 22 "$tmp/run.log" >&2
  exit 1
fi

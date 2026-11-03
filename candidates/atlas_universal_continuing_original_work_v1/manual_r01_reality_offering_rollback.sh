#!/usr/bin/env bash
# R01 NOEL standing care: disposable LOCAL PostgreSQL only, one ROLLBACK.
# Refuses nonlocal targets, missing source or missing protected schema.
# Prerequisite: a disposable production-schema-shaped clone containing the
# held Noel #2368 universal lifecycle. No real Person/session replay.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
candidate="$here/r01_reality_offering_release_candidate.sql"
post="$here/r01_reality_offering_postconditions.sql"
for src in "$candidate" "$post"; do
  test -s "$src" || { echo "Missing held source: $src" >&2; exit 2; }
done
command -v psql >/dev/null || { echo "Install psql to run this local test" >&2; exit 2; }
head -n 1 "$candidate" | grep -qx 'BEGIN;' || { echo "Unexpected SQL begin marker" >&2; exit 2; }
tail -n 1 "$candidate" | grep -qx 'COMMIT;' || { echo "Unexpected SQL end marker" >&2; exit 2; }
export PGCONNECT_TIMEOUT=4
url="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
# No production/project URL, no remote host, no alternate port.
check="$(psql "$url" -X -A -t -v ON_ERROR_STOP=1 -c "
 select case when to_regclass('atlas.work_items') is not null
 and to_regclass('atlas.rhythm_state') is not null
 and to_regclass('atlas.work_lifecycle_events_v1') is not null
 and to_regprocedure('atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)') is not null
 then 'ready' else 'missing' end;" 2>/dev/null)" || {
 echo "No disposable local schema at 127.0.0.1:54322" >&2; exit 2;
}
test "$check" = ready || {
 echo "Local clone missing canonical work/rhythm/held one-Done prerequisite" >&2; exit 2;
}
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{
  printf 'BEGIN;\n'
  sed '1d;$d' "$candidate"
  printf '\n'
  cat "$post"
  printf '\nROLLBACK;\n'
} > "$tmp/rollback.sql"
if psql "$url" -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose \
 -f "$tmp/rollback.sql" > "$tmp/result.log" 2>&1; then
 echo "PASS: assembled R01 candidate and structural postconditions; ROLLBACK complete."
 echo "NOT PROVEN: signed source authorization, actual-to-next Work, Anna Today, or production release."
else
 echo "FAIL: local candidate/postconditions; no code or data committed."
 tail -n 25 "$tmp/result.log"
 exit 1
fi

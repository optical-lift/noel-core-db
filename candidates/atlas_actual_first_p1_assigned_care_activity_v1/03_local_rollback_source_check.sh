#!/usr/bin/env bash
# SOURCE COMPILE ONLY. No signed actor test, no migration.
# Intentionally rejects remote connections; use a VERIFIED local disposable
# production-shaped PG clone on RiverSong, not a production tunnel.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${P1_DISPOSABLE_CONFIRM:-}" != "ROLLBACK_ONLY" ]]; then
  echo "STOP: Set P1_DISPOSABLE_CONFIRM=ROLLBACK_ONLY only for an independently verified disposable local clone" >&2
  exit 2
fi
if [[ -z "${P1_DISPOSABLE_PGURI:-}" ]]; then
  echo "STOP: Set P1_DISPOSABLE_PGURI to your local disposable clone, not production" >&2
  exit 2
fi
case "${P1_DISPOSABLE_PGURI}" in
  *localhost*|*127.0.0.1*|*host=/*) ;;
  *) echo "STOP: Remote/tunneled/ambiguous PostgreSQL URI refused" >&2; exit 2 ;;
esac
if ! command -v psql >/dev/null 2>&1; then
  echo "STOP: psql not installed on this machine" >&2
  exit 2
fi
{
  printf 'BEGIN;\n'
  cat "$HERE/01_assigned_activity_recognition_held.sql"
  printf '\n'
  cat "$HERE/02_rollback_postconditions_held.sql"
  printf '\nROLLBACK;\n'
} | psql "$P1_DISPOSABLE_PGURI" -X -v ON_ERROR_STOP=1 -q
echo "P1 rollback-only source compilation/postconditions completed."
echo "NO signed worker/outsider, concurrency, HTTP, Result or production test was run."

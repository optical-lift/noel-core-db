#!/usr/bin/env bash
# Historical retirement candidate: one transaction, exact local/test PG17
# schema and REAL signed tests must follow. Never point at production.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${ATLAS_LIFECYCLE_ROLLBACK_DATABASE_URL:-}" ||
      "${ATLAS_LIFECYCLE_ROLLBACK_CONFIRM:-}" != "ROLLBACK_ONLY" ]]; then
  echo "Local/test database and ROLLBACK_ONLY confirmation required" >&2
  exit 1
fi
command -v psql >/dev/null || { echo "psql required" >&2; exit 1; }
candidate="$dir/04_shadow_release_candidate.sql"
if ! tail -n 1 "$candidate" | grep -Eq '^[[:space:]]*COMMIT;[[:space:]]*$'; then
  echo "Unexpected migration terminator; cannot create rollback assembly" >&2
  exit 1
fi
{
  sed '$d' "$candidate"
  cat "$dir/06_single_transition_authority_private.sql"
  cat "$dir/10_connected_person_result_writer_single_done_cutover_candidate.sql"
  cat "$dir/12_self_adopted_original_writer_single_done_cutover_candidate.sql"
  cat "$dir/14_event_shared_original_writer_single_done_cutover_candidate.sql"
  cat "$dir/16_historical_self_adoption_review_candidate.sql"
  cat "$dir/17_historical_self_adoption_review_readback_candidate.sql"
  cat "$dir/19_historical_self_adoption_public_transport_candidate.sql"
  cat "$dir/20_native_historical_retirement_candidate.sql"
  cat "$dir/21_native_historical_retirement_preflight_transport_candidate.sql"
  cat "$dir/05_rollback_postconditions.sql"
  cat "$dir/07_single_transition_rollback_postconditions.sql"
  cat "$dir/18_historical_self_adoption_review_postconditions.sql"
  cat "$dir/22_native_historical_retirement_rollback_postconditions.sql"
  printf '\nROLLBACK;\n'
} | psql "$ATLAS_LIFECYCLE_ROLLBACK_DATABASE_URL" \
  -X -v ON_ERROR_STOP=1 -v VERBOSITY=terse --quiet
echo "PASS: candidate compiled, assertions passed, original database changes rolled back."

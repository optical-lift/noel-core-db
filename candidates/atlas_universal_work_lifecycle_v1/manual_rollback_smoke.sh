#!/usr/bin/env bash
# RiverSong/local PostgreSQL-only validation of ONE Work lifecycle candidate.
# Every test executes within a single BEGIN ... ROLLBACK connection.
# No commits, no schema deployment, no new Done APIs.
set -euo pipefail

base="$(cd "$(dirname "$0")" && pwd)"
if [[ -z "${ATLAS_LIFECYCLE_ROLLBACK_DATABASE_URL:-}" ]]; then
  echo "Set a validated local/test Postgres connection string" >&2
  exit 1
fi
if [[ "${ATLAS_LIFECYCLE_ROLLBACK_CONFIRM:-}" != "ROLLBACK_ONLY" ]]; then
  echo "Refusing database access without ATLAS_LIFECYCLE_ROLLBACK_CONFIRM=ROLLBACK_ONLY" >&2
  exit 1
fi
command -v psql >/dev/null || { echo "psql required" >&2; exit 1; }
candidate="$base/04_shadow_release_candidate.sql"
if ! tail -n 1 "$candidate" | grep -Eq '^[[:space:]]*COMMIT;[[:space:]]*$'; then
  echo "Cannot safely replace unknown release candidate terminator" >&2
  exit 1
fi

{
  # IMPORTANT: exact candidate includes BEGIN but MUST NOT COMMIT here.
  sed '$d' "$candidate"
  cat "$base/06_single_transition_authority_private.sql"
  cat "$base/10_connected_person_result_writer_single_done_cutover_candidate.sql"
  cat "$base/12_self_adopted_original_writer_single_done_cutover_candidate.sql"
  cat "$base/05_rollback_postconditions.sql"
  cat "$base/07_single_transition_rollback_postconditions.sql"
  cat "$base/08_owner_witness_source_negatives_rollback.sql"
  cat "$base/11_connected_person_original_writer_rollback.sql"
  # Isolate the tests that depend on previously completed self-adopted Work.
  printf '\nSAVEPOINT gate2_self_original_fixture;\n'
  cat "$base/09_self_adoption_person_rollback.sql"
  printf '\nROLLBACK TO SAVEPOINT gate2_self_original_fixture;\n'
  cat "$base/13_self_adopted_original_writer_rollback.sql"
  printf '\nROLLBACK;\n'
} | psql "$ATLAS_LIFECYCLE_ROLLBACK_DATABASE_URL" \
      -X -v ON_ERROR_STOP=1 -v VERBOSITY=terse --quiet

echo "PASS: all tests completed in one ROLLBACK-only transaction."

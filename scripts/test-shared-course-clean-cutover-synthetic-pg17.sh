#!/usr/bin/env bash
# Self-contained synthetic PG17 on GitHub-hosted runner; no production access.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || exit 2
command -v docker >/dev/null || exit 2
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
d="candidates/shared-teaching-course-clean-cutover-v1"
for f in fixture_synthetic_pg17.sql person_first_candidate.sql person_first_clone_postconditions.sql sk101_exact_adoption_candidate.sql canonical_authoring_candidate.sql canonical_authoring_clone_postconditions.sql operating_standing_proposal_candidate.sql operating_standing_clone_postconditions.sql synthetic_pg17_journey.sql; do
  test -s "$root/$d/$f" || { echo "Missing $f" >&2; exit 2; }
done
if grep -Eq '\\bNOEL_CORE_DATABASE_URL\\b|\\bSUPABASE_DB_URL\\b|\\bsupabase db push\\b' "$root/$d/synthetic_pg17_journey.sql"; then
  echo 'Forbidden external access in synthetic test' >&2; exit 2
fi
name="shared-course-synthetic-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
started=false
cleanup() {
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == true ]]; then docker rm -f "$name" >/dev/null 2>&1 || true; fi
  exit "$rc"
}
trap cleanup EXIT INT TERM
docker run -d --rm --name "$name" --network none \
  --mount "type=bind,src=$root,dst=/source,readonly" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=postgres \
  postgres:17 -c listen_addresses='' >/dev/null
started=true
for i in $(seq 1 50); do
  if docker exec "$name" pg_isready -U postgres -d postgres -h /var/run/postgresql >/dev/null 2>&1; then break; fi
  [[ "$i" -lt 50 ]] || { echo "Scratch PG17 unavailable" >&2; exit 3; }
  sleep 1
done
psql_scratch() {
  docker exec "$name" psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres \
    -h /var/run/postgresql "$@"
}
identity="$(psql_scratch -Atqc "select current_setting('server_version_num')::int/10000,inet_server_addr() is null,current_user")"
[[ "$identity" == '17|t|postgres' ]] || { echo 'Unexpected DB target' >&2; exit 3; }
echo 'Verified network-isolated, job-owned PG17; only synthetic persons/manuscripts.'
# The marker is an accidental-misuse guard, not a security substitute for
# protected runner isolation and the release approval process.
psql_scratch -f "/source/$d/synthetic_pg17_journey.sql"
echo 'PASS: one Person-root, idempotent create/replay, outsider isolation, revoked and ambiguous denial; synthetic SK101 UUID/revision exact adoption. No live data/DDL.'

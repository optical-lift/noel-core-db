#!/usr/bin/env bash
# Held private Unit source; disposable network-isolated PostgreSQL 17 only.
# Uses unsigned fictional Auth claims; this is NOT real signed-user acceptance.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || { echo "Hosted Linux only" >&2; exit 2; }
command -v docker >/dev/null || { echo "Docker unavailable" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
for f in \
  candidates/titus-customer-workspace-first-course-v1/fixture.sql \
  candidates/titus-customer-workspace-first-course-v1/candidate.sql \
  candidates/titus-first-draft-material-v1/candidate.sql \
  candidates/titus-private-course-units-v1/candidate.sql \
  candidates/titus-private-course-units-v1/clone_validation.sql \
  candidates/titus-private-course-units-v1/postconditions.sql \
  candidates/titus-private-course-units-v1/negative_postconditions.sql; do
  test -s "$root/$f" || { echo "Source not present: $f" >&2; exit 2; }
done
scratch="$(mktemp -d /tmp/titus-units-hosted.XXXXXXXX)"
chmod 700 "$scratch"
name="titus-units-pg17-${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
started=false
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  [[ "$started" != true ]] || docker rm -f "$name" >/dev/null 2>&1 || true
  case "$scratch" in /tmp/titus-units-hosted.*) rm -rf -- "$scratch";; *)
    echo "Unsafe test scratch cleanup" >&2; rc=1;; esac
  exit "$rc"
}
trap cleanup EXIT INT TERM
unset NOEL_CORE_DATABASE_URL DATABASE_URL SUPABASE_DB_URL PGHOST PGUSER PGPORT PGDATABASE
docker run -d --rm --name "$name" --network none \
  --mount "type=bind,src=$root,dst=/source,readonly" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=postgres \
  postgres:17 -c listen_addresses='' >/dev/null
started=true
ready=false
for i in $(seq 1 50); do
  if docker exec "$name" pg_isready -U postgres -d postgres \
      -h /var/run/postgresql >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
[[ "$ready" == true ]] || { echo "Scratch PG17 not ready" >&2; exit 3; }
psql_local(){ docker exec "$name" psql -X -v ON_ERROR_STOP=1 \
  -h /var/run/postgresql -U postgres -d postgres "$@"; }
[[ "$(psql_local -Atqc "SELECT current_setting('server_version_num')::integer/10000, inet_server_addr() IS NULL")" == "17|t" ]] || {
 echo "Unsafe DB target/version" >&2; exit 3; }
echo "Verified isolated PG17 on a Docker private socket; no production network."
for f in \
  candidates/titus-customer-workspace-first-course-v1/fixture.sql \
  candidates/titus-customer-workspace-first-course-v1/candidate.sql \
  candidates/titus-first-draft-material-v1/candidate.sql \
  candidates/titus-private-course-units-v1/candidate.sql \
  candidates/titus-private-course-units-v1/clone_validation.sql \
  candidates/titus-private-course-units-v1/postconditions.sql \
  candidates/titus-private-course-units-v1/negative_postconditions.sql; do
  psql_local -f "/source/$f" >/dev/null
  echo "PASS: $f"
done
echo "PASS private Unit contract: no customer writes, no source release, no migration."

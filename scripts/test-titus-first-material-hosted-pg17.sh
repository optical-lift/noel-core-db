#!/usr/bin/env bash
# GitHub-hosted disposable PG17; direct source test when the repo-scoped
# RiverSong-Lex runner is attached to Titus instead of Noel.
set -Eeuo pipefail
[[ "$(uname -s)" == "Linux" ]] || { echo "Hosted Linux only" >&2; exit 2; }
command -v docker >/dev/null || { echo "Docker unavailable" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_dir="/source/candidates/titus-customer-workspace-first-course-v1"
sql_dir="/source/candidates/titus-first-draft-material-v1"
for f in "$root/candidates/titus-customer-workspace-first-course-v1/fixture.sql" \
         "$root/candidates/titus-customer-workspace-first-course-v1/candidate.sql" \
         "$root/candidates/titus-first-draft-material-v1/candidate.sql" \
         "$root/candidates/titus-first-draft-material-v1/postconditions.sql"; do
  test -s "$f" || { echo "Missing source $f" >&2; exit 2; }
done
scratch="$(mktemp -d /tmp/titus-material-hosted.XXXXXXXX)"
chmod 700 "$scratch"
name="titus-material-pg17-${GITHUB_RUN_ID:-$}-${GITHUB_RUN_ATTEMPT:-1}"
started=false
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/titus-material-hosted.* && -d "$scratch" ]]; then
    rm -rf -- "$scratch"
  else
    echo "Refusing unsafe scratch cleanup" >&2
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM
docker run -d --rm --name "$name" --network none \
  --mount "type=bind,src=$root,dst=/source,readonly" \
  -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=postgres \
  postgres:17 -c listen_addresses='' >/dev/null
started=true
ready=false
for _ in $(seq 1 50); do
  if docker exec "$name" pg_isready -U postgres -d postgres \
      -h /var/run/postgresql >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
[[ "$ready" == "true" ]] || { echo "Scratch PG17 did not start" >&2; exit 3; }
psql_local(){
  docker exec "$name" psql -X -v ON_ERROR_STOP=1 -h /var/run/postgresql \
    -U postgres -d postgres "$@"
}
actual="$(psql_local -Atqc "SELECT
  current_setting('server_version_num')::integer / 10000,
  inet_server_addr() IS NULL,
  current_user;")"
[[ "$actual" == "17|t|postgres" ]] || {
  echo "Scratch database identity/version mismatch" >&2; exit 3;
}
echo "Verified disposable network-isolated PostgreSQL 17; no production connection."
psql_local -f "$source_dir/fixture.sql"
psql_local -f "$source_dir/candidate.sql"
psql_local -f "$sql_dir/candidate.sql"
psql_local -f "$sql_dir/postconditions.sql"
echo "PASS: synthetic owner creates original Course material, reopens and revises without overwriting; replay idempotency, stale/outside/revoked/expired denial, no direct grants. Unsigned synthetic Auth fixture only, no live writes."

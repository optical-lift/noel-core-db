#!/usr/bin/env bash
# Isolated fictional PG17 validation. No external DB connection or real GoTrue.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Linux runner required' >&2;exit 2; }
command -v docker >/dev/null || { echo 'Docker required' >&2;exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
candidate="/source/candidates/shared-titus-learner-private-notebook-v1"
for f in fixture.sql candidate.sql structural_postconditions.sql postconditions.sql; do
 test -s "$root/candidates/shared-titus-learner-private-notebook-v1/$f"
done
container="titus-private-notes-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
[[ "$container" =~ ^[a-zA-Z0-9_.-]+$ ]] || exit 2
started=false
cleanup(){
 rc=$?
 trap - EXIT INT TERM
 if [[ "$started" == true ]]; then docker rm -f "$container" >/dev/null 2>&1 || true;fi
 exit "$rc"
}
trap cleanup EXIT INT TERM
unset PGHOST PGHOSTADDR PGPORT PGUSER PGDATABASE PGOPTIONS PGSSLMODE
unset DATABASE_URL NOEL_CORE_DATABASE_URL SUPABASE_DB_URL || true
docker run -d --rm --name "$container" --network none \
 --mount "type=bind,src=$root,dst=/source,readonly" \
 -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=postgres \
 postgres:17 -c listen_addresses='' >/dev/null
started=true
ready=false
for _ in $(seq 1 60); do
 if docker exec "$container" pg_isready -U postgres -d postgres -h /var/run/postgresql >/dev/null 2>&1; then ready=true;break;fi
 sleep 1
done
[[ "$ready" == true ]] || { echo 'Isolated PG17 failed to initialize' >&2;exit 3; }
psql_local(){ docker exec "$container" psql -X -v ON_ERROR_STOP=1 -h /var/run/postgresql -U postgres -d postgres "$@"; }
fingerprint="$(psql_local -Atqc "select current_setting('server_version_num')::integer/10000,inet_server_addr() is null,current_user;")"
[[ "$fingerprint" == '17|t|postgres' ]] || { echo "Unexpected PG17 fingerprint: $fingerprint" >&2;exit 3; }
echo 'Verified disposable network-isolated PG17 on private Unix socket; not production.'
psql_local -f "$candidate/fixture.sql"
psql_local -f "$candidate/candidate.sql"
psql_local -f "$candidate/structural_postconditions.sql"
psql_local -f "$candidate/postconditions.sql"
echo 'PASS disposable SQL contract; synthetic unsigned claims only. No actual GoTrue signed acceptance.'

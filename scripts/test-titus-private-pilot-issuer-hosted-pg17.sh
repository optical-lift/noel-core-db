#!/usr/bin/env bash
# Hosted isolated PostgreSQL 17 proof: source and assertions are copied from
# the existing RiverSong scratch test, without production or cross-repo access.
set -Eeuo pipefail
[[ "$(uname -s)" == "Linux" ]] || { echo "Hosted Linux only" >&2; exit 2; }
command -v docker >/dev/null || { echo "Docker unavailable" >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source_dir="/source/candidates/titus-customer-workspace-first-course-v1"
issuer="/source/scripts/titus-private-pilot-issue.sql"
for f in "$root/candidates/titus-customer-workspace-first-course-v1/fixture.sql" \
         "$root/candidates/titus-customer-workspace-first-course-v1/candidate.sql" \
         "$root/scripts/titus-private-pilot-issue.sql"; do
  test -s "$f" || { echo "Missing exact source $f" >&2; exit 2; }
done
scratch="$(mktemp -d /tmp/titus-pilot-hosted.XXXXXXXX)"
chmod 700 "$scratch"
real_scratch="$(cd "$scratch" && pwd -P)"
name="titus-pilot-pg17-${GITHUB_RUN_ID:-$}-${GITHUB_RUN_ATTEMPT:-1}"
started=false
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == "true" ]]; then
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
  if [[ "$scratch" == /tmp/titus-pilot-hosted.* && -d "$scratch" ]]; then
    rm -rf -- "$scratch"
  else
    echo "Refusing unsafe scratch cleanup" >&2
    rc=1
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM
# Trust authentication is restricted to this disposable --network none
# container and its internal Unix socket, never exposed on a host port.
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
psql_local -q -c "
UPDATE auth.users SET email='lexprjct@gmail.com'
 WHERE id='00000000-0000-4000-8000-000000000101';
UPDATE auth.users SET email='outsider@example.test'
 WHERE id='00000000-0000-4000-8000-000000000102';
"
receipt='github:optical-lift/noel-core-db/issues/2489#titus-private-pilot-v1'
issue_as_pilot() {
  psql_local -Atq -v pilot_email="$1" -v pilot_receipt="$2" -v pilot_days="$3" -f "$issuer"
}
# Exactly one existing verified Auth target, no seeded university or Course.
before="$(psql_local -Atqc 'select count(*) from titus.customer_workspace_entitlements_v1;')"
[[ "$before" == '0' ]] || { echo "Issuer test fixture wasn't empty." >&2; exit 3; }
proof="$(issue_as_pilot 'lexprjct@gmail.com' "$receipt" '180')"
[[ "$proof" == *'1|1|0|0'* ]] || {
 echo "First issuer receipt mismatch (no details printed)." >&2; exit 3;
}
# Reissuing exact owner receipt must be idempotent; no second grant.
proof="$(issue_as_pilot 'lexprjct@gmail.com' "$receipt" '180')"
[[ "$proof" == *'1|1|0|0'* ]] || { echo "Pilot replay changed state." >&2; exit 3; }

deny() {
  if issue_as_pilot "$1" "$2" "$3" >"$real_scratch/denied.log" 2>&1; then
    echo "Unauthorized pilot request was accepted." >&2
    exit 4
  fi
}
deny 'unknown@example.test' 'github:optical-lift/noel-core-db/issues/2490#titus-private-pilot-v1' 180
deny 'outsider@example.test' "$receipt" 180
deny 'lexprjct@gmail.com' 'github:optical-lift/noel-core-db/issues/2491#titus-private-pilot-v1' 180
deny 'lexprjct@gmail.com' 'not-source-approved' 180
deny 'lexprjct@gmail.com' "$receipt" 365
# Missing confirmation / deleted users are not eligible.
psql_local -q -c "UPDATE auth.users SET email_confirmed_at=NULL,deleted_at=now()
 WHERE id='00000000-0000-4000-8000-000000000102';"
deny 'outsider@example.test' 'github:optical-lift/noel-core-db/issues/2492#titus-private-pilot-v1' 180
# Withdrawn grant cannot be resurrected just by replaying old receipt.
psql_local -q -c "UPDATE titus.customer_workspace_entitlements_v1 SET state='revoked'
 WHERE grant_source_receipt='$receipt';"
deny 'lexprjct@gmail.com' "$receipt" 180

count="$(psql_local -Atqc 'select count(*) from titus.customer_workspace_entitlements_v1;')"
state="$(psql_local -Atqc "select state from titus.customer_workspace_entitlements_v1 where grant_source_receipt='$receipt';")"
[[ "$count" == '1' && "$state" == 'revoked' ]] || {
 echo "Failed cases changed unauthorized grants." >&2; exit 4;
}
echo "PASS: approved owner private-pilot grant, exact eligible Auth target, idempotent receipt, other-user/unknown/conflict/invalid/expired/deleted denials, revoked replay denial; all in disposable PG17; no production mutations."

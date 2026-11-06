#!/usr/bin/env bash
# Held, synthetic PG17 source test. NO real GoTrue, NO production schema/data.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Linux required' >&2; exit 2; }
command -v docker >/dev/null || { echo 'Docker required' >&2; exit 2; }
root="$(cd "$(dirname "$0")/.." && pwd -P)"
base="/source/candidates/uni_ops_universal_company_decision_v1"
for f in \
  01_domain_neutral_source_and_decision_records_held.sql \
  02_private_company_governor_decision_writer_held.sql \
  03_private_current_governor_case_receipt_held.sql \
  06_bounded_existing_subject_disclosure_extension_held.sql \
  04_verified_farm_source_to_company_case_adapter_held.sql \
  05_farm_to_one_company_governor_decision_wrapper_held.sql \
  tests/synthetic_pg17_source_schema.sql \
  tests/synthetic_pg17_source_admission_checks.sql; do
 test -s "$root/candidates/uni_ops_universal_company_decision_v1/$f" ||
   { echo "Missing held source input $f" >&2; exit 2; }
done
scratch="$(mktemp -d /tmp/uniops-universal-held.XXXXXXXX)"
chmod 700 "$scratch"
name="uniops-univ-pg17-$RANDOM-$$"
started=false
cleanup(){
 rc=$?
 trap - EXIT INT TERM
 if [[ "$started" == true ]]; then docker rm -f "$name" >/dev/null 2>&1 || true; fi
 case "$scratch" in
   /tmp/uniops-universal-held.*) rm -rf -- "$scratch";;
   *) echo 'Unsafe scratch path, refusing deletion' >&2; rc=1;;
 esac
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
   -h /var/run/postgresql >/dev/null 2>&1; then ready=true; break; fi
 sleep 1
done
[[ "$ready" == true ]] || { echo 'Scratch PG17 did not start' >&2; exit 3; }
psql_local(){
 docker exec "$name" psql -X -v ON_ERROR_STOP=1 \
   -h /var/run/postgresql -U postgres -d postgres "$@"
}
[[ "$(psql_local -Atqc "SELECT current_setting('server_version_num')::integer/10000,inet_server_addr() IS NULL,current_user")" == '17|t|postgres' ]] || {
 echo 'Not disposable local socket-only PostgreSQL 17' >&2; exit 3;
}
echo 'PASS: job-owned socket-only PG17; network none, no production URL.'
psql_local -q -f "$base/tests/synthetic_pg17_source_schema.sql"
for f in \
  01_domain_neutral_source_and_decision_records_held.sql \
  02_private_company_governor_decision_writer_held.sql \
  03_private_current_governor_case_receipt_held.sql \
  06_bounded_existing_subject_disclosure_extension_held.sql \
  04_verified_farm_source_to_company_case_adapter_held.sql \
  05_farm_to_one_company_governor_decision_wrapper_held.sql; do
 echo "Compiling held SQL $f"
 psql_local -q -f "$base/$f"
done
psql_local -q -f "$base/tests/synthetic_pg17_source_admission_checks.sql"
echo 'PASS: synthetic PG17 source compilation, native disclosure CHECK, private ACL/RLS, two source rows, replay and denials. NOT signed GoTrue or production-shaped.'

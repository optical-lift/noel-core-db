#!/usr/bin/env bash
# Genuine signed GoTrue/PostgREST on an entirely disposable local Course Unit stack.
# No production URL, project ref, bearer, email service or private source data.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Linux isolated runner required' >&2; exit 2; }
for cmd in supabase docker psql python3; do
  command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 2; }
done
[[ "$(supabase --version | tail -n 1)" == "2.116.0" ]] || {
  echo 'Pinned Supabase CLI 2.116.0 required' >&2; exit 2;
}
root="$(cd "$(dirname "$0")/.." && pwd -P)"
scratch="$(mktemp -d /tmp/titus-units-signed-gotrue.XXXXXXXX)"
chmod 700 "$scratch"
project="$scratch/project"
started=false
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == true && -d "$project" ]]; then
    (cd "$project" && supabase stop --no-backup) >/dev/null 2>&1 || true
  fi
  case "$scratch" in
    /tmp/titus-units-signed-gotrue.*) rm -rf -- "$scratch";;
    *) echo "Refusing unsafe scratch cleanup" >&2; rc=1;;
  esac
  exit "$rc"
}
trap cleanup EXIT INT TERM
unset NOEL_CORE_DATABASE_URL DATABASE_URL SUPABASE_DB_URL SUPABASE_SERVICE_ROLE_KEY
mkdir -p "$project"
cd "$project"
supabase init --force >/dev/null
# Never use a production Supabase project; choose a unique disposable CLI identity.
python3 - <<'PY'
from pathlib import Path
import re,secrets
path=Path("supabase/config.toml")
content=path.read_text(encoding="utf-8")
updated,n=re.subn(r'(?m)^project_id\s*=\s*".*"$',
                  'project_id = "titus_signed_local_'+                  secrets.token_hex(6)+'"',content,count=1)
if n!=1: raise SystemExit("Missing isolated project ID")
path.write_text(updated,encoding="utf-8")
PY
started=true
# Start only the local Postgres/Auth/REST services. No real email or data.
supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor > "$scratch/startup.log" 2>&1 || {
  tail -n 45 "$scratch/startup.log" >&2
  exit 3
}
db='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
test "$(psql "$db" -X -v ON_ERROR_STOP=1 -A -t -c 'SELECT current_database()')" = "postgres"
psql "$db" -X -v ON_ERROR_STOP=1 -c 'CREATE SCHEMA titus;' >/dev/null
# Mirror verified live Supabase default public function privileges locally.
psql "$db" -X -v ON_ERROR_STOP=1 -c   'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon,authenticated,service_role;' >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -f   "$root/candidates/titus-customer-workspace-first-course-v1/candidate.sql" >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -f   "$root/candidates/titus-first-draft-material-v1/candidate.sql" >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -f "$root/candidates/titus-first-draft-material-v1/clone_validation.sql" >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -f "$root/candidates/titus-private-course-units-v1/candidate.sql" >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -f "$root/candidates/titus-private-course-units-v1/clone_validation.sql" >/dev/null
psql "$db" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema';" >/dev/null
sleep 2
python3 "$root/scripts/validate-titus-course-units-signed-local.py"  --db-url "$db" --output "$scratch/signed-proof.json"
python3 - "$scratch/signed-proof.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1],encoding="utf-8"))
assert result["scope"]=="fully_disposable_local_auth_and_rest"
assert result["signedUnitContracts"]=="PASS"
assert result["realHumanAcceptance"] is False
assert result["productionWrites"] is False
print("PASS isolated signed Course Unit tests; real customer/browser acceptance NOT claimed")
PY

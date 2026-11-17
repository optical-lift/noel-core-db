#!/usr/bin/env bash
# HELD fictional UI readback INSIDE existing owner-protected P3 local clone.
# No production credentials, source patch, snapshot export or GitHub artifacts.
set -euo pipefail
umask 077
# Only static stage labels may be written to a public diagnostic.
stage=environment_contract
blocked(){
  printf 'BLOCKED ATLAS_CI_BROWSER_READBACK=not_verified\nATLAS_CI_BROWSER_FAILURE_STAGE=%s\n' "$stage"
  exit 1
}

test "$#" -eq 1 || blocked
database_url="$1"
[[ "$database_url" =~ ^postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]{4,5}/postgres$ ]] || blocked
test "${ATLAS_BROWSER_FICTIONAL_ONLY:-}" = true || blocked
test "${CI:-}" = true && test "${GITHUB_ACTIONS:-}" = true || blocked
test "${GITHUB_REPOSITORY:-}" = optical-lift/noel-core-db || blocked
test -z "${NOEL_CORE_DATABASE_URL:-}" || blocked
test -z "${SUPABASE_SERVICE_ROLE_KEY:-}" || blocked
test -n "${RUNNER_TEMP:-}" && test -n "${GITHUB_WORKSPACE:-}" || blocked

stage=atlas_source_integrity
root="$GITHUB_WORKSPACE/atlas-browser-ci"
test -d "$root/.git" && test ! -L "$root" || blocked
test "$(git -C "$root" rev-parse HEAD)" = 1d80f0b26be53df1e9e6b06295d98795853c96e0 || blocked
test "$(git -C "$root" hash-object tests/held-uniops-p3-signed-browser-readback.mjs)" = 2170cb5fac7e0095b75aa949bfce162638cad525 || blocked

stage=fictional_actor_fixture
test "$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "select count(*) from auth.users where email in ('atlas-c1-owner@example.invalid','atlas-c1-outsider@example.invalid')")" = 2 || blocked

stage=accepted_work_selection
work="$(psql "$database_url" -XAt -v ON_ERROR_STOP=1 -c "
select w.id from atlas.work_items w
join atlas.work_result_acceptances a on a.work_item_id=w.id
join atlas.work_execution_results r on r.id=a.execution_result_id
where w.organization_id='e5200000-0000-4000-8000-000000000801'::uuid
  and w.source_object_type='rhythm_state'
  and w.source_object_id='e5200000-0000-4000-8000-000000000d05'::uuid
  and w.work_state='completed'
  and w.result_contract_key='continuing_care_actual_v1'
  and a.decision='accepted'
  and r.result_contract_key='continuing_care_actual_v1'")" || blocked
[[ "$work" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] || blocked

stage=local_api_configuration
mapfile -t local_api < <(python3 - <<'PY'
import subprocess
s=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=False)
if s.returncode!=0:raise SystemExit(1)
fields={}
for line in s.stdout.splitlines():
    if "=" in line:
        k,v=line.split("=",1)
        fields[k]=v.strip().strip('"')
url=fields.get("API_URL","")
key=fields.get("ANON_KEY","")
if url not in ("http://127.0.0.1:54321","http://localhost:54321") or len(key)<100:
    raise SystemExit(1)
print("http://127.0.0.1:54321")
print(key)
PY
)
test "${#local_api[@]}" = 2 || blocked
test "${#local_api[1]}" -gt 100 || blocked

log="$RUNNER_TEMP/uniops-browser-private.log"
next_log="$RUNNER_TEMP/uniops-next-private.log"
next_pid=""
cleanup(){
  if [ -n "$next_pid" ]; then
    kill "$next_pid" >/dev/null 2>&1 || true
    wait "$next_pid" >/dev/null 2>&1 || true
  fi
  rm -f -- "$log" "$next_log"
}
trap cleanup EXIT

stage=browser_source_contract
cd "$root"
node --check tests/held-uniops-p3-signed-browser-readback.mjs || blocked
node --test tests/atlas-uniops-p3-signed-browser-source.test.mjs > "$log" 2>&1 || blocked
stage=package_install
npm ci --ignore-scripts --no-audit --no-fund >> "$log" 2>&1 || blocked
npm install --no-save --no-package-lock --ignore-scripts --no-audit --no-fund \
  next@16.4.6 playwright@1.65.1 >> "$log" 2>&1 || blocked
test "$(node -p "require('./node_modules/playwright/package.json').version")" = 1.65.1 || blocked
test "$(node -p "require('./node_modules/next/package.json').version")" = 16.4.6 || blocked
stage=chromium_install
./node_modules/.bin/playwright install chromium >> "$log" 2>&1 || blocked

export NEXT_PUBLIC_SUPABASE_URL="${local_api[0]}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${local_api[1]}"
export NEXT_TELEMETRY_DISABLED=1
export ATLAS_UNI_OPS_C_LAB_ENABLED=true
export ATLAS_UNI_OPS_C_HUMAN_FIRST_PROOF_ENABLED=true
export ATLAS_LOCAL_BROWSER_URL=http://127.0.0.1:3100
export ATLAS_FICTIONAL_MOWING_WORK_ID="$work"

stage=next_server_ready
./node_modules/.bin/next dev -H 127.0.0.1 -p 3100 > "$next_log" 2>&1 &
next_pid="$!"
ready=false
for i in $(seq 1 90); do
  if curl --silent --fail --output /dev/null \
       --max-time 5 http://127.0.0.1:3100/uni-ops-lab; then
    ready=true
    break
  fi
  sleep 2
done
test "$ready" = true || blocked
stage=governor_readback_or_browser_start
if ! node tests/held-uniops-p3-signed-browser-readback.mjs > "$log" 2>&1; then
  # This exact marker is emitted only after governor Done has passed.
  # No private browser or database error text is forwarded.
  if grep -qx 'PASS ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK=PASS' "$log"; then
    stage=outsider_denial
  fi
  blocked
fi
stage=browser_acceptance_marker
grep -qx 'PASS ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK=PASS' "$log" || blocked
grep -qx 'PASS ATLAS_CI_OUTSIDER_WORK_DENIAL=PASS' "$log" || blocked
echo 'PASS ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK=PASS'
echo 'PASS ATLAS_CI_OUTSIDER_WORK_DENIAL=PASS'
echo 'ATLAS_CI_WORKER_ACTUAL_VIA_BROWSER=NOT_RUN'
echo 'NOEL_PRODUCTION_MUTATION=NONE'

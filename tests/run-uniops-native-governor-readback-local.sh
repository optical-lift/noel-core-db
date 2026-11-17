#!/usr/bin/env bash
# HELD, NOT TRIGGERED. Signed governor/worker/outsider native Notebook readback
# only AFTER the separate signed worker browser Actual and P3 source snapshots
# succeeded in a disposable PG17 + local GoTrue/PostgREST clone.
set -euo pipefail
umask 077
stage=environment
blocked(){
 printf 'BLOCKED ATLAS_NATIVE_SIGNED_READBACK=NOT_VERIFIED\nATLAS_NATIVE_FAILURE_STAGE=%s\n' "$stage"
 exit 1
}
test "$#" -eq 2 || blocked
db_url="$1"
work="$2"
[[ "$db_url" =~ ^postgres(ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres$ ]] || blocked
[[ "$work" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] || blocked
test "${CI:-}" = true && test "${GITHUB_ACTIONS:-}" = true || blocked
test "${GITHUB_REPOSITORY:-}" = optical-lift/noel-core-db || blocked
test "${ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY:-}" = true || blocked
test "${ATLAS_NATIVE_SIGNED_READBACK_ENABLED:-}" = true || blocked
test "${ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED:-}" = true || blocked
test -n "${RUNNER_TEMP:-}" && test -n "${GITHUB_WORKSPACE:-}" || blocked
test -z "${NOEL_CORE_DATABASE_URL:-}" && test -z "${SUPABASE_SERVICE_ROLE_KEY:-}" || blocked

stage=source_integrity
root="$GITHUB_WORKSPACE/atlas-browser-ci"
test -d "$root/.git" && test ! -L "$root" || blocked
test "$(git -C "$root" rev-parse HEAD)" = 6bc616db84854ea2d906dd51a017d8616ef0762d || blocked
test "$(git -C "$root" hash-object tests/held-uniops-native-notebook-signed-browser-readback.mjs)" = 98f148fed1e03d85e2c05375e0aaa325d10d4d63 || blocked

stage=local_api
mapfile -t local_api < <(python3 - <<'PY'
import subprocess
p=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=False)
if p.returncode:raise SystemExit(1)
info={}
for line in p.stdout.splitlines():
 if "=" in line:
  k,v=line.split("=",1)
  info[k]=v.strip().strip('"')
if info.get("API_URL") not in ("http://127.0.0.1:54321","http://localhost:54321"):
 raise SystemExit(1)
if len(info.get("ANON_KEY",""))<100:raise SystemExit(1)
print("http://127.0.0.1:54321")
print(info["ANON_KEY"])
PY
)
test "${#local_api[@]}" -eq 2 && test "${#local_api[1]}" -gt 100 || blocked
log="$RUNNER_TEMP/uniops-native-governor-private.log"
next_log="$RUNNER_TEMP/uniops-native-governor-next-private.log"
next_pid=""
cleanup(){
 if [ -n "$next_pid" ]; then
  kill "$next_pid" >/dev/null 2>&1 || true
  wait "$next_pid" >/dev/null 2>&1 || true
 fi
 rm -f -- "$log" "$next_log"
}
trap cleanup EXIT

stage=local_app_dependencies
cd "$root"
test -f node_modules/next/package.json && test -f node_modules/playwright/package.json || blocked
test "$(node -p "require('./node_modules/next/package.json').version")" = 16.4.6 || blocked
test "$(node -p "require('./node_modules/playwright/package.json').version")" = 1.65.1 || blocked
node --check tests/held-uniops-native-notebook-signed-browser-readback.mjs || blocked

export NEXT_PUBLIC_SUPABASE_URL="${local_api[0]}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${local_api[1]}"
export NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="${local_api[1]}"
export NEXT_TELEMETRY_DISABLED=1
export VERCEL_ENV=preview
export ATLAS_LOCAL_BROWSER_URL=http://127.0.0.1:3100
export ATLAS_FICTIONAL_MOWING_WORK_ID="$work"
export ATLAS_NATIVE_NOTEBOOK_PREVIEW_CONFIGURED=true

stage=next_local_ready
./node_modules/.bin/next dev -H 127.0.0.1 -p 3100 > "$next_log" 2>&1 &
next_pid="$!"
ready=false
for i in $(seq 1 90); do
 if curl --silent --fail --output /dev/null --max-time 5 http://127.0.0.1:3100/; then
  ready=true
  break
 fi
 sleep 2
done
test "$ready" = true || blocked

stage=governor_worker_outsider
if ! node tests/held-uniops-native-notebook-signed-browser-readback.mjs > "$log" 2>&1; then
 case "$(grep '^ATLAS_NATIVE_FAILURE_STAGE=' "$log" || true)" in
  ATLAS_NATIVE_FAILURE_STAGE=runner) stage=runner ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_signin) stage=governor_signin ;;
  ATLAS_NATIVE_FAILURE_STAGE=worker_signin) stage=worker_signin ;;
  ATLAS_NATIVE_FAILURE_STAGE=outsider_signin) stage=outsider_signin ;;
  ATLAS_NATIVE_FAILURE_STAGE=browser_start) stage=browser_start ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_native_entitlement) stage=governor_native_entitlement ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_today) stage=governor_today ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_ledger) stage=governor_ledger ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_person) stage=governor_person ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_completed_list) stage=governor_completed_list ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_original) stage=governor_original ;;
  ATLAS_NATIVE_FAILURE_STAGE=governor_verified_done) stage=governor_verified_done ;;
  ATLAS_NATIVE_FAILURE_STAGE=worker_native_notebook) stage=worker_native_notebook ;;
  ATLAS_NATIVE_FAILURE_STAGE=outsider_native_denial) stage=outsider_native_denial ;;
 esac
 blocked
fi
stage=source_accepted
grep -qx 'PASS ATLAS_NATIVE_GOVERNOR_DONE=PASS' "$log" || blocked
grep -qx 'PASS ATLAS_NATIVE_WORKER_BOUNDARY=PASS' "$log" || blocked
grep -qx 'PASS ATLAS_NATIVE_OUTSIDER_DENIAL=PASS' "$log" || blocked
echo 'PASS ATLAS_NATIVE_GOVERNOR_DONE=PASS'
echo 'PASS ATLAS_NATIVE_WORKER_BOUNDARY=PASS'
echo 'PASS ATLAS_NATIVE_OUTSIDER_DENIAL=PASS'
echo 'ATLAS_NATIVE_FOUNDRY_UI_AUTHORING=NOT_RUN'
echo 'ATLAS_NATIVE_SECOND_DOMAIN=NOT_RUN'
echo 'ATLAS_PRODUCTION_CHANGE=NONE'

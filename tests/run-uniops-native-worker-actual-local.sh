#!/usr/bin/env bash
# HELD TEST ONLY. One worker browser Actual in a separately approved, cloned
# PG17/GoTrue stack; this file does not register or trigger a protected job.
set -euo pipefail
umask 077
stage=environment
blocked(){
 printf 'BLOCKED ATLAS_NATIVE_WORKER_PHYSICAL_ACTUAL=NOT_VERIFIED\nATLAS_NATIVE_WORKER_STAGE=%s\n' "$stage"
 exit 1
}
test "$#" -eq 3 || blocked
db_url="$1"
work="$2"
private="$3"
[[ "$db_url" =~ ^postgres(ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres$ ]] || blocked
[[ "$work" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]] || blocked
test "${CI:-}" = true && test "${GITHUB_ACTIONS:-}" = true || blocked
test "${GITHUB_REPOSITORY:-}" = optical-lift/noel-core-db || blocked
test "${ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED:-}" = true || blocked
test -n "${RUNNER_TEMP:-}" && test -n "${GITHUB_WORKSPACE:-}" || blocked
test "$private" = "$RUNNER_TEMP/uniops-native-worker-actual-private.json" || blocked
test ! -e "$private" && test ! -L "$private" || blocked
test -z "${NOEL_CORE_DATABASE_URL:-}" && test -z "${SUPABASE_SERVICE_ROLE_KEY:-}" || blocked

stage=atlas_source_integrity
root="$GITHUB_WORKSPACE/atlas-browser-ci"
test -d "$root/.git" && test ! -L "$root" || blocked
test "$(git -C "$root" rev-parse HEAD)" = 4ea4033eaae50936f3317f6feda83bce89a7ce74 || blocked
test "$(git -C "$root" hash-object tests/held-uniops-native-worker-actual-browser.mjs)" = 80b8448267c126f713c08fac30405e647c9e1d13 || blocked
test "$(git -C "$root" hash-object app/PersonalConnectedPersonCompanyWork.tsx)" = f2462fc34e0074f5dbd254b257b6f782e19beea7 || blocked
test "$(git -C "$root" hash-object app/ConnectedLedgerWorkNotebook.tsx)" = e36b5b79057cd229e31b34455f0fb06dd8d3d067 || blocked
test "$(git -C "$root" hash-object app/CanonicalWorkFocusCareActual.tsx)" = 7ef7d117fff2ed3b4a99384c42a17165c25ba225 || blocked
test "$(git -C "$root" hash-object app/AtlasHomeRouterClient.tsx)" = 4a217c955e0387c115376f5961b185590a598848 || blocked
test "$(git -C "$root" hash-object lib/atlas-browser-client.ts)" = a0dbd2bb2d241e02242ef88c92224e5dac6766af || blocked

stage=local_api_configuration
mapfile -t local_api < <(python3 - <<'PY'
import subprocess
r=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=False)
if r.returncode:raise SystemExit(1)
data={}
for line in r.stdout.splitlines():
    if "=" in line:
        k,v=line.split("=",1)
        data[k]=v.strip().strip('"')
if data.get("API_URL") not in ("http://127.0.0.1:54321","http://localhost:54321"):
    raise SystemExit(1)
if len(data.get("ANON_KEY",""))<100:raise SystemExit(1)
print("http://127.0.0.1:54321")
print(data["ANON_KEY"])
PY
)
test "${#local_api[@]}" -eq 2 && test "${#local_api[1]}" -gt 100 || blocked
log="$RUNNER_TEMP/uniops-native-worker-private.log"
next_log="$RUNNER_TEMP/uniops-native-next-private.log"
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
node --check tests/held-uniops-native-worker-actual-browser.mjs || blocked
stage=package_install
npm ci --ignore-scripts --no-audit --no-fund > "$log" 2>&1 || blocked
npm install --no-save --no-package-lock --ignore-scripts --no-audit --no-fund \
 next@16.4.6 playwright@1.65.1 >> "$log" 2>&1 || blocked
test "$(node -p "require('./node_modules/next/package.json').version")" = 16.4.6 || blocked
test "$(node -p "require('./node_modules/playwright/package.json').version")" = 1.65.1 || blocked
stage=chromium_install
./node_modules/.bin/playwright install chromium >> "$log" 2>&1 || blocked

export NEXT_PUBLIC_SUPABASE_URL="${local_api[0]}"
export NEXT_PUBLIC_SUPABASE_ANON_KEY="${local_api[1]}"
export NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="${local_api[1]}"
export NEXT_TELEMETRY_DISABLED=1
export VERCEL_ENV=preview
export ATLAS_LOCAL_BROWSER_URL=http://127.0.0.1:3100
export ATLAS_FICTIONAL_MOWING_WORK_ID="$work"
export ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY=true
export ATLAS_NATIVE_NOTEBOOK_PREVIEW_CONFIGURED=true
export ATLAS_NATIVE_WORKER_RECEIPT_FILE="$private"

stage=next_server_ready
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

stage=worker_browser_actual
if ! node tests/held-uniops-native-worker-actual-browser.mjs > "$log" 2>&1; then
 # No private browser error, response or JWT is ever echoed.
 case "$(grep '^ATLAS_NATIVE_WORKER_STAGE=' "$log" || true)" in
  ATLAS_NATIVE_WORKER_STAGE=environment) stage=environment ;;
  ATLAS_NATIVE_WORKER_STAGE=auth) stage=auth ;;
  ATLAS_NATIVE_WORKER_STAGE=browser) stage=browser ;;
  ATLAS_NATIVE_WORKER_STAGE=notebook) stage=notebook ;;
  ATLAS_NATIVE_WORKER_STAGE=work_row) stage=work_row ;;
  ATLAS_NATIVE_WORKER_STAGE=work_focus) stage=work_focus ;;
  ATLAS_NATIVE_WORKER_STAGE=physical_form) stage=physical_form ;;
  ATLAS_NATIVE_WORKER_STAGE=actual_rpc) stage=actual_rpc ;;
  ATLAS_NATIVE_WORKER_STAGE=receipt) stage=receipt ;;
  ATLAS_NATIVE_WORKER_STAGE=ui_completed) stage=ui_completed ;;
  ATLAS_NATIVE_WORKER_STAGE=private_receipt) stage=private_receipt ;;
 esac
 blocked
fi
stage=private_receipt
grep -qx 'PASS ATLAS_NATIVE_WORKER_PHYSICAL_ACTUAL=PASS' "$log" || blocked
test -s "$private" && test ! -L "$private" || blocked
echo 'PASS ATLAS_NATIVE_WORKER_PHYSICAL_ACTUAL=PASS'
echo 'ATLAS_PRODUCTION_CHANGE=NONE'

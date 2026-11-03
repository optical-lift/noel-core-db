#!/usr/bin/env bash
# UNI-OPS-01 option D: RiverSong-only, local source-backed disposable GoTrue.
# Nothing may reach production or the older 55432/noel_schema_clone instance.
set -euo pipefail
umask 077
[[ $# -eq 0 ]] || { echo 'STOP: no arguments supported'; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
[[ "$HERE" == "$ROOT/candidates/atlas_governed_rulebook_u1a_v1" ]] ||
 { echo 'STOP: unexpected source location'; exit 2; }
[[ "$(git -C "$ROOT" branch --show-current)" == candidate/atlas-u1a-governed-rulebook-adoption-20261103 ]] ||
 { echo 'STOP: unexpected branch'; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] ||
 { echo 'STOP: dirty source checkout'; exit 2; }
SHA="$(git -C "$ROOT" rev-parse HEAD)"
[[ "$SHA" =~ ^[a-f0-9]{40}$ ]] || { echo 'STOP: invalid source SHA'; exit 2; }
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  [[ "$(printf '%s' "${RUNNER_NAME:-}" | tr '[:upper:]' '[:lower:]')" == riversong ]] ||
    { echo 'STOP: self-hosted runner is not RiverSong'; exit 2; }
fi
[[ "$(uname -s)" == Darwin ]] || { echo 'STOP: RiverSong macOS only'; exit 2; }
for key in NOEL_CORE_DATABASE_URL SUPABASE_DB_URL DATABASE_URL SUPABASE_ACCESS_TOKEN; do
  [[ -z "${!key:-}" ]] || { echo "STOP: remote credential $key must not be present"; exit 2; }
done
for cmd in git docker supabase psql python3 node; do
  command -v "$cmd" >/dev/null || { echo "STOP: missing $cmd"; exit 2; }
done
docker info >/dev/null 2>&1 || { echo 'STOP: Docker is unavailable'; exit 2; }
[[ "$(supabase --version | tail -1)" == 2.116.0 ]] ||
 { echo 'STOP: pinned Supabase CLI v2.116.0 required'; exit 2; }
node --test "$ROOT/tests/atlas-u1a-governed-rulebook-source.test.mjs"
[[ -s "$ROOT/validation/fixtures/20261026215011_atlas_universal_original_work_integrated_v1.sql" ]] ||
 { echo 'STOP: source-owned C1 fixture absent'; exit 2; }
MIGRATIONS="$ROOT/supabase/migrations"
[[ -d "$MIGRATIONS" && -n "$(find "$MIGRATIONS" -maxdepth 1 -name '*.sql' -print -quit)" ]] ||
 { echo 'STOP: versioned native schema migrations absent'; exit 2; }

TMP_PARENT="${TMPDIR:-/tmp}"
SCRATCH="$(mktemp -d "$TMP_PARENT/u1a-option-d-XXXXXXXX")"
PROJECT="$SCRATCH/project"
EVIDENCE="$SCRATCH/evidence"
mkdir -p "$PROJECT" "$EVIDENCE"
STARTED=false
PHASE="prepare-isolated-project"
cleanup() {
  code=$?
  trap - EXIT
  printf 'SOURCE_SHA=%s\nPHASE=%s\nEXIT_CODE=%s\n' "$SHA" "$PHASE" "$code" >"$EVIDENCE/source-result.txt"
  if [[ "$STARTED" == true ]]; then
    if (cd "$PROJECT" && supabase stop --no-backup) >"$EVIDENCE/cleanup.log" 2>&1; then
      echo 'CLEANUP: exact disposable Supabase project stopped without backup'
    else
      echo "CLEANUP BLOCKED: only inspect/stop disposable project $PROJECT" >&2
      echo 'CLEANUP_INCOMPLETE' >"$EVIDENCE/cleanup-state.txt"
      code=1
    fi
  fi
  if [[ ! -s "$EVIDENCE/cleanup-state.txt" ]]; then
    echo 'CLEANUP_COMPLETE' >"$EVIDENCE/cleanup-state.txt"
    if [[ -s "$EVIDENCE/signed-proof.txt" ]]; then
      echo 'SIGNED_U1A_PROOF_PASS'
    fi
    # Copy just the nonsecret machine-readable receipt outside scratch.
    if [[ -n "${RUNNER_TEMP:-}" ]]; then
      # Unique per Actions attempt; never display a stale result from a
      # previous run on this persistent self-hosted computer.
      RECEIPT_DIR="$RUNNER_TEMP/u1a-option-d-results-${GITHUB_RUN_ID:-manual-$}-${GITHUB_RUN_ATTEMPT:-1}"
      mkdir -p "$RECEIPT_DIR"
      cp "$EVIDENCE/cleanup-state.txt" "$RECEIPT_DIR/cleanup-state.txt"
      cp "$EVIDENCE/source-result.txt" "$RECEIPT_DIR/source-result.txt"
      [[ ! -s "$EVIDENCE/missing-native-sources.txt" ]] ||
        cp "$EVIDENCE/missing-native-sources.txt" "$RECEIPT_DIR/missing-native-sources.txt"
      [[ ! -s "$EVIDENCE/signed-proof.txt" ]] ||
        cp "$EVIDENCE/signed-proof.txt" "$RECEIPT_DIR/signed-proof.txt"
    fi
    [[ "$SCRATCH" == "$TMP_PARENT"/u1a-option-d-* ]] && rm -rf -- "$SCRATCH"
  fi
  echo "U1A option D source $SHA: $([[ "$code" == 0 ]] && echo PASS || echo HOLD)"
  exit "$code"
}
trap cleanup EXIT

cd "$PROJECT"
PHASE="initialize-unique-supabase-project"
supabase init --force >"$EVIDENCE/init.log" 2>&1
mkdir -p "$PROJECT/supabase/migrations"
cp "$MIGRATIONS"/*.sql "$PROJECT/supabase/migrations/"
python3 - "$PROJECT/supabase/config.toml" "$EVIDENCE/ports.txt" <<'PY'
from pathlib import Path
import re,secrets,socket,sys,uuid
config=Path(sys.argv[1])
seen=set()
def free_port():
    sample=list(range(38000,61000))
    secrets.SystemRandom().shuffle(sample)
    for port in sample[:512]:
        if port in seen or port in (54322,55432): continue
        with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as sock:
            try: sock.bind(("0.0.0.0",port))
            except OSError: continue
            seen.add(port)
            return port
    raise SystemExit("STOP: no available wildcard-bindable host port")
api,db=free_port(),free_port()
ident="u1a_disposable_"+uuid.uuid4().hex[:12]
section=""
found=set()
out=[]
for line in config.read_text(encoding="utf8").splitlines(keepends=True):
    val=line.strip()
    if val.startswith("[") and val.endswith("]"): section=val
    if section=="" and re.match(r"project_id\s*=",val):
        line=f'project_id = "{ident}"\n'; found.add("project")
    elif section=="[api]" and re.match(r"port\s*=",val):
        line=f"port = {api}\n"; found.add("api")
    elif section=="[db]" and re.match(r"port\s*=",val):
        line=f"port = {db}\n"; found.add("db")
    out.append(line)
if found!={"project","api","db"}: raise SystemExit("STOP: config could not isolate all endpoints")
config.write_text("".join(out),encoding="utf8")
Path(sys.argv[2]).write_text(f"{ident}\n{api}\n{db}\n",encoding="utf8")
PY
# RiverSong macOS includes Bash 3.2, which has no mapfile/readarray.
PROJECT_ID="$(sed -n '1p' "$EVIDENCE/ports.txt")"
API_PORT="$(sed -n '2p' "$EVIDENCE/ports.txt")"
DB_PORT="$(sed -n '3p' "$EVIDENCE/ports.txt")"
[[ "$PROJECT_ID" =~ ^u1a_disposable_[a-f0-9]{12}$ ]] ||
 { echo 'STOP: invalid unique test project identity'; exit 1; }
[[ "$API_PORT" =~ ^[0-9]{5}$ && "$DB_PORT" =~ ^[0-9]{5}$ ]] ||
 { echo 'STOP: invalid ephemeral test ports'; exit 1; }
DB_URL="postgresql://postgres:postgres@127.0.0.1:$DB_PORT/postgres"
echo "SOURCE_SHA=$SHA; ISOLATED_PROJECT=$PROJECT_ID; LOOPBACK_API=$API_PORT; LOOPBACK_DB=$DB_PORT"
STARTED=true
PHASE="launch-local-auth-rest-postgres"
supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor \
  >"$EVIDENCE/startup.log" 2>&1 ||
 { echo 'HOLD: isolated local Supabase startup failed (no other project changed)'; exit 1; }
query() { psql "$DB_URL" -X -At -v ON_ERROR_STOP=1 -c "$1"; }
[[ "$(query 'SELECT current_database()')" == postgres ]] ||
 { echo 'STOP: not the isolated local database'; exit 1; }

# Source-only migrations MUST reconstruct actual Noel sources. Missing
# schemas/functions are a HOLD, never a reason to synthesize grants.
PHASE="native-schema-source-parity"
missing=0
for rel in atlas.organizations atlas.ledgers atlas.work_requirements atlas.work_items \
 atlas.farms atlas.growing_objects atlas.ledger_organization_participations \
 atlas.subject_disclosure_decision_events_v1 ledger.ledgers ledger.seats \
 reality.entities foundry.events foundry.workspace_authority_registry_v1 \
 foundry.source_custody_review_cases_v1 auth.users auth.sessions; do
  if [[ "$(query "SELECT (to_regclass('$rel') IS NOT NULL)::text")" != true ]]; then
    echo "MISSING_SOURCE_TABLE: $rel" | tee -a "$EVIDENCE/missing-native-sources.txt"
    missing=1
  fi
done
for sig in \
 'atlas.foundry_current_signed_principal_v1()' \
 'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)' \
 'atlas.current_principal_id_v1()' \
 'atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)' \
 'atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)' \
 'atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)' \
 'atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)' \
 'atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)' \
 'atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text)' \
 'auth.uid()'; do
  if [[ "$(query "SELECT (to_regprocedure('$sig') IS NOT NULL)::text")" != true ]]; then
    echo "MISSING_SOURCE_FUNCTION: $sig" | tee -a "$EVIDENCE/missing-native-sources.txt"
    missing=1
  fi
done
[[ "$missing" == 0 ]] || { echo 'HOLD: incomplete versioned schema, no fictional fixture'; exit 1; }
[[ "$(query 'SELECT count(*) FROM auth.users')" == 0 ]] ||
 { echo 'STOP: nonempty Auth source, not an empty fictional clone'; exit 1; }
[[ "$(query 'SELECT count(*) FROM atlas.work_items')" == 0 ]] ||
 { echo 'STOP: native Work already exists'; exit 1; }
[[ "$(query "SELECT (to_regclass('atlas.governed_rulebook_versions_v1') IS NULL)::text")" == true ]] ||
 { echo 'STOP: U1A already installed'; exit 1; }

PHASE="install-source-owned-fictional-c1-fixture"
psql "$DB_URL" -X -v ON_ERROR_STOP=1 \
 -f "$ROOT/validation/fixtures/20261026215011_atlas_universal_original_work_integrated_v1.sql" \
 >"$EVIDENCE/fictional-c1.log" 2>&1 ||
 { echo 'HOLD: source-owned fictional C1 fixture could not install'; exit 1; }
PHASE="signed-u1a-governed-root-revision-review"
export U1A_DISPOSABLE_DB_PORT="$DB_PORT"
export U1A_DISPOSABLE_PROJECT_DIR="$PROJECT"
python3 "$HERE/run_signed_u1a_on_fresh_clone_v1.py" --db-url "$DB_URL" \
 --confirm-fresh-disposable --output "$EVIDENCE/signed-proof.txt" \
 >"$EVIDENCE/signed-test.log" 2>&1 ||
 { echo 'HOLD: real local GoTrue+REST signed proof failed'; exit 1; }
[[ -s "$EVIDENCE/signed-proof.txt" ]] ||
 { echo 'HOLD: signed proof returned no evidence'; exit 1; }
echo 'PASS: fully isolated, genuine signed U1A proof on RiverSong'

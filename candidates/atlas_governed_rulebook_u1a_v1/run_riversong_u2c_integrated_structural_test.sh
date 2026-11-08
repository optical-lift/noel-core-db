#!/usr/bin/env bash
# UNI-OPS-01 held U2C: source-owned fresh Supabase migration and SQL compilation on Atlas runner.
# NO signed U2 worker acceptance, original Work or production release.
# Nothing may reach production or the older 55432/noel_schema_clone instance.
set -euo pipefail
umask 077
[[ $# -eq 0 ]] || { echo 'STOP: no arguments supported'; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
[[ "$HERE" == "$ROOT/candidates/atlas_governed_rulebook_u1a_v1" ]] ||
 { echo 'STOP: unexpected source location'; exit 2; }
[[ "$(git -C "$ROOT" rev-parse HEAD)" == "$UNI_OPS_INTEGRATED_NOEL_SHA" ]] ||
 { echo 'STOP: exact immutable Noel U2C test head required'; exit 2; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] ||
 { echo 'STOP: dirty source checkout'; exit 2; }
SHA="$(git -C "$ROOT" rev-parse HEAD)"
[[ "$SHA" =~ ^[a-f0-9]{40}$ ]] || { echo 'STOP: invalid source SHA'; exit 2; }
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  # Noel is not where RiverSong is registered. The established, protected
  # carrier is optical-lift/atlas on its macOS atlas-verifier label; it pins
  # one immutable Noel commit into a disposable checkout.
  case "${GITHUB_REPOSITORY:-}:$(printf '%s' "${RUNNER_NAME:-}" | tr '[:upper:]' '[:lower:]')" in
    optical-lift/atlas:riversong|optical-lift/atlas:riversong-lex)
      [[ "${U1A_ATLAS_CARRIER_SHA:-}" == "$SHA" ]] ||
        { echo 'STOP: pinned Atlas carrier source SHA does not match'; exit 2; };;
    *)
      echo 'STOP: only the established Atlas RiverSong carrier may execute Actions test'; exit 2;;
  esac
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
  echo "UNI-OPS U2C held source composition $SHA: $([[ "$code" == 0 ]] && echo PASS || echo HOLD)"
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

# Name-only schema checks are inadequate for SECURITY DEFINER code. A fresh
# local clone must match pinned READ-ONLY native source-definition fingerprints
# from Noel for all nine authority/Foundry methods. No live DB endpoint is
# ever accessed from RiverSong; this file has names/hashes only.
PHASE="verified-native-authority-source-fingerprints"
FINGERPRINTS="$HERE/native_source_fingerprints_20261103.tsv"
[[ -s "$FINGERPRINTS" ]] ||
 { echo 'STOP: required source fingerprint provenance unavailable'; exit 1; }
# Validate signatures/MD5s before embedding any reviewed signature in SQL.
python3 - "$FINGERPRINTS" <<'PY'
from pathlib import Path
import re,sys
rows=[s.strip() for s in Path(sys.argv[1]).read_text().splitlines()
      if s.strip() and not s.startswith("#")]
if len(rows)!=9: raise SystemExit("STOP: nine canonical source definitions required")
for row in rows:
    pieces=row.split("|")
    if len(pieces)!=2 or not re.fullmatch(
       r'atlas\.[a-z_0-9]+\([a-z0-9_,\[\]]*\)',pieces[0]) or not re.fullmatch(
       r'[a-f0-9]{32}',pieces[1]):
        raise SystemExit("STOP: invalid source fingerprint record")
PY
verified=0
fingerprint_mismatch=0
while IFS='|' read -r signature expected; do
  [[ "$signature" == atlas.* ]] || continue
  actual="$(query "SELECT md5(pg_get_functiondef(to_regprocedure('$signature')))")"
  if [[ "$actual" != "$expected" ]]; then
    echo "STALE_OR_SUBSTITUTE_SOURCE: $signature" | tee -a "$EVIDENCE/missing-native-sources.txt"
    fingerprint_mismatch=1
  fi
  verified=$((verified+1))
done <"$FINGERPRINTS"
[[ "$verified" == 9 && "$fingerprint_mismatch" == 0 ]] ||
 { echo 'HOLD: nine approved native source definitions must match exactly before signed test'; exit 1; }

[[ "$(query 'SELECT count(*) FROM auth.users')" == 0 ]] ||
 { echo 'STOP: nonempty Auth source, not an empty fictional clone'; exit 1; }
[[ "$(query 'SELECT count(*) FROM atlas.work_items')" == 0 ]] ||
 { echo 'STOP: native Work already exists'; exit 1; }
[[ "$(query "SELECT (to_regclass('atlas.governed_rulebook_versions_v1') IS NULL)::text")" == true ]] ||
 { echo 'STOP: U1A already installed'; exit 1; }

PHASE="verify_pinned_u2c_test_sources"
[[ -n "$UNI_OPS_PIN_ROOT" && "$UNI_OPS_PIN_ROOT" == "$RUNNER_TEMP"/atlas-uniops-noel-pins.* ]] ||
 { echo 'STOP: Atlas exact source pin root absent'; exit 1; }
MANIFEST="$UNI_OPS_PIN_ROOT/source-manifest.json"
TEST_SQL="$UNI_OPS_TEST_SQL"
[[ -s "$MANIFEST" && "$TEST_SQL" == "$RUNNER_TEMP"/UNI_OPS_ACCEPTED_FIRST_*_TEST_ONLY.sql && -s "$TEST_SQL" ]] ||
 { echo 'STOP: exact test-only SQL and manifest missing'; exit 1; }
python3 - "$MANIFEST" "$TEST_SQL" "$EVIDENCE" <<'PY'
from pathlib import Path
import hashlib,json,sys
m=json.loads(Path(sys.argv[1]).read_text())
raw=Path(sys.argv[2]).read_bytes()
out=Path(sys.argv[3])
names=("lifecycle-shadow","lifecycle-single-transition","r01-r02-composed-native",
       "u1a-exact-foundry-rulebook","u1b-native-scope-history",
       "u2a-preoriginal-offer","u2b-signed-root-finalize",
       "u2c-single-authority-arbiter","u2c-accepted-only-original-guard",
       "u2c-close-old-standing-bypasses","u2c-schema-and-acl-postconditions")
rows=m.get("stages",[])
if m.get("success") is not True or m.get("kind")!="UNI_OPS_ACCEPTED_FIRST_DISPOSABLE_ONLY":
    raise SystemExit("BLOCKED: test-only source manifest invalid")
if tuple(row.get("stage") for row in rows)!=names or len(rows)!=11:
    raise SystemExit("BLOCKED: pinned source order differs")
if hashlib.sha256(raw).hexdigest()!=m.get("scratch_file_sha256"):
    raise SystemExit("BLOCKED: SQL source digest changed")
text=raw.decode("utf8")
with (out/"stages.tsv").open("w") as listing:
    for i,row in enumerate(rows,1):
        name=row["stage"]
        begin=f"-- BEGIN PINNED STAGE {name} blob:{row['blob']}\n"
        end=f"-- END PINNED STAGE {name}\n"
        if text.count(begin)!=1 or text.count(end)!=1:
            raise SystemExit("BLOCKED: pinned SQL stage delimiters changed")
        body=text.split(begin,1)[1].split(end,1)[0]
        if len(body)<100 or not body.endswith("\n"):
            raise SystemExit("BLOCKED: incomplete source SQL")
        dest=out/f"u2c-stage-{i:02d}.sql"
        dest.write_text(body)
        listing.write(f"{i}\t{name}\t{dest}\n")
PY
PHASE="held_source_sql_composition"
completed=0
while IFS="$(printf '\t')" read -r index stage file; do
  PHASE="$stage"
  if ! psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f "$file" \
    >"$EVIDENCE/stage-$index.log" 2>&1; then
    kind="$(python3 - "$EVIDENCE/stage-$index.log" <<'PY'
import re,sys
from pathlib import Path
data=Path(sys.argv[1]).read_text(errors="replace")
states=re.findall(r'ERROR:\s+([0-9A-Z]{5}):',data)
classes={'42P01':'missing_relation','42703':'missing_column',
         '42883':'missing_function','42710':'duplicate_object',
         '42P07':'duplicate_relation','42601':'sql_syntax',
         '42501':'privilege','23514':'constraint',
         '23505':'uniqueness','3F000':'missing_schema'}
print(classes.get(states[0],'other_sqlstate') if states else 'no_sqlstate')
PY
)"
    echo "HELD: pinned SQL stage $index/11 ($stage), class=$kind"
    exit 1
  fi
  completed=$((completed+1))
  echo "PASS pinned held SQL stage $completed/11: $stage"
done <"$EVIDENCE/stages.tsv"
[[ "$completed" == 11 ]] || { echo 'HELD: missing source SQL stage'; exit 1; }
PHASE="complete_structural_only"
echo 'PASS: exact migrated fresh Supabase + 11 held SQL stages, original source Work/Subject'
echo 'HOLD: genuine U1B worker acceptance and first original Work are NOT signed-tested'

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/validate-production-schema-clone.sh \
  --migration-version <14 digits> \
  --release-lane <atlas|wnph|noel|shared> \
  --candidate-migration <path> \
  [--candidate-fixture <path>] \
  [--candidate-validation <path>] \
  --roles-dump <path> \
  --schema-dump <path> \
  --artifacts-dir <path>

Runs the same disposable production-schema-clone validation used by CI.
Both dump inputs are read-only snapshots; fixture data, candidate DDL/DML, and
postconditions are applied to the local disposable database only.
EOF
  exit 2
}

version=""
lane=""
candidate_migration=""
candidate_fixture=""
candidate_validation=""
roles_dump=""
schema_dump=""
artifacts_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --migration-version) version="${2:-}"; shift 2 ;;
    --release-lane) lane="${2:-}"; shift 2 ;;
    --candidate-migration) candidate_migration="${2:-}"; shift 2 ;;
    --candidate-fixture) candidate_fixture="${2:-}"; shift 2 ;;
    --candidate-validation) candidate_validation="${2:-}"; shift 2 ;;
    --roles-dump) roles_dump="${2:-}"; shift 2 ;;
    --schema-dump) schema_dump="${2:-}"; shift 2 ;;
    --artifacts-dir) artifacts_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ ! "$version" =~ ^[0-9]{14}$ ]]; then
  usage
fi
if [[ "$lane" != "atlas" && "$lane" != "wnph" && "$lane" != "noel" && "$lane" != "shared" ]]; then
  usage
fi
for required_path in "$candidate_migration" "$roles_dump" "$schema_dump"; do
  if [ ! -s "$required_path" ]; then
    echo "Required validation input is missing or empty: $required_path" >&2
    exit 2
  fi
done
for optional_path in "$candidate_fixture" "$candidate_validation"; do
  if [ -n "$optional_path" ] && [ ! -s "$optional_path" ]; then
    echo "Optional validation input was supplied but is missing or empty: $optional_path" >&2
    exit 2
  fi
done
if [ -z "$artifacts_dir" ]; then
  usage
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_migration="$(realpath "$candidate_migration")"
if [ -n "$candidate_fixture" ]; then candidate_fixture="$(realpath "$candidate_fixture")"; fi
if [ -n "$candidate_validation" ]; then candidate_validation="$(realpath "$candidate_validation")"; fi
roles_dump="$(realpath "$roles_dump")"
schema_dump="$(realpath "$schema_dump")"
mkdir -p "$artifacts_dir"
artifacts_dir="$(cd "$artifacts_dir" && pwd)"

for command_name in supabase psql python3 realpath; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required for production-schema-clone validation." >&2
    exit 2
  fi
done
supabase_version="$(supabase --version | tail -n 1)"
if [ "$supabase_version" != "2.116.0" ]; then
  echo "Supabase CLI 2.116.0 is required; found $supabase_version." >&2
  exit 2
fi

runtime_dir="$(mktemp -d)"
project_dir="$runtime_dir/project"
schema_clone="$runtime_dir/production-user-schema.sql"
database_url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
phase="preflight"
local_started=false
signed_http_probe=false
signed_date_http_probe=false
signed_schedule_preflight_probe=false
signed_event_writer_probe=false
if [ "$lane" = "atlas" ] && [ "$version" = "20261019201528" ]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "C1 signed HTTP test requires its disposable fixture and postconditions." >&2
    exit 2
  fi
  signed_http_probe=true
fi
# Only run the source-specific signed proof when the corresponding immutable
# candidate and disposable fixture have been admitted. No remote HTTP.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_ledger_occurrence_date_evidence_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Ledger date signed HTTP proof requires disposable fixture and postconditions." >&2
    exit 2
  fi
  signed_date_http_probe=true
fi
# Require full Auth+REST for this specific source-owned schedule preflight.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_ledger_occurrence_schedule_preflight_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Schedule preflight signed HTTP proof requires synthetic fixture and postconditions." >&2
    exit 2
  fi
  signed_schedule_preflight_probe=true
fi
# One source-owned Event schedule writer, never production: genuine signed
# root/member/outsider calls on synthetic disposable clone only.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_one_event_schedule_writer_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "One Event writer signed HTTP proof requires source fixture and postconditions." >&2
    exit 2
  fi
  signed_event_writer_probe=true
fi

finish() {
  result=$?
  if [ "$local_started" = true ]; then
    (cd "$project_dir" && supabase stop --no-backup) >>"$artifacts_dir/cleanup.log" 2>&1 || true
  fi
  if [ "$result" -ne 0 ]; then
    if [ ! -f "$artifacts_dir/summary.md" ]; then
      {
        echo '# Production schema clone validation'
        echo
        echo "**FAILED during ${phase}.**"
        echo
        echo 'Inspect the attached raw diagnostics for the exact command output.'
      } > "$artifacts_dir/summary.md"
    else
      printf '\nValidation command exited during `%s`.\n' "$phase" >> "$artifacts_dir/summary.md"
    fi
  fi
  rm -rf "$runtime_dir"
  exit "$result"
}
trap finish EXIT

cd "$repo_root"
phase="release-lane custody check"
bash scripts/check-migration-release-lane.sh "$version" "$lane" "$candidate_migration"

if [ -n "$candidate_fixture" ]; then
  phase="validation fixture safety check"
  python3 - "$candidate_fixture" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding='utf-8')
text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
text = re.sub(r'--[^\n]*', ' ', text)
normalized = re.sub(r'\s+', ' ', text).strip()
forbidden = re.compile(
    r'\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|listen|notify|security)\b',
    re.I,
)
if forbidden.search(normalized):
    raise SystemExit('validation fixture may contain data setup only; schema/privilege/procedural statements are forbidden')
statements = [s.strip() for s in normalized.split(';') if s.strip()]
allowed = re.compile(r'^(insert\s+into|update\s+|delete\s+from|select\s+)', re.I)
if not statements or any(not allowed.match(s) for s in statements):
    raise SystemExit('validation fixture statements must begin with INSERT, UPDATE, DELETE, or SELECT')
print(f'validation fixture safety check passed ({len(statements)} statement(s))')
PY
fi

phase="schema dump sanitation"
python3 - "$schema_dump" "$schema_clone" <<'PY'
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
lines = source.read_text(encoding='utf-8').splitlines(keepends=True)
pattern = re.compile(r'^\s*ALTER TABLE .+ (DISABLE|ENABLE) TRIGGER ALL;\s*$')
kept = []
disabled = 0
enabled = 0
for line in lines:
    match = pattern.match(line)
    if not match:
        kept.append(line)
    elif match.group(1) == 'DISABLE':
        disabled += 1
    else:
        enabled += 1
if disabled != enabled:
    raise SystemExit(
        f'unbalanced restore-only trigger toggles: {disabled} disable vs {enabled} enable'
    )
target.write_text(''.join(kept), encoding='utf-8')
print(f'removed {disabled + enabled} restore-only trigger toggle statement(s)')
PY

phase="disposable database startup"
mkdir -p "$project_dir"
cd "$project_dir"
supabase init --force

# Choose an isolated local database port and project identity. This matters
# on persistent/self-hosted runners where another Supabase project may already
# own the CLI default port 54322. No production URL is used beyond the prior
# schema-only snapshot step.
local_database_port="$(python3 - <<'PY'
import socket
for port in range(55322, 55922):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        if sock.connect_ex(("127.0.0.1", port)) != 0:
            print(port)
            break
else:
    raise SystemExit("No available local database validation port")
PY
)"
python3 - "$project_dir/supabase/config.toml" "$local_database_port" "$version" <<'PY'
from pathlib import Path
import re
import sys
import uuid

config_path = Path(sys.argv[1])
port = int(sys.argv[2])
version = sys.argv[3]
text = config_path.read_text(encoding="utf-8")
section = ""
found_port = False
found_identity = False
out = []
for line in text.splitlines(keepends=True):
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped
    if section == "" and re.match(r'^project_id\s*=', stripped):
        line = f'project_id = "validation_{version}_{uuid.uuid4().hex[:8]}"\n'
        found_identity = True
    elif section == "[db]" and re.match(r'^port\s*=', stripped):
        line = f'port = {port}\n'
        found_port = True
    out.append(line)
if not found_port or not found_identity:
    raise SystemExit("Could not establish isolated local project ID and database port")
config_path.write_text("".join(out), encoding="utf-8")
print(f"Disposable local validation DB port: {port}")
PY
database_url="postgresql://postgres:postgres@127.0.0.1:${local_database_port}/postgres"
local_started=true
startup_attempt=1
startup_max_attempts=4
startup_delays=(0 15 30 60)
while [ "$startup_attempt" -le "$startup_max_attempts" ]; do
  startup_log="$artifacts_dir/disposable-database-startup-attempt-${startup_attempt}.log"
  if [ "${startup_delays[$((startup_attempt - 1))]}" -gt 0 ]; then
    sleep "${startup_delays[$((startup_attempt - 1))]}"
  fi

  set +e
  if [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||
     [ "$signed_schedule_preflight_probe" = true ] ||
      [ "$signed_event_writer_probe" = true ]; then
    # Full LOCAL Auth + REST + Postgres only when a signed-token proof is active.
    # Both probes stay on a disposable clone and refuse remote API endpoints.
    supabase start >"$startup_log" 2>&1
  else
    supabase db start >"$startup_log" 2>&1
  fi
  startup_status=$?
  set -e

  if [ "$startup_status" -eq 0 ]; then
    cat "$startup_log"
    break
  fi

  cat "$startup_log" >&2
  # An occupied local port is not a registry rate limit. Isolated port
  # selection above avoids that failure rather than blindly retrying it.
  if ! grep -Eiq '(toomanyrequests|too many requests|rate[ -]?limit|rate exceeded|429)' "$startup_log"; then
    echo "Disposable database startup failed for a non-registry-throttling reason on attempt ${startup_attempt}." >&2
    exit "$startup_status"
  fi

  if [ "$startup_attempt" -eq "$startup_max_attempts" ]; then
    echo "Disposable database startup remained registry-throttled after ${startup_max_attempts} attempts." >&2
    exit "$startup_status"
  fi

  echo "Registry throttling detected during disposable database startup; cleaning partial state before retry $((startup_attempt + 1))/${startup_max_attempts}." >&2
  supabase stop --no-backup >>"$artifacts_dir/cleanup.log" 2>&1 || true
  startup_attempt=$((startup_attempt + 1))
done

phase="production custom-role restore"
psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$roles_dump" \
  >"$artifacts_dir/restore-roles.log" 2>&1

phase="production user-schema restore"
psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$schema_clone" \
  >"$artifacts_dir/restore-schema.log" 2>&1

run_lint() {
  lint_name="$1"
  lint_output="$artifacts_dir/schema-lint-${lint_name}.raw.log"
  set +e
  if [[ "$lane" == "noel" ]]; then
    # Noel owns draft Reality Pools and core/intelligence evidence infrastructure.
    # Compare *changes* to the inherited lint baseline, not existing lint debt.
    supabase db lint --local --schema draft,core,intelligence --level error --fail-on error >"$lint_output" 2>&1
  else
    supabase db lint --local --schema atlas --level error --fail-on error >"$lint_output" 2>&1
  fi
  lint_status=$?
  set -e
  printf '%s\n' "$lint_status" > "$artifacts_dir/schema-lint-${lint_name}.exit-code.txt"
}

phase="baseline domain schema lint"
run_lint baseline

if [ -n "$candidate_fixture" ]; then
  phase="candidate validation fixture application"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_fixture" \
    >"$artifacts_dir/candidate-fixture.log" 2>&1
else
  echo 'No candidate validation fixture is defined.' >"$artifacts_dir/candidate-fixture.log"
fi

phase="candidate migration application"
psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_migration" \
  >"$artifacts_dir/candidate-migration.log" 2>&1

phase="candidate migration postconditions"
if [ -n "$candidate_validation" ]; then
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_validation" \
    >"$artifacts_dir/postconditions.log" 2>&1
else
  echo "No candidate migration-specific postcondition file is defined for ${version}." \
    >"$artifacts_dir/postconditions.log"
fi

if [ "$signed_http_probe" = true ]; then
  phase="signed local HTTP API authorization matrix"
  python3 "$repo_root/scripts/validate-atlas-c1-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-http-summary.txt" \
    >"$artifacts_dir/signed-http.log" 2>&1
fi
if [ "$signed_date_http_probe" = true ]; then
  phase="signed local Ledger date evidence HTTP authorization matrix"
  python3 "$repo_root/scripts/validate-atlas-date-evidence-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-date-http-summary.txt" \
    >"$artifacts_dir/signed-date-http.log" 2>&1
fi
if [ "$signed_schedule_preflight_probe" = true ]; then
  phase="signed local source-scoped schedule preflight authorization matrix"
  python3 "$repo_root/scripts/validate-atlas-schedule-preflight-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-schedule-preflight-summary.txt" \
    >"$artifacts_dir/signed-schedule-preflight.log" 2>&1
fi
if [ "$signed_event_writer_probe" = true ]; then
  phase="signed local canonical Event schedule writer and authority matrix"
  python3 "$repo_root/scripts/validate-atlas-one-event-schedule-writer-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-one-event-writer-summary.txt" \
    >"$artifacts_dir/signed-one-event-writer.log" 2>&1
fi

phase="candidate domain schema lint"
cd "$project_dir"
run_lint candidate

phase="candidate lint delta comparison"
python3 "$repo_root/scripts/compare-schema-lint.py" \
  "$artifacts_dir/schema-lint-baseline.raw.log" \
  "$artifacts_dir/schema-lint-candidate.raw.log" \
  --artifacts-dir "$artifacts_dir"

phase="local database advisors"
help="$(supabase db advisors --help 2>&1 || true)"
printf '%s\n' "$help" > "$artifacts_dir/advisors.log"
if printf '%s\n' "$help" | grep -q -- '--local'; then
  supabase db advisors --local >> "$artifacts_dir/advisors.log" 2>&1
else
  echo 'Pinned Supabase CLI does not expose local db advisors.' >> "$artifacts_dir/advisors.log"
fi

phase="complete"
printf '\nMigration postconditions and local database advisors also completed successfully.\n' \
  >> "$artifacts_dir/summary.md"
if [ "$signed_http_probe" = true ]; then
  printf '\nDisposable signed GoTrue + PostgREST HTTP authorization matrix also passed.\n' \
    >> "$artifacts_dir/summary.md"
fi

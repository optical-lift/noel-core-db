#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/validate-production-schema-clone.sh \
  --migration-version <14 digits> \
  --release-lane <atlas|wnph|shared> \
  --candidate-migration <path> \
  --roles-dump <path> \
  --schema-dump <path> \
  --artifacts-dir <path>

Runs the same disposable production-schema-clone validation used by CI.
Both dump inputs are read-only snapshots; candidate DDL is applied locally only.
EOF
  exit 2
}

version=""
lane=""
candidate_migration=""
roles_dump=""
schema_dump=""
artifacts_dir=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --migration-version) version="${2:-}"; shift 2 ;;
    --release-lane) lane="${2:-}"; shift 2 ;;
    --candidate-migration) candidate_migration="${2:-}"; shift 2 ;;
    --roles-dump) roles_dump="${2:-}"; shift 2 ;;
    --schema-dump) schema_dump="${2:-}"; shift 2 ;;
    --artifacts-dir) artifacts_dir="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ ! "$version" =~ ^[0-9]{14}$ ]]; then
  usage
fi
if [[ "$lane" != "atlas" && "$lane" != "wnph" && "$lane" != "shared" ]]; then
  usage
fi
for required_path in "$candidate_migration" "$roles_dump" "$schema_dump"; do
  if [ ! -s "$required_path" ]; then
    echo "Required validation input is missing or empty: $required_path" >&2
    exit 2
  fi
done
if [ -z "$artifacts_dir" ]; then
  usage
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
candidate_migration="$(realpath "$candidate_migration")"
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
local_started=true
supabase db start

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
  supabase db lint --local --schema atlas --level error --fail-on error >"$lint_output" 2>&1
  lint_status=$?
  set -e
  printf '%s\n' "$lint_status" > "$artifacts_dir/schema-lint-${lint_name}.exit-code.txt"
}

phase="baseline Atlas schema lint"
run_lint baseline

phase="candidate migration application"
psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_migration" \
  >"$artifacts_dir/candidate-migration.log" 2>&1

phase="canonical migration postconditions"
cd "$repo_root"
mapfile -t validations < <(find validation/migrations -maxdepth 1 -type f -name "${version}_*.sql" -print 2>/dev/null || true)
if [ "${#validations[@]}" -gt 1 ]; then
  echo "Expected at most one canonical postcondition file for ${version}; found ${#validations[@]}." >&2
  exit 1
fi
if [ "${#validations[@]}" -eq 1 ]; then
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "${validations[0]}" \
    >"$artifacts_dir/postconditions.log" 2>&1
else
  echo "No canonical migration-specific postcondition file is defined for ${version}." \
    >"$artifacts_dir/postconditions.log"
fi

phase="candidate Atlas schema lint"
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

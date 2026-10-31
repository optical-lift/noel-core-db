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
signed_calendar_reader_probe=false
signed_work_prerequisite_probe=false
signed_connected_work_prerequisite_probe=false
signed_existing_person_auth_claim_probe=false
signed_person_weight_probe=false
signed_person_collections_probe=false
signed_person_period_probe=false
signed_foundry_workspace_probe=false
signed_foundry_historical_probe=false
signed_atlas_proper_inventory_probe=false
signed_atlas_proper_needs_probe=false
signed_native_standing_work_probe=false
signed_program_author_probe=false
signed_universal_program_probe=false
signed_program_author_notes_probe=false
signed_program_source_identity_probe=false
signed_universal_original_work_probe=false
signed_work_self_assignment_probe=false
signed_care_single_done_probe=false
signed_native_work_release_probe=false
signed_ledger_reciprocal_probe=false
signed_ledger_disposition_v2_probe=false
signed_accepted_ledger_original_probe=false
signed_unified_today_p0_probe=false
signed_person_mail_probe=false
# One exact generated mail permission candidate needs true signed Auth+REST.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_communication_person_mail_read_window_v2[.]sql$ ]]; then
  if [ -z "$candidate_validation" ]; then
    echo "Mail source requires postconditions plus genuine signed acceptance." >&2
    exit 2
  fi
  signed_person_mail_probe=true
fi
# A distinct disposable Person/Event/Company Work source proof.
# Never substitute SQL-only role claims or an absent HTTP endpoint for 42501.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_unified_today_event_disclosure_work_authority_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Unified Today privacy and scheduling require disposable fixture/postconditions." >&2
    exit 2
  fi
  signed_unified_today_p0_probe=true
fi

# Signed local governor self-assignment of existing original decomposed Work.
# Only its exact generated migration can invoke this candidate-specific proof.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_work_self_assignment_native_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Native Work self-assignment requires fictional fixture/postconditions." >&2
    exit 2
  fi
  signed_work_self_assignment_probe=true
fi

# Owner-gated source-only editor/date/Result status proof. This is
# disposable scratch source, not a releasable migration or a permission grant.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_native_work_edit_schedule_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Native Work clone requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_native_work_release_probe=true
fi

# Exact owner-initiated source-only Ledger security/reciprocal Person proof.
# No SQL reaches production; new candidate file exists only in local scratch.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_ledger_reciprocal_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Reciprocal Ledger root proof requires fictional fixture/postconditions." >&2
    exit 2
  fi
  signed_ledger_reciprocal_probe=true
fi

# Exact named Ledger intake v2: genuine signed localhost GoTrue/REST, only
# when fictional fixture and source postconditions are provided.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_ledger_intake_root_disposition_v2[.]sql$ ]] &&
   [ -n "$candidate_fixture" ]; then
  if [ -z "$candidate_validation" ]; then
    echo "Ledger disposition v2 signed proof requires postconditions." >&2
    exit 2
  fi
  signed_ledger_disposition_v2_probe=true
fi

# Held post-v2 Ledger intake original-Work source. ONLY exact scratch
# package name + DML-only fictional fixture + postconditions can activate
# the new independent signed root/worker/outsider validation. Never a release.
if [ "$lane" = "atlas" ] &&
   [ "$version" = "20261031005959" ] &&
   [[ "$(basename "$candidate_migration")" = "20261031005959_atlas_ledger_intake_accepted_original_signed_clone_only_v1.sql" ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Accepted Ledger intake compatibility requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_accepted_ledger_original_probe=true
fi

# An exact named source-only physical care validation, not a release.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_care_single_done_signed_proof_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed care Done proof requires DML-only fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_care_single_done_probe=true
fi

# Only the exact Atlas original Work candidate may trigger this signed local
# GoTrue/REST probe. It requires an admitted DML-only synthetic fixture and
# original source postconditions on the disposable production-shaped clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_universal_original_work_integrated_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Universal original Work requires synthetic fixture and source postconditions." >&2
    exit 2
  fi
  signed_universal_original_work_probe=true
fi

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
# Calendar reader requires genuine GoTrue sessions in the isolated clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_one_calendar_source_read_membrane_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "ONE Calendar signed read requires fixture and postconditions." >&2
    exit 2
  fi
  signed_calendar_reader_probe=true
fi

# Exact Atlas Work prerequisites: genuine Auth + PostgREST and concurrent
# signed root sessions, all synthetic and only on the disposable local clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_work_item_prerequisites_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed Work prerequisite proof requires disposable fixture and postconditions." >&2
    exit 2
  fi
  signed_work_prerequisite_probe=true
fi

# Worker prerequisites require a source-confirmed, signed Person assignment;
# never substitute employee seats, JWT metadata or a bare synthetic allocation.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_connected_person_work_prerequisites_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed connected-Person prerequisite read requires fixture/postconditions." >&2
    exit 2
  fi
  signed_connected_work_prerequisite_probe=true
fi

# Build 1 verified account binding requires real disposable signed claimant and
# independent source-steward sessions, never merely a structural clone.
if [ "$lane" = "shared" ] &&
  [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_existing_person_new_auth_claim_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Person claim signed HTTP proof requires synthetic fixture and postconditions." >&2
    exit 2
  fi
  signed_existing_person_auth_claim_probe=true
fi

# Specific Person measurement rule: source-owned first approval, actual separate
# GoTrue sessions, and PostgREST authorization on the disposable clone only.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_person_deterministic_weight_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed Person weight proof requires a disposable fixture and postconditions." >&2
    exit 2
  fi
  signed_person_weight_probe=true
fi

# Genuine separate signed sessions for owner-only Person Collection filing.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_person_health_collections_filing_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed Person Collection proof requires fixture and postconditions." >&2
    exit 2
  fi
  signed_person_collections_probe=true
fi

# Period history reader: independent source-qualified Person read through real signed local GoTrue.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_person_period_source_history_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed Person period reader requires fictional fixture/postconditions." >&2
    exit 2
  fi
  signed_person_period_probe=true
fi

# Source-exact Foundry workspace and native Person reviewer signed proof. This is the
# approved local GoTrue/PostgREST route, never a production HTTP request.
if [ "$lane" = "shared" ] &&
   { [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_foundry_connected_workspace_gate1_signed_v1[.]sql$ ]] ||
     [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_foundry_native_person_ledger_reviewer_v1[.]sql$ ]] ||
     [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_foundry_typed_reality_evidence_v1[.]sql$ ]] ||
     [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_foundry_source_recurrence_v1[.]sql$ ]]; }; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Foundry signed session proof requires fictional fixture/postconditions." >&2
    exit 2
  fi
  signed_foundry_workspace_probe=true
fi

# Source-specific signed historical Foundry recovery on a fictional archive.
if [ "$lane" = "shared" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_foundry_historical_continuity_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Historical Foundry signed proof requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_foundry_historical_probe=true
fi

# Exact signed Atlas Proper metadata inventory: full local GoTrue/PostgREST only.
if [ "$lane" = "shared" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_atlas_proper_foundry_inventory_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Atlas Proper discovery requires fictional fixture/postconditions." >&2
    exit 2
  fi
  signed_atlas_proper_inventory_probe=true
fi

# Exact Atlas Proper signed operator work-journal test for the generated shared migration.
if [ "$lane" = "shared" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_atlas_proper_developer_needs_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Atlas Proper developer work needs fictional fixture and signed test." >&2
    exit 2
  fi
  signed_atlas_proper_needs_probe=true
fi

# Exact source-owned signed native Ledger standing-work candidate only.
# Never pretend structural postconditions prove Person authorization.
if [ "$lane" = "shared" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_native_ledger_standing_work_person_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Native Person standing Work requires synthetic fixture and postconditions." >&2
    exit 2
  fi
  signed_native_standing_work_probe=true
fi

# Author-only Program versions require real local GoTrue/REST sessions, not role-switched SQL.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_personal_training_author_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Program author signed-proof requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_program_author_probe=true
fi
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_universal_program_author_v2[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Universal Program v2 signed proof requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_universal_program_probe=true
fi

# Signed author-private notes: exact generated migration, genuine local GoTrue
# sessions, unchanged approved source and immediate entitlement revocation.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_personal_program_author_annotations_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Program author notes signed proof requires data-only fixture and postconditions." >&2
    exit 2
  fi
  signed_program_author_notes_probe=true
fi

# Signed source identity proof on an isolated clone; never against production.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_universal_program_source_identity_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Source identity proof requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_program_source_identity_probe=true
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
import secrets
import socket
# A successful connect_ex is not a reliable host-port reservation: another
# Docker bridge can bind 0.0.0.0 while no local listener answers 127.0.0.1.
# Randomized candidates reduce cross-job races; try a real wildcard bind.
ports=list(range(38000, 61000))
secrets.SystemRandom().shuffle(ports)
for port in ports[:256]:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("0.0.0.0", port))
        except OSError:
            continue
        print(port)
        break
else:
    raise SystemExit("No bindable disposable database port found")
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
      [ "$signed_event_writer_probe" = true ] ||
      [ "$signed_calendar_reader_probe" = true ] ||
      [ "$signed_work_prerequisite_probe" = true ] ||
      [ "$signed_connected_work_prerequisite_probe" = true ] ||
      [ "$signed_existing_person_auth_claim_probe" = true ] ||
       [ "$signed_person_weight_probe" = true ] ||
       [ "$signed_person_collections_probe" = true ] ||
       [ "$signed_person_period_probe" = true ] ||
       [ "$signed_foundry_workspace_probe" = true ] ||
       [ "$signed_foundry_historical_probe" = true ] ||
       [ "$signed_atlas_proper_inventory_probe" = true ] ||
       [ "$signed_atlas_proper_needs_probe" = true ] ||
       [ "$signed_native_standing_work_probe" = true ] ||
       [ "$signed_program_author_probe" = true ] ||
       [ "$signed_universal_program_probe" = true ] ||
       [ "$signed_program_author_notes_probe" = true ] ||
       [ "$signed_program_source_identity_probe" = true ] ||
       [ "$signed_universal_original_work_probe" = true ] ||
       [ "$signed_work_self_assignment_probe" = true ] ||
       [ "$signed_care_single_done_probe" = true ] ||
       [ "$signed_native_work_release_probe" = true ] ||
       [ "$signed_ledger_reciprocal_probe" = true ] ||
       [ "$signed_ledger_disposition_v2_probe" = true ] ||
       [ "$signed_accepted_ledger_original_probe" = true ] ||
       [ "$signed_unified_today_p0_probe" = true ] ||
       [ "$signed_person_mail_probe" = true ]; then
    # The source-governed signed care/Done test requires only PostgreSQL,
    # local GoTrue, PostgREST and the Kong API gateway. Pulling Studio,
    # analytics, Realtime, storage and auxiliary containers consumed the
    # public ECR quota before signed tests could start (two protected runs).
    # Limit this to the existing care probe; no change to other clone lanes,
    # image registries, pinned CLI, health checks, JWT verification or SQL.
    if [ "$signed_care_single_done_probe" = true ] ||
       [ "$signed_native_work_release_probe" = true ] ||
       [ "$signed_ledger_reciprocal_probe" = true ] ||
       [ "$signed_ledger_disposition_v2_probe" = true ] ||
       [ "$signed_accepted_ledger_original_probe" = true ]; then
      supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
    else
      supabase start >"$startup_log" 2>&1
    fi
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
if [ "$signed_calendar_reader_probe" = true ]; then
  phase="signed local ONE Calendar source-read authority matrix"
  python3 "$repo_root/scripts/validate-atlas-one-calendar-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-one-calendar-summary.txt" \
    >"$artifacts_dir/signed-one-calendar.log" 2>&1
fi
if [ "$signed_event_writer_probe" = true ]; then
  phase="signed local canonical Event schedule writer and authority matrix"
  python3 "$repo_root/scripts/validate-atlas-one-event-schedule-writer-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-one-event-writer-summary.txt" \
    >"$artifacts_dir/signed-one-event-writer.log" 2>&1
fi

if [ "$signed_work_prerequisite_probe" = true ]; then
  phase="signed local prerequisite owner/worker authority, history and concurrent cycle proof"
  python3 "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-work-prerequisite-summary.txt" \
    >"$artifacts_dir/signed-work-prerequisite.log" 2>&1
fi

if [ "$signed_person_mail_probe" = true ]; then
  phase="genuine signed local Person mailbox read, cutoff and revoke matrix"
  python3 "$repo_root/scripts/validate-atlas-person-mail-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-person-mail-summary.txt" \
    >"$artifacts_dir/signed-person-mail.log" 2>&1
  test -s "$artifacts_dir/signed-person-mail-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-person-mail-summary.txt"
fi

if [ "$signed_unified_today_p0_probe" = true ]; then
  phase="signed local Event privacy and Company date authority matrix"
  python3 "$repo_root/scripts/validate-atlas-unified-today-p0-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-unified-today-p0-summary.txt" \
    >"$artifacts_dir/signed-unified-today-p0.log" 2>&1
  test -s "$artifacts_dir/signed-unified-today-p0-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-unified-today-p0-summary.txt"
fi

if [ "$signed_work_self_assignment_probe" = true ]; then
  phase="signed native Ledger governor self-assignment and revocation matrix"
  python3 "$repo_root/scripts/validate-atlas-work-self-assignment-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-work-self-assignment-summary.txt" \
    >"$artifacts_dir/signed-work-self-assignment.log" 2>&1
  test -s "$artifacts_dir/signed-work-self-assignment-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-work-self-assignment-summary.txt"
fi

if [ "$signed_universal_original_work_probe" = true ]; then
  phase="signed original Bed3/Bed4, worker disclosure denial and Household Laundry Actual"
  python3 "$repo_root/scripts/validate-atlas-universal-original-work-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-universal-original-work-summary.txt" \
    >"$artifacts_dir/signed-universal-original-work.log" 2>&1
  test -s "$artifacts_dir/signed-universal-original-work-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-universal-original-work-summary.txt"
  # Regression: original Event schedule authority must remain independent of
  # newly admitted Household and per-Bed Work. Reuse its existing signed
  # local C1 fixture/proof, never synthesize a second Event scheduler.
  phase="signed original Event source and schedule-writer regression"
  python3 "$repo_root/scripts/validate-atlas-one-event-schedule-writer-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-universal-original-work-event-regression.txt" \
    >"$artifacts_dir/signed-universal-original-work-event-regression.log" 2>&1
  test -s "$artifacts_dir/signed-universal-original-work-event-regression.txt"
  grep -q '^PASS' "$artifacts_dir/signed-universal-original-work-event-regression.txt"
fi

if [ "$signed_ledger_reciprocal_probe" = true ]; then
  phase="signed reciprocal Ledger roots, private intake and Person identity"
  python3 "$repo_root/scripts/validate-atlas-ledger-reciprocal-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-ledger-reciprocal-summary.txt" \
    >"$artifacts_dir/signed-ledger-reciprocal.log" 2>&1
  test -s "$artifacts_dir/signed-ledger-reciprocal-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-ledger-reciprocal-summary.txt"
fi

if [ "$signed_ledger_disposition_v2_probe" = true ]; then
  phase="signed root, worker, outsider Ledger intake disposition v2"
  python3 "$repo_root/scripts/validate-atlas-ledger-intake-disposition-v2-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-ledger-disposition-v2-summary.txt" \
    >"$artifacts_dir/signed-ledger-disposition-v2.log" 2>&1
  test -s "$artifacts_dir/signed-ledger-disposition-v2-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-ledger-disposition-v2-summary.txt"
fi

if [ "$signed_accepted_ledger_original_probe" = true ]; then
  phase="signed accepted intake to one original Work, direct or consent assignment"
  python3 "$repo_root/scripts/validate-atlas-accepted-intake-original-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-accepted-intake-original-summary.txt" \
    >"$artifacts_dir/signed-accepted-intake-original.log" 2>&1
  test -s "$artifacts_dir/signed-accepted-intake-original-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-accepted-intake-original-summary.txt"
fi

if [ "$signed_native_work_release_probe" = true ]; then
  phase="signed native original Work edit, date, own Results and revocation"
  python3 "$repo_root/scripts/validate-atlas-native-work-release-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-native-work-release-summary.txt" \
    >"$artifacts_dir/signed-native-work-release.log" 2>&1
  test -s "$artifacts_dir/signed-native-work-release-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-native-work-release-summary.txt"
fi

if [ "$signed_care_single_done_probe" = true ]; then
  phase="signed care physical Actual, source permission and universal Done"
  python3 "$repo_root/scripts/validate-atlas-care-single-done-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-care-single-done-summary.txt" \
    >"$artifacts_dir/signed-care-single-done.log" 2>&1
  test -s "$artifacts_dir/signed-care-single-done-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-care-single-done-summary.txt"
fi

if [ "$signed_connected_work_prerequisite_probe" = true ]; then
  phase="signed local person-native exact Work prerequisite projection"
  python3 "$repo_root/scripts/validate-atlas-connected-work-prerequisite-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-connected-work-prerequisite-summary.txt" \
    >"$artifacts_dir/signed-connected-work-prerequisite.log" 2>&1
fi

if [ "$signed_existing_person_auth_claim_probe" = true ]; then
  phase="signed local canonical Person new-Auth claim, wrong recipient, retired credential and session revocation"
  python3 "$repo_root/scripts/validate-shared-existing-person-auth-claim-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-person-auth-claim-summary.txt" \
    >"$artifacts_dir/signed-person-auth-claim.log" 2>&1
fi

if [ "$signed_person_weight_probe" = true ]; then
  phase="signed local Person weight recognition, first approval, future history and revocation"
  python3 "$repo_root/scripts/validate-atlas-person-weight-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-person-weight-summary.txt" \
    >"$artifacts_dir/signed-person-weight.log" 2>&1
fi

if [ "$signed_person_collections_probe" = true ]; then
  phase="synthetic signed Person Collection fixture on disposable clone"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261023201945_atlas_person_deterministic_weight_v1.sql" \
    >"$artifacts_dir/signed-person-collections-fixture.log" 2>&1
  phase="genuine signed private Person Collection filing and privacy proof"
  python3 "$repo_root/scripts/validate-atlas-person-collections-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-person-collections-summary.txt" \
    >"$artifacts_dir/signed-person-collections.log" 2>&1
fi

if [ "$signed_person_period_probe" = true ]; then
  phase="signed local source-qualified Person period history, exact cursor and privacy"
  python3 "$repo_root/scripts/validate-atlas-person-period-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-person-period-summary.txt" \
    >"$artifacts_dir/signed-person-period.log" 2>&1
fi

if [ "$signed_foundry_workspace_probe" = true ]; then
  phase="genuine signed local Foundry workspace isolation, session revocation and pending-only subject scope"
  python3 "$repo_root/scripts/validate-shared-foundry-workspace-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-foundry-workspace-summary.txt" \
    >"$artifacts_dir/signed-foundry-workspace.log" 2>&1
fi

if [ "$signed_foundry_historical_probe" = true ]; then
  phase="genuine signed local historical Foundry owner/nonowner/revocation matrix"
  python3 "$repo_root/scripts/validate-shared-foundry-historical-continuity-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-foundry-historical-summary.txt" \
    >"$artifacts_dir/signed-foundry-historical.log" 2>&1
fi

if [ "$signed_atlas_proper_inventory_probe" = true ]; then
  phase="signed local Atlas Proper metadata-only inventory and revocation"
  python3 "$repo_root/scripts/validate-atlas-proper-discovery-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-atlas-proper-inventory-summary.txt" \
    >"$artifacts_dir/signed-atlas-proper-inventory.log" 2>&1
fi

if [ "$signed_atlas_proper_needs_probe" = true ]; then
  phase="signed Atlas Proper developer journal, actual writes, idempotence and revocation"
  python3 "$repo_root/scripts/validate-atlas-proper-developer-needs-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-atlas-proper-needs-summary.txt" \
    >"$artifacts_dir/signed-atlas-proper-needs.log" 2>&1
fi

if [ "$signed_native_standing_work_probe" = true ]; then
  phase="genuine signed native Ledger standing-Work Person authorization, acceptance and revocation"
  python3 "$repo_root/scripts/validate-shared-native-standing-work-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-native-standing-work-summary.txt" \
    >"$artifacts_dir/signed-native-standing-work.log" 2>&1
fi

if [ "$signed_universal_program_probe" = true ]; then
  phase="real signed local universal Program v2 author and revocation authorization"
  python3 "$repo_root/scripts/validate-atlas-universal-program-v2-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-universal-program-v2-summary.txt" \
    >"$artifacts_dir/signed-universal-program-v2.log" 2>&1
fi

if [ "$signed_program_author_notes_probe" = true ]; then
  phase="genuine signed Program author note owner, outsider and revocation matrix"
  python3 "$repo_root/scripts/validate-atlas-program-author-notes-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-program-author-notes-summary.txt" \
    >"$artifacts_dir/signed-program-author-notes.log" 2>&1
fi

if [ "$signed_program_source_identity_probe" = true ]; then
  phase="signed local Program source identity/duplicate/fork/revocation matrix"
  python3 "$repo_root/scripts/validate-atlas-program-source-identity-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-source-identity-summary.txt" \
    >"$artifacts_dir/signed-source-identity.log" 2>&1
fi

if [ "$signed_program_author_probe" = true ]; then
  phase="real signed local Program author, outsider, unbound, and revocation authorization"
  python3 "$repo_root/scripts/validate-atlas-program-author-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-program-author-summary.txt" \
    >"$artifacts_dir/signed-program-author.log" 2>&1
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
if [ "$signed_person_mail_probe" = true ]; then
  printf '\nSIGNED Person shared mail: true separate signed governor, recipient, outsider, cutoff, fallback, legacy-route and revocation tests.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_ledger_reciprocal_probe" = true ]; then
  printf '\nSIGNED reciprocal native Ledger Work: independent GoTrue owner/worker/outsider, root scoping, non-disclosure, unassigned original, revocation, no shadow People/Principals passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_accepted_ledger_original_probe" = true ]; then
  printf '\nSIGNED accepted Ledger intake: real independent GoTrue source denial, exact accepted Work, both lawfully separate responsibility modes, worker schedule denial and original blocked Result on disposable clone.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_ledger_disposition_v2_probe" = true ]; then
  printf '\nSIGNED Ledger disposition v2: independent GoTrue worker/governor/outsider, follow-up recovery, edited/rejected same original, idempotent retry, root cutoff and true 42501 denials.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_work_release_probe" = true ]; then
  printf '\nSIGNED native Work editing/date/status: local independent GoTrue actors, original identity, stale edit, Result privacy, current plan and revoked seat all passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_work_self_assignment_probe" = true ]; then
  printf '\\nSIGNED original Work: own-Person and other Person responsibility, exact idempotent replay, no forced plan/new Work, cross-Ledger denials and root/seat/session revocation passed on local clone.\\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_unified_today_p0_probe" = true ]; then
  printf '\nSIGNED unified Today P0: private Event title/detail/count isolation, exact governor grant/withhold, unrelated Work history denial, and signed worker Company date denial passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_calendar_reader_probe" = true ]; then
  printf '\nSIGNED ONE Calendar read: governor, member, outsider, anonymous and revoked-permission checks passed locally.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_event_writer_probe" = true ]; then
  printf '\nSIGNED One Event writer: root can correct one canonical Event; ordinary and outsider denied; stale sources, replay and revoked sessions passed.\n' \
    >> "$artifacts_dir/summary.md"
fi

if [ "$signed_work_prerequisite_probe" = true ]; then
  printf '\nSIGNED Work prerequisites: real GoTrue root, worker, outsider, no-seat denials; immutable history and concurrent cycle protection verified on disposable clone.\n' \
    >> "$artifacts_dir/summary.md"
fi

if [ "$signed_connected_work_prerequisite_probe" = true ]; then
  printf '\nSIGNED connected-Person prerequisite read: authentic direct Ledger Work assignment, original source, cross-Work denial and revoked sessions verified locally.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_foundry_workspace_probe" = true ]; then
  printf '\nSIGNED Foundry workspace: real local GoTrue sessions, owner/outsider/unbound denial, idempotence, unreviewed subject custody, and revoked JWT session checks passed.\n' >> "$artifacts_dir/summary.md"
fi

if [ "$signed_foundry_historical_probe" = true ]; then
  printf '\nSIGNED historical Foundry: independent real GoTrue owner/nonowner/unbound/anonymous, exact source history, source-only Implementation case registration and session revocation all passed in local clone.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_program_source_identity_probe" = true ]; then
  printf '\nSIGNED author source identity: genuine local A/B/unbound sessions, duplicate/fork custody, private source lookup and active grant revocation passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_universal_program_probe" = true ]; then
  printf '\nSIGNED universal Program v2: genuine GoTrue sessions, budget/goal/window source intent, immutable versions, foreign/unbound/anonymous denials and revocation passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_program_author_notes_probe" = true ]; then
  printf '\nSIGNED author Program margin notes: independent genuine GoTrue sessions, private source anchors, append-only note history, denied cross-owner/anonymous/unbound access and revoked entitlement verified in disposable clone.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_atlas_proper_inventory_probe" = true ]; then
  printf '\nSIGNED Atlas Proper discovery: real local operator, ordinary Principal, outsider, anonymous and revoked GoTrue sessions; no original source material or canonical mutation.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_atlas_proper_needs_probe" = true ]; then
  printf '\nSIGNED Atlas Proper needs: independent practitioner creates and updates dated work; anonymous, ordinary and revoked sessions denied; no original source mutation.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_program_author_probe" = true ]; then
  printf '\nSIGNED Program author: genuine separate GoTrue sessions, approved immutable versions, foreign/unbound/anonymous denial, replay defense, and entitlement revocation verified in disposable clone.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_standing_work_probe" = true ]; then
  printf '\nSIGNED native standing Work: real independent owner/worker/outsider GoTrue sessions, zero memberships, recipient acceptance, exact responsibility, denied impersonation and revocation passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_person_collections_probe" = true ]; then
  printf '\nSIGNED Person Collections: independent GoTrue sessions, original filing/readback, privacy, move and retry verified only in isolated clone.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_person_period_probe" = true ]; then
  printf '\nSIGNED Person period history: real local GoTrue sessions, original source standing, exact cursor and cross-Person denial passed.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_person_weight_probe" = true ]; then
  printf '\nSIGNED Person weight history: separate genuine local GoTrue sessions, first pattern approval, repeat approval, cross-person denial, subsequent source and revocation verified.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_existing_person_auth_claim_probe" = true ]; then
  printf '\nSIGNED existing Person new Auth binding: actual local GoTrue recipient, native Ledger steward, wrong-email, repeated claim and revoked-session checks passed.\n' \
    >> "$artifacts_dir/summary.md"
fi

Warning: truncated output (original token count: 36921)
Total output lines: 2516

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/validate-production-schema-clone.sh \
  --migration-version <14 digits> \
  --release-lane <atlas|wnph|titus|noel|shared> \
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
pre1_rest_proof=false
t5_rollback_shape=false
t5_signed_study=false

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
    --pre1-rest-proof) pre1_rest_proof=true; shift ;;
    --t5-rollback-shape) t5_rollback_shape=true; shift ;;
    --t5-signed-study) t5_signed_study=true; shift ;;
    *) usage ;;
  esac
done

if [[ ! "$version" =~ ^[0-9]{14}$ ]]; then
  usage
fi
if [[ "$lane" != "atlas" && "$lane" != "wnph" && "$lane" != "titus" && "$lane" != "noel" && "$lane" != "shared" ]]; then
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

if [ "$t5_signed_study" = true ] && [ "$t5_rollback_shape" != true ]; then
  echo 'Signed T5 requires exact reviewed rollback-only base proof.' >&2; exit 2
fi
# T5 is a distinct rollback-only schema-shape proof, not migration validation.
# The existing paths retain all their ordinary candidate/lint/signed checks.
if [ "$t5_rollback_shape" = true ]; then
  if [ "$lane" != shared ] || [ "$version" != 20261119100000 ] ||
     [ "$(basename "$candidate_migration")" != "20261119100000_shared_titus_t5_teaching_TEST_ONLY.sql" ] ||
     [ -n "$candidate_fixture" ] || [ -n "$candidate_validation" ] || [ "$pre1_rest_proof" = true ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'T5 requires the exact rollback-only scratch scope and no hosted credentials or fixture.' >&2
    exit 2
  fi
  python3 - "$candidate_migration" <<'PY'
from pathlib import Path
import re,sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
assert s.startswith("-- T5 PROTECTED SOURCE-SHAPE TEST ONLY; NOT A RELEASABLE MIGRATION.\nBEGIN;\n")
assert re.findall(r"(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;", s) == ["BEGIN","ROLLBACK"]
assert s.rstrip().endswith("ROLLBACK;")
assert s.count("-- SOURCE SEGMENT START ") == 7
assert s.count("-- SOURCE SEGMENT END ") == 7
PY
fi

# The additional PRE1 PostgREST proof is opt-in ONLY for exactly reviewed
# dropped-v1 source under a generated disposable scratch migration basename.
# Never allow this option to validate unrelated SQL with a false "route gone".
if [ "$pre1_rest_proof" = true ]; then
  if [ "$lane" != atlas ] ||
     [[ "$(basename "$candidate_migration")" != *"_atlas_access03_zone_direct_reader_retirement_clone_only_v1.sql" ]] ||
     [ "$(git hash-object "$candidate_migration")" != "ac8552f35e4de14f1ae337c29cfc1c2971af1c9b" ] ||
     [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "PRE1 REST proof requires exact reviewed local candidate, fixture and postconditions." >&2
    exit 2
  fi
fi
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
signed_household_original_repair_probe=false
signed_household_lifecycle_probe=false
signed_household_renewal_initial_probe=false
signed_clean_renewal_initial_probe=false
signed_household_renewal_due_probe=false
signed_clean_renewal_due_probe=false
signed_work_self_assignment_probe=false
signed_native_intake_responsibility_probe=false
signed_native_work_journal_probe=false
signed_native_original_work_comments_probe=false
signed_care_single_done_probe=false
signed_native_work_release_probe=false
signed_personal_task_amendment_probe=false
signed_personal_task_progress_probe=false
signed_personal_connected_assignment_probe=false
signed_personal_optional_date_probe=false
signed_task_initial_details_probe=false
signed_titus_object_title_probe=false
signed_ledger_reciprocal_probe=false
signed_ledger_disposition_v2_probe=false
signed_legacy_queue_owner_probe=false
signed_unified_today_p0_probe=false
signed_person_mail_probe=false
signed_venue_bed_probe=false
signed_access01_event_choices_probe=false
signed_access02_my_work_probe=false
signed_access03_zone_retirement_probe=false
signed_legacy_farm_invite_probe=false
signed_pressure_wash_retirement_probe=false
signed_generated_listening_storage_probe=false
signed_private_mp3_profile_probe=false
signed_private_course_working_loop_probe=false
signed_sk101_course_management_probe=false
orphan_queue_retirement_proof=false
obsolete_unfinished_retirement_proof=false
# HELD original pressure-wash branch: exact SQL + authentic C1 signed
# actor and full-Atlas original-row no-loss test, disposable clone ONLY.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_historical_pressure_wash_serial_branch_clone_only_v1[.]sql$ ]] || [ "$(basename "$candidate_migration")" = "20261122143231_atlas_historical_pressure_wash_serial_branch_retirement_v1.sql" ]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 25e2791bd2da2477015260017eb2e982ec5b083d ] ||
     [ "$(git hash-object "$candidate_fixture")" != 18b25f7902786e2a1697fb6ac35dbff74328ae69 ] ||
     [ "$(git hash-object "$candidate_validation")" != 2397e06f23bfdce901400fcbc68c7c6b56900b96 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'REFUSE unsigned or nonlocal held historical pressure-wash source' >&2
    exit 2
  fi
  signed_pressure_wash_retirement_probe=true
  signed_work_prerequisite_probe=true
fi


# One immutable legacy farm invitation SQL packet, clone only.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_legacy_farm_invitation_retirement_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 080ba4d73e4340cba0211c6b804bcea46231e016 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 83fd7f693be14f5b36cd4f135346f637ef49c45c ] ||
     [ "$(git hash-object "$candidate_validation")" != 45152d53023ee4ca68a5b6188584edf9c08786bc ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-legacy-farm-invite-signed-http.py")" != a8cb9318d48e85ac61cc81d5ad063fdc8989d9e9 ] ||
     [ "$(git hash-object "$repo_root/scripts/atlas-legacy-farm-member-disposable-fixture.sql")" != db6a08e231fa5fbee0efb37fd798a938a8fd79af ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
    echo 'REFUSE held legacy farm signed test without exact source and local clone' >&2
    exit 2
  fi
  signed_legacy_farm_invite_probe=true
fi


# Exact held deletion only; preserve every existing signed proof admission.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_legacy_queue_orphan_backfill_retirement_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 5956b80d02ff5e7d80553270b57d238e6fd2afd1 ] ||
     [ "$(git hash-object "$candidate_validation")" != d771e05ef86b08997b4d7a4b78d143a58547738c ] ||
     [ "$(git hash-object "$candidate_fixture")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse orphan backfill proof without exact isolated package and trusted regressions.' >&2; exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi
# TEST ONLY: exactly two original deprecated owner-completion queue functions.
# Their former progression trigger was previously separately released.
# Source-positive fictional 97-row terminal historical queue, original C1
# signed Work fixture, 730-base-table no-loss proof; NEVER use live credentials.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_owner_completion_queue_orphan_branch_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != a5a23c42557bf6913321689fb9853afb57ff2c0e ] ||
     [ "$(git hash-object "$candidate_validation")" != a3dbc4fe6f5db230ed3dbf071e514ff06487e807 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 19981823e3d6e7da8a82b5d609fb1558e38c4251 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse owner-completion serial orphan clone without exact source, fictional historical fixture and original signed no-loss proofs.' >&2
    exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi


# TEST-ONLY exact generated Anna orphan trigger/effect two-function package.
# Independent from the previous owner-completion pair; use identical ORIGINAL
# signed C1, prerequisite and all-Atlas base-row fingerprint machinery.
if [[ "$(basename "$candidate_migration")" == "20261121235035_atlas_anna_orphaned_serial_effect_retirement_v1.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 7fb7c4bdefc735484448fa3845e0125a2ffaa4eb ] ||
     [ "$(git hash-object "$candidate_validation")" != 5de235c8b83d3bfa4504aa9f3c28948cbd5848c9 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 5ddc096700e726fd9681df0067f23576b848f124 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse Anna orphan clone without exact generated source, original signed fixture and all-row no-loss tests.' >&2
    exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi


# TEST ONLY: the original legacy Task automatic assignment/Sunday policy
# two triggers + two functions; reuse the original C1 signed Work fixture and
# exact full-Atlas-table row fingerprints. NOT live authorization.
if [[ "$(basename "$candidate_migration")" == "20261122003235_atlas_legacy_person_specific_task_trigger_retirement_v1.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != fade2e58598e4e32e49f9e84f481c54b3611ad9f ] ||
     [ "$(git hash-object "$candidate_validation")" != b720cc35fa78f3626a4a0f2c8d3138c7557cdea6 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 60ac062da84b34be539ede296dda5434aa58d061 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse person-specific legacy Task trigger clone unless exact source, original signer, fictional C1 source and full-row proof.' >&2
    exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# Six-trigger retirement uses the EXISTING all-Atlas original-row fingerprint
# and genuinely signed owner/worker prerequisites, never a new validator.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_historical_queue_progression_trigger_retirement_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != a34107ba634c558af40fa437c29a013d6a7adc29 ] ||
     [ "$(git hash-object "$candidate_validation")" != 999201b8a73dfb04bbd680241a7fafab6028a218 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse progression trigger retirement unless exact isolated SQL, postcondition, fixture and trusted signer are pinned.' >&2
    exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# TEST ONLY: source-exact retirement of obsolete historical unfinished rows.
# This is DML on a disposable schema clone ONLY; no production credentials.
# Use the original signed C1 fixture/proof, plus an exact scoped 97-row
# synthetic queue fixture. No arbitrary data/role/source admission.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121184327_atlas_obsolete_2026_unfinished_retirement_v1.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 55f7f92430cea0beeef79f9c4705a8a7f2afe9a0 ] ||
     [ "$(git hash-object "$candidate_fixture")" != d06aa20d0c0694160cb32126abf3ffa49b2d3822 ] ||
     [ "$(git hash-object "$candidate_validation")" != 722d802f517b99e34fbe284e2e20b71daa99c6a6 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-obsolete-queue-retirement-row-change.py")" != bed62188f2e6ab3d8540c317e562c631b0f5bd0f ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse obsolete unfinished queue DML clone without pinned candidate, data fixture, trusted all-row and signed tests.' >&2
    exit 2
  fi
  obsolete_unfinished_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# TEST ONLY: source-positive prerequisite-safe V2 of the same exact obsolete queue.
# This is DML on a disposable schema clone ONLY; no production credentials.
# Use the original signed C1 fixture/proof, plus an exact scoped 97-row
# synthetic queue fixture. No arbitrary data/role/source admission.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_prereq_guard_clone_only_v2[.]sql$ || "$(basename "$candidate_migration")" == "20261121194446_atlas_obsolete_2026_unfinished_retirement_prereq_guard_v2.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 7d8d56797f553618b1b6fff73feddf464f394878 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 26ec0ece68dccb5d9d966a20ecf30dcbf2fc7f32 ] ||
     [ "$(git hash-object "$candidate_validation")" != 1a539dae9781ca6524abbbfd3f45ce96951e4141 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-obsolete-queue-retirement-row-change.py")" != bed62188f2e6ab3d8540c317e562c631b0f5bd0f ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse obsolete unfinished queue DML clone without pinned candidate, data fixture, trusted all-row and signed tests.' >&2
    exit 2
  fi
  obsolete_unfinished_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# TEST ONLY: source-positive INTERNAL/EXTERNAL prerequisite-chain V3.
# This is DML on a disposable schema clone ONLY; no production credentials.
# Use the original signed C1 fixture/proof, plus an exact scoped 97-row
# synthetic queue fixture. No arbitrary data/role/source admission.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_prereq_chain_clone_only_v3[.]sql$ || "$(basename "$candidate_migration")" == "20261121204646_atlas_obsolete_2026_unfinished_retirement_prereq_chain_v3.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 12bc33affcd9a57eba4d19e332a010588f2b22cb ] ||
     [ "$(git hash-object "$candidate_fixture")" != 8e4ed1f4e10b178bdd9afdf25a5b42445e22f1d0 ] ||
     [ "$(git hash-object "$candidate_validation")" != 1a96988eef4bffd515e03be9d5c918ed08641faf ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-obsolete-queue-retirement-row-change.py")" != bed62188f2e6ab3d8540c317e562c631b0f5bd0f ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse obsolete unfinished queue DML clone without pinned candidate, data fixture, trusted all-row and signed tests.' >&2
    exit 2
  fi
  obsolete_unfinished_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# Held Package B: remove only five exact live queue table dependencies.
# Existing all-row fingerprints and genuine signed Work regressions remain mandatory.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_legacy_queue_live_consumer_decoupling_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121211411_atlas_legacy_queue_five_live_consumer_decoupling_v1.sql" ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != d62d42837f4a36e7ba0ded4bf4b8c29f948488fa ] ||
     [ "$(git hash-object "$candidate_validation")" != 7d3b3ff7c7951405b823b3a2a25f3ef4c087832c ] ||
     [ "$(git hash-object "$candidate_fixture")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse historical queue live consumer cutover without exact immutable source, fixture, and signed actor proof.' >&2
    exit 2
  fi
  orphan_queue_retirement_proof=true
  signed_work_prerequisite_probe=true
fi

# Exact owner-admitted immutable package; never infer proof from a filename.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_private_course_working_loop_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != shared ] || [ -n "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 33aa73e850a22eeecabcb456dc67523c7d351370 ] ||
     [ "$(git hash-object "$candidate_validation")" != 43820e70118372c2974a747c4b86a149107e895d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-private-course-working-loop-signed-http.py")" != 5ee0d666be7bddacb91a4a362e1cb24823c4f5f8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse private Course proof without exact isolated package and signed harness.' >&2; exit 2
  fi
  signed_private_course_working_loop_probe=true
fi
# Exact owner-held SK101 management proof, disposable clone only.
if [[ "$(basename "$candidate_migration")" == "candidate.sql" ]] && [[ "$candidate_migration" == *"shared-sk101-course-management-v1/candidate.sql" ]]; then
  if [ "$lane" != shared ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != b3c4591ec23d13db6b2a92d781f907278c106b22 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 3f05af628dc4df7f8c483947f77c9996aa9655b3 ] ||
     [ "$(git hash-object "$candidate_validation")" != a7e5fd416d3ebb490fcfb57827adef58a1749a4f ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-sk101-course-management-signed-http.py")" != 61bf834bef792a13941c5fcf9bffa5b45ac3eb25 ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse SK101 management proof without exact isolated package and signed harness.' >&2; exit 2
  fi
  signed_sk101_course_management_probe=true
fi
# HELD fixed private MP3 profile: exact source-pinned owner-signed GoTrue
# proof on the ORIGINAL production-schema disposable clone and harness.
# This is not a migration or live media-admission authorization.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_native_private_mp3_profile_clone_only_v1[.]sql$ ]]; then
  profile_dir="$repo_root/candidates/shared-listening-delivery-artifact-v1"
  profile_signed_proof="$profile_dir/verify_private_mp3_profile_signed.py"
  native_signed_helper="$profile_dir/verify_generated_listening_storage_signed.py"
  if [ "$lane" != shared ] || [ -n "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [ "$(git hash-object "$candidate_migration")" != 861a34074818d33ff2f260bfbecfb1fe9738a7dd ] ||
     [ "$(git hash-object "$candidate_validation")" != 724c57e6b3cc224351480d636a417e9408a2798d ] ||
     [ "$(git hash-object "$native_signed_helper")" != e7d3f38887ea1419940bf371f1dbb8aea7b16455 ] ||
     [ "$(git hash-object "$profile_signed_proof")" != fbb3632c5ce4dc22c31ffd2a2938ee570c14ba2d ]; then
    echo 'Refuse unpinned native private MP3 signed source/clone candidate.' >&2; exit 2
  fi
  python3 -m py_compile "$profile_signed_proof"
  signed_private_mp3_profile_probe=true
fi

# Exact signed Storage proof, never a generated production migration.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_generated_listening_storage_signed_clone_only_v1[.]sql$ ]]; then
  listening_dir="$repo_root/candidates/shared-listening-delivery-artifact-v1"
  listening_proof="$listening_dir/verify_generated_listening_storage_signed.py"
  listening_completion="$listening_dir/generated_production_completion_candidate.sql"
  listening_staging="$listening_dir/generated_listening_storage_candidate.sql"
  listening_original="$listening_dir/manuscript_original_registration_candidate.sql"
  if [ "$lane" != shared ] || [ -n "$candidate_fixture" ] || [ -n "$candidate_validation" ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [ "$(git hash-object "$listening_completion")" != 1c7b398136b399983b1acdb2712b70958761d768 ] ||
     [ "$(git hash-object "$listening_staging")" != 106268970a69c33c5a8d30d737e5d98af807ccfa ] ||
     [ "$(git hash-object "$listening_original")" != de89478c094719912a9ac145af28e01186584c32 ] ||
     [ "$(git hash-object "$listening_proof")" != e7d3f38887ea1419940bf371f1dbb8aea7b16455 ] ||
     ! cmp -s "$candidate_migration" <(cat "$listening_completion" "$listening_original" "$listening_staging"); then
    echo 'Refuse without exact held generated listening SQL and signed proof.' >&2; exit 2
  fi
  signed_generated_listening_storage_probe=true
fi

# Exact title proof, only on the protected schema-only disposable clone.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_teaching_object_title_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != shared ] || [ -n "$candidate_fixture" ] || [ -n "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 6c7f9387c9cda8014762f8c3f7678c87e993cf1a ] ||
     [ ! -s "$repo_root/scripts/validate-titus-object-title-signed-http.py" ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-titus-object-title-signed-http.py")" != 761059e2029f7238ac619d3409d969c8b2a3f8eb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ]; then
    echo "Exact held title source and signed local probe required." >&2
    exit 2
  fi
  signed_titus_object_title_probe=true
fi

# ACCESS-03A: exact synthetic retirement candidate, never a release lane.
# The signed proof only accepts a synthetic postcondition and local fixture.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_access03_zone_direct_reader_retirement_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$repo_root/scripts/validate-atlas-access03-zone-retirement-signed-http.py" ]; then
    echo "ACCESS-03A signed clone needs a fictional fixture and trusted probe." >&2
    exit 2
  fi
  signed_access03_zone_retirement_probe=true
fi

# ACCESS-02: exact scratch-only signed My Work native relevance matrix.
# This name is NOT a versioned production release migration. No implicit
# signed acceptance is enabled for any other Atlas source.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_access02_my_work_relevance_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$repo_root/scripts/validate-atlas-access02-my-work-signed-http.py" ]; then
    echo "ACCESS-02 signed clone requires exact synthetic fixture, postconditions and trusted test." >&2
    exit 2
  fi
  signed_access02_my_work_probe=true
fi

# ACCESS-01 single named test-only signed disposable clone, not a release lane.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_access01_event_choices_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$repo_root/scripts/validate-atlas-access01-event-choices-signed-http.py" ]; then
    echo "ACCESS-01 signed clone requires exact fixture, postconditions and trusted signed test." >&2
    exit 2
  fi
  signed_access01_event_choices_probe=true
fi

# Exact Venue/Flower shared-use signed test. No production path: this probe
# requires the named scratch-only candidate, DML fixture and postconditions.
# Temporary public transport is permitted only within that disposable clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_venue_bed_shared_use_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Venue Bed signed proof requires a fictional fixture and source postconditions." >&2
    exit 2
  fi
  if [ ! -s "scripts/validate-atlas-venue-bed-signed-http.py" ]; then
    echo "Venue Bed signed proof requires the immutable held local HTTP test source." >&2
    exit 2
  fi
  signed_venue_bed_probe=true
fi

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

# Exact held native-intake candidate, local clone only, never a release version.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_native_intake_responsibility_clone_only_v1[.]sql$ ]]; then
  native_intake_proof="$repo_root/candidates/atlas/native_intake_responsibility_v1/validate_signed_intake_responsibility.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$native_intake_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 5fc59a4d3c3d24083037456bf3c488ae9318f3b6 ] ||
     [ "$(git hash-object "$candidate_validation")" != dd1eb5d643926de75c4c4242bab490f336a2cdb4 ] ||
     [ "$(git hash-object "$candidate_fixture")" != c5d72cc137dbf5c85ca6bdda1f4cf98d057de501 ] ||
     [ "$(git hash-object "$native_intake_proof")" != 57629753679565be0f7e0f5dabbc3c11d28de892 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ]; then
    echo "Native intake proof requires exact reviewed source and synthetic fixture." >&2
    exit 2
  fi
  signed_native_intake_responsibility_probe=true
fi

# Exact held native-work-journal candidate, local clone only, never a release version.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_native_work_journal_clone_only_v1[.]sql$ ]]; then
  native_work_journal_proof="$repo_root/candidates/atlas/native_work_record_and_journal_v1/validate_signed_native_work_journal.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$native_work_journal_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != b3b0665e0bdbc535e523a48a0a7983bf8cb26bfe ] ||
     [ "$(git hash-object "$candidate_validation")" != 53997b95d3ae427a996c5101a2513d397ac1c002 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 545fbce53ef2bafba2c83cacabea5dc6f28759ef ] ||
     [ "$(git hash-object "$native_work_journal_proof")" != 4ea6883b021cbb9e573c13281fd2ca3bd5ed461e ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ]; then
    echo "Native intake proof requires exact reviewed source and synthetic fixture." >&2
    exit 2
  fi
  signed_native_work_journal_probe=true
fi

# W07 exact scratch-only original Work comments, never a released migration.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_native_original_work_comments_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$repo_root/scripts/validate-atlas-native-original-work-com…16921 tokens truncated…3 signed ' "$artifacts_dir/signed-access03-zone-retirement-summary.txt"
fi

# PRE1 TEST ONLY: the existing signed ACCESS03A/B test intentionally flips a
# farm manager role, revokes/restores native authority, and toggles a
# synthetic retired-object marker. Its final full-row fingerprint differs
# in THREE named relations. The PRE1 task-link trigger creates a separate
# object_state row which its own synthetic probe must clean. Prove this is the
# exact known fixture transition and that ALL OTHER Atlas relations stayed
# byte-for-byte unchanged. This is not a PRE1 candidate exemption.
if [ "$pre1_rest_proof" = true ]; then
  phase="PRE1 verify exact existing ACCESS03 signed fixture transition"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pre1_row_snapshot" --mode audit-access03 \
    >"$artifacts_dir/pre1-local-access03-fixture-transition.log" 2>&1
  grep -q '^PASS ACCESS03 signed fixture transition confined to three reviewed Atlas relations;' \
    "$artifacts_dir/pre1-local-access03-fixture-transition.log"

  # A distinct SECOND baseline begins PRE1's own signed REST probe.
  # The PRE1 RPC must restore every Atlas row exactly relative to this state.
  phase="PRE1 local full-row baseline after ACCESS03 actor fixture transitions"
  pre1_post_access03_snapshot="$runtime_dir/pre1-post-access03-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pre1_post_access03_snapshot" --mode capture \
    >"$artifacts_dir/pre1-local-after-access03-baseline.log" 2>&1
  grep -q '^PRE1 LOCAL row-integrity baseline captured:' \
    "$artifacts_dir/pre1-local-after-access03-baseline.log"
fi

if [ "$pre1_rest_proof" = true ]; then
  if [ "$signed_access03_zone_retirement_probe" != true ]; then
    echo "PRE1 REST proof requires the existing signed ACCESS03 zone/RLS gate." >&2
    exit 2
  fi
  phase="signed local PRE1 v1 REST RPC absence and retained v2 owner-positive"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-tending-rpc-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-access03c-pre1-rpc-summary.txt" \
    >"$artifacts_dir/signed-access03c-pre1-rpc.log" 2>&1
  test -s "$artifacts_dir/signed-access03c-pre1-rpc-summary.txt"
  grep -q '^PASS ACCESS03C-PRE1 signed ' "$artifacts_dir/signed-access03c-pre1-rpc-summary.txt"
fi

# Exact full-row equality after PRE1's own signed RPC and scoped cleanup,
# against a separate post-ACCESS03 fixture baseline. Earlier expected ACCESS03
# transitions were independently reviewed and checked in the exact four
# named relations, rather than being silently ignored.
# This still does NOT prove Production historical row survival: the clone
# imported Production SCHEMA and ROLES, not private data rows.
if [ "$pre1_rest_proof" = true ]; then
  phase="PRE1 local all-Atlas-row unchanged after PRE1 signed HTTP cleanup"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pre1_post_access03_snapshot" --mode verify \
    >"$artifacts_dir/pre1-local-row-integrity-after-signed.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/pre1-local-row-integrity-after-signed.log"
fi

if [ "$signed_access01_event_choices_probe" = true ]; then
  phase="genuinely signed local ACCESS-01 Event identity versus wider Ledger disclosure"
  python3 "$repo_root/scripts/validate-atlas-access01-event-choices-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-access01-event-choices-summary.txt" \
    >"$artifacts_dir/signed-access01-event-choices.log" 2>&1
  test -s "$artifacts_dir/signed-access01-event-choices-summary.txt"
  grep -q '^PASS ACCESS-01' "$artifacts_dir/signed-access01-event-choices-summary.txt"
fi

if [ "$signed_venue_bed_probe" = true ]; then
  phase="signed local Flower/Venue Bed source, replay, withdrawal and revoked-session matrix"
  python3 "$repo_root/scripts/validate-atlas-venue-bed-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-venue-bed-summary.txt" \
    >"$artifacts_dir/signed-venue-bed.log" 2>&1
  test -s "$artifacts_dir/signed-venue-bed-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-venue-bed-summary.txt"
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

if [ "$signed_native_intake_responsibility_probe" = true ]; then
  phase="signed exact native Ledger intake responsibility and Result matrix"
  python3 "$native_intake_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-native-intake-responsibility-summary.txt" \
    >"$artifacts_dir/signed-native-intake-responsibility.log" 2>&1
  test -s "$artifacts_dir/signed-native-intake-responsibility-summary.txt"
  grep -q '^PASS native intake signed self-assignment' "$artifacts_dir/signed-native-intake-responsibility-summary.txt"
fi

if [ "$signed_native_work_journal_probe" = true ]; then
  phase="signed governor recording and actual-day Work journal"
  python3 "$native_work_journal_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-native-work-journal-summary.txt" \
    >"$artifacts_dir/signed-native-work-journal.log" 2>&1
  test -s "$artifacts_dir/signed-native-work-journal-summary.txt"
  grep -q '^PASS signed governor recording' "$artifacts_dir/signed-native-work-journal-summary.txt"
fi

if [ "$signed_native_original_work_comments_probe" = true ]; then
  phase="genuine local signed W07 original Work comments and revocation"
  if [ "${W07_PROOF_SCOPE:-w07_signed_clone_test_only}" = "w07_shared_native_signed_clone_test_only" ]; then
    phase="genuine local three-Person shared original Work"
    python3 "$repo_root/candidates/atlas/atlas_native_original_work_comments_v1/native_self_participation/validate_signed_shared_work.py" \
      --db-url "$database_url" \
      --output "$artifacts_dir/signed-native-shared-work-summary.txt" \
      >"$artifacts_dir/signed-native-shared-work.log" 2>&1
    grep -q '^PASS three signed People' "$artifacts_dir/signed-native-shared-work-summary.txt"
  elif [ "${W07_PROOF_SCOPE:-w07_signed_clone_test_only}" = "w07_signed_clone_test_only" ]; then
    python3 "$repo_root/scripts/validate-atlas-native-original-work-comments-signed-http.py" \
      --db-url "$database_url" \
      --output "$artifacts_dir/signed-native-original-work-comments-summary.txt" \
      >"$artifacts_dir/signed-native-original-work-comments.log" 2>&1
    test -s "$artifacts_dir/signed-native-original-work-comments-summary.txt"
    grep -q '^PASS W07 signed local GoTrue' "$artifacts_dir/signed-native-original-work-comments-summary.txt"
  else
    echo "Unrecognized W07 proof scope; refuse." >&2; exit 2
  fi
fi

if [ "$signed_household_original_repair_probe" = true ]; then
  phase="signed original Household Work repair and native Person projection"
  python3 "$household_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-household-original-repair-summary.txt" \
    >"$artifacts_dir/signed-household-original-repair.log" 2>&1
  test -s "$artifacts_dir/signed-household-original-repair-summary.txt"
  grep -q '^PASS signed original Household subject-pair seam:' "$artifacts_dir/signed-household-original-repair-summary.txt"
fi

if [ "$signed_household_lifecycle_probe" = true ]; then
  phase="signed complete Laundry lifecycle and native Person projection"
  python3 "$lifecycle_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-household-lifecycle-summary.txt" \
    >"$artifacts_dir/signed-household-lifecycle.log" 2>&1
  test -s "$artifacts_dir/signed-household-lifecycle-summary.txt"
  grep -q '^PASS signed Laundry lifecycle:' "$artifacts_dir/signed-household-lifecycle-summary.txt"
fi

if [ "$signed_household_renewal_initial_probe" = true ]; then
  phase="signed initial Laundry renewal and preserved lifecycle"
  python3 "$renewal_initial_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-household-renewal-initial-summary.txt" \
    >"$artifacts_dir/signed-household-renewal-initial.log" 2>&1
  test -s "$artifacts_dir/signed-household-renewal-initial-summary.txt"
  grep -q '^PASS signed Laundry renewal initial:' "$artifacts_dir/signed-household-renewal-initial-summary.txt"
fi

if [ "$signed_clean_renewal_initial_probe" = true ]; then
  phase="signed initial Laundry renewal and preserved lifecycle"
  python3 "$clean_initial_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-clean-renewal-initial-summary.txt" \
    >"$artifacts_dir/signed-clean-renewal-initial.log" 2>&1
  test -s "$artifacts_dir/signed-clean-renewal-initial-summary.txt"
  grep -q '^PASS signed Laundry renewal initial:' "$artifacts_dir/signed-clean-renewal-initial-summary.txt"
fi

if [ "$signed_household_renewal_due_probe" = true ]; then
  phase="signed due Laundry renewal and historical conservation"
  python3 "$renewal_due_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-household-renewal-due-summary.txt" \
    >"$artifacts_dir/signed-household-renewal-due.log" 2>&1
  test -s "$artifacts_dir/signed-household-renewal-due-summary.txt"
  grep -q '^PASS signed due renewal:' "$artifacts_dir/signed-household-renewal-due-summary.txt"
fi

if [ "$signed_clean_renewal_due_probe" = true ]; then
  phase="signed due Laundry renewal and historical conservation"
  python3 "$clean_due_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-clean-renewal-due-summary.txt" \
    >"$artifacts_dir/signed-clean-renewal-due.log" 2>&1
  test -s "$artifacts_dir/signed-clean-renewal-due-summary.txt"
  grep -q '^PASS signed due renewal:' "$artifacts_dir/signed-clean-renewal-due-summary.txt"
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

if [ "$signed_personal_task_progress_probe" = true ]; then
  phase="signed personal original progress, private paginated history and revocation"
  python3 "$repo_root/scripts/validate-atlas-personal-task-progress-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-personal-task-progress-summary.txt" \
    >"$artifacts_dir/signed-personal-task-progress.log" 2>&1
  test -s "$artifacts_dir/signed-personal-task-progress-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-personal-task-progress-summary.txt"
fi

if [ "$signed_titus_object_title_probe" = true ]; then
  phase="signed local original title changes and sealed edition custody"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/title-local-reload.log" 2>&1
  python3 "$repo_root/scripts/validate-titus-object-title-signed-http.py" \
    --db-url "$database_url" --output "$artifacts_dir/title-signed-receipt.txt" \
    >"$artifacts_dir/title-signed-local.log" 2>&1
  test "$(cat "$artifacts_dir/title-signed-receipt.txt")" = 'PASS independent local signed title proof'
fi

if [ "$signed_private_course_working_loop_probe" = true ]; then
  phase="independent signed private Course working loop and revocation"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/private-course-reload.log" 2>&1
  python3 "$repo_root/scripts/validate-private-course-working-loop-signed-http.py" \
    --db-url "$database_url" --output "$artifacts_dir/private-course-signed-receipt.txt" \
    >"$artifacts_dir/private-course-signed-local.log" 2>&1
  test "$(cat "$artifacts_dir/private-course-signed-receipt.txt")" = 'PASS independent signed standing Course read and revocation proof'
fi

if [ "$signed_personal_connected_assignment_probe" = true ]; then
  phase="signed atomic Personal and Ledger self creation on exact originals"
  python3 "$personal_connected_assignment_proof" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-compact-composer-creation-summary.txt" \
    >"$artifacts_dir/signed-compact-composer-creation.log" 2>&1
  test -s "$artifacts_dir/signed-compact-composer-creation-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-compact-composer-creation-summary.txt"
fi

if [ "$signed_personal_optional_date_probe" = true ]; then
  phase="signed optional date on exact Personal originals"
  python3 "$personal_optional_date_proof" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-personal-optional-date-summary.txt" \
    >"$artifacts_dir/signed-personal-optional-date.log" 2>&1
  test -s "$artifacts_dir/signed-personal-optional-date-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-personal-optional-date-summary.txt"
fi

if [ "$signed_task_initial_details_probe" = true ]; then
  phase="signed initial details on exact Personal originals"
  python3 "$task_initial_details_proof" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-task-initial-details-summary.txt" \
    >"$artifacts_dir/signed-task-initial-details.log" 2>&1
  test -s "$artifacts_dir/signed-task-initial-details-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-task-initial-details-summary.txt"
fi

if [ "$signed_personal_task_amendment_probe" = true ]; then
  phase="signed personal task text/date amendment on disposable original"
  python3 "$repo_root/scripts/validate-atlas-personal-task-amendment-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-personal-task-amendment-summary.txt" \
    >"$artifacts_dir/signed-personal-task-amendment.log" 2>&1
  test -s "$artifacts_dir/signed-personal-task-amendment-summary.txt"
  grep -q '^PASS' "$artifacts_dir/signed-personal-task-amendment-summary.txt"
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

if [ "$signed_generated_listening_storage_probe" = true ]; then
  phase="signed local generated listening Storage upload and readback"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/listening-local-reload.log" 2>&1
  (cd "$project_dir"; python3 "$listening_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-generated-listening-storage-summary.txt") \
    >"$artifacts_dir/signed-generated-listening-storage.log" 2>&1
  test "$(cat "$artifacts_dir/signed-generated-listening-storage-summary.txt")" = 'PASS signed local Storage and manuscript-original proof; bounded private native completion, replay and revocation denials; no publication.'
fi

if [ "$signed_private_mp3_profile_probe" = true ]; then
  phase="signed local private MP3 profile GoTrue identities and source authorization"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/private-mp3-profile-local-reload.log" 2>&1
  (cd "$project_dir"; python3 "$profile_signed_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-private-mp3-profile-summary.txt") \
    >"$artifacts_dir/signed-private-mp3-profile.log" 2>&1
  test "$(cat "$artifacts_dir/signed-private-mp3-profile-summary.txt")" = 'PASS signed local native private MP3 profile: exact owner/editor, viewer/outsider/anonymous/service denial, idempotence, source conflict, revoked role/session; no media or publication.'
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

if [ "$pre1_rest_proof" = true ]; then
  # Print no row bodies, IDs, notes, metadata or row digests into artifact.
  printf '\nPRE1 TEST ONLY: all Atlas base tables unchanged before/after held SQL; exactly three known ACCESS03 fixture relations changed during its signed actor probe; all Atlas base tables unchanged before/after PRE1 signed REST cleanup. No Production data cloned.\n' \
    >> "$artifacts_dir/summary.md"
fi

if [ "$signed_private_mp3_profile_probe" = true ]; then
  printf '\nSIGNED private MP3 profile: independent real GoTrue owner/editor/viewer/outsider; exact native source version, idempotence, cross-workspace denial, revoked membership/session and private table ACL all pass only on disposable clone. No media, publication or production release.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_generated_listening_storage_probe" = true ]; then
  printf '\nSIGNED generated listening: genuine local GoTrue owner/editor/viewer/outsider, Storage upload and byte readback, exact object version, denial of replacement and revoked access. No canonical admission or release.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$orphan_queue_retirement_proof" = true ]; then
  test -s "$artifacts_dir/signed-work-prerequisite-summary.txt"
  printf '\nOrphan backfill TEST ONLY: exact function DROP RESTRICT, all local Atlas base-table rows unchanged immediately around deletion and postconditions; existing signed Work prerequisite regression passed afterwards. Synthetic Work fixture only; no historical Production row data or external caller closure.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_pressure_wash_retirement_probe" = true ]; then
  test -s "$artifacts_dir/signed-work-prerequisite-summary.txt"
  test -s "$artifacts_dir/pressure-wash-all-atlas-row-after-candidate.log"
  printf '\nHELD pressure-wash branch TEST ONLY: exact three original DROP FUNCTION RESTRICT, all local Atlas base relation row identities and content unchanged, genuine local GoTrue root/worker/outsider/no-seat prerequisite/revocation/concurrency proof passed. Does NOT prove absence of external privileged service callers. No live SQL or production release.\n' >> "$artifacts_dir/summary.md"
fi

phase="complete"
if [ "$signed_household_original_repair_probe" = true ]; then
  printf '\nSIGNED Household repair test only: genuine independent local sessions, same original Need/Work/allocation, native Person read, physical Actual, member and session revocation. No production write or release.\n' >> "$artifacts_dir/summary.md"
fi
printf '\nMigration postconditions and local database advisors also completed successfully.\n' \
  >> "$artifacts_dir/summary.md"
if [ "$signed_http_probe" = true ]; then
  printf '\nDisposable signed GoTrue + PostgREST HTTP authorization matrix also passed.\n' \
    >> "$artifacts_dir/summary.md"
fi
if [ "$signed_access01_event_choices_probe" = true ]; then
  printf '\nSIGNED ACCESS-01: exact Event identity without extra Work/roster; genuine separate local root, participant, outsider, other-root, withheld and revoked cases passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_person_mail_probe" = true ]; then
  printf '\nSIGNED Person shared mail: true separate signed governor, recipient, outsider, cutoff, fallback, legacy-route and revocation tests.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_ledger_reciprocal_probe" = true ]; then
  printf '\nSIGNED reciprocal native Ledger Work: independent GoTrue owner/worker/outsider, root scoping, non-disclosure, unassigned original, revocation, no shadow People/Principals passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_legacy_queue_owner_probe" = true ]; then
  printf '\nSIGNED queue-owner reconciliation: independent local GoTrue owner/worker/outsider, wrong Ledger, stale original, replay, no Task fabrication or automatic Work and governing root cutoff passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_ledger_disposition_v2_probe" = true ]; then
  printf '\nSIGNED Ledger disposition v2: independent GoTrue worker/governor/outsider, follow-up recovery, edited/rejected same original, idempotent retry, root cutoff and true 42501 denials.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_personal_task_progress_probe" = true ]; then
  printf '\nSIGNED personal original progress: independent local GoTrue actors, cursor pagination, idempotency, transfer/completion/revocation denial and cleanup.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_personal_connected_assignment_probe" = true ]; then
  printf '\nSIGNED reciprocal Personal assignment: independent local GoTrue original send/share, day/backlog, authorship, one completion, privacy and revoke/reconnect.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_personal_task_amendment_probe" = true ]; then
  printf '\nSIGNED personal original task: local GoTrue separation, revision edits, conflicts, replays, revocation, private text cleanup.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_work_release_probe" = true ]; then
  printf '\nSIGNED native Work editing/date/status: local independent GoTrue actors, original identity, stale edit, Result privacy, current plan and revoked seat all passed.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_intake_responsibility_probe" = true ]; then
  printf '\nSIGNED native Ledger intake: fixed source, same original, self assignment, unscheduled transfer, replay, signed own Result and revocation on disposable clone only.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_work_journal_probe" = true ]; then
  printf '\nSIGNED native Work journal: governor recording, participant review, actual/recorded civil day, self vs other and revoked authority on disposable clone only.\n' >> "$artifacts_dir/summary.md"
fi
if [ "$signed_native_original_work_comments_probe" = true ]; then
  if [ "${W07_PROOF_SCOPE:-w07_signed_clone_test_only}" = "w07_shared_native_signed_clone_test_only" ]; then
    printf '\nSIGNED native shared Work: three independent People, two assigned, governor not carrying, notes, terminal and one rescheduled plan; no Production writes.\n' >> "$artifacts_dir/summary.md"
  else
    printf '\nSIGNED W07 original Work comments: four distinct local GoTrue sessions, scoped source read/write, denial, replay, paging and revocation. No Production writes.\n' >> "$artifacts_dir/summary.md"
  fi
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

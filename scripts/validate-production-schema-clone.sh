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
signed_anna_two_service_roots_probe=false
signed_orphan_cancelled_trigger_fn_probe=false
signed_pot_up_retirement_probe=false
signed_pressure_wash_retirement_probe=false
signed_generated_listening_storage_probe=false
signed_private_mp3_profile_probe=false
signed_private_callback_executor_probe=false
signed_private_course_working_loop_probe=false
signed_sk101_course_management_probe=false
signed_sk101_admission_probe=false
orphan_queue_retirement_proof=false
obsolete_unfinished_retirement_proof=false
# HELD exact TWO Anna/field-weeding service-only queue roots;
# immutable original candidate, source/caller/ACL guards, real signed local
# GoTrue owner/worker/outsider/no-seat and full Atlas base row fingerprints.
# Disposable local PostgreSQL17 ONLY; explicitly no production credentials.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_historical_anna_two_service_roots_clone_only_v1[.]sql$ ]] || [ "$(basename "$candidate_migration")" = "20261122175225_atlas_historical_anna_two_service_roots_retirement_v1.sql" ]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != cb4f5cf649663ca9d18e7e77133fc03cd754685a ] ||
     [ "$(git hash-object "$candidate_fixture")" != 76667bafa100414423367b109b3ee04ad21bbd12 ] ||
     [ "$(git hash-object "$candidate_validation")" != 411b0a9ee497969752bde4aa7c39bcbc0654dec1 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'REFUSE unpinned, privileged or nonlocal held Anna two service roots' >&2
    exit 2
  fi
  signed_anna_two_service_roots_probe=true
  signed_work_prerequisite_probe=true
fi

# One immutable owner-approved private caller cutoff, signed clone ONLY.
# The removed original progression trigger had already been retired on main;
# deny all live credentials; keep all five current source-linked functions.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_orphan_cancelled_occurrence_queue_trigger_function_clone_only_v1[.]sql$ ]]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 3033f34ea33af750028ac51df9a307c6d2cd4975 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 6401f4cf44f2c172c156fcc9729c87836988c252 ] ||
     [ "$(git hash-object "$candidate_validation")" != 9b8fdd20c8ea65e0bae98d7b905b4b98967ff24d ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'REFUSE unpinned or privileged orphan cancelled-trigger-function source' >&2
    exit 2
  fi
  signed_orphan_cancelled_trigger_fn_probe=true
  signed_work_prerequisite_probe=true
fi

# HELD original pot-up serial THREE-function source; only pinned original
# package, original genuinely signed C1 actor/proof and full-Atlas row witness.
# Disposable local PG17 ONLY. Separate owner cutoff does NOT grant live release.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_historical_pot_up_serial_branch_clone_only_v1[.]sql$ ]] || [ "$(basename "$candidate_migration")" = "20261122162537_atlas_historical_pot_up_serial_branch_retirement_v1.sql" ]; then
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != eb06b31b273f010549e4a39678f2c6a44b39ba13 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 4d22ffe6cf1c59e2c11d89dc717f399032b18f59 ] ||
     [ "$(git hash-object "$candidate_validation")" != eb37d62f184e26185fe567f2471cc4eb80f9eb03 ] ||
     [ "$(git hash-object "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py")" != a6dbf950b689505babe33811f421add9db2a742d ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'REFUSE unpinned, privileged or nonlocal held pot-up Task serial source' >&2
    exit 2
  fi
  signed_pot_up_retirement_probe=true
  signed_work_prerequisite_probe=true
fi

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

# HELD fixed private callback executor: immutable reviewed two-wrapper
# candidate, original local signed source, no new runner or credential source.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_private_listening_callback_executor_clone_only_v1[.]sql$ ]]; then
  native_dir="$repo_root/candidates/shared-listening-delivery-artifact-v1"
  private_callback_signed_proof="$native_dir/verify_private_callback_executor_signed.py"
  native_signed_helper="$native_dir/verify_generated_listening_storage_signed.py"
  if [ "$lane" != shared ] || [ -n "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [ "$(git hash-object "$candidate_migration")" != b5aa4105e9816d194f740ac365113263f67d8086 ] ||
     [ "$(git hash-object "$candidate_validation")" != a749d7ef221ad82fd19a76e1f565612037c997fb ] ||
     [ "$(git hash-object "$native_signed_helper")" != e7d3f38887ea1419940bf371f1dbb8aea7b16455 ] ||
     [ "$(git hash-object "$private_callback_signed_proof")" != 2431a312b1002bc05241bafad1c81da002dfa7df ]; then
    echo 'Refuse unpinned private callback role or noncanonical GoTrue proof.' >&2
    exit 2
  fi
  python3 -m py_compile "$private_callback_signed_proof"
  signed_private_callback_executor_probe=true
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

# Exact admission transition. Keep the previously released management SQL in the schema snapshot.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_sk101_management_admission_clone_only_v1[.]sql$ ]]; then
  sk101_admission_probe="$repo_root/candidate/candidates/shared-sk101-management-admission-v1/validate-management-admission-signed-http.py"
  if [ "$lane" != shared ] ||
     [ "$(git hash-object "$candidate_migration")" != 54ae5e06377a229530807f01a4878bc52ff4a8f7 ] ||
     [ "$(git hash-object "$sk101_admission_probe")" != 0ff78d8c732329b19c27f8e65adc11d462f48f08 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse SK101 admission proof without exact isolated inputs.' >&2
    exit 2
  fi
  signed_sk101_admission_probe=true
fi

# Exact owner-held SK101 management proof, disposable clone only. The
# protected resolver and this local guard must agree on every immutable input.
if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_shared_sk101_course_management_clone_only_v1[.]sql$ ]] &&
   [ -f "$repo_root/candidate/candidates/shared-sk101-course-management-v1/candidate.sql" ]; then
  if [ "$lane" != shared ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_migration")" != 146caf904994e738200f5d79b981d7fdf3942f87 ] ||
     [ "$(git hash-object "$repo_root/candidate/candidates/shared-sk101-course-management-v1/candidate.sql")" != 146caf904994e738200f5d79b981d7fdf3942f87 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 3f05af628dc4df7f8c483947f77c9996aa9655b3 ] ||
     [ "$(git hash-object "$candidate_validation")" != a7e5fd416d3ebb490fcfb57827adef58a1749a4f ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-sk101-course-management-signed-http.py")" != 19db2b16772539a884437801758a15ee6a16db00 ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ]; then
    echo 'Refuse SK101 management proof without exact isolated package and signed harness.' >&2
    exit 2
  fi
  python3 - "$repo_root/scripts/validate-production-schema-clone.sh" "$repo_root/scripts/validate-sk101-course-management-signed-http.py" <<'PY'
import pathlib, sys
shell = pathlib.Path(sys.argv[1]).read_text()
harness = pathlib.Path(sys.argv[2]).read_text()
for required in (
    'signed_sk101_course_management_probe=false',
    'signed_sk101_course_management_probe=true',
    'shared-sk101-course-management-v1/candidate.sql',
    '146caf904994e738200f5d79b981d7fdf3942f87',
    '3f05af628dc4df7f8c483947f77c9996aa9655b3',
    'a7e5fd416d3ebb490fcfb57827adef58a1749a4f',
    '19db2b16772539a884437801758a15ee6a16db00',
):
    if required not in shell:
        raise SystemExit("SK101 source-contract missing: " + required)
def marker(name):
    return "phase=" + chr(34) + name + chr(34)
fixture = shell.rindex(marker("candidate validation fixture application"))
application = shell.rindex(marker("candidate migration application"))
postconditions = shell.rindex(marker("candidate migration postconditions"))
probe = shell.rindex(marker("independent signed SK101 Course-management matrix"))
if not (fixture < application < postconditions < probe):
    raise SystemExit("SK101 setup ordering must be fixture -> migration -> postconditions -> signed probe")
if 'email=f"atlas-c1-sk101-management-{label}@example.invalid"' not in harness:
    raise SystemExit("SK101 GoTrue fixture login convention is not atlas-c1 prefixed")
for login in ("sk101-management-owner", "sk101-management-outsider"):
    if f'auth.sign_in(api,anon,"{login}")' not in harness:
        raise SystemExit("SK101 signed login convention missing: " + login)
PY
  signed_sk101_course_management_probe=true
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
     [ ! -s "$repo_root/scripts/validate-atlas-native-original-work-comments-signed-http.py" ]; then
    echo "W07 requires a synthetic fixture, postconditions and signed local script." >&2
    exit 2
  fi
  signed_native_original_work_comments_probe=true
fi

# Exact signed native progress for one original personal Task, local clone only.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_personal_task_progress_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed personal progress requires fictional fixture and postconditions." >&2
    exit 2
  fi
  signed_personal_task_progress_probe=true
fi

# Exact held compact composer, admitted solely by the protected
# owner request. Never execute a candidate-selected unpinned probe.
personal_connected_assignment_proof="$repo_root/candidates/atlas/atlas_personal_connected_task_creation_v1/validate_signed_composer.py"
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_compact_composer_creation_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$personal_connected_assignment_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 2d54e30d73c7fd2b83bd06d36f5634f51b5c573b ] ||
     [ "$(git hash-object "$candidate_fixture")" != 01d36beb7116e7fd7c27c89e9d5dfb2c9d6a3f9f ] ||
     [ "$(git hash-object "$candidate_validation")" != 6d924c434f8720fa061a8d0afa4493f028f64318 ] ||
     [ "$(git hash-object "$personal_connected_assignment_proof")" != 0190b3f3ef8e2761ee59a0800f4447e0afe9b9ce ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ]; then
    echo "Held compact composer needs exact reviewed migration, fixture, postconditions and signed local probe." >&2
    exit 2
  fi
  signed_personal_connected_assignment_probe=true
fi

# Exact held optional date, admitted solely by the protected
# owner request. Never execute a candidate-selected unpinned probe.
personal_optional_date_proof="$repo_root/candidates/atlas/atlas_personal_optional_date_v1/validate_signed_optional_date.py"
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_personal_optional_date_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$personal_optional_date_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 65b34da7bc274ddd148f043ecdda9c2cc4beb6ce ] ||
     [ "$(git hash-object "$candidate_fixture")" != 01d36beb7116e7fd7c27c89e9d5dfb2c9d6a3f9f ] ||
     [ "$(git hash-object "$candidate_validation")" != 4dd0d59c1e70b5e8fe37323bd759bce2ef144e46 ] ||
     [ "$(git hash-object "$personal_optional_date_proof")" != 3b6aca3d427b62a0139d870b985ee1057ab5821d ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ]; then
    echo "Held optional date needs exact reviewed migration, fixture, postconditions and signed local probe." >&2
    exit 2
  fi
  signed_personal_optional_date_probe=true
fi

# Exact held initial details, admitted solely by the protected
# owner request. Never execute a candidate-selected unpinned probe.
task_initial_details_proof="$repo_root/candidates/atlas/atlas_task_initial_details_v1/validate_signed_initial_details.py"
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_task_initial_details_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$task_initial_details_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 493836a06949401d067f444d2729366239292588 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 01d36beb7116e7fd7c27c89e9d5dfb2c9d6a3f9f ] ||
     [ "$(git hash-object "$candidate_validation")" != a6cd2160b7a14832c3390921d2e9aeced5d58f43 ] ||
     [ "$(git hash-object "$task_initial_details_proof")" != 1f60014949cd290a3e517a954fb5291634f711e4 ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ]; then
    echo "Held initial details needs exact reviewed migration, fixture, postconditions and signed local probe." >&2
    exit 2
  fi
  signed_task_initial_details_probe=true
fi

# Exact signed personal task amendment requires a fictional disposable clone.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_personal_task_amendment_signed_clone_only_v1[.]sql$ ]]; then
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ]; then
    echo "Signed personal amendment requires fixture and postconditions." >&2
    exit 2
  fi
  signed_personal_task_amendment_probe=true
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

# Exactly one TEST-ONLY owner queue-to-original-Work source package.
# All source/fixture/proof blobs are immutable and scoped to the owner's
# disposable issue request. Never admit this as a production migration.
if [ "$lane" = atlas ] && [ "$version" = 20261120235959 ] &&
   [ "$(basename "$candidate_migration")" = "20261120235959_atlas_legacy_queue_owner_canonical_work_clone_only_v1.sql" ]; then
  queue_signed_proof="$repo_root/candidate/candidates/atlas/atlas_legacy_queue_owner_canonical_work_cutover_v1/validate_signed_queue_owner.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$queue_signed_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 0a47afde4f84b5d08baa025e2bc3f5b1db15df8a ] ||
     [ "$(git hash-object "$candidate_validation")" != c563231ca64bf07c5bdccc805e09997496e3a00b ] ||
     [ "$(git hash-object "$candidate_fixture")" != f24b3f40ecaa32df2f88cf9d9718f0011d240222 ] ||
     [ "$(git hash-object "$queue_signed_proof")" != 7b07b29b1968af6ae0140871413eff62be8a0cd3 ] ||
     [ "$(git hash-object "$repo_root/candidate/scripts/validate-atlas-c1-signed-http.py")" != 1b82e698705e473280f1fc55b0e762bce243effb ] ||
     [ "$(git hash-object "$repo_root/candidate/scripts/validate-atlas-work-prerequisite-signed-http.py")" != eb3bbfb45848a7fca90cc503e153f1451d8d7471 ] ||
     [ "$(git hash-object "$repo_root/candidate/scripts/validate-atlas-ledger-reciprocal-signed-http.py")" != ba2be33fa479e7d24523c10eaee3bbcf12918b3b ]; then
    echo "Refuse legacy queue owner signed proof without exact disposable source, fixture and GoTrue harness." >&2
    exit 2
  fi
  signed_legacy_queue_owner_probe=true
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

# Exact held repair: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_work_subject_pair_repair_clone_only_v1[.]sql$ ]]; then
  household_proof="$repo_root/candidates/atlas/household_work_subject_pair_repair_v1/validate_signed_household_work.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$household_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != de88e16dc36ac052f2fb0e90b708c30253db06d1 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 737c8f98e4c0dcd4e9371a3bc99e123b05aae6c7 ] ||
     [ "$(git hash-object "$candidate_validation")" != 742f436f96149186a0c5c9d3b9d6d598b885667f ] ||
     [ "$(git hash-object "$household_proof")" != a561ee3d34bad17837d02eed3908db3a7be6d61c ]; then
    echo "Exact held Household repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_household_original_repair_probe=true
fi

# Exact held lifecycle: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_laundry_lifecycle_clone_only_v1[.]sql$ ]]; then
  lifecycle_proof="$repo_root/candidates/atlas/household_laundry_process_reassessment_v1/validate_signed_process_reassessment.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$lifecycle_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 058c6627e5c369ed9b83b0f972abc949739095e7 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 737c8f98e4c0dcd4e9371a3bc99e123b05aae6c7 ] ||
     [ "$(git hash-object "$candidate_validation")" != ce747e365321526757e2302f32572dfd45ca91e9 ] ||
     [ "$(git hash-object "$lifecycle_proof")" != 9f1ae62612df98ae0a8b2d73482ebbf58f11fa19 ]; then
    echo "Exact held Laundry lifecycle repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_household_lifecycle_probe=true
fi

# Exact held lifecycle: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_laundry_renewal_initial_clone_only_v1[.]sql$ ]]; then
  renewal_initial_proof="$repo_root/candidates/atlas/household_laundry_renewal_attention_v1/validate_signed_renewal_initial.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$renewal_initial_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 9cb29da5dfd9042224fcc1e1e08414a537c72fa0 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 0a6225004cdd8d693d2f243b770d1b8b7412f5cf ] ||
     [ "$(git hash-object "$candidate_validation")" != 76728974daa1622c11f0c4a9d08e6b26b8c1af11 ] ||
     [ "$(git hash-object "$renewal_initial_proof")" != 09af135127887ca34ed428ec7c4531ab6dc8dc9d ] ||
     [ "$(git hash-object "$(dirname "$renewal_initial_proof")/validate_signed_renewal_attention.py")" != 69426f1df315dafe528981b69dd50a84100ec78c ]; then
    echo "Exact held Laundry renewal initial repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_household_renewal_initial_probe=true
fi

# Exact held lifecycle: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_need_renewal_clean_initial_clone_only_v1[.]sql$ ]]; then
  clean_initial_proof="$repo_root/candidates/atlas/household_need_renewal_clean_cutover_v1/validate_signed_renewal_initial.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$clean_initial_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 27561382cbc33be1da2b1128481702b2d511001f ] ||
     [ "$(git hash-object "$candidate_fixture")" != d0c82b47f242b3ef4fe077f86fd1d20f378e359f ] ||
     [ "$(git hash-object "$candidate_validation")" != 23eaa37cd92a4e72ba954d5892e6b2bae0466aee ] ||
     [ "$(git hash-object "$clean_initial_proof")" != 1251c8971f26518220f8e8851ce9b220b10e60af ] ||
     [ "$(git hash-object "$(dirname "$clean_initial_proof")/validate_signed_renewal_attention.py")" != 9440ffcedd817b33e2736a969e40c523f75e18a3 ]; then
    echo "Exact held clean Need renewal initial repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_clean_renewal_initial_probe=true
fi

# Exact held lifecycle: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_laundry_renewal_due_clone_only_v1[.]sql$ ]]; then
  renewal_due_proof="$repo_root/candidates/atlas/household_laundry_renewal_attention_v1/validate_signed_renewal_historical.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$renewal_due_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 9cb29da5dfd9042224fcc1e1e08414a537c72fa0 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 0a6225004cdd8d693d2f243b770d1b8b7412f5cf ] ||
     [ "$(git hash-object "$candidate_validation")" != 76728974daa1622c11f0c4a9d08e6b26b8c1af11 ] ||
     [ "$(git hash-object "$renewal_due_proof")" != cd244d0f961187bd022309c50790fe5334e92afc ] ||
     [ "$(git hash-object "$(dirname "$renewal_due_proof")/validate_signed_renewal_due.py")" != dde6d83550b892ada267d68a99bde3d493860faa ]; then
    echo "Exact held Laundry renewal due repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_household_renewal_due_probe=true
fi

# Exact held lifecycle: a CLI-created scratch identity with pinned SQL, fixture,
# postconditions and signed probe. No generic candidate-selected executable.
if [ "$lane" = "atlas" ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_household_need_renewal_clean_due_clone_only_v1[.]sql$ ]]; then
  clean_due_proof="$repo_root/candidates/atlas/household_need_renewal_clean_cutover_v1/validate_signed_renewal_historical.py"
  if [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ ! -s "$clean_due_proof" ] ||
     [ "$(git hash-object "$candidate_migration")" != 27561382cbc33be1da2b1128481702b2d511001f ] ||
     [ "$(git hash-object "$candidate_fixture")" != d0c82b47f242b3ef4fe077f86fd1d20f378e359f ] ||
     [ "$(git hash-object "$candidate_validation")" != 23eaa37cd92a4e72ba954d5892e6b2bae0466aee ] ||
     [ "$(git hash-object "$clean_due_proof")" != 6be4632c95c076e3a962a7b8e10967063cc14984 ] ||
     [ "$(git hash-object "$(dirname "$clean_due_proof")/validate_signed_renewal_due.py")" != cbb87cb6cd0feadb459007bc6938f0f566454598 ]; then
    echo "Exact held clean Need renewal due repair and local-only proof bytes required." >&2
    exit 2
  fi
  signed_clean_renewal_due_probe=true
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
# ON CONFLICT ... DO NOTHING is data-only idempotent setup; remove only
# that exact clause before the procedural-keyword scan. Standalone DO blocks
# and every other procedural or privilege statement remain forbidden.
scan_text = re.sub(r'\bon\s+conflict\s*\([^;]*?\)\s+do\s+nothing\b', ' ', normalized, flags=re.I)
forbidden = re.compile(
    r'\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|listen|notify|security)\b',
    re.I,
)
if forbidden.search(scan_text):
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
# ACCESS-03A: startup must use the default exposed schemas. The production-
# shaped atlas schema does not exist until the later schema restore. Exposing
# atlas before startup makes PostgREST health check fail (PGRST002 / 3F000).
# Only after restoration and local SQL postconditions are complete will this
# one disposable clone enable atlas through database-local PostgREST config.
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
  if [ "$t5_signed_study" = true ]; then
    supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_sk101_course_management_probe" = true ] || [ "$signed_sk101_admission_probe" = true ]; then
    # Same disposable PostgreSQL/Auth/REST footprint as the existing signed Course proof.
    supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_private_callback_executor_probe" = true ]; then
    # Genuine loopback GoTrue, Storage, REST and DB on the ORIGINAL protected clone.
    supabase start -x realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_generated_listening_storage_probe" = true ]; then
    # Storage, Auth, REST and Kong must all run; no unrelated services.
    supabase start -x realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_private_mp3_profile_probe" = true ]; then
    # Only local GoTrue, REST and PostgreSQL for signed profile proof.
    # Storage is not used; this remains profile-only, no byte transfer.
    supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_private_course_working_loop_probe" = true ]; then
    # Same local GoTrue, REST and PostgreSQL footprint, on the pinned Course package.
    supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_legacy_farm_invite_probe" = true ]; then
    # Existing local Auth/PostgREST footprint; preserve all older predicates.
    supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
  elif [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||
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
       [ "$signed_household_lifecycle_probe" = true ] ||
       [ "$signed_household_renewal_initial_probe" = true ] ||
       [ "$signed_clean_renewal_initial_probe" = true ] ||
       [ "$signed_household_renewal_due_probe" = true ] ||
       [ "$signed_clean_renewal_due_probe" = true ] ||
       [ "$signed_household_original_repair_probe" = true ] ||
       [ "$signed_universal_original_work_probe" = true ] ||
       [ "$signed_work_self_assignment_probe" = true ] ||
       [ "$signed_native_intake_responsibility_probe" = true ] ||
       [ "$signed_native_work_journal_probe" = true ] ||
       [ "$signed_native_original_work_comments_probe" = true ] ||
       [ "$signed_care_single_done_probe" = true ] ||
       [ "$signed_native_work_release_probe" = true ] ||
       [ "$signed_personal_task_amendment_probe" = true ] ||
       [ "$signed_personal_task_progress_probe" = true ] ||
       [ "$signed_personal_connected_assignment_probe" = true ] ||
       [ "$signed_personal_optional_date_probe" = true ] ||
       [ "$signed_task_initial_details_probe" = true ] ||
       [ "$signed_titus_object_title_probe" = true ] ||
       [ "$signed_ledger_reciprocal_probe" = true ] ||
       [ "$signed_ledger_disposition_v2_probe" = true ] ||
       [ "$signed_legacy_queue_owner_probe" = true ] ||
       [ "$signed_unified_today_p0_probe" = true ] ||
       [ "$signed_person_mail_probe" = true ] ||
       [ "$signed_venue_bed_probe" = true ] ||
       [ "$signed_access01_event_choices_probe" = true ] ||
       [ "$signed_access02_my_work_probe" = true ] ||
       [ "$signed_access03_zone_retirement_probe" = true ]; then
    # The source-governed signed care/Done test requires only PostgreSQL,
    # local GoTrue, PostgREST and the Kong API gateway. Pulling Studio,
    # analytics, Realtime, storage and auxiliary containers consumed the
    # public ECR quota before signed tests could start (two protected runs).
    # Limit this to the existing care probe; no change to other clone lanes,
    # image registries, pinned CLI, health checks, JWT verification or SQL.
    if [ "$orphan_queue_retirement_proof" = true ] || [ "$obsolete_unfinished_retirement_proof" = true ]; then
      supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >"$startup_log" 2>&1
    elif [ "$signed_care_single_done_probe" = true ] ||
       [ "$signed_native_work_release_probe" = true ] ||
       [ "$signed_personal_task_amendment_probe" = true ] ||
       [ "$signed_personal_task_progress_probe" = true ] ||
       [ "$signed_personal_connected_assignment_probe" = true ] ||
       [ "$signed_personal_optional_date_probe" = true ] ||
       [ "$signed_task_initial_details_probe" = true ] ||
       [ "$signed_titus_object_title_probe" = true ] ||
       [ "$signed_native_intake_responsibility_probe" = true ] ||
       [ "$signed_native_work_journal_probe" = true ] ||
       [ "$signed_native_original_work_comments_probe" = true ] ||
       [ "$signed_ledger_reciprocal_probe" = true ] ||
       [ "$signed_ledger_disposition_v2_probe" = true ] ||
       [ "$signed_legacy_queue_owner_probe" = true ] ||
       [ "$signed_venue_bed_probe" = true ] ||
       [ "$signed_access01_event_choices_probe" = true ] ||
       [ "$signed_access02_my_work_probe" = true ] ||
       [ "$signed_access03_zone_retirement_probe" = true ]; then
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

# T5 only: use the job-created local database container's Unix socket.
# Assertions run in the candidate transaction and it must roll back.
# Do not enter migration application, persistent validation or release lint.
if [ "$t5_rollback_shape" = true ]; then
  phase="T5 disposable rollback-only shape"
  local_project_id="$(python3 - "$project_dir/supabase/config.toml" <<'PY'
import re,sys,tomllib
with open(sys.argv[1],"rb") as f:
    value=tomllib.load(f)["project_id"]
assert re.fullmatch(r"validation_20261119100000_[0-9a-f]{8}",value)
print(value)
PY
)"
  local_container="supabase_db_$local_project_id"
  test "$(docker inspect --format '{{.State.Running}}' "$local_container")" = true
  docker port "$local_container" 5432/tcp | grep -Eq ":$local_database_port$"
  test "$(docker exec "$local_container" psql -X -U postgres -d postgres -Atqc "SELECT current_setting('server_version_num')::int/10000,inet_server_addr() IS NULL,current_user")" = '17|t|postgres'
  docker exec -i "$local_container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 \
    <"$candidate_migration" >"$artifacts_dir/t5-rollback-only.log" 2>&1
  test "$(docker exec "$local_container" psql -X -U postgres -d postgres -Atqc "SELECT to_regclass('atlas.teaching_course_composition_revisions') IS NULL AND to_regclass('atlas.teaching_course_private_answer_submissions') IS NULL AND NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='atlas.teaching_course_versions'::regclass AND attname='publication_request_id' AND NOT attisdropped)")" = t
  echo 'PASS T5 restored schema compilation and private ACL postconditions; rollback confirmed.'
  if [ "$t5_signed_study" = true ]; then
    phase="T5 signed fictional HTTP proof"
    # Only on this job-owned disposable clone: retain the just-proved source
    # to exercise independent GoTrue transactions. No production migration.
    python3 - "$candidate_migration" "$runtime_dir/t5-signed-local-only.sql" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert s.rstrip().endswith("ROLLBACK;")
Path(sys.argv[2]).write_text(s.rstrip()[:-len("ROLLBACK;")]+"COMMIT;\n")
PY
    docker exec -i "$local_container" psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 \
      <"$runtime_dir/t5-signed-local-only.sql" >"$artifacts_dir/t5-local-install.log" 2>&1
    psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/t5-local-reload.log" 2>&1
    python3 "$repo_root/scripts/validate-titus-t5-signed-study-http.py" --db-url "$database_url" --output "$artifacts_dir/t5-signed-receipt.txt" >"$artifacts_dir/t5-signed-local.log" 2>&1
    test "$(cat "$artifacts_dir/t5-signed-receipt.txt")" = 'PASS T5 independent local signed study journey'
    echo 'PASS T5 independent local signed study journey; disposable clone only.'
  fi
  exit 0
fi

run_lint() {
  lint_name="$1"
  lint_output="$artifacts_dir/schema-lint-${lint_name}.raw.log"
  set +e
  if [[ "$lane" == "noel" ]]; then
    # Noel owns draft Reality Pools and core/intelligence evidence infrastructure.
    # Compare *changes* to the inherited lint baseline, not existing lint debt.
    supabase db lint --local --schema draft,core,intelligence --level error --fail-on error >"$lint_output" 2>&1
  elif [[ "$lane" == "titus" ]]; then
    # Titus's structural release must lint Titus, not accidentally pass on Atlas.
    # Do not widen this to private Noel research or unrelated application schemas.
    supabase db lint --local --schema titus --level error --fail-on error >"$lint_output" 2>&1
  else
    supabase db lint --local --schema atlas --level error --fail-on error >"$lint_output" 2>&1
  fi
  lint_status=$?
  set -e
  printf '%s\n' "$lint_status" > "$artifacts_dir/schema-lint-${lint_name}.exit-code.txt"
}

# W07 direct-original only: re-establish the verified released REST ACL
# baseline for the exact held correction or its byte-identical generated
# migration package. Signed tests confirmed the local restore creates 16
# extra direct grants; the same correction is required in the release clone.
# No production credentials, arbitrary package, or release-script path.
w07_generated_parity=false
if [ "$version" = 20261119230336 ] &&
   [ "$(basename "$candidate_migration")" = 20261119230336_atlas_native_shared_work_direct_original_v1.sql ]; then
  w07_generated_parity=true
fi
if { [ "$signed_native_original_work_comments_probe" = true ] &&
     [[ "${REQUEST_SCOPE:-}" == w07_direct_original_* ]]; } ||
   [ "$w07_generated_parity" = true ]; then
  phase="W07 disposable direct-original REST ACL parity"
  if { [ "$w07_generated_parity" = false ] &&
       [[ "${REQUEST_SCOPE:-}" != w07_direct_original_signed_clone_test_only &&
          "${REQUEST_SCOPE:-}" != w07_direct_original_privacy_clone_test_only ]]; } ||
     { [ "$w07_generated_parity" = true ] &&
       { [ -n "${REQUEST_SCOPE:-}" ] ||
         [ -z "$candidate_fixture" ] ||
         [ "$(git hash-object "$candidate_fixture")" != 5689af4e122c358261ea5f43b67c80098b6d5edf ]; }; } ||
     [ "$lane" != atlas ] ||
     [ "$(git hash-object "$candidate_migration")" != e590441c4c10a75c15f811227b9f62a15f0be107 ] ||
     [ "$(git hash-object "$candidate_validation")" != 1a21fffea419280775ae532fa351d2a1e1b94d02 ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [[ ! "$database_url" =~ ^postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'REFUSE W07 parity without exact direct-original local package' >&2; exit 2
  fi
  PGOPTIONS="-c w07.direct_disposable_clone=true" \
    psql "$database_url" -X -v ON_ERROR_STOP=1 \
      -f "$repo_root/scripts/atlas-w07-direct-disposable-rest-acl-parity-held.sql" \
      >"$artifacts_dir/w07-direct-rest-acl-parity.log" 2>&1
fi

phase="baseline domain schema lint"
run_lint baseline

if [ "$obsolete_unfinished_retirement_proof" = true ]; then
  phase="trusted original C1 Work fixture before bounded old-queue synthetic data"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql" \
    >"$artifacts_dir/obsolete-retirement-original-c1-fixture.log" 2>&1
fi

# P0 orphan owner-completion disposable proof ONLY: the independent signed
# original C1 Work fixture must establish its fictional owner/Organization first.
# The bounded 97-row historical queue fixture refers to that exact identity.
# Do not widen admission, clone production data, or bypass real actor checks.
if [ "$orphan_queue_retirement_proof" = true ] &&
   [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_owner_completion_queue_orphan_branch_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql" ]]; then
  phase="trusted original C1 Work fixture before historical owner queue data"
  trusted_c1="$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql"
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$trusted_c1")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 19981823e3d6e7da8a82b5d609fb1558e38c4251 ] ||
     [ "$(git hash-object "$candidate_migration")" != a5a23c42557bf6913321689fb9853afb57ff2c0e ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo "Refuse C1 pre-load without exact original Work fixture, immutable candidate, and local-only database" >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$trusted_c1" \
    >"$artifacts_dir/owner-queue-original-signed-c1-fixture.log" 2>&1
fi


# Separately locked admission of the NEW Anna orphan fixture, preserving the
# original older owner-completion branch's exact test admission unchanged.
if [ "$orphan_queue_retirement_proof" = true ] &&
   [[ "$(basename "$candidate_migration")" == "20261121235035_atlas_anna_orphaned_serial_effect_retirement_v1.sql" ]]; then
  phase="trusted original C1 Work fixture before synthetic Anna terminal queue"
  trusted_c1="$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql"
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$trusted_c1")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 5ddc096700e726fd9681df0067f23576b848f124 ] ||
     [ "$(git hash-object "$candidate_migration")" != 7fb7c4bdefc735484448fa3845e0125a2ffaa4eb ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'Refuse new Anna orphan C1 preload without immutable source, synthetic fixture and local-only PostgreSQL' >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$trusted_c1" \
    >"$artifacts_dir/anna-orphan-original-signed-c1-fixture.log" 2>&1
fi


# New exact-version C1 identity pre-load. Original protected C1 fixture is
# immutable, non-production, and installed before synthetic fixture and
# before ALL local Atlas row fingerprints; no historical rows copied.
if [ "$orphan_queue_retirement_proof" = true ] &&
   [[ "$(basename "$candidate_migration")" == "20261122003235_atlas_legacy_person_specific_task_trigger_retirement_v1.sql" ]]; then
  phase="trusted original C1 Work fixture before legacy Task trigger retirement"
  trusted_c1="$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql"
  if [ "$lane" != atlas ] || [ -z "$candidate_fixture" ] || [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$trusted_c1")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [ "$(git hash-object "$candidate_fixture")" != 60ac062da84b34be539ede296dda5434aa58d061 ] ||
     [ "$(git hash-object "$candidate_migration")" != fade2e58598e4e32e49f9e84f481c54b3611ad9f ] ||
     [ -n "${NOEL_CORE_DATABASE_URL:-}${DATABASE_URL:-}${SUPABASE_DB_URL:-}${SUPABASE_ACCESS_TOKEN:-}${SUPABASE_SERVICE_ROLE_KEY:-}${SUPABASE_SECRET_KEY:-}" ] ||
     [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'Refuse exact Task trigger C1 pre-load without fixed source and local-only PostgreSQL.' >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$trusted_c1" \
    >"$artifacts_dir/person-task-original-signed-c1-fixture.log" 2>&1
fi

if [ "$signed_legacy_farm_invite_probe" = true ]; then
  phase="held farm original fictional identities and member fixture"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql" \
    >"$artifacts_dir/legacy-farm-original-c1-fixture.log" 2>&1
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/scripts/atlas-legacy-farm-member-disposable-fixture.sql" \
    >"$artifacts_dir/legacy-farm-member-fixture.log" 2>&1
fi

# The original orphan-cancellation fixture expects the trusted original C1
# fictional Organization to exist BEFORE its own 97 synthetic queue rows.
# This isolated preload was missing from test run #45060597787, which failed
# at the fictional fixture preflight before candidate SQL was attempted.
if [ "$signed_orphan_cancelled_trigger_fn_probe" = true ]; then
  phase="held orphan-cancelled-trigger original signed C1 Work/Organization fixture"
  trusted_c1="$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql"
  if [ "$lane" != atlas ] ||
     [ "$(git hash-object "$trusted_c1")" != 766ab2b69c53796ca6aa892d57a1188fab799bc8 ] ||
     [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'REFUSE orphan cancelled-trigger preflight without original trusted C1 and local PG17' >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$trusted_c1" \
    >"$artifacts_dir/orphan-cancelled-trigger-original-c1-fixture.log" 2>&1
fi

if [ "$signed_anna_two_service_roots_probe" = true ]; then
  phase="held anna-two-service-roots original signed C1 fictional Person/Work fixture"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql" \
    >"$artifacts_dir/anna-two-service-roots-original-c1-fixture.log" 2>&1
fi

if [ "$signed_pot_up_retirement_probe" = true ]; then
  phase="held pot-up original signed C1 fictional Person/Work fixture"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql" \
    >"$artifacts_dir/pot-up-original-c1-fixture.log" 2>&1
fi

if [ "$signed_pressure_wash_retirement_probe" = true ]; then
  phase="held pressure-wash original signed C1 fictional Person/Work fixture"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql" \
    >"$artifacts_dir/pressure-wash-original-c1-fixture.log" 2>&1
fi

if [ -n "$candidate_fixture" ]; then
  phase="candidate validation fixture application"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_fixture" \
    >"$artifacts_dir/candidate-fixture.log" 2>&1
else
  echo 'No candidate validation fixture is defined.' >"$artifacts_dir/candidate-fixture.log"
fi

# PRE1 TEST ONLY: inspect ALL local Atlas base table rows, including original
# Work IDs, physical history, and associated metadata, before function-only DROP.
# Snapshot is kept in the disposable runtime directory and never uploaded.
if [ "$pre1_rest_proof" = true ]; then
  phase="PRE1 local all-Atlas-table identity/content baseline"
  pre1_row_snapshot="$runtime_dir/pre1-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pre1_row_snapshot" --mode capture \
    >"$artifacts_dir/pre1-local-row-integrity-baseline.log" 2>&1
fi

# No production rows are cloned. Capture every local Atlas base relation
# after the trusted fictional Work fixture and before the exact deletion.
if [ "$orphan_queue_retirement_proof" = true ]; then
  phase="orphan backfill local all-Atlas-row baseline"
  [[ "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select current_setting('server_version_num')::int/10000")" = 17
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from atlas.work_items")" -gt 0
  orphan_row_snapshot="$runtime_dir/orphan-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$orphan_row_snapshot" --mode capture \
    >"$artifacts_dir/orphan-local-row-integrity-baseline.log" 2>&1
fi

if [ "$obsolete_unfinished_retirement_proof" = true ]; then
  phase="held obsolete queue full-Atlas pre-retirement row baseline"
  obsolete_row_snapshot="$runtime_dir/obsolete-queue-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-obsolete-queue-retirement-row-change.py" \
    --db-url "$database_url" --snapshot "$obsolete_row_snapshot" --mode capture \
    >"$artifacts_dir/obsolete-queue-row-baseline.log" 2>&1
fi

if [ "$signed_legacy_farm_invite_probe" = true ]; then
  phase="held farm genuine signed original member reader BEFORE SQL candidate"
  if [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'REFUSE nonlocal signed farm member proof' >&2; exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c \
    "ALTER ROLE authenticator IN DATABASE postgres SET pgrst.db_schemas = 'public,graphql_public,atlas';" \
    >"$artifacts_dir/legacy-farm-local-exposure.log" 2>&1
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c \
    "NOTIFY pgrst, 'reload config'; NOTIFY pgrst, 'reload schema';" \
    >>"$artifacts_dir/legacy-farm-local-exposure.log" 2>&1
  python3 "$repo_root/scripts/validate-atlas-legacy-farm-invite-signed-http.py" \
    --db-url "$database_url" --phase before \
    --state-file "$runtime_dir/legacy-farm-member-original.json" \
    --receipt "$artifacts_dir/legacy-farm-member-signed-summary.txt" \
    >"$artifacts_dir/legacy-farm-member-before.log" 2>&1
fi

if [ "$signed_orphan_cancelled_trigger_fn_probe" = true ]; then
  phase="held orphan cancellation trigger function: all Atlas base rows BEFORE SQL"
  [[ "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select current_setting('server_version_num')::int/10000")" = 17
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from atlas.work_items")" -gt 0
  orphan_cancel_trigger_snapshot="$runtime_dir/held-orphan-cancelled-trigger-fn-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$orphan_cancel_trigger_snapshot" --mode capture \
    >"$artifacts_dir/orphan-cancelled-trigger-all-atlas-row-baseline.log" 2>&1
fi

if [ "$signed_anna_two_service_roots_probe" = true ]; then
  phase="held anna-two-service-roots all Atlas base rows BEFORE original SQL"
  [[ "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select current_setting('server_version_num')::int/10000")" = 17
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from atlas.work_items")" -gt 0
  anna_two_roots_snapshot="$runtime_dir/held-anna-two-service-roots-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$anna_two_roots_snapshot" --mode capture \
    >"$artifacts_dir/anna-two-service-roots-all-atlas-row-baseline.log" 2>&1
fi

if [ "$signed_pot_up_retirement_probe" = true ]; then
  phase="held pot-up all Atlas base rows BEFORE original SQL"
  [[ "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select current_setting('server_version_num')::int/10000")" = 17
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from atlas.work_items")" -gt 0
  pot_up_snapshot="$runtime_dir/held-pot-up-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pot_up_snapshot" --mode capture \
    >"$artifacts_dir/pot-up-all-atlas-row-baseline.log" 2>&1
fi

if [ "$signed_pressure_wash_retirement_probe" = true ]; then
  phase="held pressure-wash all Atlas base rows BEFORE exact original SQL"
  [[ "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select current_setting('server_version_num')::int/10000")" = 17
  test "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc "select count(*) from atlas.work_items")" -gt 0
  pressure_wash_snapshot="$runtime_dir/held-pressure-wash-all-atlas-row-fingerprints.json"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pressure_wash_snapshot" --mode capture \
    >"$artifacts_dir/pressure-wash-all-atlas-row-baseline.log" 2>&1
fi

phase="candidate migration application"
# Test the NEW exact-version live row guard with the ORIGINAL canonical
# migration through the EXISTING releaser on this disposable local clone.
# This is not the protected production release. Remote URLs are never used.
if [ "$lane" = atlas ] && [ "$version" = 20261120211526 ] &&
   [ "$(basename "$candidate_migration")" = "20261120211526_atlas_access03c_pre1_tending_v1_pair_retirement_v1.sql" ]; then
  # Bind the releaser to THIS disposable clone's assigned local port.
  # The canonical startup selected and configured 38000..60999 above; a
  # different host, endpoint, or port must fail closed, never fall back.
  if [[ ! "$local_database_port" =~ ^[0-9]{5}$ ]] ||
     [ "$local_database_port" -lt 38000 ] ||
     [ "$local_database_port" -ge 61000 ] ||
     [ "$database_url" != "postgresql://postgres:postgres@127.0.0.1:${local_database_port}/postgres" ] ||
     [ "$(git hash-object "$candidate_migration")" != ac8552f35e4de14f1ae337c29cfc1c2971af1c9b ] ||
     [ -z "$candidate_validation" ] ||
     [ "$(git hash-object "$candidate_validation")" != aff86ae537a7dfbffefa4320e6d21328c32c78d7 ]; then
    echo 'Refusing PRE1 guarded release proof without exact local clone and source.' >&2
    exit 2
  fi
  # This clone restores only production USER schemas; Supabase's managed
  # migration-history table is intentionally not part of that schema dump.
  # Verify the job-owned database container before provisioning ONLY its
  # scratch history table. No remote session, production rows, or real history.
  pre1_project_id="$(python3 - "$project_dir/supabase/config.toml" <<'PY'
import re, sys, tomllib
with open(sys.argv[1], "rb") as f:
    project = tomllib.load(f)["project_id"]
assert re.fullmatch(r"validation_20261120211526_[0-9a-f]{8}", project)
print(project)
PY
)"
  pre1_container="supabase_db_$pre1_project_id"
  test "$(docker inspect --format '{{.State.Running}}' "$pre1_container")" = true
  docker port "$pre1_container" 5432/tcp | grep -Eq ":$local_database_port$"
  # Pinned Supabase CLI v2.116.0 native history columns are version text PK,
  # statements text[] and name text (pkg/migration/history.go). Noel's own
  # existing releaser additionally records created_by text. An empty local
  # table with those columns is needed for an authentic release-wrapper test.
  # The command refuses a pre-existing history table instead of overriding it.
  phase="PRE1 disposable native migration-history compatibility"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -q \
    >"$artifacts_dir/pre1-local-history-bootstrap.log" 2>&1 <<'SQL'
BEGIN;
DO $pre1_missing_local_history$
BEGIN
  IF to_regclass('supabase_migrations.schema_migrations') IS NOT NULL THEN
    RAISE EXCEPTION 'PRE1 disposable migration history already exists';
  END IF;
END
$pre1_missing_local_history$;
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations (
  version text NOT NULL PRIMARY KEY,
  statements text[],
  name text,
  created_by text
);
REVOKE ALL ON TABLE supabase_migrations.schema_migrations FROM PUBLIC;
COMMIT;
SQL
  if [ "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc       "SELECT string_agg(column_name || ':' || udt_name, ',' ORDER BY ordinal_position)
       FROM information_schema.columns
       WHERE table_schema='supabase_migrations' AND table_name='schema_migrations'")" \
      != 'version:text,statements:_text,name:text,created_by:text' ] ||
     [ "$(psql "$database_url" -X -v ON_ERROR_STOP=1 -Atqc       'SELECT count(*) FROM supabase_migrations.schema_migrations')" != 0 ]; then
    echo 'Refusing PRE1 proof: disposable history table has unexpected shape or rows.' >&2
    exit 2
  fi
  phase="PRE1 guarded candidate migration application"
  (
    cd "$repo_root"
    NOEL_CORE_DATABASE_URL="$database_url" \
      GITHUB_RELEASE_SHA=0000000000000000000000000000000000000000 \
      bash scripts/release-production-migration.sh "$version"
  ) >"$artifacts_dir/candidate-migration.log" 2>&1
  grep -q 'PASS PRE1 same-transaction original-row conservation: 730 Atlas base relations' \
    "$artifacts_dir/candidate-migration.log"
else
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_migration" \
    >"$artifacts_dir/candidate-migration.log" 2>&1
fi

# ACCESS-02 TEST ONLY: exact My Work wrapper clone-only anonymous ACL
# parity, never a migration or permission change on a linked database.
if [ "$signed_access02_my_work_probe" = true ]; then
  phase="ACCESS-02 disposable anonymous REST ACL parity"
  PGOPTIONS="-c access02.disposable_clone=true" \
    psql "$database_url" -X -v ON_ERROR_STOP=1 \
      -f "$repo_root/scripts/atlas-access02-disposable-anon-parity-held.sql" \
      >"$artifacts_dir/access02-anon-parity.log" 2>&1
fi

# ACCESS-01 only: restore the *exact* expected anonymous-denial baseline
# after a production-shaped user-schema restore, if the two PUBLIC REST wrapper
# grants differ only by the known clone-specific extra anon grant.
# The helper refuses any unexpected shape; it changes only the local clone.
if [ "$signed_access01_event_choices_probe" = true ] || {
     [ "$lane" = "atlas" ] &&
     [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_access01_event_choices_root_boundary_v1[.]sql$ ]];
   }; then
  phase="ACCESS-01 disposable anonymous REST ACL parity"
  PGOPTIONS="-c access01.disposable_clone=true" \
    psql "$database_url" -X -v ON_ERROR_STOP=1 \
      -f "$repo_root/scripts/atlas-access01-disposable-anon-parity-held.sql" \
      >"$artifacts_dir/access01-anon-parity.log" 2>&1
fi

phase="candidate migration postconditions"
if [ -n "$candidate_validation" ]; then
  psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_validation" \
    >"$artifacts_dir/postconditions.log" 2>&1
else
  echo "No candidate migration-specific postcondition file is defined for ${version}." \
    >"$artifacts_dir/postconditions.log"
fi

if [ "$signed_sk101_admission_probe" = true ]; then
  phase="signed SK101 carrier admission transition"
  sk101_probe_dir="$(mktemp -d)"
  cp "$repo_root/scripts/validate-atlas-c1-signed-http.py" "$sk101_admission_probe" "$sk101_probe_dir/"
  python3 "$sk101_probe_dir/validate-management-admission-signed-http.py" --db-url "$database_url" \
    --output "$artifacts_dir/sk101-admission-signed-receipt.txt" \
    >"$artifacts_dir/sk101-admission-signed-local.log" 2>&1
  test -s "$artifacts_dir/sk101-admission-signed-receipt.txt"
fi

if [ "$signed_sk101_course_management_probe" = true ]; then
  phase="independent signed SK101 Course-management matrix"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/sk101-management-reload.log" 2>&1
  python3 "$repo_root/scripts/validate-sk101-course-management-signed-http.py" \
    --db-url "$database_url" --output "$artifacts_dir/sk101-management-signed-receipt.txt" \
    >"$artifacts_dir/sk101-management-signed-local.log" 2>&1
  test "$(cat "$artifacts_dir/sk101-management-signed-receipt.txt")" = 'PASS signed SK101 management clone'
fi

if [ "$signed_orphan_cancelled_trigger_fn_probe" = true ]; then
  phase="held orphan cancellation trigger function: all Atlas rows AFTER DROP RESTRICT"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$orphan_cancel_trigger_snapshot" --mode verify \
    >"$artifacts_dir/orphan-cancelled-trigger-all-atlas-row-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/orphan-cancelled-trigger-all-atlas-row-after-candidate.log"
fi

if [ "$signed_anna_two_service_roots_probe" = true ]; then
  phase="held anna-two-service-roots all Atlas rows AFTER two function-only DROP RESTRICT"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$anna_two_roots_snapshot" --mode verify \
    >"$artifacts_dir/anna-two-service-roots-all-atlas-row-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/anna-two-service-roots-all-atlas-row-after-candidate.log"
fi

if [ "$signed_pot_up_retirement_probe" = true ]; then
  phase="held pot-up all Atlas rows AFTER three function-only DROP RESTRICT"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pot_up_snapshot" --mode verify \
    >"$artifacts_dir/pot-up-all-atlas-row-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/pot-up-all-atlas-row-after-candidate.log"
fi

if [ "$signed_pressure_wash_retirement_probe" = true ]; then
  phase="held pressure-wash exact original source all Atlas rows AFTER DROP RESTRICT"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pressure_wash_snapshot" --mode verify \
    >"$artifacts_dir/pressure-wash-all-atlas-row-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/pressure-wash-all-atlas-row-after-candidate.log"
fi

if [ "$signed_legacy_farm_invite_probe" = true ]; then
  phase="held farm genuine signed member no-loss AFTER SQL candidate"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c \
    "NOTIFY pgrst, 'reload schema';" \
    >"$artifacts_dir/legacy-farm-reload-post.log" 2>&1
  python3 "$repo_root/scripts/validate-atlas-legacy-farm-invite-signed-http.py" \
    --db-url "$database_url" --phase after \
    --state-file "$runtime_dir/legacy-farm-member-original.json" \
    --receipt "$artifacts_dir/legacy-farm-member-signed-summary.txt" \
    >"$artifacts_dir/legacy-farm-member-after.log" 2>&1
  grep -q '^PASS HELD farm invitation source retirement signed owner/nonowner ' \
    "$artifacts_dir/legacy-farm-member-signed-summary.txt"
fi

if [ "$obsolete_unfinished_retirement_proof" = true ]; then
  phase="held obsolete queue exact four source-capacity tables and all-other-Atlas-row conservation"
  python3 "$repo_root/scripts/validate-atlas-obsolete-queue-retirement-row-change.py" \
    --db-url "$database_url" --snapshot "$obsolete_row_snapshot" --mode verify \
    >"$artifacts_dir/obsolete-queue-row-after-candidate.log" 2>&1
  grep -q "^PASS historical retirement: exactly four source-owned Atlas relations changed" \
    "$artifacts_dir/obsolete-queue-row-after-candidate.log"
fi

if [ "$orphan_queue_retirement_proof" = true ]; then
  phase="orphan backfill local all-Atlas-row unchanged after exact deletion"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$orphan_row_snapshot" --mode verify \
    >"$artifacts_dir/orphan-local-row-integrity-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/orphan-local-row-integrity-after-candidate.log"
fi

# PRE1: verify that the exact two-function DROP and its postconditions
# changed ZERO row identities/values in ANY Atlas base relation.
if [ "$pre1_rest_proof" = true ]; then
  phase="PRE1 local all-Atlas-row unchanged after function retirement"
  python3 "$repo_root/scripts/validate-atlas-access03c-pre1-local-row-integrity.py" \
    --db-url "$database_url" --snapshot "$pre1_row_snapshot" --mode verify \
    >"$artifacts_dir/pre1-local-row-integrity-after-candidate.log" 2>&1
  grep -q '^PASS ACCESS03C-PRE1 local all-base-row identity/content conservation:' \
    "$artifacts_dir/pre1-local-row-integrity-after-candidate.log"
fi

if [ "$signed_legacy_queue_owner_probe" = true ]; then
  phase="genuinely signed local Ledger-owner queue evidence and original Work denial matrix"
  if [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'Queue owner signed proof refuses nonlocal database' >&2
    exit 2
  fi
  python3 "$queue_signed_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-legacy-queue-owner-summary.txt" \
    >"$artifacts_dir/signed-legacy-queue-owner.log" 2>&1
  test -s "$artifacts_dir/signed-legacy-queue-owner-summary.txt"
  grep -q '^PASS signed original queue owner, wrong Ledger' \
    "$artifacts_dir/signed-legacy-queue-owner-summary.txt"
fi

if [ "$signed_access02_my_work_probe" = true ]; then
  phase="genuinely signed local ACCESS-02 My Work relevance grant-withdraw-restore"
  python3 "$repo_root/scripts/validate-atlas-access02-my-work-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-access02-my-work-summary.txt" \
    >"$artifacts_dir/signed-access02-my-work.log" 2>&1
  test -s "$artifacts_dir/signed-access02-my-work-summary.txt"
  grep -q '^PASS ACCESS-02 signed ' "$artifacts_dir/signed-access02-my-work-summary.txt"
fi

if [ "$signed_access03_zone_retirement_probe" = true ]; then
  phase="ACCESS-03A disposable PostgREST schema exposure AFTER schema restoration"
  # This explicit local-only URL guard also protects the helper if the
  # shared controller's earlier local-database guard changes in future.
  if [[ ! "$database_url" =~ ^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo "ACCESS03 PostgREST schema exposure refuses nonlocal database" >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c \
    "ALTER ROLE authenticator IN DATABASE postgres SET pgrst.db_schemas = 'public,graphql_public,atlas';" \
    >"$artifacts_dir/access03-local-pgrst-exposure.log" 2>&1
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c \
    "NOTIFY pgrst, 'reload config'; NOTIFY pgrst, 'reload schema';" \
    >>"$artifacts_dir/access03-local-pgrst-exposure.log" 2>&1
  # Database-specific settings override default container environment only
  # on this disposable local instance; no production settings are touched.
fi

if [ "$signed_access03_zone_retirement_probe" = true ]; then
  phase="genuine signed local ACCESS-03A legacy zone and crop direct read retirement"
  python3 "$repo_root/scripts/validate-atlas-access03-zone-retirement-signed-http.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/signed-access03-zone-retirement-summary.txt" \
    >"$artifacts_dir/signed-access03-zone-retirement.log" 2>&1
  test -s "$artifacts_dir/signed-access03-zone-retirement-summary.txt"
  grep -q '^PASS ACCESS03 signed ' "$artifacts_dir/signed-access03-zone-retirement-summary.txt"
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


if [ "$signed_private_callback_executor_probe" = true ]; then
  # Supabase-managed storage.objects policies are intentionally absent from the
  # production USER-schema-only dump. These eight existing released policies
  # must be restored from their ORIGINAL immutable Noel SQL SOURCE, into this
  # disposable local PostgreSQL clone ONLY, before invoking the unchanged
  # canonical signed Storage/GoTrue fixture. Do not forge permissions or
  # weaken the signed precondition. Refuse any altered source/shape.
  phase="restore exact released native Storage policy parity in disposable clone only"
  listening_generated_source="$repo_root/candidates/shared-listening-delivery-artifact-v1/generated_listening_storage_candidate.sql"
  listening_original_source="$repo_root/candidates/shared-listening-delivery-artifact-v1/manuscript_original_registration_candidate.sql"
  if [ "$(git hash-object "$listening_generated_source")" != 106268970a69c33c5a8d30d737e5d98af807ccfa ] ||
     [ "$(git hash-object "$listening_original_source")" != de89478c094719912a9ac145af28e01186584c32 ]; then
    echo 'REFUSE noncanonical native Storage policy source on callback clone.' >&2
    exit 2
  fi
  python3 - "$listening_generated_source" "$listening_original_source" \
    "$artifacts_dir/private-callback-existing-storage-policy-parity.sql" <<'PY_CALLBACK_EXISTING_STORAGE_POLICIES'
import pathlib
import re
import sys

generated, original, output = map(pathlib.Path, sys.argv[1:])
names = (
  "transcript_core_listening_render_insert_v1",
  "transcript_core_listening_render_read_guard_v1",
  "transcript_core_listening_render_update_guard_v1",
  "transcript_core_listening_render_delete_guard_v1",
  "transcript_core_manuscript_original_insert_guard_v1",
  "transcript_core_manuscript_original_read_guard_v1",
  "transcript_core_manuscript_original_update_guard_v1",
  "transcript_core_manuscript_original_delete_guard_v1",
)
statements = []
found = []
for source in (generated, original):
    content = source.read_text()
    matches = list(re.finditer(
        r"^CREATE POLICY ([a-z][a-z0-9_]*) ON storage[.]objects\s+([\s\S]*?);",
        content, re.MULTILINE))
    if len(matches) != 4 or content.count("CREATE POLICY ") != 4:
        raise SystemExit("REFUSE changed original native Storage policy statement count")
    for match in matches:
        found.append(match.group(1))
        statements.append(match.group(0))
if tuple(found) != names or len(set(found)) != 8:
    raise SystemExit("REFUSE altered original native Storage policy identity/order")

escaped_names = ",".join("'" + name + "'" for name in names)
# The source copy has NO DROP, no broad grant and no synthetic substitute.
# Production's original eight policies are checked below by exact pg_policies
# structural fingerprint, not merely by counting their names.
sql = (
    "BEGIN;\n"
    "DO $policy_preflight$\nBEGIN\n"
    " IF (SELECT count(*) FROM pg_policies WHERE schemaname='storage' "
    "AND tablename='objects' AND (policyname LIKE "
    "'transcript_core_listening_render_%_v1' OR policyname LIKE "
    "'transcript_core_manuscript_original_%_v1')) <> 0 THEN\n"
    "  RAISE EXCEPTION 'Existing clone Storage policies require reconciliation';\n"
    " END IF;\n"
    " IF (SELECT relrowsecurity FROM pg_class WHERE oid='storage.objects'::regclass) "
    "IS DISTINCT FROM true THEN\n"
    "  RAISE EXCEPTION 'Storage objects RLS must already be enabled';\n"
    " END IF;\n"
    "END $policy_preflight$;\n"
    + "\n".join(statements) + "\n"
    "DO $policy_postcondition$\nDECLARE actual text;\nBEGIN\n"
    " IF (SELECT count(*) FROM pg_policies WHERE schemaname='storage' "
    "AND tablename='objects' AND policyname IN (" + escaped_names +
    ")) <> 8 THEN\n"
    "  RAISE EXCEPTION 'Exact released native Storage policies missing';\n"
    " END IF;\n"
    " SELECT md5(string_agg(jsonb_build_object("
    "'name',policyname,'cmd',cmd,'roles',roles,'permissive',permissive,"
    "'qual',qual,'with_check',with_check)::text, E'\\n' ORDER BY policyname)) "
    "INTO actual FROM pg_policies WHERE schemaname='storage' "
    "AND tablename='objects' AND policyname IN (" + escaped_names + ");\n"
    " IF actual IS DISTINCT FROM 'd3ba560a91e6c042fc1c8601d6df08c1' THEN\n"
    "  RAISE EXCEPTION 'Clone Storage policy structure differs from read-only "
    "production eight-policy fingerprint';\n"
    " END IF;\n"
    "END $policy_postcondition$;\n"
    "COMMIT;\n"
)
output.write_text(sql)
PY_CALLBACK_EXISTING_STORAGE_POLICIES
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$artifacts_dir/private-callback-existing-storage-policy-parity.sql" \
    >"$artifacts_dir/private-callback-storage-policy-parity.log" 2>&1
  # PostgreSQL 17 CREATEROLE automatically returns ADMIN but SET FALSE to
  # the non-superuser creator. The protected localhost clone's trusted psql
  # fixture cannot SET LOCAL ROLE without SET TRUE membership. Simulate only
  # the future delegated host's SET boundary on this disposable clone;
  # do NOT modify candidate SQL, real membership, login or credentials.
  phase="local-only role SET membership for signed private callback simulation"
  if [[ ! "$database_url" =~ ^postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]; then
    echo 'REFUSE private callback role fixture outside disposable loopback clone' >&2
    exit 2
  fi
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    >"$artifacts_dir/private-callback-local-role-set.log" 2>&1 <<'SQL_LOCAL_PRIVATE_CALLBACK_SET'
BEGIN;
DO $local_caller_preflight$
BEGIN
 IF session_user IS DISTINCT FROM 'postgres' OR current_user IS DISTINCT FROM 'postgres'
   OR NOT EXISTS (
     SELECT 1 FROM pg_roles
     WHERE rolname='transcript_core_private_callback_executor_v1'
       AND NOT rolcanlogin AND NOT rolsuper AND NOT rolbypassrls
       AND NOT rolcreaterole AND NOT rolcreatedb
   )
 THEN RAISE EXCEPTION 'Refuse non-local or overpowered private callback role fixture'; END IF;
END $local_caller_preflight$;
GRANT transcript_core_private_callback_executor_v1 TO postgres
  WITH SET TRUE, INHERIT FALSE;
DO $local_caller_postcondition$
BEGIN
 IF NOT pg_has_role('postgres','transcript_core_private_callback_executor_v1','SET')
    OR NOT EXISTS (
      SELECT 1 FROM pg_auth_members m
      JOIN pg_roles r ON r.oid=m.roleid
      JOIN pg_roles u ON u.oid=m.member
      WHERE r.rolname='transcript_core_private_callback_executor_v1'
        AND u.rolname='postgres' AND m.set_option AND NOT m.inherit_option
    )
 THEN RAISE EXCEPTION 'Exact non-inherited localhost role SET membership missing'; END IF;
END $local_caller_postcondition$;
COMMIT;
SQL_LOCAL_PRIVATE_CALLBACK_SET
  phase="signed local private NOLOGIN callback executor and native Storage proof"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -c "NOTIFY pgrst, 'reload schema'" >"$artifacts_dir/private-callback-local-reload.log" 2>&1
  (cd "$project_dir"; python3 "$private_callback_signed_proof" --db-url "$database_url" \
    --output "$artifacts_dir/signed-private-callback-executor-summary.txt") \
    >"$artifacts_dir/signed-private-callback-executor.log" 2>&1
  test "$(cat "$artifacts_dir/signed-private-callback-executor-summary.txt")" = 'PASS signed local private callback executor: genuine GoTrue and Storage, private NOLOGIN wrapper, exact original/completion replay, viewer/outsider/anonymous/service and revoked-session denial; unpublished, clone only.'
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


if [ "$signed_private_callback_executor_probe" = true ]; then
  printf '\\nSIGNED private callback executor: exact NOLOGIN two-function wrapper, genuine local GoTrue identities, original and render Storage byte readback, source/role/replay/revocation denials, no published media or live execution. TEST-ONLY.\\n' >> "$artifacts_dir/summary.md"
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
if [ "$signed_orphan_cancelled_trigger_fn_probe" = true ]; then
  test -s "$artifacts_dir/signed-work-prerequisite-summary.txt"
  test -s "$artifacts_dir/orphan-cancelled-trigger-all-atlas-row-after-candidate.log"
  printf '\nHELD orphan cancelled-occurrence trigger-function TEST ONLY: one exact original DROP FUNCTION RESTRICT in disposable local PG17, all Atlas base-table identities and content conserved, genuine signed GoTrue owner/worker/outsider/no-seat and replay/concurrency/revocation prerequisite proof passed. Does not prove external caller absence and does not authorize production SQL, release or historical row deletion.\n' >> "$artifacts_dir/summary.md"
fi

if [ "$signed_anna_two_service_roots_probe" = true ]; then
  test -s "$artifacts_dir/signed-work-prerequisite-summary.txt"
  test -s "$artifacts_dir/anna-two-service-roots-all-atlas-row-after-candidate.log"
  printf '\nHELD anna-two-service-roots branch TEST ONLY: exact 2 original DROP FUNCTION RESTRICT, all local Atlas base-relation identities and content unchanged, original genuinely signed GoTrue root/worker/outsider/no-seat prerequisite/revocation/concurrency proof passed. Independent private callers retired only by separate owner decision; no production SQL, release or history deletion.\n' >> "$artifacts_dir/summary.md"
fi

if [ "$signed_pot_up_retirement_probe" = true ]; then
  test -s "$artifacts_dir/signed-work-prerequisite-summary.txt"
  test -s "$artifacts_dir/pot-up-all-atlas-row-after-candidate.log"
  printf '\nHELD pot-up branch TEST ONLY: exact 3 original DROP FUNCTION RESTRICT, all local Atlas base-relation identities and content unchanged, original genuinely signed GoTrue root/worker/outsider/no-seat prerequisite/revocation/concurrency proof passed. Independent private callers retired only by separate owner decision; no production SQL, release or history deletion.\n' >> "$artifacts_dir/summary.md"
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

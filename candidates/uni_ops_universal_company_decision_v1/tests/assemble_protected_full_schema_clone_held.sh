#!/usr/bin/env bash
# HELD test only. Invoke only inside owner-authorized full production-SCHEMA
# clone after a read-only schema/role restore. No production DB URL accepted.
# This is NOT a signed GoTrue test or a releasable migration.
set -Eeuo pipefail
usage(){
  echo 'Usage: bash assemble_protected_full_schema_clone_held.sh --local-db-url postgresql://postgres:postgres@127.0.0.1:54322/postgres --main-checkout DIR --p3-checkout DIR --universal-checkout DIR' >&2
  exit 2
}
url='' main='' p3='' univ=''
while (( $# )); do
  [[ $# -ge 2 ]] || usage
  case "$1" in
    --local-db-url) url="$2"; shift 2;;
    --main-checkout) main="$2"; shift 2;;
    --p3-checkout) p3="$2"; shift 2;;
    --universal-checkout) univ="$2"; shift 2;;
    *) usage;;
  esac
done
[[ "$url" == 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' ]] || usage
for tool in psql git realpath; do command -v "$tool" >/dev/null || usage; done
for dir in "$main" "$p3" "$univ"; do
  [[ -n "$dir" && -d "$dir/.git" ]] || usage
done
main="$(realpath "$main")"
p3="$(realpath "$p3")"
univ="$(realpath "$univ")"
[[ "$(git -C "$p3" rev-parse HEAD)" == 'd608391b3374d8113d869a6338dffab299be1b1e' ]] || {
  echo 'P3 held owner-attention source commit changed; re-review required' >&2; exit 3;
}
check_blob(){
  local file="$1" expected="$2" actual
  [[ -s "$file" ]] || { echo 'Missing exact source' >&2; exit 3; }
  actual="$(git hash-object --no-filters "$file")"
  [[ "$actual" == "$expected" ]] || {
    echo "Changed source $(basename "$file"), stop" >&2; exit 3;
  }
}
custody="$main/supabase/migrations/20261026010327_atlas_farm_crop_custody_and_work_growing_object_link_v1.sql"
f14="$p3/candidates/uni_ops_p3_no_auto_successor_v1/14_harvest_bucket_result_no_automatic_preparation_held.sql"
f15="$p3/candidates/uni_ops_p3_no_auto_successor_v1/15_seed_inventory_result_no_auto_shortfall_task_held.sql"
u="$univ/candidates/uni_ops_universal_company_decision_v1"
check_blob "$custody" '53610c2de7592813a54b31bd5b2055fad61a82a9'
check_blob "$f14" 'c9f46e5893fa09302608e46280c17b0ac6f7fe38'
check_blob "$f15" 'ebcc43f9c91e0dbd4b94cbef56831e4aa078df3f'
check_blob "$u/01_domain_neutral_source_and_decision_records_held.sql" '41b4dbe53ca71a6f816a99d3944da4ecb8ada443'
check_blob "$u/02_private_company_governor_decision_writer_held.sql" '54c5a4201ba07c753ee7714a520f05f569be366d'
check_blob "$u/03_private_current_governor_case_receipt_held.sql" 'efa708c308378acb40aeb427ad821478a34108f7'
check_blob "$u/06_bounded_existing_subject_disclosure_extension_held.sql" 'fbdb763e1366a2d6dc4b352f3d96f1b6e731350c'
check_blob "$u/04_verified_farm_source_to_company_case_adapter_held.sql" '9a7608ace7c805cd70a057dbec2285400012900f'
check_blob "$u/05_farm_to_one_company_governor_decision_wrapper_held.sql" '5be176df81402feef543c9616953ea71b250634f'
check_blob "$u/deferred_postconditions.sql" '427d195dd76c7fa58b1a5dce58e146778a56e1d9'

psql_local(){ psql "$url" -X -q -v ON_ERROR_STOP=1 "$@"; }
identity="$(psql_local -A -t -c "SELECT current_setting('server_version_num')::integer/10000||'|'||current_database()||'|'||inet_server_addr()::text" | tail -1)"
[[ "$identity" == '17|postgres|127.0.0.1' ]] || {
  echo 'Not disposable local PG17 clone; refusing SQL' >&2; exit 3;
}
preflight="$(psql_local -A -t -c "SELECT
to_regclass('atlas.farms') IS NOT NULL
AND to_regclass('atlas.journal_event_index') IS NOT NULL
AND to_regclass('atlas.subject_disclosure_decision_events_v1') IS NOT NULL
AND to_regclass('ledger.ledgers') IS NOT NULL
AND to_regclass('reality.entities') IS NOT NULL
AND to_regclass('atlas.farm_crop_ledger_custody_v1') IS NULL
AND to_regclass('atlas.uni_ops_governed_source_cases_v1') IS NULL
AND to_regclass('atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NULL" | tail -1)"
[[ "$preflight" == t ]] || {
  echo 'Protected production-shaped clone is not at expected uninstalled source state' >&2; exit 3;
}
echo 'PASS: exact source blob custody, local PG17, true uninstalled source preconditions.'
# P3 16/17 are EXCLUDED: 17 would introduce a second governing history.
# This helper loads source into disposable clone only, never production.
for source_file in "$custody" "$f14" "$f15" \
 "$u/01_domain_neutral_source_and_decision_records_held.sql" \
 "$u/02_private_company_governor_decision_writer_held.sql" \
 "$u/03_private_current_governor_case_receipt_held.sql" \
 "$u/06_bounded_existing_subject_disclosure_extension_held.sql" \
 "$u/04_verified_farm_source_to_company_case_adapter_held.sql" \
 "$u/05_farm_to_one_company_governor_decision_wrapper_held.sql" \
 "$u/deferred_postconditions.sql"; do
  echo "DISPOSABLE clone compile: $(basename "$source_file")"
  psql_local -f "$source_file"
done
psql_local -c "DO \$gate\$
BEGIN
 IF to_regclass('atlas.uni_ops_p3_owner_attention_decision_events_v1') IS NOT NULL
 OR to_regclass('atlas.uni_ops_governed_case_decision_events_v1') IS NULL
 OR to_regclass('atlas.uni_ops_farm_company_source_links_v1') IS NULL
 OR to_regclass('atlas.farm_crop_ledger_custody_v1') IS NULL
 THEN RAISE EXCEPTION 'One Company governor/source assembly not proven'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.uni_ops_governed_case_decision_events_v1)
 OR EXISTS(SELECT 1 FROM atlas.uni_ops_governed_source_cases_v1)
 THEN RAISE EXCEPTION 'Schema assembly fabricated a governing decision'; END IF;
 RAISE NOTICE 'PASS schema-only local assembly; no signed actor proof';
END;
\$gate\$;"
echo 'PASS: held source assembled on disposable full schema ONLY. Actual signed GoTrue/REST + worker/Principal authorization are NOT proved.'

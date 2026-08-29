#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"
recovery_registry="custody/post-fence-migration-recoveries-v4.json"

for required in \
  "schemas/OWNERSHIP.md" \
  "$baseline" \
  "$recovery_registry" \
  "custody/PRODUCTION_BASELINE.md" \
  "scripts/read-production-baseline.sql"; do
  if [ ! -f "$required" ]; then
    echo "Missing $required"
    exit 1
  fi
done

if [ ! -d "supabase/migrations" ]; then
  echo "Missing supabase/migrations"
  exit 1
fi

readarray -t baseline_values < <(python3 - <<'PY'
import json, re
from pathlib import Path

p = Path('custody/production-baseline-v1.json')
data = json.loads(p.read_text())

assert data['contractVersion'] == 1
assert data['physicalProject']['name'] == 'noel-core'
assert data['physicalProject']['projectRef'] == 'zirqkouammpwxlqfbsvf'
assert data['inheritedHistory']['authority'] == 'production-migration-ledger'
assert data['inheritedHistory']['migrationCount'] == 2022
assert data['inheritedHistory']['firstVersion'] == '20260702172540'
assert data['inheritedHistory']['throughVersion'] == '20260825203448'
assert data['inheritedHistory']['throughName'] == 'state_progression_sales_inventory_version_drift_adjudication_v1'
assert data['cutover']['effectiveAfterVersion'] == data['inheritedHistory']['throughVersion']
assert data['cutover']['newExecutableMigrationAuthority'] == 'optical-lift/noel-core-db'
assert data['cutover']['legacyHistoryDisposition'] == 'inherited_frozen'
assert data['cutover']['legacyFilesCopiedIntoThisRepository'] is False
assert data['cutover']['productRepositoriesMayOwnNewCanonicalMigrations'] is False
assert data['atlasAnchor']['repository'] == 'optical-lift/farm-atlas'
assert data['atlasAnchor']['governedArtifactCount'] == 4396
assert 'wnph' in data['schemaCensusAtCutover']['plannedProductSchemasAbsentAtCutover']
assert 'wnph_api' in data['schemaCensusAtCutover']['plannedProductSchemasAbsentAtCutover']

for key in ('throughBodyGitBlobSha1',):
    assert re.fullmatch(r'[0-9a-f]{40}', data['inheritedHistory'][key])
for key in ('throughBodySha256', 'ledgerSha256'):
    assert re.fullmatch(r'[0-9a-f]{64}', data['inheritedHistory'][key])

print(data['inheritedHistory']['throughVersion'])
print('|'.join(data['cutover']['requiredOwnerPrefixes']))
PY
)

fence_version="${baseline_values[0]}"
# The baseline list records owners known at cutover. Reporting Core was created
# post-cutover, so extend current ownership without rewriting the frozen baseline.
owner_prefixes="${baseline_values[1]}|reporting"

declare -A recovered_sha=()
while IFS='|' read -r filename sha; do
  recovered_sha["$filename"]="$sha"
done < <(python3 - <<'PY'
import json, re
from pathlib import Path

path = Path('custody/post-fence-migration-recoveries-v4.json')
data = json.loads(path.read_text())
assert data['contractVersion'] == 4
assert data['sealed'] is True
assert data['classification'] == 'retrospective_post_fence_custody_recovery'

expected = {
    '20260825223950_retire_rebuild_staging_and_backup_artifacts.sql': ('67494243146fef19ba6b95287b6c6098ce362347', 'core'),
    '20260825224131_drop_redundant_corpus_indexes.sql': ('22f480f99c3d7c72548805ff2ffc3a35b50fb7b5', 'core'),
    '20260825224151_retire_unconsumed_corpus_stage_tables.sql': ('9d6121325f867d52ebddb5d0ff650beb7b43a799', 'core'),
    '20260825224705_evict_rebuildable_dss_parsed_caches.sql': ('96ded2fd718d44b170069f65fc454b562c201241', 'core'),
    '20260825224836_evict_rebuildable_lxx_span_candidate_cache.sql': ('e9fbff6b1541d796e60cbcbe2f61e311f5dd6208', 'core'),
    '20260826224150_setup_known_growing_object_checklist_v1.sql': ('8b95b4c83d797022d2a358c0b1d33eb76ba2010f', 'atlas'),
    '20260826224303_revert_redundant_setup_unit_materializer_v1.sql': ('d79ae51cdbc0b0367b322ea547d17cf39d2b7676', 'atlas'),
    '20260827002345_phone_outreach_intelligence_bridge_v1.sql': ('159e4ef8595fd90f5bb52ec9d1a2a077faadf453', 'atlas'),
    '20260828202310_crop_lifecycle_continuity_contract_v1.sql': ('0b96be2db8fc5b8608699f9439eb55789aedb144', 'atlas'),
    '20260828202358_link_aug8_zinnia_cycles_to_generic_profile.sql': ('0107411357e8b9a75d725817fd5397643bdb63a1', 'atlas'),
    '20260828202642_refine_crop_lifecycle_continuity_evidence_v1.sql': ('c80d786e2a11c0ef50ef67d62116b4013f86bfa0', 'atlas'),
    '20260828203222_dependency_pressure_and_occurrence_lineage_v1.sql': ('e3e2bd989f495ffe52f12a1c301ea63cb2e09e31', 'atlas'),
    '20260828212857_production_stage_reservoir_contracts_v1.sql': ('bea5143112001b1b85d4b06ddcd19e2f5ae3d0fb', 'atlas'),
    '20260828212941_production_pot_up_to_hardening_reservoir_v1.sql': ('d9468dc65841b5dd38c73b278835c209054db2b4', 'atlas'),
    '20260828213016_production_hardening_to_readiness_reservoir_v1.sql': ('1755a3da02611f9b3fe43c3c98c8242d11937ae5', 'atlas'),
    '20260828222141_correct_overwinter_snapdragon_no_pot_up_v1.sql': ('00a3dc963c15c74d8c0d739415d721d83194cc54', 'atlas'),
    '20260828223114_production_stage_authorization_wrappers_v1.sql': ('bec68185f6315d4ba96bd22b172195f9de104200', 'atlas'),
    '20260828223648_production_readiness_preserves_truth_when_bed_math_unknown_v1.sql': ('16a6046d01c3c40bba8b06a3fc755726441e5567', 'atlas'),
    '20260828223728_production_readiness_resolves_tray_batch_from_restored_lineage_v1.sql': ('16b43d464d9ac649aff7f697883db3478aa02095', 'atlas'),
    '20260828224946_add_flower_buyer_position_layer_v1.sql': ('823ed6f503c563f9b0ecd673749cd7a604d5a024', 'atlas'),
    '20260828234710_production_work_authoring_membrane_v1.sql': ('e93cf6952108a4bff240345e37cf7a75c2581e29', 'atlas'),
    '20260828234749_production_readiness_uses_reservoir_v1.sql': ('ae5df0794a67858711335289f69bfd3f8e65e50e', 'atlas'),
    '20260828234814_production_transplant_gate_uses_reservoir_v1.sql': ('36c63f20df9bd24d7903e697575aeb3069c7c8af', 'atlas'),
    '20260828234859_production_transplant_authors_establishment_occurrence_v1.sql': ('bb5f4099003057495457b5c9fb77ac0869ae524e', 'atlas'),
    '20260828235013_production_establishment_uses_reservoir_v1.sql': ('a2dd860f42c71db948c4973985811d8e1e1111d9', 'atlas'),
    '20260828235110_production_harvest_gate_uses_reservoir_v1.sql': ('dc1cb6313d7f2ff4345afc6e0daeb61a4b24c08b', 'atlas'),
    '20260828235135_production_harvest_readiness_uses_reservoir_v1.sql': ('5253d85e6a66dce4e1671480406bed6345c60f7c', 'atlas'),
    '20260828235217_production_postharvest_gate_uses_reservoir_v1.sql': ('da1b2c314ad373e546d1f3303ecb32dc1646c68a', 'atlas'),
    '20260828235306_production_germination_uses_reservoir_v1.sql': ('233eba5b6008c219ac67efa8b24f2f059f088464', 'atlas'),
    '20260828235334_production_sowing_uses_reservoir_v1.sql': ('7bfb803f64830c9a358cd091dffcf54237017d05', 'atlas'),
    '20260828235425_production_next_propagation_operation_v1.sql': ('3ef8abf5aef6f92b2151a8ea4e63ce053dac567f', 'atlas'),
    '20260828235508_production_seedling_care_compiles_next_stage_v1.sql': ('b54af13dae92459ad9a2e6ad2de6305f0211dddc', 'atlas'),
    '20260828235645_production_clear_path_uses_lifecycle_contract_v1.sql': ('744d8a31c956b83013b8eff9f7f564a1acf60efb', 'atlas'),
    '20260828235702_production_clear_authors_turnover_occurrence_v1.sql': ('1198783a64762124ccdcbf9a6df5d58bc93f2059', 'atlas'),
    '20260828235735_production_care_policy_uses_reservoir_v1.sql': ('e33bb4bff2f527cfd52f7b513ca4e27062f7942f', 'atlas'),
    '20260828235819_snapdragon_bed_preparation_uses_reservoir_v1.sql': ('5da3f4a7c5b08e46b5a9dd6277573f85fc1c4117', 'atlas'),
    '20260828235906_production_pot_up_compiles_next_stage_v1.sql': ('b19ed30c17db5ec54d10a989f3c8083a20b7d378', 'atlas'),
}
recoveries = data['recoveries']
actual = {}
for row in recoveries:
    assert row['disposition'] == 'recovered_exact_live_bytes'
    assert row['reason'] == 'post_fence_live_migration_bypassed_source_custody'
    filename = row['filename']
    sha = row['gitBlobSha1']
    owner = row['logicalOwner']
    assert re.fullmatch(r'[0-9a-f]{40}', sha)
    assert owner in ('core', 'atlas')
    assert filename == f"{row['version']}_{row['name']}.sql"
    assert filename not in actual
    actual[filename] = (sha, owner)

assert actual == expected
for filename in sorted(actual):
    print(f"{filename}|{actual[filename][0]}")
PY
)

bad=0
while IFS= read -r file; do
  base="$(basename "$file")"
  if [[ "$base" == "README.md" ]]; then
    continue
  fi

  if [[ ! "$base" =~ ^([0-9]{14})_([a-z0-9]+)_ ]]; then
    echo "Migration filename is invalid: $file"
    bad=1
    continue
  fi

  version="${BASH_REMATCH[1]}"
  owner="${BASH_REMATCH[2]}"

  if [[ "$version" -le "$fence_version" ]]; then
    echo "Pre-fence migration history is inherited, not copied here: $file"
    bad=1
  fi

  if [[ "|$owner_prefixes|" != *"|$owner|"* ]]; then
    expected_sha="${recovered_sha[$base]:-}"
    if [[ -z "$expected_sha" ]]; then
      echo "Migration lacks an approved owner prefix: $file"
      bad=1
    else
      actual_sha="$(git hash-object "$file")"
      if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "Recovered migration bytes changed: $file; expected=$expected_sha actual=$actual_sha"
        bad=1
      fi
    fi
  fi
done < <(find supabase/migrations -maxdepth 1 -type f | sort)

if [ "$bad" -ne 0 ]; then
  exit 1
fi

echo "Database custody checks passed: inherited history fenced through $fence_version; new migrations belong to noel-core-db; 37 sealed retrospective recoveries preserve exact live bytes."

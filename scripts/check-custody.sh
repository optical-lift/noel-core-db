#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"
recovery_registry="custody/post-fence-migration-recoveries-v2.json"

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
owner_prefixes="${baseline_values[1]}"

declare -A recovered_sha=()
while IFS='|' read -r filename sha; do
  recovered_sha["$filename"]="$sha"
done < <(python3 - <<'PY'
import json, re
from pathlib import Path

path = Path('custody/post-fence-migration-recoveries-v2.json')
data = json.loads(path.read_text())
assert data['contractVersion'] == 2
assert data['sealed'] is True
assert data['classification'] == 'retrospective_post_fence_custody_recovery'

expected = {
    '20260825223950_retire_rebuild_staging_and_backup_artifacts.sql': ('67494243146fef19ba6b95287b6c6098ce362347', 'core'),
    '20260825224131_drop_redundant_corpus_indexes.sql': ('22f480f99c3d7c72548805ff2ffc3a35b50fb7b5', 'core'),
    '20260825224151_retire_unconsumed_corpus_stage_tables.sql': ('9d6121325f867d52ebddb5d0ff650beb7b43a799', 'core'),
    '20260825224705_evict_rebuildable_dss_parsed_caches.sql': ('96ded2fd718d44b170069f65fc454b562c201241', 'core'),
    '20260825224836_evict_rebuildable_lxx_span_candidate_cache.sql': ('e9fbff6b1541d796e60cbcbe2f61e311f5dd6208', 'core'),
    '20260827002345_phone_outreach_intelligence_bridge_v1.sql': ('ce558a225f3fed2845c445012ab763bbe444628c', 'atlas'),
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

echo "Database custody checks passed: inherited history fenced through $fence_version; new migrations belong to noel-core-db; six sealed retrospective recoveries preserve exact live bytes."

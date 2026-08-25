#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"

for required in \
  "schemas/OWNERSHIP.md" \
  "$baseline" \
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
    echo "Migration lacks an approved owner prefix: $file"
    bad=1
  fi
done < <(find supabase/migrations -maxdepth 1 -type f | sort)

if [ "$bad" -ne 0 ]; then
  exit 1
fi

echo "Database custody checks passed: inherited history fenced through $fence_version; new migrations belong to noel-core-db."

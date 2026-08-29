#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"
recovery_registry_v4="custody/post-fence-migration-recoveries-v4.json"
recovery_registry_v5="custody/post-fence-migration-recoveries-v5.json"
recovery_registry_v6="custody/post-fence-migration-recoveries-v6.json"
recovery_registry_v7="custody/post-fence-migration-recoveries-v7.json"
recovery_registry_v8="custody/post-fence-migration-recoveries-v8.json"
recovery_registry_v9="custody/post-fence-migration-recoveries-v9.json"

for required in \
  "schemas/OWNERSHIP.md" \
  "$baseline" \
  "$recovery_registry_v4" \
  "$recovery_registry_v5" \
  "$recovery_registry_v6" \
  "$recovery_registry_v7" \
  "$recovery_registry_v8" \
  "$recovery_registry_v9" \
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

# Recovery registries are sealed historical exceptions. Pin the registry blobs
# themselves so changing a recovery row requires an explicit new registry version.
declare -A sealed_registry_sha=(
  ["$recovery_registry_v4"]="846d0d72267db4b1d129cf257e60f0f8b1f3dc74"
  ["$recovery_registry_v5"]="09302e333c32223b37badad95506d61695100676"
  ["$recovery_registry_v6"]="8551ea9f754f4d2067f393bc1b6681751fc2976a"
  ["$recovery_registry_v7"]="b7a9a9dd9ec777978afac9a390f62007eb443b84"
  ["$recovery_registry_v8"]="a268cc00ebcc0cc6ecb2380d88217e2e0c7fc49f"
  ["$recovery_registry_v9"]="ad418e6d9b1bc2360168d5d0e669b8672f145b29"
)
for registry in "$recovery_registry_v4" "$recovery_registry_v5" "$recovery_registry_v6" "$recovery_registry_v7" "$recovery_registry_v8" "$recovery_registry_v9"; do
  actual_registry_sha="$(git hash-object "$registry")"
  if [[ "$actual_registry_sha" != "${sealed_registry_sha[$registry]}" ]]; then
    echo "Sealed recovery registry changed: $registry; expected=${sealed_registry_sha[$registry]} actual=$actual_registry_sha"
    exit 1
  fi
done

declare -A recovered_sha=()
while IFS='|' read -r filename sha; do
  recovered_sha["$filename"]="$sha"
done < <(python3 - <<'PY'
import json, re
from pathlib import Path

specs = [
    (Path('custody/post-fence-migration-recoveries-v4.json'), 4, None),
    (Path('custody/post-fence-migration-recoveries-v5.json'), 5, 'post-fence-migration-recoveries-v4.json'),
    (Path('custody/post-fence-migration-recoveries-v6.json'), 6, 'post-fence-migration-recoveries-v5.json'),
    (Path('custody/post-fence-migration-recoveries-v7.json'), 7, 'post-fence-migration-recoveries-v6.json'),
    (Path('custody/post-fence-migration-recoveries-v8.json'), 8, 'post-fence-migration-recoveries-v7.json'),
    (Path('custody/post-fence-migration-recoveries-v9.json'), 9, 'post-fence-migration-recoveries-v8.json'),
]

seen = {}
for path, contract_version, inherits in specs:
    data = json.loads(path.read_text())
    assert data['contractVersion'] == contract_version
    assert data['sealed'] is True
    assert data['classification'] == 'retrospective_post_fence_custody_recovery'
    if inherits is not None:
        assert data['inherits'] == inherits
    for row in data['recoveries']:
        assert row['disposition'] == 'recovered_exact_live_bytes'
        assert row['reason'] == 'post_fence_live_migration_bypassed_source_custody'
        filename = row['filename']
        sha = row['gitBlobSha1']
        owner = row['logicalOwner']
        assert re.fullmatch(r'[0-9a-f]{40}', sha)
        assert owner in ('core', 'atlas')
        assert filename == f"{row['version']}_{row['name']}.sql"
        assert filename not in seen
        seen[filename] = sha

assert len(seen) == 52
for filename in sorted(seen):
    print(f"{filename}|{seen[filename]}")
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

echo "Database custody checks passed: inherited history fenced through $fence_version; new migrations belong to noel-core-db; 52 sealed retrospective recoveries preserve exact live bytes."

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
# The baseline list records owners known at cutover. These namespaces were
# established post-cutover inside the same shared database authority. Extend
# current ownership without rewriting the frozen production baseline.
owner_prefixes="${baseline_values[1]}|reporting|local|canon|worker|composition"

# Recovery registries are sealed historical exceptions. Pin every governed
# registry blob so changing any historical evidence requires a new version.
declare -A sealed_registry_sha=(
  ["custody/post-fence-migration-recoveries-v4.json"]="846d0d72267db4b1d129cf257e60f0f8b1f3dc74"
  ["custody/post-fence-migration-recoveries-v5.json"]="09302e333c32223b37badad95506d61695100676"
  ["custody/post-fence-migration-recoveries-v6.json"]="8551ea9f754f4d2067f393bc1b6681751fc2976a"
  ["custody/post-fence-migration-recoveries-v7.json"]="b7a9a9dd9ec777978afac9a390f62007eb443b84"
  ["custody/post-fence-migration-recoveries-v8.json"]="a268cc00ebcc0cc6ecb2380d88217e2e0c7fc49f"
  ["custody/post-fence-migration-recoveries-v9.json"]="ad418e6d9b1bc2360168d5d0e669b8672f145b29"
  ["custody/post-fence-migration-recoveries-v10.json"]="d4dd75db5ecabf37302531de1beada39ee7286fc"
  ["custody/post-fence-migration-recoveries-v11.json"]="1223d87c0bc04ff0cadd58d728b5ca2ebdc91f21"
  ["custody/post-fence-migration-recoveries-v12.json"]="4b1073cc1716317587430b5397cef6c071413028"
  ["custody/post-fence-migration-recoveries-v13.json"]="c2b736c60890f2df965e9dce0a1fd4a4072f4cfa"
  ["custody/post-fence-migration-recoveries-v14.json"]="4dfadad688241cb2ba17b358715a9902e88099a5"
  ["custody/post-fence-migration-recoveries-v15.json"]="98bd248bec3f82d40a9d8273936a6b344584a010"
  ["custody/post-fence-migration-recoveries-v16.json"]="8481f5c492b7ebb86966ea69990ac0830ea6f4e5"
  ["custody/post-fence-migration-recoveries-v17.json"]="7973d0903dcd9dbab0ee00847f3eca4750a01f55"
  ["custody/post-fence-migration-recoveries-v18.json"]="fdd1d44c280056e5b551d964d37e453e8721ecbf"
  ["custody/post-fence-migration-recoveries-v19.json"]="4c5c17d6e62015073280de2f26e05e172e866562"
  ["custody/post-fence-migration-recoveries-v20.json"]="2f2ca02677a77a6cd168a2681dce5e970ea14fa6"
  ["custody/post-fence-migration-recoveries-v21.json"]="8b5ad6fb1a388f216250ac00338c7582a77113a4"
  ["custody/post-fence-migration-recoveries-v22.json"]="8755eea2448113b28e9c225e60012e6766c9c59a"
  ["custody/post-fence-migration-recoveries-v23.json"]="526c72f9d1ead5129f7f293498e03d82d3de33a7"
  ["custody/post-fence-migration-recoveries-v24.json"]="ce6a2d1112392518a18c99539029854dbe8aaeff"
  ["custody/post-fence-migration-recoveries-v25.json"]="e87a1caceabfb1be2a50a9857788af581a74e8a4"
  ["custody/post-fence-migration-recoveries-v26.json"]="9da84cde9a52c6d6cdd2ce52a6608a4a1bd6b75c"
  ["custody/post-fence-migration-recoveries-v27.json"]="ec5543fb29af3b20c55fdedd6806032abd18b01f"
  ["custody/post-fence-migration-recoveries-v28.json"]="eb8f3bec7d231caf457a4feb8f689d8a0f431e28"
  ["custody/post-fence-migration-recoveries-v29.json"]="75bee021ad08d2c348cc6f6f4edbe14e498288c6"
  ["custody/post-fence-migration-recoveries-v30.json"]="d5ff91a22aac39d6ab4c116ae4cab6350f850975"
  ["custody/post-fence-migration-recoveries-v31.json"]="ca7b04ee203881760e3352f0949f6be134b64c1e"
  ["custody/post-fence-migration-recoveries-v32.json"]="b017afff8024aa86fe42b7db92014ce90d13c651"
  ["custody/post-fence-migration-recoveries-v33.json"]="0ea0e49bca1cfab08d164eee1360b152d31b391a"
  ["custody/post-fence-migration-recoveries-v34.json"]="cb87f506cb22273d9c2f50d04d03890d40a93545"
)

for version in $(seq 4 34); do
  registry="custody/post-fence-migration-recoveries-v${version}.json"
  if [ ! -f "$registry" ]; then
    echo "Missing $registry"
    exit 1
  fi
  expected_registry_sha="${sealed_registry_sha[$registry]:-}"
  if [ -z "$expected_registry_sha" ]; then
    echo "Missing sealed SHA pin for $registry"
    exit 1
  fi
  actual_registry_sha="$(git hash-object "$registry")"
  if [[ "$actual_registry_sha" != "$expected_registry_sha" ]]; then
    echo "Sealed recovery registry changed: $registry; expected=$expected_registry_sha actual=$actual_registry_sha"
    exit 1
  fi
done

declare -A recovered_sha=()
while IFS='|' read -r filename sha; do
  recovered_sha["$filename"]="$sha"
done < <(python3 - <<'PY'
import json, re
from pathlib import Path

specs = []
for version in range(4, 35):
    path = Path(f'custody/post-fence-migration-recoveries-v{version}.json')
    inherits = None if version == 4 else f'post-fence-migration-recoveries-v{version - 1}.json'
    specs.append((path, version, inherits))

allowed_reasons = {
    'post_fence_live_migration_bypassed_source_custody',
    'post_release_repository_byte_drift',
    'post_fence_live_migration_bypassed_or_drifted_from_source_custody',
}

# v26 explicitly corrects two nonmatching blob guesses from v25. No other
# duplicate filename is allowed in the sealed chain.
corrections = {
    '20260911002240_atlas_implementation_artifact_interpretation_v1.sql': (
        'a7c89fbd1010a01281ec58bd2e6affa31f7b5768',
        'a473f8d120fd989fdd808020f4df500063da6920',
    ),
    '20260911002857_atlas_implementation_artifact_ready_state_v1.sql': (
        'c71f6606659fd1ef73f65ae636ddfa2ec08f3a84',
        '9f0446fd738a827081afe715844e72f7368ae34a',
    ),
}

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
        assert row['reason'] in allowed_reasons
        filename = row['filename']
        sha = row['gitBlobSha1']
        owner = row['logicalOwner']
        assert re.fullmatch(r'[0-9a-f]{40}', sha)
        assert owner in ('core', 'atlas')
        assert filename == f"{row['version']}_{row['name']}.sql"
        if filename in seen:
            expected = corrections.get(filename)
            actual = (seen[filename], sha)
            assert contract_version == 26 and expected == actual, (
                f'unapproved duplicate/correction for {filename}: {actual!r}'
            )
        seen[filename] = sha

assert len(seen) == 203
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

echo "Database custody checks passed: inherited history fenced through $fence_version; new migrations belong to noel-core-db; 203 sealed retrospective recovery identities preserve exact live bytes."

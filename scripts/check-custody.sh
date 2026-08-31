#!/usr/bin/env bash
set -euo pipefail

historical_baseline="custody/production-baseline-v1.json"
canonical_baseline="custody/canonical-source-baseline-v2.json"

recovery_registries=(
  "custody/post-fence-migration-recoveries-v4.json"
  "custody/post-fence-migration-recoveries-v5.json"
  "custody/post-fence-migration-recoveries-v6.json"
  "custody/post-fence-migration-recoveries-v7.json"
  "custody/post-fence-migration-recoveries-v8.json"
  "custody/post-fence-migration-recoveries-v9.json"
  "custody/post-fence-migration-recoveries-v10.json"
  "custody/post-fence-migration-recoveries-v11.json"
  "custody/post-fence-migration-recoveries-v12.json"
  "custody/post-fence-migration-recoveries-v13.json"
  "custody/post-fence-migration-recoveries-v14.json"
  "custody/post-fence-migration-recoveries-v15.json"
  "custody/post-fence-migration-recoveries-v16.json"
)

for required in \
  "schemas/OWNERSHIP.md" \
  "$historical_baseline" \
  "$canonical_baseline" \
  "custody/PRODUCTION_BASELINE.md" \
  "scripts/read-production-baseline.sql"; do
  if [ ! -f "$required" ]; then
    echo "Missing $required"
    exit 1
  fi
done

for registry in "${recovery_registries[@]}"; do
  if [ ! -f "$registry" ]; then
    echo "Missing sealed historical recovery registry: $registry"
    exit 1
  fi
done

if [ ! -d "supabase/migrations" ]; then
  echo "Missing supabase/migrations"
  exit 1
fi

# The original production baseline remains immutable historical authority. It
# fences inherited pre-repository history; this v2 convergence does not rewrite it.
python3 - <<'PY'
import json, re
from pathlib import Path

data = json.loads(Path('custody/production-baseline-v1.json').read_text())
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
for key in ('throughBodyGitBlobSha1',):
    assert re.fullmatch(r'[0-9a-f]{40}', data['inheritedHistory'][key])
for key in ('throughBodySha256', 'ledgerSha256'):
    assert re.fullmatch(r'[0-9a-f]{64}', data['inheritedHistory'][key])
PY

# Retrospective recovery registries are now historical artifacts only. Keep
# their exact bytes sealed, but never extend this exception mechanism again.
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
)
for registry in "${recovery_registries[@]}"; do
  actual_registry_sha="$(git hash-object "$registry")"
  if [[ "$actual_registry_sha" != "${sealed_registry_sha[$registry]}" ]]; then
    echo "Sealed historical recovery registry changed: $registry; expected=${sealed_registry_sha[$registry]} actual=$actual_registry_sha"
    exit 1
  fi
done

# Pin the v2 baseline artifact itself. A future baseline requires an explicit
# checker revision; it cannot be silently edited in place.
expected_canonical_baseline_blob="114794c702f5c77ec9355800b7732d61156adab2"
actual_canonical_baseline_blob="$(git hash-object "$canonical_baseline")"
if [[ "$actual_canonical_baseline_blob" != "$expected_canonical_baseline_blob" ]]; then
  echo "Canonical source baseline v2 changed; expected=$expected_canonical_baseline_blob actual=$actual_canonical_baseline_blob"
  exit 1
fi

python3 - <<'PY'
import hashlib
import json
import re
from pathlib import Path

historical = json.loads(Path('custody/production-baseline-v1.json').read_text())
canonical = json.loads(Path('custody/canonical-source-baseline-v2.json').read_text())

assert canonical['contractVersion'] == 2
assert canonical['classification'] == 'canonical_source_baseline'
assert canonical['sealed'] is True
assert canonical['physicalProject']['name'] == 'noel-core'
assert canonical['physicalProject']['projectRef'] == 'zirqkouammpwxlqfbsvf'
assert canonical['repositoryAuthority'] == 'optical-lift/noel-core-db'
assert canonical['inheritedHistoryFence'] == historical['inheritedHistory']['throughVersion']
assert canonical['canonicalSource']['firstVersion'] == '20260825212415'
assert canonical['canonicalSource']['throughVersion'] == '20260830220912'
assert canonical['canonicalSource']['postFenceMigrationCount'] == 310
assert canonical['canonicalSource']['manifestSha256'] == 'e743ee43f54dde1a397d4dea9426d346fbf75860ff46de0abd7529bc3aecee5a'
assert canonical['forwardPolicy']['authority'] == 'git_first'
assert canonical['forwardPolicy']['canonicalRepository'] == 'optical-lift/noel-core-db'
assert canonical['forwardPolicy']['productionMayNotLeadCanonicalGit'] is True
assert canonical['forwardPolicy']['newMigrationFilesMayExistInGitBeforeProduction'] is True
assert canonical['forwardPolicy']['retrospectiveRecoveryRegistriesAreHistoricalOnly'] is True

fence = canonical['inheritedHistoryFence']
through = canonical['canonicalSource']['throughVersion']
expected_count = canonical['canonicalSource']['postFenceMigrationCount']
expected_manifest = canonical['canonicalSource']['manifestSha256']

name_re = re.compile(r'^(\d{14})_([a-z0-9][a-z0-9_]*)\.sql$')
rows = []
forward = []
seen_versions = set()

for path in sorted(Path('supabase/migrations').glob('*.sql')):
    match = name_re.fullmatch(path.name)
    if not match:
        raise SystemExit(f'Migration filename is invalid: {path}')
    version, name = match.groups()
    if version in seen_versions:
        raise SystemExit(f'Duplicate migration version in canonical repository: {version}')
    seen_versions.add(version)
    if version <= fence:
        raise SystemExit(f'Pre-fence migration history is inherited, not copied here: {path}')

    raw = path.read_bytes()
    header = f'blob {len(raw)}\0'.encode('utf-8')
    blob_sha = hashlib.sha1(header + raw).hexdigest()

    if version <= through:
        rows.append((version, name, blob_sha))
    else:
        forward.append((version, name, blob_sha))

rows.sort(key=lambda row: row[0])
if len(rows) != expected_count:
    raise SystemExit(f'Canonical v2 migration count mismatch: expected={expected_count} actual={len(rows)}')
if not rows or rows[0][0] != canonical['canonicalSource']['firstVersion'] or rows[-1][0] != through:
    raise SystemExit('Canonical v2 migration version bounds do not match the sealed baseline')

body = '\n'.join('|'.join(row) for row in rows).encode('utf-8')
manifest = hashlib.sha256(body).hexdigest()
if manifest != expected_manifest:
    raise SystemExit(f'Canonical v2 migration manifest mismatch: expected={expected_manifest} actual={manifest}')

# Forward files are intentionally allowed before production sees them. That is
# the Git-first direction of travel; the live-production check separately
# guarantees production can never contain a migration absent from this tree.
print(f'Database custody static checks passed: canonical v2 seals {len(rows)} exact migrations through {through}; forward Git-first migrations={len(forward)}.')
PY

#!/usr/bin/env bash
set -euo pipefail

lane="${1:-}"
baseline="custody/production-baseline-v1.json"
manifest="custody/release-lanes-v1.json"
api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"

if [[ "$lane" != "atlas" && "$lane" != "wnph" && "$lane" != "shared" ]]; then
  echo "Usage: $0 <atlas|wnph|shared>" >&2
  exit 2
fi
if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required." >&2
  exit 2
fi

packet="$({
  curl --fail --silent --show-error \
    --request POST \
    --header "apikey: $publishable_key" \
    --header "Authorization: Bearer $publishable_key" \
    --header "Content-Type: application/json" \
    --data '{}' \
    "$api_url/rest/v1/rpc/shared_db_custody_release_packet_v1"
} | tr -d '\r')"

PACKET_JSON="$packet" python3 - "$lane" "$baseline" "$manifest" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

lane, baseline_path, manifest_path = sys.argv[1:]
baseline = json.loads(Path(baseline_path).read_text())
manifest = json.loads(Path(manifest_path).read_text())
packet = json.loads(os.environ['PACKET_JSON'])

expected = baseline['inheritedHistory']
fence = packet.get('fence') or {}
current = packet.get('current') or {}
post_fence = packet.get('postFence') or []
lanes = manifest['lanes']
errors = []
ignored = []

if manifest.get('contractVersion') != 1:
    errors.append(f"Unexpected release-lane contract version: {manifest.get('contractVersion')!r}")
if packet.get('contractVersion') != 1:
    errors.append(f"Unexpected live custody contract version: {packet.get('contractVersion')!r}")
if packet.get('projectRef') != baseline['physicalProject']['projectRef']:
    errors.append(f"Live custody packet project mismatch: {packet.get('projectRef')!r}")

for key, value in {
    'migrationCount': expected['migrationCount'],
    'firstVersion': expected['firstVersion'],
    'throughVersion': expected['throughVersion'],
    'ledgerSha256': expected['ledgerSha256'],
}.items():
    if fence.get(key) != value:
        errors.append(f"Inherited fence mismatch for {key}: expected {value!r}, live {fence.get(key)!r}")

prefix_to_lane = {cfg['migrationPrefix']: key for key, cfg in lanes.items()}
def classify(name: str) -> str:
    for prefix, owner_lane in prefix_to_lane.items():
        if name.startswith(prefix):
            return owner_lane
    return 'unclassified'

versions = []
for row in post_fence:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    production_blob = str(row.get('gitBlobSha1') or '')
    versions.append(version)
    owner_lane = classify(name)

    path = Path('supabase/migrations') / f'{version}_{name}.sql'
    repository_blob = None
    if path.is_file():
        repository_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()

    exact = path.is_file() and repository_blob == production_blob
    if exact:
        continue

    foreign = owner_lane not in (lane, 'unclassified', 'shared')
    if lane != 'shared' and foreign:
        ignored.append(f'{version}_{name} ({owner_lane})')
        continue

    if not path.is_file():
        errors.append(
            f"{lane} release lane blocked by uncustodied {owner_lane} live migration: "
            f"{version}_{name}; expected {path}"
        )
    else:
        errors.append(
            f"{lane} release lane blocked by byte drift in {owner_lane} live migration: {path}; "
            f"repository={repository_blob} production={production_blob}"
        )

if versions != sorted(versions) or len(versions) != len(set(versions)):
    errors.append('Live post-fence migration versions are not strictly ordered and unique.')

expected_current_count = expected['migrationCount'] + len(post_fence)
if current.get('migrationCount') != expected_current_count:
    errors.append(
        'Current migration count is inconsistent with the frozen prefix plus post-fence rows: '
        f"expected {expected_current_count}, live {current.get('migrationCount')!r}"
    )
expected_latest = versions[-1] if versions else expected['throughVersion']
if current.get('latestVersion') != expected_latest:
    errors.append(
        'Current latest migration is inconsistent with the post-fence ledger: '
        f"expected {expected_latest!r}, live {current.get('latestVersion')!r}"
    )

if errors:
    print(f'Live production {lane} release-lane custody FAILED:')
    for error in errors:
        print(f'- {error}')
    if ignored:
        print(f'- {len(ignored)} foreign-lane custody deviation(s) were intentionally outside this release decision.')
    raise SystemExit(1)

print(
    f'Live production {lane} release-lane custody passed. '
    f'{len(ignored)} foreign-lane custody deviation(s) are visible to the global auditor but do not block this lane.'
)
PY

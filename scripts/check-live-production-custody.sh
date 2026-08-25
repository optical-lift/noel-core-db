#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"
api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required for live production custody verification."
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

PACKET_JSON="$packet" python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path

baseline = json.loads(Path('custody/production-baseline-v1.json').read_text())
packet = json.loads(os.environ['PACKET_JSON'])

expected = baseline['inheritedHistory']
fence = packet.get('fence') or {}
current = packet.get('current') or {}
post_fence = packet.get('postFence') or []

errors = []

if packet.get('contractVersion') != 1:
    errors.append(f"Unexpected live custody contract version: {packet.get('contractVersion')!r}")
if packet.get('projectRef') != baseline['physicalProject']['projectRef']:
    errors.append(f"Live custody packet project mismatch: {packet.get('projectRef')!r}")

checks = {
    'migrationCount': expected['migrationCount'],
    'firstVersion': expected['firstVersion'],
    'throughVersion': expected['throughVersion'],
    'ledgerSha256': expected['ledgerSha256'],
}
for key, value in checks.items():
    if fence.get(key) != value:
        errors.append(f"Inherited fence mismatch for {key}: expected {value!r}, live {fence.get(key)!r}")

versions = []
for row in post_fence:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    production_blob = str(row.get('gitBlobSha1') or '')
    versions.append(version)

    path = Path('supabase/migrations') / f'{version}_{name}.sql'
    if not path.is_file():
        errors.append(f"Unauthorized or uncustodied live post-fence migration: {version}_{name}; expected {path}")
        continue

    repository_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
    if repository_blob != production_blob:
        errors.append(
            f"Live post-fence migration bytes do not match canonical source: {path}; "
            f"repository={repository_blob} production={production_blob}"
        )

if versions != sorted(versions) or len(versions) != len(set(versions)):
    errors.append('Live post-fence migration versions are not strictly ordered and unique.')

expected_current_count = expected['migrationCount'] + len(post_fence)
if current.get('migrationCount') != expected_current_count:
    errors.append(
        f"Current migration count is inconsistent with the frozen prefix plus post-fence rows: "
        f"expected {expected_current_count}, live {current.get('migrationCount')!r}"
    )

expected_latest = versions[-1] if versions else expected['throughVersion']
if current.get('latestVersion') != expected_latest:
    errors.append(
        f"Current latest migration is inconsistent with the post-fence ledger: "
        f"expected {expected_latest!r}, live {current.get('latestVersion')!r}"
    )

if errors:
    print('Live production migration custody FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print(
    'Live production custody passed: inherited fence is unchanged and '
    f'{len(post_fence)} post-fence migration(s) have exact canonical source in noel-core-db.'
)
PY

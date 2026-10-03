#!/usr/bin/env bash
set -euo pipefail

baseline="custody/production-baseline-v1.json"
reconciliation="custody/executed-statement-body-reconciliations-v1.json"
reconciliation_sha="12962a43cd510f7015ff46c7f3364192229dba2c"
api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required for live production custody verification."
  exit 2
fi

if [ ! -f "$reconciliation" ]; then
  echo "Missing sealed executed-statement reconciliation receipt: $reconciliation"
  exit 1
fi
if [ "$(git hash-object "$reconciliation")" != "$reconciliation_sha" ]; then
  echo "Executed-statement reconciliation receipt changed; expected sealed blob $reconciliation_sha"
  exit 1
fi

packet_file="$(mktemp)"
trap 'rm -f "$packet_file"' EXIT

curl --fail --silent --show-error \
  --request POST \
  --header "apikey: $publishable_key" \
  --header "Authorization: Bearer $publishable_key" \
  --header "Content-Type: application/json" \
  --data '{}' \
  "$api_url/rest/v1/rpc/shared_db_custody_release_packet_v1" \
  | tr -d '\r' > "$packet_file"

python3 - "$packet_file" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

packet_path = Path(sys.argv[1])
baseline = json.loads(Path('custody/production-baseline-v1.json').read_text())
receipt = json.loads(Path('custody/executed-statement-body-reconciliations-v1.json').read_text())
try:
    packet = json.loads(packet_path.read_text())
except Exception as exc:
    print(f'Live production migration custody FAILED: invalid custody packet: {exc}')
    raise SystemExit(1)

errors = []
if receipt.get('contractVersion') != 1 or receipt.get('sealed') is not True:
    errors.append('Executed-statement reconciliation receipt contract/seal is invalid.')
if receipt.get('classification') != 'supabase_executed_statement_body_reconciliation':
    errors.append('Executed-statement reconciliation receipt classification is invalid.')

reconciliations = {}
for row in receipt.get('rows') or []:
    filename = str(row.get('filename') or '')
    source_blob = str(row.get('canonicalSourceGitBlobSha1') or '')
    executed_blob = str(row.get('executedBodyGitBlobSha1') or '')
    if not filename.endswith('.sql') or not re.fullmatch(r'[0-9a-f]{40}', source_blob) or not re.fullmatch(r'[0-9a-f]{40}', executed_blob):
        errors.append(f'Invalid executed-statement reconciliation row: {row!r}')
        continue
    if filename in reconciliations:
        errors.append(f'Duplicate executed-statement reconciliation filename: {filename}')
        continue
    reconciliations[filename] = (source_blob, executed_blob)
if len(reconciliations) != 58:
    errors.append(f'Expected 58 sealed executed-statement reconciliation rows, found {len(reconciliations)}.')

expected = baseline['inheritedHistory']
fence = packet.get('fence') or {}
current = packet.get('current') or {}
post_fence = packet.get('postFence') or []

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
direct_exact = 0
statement_reconciled = 0
for row in post_fence:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    executed_body_blob = str(row.get('gitBlobSha1') or '')
    versions.append(version)

    filename = f'{version}_{name}.sql'
    path = Path('supabase/migrations') / filename
    if not path.is_file():
        errors.append(f"Unauthorized or uncustodied live post-fence migration: {version}_{name}; expected {path}")
        continue

    repository_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
    if repository_blob == executed_body_blob:
        direct_exact += 1
        continue

    receipt_pair = reconciliations.get(filename)
    if receipt_pair == (repository_blob, executed_body_blob):
        statement_reconciled += 1
        continue

    if receipt_pair is None:
        errors.append(
            f"Live executed-statement body differs from canonical source without a sealed reconciliation: {path}; "
            f"canonicalSource={repository_blob} executedBody={executed_body_blob}"
        )
    else:
        errors.append(
            f"Live/canonical hash pair changed from sealed reconciliation: {path}; "
            f"canonicalSource={repository_blob} executedBody={executed_body_blob} "
            f"sealedCanonicalSource={receipt_pair[0]} sealedExecutedBody={receipt_pair[1]}"
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
    f'{len(post_fence)} post-fence migration(s) are source-custodied in noel-core-db '
    f'({direct_exact} direct executed-body/source byte matches; '
    f'{statement_reconciled} sealed executed-statement/source reconciliations).'
)
PY

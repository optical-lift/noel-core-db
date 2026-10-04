#!/usr/bin/env bash
set -euo pipefail

api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required." >&2
  exit 2
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

ROOT = Path('.')
packet_path = Path(sys.argv[1])
policy_path = ROOT / 'custody/live-custody-reconciliation-policy-v1.json'
baseline_path = ROOT / 'custody/production-baseline-v1.json'
sha1_re = re.compile(r'^[0-9a-f]{40}$')
errors = []

foundation = {
    '20261003211522_titus_formation_kernel_v1.sql': 'b710263a0cb124037441a9655a2f31455c3cb9d9',
    '20261003212733_titus_formation_access_membrane_v1.sql': 'affc850e1a7d8d2c2750df151ae5845aea798dfd',
}
expected_live_foundation = {
    '20261003211522_titus_formation_kernel_v1.sql': 'a8ca9752d6350324ffb21a09caf8b664b04515ec',
    '20261003212733_titus_formation_access_membrane_v1.sql': '5fda1a5f39a33c4cfbbb6d3f9c75405db2b7ea72',
}
required_files = [
    'architecture/TITUS_FORMATION_CUSTODY_V1.md',
    'architecture/TITUS_FORMATION_ACCESS_MEMBRANE_V1.md',
    'schemas/OWNERSHIP.md',
]


def git_blob(path: Path) -> str:
    return subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()

for filename, expected in foundation.items():
    path = ROOT / 'supabase/migrations' / filename
    if not path.is_file():
        errors.append(f'Missing immutable Titus foundation migration: {path}')
        continue
    actual = git_blob(path)
    if actual != expected:
        errors.append(f'Titus foundation migration changed: {path}; expected {expected}, actual {actual}')

for rel in required_files:
    if not (ROOT / rel).is_file():
        errors.append(f'Missing Titus custody/ownership artifact: {rel}')

ownership = (ROOT / 'schemas/OWNERSHIP.md').read_text() if (ROOT / 'schemas/OWNERSHIP.md').is_file() else ''
for fragment in (
    '| `titus` | Titus |',
    'one post-fence executable migration authority: this repository',
    'The Titus application repository does not become a competing migration authority',
):
    if fragment not in ownership:
        errors.append(f'Titus ownership contract missing required language: {fragment}')

policy = json.loads(policy_path.read_text())
baseline = json.loads(baseline_path.read_text())
receipt_cfg = policy.get('executedStatementReconciliation') or {}
receipt_cfgs = [{
    'path': receipt_cfg.get('path'),
    'sealedGitBlobSha1': receipt_cfg.get('sealedGitBlobSha1'),
    'expectedRowCount': receipt_cfg.get('expectedRowCount'),
}] + list(receipt_cfg.get('supplements') or [])

pairs = {}
for cfg in receipt_cfgs:
    rel = str(cfg.get('path') or '')
    path = ROOT / rel
    if not path.is_file():
        errors.append(f'Missing sealed executed-statement receipt: {rel}')
        continue
    actual_receipt_blob = git_blob(path)
    expected_receipt_blob = str(cfg.get('sealedGitBlobSha1') or '')
    if actual_receipt_blob != expected_receipt_blob:
        errors.append(f'Executed-statement receipt changed: {rel}; expected {expected_receipt_blob}, actual {actual_receipt_blob}')
        continue
    doc = json.loads(path.read_text())
    if doc.get('sealed') is not True or doc.get('classification') != 'supabase_executed_statement_body_reconciliation':
        errors.append(f'Invalid executed-statement receipt contract: {rel}')
        continue
    rows = doc.get('rows') or []
    if len(rows) != int(cfg.get('expectedRowCount') or 0):
        errors.append(f'Executed-statement receipt row-count mismatch: {rel}')
    for row in rows:
        filename = str(row.get('filename') or '')
        pair = (
            str(row.get('canonicalSourceGitBlobSha1') or ''),
            str(row.get('executedBodyGitBlobSha1') or ''),
        )
        if not filename.endswith('.sql') or not all(sha1_re.fullmatch(value) for value in pair):
            errors.append(f'Malformed executed-statement reconciliation row in {rel}: {row!r}')
            continue
        if filename in pairs:
            errors.append(f'Duplicate executed-statement reconciliation row across receipts: {filename}')
            continue
        pairs[filename] = pair

try:
    packet = json.loads(packet_path.read_text())
except Exception as exc:
    errors.append(f'Invalid live custody packet: {exc}')
    packet = {}

if packet.get('projectRef') != baseline['physicalProject']['projectRef']:
    errors.append(f"Live project mismatch: expected {baseline['physicalProject']['projectRef']}, got {packet.get('projectRef')!r}")

post_fence = packet.get('postFence') or []
seen_foundation = set()
titus_rows = 0
reconciled_rows = 0
exact_rows = 0
for row in post_fence:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    if not name.startswith('titus_'):
        continue
    titus_rows += 1
    filename = f'{version}_{name}.sql'
    production_blob = str(row.get('gitBlobSha1') or '')
    path = ROOT / 'supabase/migrations' / filename
    if filename in foundation:
        seen_foundation.add(filename)
        expected_live = expected_live_foundation[filename]
        if production_blob != expected_live:
            errors.append(f'Titus foundation live execution history changed unexpectedly: {filename}; expected {expected_live}, live {production_blob}')
    if not path.is_file():
        errors.append(f'Uncustodied live Titus migration: {filename}; production={production_blob}')
        continue
    source_blob = git_blob(path)
    if source_blob == production_blob:
        exact_rows += 1
        continue
    if pairs.get(filename) == (source_blob, production_blob):
        reconciled_rows += 1
        continue
    errors.append(
        f'Unreconciled Titus source/execution drift: {filename}; source={source_blob}; production={production_blob}'
    )

missing_foundation = set(foundation) - seen_foundation
for filename in sorted(missing_foundation):
    errors.append(f'Expected live Titus foundation row is absent from production ledger: {filename}')

if errors:
    print('Titus Formation custody FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print(
    'Titus Formation custody passed: '
    f'{titus_rows} live Titus migration(s), {exact_rows} exact, {reconciled_rows} explicitly reconciled; '
    'foundation hashes immutable and single migration authority intact.'
)
PY

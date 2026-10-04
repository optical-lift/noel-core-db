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

python3 - "$lane" "$baseline" "$manifest" "$packet_file" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

lane, baseline_path, manifest_path, packet_path = sys.argv[1:]
baseline = json.loads(Path(baseline_path).read_text())
manifest = json.loads(Path(manifest_path).read_text())
try:
    packet = json.loads(Path(packet_path).read_text())
except Exception as exc:
    print(f'Live production {lane} release-lane custody FAILED: invalid custody packet: {exc}')
    raise SystemExit(1)

expected = baseline['inheritedHistory']
fence = packet.get('fence') or {}
current = packet.get('current') or {}
post_fence = packet.get('postFence') or []
lanes = manifest['lanes']
errors = []
ignored = []
sha1_re = re.compile(r'^[0-9a-f]{40}$')


def git_blob(path: Path) -> str:
    return subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()


# Historical post-fence migrations may have been recovered after they reached production.
# A sealed recovery registry is evidence of the exact live Git blob identity. It does not
# authorize future migrations, prefixes, or byte drift; it only keeps known historical debt
# from permanently blocking an otherwise clean product release lane.
recovered = set()
for recovery_path in sorted(Path('custody').glob('post-fence-migration-recoveries-v*.json')):
    try:
        recovery_doc = json.loads(recovery_path.read_text())
    except Exception as exc:
        errors.append(f"Invalid custody recovery registry {recovery_path}: {exc}")
        continue
    if recovery_doc.get('sealed') is not True:
        errors.append(f"Custody recovery registry is not sealed: {recovery_path}")
        continue
    for entry in recovery_doc.get('recoveries') or []:
        version = str(entry.get('version') or '')
        name = str(entry.get('name') or '')
        blob = str(entry.get('gitBlobSha1') or '')
        filename = str(entry.get('filename') or '')
        if not version or not name or not blob or filename != f'{version}_{name}.sql':
            errors.append(f"Malformed custody recovery entry in {recovery_path}: {entry!r}")
            continue
        recovered.add((version, name, blob))

# Canonical source and live execution history are allowed to differ only through the same
# sealed two-hash receipts used by the authoritative global live-custody reconciler.
statement_pairs = {}
policy_path = Path('custody/live-custody-reconciliation-policy-v1.json')
try:
    policy = json.loads(policy_path.read_text())
except Exception as exc:
    errors.append(f"Invalid live custody reconciliation policy {policy_path}: {exc}")
    policy = {}

if policy and (policy.get('contractVersion') != 1 or policy.get('sealed') is not True):
    errors.append(f"Unexpected live custody reconciliation policy contract: {policy_path}")

statement_cfg = policy.get('executedStatementReconciliation') or {}
receipt_specs = []
if statement_cfg:
    receipt_specs.append((
        Path(str(statement_cfg.get('path') or '')),
        str(statement_cfg.get('sealedGitBlobSha1') or ''),
        int(statement_cfg.get('expectedRowCount') or 0),
    ))
    for supplement in statement_cfg.get('supplements') or []:
        receipt_specs.append((
            Path(str(supplement.get('path') or '')),
            str(supplement.get('sealedGitBlobSha1') or ''),
            int(supplement.get('expectedRowCount') or 0),
        ))

for receipt_path, expected_receipt_sha, expected_count in receipt_specs:
    if not str(receipt_path) or not receipt_path.is_file():
        errors.append(f"Missing executed-statement reconciliation receipt: {receipt_path}")
        continue
    if not sha1_re.fullmatch(expected_receipt_sha):
        errors.append(f"Invalid sealed receipt SHA in live custody policy for {receipt_path}: {expected_receipt_sha!r}")
        continue
    actual_receipt_sha = git_blob(receipt_path)
    if actual_receipt_sha != expected_receipt_sha:
        errors.append(
            f"Executed-statement reconciliation receipt changed: {receipt_path}; "
            f"expected={expected_receipt_sha} actual={actual_receipt_sha}"
        )
        continue
    try:
        receipt = json.loads(receipt_path.read_text())
    except Exception as exc:
        errors.append(f"Invalid executed-statement reconciliation receipt {receipt_path}: {exc}")
        continue
    if receipt.get('sealed') is not True or receipt.get('classification') != 'supabase_executed_statement_body_reconciliation':
        errors.append(f"Unexpected executed-statement reconciliation contract: {receipt_path}")
        continue
    rows = receipt.get('rows') or []
    if len(rows) != expected_count:
        errors.append(
            f"Executed-statement reconciliation row count changed: {receipt_path}; "
            f"expected={expected_count} actual={len(rows)}"
        )
        continue
    for entry in rows:
        filename = str(entry.get('filename') or '')
        source_blob = str(entry.get('canonicalSourceGitBlobSha1') or '')
        executed_blob = str(entry.get('executedBodyGitBlobSha1') or '')
        if not filename.endswith('.sql') or not sha1_re.fullmatch(source_blob) or not sha1_re.fullmatch(executed_blob):
            errors.append(f"Malformed executed-statement reconciliation entry in {receipt_path}: {entry!r}")
            continue
        if filename in statement_pairs:
            errors.append(f"Duplicate executed-statement reconciliation entry for {filename}")
            continue
        statement_pairs[filename] = (source_blob, executed_blob)

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

    filename = f'{version}_{name}.sql'
    path = Path('supabase/migrations') / filename
    repository_blob = None
    if path.is_file():
        repository_blob = git_blob(path)

    exact_repository = path.is_file() and repository_blob == production_blob
    exact_recovery = (version, name, production_blob) in recovered
    exact_statement_reconciliation = (
        path.is_file()
        and statement_pairs.get(filename) == (repository_blob, production_blob)
    )
    if exact_repository or exact_recovery or exact_statement_reconciliation:
        continue

    foreign = owner_lane not in (lane, 'unclassified', 'shared')
    if lane != 'shared' and foreign:
        ignored.append(f'{version}_{name} ({owner_lane})')
        continue

    if not path.is_file():
        errors.append(
            f"{lane} release lane blocked by uncustodied {owner_lane} live migration: "
            f"{version}_{name}; production={production_blob}; expected {path}, a sealed exact-live-byte recovery, "
            "or a sealed canonical-source/executed-body reconciliation"
        )
    else:
        errors.append(
            f"{lane} release lane blocked by byte drift in {owner_lane} live migration: {path}; "
            f"repository={repository_blob} production={production_blob}; "
            "no sealed matching recovery or statement-body reconciliation"
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

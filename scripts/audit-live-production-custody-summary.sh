#!/usr/bin/env bash
set -euo pipefail

api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"

if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required."
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
import collections
import json
import subprocess
import sys
from pathlib import Path

packet = json.loads(Path(sys.argv[1]).read_text())
receipt = json.loads(Path('custody/executed-statement-body-reconciliations-v1.json').read_text())
reconciliations = {
    row['filename']: (row['canonicalSourceGitBlobSha1'], row['executedBodyGitBlobSha1'])
    for row in receipt.get('rows') or []
}
rows = packet.get('postFence') or []
counts = collections.Counter()
by_day = collections.defaultdict(collections.Counter)
missing = []
unreconciled = []

for row in rows:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    executed_blob = str(row.get('gitBlobSha1') or '')
    day = version[:8] if len(version) >= 8 else 'unknown'
    filename = f'{version}_{name}.sql'
    path = Path('supabase/migrations') / filename
    if not path.is_file():
        status = 'missing'
        missing.append(f'{version}_{name}')
    else:
        repo_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
        if repo_blob == executed_blob:
            status = 'exact'
        elif reconciliations.get(filename) == (repo_blob, executed_blob):
            status = 'reconciled'
        else:
            status = 'unreconciled'
            unreconciled.append({
                'migration': f'{version}_{name}',
                'canonicalSource': repo_blob,
                'executedBody': executed_blob,
            })
    counts[status] += 1
    by_day[day][status] += 1

summary = {
    'contractVersion': 2,
    'postFenceCount': len(rows),
    'exactCount': counts['exact'],
    'reconciledCount': counts['reconciled'],
    'missingCount': counts['missing'],
    'unreconciledCount': counts['unreconciled'],
    'byDay': {
        day: {
            'exact': c['exact'],
            'reconciled': c['reconciled'],
            'missing': c['missing'],
            'unreconciled': c['unreconciled'],
            'total': sum(c.values()),
        }
        for day, c in sorted(by_day.items())
    },
    'firstMissing': missing[:20],
    'firstUnreconciled': unreconciled[:20],
}
print('LIVE_CUSTODY_DRIFT_SUMMARY=' + json.dumps(summary, sort_keys=True, separators=(',', ':')))
PY

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
rows = packet.get('postFence') or []
counts = collections.Counter()
by_day = collections.defaultdict(collections.Counter)
missing = []
mismatch = []

for row in rows:
    version = str(row.get('version') or '')
    name = str(row.get('name') or '')
    production_blob = str(row.get('gitBlobSha1') or '')
    day = version[:8] if len(version) >= 8 else 'unknown'
    path = Path('supabase/migrations') / f'{version}_{name}.sql'
    if not path.is_file():
        status = 'missing'
        missing.append(f'{version}_{name}')
    else:
        repo_blob = subprocess.check_output(['git', 'hash-object', str(path)], text=True).strip()
        if repo_blob == production_blob:
            status = 'exact'
        else:
            status = 'mismatch'
            mismatch.append({
                'migration': f'{version}_{name}',
                'repository': repo_blob,
                'production': production_blob,
            })
    counts[status] += 1
    by_day[day][status] += 1

summary = {
    'contractVersion': 1,
    'postFenceCount': len(rows),
    'exactCount': counts['exact'],
    'missingCount': counts['missing'],
    'mismatchCount': counts['mismatch'],
    'byDay': {
        day: {
            'exact': c['exact'],
            'missing': c['missing'],
            'mismatch': c['mismatch'],
            'total': sum(c.values()),
        }
        for day, c in sorted(by_day.items())
    },
    'firstMissing': missing[:20],
    'firstMismatches': mismatch[:20],
}
print('LIVE_CUSTODY_DRIFT_SUMMARY=' + json.dumps(summary, sort_keys=True, separators=(',', ':')))
PY

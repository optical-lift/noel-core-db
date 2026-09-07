#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${NOEL_CORE_DATABASE_URL:-}" ]]; then
  echo "::error::NOEL_CORE_DATABASE_URL is required."
  exit 1
fi

versions=(
  20260905190050
  20260905223627
  20260905231046
  20260905231340
  20260905233029
  20260905233138
  20260905233244
  20260906000947
  20260906001357
  20260906002837
  20260906003115
  20260906003432
  20260906003549
  20260906003713
  20260906003814
  20260906004144
  20260906004231
  20260906004430
  20260906023055
  20260907163306
  20260907163903
  20260907163916
  20260907164541
  20260907165424
  20260907165509
  20260907173356
  20260907173436
  20260907173630
  20260907173644
  20260907185313
  20260907185610
  20260907190102
  20260907190203
  20260907194502
  20260907194606
  20260907194628
  20260907195104
  20260907195157
  20260907195546
  20260907200543
  20260907200820
  20260907200840
  20260907213046
)

if [[ ${#versions[@]} -ne 43 ]]; then
  echo "::error::Recovery manifest must contain exactly 43 migrations."
  exit 1
fi

: > /tmp/recovered.tsv
mkdir -p supabase/migrations

for version in "${versions[@]}"; do
  sql="with m as (
    select version,name,convert_to(array_to_string(statements,E'\\n'),'UTF8') as body
    from supabase_migrations.schema_migrations where version='${version}'
  )
  select name,
         encode(body,'hex'),
         encode(extensions.digest(convert_to('blob ' || octet_length(body)::text,'UTF8') || decode('00','hex') || body,'sha1'),'hex')
  from m;"
  row="$(psql "${NOEL_CORE_DATABASE_URL}" -X -A -t -F $'\t' -v ON_ERROR_STOP=1 -c "$sql")"
  if [[ -z "$row" ]]; then
    echo "::error::Production migration ${version} was not found."
    exit 1
  fi
  IFS=$'\t' read -r name body_hex expected_sha <<< "$row"
  path="supabase/migrations/${version}_${name}.sql"
  if [[ -e "$path" ]]; then
    actual_sha="$(git hash-object "$path")"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      echo "::error::Existing repository file drifts from production: $path repository=$actual_sha production=$expected_sha"
      exit 1
    fi
  else
    printf '%s' "$body_hex" | xxd -r -p > "$path"
    actual_sha="$(git hash-object "$path")"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      echo "::error::Recovered bytes did not reproduce production blob: $path recovered=$actual_sha production=$expected_sha"
      exit 1
    fi
  fi
  printf '%s\t%s\t%s\n' "$version" "$name" "$expected_sha" >> /tmp/recovered.tsv
done

test "$(wc -l < /tmp/recovered.tsv | tr -d ' ')" = "43"

python3 - <<'PY'
import json
from pathlib import Path

approved = {'core','atlas','wnph','shared','reporting','local','canon','worker','composition'}
rows = []
for line in Path('/tmp/recovered.tsv').read_text().splitlines():
    version, name, sha = line.split('\t')
    if name.split('_', 1)[0] in approved:
        continue
    rows.append({
        'version': version,
        'name': name,
        'filename': f'{version}_{name}.sql',
        'gitBlobSha1': sha,
        'logicalOwner': 'core',
        'disposition': 'recovered_exact_live_bytes',
        'reason': 'post_fence_live_migration_bypassed_source_custody',
    })

if len(rows) != 24:
    raise SystemExit(f'Expected 24 unclassified historical rows, got {len(rows)}')

payload = {
    'contractVersion': 17,
    'sealed': True,
    'classification': 'retrospective_post_fence_custody_recovery',
    'inherits': 'post-fence-migration-recoveries-v16.json',
    'rule': 'These live post-fence rows bypassed canonical source custody. Preserve their exact production filenames and bytes as historical evidence only; this registry does not authorize their historical unclassified prefixes for future migrations.',
    'recoveries': rows,
}
Path('custody/post-fence-migration-recoveries-v17.json').write_text(json.dumps(payload, indent=2) + '\n')
PY

registry_sha="$(git hash-object custody/post-fence-migration-recoveries-v17.json)"
python3 - "$registry_sha" <<'PY'
from pathlib import Path
import sys

sha = sys.argv[1]
p = Path('scripts/check-custody.sh')
s = p.read_text()
replacements = [
    (
        'recovery_registry_v16="custody/post-fence-migration-recoveries-v16.json"\n',
        'recovery_registry_v16="custody/post-fence-migration-recoveries-v16.json"\nrecovery_registry_v17="custody/post-fence-migration-recoveries-v17.json"\n',
    ),
    (
        '  "$recovery_registry_v16" \\\n  "custody/PRODUCTION_BASELINE.md"',
        '  "$recovery_registry_v16" \\\n  "$recovery_registry_v17" \\\n  "custody/PRODUCTION_BASELINE.md"',
    ),
    (
        '  ["$recovery_registry_v16"]="8481f5c492b7ebb86966ea69990ac0830ea6f4e5"\n',
        f'  ["$recovery_registry_v16"]="8481f5c492b7ebb86966ea69990ac0830ea6f4e5"\n  ["$recovery_registry_v17"]="{sha}"\n',
    ),
    (
        '"$recovery_registry_v15" "$recovery_registry_v16"; do',
        '"$recovery_registry_v15" "$recovery_registry_v16" "$recovery_registry_v17"; do',
    ),
    (
        "    (Path('custody/post-fence-migration-recoveries-v16.json'), 16, 'post-fence-migration-recoveries-v15.json'),\n]",
        "    (Path('custody/post-fence-migration-recoveries-v16.json'), 16, 'post-fence-migration-recoveries-v15.json'),\n    (Path('custody/post-fence-migration-recoveries-v17.json'), 17, 'post-fence-migration-recoveries-v16.json'),\n]",
    ),
    ('assert len(seen) == 60', 'assert len(seen) == 84'),
    ('60 sealed retrospective recoveries preserve exact live bytes.', '84 sealed retrospective recoveries preserve exact live bytes.'),
]
for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit(f'Custody checker patch anchor count was {s.count(old)} instead of 1: {old!r}')
    s = s.replace(old, new, 1)
p.write_text(s)
PY

bash scripts/check-custody.sh
bash scripts/check-live-production-custody-lane.sh atlas

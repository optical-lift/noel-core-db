#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
lane="${2:-}"
migration_override="${3:-}"
manifest="custody/release-lanes-v1.json"

if [[ ! "$version" =~ ^[0-9]{14}$ ]]; then
  echo "Usage: $0 <14-digit-migration-version> <atlas|wnph|shared>" >&2
  exit 2
fi
if [[ "$lane" != "atlas" && "$lane" != "wnph" && "$lane" != "shared" ]]; then
  echo "Release lane must be atlas, wnph, or shared." >&2
  exit 2
fi
if [ ! -f "$manifest" ]; then
  echo "Missing $manifest" >&2
  exit 1
fi

if [ -n "$migration_override" ]; then
  if [ ! -f "$migration_override" ]; then
    echo "Migration override does not exist: $migration_override" >&2
    exit 1
  fi
  migration="$migration_override"
  override_base="$(basename "$migration")"
  if [[ "$override_base" != "${version}_"*.sql ]]; then
    echo "Migration override does not belong to version $version: $override_base" >&2
    exit 1
  fi
else
  shopt -s nullglob
  matches=(supabase/migrations/"${version}"_*.sql)
  shopt -u nullglob
  if [ "${#matches[@]}" -ne 1 ]; then
    echo "Expected exactly one canonical migration for version $version; found ${#matches[@]}." >&2
    exit 1
  fi
  migration="${matches[0]}"
fi

base="$(basename "$migration")"
name="${base#${version}_}"
name="${name%.sql}"

python3 - "$manifest" "$lane" "$name" "$migration" <<'PY'
import json
import sys
from pathlib import Path

manifest_path, lane, name, migration_path = sys.argv[1:]
spec = json.loads(Path(manifest_path).read_text())
if spec.get('contractVersion') != 1:
    raise SystemExit('Unexpected release-lane contract version.')
lanes = spec.get('lanes') or {}
if lane not in lanes:
    raise SystemExit(f'Unknown release lane: {lane}')

cfg = lanes[lane]
prefix = cfg['migrationPrefix']
if not name.startswith(prefix):
    raise SystemExit(
        f'Migration {name} is not owned by release lane {lane}; expected prefix {prefix!r}.'
    )

sql = Path(migration_path).read_text(encoding='utf-8').lower()
violations = [fragment for fragment in cfg.get('forbiddenSqlFragments', []) if fragment.lower() in sql]
if violations:
    raise SystemExit(
        f'Migration {name} crosses the {lane} release membrane through forbidden reference(s): '
        + ', '.join(violations)
        + '. Move cross-product work to an explicit shared_ migration instead.'
    )

print(f'Release lane check passed: {name} belongs to {lane} and does not directly cross its product membrane.')
PY

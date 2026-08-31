#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/production-db-release.yml"
releaser="scripts/release-production-migration.sh"

for required in "$workflow" "$releaser"; do
  if [ ! -f "$required" ]; then
    echo "Missing $required"
    exit 1
  fi
done

python3 - <<'PY'
from pathlib import Path

workflow = Path('.github/workflows/production-db-release.yml').read_text()
releaser = Path('scripts/release-production-migration.sh').read_text()

errors = []

on_block = workflow.split('on:', 1)[1].split('\npermissions:', 1)[0] if 'on:' in workflow and '\npermissions:' in workflow else ''
if 'workflow_dispatch:' not in on_block:
    errors.append('Production release must be manually dispatched.')
if 'push:' in on_block or 'pull_request:' in on_block or 'schedule:' in on_block:
    errors.append('Production release must not run automatically from push, PR, or schedule events.')

required_workflow_fragments = [
    "github.ref == 'refs/heads/main'",
    'environment: production',
    'NOEL_CORE_DATABASE_URL: ${{ secrets.NOEL_CORE_DATABASE_URL }}',
    'zirqkouammpwxlqfbsvf',
    'bash scripts/check-custody.sh',
    'bash scripts/check-live-production-custody.sh',
    'bash scripts/release-production-migration.sh',
]
for fragment in required_workflow_fragments:
    if fragment not in workflow:
        errors.append(f'Missing governed workflow requirement: {fragment}')

required_releaser_fragments = [
    'git hash-object',
    'supabase_migrations.schema_migrations',
    'NOEL_CORE_DATABASE_URL',
    'psql "$NOEL_CORE_DATABASE_URL"',
    'Governed production release requires the migration to begin with BEGIN;',
    'Governed production release requires a terminal COMMIT;',
    'array[{tag}{body}{tag}]',
    'Released exactly:',
]
for fragment in required_releaser_fragments:
    if fragment not in releaser:
        errors.append(f'Missing exact-release requirement: {fragment}')

if 'service_role' in workflow.lower():
    errors.append('Production migration workflow must not use a service-role application key as a DDL escape hatch.')
if 'supabase db reset' in workflow or 'supabase db reset' in releaser:
    errors.append('Production release seam must never reset the production database.')

if errors:
    print('Production database release contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production database release contract passed: manual main-only release, protected DB secret, canonical-byte receipt, and live custody verification are all required.')
PY

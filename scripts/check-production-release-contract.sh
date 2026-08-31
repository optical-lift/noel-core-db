#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/production-db-release.yml"
releaser="scripts/release-production-migration.sh"
lane_checker="scripts/check-migration-release-lane.sh"
live_lane_checker="scripts/check-live-production-custody-lane.sh"
manifest="custody/release-lanes-v1.json"

for required in "$workflow" "$releaser" "$lane_checker" "$live_lane_checker" "$manifest"; do
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
    'release_lane:',
    'type: choice',
    '- atlas',
    '- wnph',
    '- shared',
    'bash scripts/check-custody.sh',
    'bash scripts/check-migration-release-lane.sh',
    'bash scripts/check-live-production-custody-lane.sh',
    'bash scripts/release-production-migration.sh',
    'continue-on-error: true',
    'bash scripts/check-live-production-custody.sh',
]
for fragment in required_workflow_fragments:
    if fragment not in workflow:
        errors.append(f'Missing governed workflow requirement: {fragment}')

if "if: inputs.release_lane == 'wnph' || inputs.release_lane == 'shared'" not in workflow:
    errors.append('WNPH membrane must block WNPH/shared releases without blocking Atlas releases.')

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

print('Production database release contract passed: manual main-only release, protected DB secret, canonical-byte receipt, target-lane custody enforcement, and nonblocking global health audit are all required.')
PY

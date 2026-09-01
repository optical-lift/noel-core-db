#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/production-schema-clone-validation.yml"

if [ ! -f "$workflow" ]; then
  echo "Missing $workflow"
  exit 1
fi

python3 - <<'PY'
from pathlib import Path

workflow = Path('.github/workflows/production-schema-clone-validation.yml').read_text()
errors = []

on_block = workflow.split('on:', 1)[1].split('\npermissions:', 1)[0] if 'on:' in workflow and '\npermissions:' in workflow else ''
if 'issues:' not in on_block:
    errors.append('Production schema validation must be requested through an issue on canonical main.')
if 'push:' in on_block or 'pull_request:' in on_block or 'schedule:' in on_block or 'workflow_dispatch:' in on_block:
    errors.append('Production schema validation must not run automatically or from an arbitrary branch dispatch.')

required = [
    "github.event.issue.author_association == 'OWNER'",
    "startsWith(github.event.issue.title, 'Production schema validation request:')",
    'environment: production',
    'ref: main',
    'persist-credentials: false',
    'candidate_sha',
    "re.fullmatch(r'[0-9a-f]{40}', candidate_sha)",
    'NOEL_CORE_DATABASE_URL: ${{ secrets.NOEL_CORE_DATABASE_URL }}',
    'supabase db dump',
    '--schema atlas',
    '--db-url "$NOEL_CORE_DATABASE_URL"',
    'ref: ${{ steps.request.outputs.candidate_sha }}',
    'bash scripts/check-migration-release-lane.sh',
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    'supabase db lint --local --schema atlas --level error --fail-on error',
    'supabase stop --no-backup',
]
for fragment in required:
    if fragment not in workflow:
        errors.append(f'Missing governed schema-validation requirement: {fragment}')

for forbidden in [
    'psql "$NOEL_CORE_DATABASE_URL"',
    "psql '$NOEL_CORE_DATABASE_URL'",
    'supabase db push --linked',
    'supabase migration up --linked',
    'supabase db reset --linked',
    'supabase db reset --db-url',
    'supabase migration up --db-url',
    'supabase db push --db-url',
    'service_role',
]:
    if forbidden.lower() in workflow.lower():
        errors.append(f'Forbidden production-schema-validation behavior: {forbidden}')

snapshot_marker = '- name: Snapshot Atlas production schema read-only'
candidate_marker = '- name: Checkout immutable candidate'
apply_marker = '- name: Apply candidate migration only to local clone'
if snapshot_marker not in workflow or candidate_marker not in workflow or apply_marker not in workflow:
    errors.append('Schema validation step ordering markers are incomplete.')
else:
    snapshot_pos = workflow.index(snapshot_marker)
    candidate_pos = workflow.index(candidate_marker)
    apply_pos = workflow.index(apply_marker)
    if not snapshot_pos < candidate_pos < apply_pos:
        errors.append('Production schema must be snapshotted before candidate checkout, and candidate DDL must execute only after the local clone exists.')

secret_occurrences = workflow.count('NOEL_CORE_DATABASE_URL')
if secret_occurrences != 4:
    errors.append(f'Expected the production DB secret token exactly 4 times inside the single snapshot step; found {secret_occurrences}.')

if errors:
    print('Production schema validation contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production schema validation contract passed: owner-only main workflow, immutable candidate SHA, schema-only production read, local-only candidate execution, and no production DDL path.')
PY

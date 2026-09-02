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
harness = Path('scripts/validate-production-schema-clone.sh').read_text()
comparator = Path('scripts/compare-schema-lint.py').read_text()
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
    '--db-url "$NOEL_CORE_DATABASE_URL"',
    '--role-only',
    '--file "$RUNNER_TEMP/production-custom-roles.sql"',
    '--file "$RUNNER_TEMP/production-user-schema.sql"',
    'ref: ${{ steps.request.outputs.candidate_sha }}',
    'bash scripts/check-migration-release-lane.sh',
    'bash scripts/validate-production-schema-clone.sh',
    '--roles-dump "$RUNNER_TEMP/production-custom-roles.sql"',
    '--schema-dump "$RUNNER_TEMP/production-user-schema.sql"',
    'Publish validation summary',
    'actions/upload-artifact@v4',
    'if-no-files-found: error',
]
for fragment in required:
    if fragment not in workflow:
        errors.append(f'Missing governed schema-validation requirement: {fragment}')

harness_required = [
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    'supabase db lint --local --schema atlas --level error --fail-on error',
    'run_lint baseline',
    'run_lint candidate',
    'scripts/compare-schema-lint.py',
    'supabase stop --no-backup',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$roles_dump"',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$schema_clone"',
]
for fragment in harness_required:
    if fragment not in harness:
        errors.append(f'Missing canonical local-harness requirement: {fragment}')

comparator_required = [
    'candidate_by_key.keys() - baseline_by_key.keys()',
    'schema-lint-delta.json',
    'summary.md',
    'return 1 if introduced else 0',
]
for fragment in comparator_required:
    if fragment not in comparator:
        errors.append(f'Missing lint-delta requirement: {fragment}')

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

snapshot_marker = '- name: Snapshot production user schemas read-only'
candidate_marker = '- name: Checkout immutable candidate'
resolve_marker = '- name: Resolve exact candidate migration'
validate_marker = '- name: Validate candidate through canonical local harness'
markers = [snapshot_marker, candidate_marker, resolve_marker, validate_marker]
if any(marker not in workflow for marker in markers):
    errors.append('Schema validation step ordering markers are incomplete.')
else:
    snapshot_pos = workflow.index(snapshot_marker)
    candidate_pos = workflow.index(candidate_marker)
    resolve_pos = workflow.index(resolve_marker)
    validate_pos = workflow.index(validate_marker)
    if not snapshot_pos < candidate_pos < resolve_pos < validate_pos:
        errors.append('Production custom roles and user schemas must be snapshotted before immutable candidate resolution and canonical local validation.')
    snapshot_block = workflow[snapshot_pos:candidate_pos]
    if '--schema ' in snapshot_block:
        errors.append('Production schema clone must not filter to one user schema; cross-schema dependencies require the complete user-schema graph.')
    if '--role-only' not in snapshot_block or 'production-custom-roles.sql' not in snapshot_block:
        errors.append('Production clone must snapshot custom roles so schema ACL targets exist in the disposable database.')

if snapshot_marker in workflow and candidate_marker in workflow:
    snapshot_pos = workflow.index(snapshot_marker)
    candidate_pos = workflow.index(candidate_marker)
    if 'NOEL_CORE_DATABASE_URL' in workflow[:snapshot_pos] or 'NOEL_CORE_DATABASE_URL' in workflow[candidate_pos:]:
        errors.append('The protected production DB secret may only appear inside the read-only snapshot step.')

if errors:
    print('Production schema validation contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production schema validation contract passed: owner-only main workflow, immutable candidate SHA, dependency-complete schema plus custom-role production reads, one local/CI harness, baseline-aware Atlas lint deltas, durable failure artifacts, local-only candidate execution, and no production DDL path.')
PY

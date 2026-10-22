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
    'Resolve exact candidate migration package',
    'candidate/validation/fixtures',
    'candidate/validation/migrations',
    'fixture_path=',
    'validation_path=',
    'bash scripts/check-migration-release-lane.sh',
    'bash scripts/validate-production-schema-clone.sh',
    '--candidate-fixture "$CANDIDATE_FIXTURE"',
    '--candidate-validation "$CANDIDATE_VALIDATION"',
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
    '--candidate-fixture',
    '--candidate-validation',
    'validation fixture safety check',
    'validation fixture may contain data setup only',
    'candidate validation fixture application',
    'candidate migration postconditions',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_fixture"',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$candidate_validation"',
    'supabase db lint --local --schema atlas --level error --fail-on error',
    'run_lint baseline',
    'run_lint candidate',
    'scripts/compare-schema-lint.py',
    'supabase stop --no-backup',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$roles_dump"',
    'psql "$database_url" -X -v ON_ERROR_STOP=1 -f "$schema_clone"',
    'signed_work_prerequisite_probe',
    'validate-atlas-work-prerequisite-signed-http.py',
    'signed-work-prerequisite.log',
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
resolve_marker = '- name: Resolve exact candidate migration package'
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

# A source-only check for the exact signed prerequisite proof. Any
# production host or user-impersonation shortcut would violate its boundaries.
prereq = Path('scripts/validate-atlas-work-prerequisite-signed-http.py')
fixture = Path('validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql')
if not prereq.is_file() or not fixture.is_file():
    errors.append('Signed prerequisite probe and synthetic fixture are required')
else:
    proof=prereq.read_text()
    synthetic=fixture.read_text()
    import ast
    try:
        ast.parse(proof,filename=str(prereq))
    except SyntaxError as exc:
        errors.append(f'Signed prerequisite Python source is invalid: {exc}')
    for fragment in ('c1.local_status()', 'c1.sign_in(', 'ThreadPoolExecutor',
                     'signed session', 'sourceActionId', '42501',
                     'work_item_prerequisite_events_v1'):
        if fragment not in proof:
            errors.append(f'Missing signed prerequisite proof: {fragment}')
    for fragment in ('insert into auth.users', 'insert into atlas.work_items',
                     'insert into atlas.company_work_native_ledger_relevance'):
        if fragment not in synthetic:
            errors.append(f'Missing synthetic fixture setup: {fragment}')
    if 'https://zirqkouammpwxlqfbsvf.supabase.co' in proof:
        errors.append('Signed proof must not hardcode production Supabase endpoint')
    # Match the disposable harness's DML-only fixture safety gate in PR CI,
    # before requiring a protected production-schema snapshot.
    import re
    normalized = re.sub(r'/\\*.*?\\*/', ' ', synthetic, flags=re.S)
    normalized = re.sub(r'--[^\\n]*', ' ', normalized)
    normalized = re.sub(r'\\s+', ' ', normalized).strip()
    forbidden = re.compile(
        r'\\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|'
        r'reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|'
        r'listen|notify|security)\\b', re.I)
    found = forbidden.search(normalized)
    if found:
        errors.append(f'Prererequisite fixture has forbidden token: {found.group(0)}')
    statements = [item.strip() for item in normalized.split(';') if item.strip()]
    if not statements or any(not re.match(r'^(insert\\s+into|update\\s+|delete\\s+from|select\\s+)', item, re.I) for item in statements):
        errors.append('Prerequisite fixture has non-DML statements')


if errors:
    print('Production schema validation contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production schema validation contract passed: owner-only main workflow, immutable candidate SHA, dependency-complete schema plus custom-role production reads, immutable candidate fixtures/postconditions, DML-only local fixture setup, one local/CI harness, baseline-aware Atlas lint deltas, durable failure artifacts, local-only candidate execution, and no production DDL path.')
PY

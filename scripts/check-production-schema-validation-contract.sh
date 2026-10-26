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
    'signed_connected_work_prerequisite_probe',
    'validate-atlas-connected-work-prerequisite-signed-http.py',
    'signed-connected-work-prerequisite.log',
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
    # Mirror the disposable harness's exact DML-only fixture safety guard.
    import re
    normalized = re.sub(r'/\*.*?\*/', ' ', synthetic, flags=re.S)
    normalized = re.sub(r'--[^\n]*', ' ', normalized)
    normalized = re.sub(r'\s+', ' ', normalized).strip()
    forbidden = re.compile(
        r'\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|'
        r'reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|'
        r'listen|notify|security)\b', re.I)
    found = forbidden.search(normalized)
    if found:
        errors.append(f'Prerequisite fixture has forbidden token: {found.group(0)}')
    statements = [item.strip() for item in normalized.split(';') if item.strip()]
    if not statements or any(
        not re.match(r'^(insert\s+into|update\s+|delete\s+from|select\s+)', item, re.I)
        for item in statements
    ):
        errors.append('Prerequisite fixture has non-DML statements')


# Governed worker source: neither a Ledger seat nor editable JWT metadata
# is a substitute for a current, source-confirmed responsible Work allocation.
worker_sql=Path('candidates/atlas/atlas_connected_person_work_prerequisites_v1.sql')
worker_fixture=Path('candidates/atlas/atlas_connected_person_work_prerequisites_v1_fixture.sql')
worker_validation=Path('candidates/atlas/atlas_connected_person_work_prerequisites_v1_postconditions.sql')
worker_test=Path('scripts/validate-atlas-connected-work-prerequisite-signed-http.py')
worker_review=Path('proposals/atlas_connected_person_work_prerequisites_v1_REVIEW_ONLY.sql')
if not all(p.is_file() for p in (worker_sql,worker_fixture,worker_validation,worker_test,worker_review)):
    errors.append('Exact worker prerequisite generator, local fixture, validation and signed source proof are required')
else:
    source=worker_review.read_text()
    candidate=worker_sql.read_text()
    proof=worker_test.read_text()
    generated_fixture=worker_fixture.read_text()
    import ast
    try:
        ast.parse(proof,filename=str(worker_test))
    except SyntaxError as exc:
        errors.append(f'Signed connected Work reader source invalid: {exc}')
    if not candidate.startswith('BEGIN;\n') or not candidate.rstrip().endswith('COMMIT;'):
        errors.append('Worker prerequisite candidate missing atomic transaction boundaries')
    if source.strip() not in candidate:
        errors.append('Worker candidate differs from reviewed source SQL')
    for fragment in ('reality_access_self_api_v1','current_person_id_v1',
                     'person_has_native_ledger_connection_v1',
                     'work_prerequisite_ledger_scope_v1',
                     'assignee_canonical_person_id=v_person',
                     'a.assignee_membership_id is null',
                     "a.allocation_role='responsible'",
                     'doesNotAuthorizeRelationChanges'):
        if fragment not in source:
            errors.append(f'Worker prerequisite source authority missing: {fragment}')
    for fragment in ('c1.sign_in(', 'original.setup_auth(', 'connected_ledger_direct_assign_self_api_v1',
                     'atlas_set_work_prerequisite_self_api_v1', 'original.deny(',
                     'auth.sessions', 'ledger.seats'):
        if fragment not in proof:
            errors.append(f'Worker signed proof missing: {fragment}')
    if 'https://zirqkouammpwxlqfbsvf.supabase.co' in proof:
        errors.append('Worker signed proof must never hardcode production')
    # Exact disposable-clone fixture sanitizer, including SQL keywords in
    # literal titles; catches mistakes before a protected schema snapshot.
    scrub=re.sub(r'/\*.*?\*/',' ',generated_fixture,flags=re.S)
    scrub=re.sub(r'--[^\n]*',' ',scrub)
    normalized=re.sub(r'\s+',' ',scrub).strip()
    blocked=re.compile(
        r'\b(create|alter|drop|truncate|grant|revoke|comment|vacuum|analyze|'
        r'reindex|cluster|refresh|copy|do|call|execute|prepare|deallocate|'
        r'listen|notify|security)\b',re.I)
    match=blocked.search(normalized)
    if match: errors.append(f'Worker prerequisite fixture contains forbidden token: {match.group(0)}')
    operations=[t.strip() for t in normalized.split(';') if t.strip()]
    if not operations or any(
        not re.match(r'^(insert\s+into|update\s+|delete\s+from|select\s+)',t,re.I)
        for t in operations):
        errors.append('Worker prerequisite fixture is not DML-only')

# Foundry's new signed proof runs through the **same** protected
# schema-clone harness, and must never substitute unsigned SQL GUC identity.
foundry_probe = Path('scripts/validate-shared-foundry-workspace-signed-http.py')
if not foundry_probe.is_file():
    errors.append('Missing genuine local signed Foundry workspace proof')
else:
    probe_text = foundry_probe.read_text()
    try:
        ast.parse(probe_text,filename=str(foundry_probe))
    except SyntaxError as exc:
        errors.append(f'Foundry signed proof Python syntax invalid: {exc}')
    for fragment in ("127[.]0[.]0[.]1", "c1.sign_in(", "auth.sessions",
                     "get_foundry_workspace_preparation_self_api_v1",
                     "prepare_foundry_workspace_self_api_v1",
                     "deleted GoTrue session", "cross-Principal",
                     "custody_review_state='pending'"):
        if fragment not in probe_text:
            errors.append(f'Missing Foundry signed-auth boundary: {fragment}')
    if 'https://zirqkouammpwxlqfbsvf.supabase.co' in probe_text:
        errors.append('Foundry signed test cannot contact production Supabase')
for fragment in ('signed_foundry_workspace_probe=true',
                 'validate-shared-foundry-workspace-signed-http.py',
                 'shared_foundry_connected_workspace_gate1_signed_v1'):
    if fragment not in harness:
        errors.append(f'Foundry signed local harness dispatch missing: {fragment}')

# Independent-human Foundry source-custody review is a signed LOCAL-only
# extension of the existing Foundry workspace probe, not a new paid service.
custody_probe = Path('scripts/validate-shared-foundry-custody-signed-http.py')
if not custody_probe.is_file():
    errors.append('Missing local signed two-human Foundry custody probe')
else:
    custody_source = custody_probe.read_text()
    try:
        ast.parse(custody_source,filename=str(custody_probe))
    except SyntaxError as exc:
        errors.append(f'Foundry human custody signed proof syntax invalid: {exc}')
    for fragment in ('source_refs', 'foundry-other', 'foundry-owner',
                     'independent', 'request_foundry_source_custody_review_self_api_v1',
                     'decide_foundry_source_custody_review_self_api_v1',
                     'revoke_foundry_source_custody_review_self_api_v1',
                     'aiCarrierAccess', 'auth.sessions', 'signed'):
        if fragment not in custody_source:
            errors.append(f'Foundry custody proof missing boundary: {fragment}')
for fragment in ('validate-shared-foundry-custody-signed-http.py',
                 'to_regprocedure('):
    if fragment not in Path('scripts/validate-shared-foundry-workspace-signed-http.py').read_text():
        errors.append(f'Foundry signed workspace runner missing human custody hook: {fragment}')


# Universal Work is the same canonical Work engine across Bed and Household
# Subjects. This checker authorizes only the pre-existing protected clone,
# fictional DML fixtures and genuine local GoTrue/REST source assertions.
signed_universal = Path('scripts/validate-atlas-universal-original-work-signed-http.py')
if not signed_universal.is_file():
    errors.append('Universal original Work signed proof missing')
else:
    proof = signed_universal.read_text()
    try:
        ast.parse(proof, filename=str(signed_universal))
    except SyntaxError as exc:
        errors.append(f'Universal original Work signed proof syntax invalid: {exc}')
    for fragment in ('127[.]0[.]0[.]1', 'c1.sign_in(', 'auth.sessions',
                     'split_original_canonical_work_owner_self_api_v1',
                     'owner_direct_assign_existing_original_work_self_api_v1',
                     'connected_person_original_work_subject_self_api_v1',
                     'record_household_laundry_wash_started_self_api_v1',
                     'household_laundry_explicit_rhythm_decide_self_api_v1'):
        if fragment not in proof:
            errors.append(f'Universal Work signed proof missing boundary: {fragment}')
    if 'https://zirqkouammpwxlqfbsvf.supabase.co' in proof:
        errors.append('Universal Work signed proof may not reach production')
for fragment in ('signed_universal_original_work_probe=true',
                 'atlas_universal_original_work_integrated_v1',
                 'validate-atlas-universal-original-work-signed-http.py',
                 'signed-universal-original-work-summary.txt',
                 'signed-universal-original-work.log'):
    if fragment not in harness:
        errors.append(f'Protected local clone missing universal signed gate: {fragment}')

if errors:
    print('Production schema validation contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production schema validation contract passed: owner-only main workflow, immutable candidate SHA, dependency-complete schema plus custom-role production reads, immutable candidate fixtures/postconditions, DML-only local fixture setup, one local/CI harness, baseline-aware Atlas lint deltas, durable failure artifacts, local-only candidate execution, and no production DDL path.')
PY

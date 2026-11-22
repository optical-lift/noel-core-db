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

# Disposable Docker host-port isolation must test wildcard bindability,
# not infer availability from a failed localhost connect() or a fixed port.
for fragment in ('secrets.SystemRandom().shuffle(ports)',
                 'sock.bind(("0.0.0.0", port))',
                 'No bindable disposable database port found'):
    if fragment not in harness:
        errors.append('Disposable clone host-port guard missing: '+fragment)

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

# Exact held generated listening scope: no new protected workflow or hosted writer.
for fragment in (
    '3927e5498298fd79aa47902b073c6b70b7a30cf0', '1c7b398136b399983b1acdb2712b70958761d768', '106268970a69c33c5a8d30d737e5d98af807ccfa', 'de89478c094719912a9ac145af28e01186584c32', '5edc7bbebbdbaa4ba00e1415fcf58b6102fafa7c',
    'shared_generated_listening_storage_signed_clone_only_v1',
    'held-generated-listening-storage', 'verify_generated_listening_storage_signed.py',
):
    if fragment not in workflow:
        errors.append('Missing held generated listening scope: '+fragment)
for fragment in (
    '1c7b398136b399983b1acdb2712b70958761d768', '106268970a69c33c5a8d30d737e5d98af807ccfa', 'de89478c094719912a9ac145af28e01186584c32', '5edc7bbebbdbaa4ba00e1415fcf58b6102fafa7c', 'signed_generated_listening_storage_probe=true',
    'cat "$listening_completion" "$listening_original" "$listening_staging"',
    'signed-generated-listening-storage-summary.txt',
    'PASS signed local Storage staging and byte readback; independent denials; no admission or publication.',
):
    if fragment not in harness:
        errors.append('Missing exact signed generated listening harness gate: '+fragment)
storage_start = harness.split('elif [ "$signed_generated_listening_storage_probe" = true ]; then',1)[-1].split('elif ',1)[0]
if 'supabase start -x ' not in storage_start or 'storage-api' in storage_start or 'supabase db start' in storage_start:
    errors.append('Signed generated listening must start actual local Storage API, Auth and REST.')

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
                     'household_laundry_explicit_rhythm_decide_self_api_v1',
                     'farm_memberships', 'zone_registry_source_v1',
                     'object_crop_bed_map_v1', 'farm_care_zone_v1',
                     'farm_snapshot_for_member_v1',
                     'bed_components_state_v1'):
        if fragment not in proof:
            errors.append(f'Universal Work signed proof missing boundary: {fragment}')
    if 'https://zirqkouammpwxlqfbsvf.supabase.co' in proof:
        errors.append('Universal Work signed proof may not reach production')
for fragment in ('signed_universal_original_work_probe=true',
                 'atlas_universal_original_work_integrated_v1',
                 'validate-atlas-universal-original-work-signed-http.py',
                 'signed-universal-original-work-summary.txt',
                 'signed-universal-original-work.log',
                 'validate-atlas-one-event-schedule-writer-signed-http.py',
                 'signed-universal-original-work-event-regression.txt',
                 'signed-universal-original-work-event-regression.log'):
    if fragment not in harness:
        errors.append(f'Protected local clone missing universal signed gate: {fragment}')


# Executing signed original Work requires LOCAL Auth and PostgREST, not only
# the local PostgreSQL container. Guard against silently falling back to
# `supabase db start` while a signed probe appears to have been selected.
startup = harness.split('if [ "$signed_http_probe" = true ] ||',1)[-1]
startup = startup.split('supabase start >"$startup_log" 2>&1',1)[0]
if '[ "$signed_universal_original_work_probe" = true ]' not in startup:
    errors.append('Universal signed probe accidentally starts PostgreSQL-only')

# Exact held Household repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held Household Work",
                 "fdbd73772b4760c9a97d743571705cfe29822a2f", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_work_subject_pair_repair_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held Household request boundary missing: "+fragment)
for fragment in ("de88e16dc36ac052f2fb0e90b708c30253db06d1",
                 "742f436f96149186a0c5c9d3b9d6d598b885667f",
                 "737c8f98e4c0dcd4e9371a3bc99e123b05aae6c7",
                 "a561ee3d34bad17837d02eed3908db3a7be6d61c"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held Household immutable package pin missing: "+fragment)
if '[ "$signed_household_original_repair_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if 'signed-household-original-repair-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Exact held Laundry lifecycle repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held Laundry lifecycle",
                 "d865a4e510e26fdd9a154466ad9deb0af71a243f", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_laundry_lifecycle_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held Laundry lifecycle request boundary missing: "+fragment)
for fragment in ("058c6627e5c369ed9b83b0f972abc949739095e7",
                 "ce747e365321526757e2302f32572dfd45ca91e9",
                 "737c8f98e4c0dcd4e9371a3bc99e123b05aae6c7",
                 "9f1ae62612df98ae0a8b2d73482ebbf58f11fa19"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held Laundry lifecycle immutable package pin missing: "+fragment)
if '[ "$signed_household_lifecycle_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if 'signed-household-lifecycle-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Exact held Laundry renewal initial repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held Laundry renewal initial",
                 "862e54018648341d1d4ddd8b55c559984b3f8f7c", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_laundry_renewal_initial_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held Laundry renewal initial request boundary missing: "+fragment)
for fragment in ("9cb29da5dfd9042224fcc1e1e08414a537c72fa0",
                 "76728974daa1622c11f0c4a9d08e6b26b8c1af11",
                 "0a6225004cdd8d693d2f243b770d1b8b7412f5cf",
                 "09af135127887ca34ed428ec7c4531ab6dc8dc9d", "69426f1df315dafe528981b69dd50a84100ec78c"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held Laundry renewal initial immutable package pin missing: "+fragment)
if '[ "$signed_household_renewal_initial_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if 'signed-household-renewal-initial-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Exact held Laundry renewal due repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held Laundry renewal due",
                 "e3290c01631f9d28d16fbecd3085c904eaab5a6c", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_laundry_renewal_due_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held Laundry renewal due request boundary missing: "+fragment)
for fragment in ("9cb29da5dfd9042224fcc1e1e08414a537c72fa0",
                 "76728974daa1622c11f0c4a9d08e6b26b8c1af11",
                 "0a6225004cdd8d693d2f243b770d1b8b7412f5cf",
                 "cd244d0f961187bd022309c50790fe5334e92afc", "dde6d83550b892ada267d68a99bde3d493860faa"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held Laundry renewal due immutable package pin missing: "+fragment)
if '[ "$signed_household_renewal_due_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if "grep -q '^PASS signed due renewal:'" not in harness:
    errors.append("Due renewal exact signed receipt matcher changed")
if 'signed-household-renewal-due-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Exact held clean Need renewal initial repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held clean Need renewal initial",
                 "b5a64691e1e5f96741bde81469f636b8356198b4", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_need_renewal_clean_initial_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held clean Need renewal initial request boundary missing: "+fragment)
for fragment in ("27561382cbc33be1da2b1128481702b2d511001f",
                 "23eaa37cd92a4e72ba954d5892e6b2bae0466aee",
                 "d0c82b47f242b3ef4fe077f86fd1d20f378e359f",
                 "1251c8971f26518220f8e8851ce9b220b10e60af", "9440ffcedd817b33e2736a969e40c523f75e18a3"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held clean Need renewal initial immutable package pin missing: "+fragment)
if '[ "$signed_clean_renewal_initial_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if 'signed-clean-renewal-initial-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Exact held clean Need renewal due repair: preserve the one canonical protected carrier;
# owner request and immutable SQL/fixture/proof bytes, local-only execution.
for fragment in ("Production schema validation request: Atlas held clean Need renewal due",
                 "b5a64691e1e5f96741bde81469f636b8356198b4", "os.environ['REQUEST_ACTOR'] != os.environ['REPO_OWNER']",
                 "supabase migration new atlas_household_need_renewal_clean_due_clone_only_v1",
                 "actual_version=$version", "held_proof"):
    if fragment not in workflow:
        errors.append("Held clean Need renewal due request boundary missing: "+fragment)
for fragment in ("27561382cbc33be1da2b1128481702b2d511001f",
                 "23eaa37cd92a4e72ba954d5892e6b2bae0466aee",
                 "d0c82b47f242b3ef4fe077f86fd1d20f378e359f",
                 "6be4632c95c076e3a962a7b8e10967063cc14984", "cbb87cb6cd0feadb459007bc6938f0f566454598"):
    if fragment not in workflow or fragment not in harness:
        errors.append("Held clean Need renewal due immutable package pin missing: "+fragment)
if '[ "$signed_clean_renewal_due_probe" = true ]' not in startup:
    errors.append("Household signed probe accidentally starts PostgreSQL-only")
if "grep -q '^PASS signed due renewal:'" not in harness:
    errors.append("Due renewal exact signed receipt matcher changed")
if 'signed-clean-renewal-due-summary.txt' not in harness:
    errors.append("Household signed proof cannot be omitted from successful clone")

# Signed care proof must reuse local native Work/Person infrastructure and
# must never become an arbitrary candidate-triggered or production call.
care_script=Path('scripts/validate-atlas-care-single-done-signed-http.py')
if not care_script.is_file():
    errors.append('Canonical signed care proof script missing')
else:
    import ast
    care=care_script.read_text()
    try: ast.parse(care,filename=str(care_script))
    except SyntaxError as exc:
        errors.append(f'Signed care proof invalid Python: {exc}')
    for part in ('c1.sign_in(', 'auth.sessions',
                 'owner_establish_observed_continuing_care_work_self_api_v1',
                 'record_continuing_care_actual_self_api_v1',
                 'work_transition_applied', 'rhythm_satisfactions',
                 'connected_person_original_work_subject_self_api_v1',
                 'weeded_partial','weeded_full'):
        if part not in care: errors.append('Signed care proof missing '+part)
    # This gate must use REAL bearer HTTP through the public reporter,
    # never only privileged SQL with copied JWT claims as previous private
    # source coverage did.
    for part in ("CARE_RPC=\"record_continuing_care_actual_self_api_v1\"",
                 "partial=allow(api,key,worker,CARE_RPC",
                 "full=allow(api,key,worker,CARE_RPC",
                 "replay=allow(api,key,worker,CARE_RPC",
                 "refused_care(api,key,outsider",
                 "refused_care(api,key,owner",
                 "has_function_privilege('anon'",
                 "has_function_privilege('authenticated'"):
        if part not in care:
            errors.append('Real signed HTTP care proof missing: '+part)
    # The chosen standing method, projected eligibility, and physical
    # observation must use real independent signed HTTP identity, not local
    # privileged SQL or a second Work/Clock generator.
    for part in ('owner_decide_continuing_source_governance_self_api_v1',
                 'continuing_work_source_eligibility_self_api_v1',
                 'record_standing_care_observation_self_api_v1',
                 'assigned_work_only', 'eligible_disclosed',
                 'standing_source_observed',
                 'fresh_physical_observation_required',
                 'physical_condition_or_strategy_not_eligible',
                 'rhythm_window_not_reached',
                 'Governor hold immediately revokes',
                 'sourceObservationId', 'noWorkCreated'):
        if part not in care:
            errors.append('Signed standing source proof missing '+part)
    # The final Work gate must be the SAME native canonical Person/Today
    # source, with real signed HTTP and source_verified governor authority.
    for part in ('standing_admission(', 'reject_admission(',
                 'admit_standing_continuing_source_work_self_api_v1',
                 'company_work_native_ledger_relevance',
                 'source_verified','connected_person_my_work_self_api_v1',
                 'workRelevanceVerified', 'scheduleState',
                 'newOriginalWorkCreated',
                 'Another action cannot duplicate open standing Need',
                 'Owner hold also revokes further standing Work admission'):
        if part not in care:
            errors.append('Native signed standing admission proof missing '+part)
    if 'zirqkouammpwxlqfbsvf' in care:
        errors.append('Signed care proof must not refer to production project')
for part in ('signed_care_single_done_probe=true',
             'atlas_care_single_done_signed_proof_v1',
             'validate-atlas-care-single-done-signed-http.py',
             'signed-care-single-done.log',
             'signed-care-single-done-summary.txt'):
    if part not in harness:
        errors.append('Canonical clone care proof admission missing: '+part)
startup=harness.split('if [ "$signed_http_probe" = true ] ||',1)[-1]
startup=startup.split('supabase start >"$startup_log" 2>&1',1)[0]
if '[ "$signed_care_single_done_probe" = true ]' not in startup:
    errors.append('Signed care probe accidentally starts PostgreSQL-only')

# ACCESS-01: only the exact generated Atlas migration inherits the proven
# fail-closed disposable anonymous REST ACL parity recovery. All other names
# and domains retain the original untouched validator behavior.
access01_route = (
    'if [ "$signed_access01_event_choices_probe" = true ] || {' in harness
    and '[ "$lane" = "atlas" ] &&' in harness
    and '^[0-9]{14}_atlas_access01_event_choices_root_boundary_v1[.]sql$' in harness
    and 'phase="ACCESS-01 disposable anonymous REST ACL parity"' in harness
    and 'PGOPTIONS="-c access01.disposable_clone=true"' in harness
    and 'scripts/atlas-access01-disposable-anon-parity-held.sql' in harness
)
if not access01_route:
    errors.append('ACCESS-01 exact generated Atlas clone ACL fidelity route missing')

# Held orphan retirement: exact package admission and unchanged trusted proof.
for fragment in (
    'Production schema validation request: Atlas held orphan queue backfill retirement', '833cbd7dbe2674fb747bc055878344b94be12c2b', 'held-orphan-queue-backfill-retirement',
    '5956b80d02ff5e7d80553270b57d238e6fd2afd1', 'd771e05ef86b08997b4d7a4b78d143a58547738c', '766ab2b69c53796ca6aa892d57a1188fab799bc8', 'a6dbf950b689505babe33811f421add9db2a742d', 'eb3bbfb45848a7fca90cc503e153f1451d8d7471', '1b82e698705e473280f1fc55b0e762bce243effb',
    "Exact owner-held orphan backfill validation authorization required",
):
    if fragment not in workflow:
        errors.append('Orphan backfill exact owner/source admission missing: '+fragment)
for fragment in (
    'atlas_legacy_queue_orphan_backfill_retirement_clone_only_v1', '5956b80d02ff5e7d80553270b57d238e6fd2afd1', 'd771e05ef86b08997b4d7a4b78d143a58547738c', '766ab2b69c53796ca6aa892d57a1188fab799bc8', 'a6dbf950b689505babe33811f421add9db2a742d', 'eb3bbfb45848a7fca90cc503e153f1451d8d7471', '1b82e698705e473280f1fc55b0e762bce243effb',
    'orphan_queue_retirement_proof=true', 'orphan-all-atlas-row-fingerprints.json',
    '--snapshot "$orphan_row_snapshot" --mode capture',
    '--snapshot "$orphan_row_snapshot" --mode verify',
    'orphan-local-row-integrity-after-candidate.log',
    'signed_work_prerequisite_probe=true',
    'Refuse orphan backfill proof without exact isolated package and trusted regressions.',
):
    if fragment not in harness:
        errors.append('Orphan backfill protected clone proof missing: '+fragment)
if not (harness.index('orphan-local-row-integrity-baseline.log') <
        harness.index('phase="candidate migration application"') <
        harness.index('orphan-local-row-integrity-after-candidate.log') <
        harness.index('phase="signed local prerequisite owner/worker authority')):
    errors.append('Orphan backfill proof must compare all rows around deletion before signed fixture mutation.')

# Queue owner reconciliation: exactly one immutable test-only candidate,
# never an arbitrary migration, mutable fixture, remote DB, or missing signer.
for fragment in (
  'signed_legacy_queue_owner_probe=false',
  '[ "$version" = 20261120235959 ]',
  '20261120235959_atlas_legacy_queue_owner_canonical_work_clone_only_v1.sql',
  '0a47afde4f84b5d08baa025e2bc3f5b1db15df8a',
  'f24b3f40ecaa32df2f88cf9d9718f0011d240222',
  'c563231ca64bf07c5bdccc805e09997496e3a00b',
  '7b07b29b1968af6ae0140871413eff62be8a0cd3',
  'ba2be33fa479e7d24523c10eaee3bbcf12918b3b',
  'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
  '1b82e698705e473280f1fc55b0e762bce243effb',
  'signed_legacy_queue_owner_probe=true',
  'phase="genuinely signed local Ledger-owner queue evidence and original Work denial matrix"',
  'signed-legacy-queue-owner-summary.txt',
  'signed-legacy-queue-owner.log',
  'Queue owner signed proof refuses nonlocal database'
):
    if fragment not in harness:
        errors.append('Exact signed queue owner disposable source protection missing: '+fragment)
if not (harness.index('phase="candidate migration postconditions"') <
        harness.index('phase="genuinely signed local Ledger-owner queue evidence')):
    errors.append('Queue owner signed probe must run only after candidate postconditions')
if harness.count('signed_legacy_queue_owner_probe=true') != 1:
    errors.append('Queue owner proof admission must have one exact source gate')

# Exactly two owner-completion serial queue functions: original immutable held
# source and disposable original PG17/full-730-table/signed C1 custody path.
for fragment in (
    'Production schema validation request: Atlas held owner-completion serial orphan branch',
    'atlas_owner_completion_queue_orphan_branch_clone_only_v1',
    'held-owner-completion-serial-orphan',
    'ae73258185a6d9840ec9528c6f498ef620fb1fee',
    'a5a23c42557bf6913321689fb9853afb57ff2c0e',
    'a3dbc4fe6f5db230ed3dbf071e514ff06487e807',
    '19981823e3d6e7da8a82b5d609fb1558e38c4251',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held two-function serial orphan branch test approval required',
):
    if fragment not in workflow:
        errors.append('Original held owner-completion serial orphan source admission missing: '+fragment)
for fragment in (
    'atlas_owner_completion_queue_orphan_branch_clone_only_v1',
    'a5a23c42557bf6913321689fb9853afb57ff2c0e',
    'a3dbc4fe6f5db230ed3dbf071e514ff06487e807',
    '19981823e3d6e7da8a82b5d609fb1558e38c4251',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'orphan_queue_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
    'orphan-all-atlas-row-fingerprints.json',
):
    if fragment not in harness:
        errors.append('Original protected owner-completion serial orphan signed/no-loss machinery missing: '+fragment)
if not (
    "if title == 'Production schema validation request: Atlas held owner-completion serial orphan branch':" in workflow
    and 'test "$(git -C candidate rev-parse HEAD)" = "ae73258185a6d9840ec9528c6f498ef620fb1fee"' in workflow
    and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_owner_completion_queue_orphan_branch_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql" ]]' in harness
):
    errors.append('Two-function orphan branch must be source-pinned in SAME existing protected workflow')
if not (harness.index('phase="orphan backfill local all-Atlas-row baseline"') <
        harness.index('phase="candidate migration application"') <
        harness.index('orphan-local-row-integrity-after-candidate.log') <
        harness.index('phase="signed local prerequisite owner/worker authority')):
    errors.append('Two-function orphan must use original full-Atlas-row proof before signed C1 regression')

# Six-trigger Package B subtraction: exact held SHA/source/postcondition,
# existing production-shaped disposable clone and trusted signer, never release.
for fragment in (
    'Production schema validation request: Atlas held queue progression trigger retirement',
    'atlas_historical_queue_progression_trigger_retirement_clone_only_v1',
    'held-queue-progression-retirement',
    '849fb0eb5123545ddc10fb67e4c0bd9efe798c0e',
    'a34107ba634c558af40fa437c29a013d6a7adc29',
    '999201b8a73dfb04bbd680241a7fafab6028a218',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held progression trigger retirement validation authorization required',
):
    if fragment not in workflow:
        errors.append('Queue trigger retirement source admission missing: '+fragment)
for fragment in (
    'atlas_historical_queue_progression_trigger_retirement_clone_only_v1',
    'a34107ba634c558af40fa437c29a013d6a7adc29',
    '999201b8a73dfb04bbd680241a7fafab6028a218',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'orphan_queue_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
):
    if fragment not in harness:
        errors.append('Queue trigger retirement protected clone or signer missing: '+fragment)
if not ('if title == \'Production schema validation request: Atlas held queue progression trigger retirement\':' in workflow
        and 'test "$(git -C candidate rev-parse HEAD)" = "849fb0eb5123545ddc10fb67e4c0bd9efe798c0e"' in workflow
        and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_historical_queue_progression_trigger_retirement_clone_only_v1[.]sql$ ]]' in harness):
    errors.append('Queue trigger retirement package must be independently pinned to owner request, SHA and local harness.')
if not (harness.index('phase="orphan backfill local all-Atlas-row baseline"') <
        harness.index('phase="candidate migration application"') <
        harness.index('phase="orphan backfill local all-Atlas-row unchanged after exact deletion"') <
        harness.index('phase="signed local prerequisite owner/worker authority')):
    errors.append('Queue trigger retirement must use existing before/after ALL-row fingerprint and signed actor regression.')

# Five-function queue consumer subtraction: pinned immutable source,
# original Work/source-row preservation, no special SQL execution carrier.
for fragment in (
    'Production schema validation request: Atlas held five live queue consumer decoupling',
    'atlas_legacy_queue_live_consumer_decoupling_clone_only_v1',
    'held-queue-consumer-decoupling',
    'eeded0cd1d3d26977c2f499af5288b59858195d2',
    'd62d42837f4a36e7ba0ded4bf4b8c29f948488fa',
    '7d3b3ff7c7951405b823b3a2a25f3ef4c087832c',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held five live queue consumer validation authorization required',
):
    if fragment not in workflow:
        errors.append('Five live consumer held source workflow admission missing: '+fragment)
for fragment in (
    'atlas_legacy_queue_live_consumer_decoupling_clone_only_v1',
    'd62d42837f4a36e7ba0ded4bf4b8c29f948488fa',
    '7d3b3ff7c7951405b823b3a2a25f3ef4c087832c',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'orphan_queue_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
):
    if fragment not in harness:
        errors.append('Five live consumer held signed harness admission missing: '+fragment)
if not ('if title == \'Production schema validation request: Atlas held five live queue consumer decoupling\':' in workflow
        and 'test "$(git -C candidate rev-parse HEAD)" = "eeded0cd1d3d26977c2f499af5288b59858195d2"' in workflow
        and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_legacy_queue_live_consumer_decoupling_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121211411_atlas_legacy_queue_five_live_consumer_decoupling_v1.sql" ]]' in harness):
    errors.append('Five live consumer candidate not pinned to exact owner request/immutable source')
if not (harness.index('phase="orphan backfill local all-Atlas-row baseline"') <
        harness.index('phase="candidate migration application"') <
        harness.index('phase="orphan backfill local all-Atlas-row unchanged after exact deletion"') <
        harness.index('phase="signed local prerequisite owner/worker authority')):
    errors.append('Five live consumer source cutover must retain all-row preservation and signed actor regression')

# One exact owner-adjudicated 2026 unfinished retirement. The original
# C1 signed actor, all-Atlas row fingerprint, protected issue admission,
# immutable SQL/fixture/postcondition and separate local-only DML are required.
for fragment in (
    'Production schema validation request: Atlas held obsolete 2026 unfinished retirement',
    'atlas_obsolete_2026_unfinished_retirement_clone_only_v1',
    'held-obsolete-unfinished-retirement',
    'a6c1522ea5cc154ae13dd4f872bc7251337f69e9',
    '55f7f92430cea0beeef79f9c4705a8a7f2afe9a0',
    'd06aa20d0c0694160cb32126abf3ffa49b2d3822',
    '722d802f517b99e34fbe284e2e20b71daa99c6a6',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held obsolete 2026 unfinished retirement proof required',
):
    if fragment not in workflow:
        errors.append('2026 unfinished source-only protected owner admission missing: '+fragment)
for fragment in (
    'atlas_obsolete_2026_unfinished_retirement_clone_only_v1',
    '20261121184327_atlas_obsolete_2026_unfinished_retirement_v1.sql',
    '55f7f92430cea0beeef79f9c4705a8a7f2afe9a0',
    'd06aa20d0c0694160cb32126abf3ffa49b2d3822',
    '722d802f517b99e34fbe284e2e20b71daa99c6a6',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    'a6dbf950b689505babe33811f421add9db2a742d',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'obsolete_unfinished_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
    'held obsolete queue exact four source-capacity tables and all-other-Atlas-row conservation',
):
    if fragment not in harness:
        errors.append('2026 unfinished held DML guard, row no-loss, or genuine signer missing: '+fragment)
if not ('if title == \'Production schema validation request: Atlas held obsolete 2026 unfinished retirement\':' in workflow
        and 'test "$(git -C candidate rev-parse HEAD)" = "a6c1522ea5cc154ae13dd4f872bc7251337f69e9"' in workflow
        and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121184327_atlas_obsolete_2026_unfinished_retirement_v1.sql" ]]' in harness):
    errors.append('Unfinished retirement requires exact owner request, candidate SHA and local DML identity')
if not (harness.index('phase="trusted original C1 Work fixture before bounded old-queue synthetic data"') <
        harness.index('phase="candidate validation fixture application"') <
        harness.index('phase="held obsolete queue full-Atlas pre-retirement row baseline"') <
        harness.index('phase="candidate migration application"') <
        harness.index('phase="held obsolete queue exact four source-capacity tables and all-other-Atlas-row conservation"') <
        harness.index('phase="signed local prerequisite owner/worker authority, history and concurrent cycle proof"')):
    errors.append('Unfinished retirement must be fixture->730-table before->exact DML->730-table bounded compare->signed Work')


# Independent TEST-ONLY admission of the source-positive V2 prerequisite fix.
# The V1 versioned release stays immutable and is not authorized for retry.
for fragment in (
    'Production schema validation request: Atlas held obsolete 2026 prerequisite-safe retirement V2',
    'atlas_obsolete_2026_unfinished_retirement_prereq_guard_clone_only_v2',
    'held-obsolete-unfinished-prereq-v2',
    '6ed2978f7b79da1ffdb5dff096375c016f0a987d',
    'candidates/atlas/atlas_obsolete_2026_unfinished_retirement_prereq_guard_v2/',
    '7d8d56797f553618b1b6fff73feddf464f394878',
    '26ec0ece68dccb5d9d966a20ecf30dcbf2fc7f32',
    '1a539dae9781ca6524abbbfd3f45ce96951e4141',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held obsolete 2026 unfinished retirement proof required',
):
    if fragment not in workflow:
        errors.append('V2 source-positive protected owner/custody admission missing: '+fragment)
for fragment in (
    'atlas_obsolete_2026_unfinished_retirement_prereq_guard_clone_only_v2',
    '7d8d56797f553618b1b6fff73feddf464f394878',
    '26ec0ece68dccb5d9d966a20ecf30dcbf2fc7f32',
    '1a539dae9781ca6524abbbfd3f45ce96951e4141',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    'a6dbf950b689505babe33811f421add9db2a742d',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'obsolete_unfinished_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
):
    if fragment not in harness:
        errors.append('V2 original 730-table/canonical Work/signed C1 proof missing: '+fragment)
if not ("if title == 'Production schema validation request: Atlas held obsolete 2026 prerequisite-safe retirement V2':" in workflow
       and 'test "$(git -C candidate rev-parse HEAD)" = "6ed2978f7b79da1ffdb5dff096375c016f0a987d"' in workflow
       and 'atlas_obsolete_2026_unfinished_retirement_prereq_guard_clone_only_v2[.]sql$' in harness):
    errors.append('V2 must preserve exact owner, immutable source SHA and local disposable admission')


# Independent TEST-ONLY admission of the actual internal/external chain V3.
# The V1 versioned release stays immutable and is not authorized for retry.
for fragment in (
    'Production schema validation request: Atlas held obsolete 2026 prerequisite-chain retirement V3',
    'atlas_obsolete_2026_unfinished_retirement_prereq_chain_clone_only_v3',
    'held-obsolete-unfinished-chain-v3',
    '1b966a47d3cbb3672a0deb47c93c1a6aab9d0460',
    'candidates/atlas/atlas_obsolete_2026_unfinished_retirement_prereq_chain_v3/',
    '12bc33affcd9a57eba4d19e332a010588f2b22cb',
    '8e4ed1f4e10b178bdd9afdf25a5b42445e22f1d0',
    '1a96988eef4bffd515e03be9d5c918ed08641faf',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'a6dbf950b689505babe33811f421add9db2a742d',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'Exact owner-held obsolete 2026 unfinished retirement proof required',
):
    if fragment not in workflow:
        errors.append('V3 source-positive chain protected owner/custody admission missing: '+fragment)
for fragment in (
    'atlas_obsolete_2026_unfinished_retirement_prereq_chain_clone_only_v3',
    '12bc33affcd9a57eba4d19e332a010588f2b22cb',
    '8e4ed1f4e10b178bdd9afdf25a5b42445e22f1d0',
    '1a96988eef4bffd515e03be9d5c918ed08641faf',
    'bed62188f2e6ab3d8540c317e562c631b0f5bd0f',
    'a6dbf950b689505babe33811f421add9db2a742d',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'eb3bbfb45848a7fca90cc503e153f1451d8d7471',
    '1b82e698705e473280f1fc55b0e762bce243effb',
    'obsolete_unfinished_retirement_proof=true',
    'signed_work_prerequisite_probe=true',
):
    if fragment not in harness:
        errors.append('V3 original 730-table/canonical Work/signed C1 proof missing: '+fragment)
if not ("if title == 'Production schema validation request: Atlas held obsolete 2026 prerequisite-chain retirement V3':" in workflow
       and 'test "$(git -C candidate rev-parse HEAD)" = "1b966a47d3cbb3672a0deb47c93c1a6aab9d0460"' in workflow
       and 'atlas_obsolete_2026_unfinished_retirement_prereq_chain_clone_only_v3[.]sql$' in harness):
    errors.append('V3 must preserve exact owner, immutable source SHA and local disposable admission')


# New canonical Atlas V2 must take precisely the same source-positive,
# full 730-table PRE1 conservation, and genuine C1 signed proof as the held
# clone-only V2. An unpinned version must not silently take generic checks.
if not (
    '20261121194446_atlas_obsolete_2026_unfinished_retirement_prereq_guard_v2.sql' in harness
    and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_prereq_guard_clone_only_v2[.]sql$ || "$(basename "$candidate_migration")" == "20261121194446_atlas_obsolete_2026_unfinished_retirement_prereq_guard_v2.sql" ]]' in harness
    and '7d8d56797f553618b1b6fff73feddf464f394878' in harness
    and '26ec0ece68dccb5d9d966a20ecf30dcbf2fc7f32' in harness
    and '1a539dae9781ca6524abbbfd3f45ce96951e4141' in harness
    and 'bed62188f2e6ab3d8540c317e562c631b0f5bd0f' in harness
    and 'obsolete_unfinished_retirement_proof=true' in harness
    and 'signed_work_prerequisite_probe=true' in harness
):
    errors.append('Canonical 20261121194446 V2 must use original hash-pinned source-positive 730-table/signed proof')



# Generated canonical V3 is explicitly bound to the SAME original
# source-positive 730-table full-row proof and genuine signed actor acceptance.
# A different/new migration basename must NEVER inherit generic weaker checks.
if not (
    '20261121204646_atlas_obsolete_2026_unfinished_retirement_prereq_chain_v3.sql' in harness
    and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_obsolete_2026_unfinished_retirement_prereq_chain_clone_only_v3[.]sql$ || "$(basename "$candidate_migration")" == "20261121204646_atlas_obsolete_2026_unfinished_retirement_prereq_chain_v3.sql" ]]' in harness
    and '12bc33affcd9a57eba4d19e332a010588f2b22cb' in harness
    and '8e4ed1f4e10b178bdd9afdf25a5b42445e22f1d0' in harness
    and '1a96988eef4bffd515e03be9d5c918ed08641faf' in harness
    and 'bed62188f2e6ab3d8540c317e562c631b0f5bd0f' in harness
    and 'obsolete_unfinished_retirement_proof=true' in harness
    and 'signed_work_prerequisite_probe=true' in harness
):
    errors.append('Canonical 20261121204646 V3 must use original exact source-positive 730-table/signed proof')



# NEW exact governed five-live-consumer canonical version uses the ORIGINAL
# signed owner/worker/outsider/concurrency and all-730-Atlas-row proof.
# No version outside this exact allowlist may silently receive generic checks.
if not (
    '20261121211411_atlas_legacy_queue_five_live_consumer_decoupling_v1.sql' in harness
    and 'if [[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_legacy_queue_live_consumer_decoupling_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121211411_atlas_legacy_queue_five_live_consumer_decoupling_v1.sql" ]]' in harness
    and 'd62d42837f4a36e7ba0ded4bf4b8c29f948488fa' in harness
    and '7d3b3ff7c7951405b823b3a2a25f3ef4c087832c' in harness
    and '766ab2b69c53796ca6aa892d57a1188fab799bc8' in harness
    and 'a6dbf950b689505babe33811f421add9db2a742d' in harness
    and 'eb3bbfb45848a7fca90cc503e153f1451d8d7471' in harness
    and '1b82e698705e473280f1fc55b0e762bce243effb' in harness
    and 'orphan_queue_retirement_proof=true' in harness
    and 'signed_work_prerequisite_probe=true' in harness
):
    errors.append('Canonical 20261121211411 must use original hash-pinned signed 730-table five-consumer proof')



# Generated exact Atlas five-consumer package intentionally has no duplicated
# fixture file. Main's ORIGINAL frozen signed Work fixture is the only
# permitted input to the immutable signed 730-table clone, after SHA pinning.
for fragment in (
    'if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261121211411" ]]; then',
    '694bb5e6b7f9a452cffa5343ffd1c0e1063cc52a',
    'd62d42837f4a36e7ba0ded4bf4b8c29f948488fa',
    '7d3b3ff7c7951405b823b3a2a25f3ef4c087832c',
    'validation/fixtures/20261022182439_atlas_work_item_prerequisites_v1.sql',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    'fixtures=("$trusted_fixture")',
):
    if fragment not in workflow:
        errors.append('Exact five-consumer canonical immutable trusted fixture admission missing: '+fragment)



# HELD two-function serial orphan requires the original frozen signed C1
# source before the fictional 97-row queue data; no second identity system.
# This is a strict local-only test-phase ordering fix, not migration authority.
for fragment in (
    'phase="trusted original C1 Work fixture before historical owner queue data"',
    'owner-queue-original-signed-c1-fixture.log',
    '766ab2b69c53796ca6aa892d57a1188fab799bc8',
    '19981823e3d6e7da8a82b5d609fb1558e38c4251',
    'a5a23c42557bf6913321689fb9853afb57ff2c0e',
    'orphan_queue_retirement_proof',
    'Refuse C1 pre-load without exact original Work fixture, immutable candidate, and local-only database',
):
    if fragment not in harness:
        errors.append('Original immutable C1 preload source gate absent for held owner-completion orphan: '+fragment)
if not (
    harness.index('phase="trusted original C1 Work fixture before historical owner queue data"')
    < harness.index('phase="candidate validation fixture application"')
    < harness.index('phase="orphan backfill local all-Atlas-row baseline"')
    < harness.index('phase="candidate migration application"')
):
    errors.append('Original C1 must precede historical test data and full-row baseline before candidate')


# One NEW generated two-function canonical version, exact source / fixture /
# postconditions hashes, same frozen C1 signed and full 730-table proof.
# This is only test admission. It does not weaken old held source gates or
# grant approval to release any generated migration to production.
if not (
    'if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261121225626" ]]; then' in workflow
    and 'efedc90e4186349f7c7b904fc14344bdc86e7206' in workflow
    and '20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql' in workflow
    and 'a5a23c42557bf6913321689fb9853afb57ff2c0e' in workflow
    and '19981823e3d6e7da8a82b5d609fb1558e38c4251' in workflow
    and 'a3dbc4fe6f5db230ed3dbf071e514ff06487e807' in workflow
    and '766ab2b69c53796ca6aa892d57a1188fab799bc8' in workflow
    and 'a6dbf950b689505babe33811f421add9db2a742d' in workflow
    and 'eb3bbfb45848a7fca90cc503e153f1451d8d7471' in workflow
    and '1b82e698705e473280f1fc55b0e762bce243effb' in workflow
    and '[[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_owner_completion_queue_orphan_branch_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql" ]]' in harness
    and harness.count('[[ "$(basename "$candidate_migration")" =~ ^[0-9]{14}_atlas_owner_completion_queue_orphan_branch_clone_only_v1[.]sql$ || "$(basename "$candidate_migration")" == "20261121225626_atlas_owner_completion_queue_dead_branch_retirement_v1.sql" ]]') == 2
    and 'orphan_queue_retirement_proof=true' in harness
    and 'signed_work_prerequisite_probe=true' in harness
    and 'owner-queue-original-signed-c1-fixture.log' in harness
    and 'orphan-local-row-integrity-after-candidate.log' in harness
):
    errors.append('Exact 20261121225626 must retain original frozen C1 signer, 730-table full-row proof and hash-pinned two-function retirement')

# Exact new 20261121235035 Anna serial orphan source only. This does not
# broaden the previous immutable owner-completion / original C1 proof.
new_anna_name = '20261121235035_atlas_anna_orphaned_serial_effect_retirement_v1.sql'
new_anna_sha = '8c181e8190bba385392f3679554fc83228d9f6f3'
new_anna_blobs = (
    '7fb7c4bdefc735484448fa3845e0125a2ffaa4eb',
    '5ddc096700e726fd9681df0067f23576b848f124',
    '5de235c8b83d3bfa4504aa9f3c28948cbd5848c9',
)
for fragment in (new_anna_name, new_anna_sha, *new_anna_blobs,
                 'if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261121235035" ]]; then',
                 'test "${#fixtures[@]}" = 1',
                 'test "${#validations[@]}" = 1'):
    if fragment not in workflow:
        errors.append('Exact immutable Anna orphan package workflow gate absent: ' + fragment)
for fragment in (new_anna_name, *new_anna_blobs,
                 'orphan_queue_retirement_proof=true',
                 'signed_work_prerequisite_probe=true',
                 'anna-orphan-original-signed-c1-fixture.log',
                 "Refuse Anna orphan clone without exact generated source, original signed fixture and all-row no-loss tests.",
                 "Refuse new Anna orphan C1 preload without immutable source, synthetic fixture and local-only PostgreSQL"):
    if fragment not in harness:
        errors.append('Exact Anna orphan protected clone proof absent: ' + fragment)
if not (
    workflow.count('if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261121235035" ]]; then') == 1
    and harness.count('if [[ "$(basename "$candidate_migration")" == "' + new_anna_name + '" ]]; then') == 1
    and harness.count('[[ "$(basename "$candidate_migration")" == "' + new_anna_name + '" ]]') == 2
    and harness.index('anna-orphan-original-signed-c1-fixture.log')
        < harness.index('phase="candidate validation fixture application"')
        < harness.index('phase="orphan backfill local all-Atlas-row baseline"')
        < harness.index('phase="orphan backfill local all-Atlas-row unchanged after exact deletion"')
    and 'scripts/validate-atlas-access03c-pre1-local-row-integrity.py' in harness
    and 'scripts/validate-atlas-work-prerequisite-signed-http.py' in harness
):
    errors.append('Anna orphan must reuse exact protected C1, signed Work and full Atlas base-row conservation proof')

# One immutable new legacy Task hardcoded policy removal candidate only.
# Retain the original signed C1 and all-Atlas-row/negative test contract.
legacy_task_version = '20261122003235'
legacy_task_name = '20261122003235_atlas_legacy_person_specific_task_trigger_retirement_v1.sql'
legacy_task_sha = '4406fd7e9a6179fa225b33ba663d50ec812a3201'
legacy_task_blobs = (
    'fade2e58598e4e32e49f9e84f481c54b3611ad9f',
    '60ac062da84b34be539ede296dda5434aa58d061',
    'b720cc35fa78f3626a4a0f2c8d3138c7557cdea6',
)
for fragment in (legacy_task_version, legacy_task_name, legacy_task_sha, *legacy_task_blobs,
                 'if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261122003235" ]]; then',
                 'test "${#fixtures[@]}" = 1',
                 'test "${#validations[@]}" = 1'):
    if fragment not in workflow:
        errors.append('Exact legacy Task immutable workflow gate missing: ' + fragment)
for fragment in (legacy_task_name, *legacy_task_blobs,
                 'orphan_queue_retirement_proof=true',
                 'signed_work_prerequisite_probe=true',
                 'person-task-original-signed-c1-fixture.log',
                 'Refuse person-specific legacy Task trigger clone unless exact source, original signer, fictional C1 source and full-row proof.',
                 'Refuse exact Task trigger C1 pre-load without fixed source and local-only PostgreSQL.'):
    if fragment not in harness:
        errors.append('Exact legacy Task protected C1/full-row signer missing: ' + fragment)
if not (
    workflow.count('if [[ "$RELEASE_LANE" == "atlas" && "$MIGRATION_VERSION" == "20261122003235" ]]; then') == 1
    and harness.count('if [[ "$(basename "$candidate_migration")" == "' + legacy_task_name + '" ]]; then') == 1
    and harness.count('[[ "$(basename "$candidate_migration")" == "' + legacy_task_name + '" ]]') == 2
    and harness.index('person-task-original-signed-c1-fixture.log')
        < harness.index('phase="candidate validation fixture application"')
        < harness.index('phase="orphan backfill local all-Atlas-row baseline"')
        < harness.index('phase="orphan backfill local all-Atlas-row unchanged after exact deletion"')
    and 'scripts/validate-atlas-access03c-pre1-local-row-integrity.py' in harness
    and 'scripts/validate-atlas-work-prerequisite-signed-http.py' in harness
    and 'scripts/validate-atlas-c1-signed-http.py' in harness
):
    errors.append('Legacy Task trigger deletion must use original protected C1, signed and all-Atlas-row no-loss machinery')

if errors:
    print('Production schema validation contract FAILED:')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('Production schema validation contract passed: owner-only main workflow, immutable candidate SHA, dependency-complete schema plus custom-role production reads, immutable candidate fixtures/postconditions, DML-only local fixture setup, one local/CI harness, baseline-aware Atlas lint deltas, durable failure artifacts, local-only candidate execution, and no production DDL path.')
PY

#!/usr/bin/env python3
"""HELD C2 signed read hook for one disposable copy of Noel's canonical validator.

This code never runs a database, uses protected credentials, alters the source
validator or authorizes an issue. The future trusted workflow has to verify all
immutable source heads/blobs and owner authority before using this helper.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

CANONICAL_VALIDATOR_BLOB = "39f526cd8671f0aadbaab61c66dfc4971ef52131"
C2_FUNCTION_BASELINE_MD5 = "ffcf0b1c8ab49b4d456037aa5f1147cf"
MARKER = 'phase="candidate domain schema lint"\n'

HOOK = """# Exact selected-native-Ledger C2 source-only *disposable* signed matrix.
# C1 has already run via the canonical signed_http_probe path. No release.
phase="held C2 exact native Ledger source proof signed matrix"
test -n "${C2_TEST_ROOT:-}" && test -n "${C2_SOURCE_ROOT:-}"
test -s "$C2_TEST_ROOT/tests/uniops_c2_case_work_disposable_fixture_held.sql"
test -s "$C2_TEST_ROOT/scripts/validate-atlas-c2-case-work-signed-http.py"
test -s "$C2_SOURCE_ROOT/docs/review/uniops_c2_native_ledger_requirement_work_scope_held/proposed_function_review_only.sql"
# Refuse unexpected currently-installed source. This is a clone-only check
# using the unmodified, exact C1 owner RPC baseline, before #2668 install.
test "$(psql "$database_url" -X -A -t -v ON_ERROR_STOP=1 -c "select md5(pg_get_functiondef('atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure))")" = 'ffcf0b1c8ab49b4d456037aa5f1147cf'
# Never mutate the actual protected schema source: all psql connections below
# must be the validator's generated disposable local database URL.
[[ "$database_url" =~ ^postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres$ ]]
PGOPTIONS='-c uni_ops.disposable_clone=true' psql "$database_url" -X -v ON_ERROR_STOP=1 \\
  -f "$C2_SOURCE_ROOT/docs/review/uniops_c2_native_ledger_requirement_work_scope_held/proposed_function_review_only.sql" \\
  >"$artifacts_dir/held-c2-disposable-function.log" 2>&1
PGOPTIONS='-c uni_ops.disposable_clone=true' psql "$database_url" -X -v ON_ERROR_STOP=1 \\
  -f "$C2_TEST_ROOT/tests/uniops_c2_case_work_disposable_fixture_held.sql" \\
  >"$artifacts_dir/held-c2-six-original-fixture.log" 2>&1
PGOPTIONS='-c uni_ops.disposable_clone=true' python3 "$C2_TEST_ROOT/scripts/validate-atlas-c2-case-work-signed-http.py" \\
  --db-url "$database_url" \\
  --expected-function-sql "$C2_SOURCE_ROOT/docs/review/uniops_c2_native_ledger_requirement_work_scope_held/proposed_function_review_only.sql" \\
  --output "$artifacts_dir/held-c2-signed-private-receipt.txt" \\
  >"$artifacts_dir/held-c2-signed-private.log" 2>&1
test -s "$artifacts_dir/held-c2-signed-private-receipt.txt"
grep -q '^C2 HELD synthetic signed owner, source-verified' "$artifacts_dir/held-c2-signed-private-receipt.txt"
echo 'PASS C2 ephemeral signed local test (private results withheld)'
# No raw SQL, JWT, cloned schema or fixture rows may be published.
"""


def github_blob_sha(content: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(content)).encode() + b"\\0" + content).hexdigest()


def build_copy(original: str) -> str:
    if github_blob_sha(original.encode()) != CANONICAL_VALIDATOR_BLOB:
        raise ValueError("canonical validator source changed; refuse unreviewed hook")
    if original.count(MARKER) != 1:
        raise ValueError("canonical signed-test placement changed")
    if original.count('signed_http_probe=true\n') != 1:
        raise ValueError("canonical C1 true signed path not found")
    if original.count('python3 "$repo_root/scripts/validate-atlas-c1-signed-http.py"') != 1:
        raise ValueError("genuine local C1 signer path not found")
    if original.count('if [ "$signed_http_probe" = true ] || [ "$signed_date_http_probe" = true ] ||') != 1:
        raise ValueError("C1 local Auth/REST startup source changed")
    if 'held C2 exact native Ledger source proof signed matrix' in original:
        raise ValueError("duplicate C2 hook refused")
    before, after = original.split(MARKER)
    if before.find('python3 "$repo_root/scripts/validate-atlas-c1-signed-http.py"') < 0:
        raise ValueError("C1 signed owner action must precede C2")
    return before + HOOK + "\n" + MARKER + after


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("disposable_validator_copy")
    args = parser.parse_args()
    path = Path(args.disposable_validator_copy)
    if path.is_symlink() or not path.is_file():
        raise SystemExit("regular disposable validator copy required")
    source = path.read_text(encoding="utf-8")
    try:
        updated = build_copy(source)
    except ValueError as exc:
        raise SystemExit("REFUSE C2 hook: " + str(exc))
    path.write_text(updated, encoding="utf-8")
    print("PASS one C2 test-only hook on one canonical validator COPY; no database run")


if __name__ == "__main__":
    main()

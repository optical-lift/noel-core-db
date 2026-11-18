#!/usr/bin/env python3
"""Source-pinned U2F hook into a DISPOSABLE COPY of Noel's existing signed clone.

This installer NEVER runs the signed test, accesses a database, dispatches a
workflow, or updates the canonical validator. It edits one existing copy ONLY,
inside a temporary scratch folder. An independently approved owner-protected
controller is required to make the scratch copy and run it.
"""
from pathlib import Path
import argparse
import hashlib
import os
import re

EXPECTED_CANONICAL_HARNESS_GIT_BLOB="a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5"
ANCHOR=(
    'if [ "$signed_ledger_reciprocal_probe" = true ]; then\n'
    '  phase="signed reciprocal Ledger roots, private intake and Person identity"'
)
U2F_ROOT="candidates/atlas/uni_ops_u2f_universal_delegated_command_v1"
HOOK=r'''if [ "$signed_ledger_reciprocal_probe" = true ]; then
  # U2F source-only opt-in: this exact hook may appear only in an
  # owner-authorized, disposable COPY of the canonical signed-clone validator.
  # This runs BEFORE the existing reciprocal Ledger test (which revokes B).
  phase="U2F separately authorized signed-review-only clone check"
  test "$database_url" = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
  test -s "$repo_root/U2F_ROOT/06_signed_native_root_lifecycle_held.sql"
  test -s "$repo_root/U2F_ROOT/08_signed_clone_only_rpc_bridge_held.sql"
  test -s "$repo_root/U2F_ROOT/pg17/validate_u2f_genuine_signed_clone_held.py"

  # These are LOCAL-CLONE-ONLY permissions, not a production migration.
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/U2F_ROOT/06_signed_native_root_lifecycle_held.sql" \
    >"$artifacts_dir/u2f-private-install.log" 2>&1
  PGOPTIONS="-c uniops.disposable_signed=u2f_owner_authorized_clone_only_v1" \
    psql "$database_url" -X -v ON_ERROR_STOP=1 \
      -f "$repo_root/U2F_ROOT/08_signed_clone_only_rpc_bridge_held.sql" \
      >"$artifacts_dir/u2f-local-transport-install.log" 2>&1

  python3 "$repo_root/U2F_ROOT/pg17/validate_u2f_genuine_signed_clone_held.py" \
    --db-url "$database_url" \
    --output "$artifacts_dir/u2f-signed-only-verdict.txt" \
    >"$artifacts_dir/u2f-signed-private.log" 2>&1
  test -s "$artifacts_dir/u2f-signed-only-verdict.txt"
  grep -qx 'U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS' \
    "$artifacts_dir/u2f-signed-only-verdict.txt"
fi

if [ "$signed_ledger_reciprocal_probe" = true ]; then
  phase="signed reciprocal Ledger roots, private intake and Person identity"'''.replace("U2F_ROOT", "candidates/atlas/uni_ops_u2f_universal_delegated_command_v1")

def blob_id(data: bytes) -> str:
    return hashlib.sha1(b"blob "+str(len(data)).encode("ascii")+b"\0"+data).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--copy",required=True)
    args=parser.parse_args()
    source=Path(__file__).resolve().parents[4]/"scripts/validate-production-schema-clone.sh"
    target=Path(args.copy)
    if target.is_symlink() or not target.is_file() or target.name!=source.name:
        raise SystemExit("STOP: regular disposable validator COPY required")
    if target.resolve()==source:
        raise SystemExit("STOP: may not modify canonical validator")
    temp=os.environ.get("RUNNER_TEMP")
    if not temp or not Path(temp).is_dir():
        raise SystemExit("STOP: owner-controlled RUNNER_TEMP required")
    try:
        target.resolve().relative_to(Path(temp).resolve())
    except ValueError:
        raise SystemExit("STOP: copy must live inside controlled runner temporary folder")
    if target.parent.name!="u2f-scratch":
        raise SystemExit("STOP: one dedicated U2F scratch directory required")
    original=target.read_bytes()
    if blob_id(original)!=EXPECTED_CANONICAL_HARNESS_GIT_BLOB:
        raise SystemExit("STOP: trusted canonical harness source blob drift")
    if source.is_file() and blob_id(source.read_bytes())!=EXPECTED_CANONICAL_HARNESS_GIT_BLOB:
        raise SystemExit("STOP: source repository canonical harness drift")
    content=original.decode("utf-8")
    if content.count(ANCHOR)!=1:
        raise SystemExit("STOP: missing/ambiguous exact signed reciprocal phase anchor")
    if "U2F separately authorized signed-review-only clone check" in content:
        raise SystemExit("STOP: hook already installed")
    content=content.replace(ANCHOR,HOOK,1)
    if content.count("U2F separately authorized signed-review-only clone check")!=1:
        raise SystemExit("STOP: U2F hook occurrence not exactly one")
    if content.count('phase="signed reciprocal Ledger roots, private intake and Person identity"')!=1:
        raise SystemExit("STOP: source reciprocal signed test accidentally changed")
    target.write_text(content,encoding="utf-8")
    print("U2F_TEMPORARY_CLONE_HOOK_SOURCE=PASS")
    print("CANONICAL_VALIDATOR_MODIFIED=NO")
    print("SIGNED_TEST_EXECUTED=NO")
    print("PRODUCTION_MUTATION=NONE")

if __name__=="__main__":
    main()

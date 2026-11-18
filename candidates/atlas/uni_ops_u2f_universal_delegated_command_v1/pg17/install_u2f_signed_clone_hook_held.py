#!/usr/bin/env python3
"""PINNED, TWO-POINT U2F hook in a TEMPORARY current-schema signed clone only.

The existing reciprocal signed test creates the four genuine GoTrue identity
records before it later ends the second fictional root. U2F must execute AFTER
that once-only identity setup, BEFORE the original reciprocal test. The installer
patches only two source-checked disposable copies. It never changes main or
the canonical runner, starts a clone, authorizes an owner, or runs a test.
"""
from pathlib import Path
import argparse
import hashlib
import os

CANONICAL_HARNESS_BLOB="a965fcca2cb5e1c44f255eba2fa24cca2a4d21c5"
CANONICAL_RECIPROCAL_BLOB="ba2be33fa479e7d24523c10eaee3bbcf12918b3b"
ROOT="candidates/atlas/uni_ops_u2f_universal_delegated_command_v1"

SHELL_ANCHOR=(
    'if [ "$signed_ledger_reciprocal_probe" = true ]; then\n'
    '  phase="signed reciprocal Ledger roots, private intake and Person identity"'
)
SHELL_HOOK=r'''if [ "$signed_ledger_reciprocal_probe" = true ]; then
  # The original signed reciprocal probe is NOT replaced or skipped.
  # Install only U2F review-only private source+local bridge in this clone.
  phase="U2F separately authorized signed-review-only clone setup"
  # Noel's canonical clone picks an isolated random local port per run.
  # Require its exact chosen localhost URL and bounded ephemeral port range.
  [[ "$local_database_port" =~ ^[0-9]{5}$ ]]
  (( local_database_port >= 38000 && local_database_port < 61000 ))
  test "$database_url" = "postgresql://postgres:postgres@127.0.0.1:${local_database_port}/postgres"
  test -s "$repo_root/U2F_ROOT/06_signed_native_root_lifecycle_held.sql"
  test -s "$repo_root/U2F_ROOT/08_signed_clone_only_rpc_bridge_held.sql"
  test -s "$repo_root/U2F_ROOT/pg17/validate_u2f_genuine_signed_clone_held.py"
  psql "$database_url" -X -v ON_ERROR_STOP=1 \
    -f "$repo_root/U2F_ROOT/06_signed_native_root_lifecycle_held.sql" \
    >"$artifacts_dir/u2f-private-install.log" 2>&1
  PGOPTIONS="-c uniops.disposable_signed=u2f_owner_authorized_clone_only_v1" \
    psql "$database_url" -X -v ON_ERROR_STOP=1 \
      -f "$repo_root/U2F_ROOT/08_signed_clone_only_rpc_bridge_held.sql" \
      >"$artifacts_dir/u2f-local-transport-install.log" 2>&1
fi

if [ "$signed_ledger_reciprocal_probe" = true ]; then
  phase="signed reciprocal Ledger roots, private intake and Person identity"'''.replace("U2F_ROOT",ROOT)

SHELL_VERDICT_ANCHOR=(
    '  grep -q \'^PASS\' "$artifacts_dir/signed-ledger-reciprocal-summary.txt"\n'
    'fi'
)
SHELL_VERDICT=(
    '  grep -q \'^PASS\' "$artifacts_dir/signed-ledger-reciprocal-summary.txt"\n'
    '  test -s "$artifacts_dir/u2f-signed-only-verdict.txt"\n'
    '  grep -qx \'U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS\' \\\n'
    '    "$artifacts_dir/u2f-signed-only-verdict.txt"\n'
    'fi'
)

RECIPROCAL_ANCHOR='    base.setup_auth(a.db_url)\n    tokens={}'
RECIPROCAL_HOOK=r'''    base.setup_auth(a.db_url)
    # U2F reuses these exact newly initialized synthetic GoTrue identities.
    # Do not call C1 setup_auth twice and do not reuse other issue approvals.
    # Review-only SQL was installed by the disposable shell hook.
    import sys as _sys
    _u2f_runner=HERE.parent/"U2F_ROOT/pg17/validate_u2f_genuine_signed_clone_held.py"
    _u2f_result=Path(a.output).with_name("u2f-signed-only-verdict.txt")
    _u2f_private=Path(a.output).with_name("u2f-signed-private.log")
    with _u2f_private.open("w",encoding="utf8") as _private:
        _u2f_run=subprocess.run(
            [_sys.executable,str(_u2f_runner),"--db-url",a.db_url,
             "--output",str(_u2f_result),"--reuse-existing-signed-auth"],
            stdout=_private,stderr=subprocess.STDOUT,check=False)
    must(_u2f_run.returncode==0,"U2F genuinely signed review-only clone check failed")
    must(_u2f_result.is_file() and
         "U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS" in _u2f_result.read_text(),
         "U2F signed review receipt absent or unsuccessful")
    tokens={}'''.replace("U2F_ROOT",ROOT)

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--copy",required=True)
    p.add_argument("--reciprocal-copy",required=True)
    a=p.parse_args()
    repo=Path(__file__).resolve().parents[4]
    canonical_harness=repo/"scripts/validate-production-schema-clone.sh"
    canonical_reciprocal=repo/"scripts/validate-atlas-ledger-reciprocal-signed-http.py"
    target=Path(a.copy)
    reciprocal_target=Path(a.reciprocal_copy)
    temp=os.environ.get("RUNNER_TEMP")
    if not temp or not Path(temp).is_dir():
        raise SystemExit("STOP: owner-controlled RUNNER_TEMP required")
    base=Path(temp).resolve()
    for dest in (target,reciprocal_target):
        if not dest.is_file() or dest.is_symlink():
            raise SystemExit("STOP: source-checked regular disposable COPY required")
        try:
            dest.resolve().relative_to(base)
        except ValueError:
            raise SystemExit("STOP: COPY must be inside the runner temporary area")
    if target.resolve()==canonical_harness.resolve() and not canonical_harness.resolve().is_relative_to(base):
        raise SystemExit("STOP: may not modify canonical validator")
    if reciprocal_target.resolve()==canonical_reciprocal.resolve() and not canonical_reciprocal.resolve().is_relative_to(base):
        raise SystemExit("STOP: may not modify canonical signed reciprocal test")
    if target.parent.name!="u2f-scratch" or target.name!=canonical_harness.name:
        raise SystemExit("STOP: one dedicated U2F scratch validator required")
    if reciprocal_target.name!=canonical_reciprocal.name or reciprocal_target.parent.name!="scripts":
        raise SystemExit("STOP: exact scratch reciprocal test script required")
    source_bytes=target.read_bytes()
    reciprocal_bytes=reciprocal_target.read_bytes()
    if git_blob(source_bytes)!=CANONICAL_HARNESS_BLOB or git_blob(canonical_harness.read_bytes())!=CANONICAL_HARNESS_BLOB:
        raise SystemExit("STOP: trusted canonical harness source blob drift")
    if git_blob(reciprocal_bytes)!=CANONICAL_RECIPROCAL_BLOB or git_blob(canonical_reciprocal.read_bytes())!=CANONICAL_RECIPROCAL_BLOB:
        raise SystemExit("STOP: trusted original signed reciprocal source blob drift")
    source=source_bytes.decode("utf-8")
    reciprocal=reciprocal_bytes.decode("utf-8")
    if source.count(SHELL_ANCHOR)!=1 or source.count(SHELL_VERDICT_ANCHOR)!=1:
        raise SystemExit("STOP: unexpected canonical signed-clone anchor")
    if reciprocal.count(RECIPROCAL_ANCHOR)!=1:
        raise SystemExit("STOP: missing/ambiguous original auth setup boundary")
    source=source.replace(SHELL_ANCHOR,SHELL_HOOK,1).replace(SHELL_VERDICT_ANCHOR,SHELL_VERDICT,1)
    reciprocal=reciprocal.replace(RECIPROCAL_ANCHOR,RECIPROCAL_HOOK,1)
    if source.count("U2F separately authorized signed-review-only clone setup")!=1:
        raise SystemExit("STOP: U2F setup not exactly one")
    if source.count('phase="signed reciprocal Ledger roots, private intake and Person identity"')!=1:
        raise SystemExit("STOP: reciprocal signed shell probe changed")
    if reciprocal.count("    base.setup_auth(a.db_url)")!=1 or reciprocal.count("    tokens={}")!=1:
        raise SystemExit("STOP: reciprocal auth/identity matrix changed")
    # Both source copies are validated BEFORE either test-only copy is written.
    target.write_text(source,encoding="utf-8")
    reciprocal_target.write_text(reciprocal,encoding="utf-8")
    print("U2F_TEMPORARY_CLONE_HOOK_SOURCE=PASS")
    print("CANONICAL_VALIDATOR_MODIFIED=NO")
    print("CANONICAL_RECIPROCAL_TEST_MODIFIED=NO")
    print("U2F_AUTH_BOOTSTRAP_DUPLICATED=NO")
    print("SIGNED_TEST_EXECUTED=NO")
    print("PRODUCTION_MUTATION=NONE")

if __name__=="__main__":
    main()

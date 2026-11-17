#!/usr/bin/env python3
"""Attach one exact fictional browser readback to a disposable P3 validator COPY.

The canonical validator and existing U2/U4/P3 signed tests are untouched.
This installer never reads production, creates Work or changes rights.
"""
from pathlib import Path
import sys

def stop(reason):
    raise SystemExit("HELD Atlas browser hook refused: "+reason)

if len(sys.argv)!=2:
    stop("one validator-copy path required")
path=Path(sys.argv[1])
if path.is_symlink() or not path.is_file():
    stop("ordinary disposable copy required")
raw=path.read_text(encoding="utf8")
marker='phase="candidate domain schema lint"\n'
anchor='phase="signed integrated U1B source and U2 accepted-first original"\n'
if (raw.count(marker)!=1 or raw.count(anchor)!=1 or
        raw.count("--u4-actual-followon")!=1 or
        raw.count("signed_accepted_first_probe=true")!=1 or
        raw.index(anchor)>=raw.index(marker)):
    stop("reviewed signed U2/U4 current harness drift")
if "ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK" in raw:
    stop("duplicate browser hook")
hook='''# HELD browser-only independent read after the actual signed U2/U4/P3.
# Nothing in this hook may be used to issue Work or a physical Result.
phase="Atlas fictional governor Done/outsider browser readback"
test "${ATLAS_BROWSER_FICTIONAL_ONLY:-}" = true
test -s "$repo_root/tests/run-uniops-atlas-browser-readback-local.sh"
bash "$repo_root/tests/run-uniops-atlas-browser-readback-local.sh" "$database_url" \\
  > "$artifacts_dir/uniops-atlas-browser-private.log" 2>&1
grep -qx 'PASS ATLAS_CI_GOVERNOR_EXACT_DONE_READBACK=PASS' \\
  "$artifacts_dir/uniops-atlas-browser-private.log"
grep -qx 'PASS ATLAS_CI_OUTSIDER_WORK_DENIAL=PASS' \\
  "$artifacts_dir/uniops-atlas-browser-private.log"

'''
path.write_text(raw.replace(marker,hook+marker,1),encoding="utf8")
print("PASS Atlas read-only browser hook attached only to local P3 copy")

#!/usr/bin/env python3
"""HELD SOURCE ONLY: swap ONE U4 first positive RPC for real native worker UI.

This module creates a new disposable test-driver copy. It cannot run that copy,
install DDL, use a database connection or authorize CI. A future separately
reviewed owner-gated workflow must pin both Noel and Atlas source and approve
inserting this hook *only* into the already isolated local clone test.

All negative permission/condition probes and idempotent replay stay in the
frozen U4 proof. The replaced positive response must be the actual browser
RPC response held in a private 0600 runner file. No fake Result receipt.
"""
import argparse
import hashlib
from pathlib import Path

FROZEN_SOURCE_BLOB = "2e180aa2363201e75ca0d717eeeddd5a708193ab"
FROZEN_FILE = "uniops_u2_qualified_actual_followon_held.py"
OUTPUT_FILE = "uniops_u2_qualified_actual_browser_local_only.py"
NEEDLE = '    status, response = call("worker")'
HEADER = 'import re\nfrom uuid import UUID\n'
GUARD = '''
import json
import os
import re as _re
import subprocess
from pathlib import Path as _Path

_BROWSER_STAGES=frozenset((
    "environment","auth","browser","notebook","work_row","work_focus",
    "physical_form","actual_rpc","receipt","ui_completed","private_receipt",
))

def _browser_positive_actual(db_url, work, payload):
    # This hook is callable only when the separately owner-gated, protected
    # disposable-clone runner specifically opts in. Not a generic U4 fallback.
    require(os.environ.get("ATLAS_NATIVE_WORKER_BROWSER_ACTUAL_ENABLED")=="true",
            "U4 native browser runner not authorized")
    require(local_only(db_url),"U4 probe requires a disposable loopback PG")
    require(valid_uuid(work),"U4 requires the exact existing canonical Work")
    root=_Path(__file__).resolve().parents[1]
    runner=root/"tests"/"run-uniops-native-worker-actual-local.sh"
    temp=os.environ.get("RUNNER_TEMP","")
    require(bool(temp) and _Path(temp).is_absolute(),
            "U4 native browser runner not authorized")
    private=_Path(temp)/"uniops-native-worker-actual-private.json"
    require(not private.exists() and not private.is_symlink(),
            "U4 native browser receipt preexisted")
    try:
        proc=subprocess.run(
            ["bash",str(runner),db_url,work,str(private)],
            capture_output=True,text=True,timeout=360,check=False,
        )
        safe_lines=(proc.stdout+"\\n"+proc.stderr).splitlines()
        stages=[m.group(1) for line in safe_lines
          if (m:=_re.fullmatch(r"ATLAS_NATIVE_WORKER_STAGE=([a-z_]+)",line))
          and m.group(1) in _BROWSER_STAGES]
        if proc.returncode!=0 or safe_lines.count(
                "PASS ATLAS_NATIVE_WORKER_PHYSICAL_ACTUAL=PASS")!=1:
            print("U4_NATIVE_WORKER_UI_STAGE="+
                  (stages[0] if len(stages)==1 else "unclassified"),flush=True)
            require(False,"U4 native worker physical Actual not verified")
        require(private.is_file() and not private.is_symlink(),
                "U4 native worker physical Actual not verified")
        receipt=json.loads(private.read_text(encoding="utf-8"))
        require(isinstance(receipt,dict)
                and receipt.get("workItemId")==work
                and valid_uuid(receipt.get("actionId"))
                and valid_uuid(receipt.get("workResultId"))
                and isinstance(receipt.get("receipt"),dict)
                and receipt["receipt"].get("workResultId")==receipt["workResultId"]
                and accepted_receipt(receipt["receipt"],work),
                "U4 native worker physical Actual not verified")
        # The true browser chose its action identity; replay MUST use exactly
        # that same action ID and the exact same typed physical payload.
        payload["p_action_id"]=receipt["actionId"]
        print("PASS U4_NATIVE_SIGNED_WORKER_BROWSER_ORIGIN=PASS",flush=True)
        return 200,receipt["receipt"]
    finally:
        private.unlink(missing_ok=True)
'''
REPLACEMENT = '    status, response = _browser_positive_actual(db_url, work, payload)'
MORE_DENIALS = '''    "U4 native browser runner not authorized": "native_browser_authorization_gate",
    "U4 native browser receipt preexisted": "native_browser_receipt_preexisting",
    "U4 native worker physical Actual not verified": "native_browser_result_gate",
'''
DENIAL_MARKER = 'U4_DENIAL_CLASSES = {\n'


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def prepare(data: bytes) -> bytes:
    if git_blob(data) != FROZEN_SOURCE_BLOB:
        raise ValueError("Refuse U4 driver from unreviewed source")
    source = data.decode("utf-8")
    if source.count(NEEDLE) != 1 or source.count(HEADER) != 1:
        raise ValueError("Cannot identify one frozen U4 worker positive")
    if source.count(DENIAL_MARKER) != 1 or "_browser_positive_actual" in source:
        raise ValueError("Cannot prove original U4 source integrity")
    result = source.replace(HEADER, HEADER + GUARD + "\n", 1)
    result = result.replace(DENIAL_MARKER, DENIAL_MARKER + MORE_DENIALS, 1)
    result = result.replace(NEEDLE, REPLACEMENT, 1)
    assert result.count(REPLACEMENT) == 1
    assert result.count('status, replay = call("worker")') == 1
    assert result.count('for actor in ("outsider","owner"):') == 1
    assert result.count('status, response = call("worker",invalid)') == 1
    compile(result, OUTPUT_FILE, "exec")
    return result.encode("utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    source = Path(args.source)
    output = Path(args.output)
    if source.name != FROZEN_FILE or output.name != OUTPUT_FILE:
        raise SystemExit("Refuse unexpected signed source/target name")
    if source.resolve() == output.resolve() or output.exists() or output.is_symlink():
        raise SystemExit("Refuse in-place or existing protected target")
    data = prepare(source.read_bytes())
    with output.open("xb") as target:
        target.write(data)
    print("PASS one browser-only U4 test copy, all frozen negatives and replay preserved")


if __name__ == "__main__":
    main()

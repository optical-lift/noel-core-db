#!/usr/bin/env python3
"""HELD SOURCE ONLY: opt-in signed historical cancellation in an ephemeral U4 COPY.

This prepares the EXACT frozen U2/U4 driver with a second, separately gated
historical retirement probe. It never invokes a signed test, SQL or network.
The source and signed sessions still belong to Noel's original test carrier.
Only write the resulting file under RUNNER_TEMP, never to the source checkout.
The separately principal-approved protected workflow must explicitly opt in.
"""
import argparse
import hashlib
import os
from pathlib import Path

DRIVER_BLOB = "09eeee925ebfa2cb64b1dea336688ba8076ef44d"
BRIDGE_BLOB = "f1a4eadb4d0199e8b4d9c1f17738675c281e249d"
COMPANION_BLOB = "79151f723e60b33410c760acef715155a53771f3"

ARG_ANCHOR = "    a=p.parse_args()\n"
ACTOR_ANCHOR = "    # A signed actor's existing JWT is not authority after session removal.\n"
RECEIPT_ANCHOR = "      u2_receipt+result_claim+\n"

ARG_PATCH = '''    p.add_argument("--historical-retirement-followon",action="store_true",
                   help="HELD: explicit governor historical cancel proof in local clone only")
    a=p.parse_args()
'''
ACTOR_PATCH = '''    history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=NOT_RUN\\n"
    if a.historical_retirement_followon:
        check(a.u4_actual_followon,
              "Historical gate must follow the separately signed U4 proof")
        hist_spec=importlib.util.spec_from_file_location(
            "held_governor_historical_retirement",
            ROOT/"tests"/"uniops_historical_retirement_signed_bridge_held.py")
        check(hist_spec is not None and hist_spec.loader is not None,
              "Exact held historical source bridge missing")
        hist=importlib.util.module_from_spec(hist_spec)
        hist_spec.loader.exec_module(hist)
        history_receipt=hist.prove(
            a.db_url,api,key,
            {"owner":owner,"worker":worker,"outsider":outsider,
             "no-seat":signed["no-seat"][0]},
            source_path=ROOT/"tests"/"validate-atlas-native-historical-retirement-signed-http.py",
            sql=sql,rpc=rpc,c1=base.c1)
        check(isinstance(history_receipt,str)
              and history_receipt.startswith(
                "PASS genuine signed governor historic retirement:"),
              "Genuine signed governor cancellation not established")
        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"

    # A signed actor's existing JWT is not authority after session removal.
'''

class HeldHookRefusal(RuntimeError):
    """Static source-only error. Do not echo untrusted source content."""


def git_blob(payload):
    return hashlib.sha1(
        b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    ).hexdigest()


def prepare(driver, bridge, companion):
    """Byte-pin original driver, already merged bridge and immutable companion."""
    for data, expected, label in (
        (driver, DRIVER_BLOB, "signed U4 driver"),
        (bridge, BRIDGE_BLOB, "historical bridge"),
        (companion, COMPANION_BLOB, "historical source companion"),
    ):
        if not isinstance(data, bytes) or git_blob(data) != expected:
            raise HeldHookRefusal("Immutable " + label + " blob mismatch")
    text = driver.decode("utf-8")
    for anchor, patch in (
        (ARG_ANCHOR, ARG_PATCH),
        (ACTOR_ANCHOR, ACTOR_PATCH),
        (RECEIPT_ANCHOR, "      u2_receipt+result_claim+history_mark+\n"),
    ):
        if text.count(anchor) != 1:
            raise HeldHookRefusal("Frozen signed driver insertion anchor changed")
        text = text.replace(anchor, patch, 1)
    if (text.count('--historical-retirement-followon') != 1
            or text.count('history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS') != 1
            or text.count("source_path=ROOT/") != 1
            or text.count("    owner_session=signed[") != 1):
        raise HeldHookRefusal("Historical driver opt-in assertion failed")
    return text.encode("utf-8")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--driver", type=Path, required=True)
    p.add_argument("--bridge", type=Path, required=True)
    p.add_argument("--companion", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    runner = os.environ.get("RUNNER_TEMP")
    if not runner or not Path(runner).is_dir():
        raise HeldHookRefusal("Require explicit disposable RUNNER_TEMP")
    safe_root = Path(runner).resolve()
    out = a.output.resolve()
    if out.parent != safe_root or out.name != "validate-uniops-historical-signed-local-only.py":
        raise HeldHookRefusal("Output must be the fixed disposable local test file")
    for file in (a.driver, a.bridge, a.companion):
        if file.is_symlink() or not file.is_file():
            raise HeldHookRefusal("Missing or symlinked pinned source input")
    patch = prepare(a.driver.read_bytes(), a.bridge.read_bytes(),
                    a.companion.read_bytes())
    with out.open("xb") as dst:
        dst.write(patch)
    print("PASS source-only exact historical signed follow-on patch; NOT RUN")


if __name__ == "__main__":
    main()

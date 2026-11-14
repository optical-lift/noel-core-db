#!/usr/bin/env python3
"""HELD SOURCE ONLY: compose existing historical governor proof AFTER P3 signed mowing.

Must begin with the IMMUTABLE U2 driver and #2368 historical source companion.
Reuses Noel's already source-reviewed history follow-on patch. Adds read-only,
source-pinned P3 snapshot checks immediately around governor retirement.
Never executes this driver here. A NEW and separately authorized owner-only
disposable clone is required before claiming ANY new signed history PASS.
"""
import argparse
import hashlib
import os
from pathlib import Path
import sys

import prepare_uniops_historical_retirement_signed_followon_held as original

PREPARER_BLOB="6ff245eb3c2c3ce007b0a0a59e1d382d7ae0d519"
GUARD_BLOB="a0ab7523f10e9b79d3290871fd5faac777e6e733"
P3_HOOK_BLOB="4efef70ea67209b04def420aade39b8a6fd44f38"
SAFE_OUTPUT="validate-uniops-p3-historical-signed-local-only.py"

HISTORY_START="        history_receipt=hist.prove(\n"
HISTORY_SUCCESS='        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"\n'
HISTORY_PRE='''        # Test-only: capture exact completed mowing source in this same
        # disposable organization, before any separate historic cancellation.
        _p3_spec=importlib.util.spec_from_file_location(
            "uniops_p3_6a_snapshot_hook_held",
            ROOT/"tests"/"uniops_p3_6a_snapshot_hook_held.py")
        check(_p3_spec is not None and _p3_spec.loader is not None,
              "Pinned signed P3 snapshot hook missing")
        _p3=importlib.util.module_from_spec(_p3_spec)
        _p3_spec.loader.exec_module(_p3)
        _pres_spec=importlib.util.spec_from_file_location(
            "uniops_p3_historical_preservation_check_held",
            ROOT/"tests"/"uniops_p3_historical_preservation_check_held.py")
        check(_pres_spec is not None and _pres_spec.loader is not None,
              "Pinned P3 historical preservation guard missing")
        _pres=importlib.util.module_from_spec(_pres_spec)
        _pres_spec.loader.exec_module(_pres)
        _mowing_before_history=_p3.capture(
            a.db_url,sql,_p3.ORG,_p3.STATE,new_work,"replay")
'''
HISTORY_POST='''        _mowing_after_history=_p3.capture(
            a.db_url,sql,_p3.ORG,_p3.STATE,new_work,"replay")
        check(_pres.require_preserved(_mowing_before_history,
                                     _mowing_after_history) is True,
              "Governed mowing Work/Need changed during separate historic retirement")
        print("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS",flush=True)
        history_mark="UNI_OPS_SIGNED_HISTORY_CANCEL=PASS\\n"
'''

class P3HistoricalRefusal(RuntimeError):
    pass

def git_blob(payload):
    return hashlib.sha1(b"blob "+str(len(payload)).encode()+b"\0"+payload).hexdigest()

def prepare(driver,bridge,companion,guard,hook,preparer):
    for data,pin,label in (
        (preparer,PREPARER_BLOB,"historical preparer"),
        (guard,GUARD_BLOB,"P3 preservation guard"),
        (hook,P3_HOOK_BLOB,"signed P3 snapshot source")):
        if not isinstance(data,bytes) or git_blob(data)!=pin:
            raise P3HistoricalRefusal("Reviewed "+label+" source drift")
    # The existing history preparer authenticates ALL THREE genuine source
    # blobs before producing one copy. It already rejects source tampering.
    prepared=original.prepare(driver,bridge,companion).decode("utf8")
    if prepared.count(HISTORY_START)!=1 or prepared.count(HISTORY_SUCCESS)!=1:
        raise P3HistoricalRefusal("Original signed history driver insertion drift")
    if "UNI_OPS_P3_MOWING_AFTER_HISTORY" in prepared:
        raise P3HistoricalRefusal("History preservation already inserted")
    prepared=prepared.replace(HISTORY_START,HISTORY_PRE+HISTORY_START,1)
    prepared=prepared.replace(HISTORY_SUCCESS,HISTORY_POST,1)
    for tok in ("--historical-retirement-followon",
                "_mowing_before_history=_p3.capture",
                "history_receipt=hist.prove",
                "_mowing_after_history=_p3.capture",
                "_pres.require_preserved",
                "UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"):
        if prepared.count(tok)!=1:
            raise P3HistoricalRefusal("Historical signed source composition not unique")
    return prepared.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    for arg in ("driver","bridge","companion","guard","p3-hook","preparer","output"):
        p.add_argument("--"+arg,required=True,type=Path)
    a=p.parse_args()
    runner=os.environ.get("RUNNER_TEMP")
    if not runner or not Path(runner).is_dir():
        raise P3HistoricalRefusal("Explicit runner scratch required")
    out=a.output
    root=Path(runner).resolve()
    if (not out.is_absolute() or out.parent.resolve()!=root
            or out.name!=SAFE_OUTPUT or out.exists()):
        raise P3HistoricalRefusal("Exact new disposable driver file required")
    inputs=[a.driver,a.bridge,a.companion,a.guard,a.p3_hook,a.preparer]
    if any(not inp.is_file() or inp.is_symlink() for inp in inputs):
        raise P3HistoricalRefusal("Reviewed ordinary input file missing")
    data=prepare(*(i.read_bytes() for i in inputs))
    with out.open("xb") as file:
        file.write(data)
    os.chmod(out,0o600)
    print("PASS source-only composite P3 plus separately approved governor history; NO SIGNED RUN")

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""HELD SOURCE ONLY: layer preexisting old mowing carriers onto the proven U2/U4/P3/history driver.

Do NOT rewrite the existing signed-history source, companion, test workflow, or
#2784 owner permission. This prepares a *new* disposable COPY for a separately
reviewed future owner-specific gate. It does not execute SQL or signed actors.
"""
import argparse
import hashlib
import os
from pathlib import Path
import sys

import prepare_uniops_p3_history_signed_followon_held as parent

PARENT_BLOB="e0240feabf26a3c19b7f86aa7f4de22d70635523"
FIXTURE_BLOB="4687c4a0f44d2f5581ee4361f6d8c56d92175c1a"
SAFE_OUTPUT="validate-uniops-preexisting-mowing-signed-local-only.py"
SEED_ANCHOR="    count_before=int(sql(a.db_url,"
BEFORE_ANCHOR='        print("UNI_OPS_HISTORY_HANDOFF_STAGE=governor_started",flush=True)\n'
AFTER_ANCHOR='        print("UNI_OPS_HISTORY_HANDOFF_STAGE=conservation_started",flush=True)\n'

PREPARE_SEED='''    # Synthetic previously existing old-queue carriers must predate the signed
    # native Rulebook adoption, before worker U2/U4/P3. No governor approval,
    # old Work completion, or human acceptance is fabricated by this fixture.
    import hashlib as _legacy_hashlib
    _legacy_path=ROOT/"tests"/"uniops_preexisting_mowing_carriers_held.py"
    check(_legacy_path.is_file() and not _legacy_path.is_symlink(),
          "Reviewed prior mowing fixture missing")
    _legacy_bytes=_legacy_path.read_bytes()
    check(_legacy_hashlib.sha1(b"blob "+str(len(_legacy_bytes)).encode("ascii")
          +b"\\\\0"+_legacy_bytes).hexdigest()
          =="4687c4a0f44d2f5581ee4361f6d8c56d92175c1a",
          "Prior mowing fixture changed")
    _legacy_spec=importlib.util.spec_from_file_location(
        "uniops_preexisting_mowing_carriers_held",_legacy_path)
    check(_legacy_spec is not None and _legacy_spec.loader is not None,
          "Prior mowing fixture source unavailable")
    _legacy=importlib.util.module_from_spec(_legacy_spec)
    _legacy_spec.loader.exec_module(_legacy)
    _legacy.install(a.db_url,sql)
    print("UNI_OPS_PRIOR_MOWING_FIXTURE=SEEDED_BEFORE_GOVERNANCE",flush=True)
'''
PRE_HISTORY='''        _legacy_before=_legacy.capture(a.db_url,sql)
        print("UNI_OPS_PRIOR_MOWING_HISTORY_BEFORE=CAPTURED",flush=True)
'''
POST_HISTORY='''        _legacy_after=_legacy.capture(a.db_url,sql)
        check(_legacy.require_preserved(
            _legacy_before,_legacy_after,
            _mowing_before_history,_mowing_after_history) is True,
            "Retirement changed a preexisting mowing Task or occurrence")
        print("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",flush=True)
'''

class LegacyCarrierCompositionRefusal(AssertionError):
    pass

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()

def inject(reviewed_composite,fixture):
    if not isinstance(reviewed_composite,bytes) or not isinstance(fixture,bytes):
        raise LegacyCarrierCompositionRefusal("Reviewed bytes required")
    if git_blob(fixture)!=FIXTURE_BLOB:
        raise LegacyCarrierCompositionRefusal("Prior mowing fixture not reviewed")
    code=reviewed_composite.decode("utf8")
    for anchor in (SEED_ANCHOR,BEFORE_ANCHOR,AFTER_ANCHOR):
        if code.count(anchor)!=1:
            raise LegacyCarrierCompositionRefusal("One source-owned insertion anchor changed")
    if "UNI_OPS_PRIOR_MOWING_FIXTURE=" in code:
        raise LegacyCarrierCompositionRefusal("Prior mowing source already injected")
    code=code.replace(SEED_ANCHOR,PREPARE_SEED+SEED_ANCHOR,1)
    code=code.replace(BEFORE_ANCHOR,PRE_HISTORY+BEFORE_ANCHOR,1)
    code=code.replace(AFTER_ANCHOR,POST_HISTORY+AFTER_ANCHOR,1)
    for fragment in (
        "_legacy.install(a.db_url,sql)",
        "_legacy_before=_legacy.capture(a.db_url,sql)",
        "_legacy_after=_legacy.capture(a.db_url,sql)",
        "_legacy.require_preserved(",
        "UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS",
        "UNI_OPS_SIGNED_HISTORY_CANCEL=PASS",
        "history_receipt=hist.prove(",
        "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",
    ):
        if code.count(fragment)!=1:
            raise LegacyCarrierCompositionRefusal("Signed source integration cardinality changed")
    if not (code.index("_legacy.install(a.db_url,sql)")
            <code.index("count_before=int(sql(a.db_url,")
            <code.index("history_receipt=hist.prove(")
            <code.index("_legacy_after=_legacy.capture(a.db_url,sql)")
            <code.index("_legacy.require_preserved(")
            <code.index("UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS")):
        raise LegacyCarrierCompositionRefusal("Preexisting carrier order changed")
    return code.encode("utf8")

def prepare(driver,bridge,companion,guard,hook,preparer,compat,fixture):
    # Parent composer independently checks all seven immutable inputs and
    # returns the reviewed historical P3 driver, not a newer loose substitute.
    if git_blob(Path(parent.__file__).read_bytes())!=PARENT_BLOB:
        raise LegacyCarrierCompositionRefusal("Original signed P3 history composer drift")
    reviewed=parent.prepare(driver,bridge,companion,guard,hook,preparer,compat)
    return inject(reviewed,fixture)

def main():
    p=argparse.ArgumentParser()
    for name in ("driver","bridge","companion","guard","p3-hook",
                 "preparer","compat","fixture","output"):
        p.add_argument("--"+name,required=True,type=Path)
    a=p.parse_args()
    scratch=os.environ.get("RUNNER_TEMP")
    if not scratch or not Path(scratch).is_dir():
        raise LegacyCarrierCompositionRefusal("Explicit ephemeral runner scratch required")
    target=Path(scratch).resolve()
    if (not a.output.is_absolute() or a.output.parent.resolve()!=target
        or a.output.name!=SAFE_OUTPUT or a.output.exists()):
        raise LegacyCarrierCompositionRefusal("Exact new disposable output required")
    inputs=(a.driver,a.bridge,a.companion,a.guard,a.p3_hook,a.preparer,
            a.compat,a.fixture)
    if any(not path.is_file() or path.is_symlink() for path in inputs):
        raise LegacyCarrierCompositionRefusal("Only ordinary reviewed input files permitted")
    content=prepare(*(path.read_bytes() for path in inputs))
    with a.output.open("xb") as out:
        out.write(content)
    os.chmod(a.output,0o600)
    print("PASS held preexisting Task/occurrence signed-driver SOURCE ONLY; NOT EXECUTED")

if __name__=="__main__":
    main()

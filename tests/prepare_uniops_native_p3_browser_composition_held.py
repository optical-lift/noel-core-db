#!/usr/bin/env python3
"""HELD offline only: reconcile frozen P3 snapshots with ONE native U4 browser Actual.

Do not weaken either parent source-pin. Reproduce P3's original exact-blob
instrumentation in a fresh scratch copy first, compare that byte-for-byte with
the already prepared disposable U4, then introduce the ONE browser-positive
Result. Denials, after/replay snapshots and no-successor proof are retained.

This program does not contact GitHub, localhost, Supabase or production and
cannot run a protected job. Caller MUST source-pin the Noel frozen U4,
the immutable P3 hook and this new reviewed composer.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import tempfile

FROZEN_U4_BLOB="2e180aa2363201e75ca0d717eeeddd5a708193ab"
PINNED_P3_BLOB="4efef70ea67209b04def420aade39b8a6fd44f38"
OUTPUT_NAME="uniops_u2_qualified_actual_browser_p3_local_only.py"
P3_MARKERS=(
    "_p3_before=_p3.capture(db_url,sql,ORG,STATE,work,\"before\")",
    "_p3_after=_p3.capture(db_url,sql,ORG,STATE,work,\"after\")",
    "_p3_replay=_p3.capture(db_url,sql,ORG,STATE,work,\"replay\")",
    '_p3.compare(_p3_before,_p3_after,_p3_replay,"completed")',
)
SOURCE_NEGATIVES=(
    'for actor in ("outsider","owner"):',
    'status, response = call("worker",invalid)',
    'status, replay = call("worker")',
    'U4 Result/Done produced an unauthorized successor, task, offer or plan',
    'U4 signed retry produced a second Result or changed its identity',
    "and count(\"atlas.work_result_acceptances\"",
)
def git_blob(data):
    return hashlib.sha1(
      b"blob "+str(len(data)).encode()+b"\\0"+data
    ).hexdigest()

def load_exact(path,blob,kind):
    p=Path(path)
    if not p.is_file() or p.is_symlink():
        raise ValueError(kind+" must be a regular source file")
    raw=p.read_bytes()
    if git_blob(raw)!=blob:
        raise ValueError(kind+" source checksum changed")
    return raw

def import_script(path,name):
    spec=importlib.util.spec_from_file_location(name,str(path))
    if spec is None or spec.loader is None:
        raise ValueError("Source-only script import unavailable")
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def p3_expected(frozen_u4,p3_script):
    # The immutable P3 hook checks FROZEN_U4_BLOB independently.
    with tempfile.TemporaryDirectory(prefix="held-uniops-p3-browser-") as root:
        source=Path(root)/"uniops_u2_qualified_actual_followon_held.py"
        source.write_bytes(frozen_u4)
        p3=import_script(p3_script,"pinned_held_p3")
        if p3.SIGNED_U4_PARENT_BLOB!=FROZEN_U4_BLOB:
            raise ValueError("P3 parent target was changed")
        p3.patch_exact_disposable_u4(source)
        return source.read_bytes()

def splice(frozen,p3_script,preinstrumented,positive_module):
    expected=p3_expected(frozen,p3_script)
    if expected!=preinstrumented:
        raise ValueError("Previous P3 snapshot hook differs from exact source")
    original=expected.decode("utf-8")
    if any(original.count(marker)!=1 for marker in P3_MARKERS):
        raise ValueError("Missing one of the exact P3 snapshots")
    if any(original.count(marker)!=1 for marker in SOURCE_NEGATIVES):
        raise ValueError("Frozen independent U4 negatives or replay changed")
    if original.count(positive_module.NEEDLE)!=1:
        raise ValueError("Not exactly one first physical worker Result")
    if original.count(positive_module.HEADER)!=1 or (
      original.count(positive_module.DENIAL_MARKER)!=1):
        raise ValueError("Source guard insertion points changed")
    result=original.replace(
        positive_module.HEADER,
        positive_module.HEADER+positive_module.GUARD+"\\n",1
    ).replace(
        positive_module.DENIAL_MARKER,
        positive_module.DENIAL_MARKER+positive_module.MORE_DENIALS,1
    ).replace(
        positive_module.NEEDLE,positive_module.REPLACEMENT,1
    )
    if any(result.count(marker)!=1 for marker in P3_MARKERS):
        raise ValueError("P3 before/after/replay source was displaced")
    if any(result.count(marker)!=1 for marker in SOURCE_NEGATIVES):
        raise ValueError("U4 negative/replay/zero-successor source was displaced")
    if result.count(positive_module.REPLACEMENT)!=1 or (
      positive_module.NEEDLE in result):
        raise ValueError("Browser Result was not the sole positive")
    compile(result,OUTPUT_NAME,"exec")
    return result.encode("utf-8")

def compose(frozen_u4,p3_script,instrumented,positive_script):
    frozen=load_exact(frozen_u4,FROZEN_U4_BLOB,"Frozen U4")
    load_exact(p3_script,PINNED_P3_BLOB,"Pinned P3 snapshot")
    patcher=import_script(positive_script,"held_browser_positive")
    if patcher.FROZEN_SOURCE_BLOB!=FROZEN_U4_BLOB:
        raise ValueError("Browser-positive parent changed")
    target=Path(instrumented)
    if not target.is_file() or target.is_symlink():
        raise ValueError("P3-instrumented disposable file missing")
    return splice(frozen,Path(p3_script),target.read_bytes(),patcher)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--frozen-u4",required=True)
    p.add_argument("--p3-script",required=True)
    p.add_argument("--instrumented",required=True)
    p.add_argument("--browser-patcher",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    output=Path(a.output)
    if output.name!=OUTPUT_NAME or output.exists() or output.is_symlink():
        raise SystemExit("Refuse unexpected or existing disposable output")
    inputs=(a.frozen_u4,a.p3_script,a.instrumented,a.browser_patcher)
    if any(output.resolve()==Path(item).resolve() for item in inputs):
        raise SystemExit("Refuse mutation of governed source")
    data=compose(*inputs)
    with output.open("xb") as h:
        h.write(data)
    print("PASS exact P3 before/after/replay and one native browser worker Actual: held source only")

if __name__=="__main__":
    main()

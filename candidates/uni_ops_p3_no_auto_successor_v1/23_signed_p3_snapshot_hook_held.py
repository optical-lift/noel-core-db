#!/usr/bin/env python3
"""HELD U2->U4->P3 6A signed-test instrumentation. Disposable clone ONLY.

This module only reads a source-controlled SQL SELECT snapshot and invokes the
already-pinned Node comparator. It NEVER manufactures signed tokens, writes
Postgres data, calls the Actual RPC, changes source authority or creates a Task.
U4 independently signs and exercises the real worker RPC, and its ORIGINAL
source file remains pinned. This hook is loaded by a byte-guarded TEMPORARY
copy of that runner, never by the committed U4 implementation.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from uuid import UUID

HERE=Path(__file__).resolve().parent
SNAPSHOT=HERE/"uniops_p3_6a_snapshot.sql"
COMPARATOR=HERE/"uniops_p3_6a_compare.mjs"
SIGNED_U4_PARENT_BLOB="2e180aa2363201e75ca0d717eeeddd5a708193ab"
SNAPSHOT_BLOB="8acc6ddae19a1e2b7e7f08695406648246023106"
COMPARATOR_BLOB="618ea32d80a6794e637b9428b90b34b366b031c4"
ORG="e5200000-0000-4000-8000-000000000801"
STATE="e5200000-0000-4000-8000-000000000d05"

def _git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()

def _pinned(path,expected):
    raw=path.read_bytes()
    if _git_blob(raw)!=expected:
        raise AssertionError("P3 signed snapshot source pin changed")
    return raw.decode("utf8")

def _uuid(value):
    try:
        return str(UUID(str(value)))==str(value)
    except (ValueError,TypeError,AttributeError):
        return False

def render_snapshot(source,org,state,work,phase):
    """One exact SELECT from the isolated source, with literal UUIDs only."""
    if not (_uuid(org) and _uuid(state) and _uuid(work) and org==ORG and
            state==STATE and phase in ("before","after","replay")):
        raise AssertionError("P3 snapshot fixture identity/phase not authorized")
    lines=[x for x in source.splitlines()
           if not x.lstrip().startswith("--") and not x.lstrip().startswith("\\set ")]
    query="\n".join(lines)
    for key,value in (("organization_id",org),("rhythm_state_id",state),
                      ("work_item_id",work),("phase",phase)):
        token=":'"+key+"'"
        if query.count(token)!=1:
            raise AssertionError("P3 snapshot parameter source drift")
        query=query.replace(token,"'"+value+"'")
    if re.search(r":'[a-z_]+('|$)",query) or re.search(
            r"(?i)\b(?:insert\s+into|update\s+atlas\.|delete\s+from|"
            r"create\s+table|drop\s+table|grant\s+|alter\s+table)\b",query):
        raise AssertionError("P3 snapshot is not the reviewed read-only query")
    if query.count("SELECT jsonb_build_object(")!=1:
        raise AssertionError("P3 snapshot cardinality changed")
    return query

def capture(db_url,sql,org,state,work,phase):
    # Matches the true U4 local-only signature. Reject remote and production.
    if not re.fullmatch(
      r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
      db_url or ""):
        raise AssertionError("P3 snapshots require isolated loopback PG")
    source=_pinned(SNAPSHOT,SNAPSHOT_BLOB)
    _pinned(COMPARATOR,COMPARATOR_BLOB)
    raw=sql(db_url,render_snapshot(source,org,state,work,phase))
    if not isinstance(raw,str) or not raw.strip().startswith("{") or (
            raw.count("\n")>1):
        raise AssertionError("P3 snapshot returned non-unique SQL evidence")
    try:
        evidence=json.loads(raw)
    except (ValueError,TypeError) as exc:
        raise AssertionError("P3 snapshot lacked valid JSON") from exc
    if not isinstance(evidence,dict) or evidence.get("phase")!=phase or (
        evidence.get("contract")!="uni_ops_p3_signed_result_snapshot_v1"):
        raise AssertionError("P3 snapshot does not prove exact fixture/phase")
    return evidence

def compare(before,after,replay,kind):
    if kind!="completed":
        raise AssertionError("P3 first signed runner proves completed only")
    _pinned(COMPARATOR,COMPARATOR_BLOB)
    with tempfile.TemporaryDirectory(prefix="uniops-p3-6a-signed-") as root:
        paths=[]
        for name,object_ in (("before",before),("after",after),("replay",replay)):
            if not isinstance(object_,dict):
                raise AssertionError("P3 source snapshot must be a JSON object")
            target=Path(root)/(name+".json")
            target.write_text(json.dumps(object_,sort_keys=True),encoding="utf8")
            os.chmod(target,0o600)
            paths.append(str(target))
        r=subprocess.run(["node",str(COMPARATOR),paths[0],paths[1],kind,paths[2]],
            capture_output=True,text=True,check=False,timeout=15)
        if r.returncode!=0 or (
                "UNI_OPS_P3_SIGNED_RESULT_SNAPSHOT_COUNTS=PASS" not in r.stdout):
            # Errors and private test JSON never enter CI output or issues.
            raise AssertionError("P3 source-signed before/after/redo evidence failed")
    print("P3_6A_SIGNED_RESULT_SNAPSHOT=PASS",flush=True)
    return True

def patch_exact_disposable_u4(path):
    """Patch one COPY only; require the unchanged previously signed U4 blob."""
    p=Path(path)
    if p.is_symlink() or not p.is_file():
        raise AssertionError("P3 hook requires an ordinary disposable runner file")
    raw=p.read_bytes()
    if _git_blob(raw)!=SIGNED_U4_PARENT_BLOB:
        raise AssertionError("P3 hook source is not exact separately signed U4")
    original=raw.decode("utf8")
    before='    status, response = call("worker")\n    if status != 200 or not accepted_receipt(response,work):'
    after=('    require(count("atlas.work_items",\n'
           '                  "id="+work_ref+" and work_state=\'completed\'")==1\n'
           '            and count("atlas.work_lifecycle_events_v1",\n'
           '                      "work_item_id="+work_ref+\n'
           '                      " and event_kind=\'work_transition_applied\'")==1,\n'
           '            "U4 qualified Result did not create one canonical terminal transition")')
    replay=('    require(status==200 and accepted_receipt(replay,work)\n'
            '            and replay["workResultId"]==response["workResultId"]\n'
            '            and replay.get("idempotent") is True,\n'
            '             "U4 signed retry produced a second Result or changed its identity")')
    for anchor in (before,after,replay):
        if original.count(anchor)!=1:
            raise AssertionError("P3 U4 injection anchor source drift")
    setup=(
        '    from importlib.util import spec_from_file_location, module_from_spec\n'
        '    from pathlib import Path\n'
        '    _p3_path=Path(__file__).resolve().parent/"uniops_p3_6a_snapshot_hook_held.py"\n'
        '    _p3_spec=spec_from_file_location("uniops_p3_6a_snapshot_hook_held",_p3_path)\n'
        '    require(_p3_spec is not None and _p3_spec.loader is not None,\n'
        '            "P3 pinned snapshot hook absent from disposable runner")\n'
        '    _p3=module_from_spec(_p3_spec)\n'
        '    _p3_spec.loader.exec_module(_p3)\n'
        '    _p3_before=_p3.capture(db_url,sql,ORG,STATE,work,"before")\n')
    rewritten=original.replace(before,setup+before,1)
    rewritten=rewritten.replace(after,after+
        '\n    _p3_after=_p3.capture(db_url,sql,ORG,STATE,work,"after")',1)
    rewritten=rewritten.replace(replay,replay+
        '\n    _p3_replay=_p3.capture(db_url,sql,ORG,STATE,work,"replay")'
        '\n    _p3.compare(_p3_before,_p3_after,_p3_replay,"completed")',1)
    if not all(rewritten.count(fragment)==1 for fragment in (
        '_p3_before=_p3.capture','_p3_after=_p3.capture',
        '_p3_replay=_p3.capture','_p3.compare(')):
        raise AssertionError("P3 snapshot hooks were not installed exactly once")
    p.write_text(rewritten,encoding="utf8")
    return True

if __name__=="__main__":
    import sys
    if len(sys.argv)!=2:
        raise SystemExit("Usage: 23_signed_p3_snapshot_hook_held.py DISPOSABLE_U4_COPY")
    patch_exact_disposable_u4(sys.argv[1])
    print("P3_6A_SIGNED_SNAPSHOT_HOOK=INSTALLED_TO_TEMP_COPY_ONLY")

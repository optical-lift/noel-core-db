#!/usr/bin/env python3
"""HELD / P3 6A: replace ONE false structural source-reference in TEST_ONLY SQL.

The final P3 structural check wrongly searches for the accepted-standing
writer's name IN the BEFORE INSERT trigger body. The frozen 04 source checks
that function's exact signature in its prerequisite DO; the trigger calls
the U2C accepted-first receipt, and 06 separately enforces COMMIT state.

This corrects a structural TEST expectation ONLY. It does not skip any
function-existence, source-receipt, deferred-commit, trigger or ACL guard.
The original 20 source, U2/U4, P3 held branch, schema and production are
untouched. Fail closed on any unexpected source, scratch, path or prior edit.
"""
from pathlib import Path
import hashlib
import os
import sys
import tempfile

NAME="20261107211000_atlas_uni_ops_p3_6a_TEST_ONLY.sql"
# The actual post-four-terminator scratch digest from owner run #43618014073.
FRAMED_SQL_SHA="293d66ad1557c675af973e26437343e737bf65db4a1cc9bca7199ca0dec4c751"
REVIEWED={
  "04_canonical_original_acceptance_guard_held.sql":"af9a70d8e29273707b6eb20d1b4c8a153ffa9d60",
  "06_deferred_governed_original_finalization_held.sql":"a1bbc4f05b61f3de7694a738976bca3d838bbc32",
  "20_mowing_6a_core_postconditions_held.sql":"210c42f97ceebc8dde2b493e898d23747cce7787",
}
STANDING="atlas.require_accepted_prework_standing_original_v1(uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)"
OLD="OR position('require_accepted_prework_standing_original_v1' IN\n       v_original_guard)=0"
NEW=("OR pg_catalog.to_regprocedure(\n"
     "       '"+STANDING+"'\n"
     "     ) IS NULL")

def git_blob(data):
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

def check_sources(root):
    base=Path(root)
    if not base.is_dir() or base.is_symlink():
        raise AssertionError("reviewed held source directory not found")
    raw={}
    for filename,pin in REVIEWED.items():
        p=base/filename
        if not p.is_file() or p.is_symlink():
            raise AssertionError("reviewed held file must be ordinary file")
        data=p.read_bytes()
        if git_blob(data)!=pin:
            raise AssertionError("P3 reviewed source changed: "+filename)
        raw[filename]=data.decode("utf8")
    guard=raw["04_canonical_original_acceptance_guard_held.sql"]
    deferred=raw["06_deferred_governed_original_finalization_held.sql"]
    post=raw["20_mowing_6a_core_postconditions_held.sql"]
    if guard.count("'"+STANDING+"'")!=1 or (
            guard.index("'"+STANDING+"'") > guard.index("CREATE FUNCTION atlas.guard_uni_ops_governed_care_original_acceptance_v1")):
        raise AssertionError("Exact accepted-standing dependency not in 04 prerequisite")
    trigger_body=guard.split("AS $governed_original$",1)[1].split("$governed_original$;",1)[0]
    if "require_accepted_prework_standing_original_v1" in trigger_body:
        raise AssertionError("Accepted-standing writer unexpectedly in guard body")
    if trigger_body.count("uni_ops_accepted_first_original_source_receipt_held_v1")!=1:
        raise AssertionError("Trigger does not depend on the single accepted-first source receipt")
    if deferred.count("atlas.resolve_governed_canonical_farm_rule_authority_v1(")!=2:
        raise AssertionError("Commit-stage Rulebook preflight and call missing")
    defer_body=deferred.split("AS $final_commit$",1)[1].split("$final_commit$;",1)[0]
    if defer_body.count("atlas.resolve_governed_canonical_farm_rule_authority_v1(")!=1:
        raise AssertionError("Actual deferred COMMIT authority call missing")
    if "CREATE CONSTRAINT TRIGGER z_uni_ops_governed_original_finalization_v1" not in deferred:
        raise AssertionError("Commit-time deferred trigger absent in source")
    if post.count(OLD)!=1:
        raise AssertionError("Exactly one false check expected in 20")
    if post.count("position('uni_ops_accepted_first_original_source_receipt_held_v1' IN")!=1:
        raise AssertionError("Receipt structural check must be retained")
    if post.count("position('resolve_governed_canonical_farm_rule_authority_v1' IN")!=1:
        raise AssertionError("Deferred Rulebook check must be retained")
    return raw

def correct_sql(source, raw):
    if source.count("-- BEGIN PINNED STAGE ")!=18 or source.count("-- END PINNED STAGE ")!=18:
        raise AssertionError("Original U2/U4 stage provenance unexpected")
    if source.count("-- BEGIN PINNED P3 6A HELD STAGE ")!=8 or source.count("-- END PINNED P3 6A HELD STAGE ")!=8:
        raise AssertionError("Eight P3 stage provenance markers required")
    filename="20_mowing_6a_core_postconditions_held.sql"
    start="\n-- BEGIN PINNED P3 6A HELD STAGE "+filename+" "+REVIEWED[filename]+"\n"
    finish="\n-- END PINNED P3 6A HELD STAGE "+filename+"\n"
    if source.count(start)!=1 or source.count(finish)!=1:
        raise AssertionError("P3 structural source marker missing or duplicate")
    prefix,tail=source.split(start,1)
    body,suffix=tail.split(finish,1)
    if body!=raw[filename]:
        raise AssertionError("P3 structural source changed within scratch")
    if source.count(OLD)!=1 or NEW in source:
        raise AssertionError("Expected one unpatched check in full scratch")
    corrected=raw[filename].replace(OLD,NEW,1)
    result=prefix+start+corrected+finish+suffix
    if result.count(NEW)!=1 or result.count(OLD)!=0:
        raise AssertionError("Structural postcondition correction not exact")
    return result

def main(argv):
    if len(argv)!=3:
        raise SystemExit("Usage: correct_uniops_p3_6a_postcondition_deppath_held.py ABSOLUTE_P3_TEST_ONLY.sql ABSOLUTE_REVIEWED_P3_SOURCE_DIR")
    file=Path(argv[1])
    if not file.is_absolute() or file.name!=NAME or not file.is_file() or file.is_symlink():
        raise SystemExit("Refuse anything except ordinary exact P3 TEST_ONLY scratch")
    actual=file.resolve()
    roots=[Path(tempfile.gettempdir()).resolve()]
    if os.environ.get("RUNNER_TEMP"):
        roots.append(Path(os.environ["RUNNER_TEMP"]).resolve())
    if not any(actual.is_relative_to(root) for root in roots):
        raise SystemExit("P3 postcondition correction requires disposable temp path")
    original=file.read_bytes()
    if hashlib.sha256(original).hexdigest()!=FRAMED_SQL_SHA:
        raise SystemExit("P3 held framed scratch digest drift; no modification")
    raw=check_sources(argv[2])
    new=correct_sql(original.decode("utf8"),raw)
    if original.decode("utf8")==new:
        raise SystemExit("No correction was made")
    fd,path=tempfile.mkstemp(prefix=".p3-held-condition-",dir=str(file.parent))
    try:
        with os.fdopen(fd,"wb") as o:
            os.chmod(o.fileno(),0o600)
            o.write(new.encode("utf8"))
            o.flush()
            os.fsync(o.fileno())
        os.replace(path,file)
    finally:
        if os.path.exists(path):
            os.unlink(path)
    print("P3_6A_POSTCONDITION_REAL_DEPENDENCY=EXACT_SCRATCH_ONLY")
    print("P3_6A_REVIEWED_SQL_SHA256="+hashlib.sha256(new.encode("utf8")).hexdigest())
    print("PRODUCTION_MUTATION=NONE")

if __name__=="__main__":
    main(sys.argv)

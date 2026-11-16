#!/usr/bin/env python3
"""HELD source-only correction of a fictional old mowing Task release binding.

The frozen original #2799 fixture is *input*, not edited. The live reviewed
task-release gate requires BOTH planned_occurrence_id and release_policy_id to
recognize an already-released Task. Fix only that omitted key, and add one
matching physical-identity postcondition. Patch only the disposable signed
driver's corresponding exact fixture SHA1 pin. No SQL is executed here; this
has NO permission to use the owner-approved already-consumed #2800 runs.
"""
import argparse
import ast
import hashlib
import os
from pathlib import Path

FROZEN_FIXTURE_BLOB="ac3eb1ea158c4a6c43421e7d77932e7743f1026f"
ORIGINAL_COLUMNS="   planned_occurrence_id,released_at,metadata)\n"
FIXED_COLUMNS="   planned_occurrence_id,release_policy_id,released_at,metadata)\n"
ORIGINAL_VALUES=" '{RELEASED}'::uuid,now()-interval '3 days',\n"
FIXED_VALUES=" '{RELEASED}'::uuid,'{POLICY}'::uuid,now()-interval '3 days',\n"
ORIGINAL_POSTCONDITION="        AND planned_occurrence_id='{RELEASED}'::uuid)<>1"
FIXED_POSTCONDITION=("        AND planned_occurrence_id='{RELEASED}'::uuid\n"
                     "        AND release_policy_id='{POLICY}'::uuid)<>1")
ORIGINAL_ROW_GUARD='        and task.get("planned_occurrence_id")==RELEASED\n'
FIXED_ROW_GUARD=(ORIGINAL_ROW_GUARD+
                 '        and task.get("release_policy_id")==POLICY\n')
FROZEN_STAGE_DRIVER="validate-uniops-prior-mowing-staged-local-only.py"
OUTPUT_DRIVER="validate-uniops-prior-mowing-fixed-signed-local-only.py"
OUTPUT_FIXTURE="uniops-preexisting-mowing-fixture-fixed-local-only.py"

class PriorMowingFixturePatchRefusal(AssertionError):
    pass

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()

def exact_swap(text,old,new):
    if text.count(old)!=1 or new in text:
        raise PriorMowingFixturePatchRefusal("Frozen physical release anchor changed")
    return text.replace(old,new,1)

def patch_fixture(frozen):
    if not isinstance(frozen,bytes) or git_blob(frozen)!=FROZEN_FIXTURE_BLOB:
        raise PriorMowingFixturePatchRefusal("Original immutable fixture changed")
    try:
        source=frozen.decode("utf8")
        original=source
        source=exact_swap(source,ORIGINAL_COLUMNS,FIXED_COLUMNS)
        source=exact_swap(source,ORIGINAL_VALUES,FIXED_VALUES)
        source=exact_swap(source,ORIGINAL_POSTCONDITION,FIXED_POSTCONDITION)
        source=exact_swap(source,ORIGINAL_ROW_GUARD,FIXED_ROW_GUARD)
        ast.parse(source)
    except (UnicodeError,SyntaxError):
        raise PriorMowingFixturePatchRefusal("Invalid fixture source") from None
    # The four swaps do not affect SQL source id, gate type, task state,
    # triggers, authorization, actor identity, downstream Work or cleanup.
    if (source==original or source.count("release_policy_id='{POLICY}'::uuid")!=1
        or source.count('task.get("release_policy_id")==POLICY')!=1):
        raise PriorMowingFixturePatchRefusal("Only one physical Task binding is authorized")
    return source.encode("utf8")

def patch_driver(frozen_driver,corrected_fixture):
    if not isinstance(frozen_driver,bytes) or not isinstance(corrected_fixture,bytes):
        raise PriorMowingFixturePatchRefusal("Reviewed source bytes required")
    try:
        source=frozen_driver.decode("utf8")
    except UnicodeError:
        raise PriorMowingFixturePatchRefusal("Invalid staged driver") from None
    if (source.count(FROZEN_FIXTURE_BLOB)!=1
        or source.count("_legacy.install(a.db_url,_prior_mowing_traced_sql)")!=1
        or source.count("UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS")!=1
        or source.count("history_receipt=hist.prove(")!=1
        or source.count("_legacy.require_preserved(")!=1):
        raise PriorMowingFixturePatchRefusal("Reviewable staged signed source changed")
    source=source.replace(FROZEN_FIXTURE_BLOB,git_blob(corrected_fixture),1)
    ast.parse(source)
    return source.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--fixture",type=Path,required=True)
    p.add_argument("--staged-driver",type=Path,required=True)
    p.add_argument("--output-driver",type=Path,required=True)
    p.add_argument("--output-fixture",type=Path,required=True)
    a=p.parse_args()
    scratch=os.environ.get("RUNNER_TEMP")
    if not scratch or not Path(scratch).is_dir():
        raise PriorMowingFixturePatchRefusal("Only explicit ephemeral runner scratch permitted")
    root=Path(scratch).resolve()
    if (not a.fixture.is_file() or a.fixture.is_symlink()
        or not a.staged_driver.is_file() or a.staged_driver.is_symlink()
        or a.staged_driver.name!=FROZEN_STAGE_DRIVER
        or a.staged_driver.parent.resolve()!=root):
        raise PriorMowingFixturePatchRefusal("Only immutable fixture plus exact staged driver")
    for dest,name in ((a.output_fixture,OUTPUT_FIXTURE),(a.output_driver,OUTPUT_DRIVER)):
        if (not dest.is_absolute() or dest.name!=name
            or dest.parent.resolve()!=root or dest.exists()):
            raise PriorMowingFixturePatchRefusal("No replacement outside new scratch copy")
    new_fixture=patch_fixture(a.fixture.read_bytes())
    new_driver=patch_driver(a.staged_driver.read_bytes(),new_fixture)
    for dest,data in ((a.output_fixture,new_fixture),(a.output_driver,new_driver)):
        with dest.open("xb") as stream:
            stream.write(data)
        os.chmod(dest,0o600)
    print("PASS independent frozen prior-mowing release-policy fixture COPY ONLY; NO SQL EXECUTED")
    print("UNI_OPS_PRIOR_MOWING_FIXTURE_FIXED_BLOB="+git_blob(new_fixture))

if __name__=="__main__":
    main()

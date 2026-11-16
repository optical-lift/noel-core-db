#!/usr/bin/env python3
"""HELD TEST ONLY: refine the prior-mowing task_other FK label.

The signed v5 run showed a Task-family constraint other than organization,
farm, planned occurrence, or release-policy. The private exception is
classified into a finite source-reviewed family, never printed or returned.
No actor, SQL, frozen fixture, schema or credential is changed.
"""
import argparse
import ast
import hashlib
import os
from pathlib import Path
import re
import subprocess

V5_BLOB="a18904f46719457ae06ca301ed1c12323a5ca3c2"
V4_BLOB="3847bebca7490bfc4bfbad7f629a6b26f64d7acd"
FIXTURE_BLOB="ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc"
ANCHOR='''                print("UNI_OPS_PRIOR_MOWING_FK_LOCUS="+
                      _fk.classify_exception(_seed_failure),flush=True)
'''
OUTPUT="validate-uniops-prior-mowing-task-fk-local-only.py"
EXACT={
    "tasks_parent_task_id_fkey":"task_parent",
    "tasks_assigned_membership_id_fkey":"task_assigned_farm_membership",
}
FAMILIES=(
    ("_membership_id_fkey","task_other_membership"),
    ("_person_id_fkey","task_person"),
    ("_task_id_fkey","task_other_task"),
    ("_work_item_id_fkey","task_company_work"),
    ("_work_allocation_id_fkey","task_work_allocation"),
    ("_result_id_fkey","task_result"),
    ("_activity_id_fkey","task_activity"),
    ("_entity_id_fkey","task_entity"),
    ("_ledger_id_fkey","task_ledger"),
    ("_resource_id_fkey","task_resource"),
    ("_zone_id_fkey","task_zone"),
    ("_project_id_fkey","task_project"),
    ("_crop_cycle_id_fkey","task_crop_cycle"),
    ("_object_id_fkey","task_object"),
    ("_source_id_fkey","task_source"),
    ("_schedule_id_fkey","task_schedule"),
    ("_event_id_fkey","task_event"),
)
FIXED=frozenset(set(EXACT.values())|{x[1] for x in FAMILIES}|{
    "task_unclassified","not_task_fk","multiple_fk","error_without_constraint",
    "non_psql_exception","not_reported","ambiguous_report","untrusted_report",
    "untrusted_source",
})
EXTRA='''                _task_fk_path=ROOT/"tests"/"uniops_prior_mowing_task_fk_refinement_held.py"
                check(_task_fk_path.is_file() and not _task_fk_path.is_symlink(),
                      "Reviewed task foreign-key refinement missing")
                _task_fk_bytes=_task_fk_path.read_bytes()
                import hashlib as _task_fk_hashlib
                _task_fk_blob=_task_fk_hashlib.sha1(
                    b"blob "+str(len(_task_fk_bytes)).encode("ascii")+b"\\0"+_task_fk_bytes
                ).hexdigest()
                check(_task_fk_blob=="{blob}",
                      "Reviewed task foreign-key refinement changed")
                _task_fk_spec=importlib.util.spec_from_file_location(
                    "uniops_prior_mowing_task_fk_refinement_held",_task_fk_path)
                check(_task_fk_spec is not None and _task_fk_spec.loader is not None,
                      "Reviewed task foreign-key refinement unavailable")
                _task_fk=importlib.util.module_from_spec(_task_fk_spec)
                _task_fk_spec.loader.exec_module(_task_fk)
                print("UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="+
                      _task_fk.classify_exception(_seed_failure),flush=True)
'''
class TaskForeignKeyRefusal(AssertionError):
    pass

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()

def classify_exception(exc):
    if not isinstance(exc,subprocess.CalledProcessError) or not isinstance(exc.stderr,str):
        return "non_psql_exception"
    names=[]
    for line in exc.stderr.splitlines():
        if not re.search(r"(?i)(?:ERROR|FATAL):",line):
            continue
        m=re.search(r'(?i)\bviolates foreign key constraint\s+"([a-z0-9_]+)"',line)
        if m:
            names.append(m.group(1).lower())
    if not names:
        return "error_without_constraint"
    if len(names)!=1:
        return "multiple_fk"
    name=names[0]
    if not name.startswith("tasks_") or not name.endswith("_fkey"):
        return "not_task_fk"
    if name in EXACT:
        return EXACT[name]
    for suffix,label in FAMILIES:
        if name.endswith(suffix):
            return label
    return "task_unclassified"

def extract(log):
    if not isinstance(log,str):
        return "untrusted_report"
    key="UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="
    lines=[line[len(key):] for line in log.splitlines() if line.startswith(key)]
    if not lines:
        return "not_reported"
    if len(lines)!=1:
        return "ambiguous_report"
    return lines[0] if lines[0] in FIXED else "untrusted_report"

def inject(classified_driver,helper_blob):
    if not isinstance(classified_driver,bytes) or not re.fullmatch(r"[a-f0-9]{40}",helper_blob):
        raise TaskForeignKeyRefusal("Exactly pinned v5 signed driver required")
    try:
        source=classified_driver.decode("utf8")
    except UnicodeError:
        raise TaskForeignKeyRefusal("Invalid signed source encoding") from None
    for anchor in (ANCHOR,V5_BLOB,V4_BLOB,FIXTURE_BLOB,
                   "_legacy.install(a.db_url,_prior_mowing_traced_sql)",
                   "_legacy.require_preserved(","history_receipt=hist.prove(",
                   "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS"):
        if source.count(anchor)!=1:
            raise TaskForeignKeyRefusal("Immutable prior signed wrapper changed")
    if "UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT=" in source:
        raise TaskForeignKeyRefusal("Already instrumented")
    rendered=source.replace(ANCHOR,ANCHOR+EXTRA.format(blob=helper_blob),1)
    ast.parse(rendered)
    if rendered.count("UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT=")!=1:
        raise TaskForeignKeyRefusal("Exactly one finite task reference receipt")
    return rendered.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--fk-driver",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    scratch=os.environ.get("RUNNER_TEMP")
    if not scratch or not Path(scratch).is_dir():
        raise TaskForeignKeyRefusal("No owned disposable runner root")
    root=Path(scratch).resolve()
    if (not a.fk_driver.is_file() or a.fk_driver.is_symlink()
        or a.fk_driver.parent.resolve()!=root
        or a.fk_driver.name!="validate-uniops-prior-mowing-fk-locus-local-only.py"):
        raise TaskForeignKeyRefusal("Only the exact v5 disposable signed driver")
    if (not a.output.is_absolute() or a.output.parent.resolve()!=root
        or a.output.name!=OUTPUT or a.output.exists()):
        raise TaskForeignKeyRefusal("Only a new expected disposable output")
    result=inject(a.fk_driver.read_bytes(),git_blob(Path(__file__).read_bytes()))
    with a.output.open("xb") as stream:
        stream.write(result)
    os.chmod(a.output,0o600)
    print("PASS source-only closed Task FK family refinement; NO SQL EXECUTED")

if __name__=="__main__":
    main()

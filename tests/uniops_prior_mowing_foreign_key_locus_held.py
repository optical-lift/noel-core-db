#!/usr/bin/env python3
"""HELD/source-only: identify one bounded foreign-key *locus* in the fictional seed.

Original signed actor source, production schema, SQL statements and private log
are not modified. This module never returns an error message, constraint name,
table row, SQL string or secret: only finite pre-reviewed labels. It operates
only on the existing disposable v4 classifier's private caught exception.
"""
import argparse
import ast
import hashlib
import os
from pathlib import Path
import re
import subprocess

SOURCE_V4_HELPER_BLOB="3847bebca7490bfc4bfbad7f629a6b26f64d7acd"
SOURCE_V3_FIXTURE_BLOB="ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc"
SOURCE_V4_ANCHOR='''                print("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="+
                      _sc.classify_exception(_seed_failure),flush=True)
'''
OUTPUT_NAME="validate-uniops-prior-mowing-fk-locus-local-only.py"
LABELS={
    "work_definitions_farm_id_fkey":"definition_farm",
    "work_release_policies_farm_id_fkey":"policy_farm",
    "work_release_policies_work_definition_id_fkey":"policy_definition",
    "planned_work_occurrences_farm_id_fkey":"occurrence_farm",
    "planned_work_occurrences_work_definition_id_fkey":"occurrence_definition",
    "planned_work_occurrences_release_policy_id_fkey":"occurrence_policy",
    "planned_work_occurrences_parent_occurrence_id_fkey":"occurrence_parent",
    "planned_work_occurrences_released_task_id_fkey":"occurrence_released_task",
    "tasks_organization_id_fkey":"task_organization",
    "tasks_farm_id_fkey":"task_farm",
    "tasks_planned_occurrence_id_fkey":"task_occurrence",
    "tasks_release_policy_id_fkey":"task_policy",
    "task_release_events_farm_id_fkey":"release_event_farm",
    "task_release_events_occurrence_id_fkey":"release_event_occurrence",
    "task_release_events_release_policy_id_fkey":"release_event_policy",
    "task_release_events_task_id_fkey":"release_event_task",
}
FAMILIES={
    "work_definitions_":"definition_other",
    "work_release_policies_":"policy_other",
    "planned_work_occurrences_":"occurrence_other",
    "tasks_":"task_other",
    "task_release_events_":"release_event_other",
    "work_execution_adapters_":"execution_adapter_other",
    "work_items_":"company_work_other",
    "work_allocations_":"allocation_other",
}
FIXED=frozenset(set(LABELS.values())|set(FAMILIES.values())|{
    "unknown_fk","multiple_fk","error_without_constraint","non_psql_exception",
    "not_reported","ambiguous_report","untrusted_report","untrusted_source"
})

# This is *added* after the existing v4 classifier; the original failure
# always propagates and the original v4 foreign_key receipt is preserved.
EXTRA='''                _fk_path=ROOT/"tests"/"uniops_prior_mowing_foreign_key_locus_held.py"
                check(_fk_path.is_file() and not _fk_path.is_symlink(),
                      "Reviewed foreign-key locus helper missing")
                _fk_bytes=_fk_path.read_bytes()
                import hashlib as _fk_hashlib
                _fk_sha=_fk_hashlib.sha1(
                    b"blob "+str(len(_fk_bytes)).encode("ascii")+b"\\\\0"+_fk_bytes
                ).hexdigest()
                check(_fk_sha=="{blob}",
                      "Reviewed foreign-key locus helper changed")
                _fk_spec=importlib.util.spec_from_file_location(
                    "uniops_prior_mowing_foreign_key_locus_held",_fk_path)
                check(_fk_spec is not None and _fk_spec.loader is not None,
                      "Reviewed foreign-key locus helper unavailable")
                _fk=importlib.util.module_from_spec(_fk_spec)
                _fk_spec.loader.exec_module(_fk)
                print("UNI_OPS_PRIOR_MOWING_FK_LOCUS="+
                      _fk.classify_exception(_seed_failure),flush=True)
'''

class ForeignKeyLocusRefusal(AssertionError):
    pass

def classify_exception(exc):
    """Derive only a finite source-named family label; never return private text."""
    if not isinstance(exc,subprocess.CalledProcessError) or not isinstance(exc.stderr,str):
        return "non_psql_exception"
    names=[]
    for line in exc.stderr.splitlines():
        if not re.search(r"(?i)(?:ERROR|FATAL):",line):
            continue
        match=re.search(r'(?i)\bviolates foreign key constraint\s+"([a-z0-9_]+)"',line)
        if match:
            names.append(match.group(1).lower())
    if not names:
        return "error_without_constraint"
    if len(names)!=1:
        return "multiple_fk"
    name=names[0]
    if name in LABELS:
        return LABELS[name]
    for prefix,label in FAMILIES.items():
        if name.startswith(prefix) and name.endswith("_fkey"):
            return label
    return "unknown_fk"

def extract_locus(log):
    if not isinstance(log,str):
        return "untrusted_report"
    key="UNI_OPS_PRIOR_MOWING_FK_LOCUS="
    lines=[l[len(key):] for l in log.splitlines() if l.startswith(key)]
    if not lines:
        return "not_reported"
    if len(lines)!=1:
        return "ambiguous_report"
    return lines[0] if lines[0] in FIXED else "untrusted_report"

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()

def inject(classified_driver,helper_blob):
    if not isinstance(classified_driver,bytes):
        raise ForeignKeyLocusRefusal("Exact reviewed v4 scratch source required")
    if not re.fullmatch("[a-f0-9]{40}",helper_blob):
        raise ForeignKeyLocusRefusal("Exact classifier hash required")
    try:
        source=classified_driver.decode("utf8")
    except UnicodeError:
        raise ForeignKeyLocusRefusal("Unreviewed source encoding") from None
    for anchor in (
        SOURCE_V4_ANCHOR,SOURCE_V4_HELPER_BLOB,SOURCE_V3_FIXTURE_BLOB,
        "_legacy.install(a.db_url,_prior_mowing_traced_sql)",
        "_legacy.require_preserved(","history_receipt=hist.prove(",
        "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",
    ):
        if source.count(anchor)!=1:
            raise ForeignKeyLocusRefusal("Original exact signed source anchor changed")
    if "UNI_OPS_PRIOR_MOWING_FK_LOCUS=" in source:
        raise ForeignKeyLocusRefusal("Already patched")
    out=source.replace(SOURCE_V4_ANCHOR,
                       SOURCE_V4_ANCHOR+EXTRA.format(blob=helper_blob),1)
    ast.parse(out)
    if out.count("UNI_OPS_PRIOR_MOWING_FK_LOCUS=")!=1:
        raise ForeignKeyLocusRefusal("Only one bounded locus is permitted")
    return out.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--classified-driver",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    root=os.environ.get("RUNNER_TEMP")
    if not root or not Path(root).is_dir():
        raise ForeignKeyLocusRefusal("Explicit job-only runner scratch required")
    root=Path(root).resolve()
    if (not a.classified_driver.is_file() or a.classified_driver.is_symlink()
        or a.classified_driver.parent.resolve()!=root
        or a.classified_driver.name!="validate-uniops-prior-mowing-seed-classified-local-only.py"):
        raise ForeignKeyLocusRefusal("Only the exact corrected classified driver copy")
    if (not a.output.is_absolute() or a.output.parent.resolve()!=root
        or a.output.name!=OUTPUT_NAME or a.output.exists()):
        raise ForeignKeyLocusRefusal("Output must be a new exact ephemeral name")
    own=Path(__file__).read_bytes()
    content=inject(a.classified_driver.read_bytes(),git_blob(own))
    with a.output.open("xb") as sink:
        sink.write(content)
    os.chmod(a.output,0o600)
    print("PASS bounded FK locus source instrumentation only; NO SQL EXECUTED")

if __name__=="__main__":
    main()

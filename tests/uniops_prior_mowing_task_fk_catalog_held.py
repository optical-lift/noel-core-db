#!/usr/bin/env python3
"""HELD: classify only the unclassified Task FK using disposable PG catalog.

Reads one catalog relation in the isolated loopback clone AFTER the original
fixture failure. It never prints a constraint, relation, column, SQL exception,
row, source record, credential, or traceback. The frozen failed INSERT is
re-raised unchanged. This has NO authority to run a protected job.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

V6_BLOB = "33340d412df23d4ee608d894a37dce638ea73b2b"
V5_BLOB = "a18904f46719457ae06ca301ed1c12323a5ca3c2"
V4_BLOB = "3847bebca7490bfc4bfbad7f629a6b26f64d7acd"
FIXTURE_BLOB = "ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc"
LOCAL_DB = r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres"
ANCHOR = '''                print("UNI_OPS_PRIOR_MOWING_TASK_FK_REFINEMENT="+
                      _task_fk.classify_exception(_seed_failure),flush=True)
'''
OUTPUT = "validate-uniops-prior-mowing-task-fk-catalog-local-only.py"
RECEIPT = "UNI_OPS_PRIOR_MOWING_TASK_FK_CATALOG="

# A fixed, non-sensitive semantic vocabulary. No dynamic catalog names can
# appear in public receipts. The unknown case must remain unresolved.
COLUMN_FAMILIES = {
    "generated_from_id": "task_generated_source",
    "organization_id": "task_organization",
    "farm_id": "task_farm",
    "planned_occurrence_id": "task_planned_occurrence",
    "release_policy_id": "task_release_policy",
    "parent_task_id": "task_parent",
    "assigned_membership_id": "task_assigned_membership",
    "assigned_user_id": "task_assigned_user",
    "assigned_to_user_id": "task_assigned_user",
    "owner_user_id": "task_owner_user",
    "created_by_user_id": "task_creator_user",
    "created_by": "task_creator_user",
    "zone_id": "task_zone",
    "project_id": "task_project",
    "crop_cycle_id": "task_crop_cycle",
    "growing_object_id": "task_growing_object",
    "work_definition_id": "task_work_definition",
    "work_item_id": "task_work_item",
    "work_allocation_id": "task_work_allocation",
    "source_task_id": "task_source_task",
    "source_id": "task_source",
    "person_id": "task_person",
    "organization_membership_id": "task_organization_membership",
    "farm_membership_id": "task_farm_membership",
}
REFERENCED_FAMILIES = {
    "atlas.rhythm_state": "task_ref_rhythm_state",
    "atlas.tasks": "task_ref_task",
    "atlas.work_definitions": "task_ref_work_definition",
    "atlas.work_release_policies": "task_ref_release_policy",
    "atlas.planned_work_occurrences": "task_ref_occurrence",
    "atlas.farm_memberships": "task_ref_membership",
    "atlas.organization_memberships": "task_ref_membership",
    "auth.users": "task_ref_user",
    "atlas.farms": "task_ref_farm",
    "atlas.organizations": "task_ref_organization",
}
SPECIAL = {
    "not_reported", "untrusted_report", "ambiguous_report",
    "non_psql_exception", "multiple_fk", "wrong_fk_family",
    "non_disposable", "catalog_unavailable", "catalog_untrusted",
    "catalog_unknown_column", "prior_stage_mismatch", "untrusted_source",
}
FIXED = frozenset(COLUMN_FAMILIES.values()) | frozenset(REFERENCED_FAMILIES.values()) | SPECIAL

EXTRA = '''                _cat_path=ROOT/"tests"/"uniops_prior_mowing_task_fk_catalog_held.py"
                check(_cat_path.is_file() and not _cat_path.is_symlink(),
                      "Reviewed task catalog classifier missing")
                import hashlib as _cat_hashlib
                _cat_bytes=_cat_path.read_bytes()
                _cat_blob=_cat_hashlib.sha1(
                    b"blob "+str(len(_cat_bytes)).encode("ascii")+b"\\0"+_cat_bytes
                ).hexdigest()
                check(_cat_blob=="{blob}","Task catalog classifier changed")
                _cat_spec=importlib.util.spec_from_file_location(
                    "uniops_prior_mowing_task_fk_catalog_held",_cat_path)
                check(_cat_spec is not None and _cat_spec.loader is not None,
                      "Task catalog classifier unavailable")
                _cat=importlib.util.module_from_spec(_cat_spec)
                _cat_spec.loader.exec_module(_cat)
                _cat_label=(
                    _cat.classify_exception(_seed_failure,a.db_url,sql)
                    if _task_fk.classify_exception(_seed_failure)=="task_unclassified"
                    else "prior_stage_mismatch"
                )
                print("UNI_OPS_PRIOR_MOWING_TASK_FK_CATALOG="+_cat_label,flush=True)
'''

class TaskCatalogRefusal(AssertionError):
    pass

def git_blob(raw):
    return hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()

def constraint_from_exception(exc):
    if not isinstance(exc, subprocess.CalledProcessError) or not isinstance(exc.stderr, str):
        return None
    matches=[]
    for line in exc.stderr.splitlines():
        if not re.search(r"(?i)(?:ERROR|FATAL):",line):
            continue
        hit=re.search(r'(?i)\bviolates foreign key constraint\s+"([a-z0-9_]+)"',line)
        if hit:
            matches.append(hit.group(1).lower())
    return matches[0] if len(matches)==1 else None

def catalog_query(name):
    if not isinstance(name,str) or not re.fullmatch(r"tasks_[a-z0-9_]+_fkey",name):
        raise TaskCatalogRefusal("Unknown Task constraint identifier")
    # Only pg_catalog structural metadata in disposable postgres database.
    # The query's raw result stays in process; only classified labels print.
    return f"""SELECT COALESCE((
 SELECT jsonb_build_object(
  'columns', (SELECT jsonb_agg(a.attname ORDER BY k.ord)
              FROM unnest(c.conkey) WITH ORDINALITY k(num,ord)
              JOIN pg_catalog.pg_attribute a
                ON a.attrelid=c.conrelid AND a.attnum=k.num),
  'reference', nr.nspname || '.' || tr.relname)::text
 FROM pg_catalog.pg_constraint c
 JOIN pg_catalog.pg_class tc ON tc.oid=c.conrelid
 JOIN pg_catalog.pg_namespace nt ON nt.oid=tc.relnamespace
 JOIN pg_catalog.pg_class tr ON tr.oid=c.confrelid
 JOIN pg_catalog.pg_namespace nr ON nr.oid=tr.relnamespace
 WHERE current_database()='postgres'
   AND nt.nspname='atlas' AND tc.relname='tasks'
   AND c.contype='f' AND c.conname='{name}'
), 'null')"""

def classify_catalog(raw):
    if not isinstance(raw,str) or len(raw)>5000 or raw.count("\n")>1:
        return "catalog_untrusted"
    try:
        value=json.loads(raw.strip())
    except (ValueError, TypeError):
        return "catalog_untrusted"
    if not isinstance(value,dict) or set(value)!={"columns","reference"}:
        return "catalog_untrusted"
    cols=value["columns"]
    ref=value["reference"]
    if (not isinstance(cols,list) or not 1<=len(cols)<=3 or
        not all(isinstance(c,str) and re.fullmatch(r"[a-z0-9_]{1,80}",c) for c in cols) or
        not isinstance(ref,str) or not re.fullmatch(r"[a-z0-9_]+\.[a-z0-9_]+",ref)):
        return "catalog_untrusted"
    if len(cols)==1 and cols[0] in COLUMN_FAMILIES:
        return COLUMN_FAMILIES[cols[0]]
    return REFERENCED_FAMILIES.get(ref,"catalog_unknown_column")

def classify_exception(exc, db_url, sql):
    if not isinstance(exc, subprocess.CalledProcessError) or not isinstance(exc.stderr,str):
        return "non_psql_exception"
    name=constraint_from_exception(exc)
    if name is None:
        return "multiple_fk"
    if not name.startswith("tasks_") or not name.endswith("_fkey"):
        return "wrong_fk_family"
    if not isinstance(db_url,str) or not re.fullmatch(LOCAL_DB,db_url) or not callable(sql):
        return "non_disposable"
    try:
        raw=sql(db_url,catalog_query(name))
    except Exception:
        return "catalog_unavailable"
    return classify_catalog(raw)

def extract(log):
    if not isinstance(log,str):
        return "untrusted_report"
    vals=[line[len(RECEIPT):] for line in log.splitlines() if line.startswith(RECEIPT)]
    if not vals:
        return "not_reported"
    if len(vals)!=1:
        return "ambiguous_report"
    return vals[0] if vals[0] in FIXED else "untrusted_report"

def inject(v6_driver, helper_blob):
    if not isinstance(v6_driver,bytes) or not re.fullmatch(r"[0-9a-f]{40}",helper_blob):
        raise TaskCatalogRefusal("Pinned v6 driver required")
    try:
        code=v6_driver.decode("utf8")
    except UnicodeError:
        raise TaskCatalogRefusal("Invalid signed source encoding") from None
    for token in (ANCHOR,V6_BLOB,V5_BLOB,V4_BLOB,FIXTURE_BLOB,
                  "_legacy.install(a.db_url,_prior_mowing_traced_sql)",
                  "_legacy.require_preserved(","history_receipt=hist.prove(",
                  "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS"):
        if code.count(token)!=1:
            raise TaskCatalogRefusal("Immutable prior signed source changed")
    if RECEIPT in code:
        raise TaskCatalogRefusal("Already catalog instrumented")
    result=code.replace(ANCHOR,ANCHOR+EXTRA.format(blob=helper_blob),1)
    ast.parse(result)
    if result.count(RECEIPT)!=1:
        raise TaskCatalogRefusal("Expected one bounded classifier receipt")
    return result.encode("utf8")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--v6-driver",required=True,type=Path)
    p.add_argument("--output",required=True,type=Path)
    a=p.parse_args()
    scratch=os.environ.get("RUNNER_TEMP")
    if not scratch or not Path(scratch).is_dir():
        raise TaskCatalogRefusal("No owned disposable runner root")
    root=Path(scratch).resolve()
    if (not a.v6_driver.is_file() or a.v6_driver.is_symlink() or
        a.v6_driver.parent.resolve()!=root or
        a.v6_driver.name!="validate-uniops-prior-mowing-task-fk-local-only.py"):
        raise TaskCatalogRefusal("Only exact v6 disposable driver")
    if (not a.output.is_absolute() or a.output.parent.resolve()!=root or
        a.output.name!=OUTPUT or a.output.exists()):
        raise TaskCatalogRefusal("Only new expected disposable output")
    result=inject(a.v6_driver.read_bytes(),git_blob(Path(__file__).read_bytes()))
    with a.output.open("xb") as f:
        f.write(result)
    os.chmod(a.output,0o600)
    print("PASS source-only Task FK catalog classifier; NO SQL EXECUTED")

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""HELD TEST ONLY — finite SQL error classification for the prior-mowing seed.

No live database, credentials, SQL payload or error text is logged by this
module. Original #2799 fixture, v3 corrected disposable fixture, U2/U4/P3
signed actors, governor and historical cancellation SQL are unchanged.
Only a strict client-side error CATEGORY is emitted from an existing
subprocess.CalledProcessError raised during the fiction-only seed.
"""
import argparse
import ast
import os
from pathlib import Path
import re
import subprocess

FIXED_FIXTURE_BLOB = "ae5da30ca5953ad9bd7cb17ed09fd00ab4825dfc"
ANCHOR = "        return sql(_db,_statement)\n"
OUTPUT_NAME = "validate-uniops-prior-mowing-seed-classified-local-only.py"
CATEGORIES = frozenset((
    "preflight_guard","postcondition_guard","task_release_gate",
    "task_release_farm_guard","foreign_key","not_null","check_constraint",
    "uniqueness","exclusion","rls","privilege","missing_relation",
    "missing_column","missing_function","invalid_value","syntax",
    "other_sql_error","psql_without_error_line","non_psql_exception",
    "not_reported","ambiguous_report","untrusted_report","untrusted_source",
))
PHASED_PATCH = '''        try:
            return sql(_db,_statement)
        except Exception as _seed_failure:
            if _next == "physical_seed_called":
                # Read only this exact reviewed test-only classifier source.
                _sc_path=ROOT/"tests"/"uniops_prior_mowing_seed_error_classification_held.py"
                check(_sc_path.is_file() and not _sc_path.is_symlink(),
                      "Reviewed physical seed category helper absent")
                _sc_raw=_sc_path.read_bytes()
                import hashlib as _sc_hashlib
                _sc_sha=_sc_hashlib.sha1(
                    b"blob "+str(len(_sc_raw)).encode("ascii")+b"\\0"+_sc_raw
                ).hexdigest()
                check(_sc_sha == "{classifier_blob}",
                      "Reviewed physical seed category helper changed")
                _sc_spec=importlib.util.spec_from_file_location(
                    "uniops_prior_mowing_seed_error_classification_held",_sc_path)
                check(_sc_spec is not None and _sc_spec.loader is not None,
                      "Reviewed physical seed category helper unavailable")
                _sc=importlib.util.module_from_spec(_sc_spec)
                _sc_spec.loader.exec_module(_sc)
                print("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="+
                      _sc.classify_exception(_seed_failure),flush=True)
            raise
'''

class SeedErrorCategoryRefusal(AssertionError):
    pass

def classify_exception(exc):
    """Never return a fragment of stderr, SQL, credentials, error or traceback."""
    if not isinstance(exc,subprocess.CalledProcessError):
        return "non_psql_exception"
    err=exc.stderr
    if not isinstance(err,str):
        return "psql_without_error_line"
    # psql may include a filename/line before ERROR; no filename is exposed.
    message=[]
    for line in err.splitlines():
        m=re.search(r"(?i)(?:^|:\s*)(?:ERROR|FATAL):\s*(.*)$",line)
        if m:
            message.append(m.group(1).lower())
    if not message:
        return "psql_without_error_line"
    # A single source error may be surrounded by CONTEXT/detail lines.
    detail=message[0]
    labels=(
      ("preflight_guard",r"prior-mowing fixture requires clean prepolicy disposable source"),
      ("postcondition_guard",r"prior-mowing fixture did not establish exact linked carriers"),
      ("task_release_gate",r"active tasks require a planned occurrence"),
      ("task_release_farm_guard",r"task release gate does not belong to the task farm"),
      ("foreign_key",r"violates foreign key constraint|is not present in table"),
      ("not_null",r"null value in column|not-null constraint"),
      ("check_constraint",r"violates check constraint|check constraint"),
      ("uniqueness",r"duplicate key value|unique constraint"),
      ("exclusion",r"exclusion constraint"),
      ("rls",r"row-level security policy"),
      ("privilege",r"permission denied|insufficient privilege"),
      ("missing_relation",r"relation .+ does not exist"),
      ("missing_column",r"column .+ does not exist"),
      ("missing_function",r"function .+ does not exist"),
      ("invalid_value",r"invalid input syntax|value out of range"),
      ("syntax",r"syntax error"),
    )
    for label,expr in labels:
        if re.search(expr,detail):
            return label
    return "other_sql_error"

def extract_category(log):
    if not isinstance(log,str):
        return "untrusted_report"
    prefix="UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS="
    lines=[line[len(prefix):] for line in log.splitlines() if line.startswith(prefix)]
    if not lines:
        return "not_reported"
    if len(lines)!=1:
        return "ambiguous_report"
    value=lines[0]
    return value if value in CATEGORIES else "untrusted_report"

def inject(fixed_driver, classifier_blob):
    if not isinstance(fixed_driver,bytes):
        raise SeedErrorCategoryRefusal("Exactly one reviewed signed source required")
    if not re.fullmatch(r"[a-f0-9]{40}",classifier_blob):
        raise SeedErrorCategoryRefusal("Immutable classifier blob required")
    try:
        source=fixed_driver.decode("utf8")
    except UnicodeError:
        raise SeedErrorCategoryRefusal("Invalid signed source encoding") from None
    for token in (ANCHOR,FIXED_FIXTURE_BLOB,"_legacy.install(a.db_url,_prior_mowing_traced_sql)",
                  "UNI_OPS_PRIOR_MOWING_AFTER_HISTORY=PASS",
                  "history_receipt=hist.prove("):
        if source.count(token)!=1:
            raise SeedErrorCategoryRefusal("Original signed driver exact source changed")
    if "UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS=" in source:
        raise SeedErrorCategoryRefusal("Error classifier already installed")
    rendered=source.replace(ANCHOR,PHASED_PATCH.format(classifier_blob=classifier_blob),1)
    ast.parse(rendered)
    if rendered.count("UNI_OPS_PRIOR_MOWING_SEED_SQL_ERROR_CLASS=")!=1:
        raise SeedErrorCategoryRefusal("Only one classified fixture error permitted")
    return rendered.encode("utf8")

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--fixed-driver",required=True,type=Path)
    parser.add_argument("--output",required=True,type=Path)
    a=parser.parse_args()
    temp=os.environ.get("RUNNER_TEMP")
    if not temp or not Path(temp).is_dir():
        raise SeedErrorCategoryRefusal("Explicit ephemeral runner root required")
    root=Path(temp).resolve()
    if (not a.fixed_driver.is_file() or a.fixed_driver.is_symlink()
        or a.fixed_driver.parent.resolve()!=root
        or a.fixed_driver.name!="validate-uniops-prior-mowing-fixed-signed-local-only.py"):
        raise SeedErrorCategoryRefusal("Exact disposable corrected source required")
    if (not a.output.is_absolute() or a.output.parent.resolve()!=root
        or a.output.name!=OUTPUT_NAME or a.output.exists()):
        raise SeedErrorCategoryRefusal("Output must be new exact disposable script")
    raw=Path(__file__).read_bytes()
    import hashlib
    blob=hashlib.sha1(b"blob "+str(len(raw)).encode("ascii")+b"\0"+raw).hexdigest()
    result=inject(a.fixed_driver.read_bytes(),blob)
    with a.output.open("xb") as stream:
        stream.write(result)
    os.chmod(a.output,0o600)
    print("PASS bounded physical-seed SQL error category script SOURCE ONLY; no SQL invoked")

if __name__=="__main__":
    main()

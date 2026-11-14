#!/usr/bin/env python3
"""HELD P3 private-error classifier. No SQL, network, database or authorization.

The protected validator has ALREADY failed. Convert ONLY an exact recognized
static source-authored P3 structural assertion into one finite diagnostic enum.
Never reveal the private PostgreSQL error line, source SQL, actor or row data.
"""
from pathlib import Path
import hashlib

PHRASES=(
 ("core_source_missing","Core 6A exact accepted-first/original source missing"),
 ("result_only_evaluator_missing","Result/Done must evaluate state without issuing new Work"),
 ("governed_signal_guard_missing","Source-specific governed clock hold or preserved independent signal missing"),
 ("legacy_task_bypass_open","Existing legacy rhythm Task/occurrence bypass remains"),
 ("accepted_first_commit_proof_missing","One accepted first original guard or governed COMMIT proof missing"),
 ("atomic_original_triggers_missing","Atomic first-original triggers not attached and enabled"),
 ("private_function_acl_exposed","Private 6A authority became callable by API role"),
)
P3_POSTCONDITION_SHA="210c42f97ceebc8dde2b493e898d23747cce7787"

def git_blob(value):
    return hashlib.sha1(
      b"blob "+str(len(value)).encode("ascii")+b"\0"+value
    ).hexdigest()

def source_catalog_valid(path):
    p=Path(path)
    if not p.is_file() or p.is_symlink():
        return False
    raw=p.read_bytes()
    if git_blob(raw)!=P3_POSTCONDITION_SHA:
        return False
    body=raw.decode("utf8")
    # Every label is sourced from a distinct immutable RAISE EXCEPTION and
    # never matches dynamic data or uncatalogued diagnostic messages.
    return all(body.count("'"+message+"'")==1 for _,message in PHRASES)

def classify(error_line, source_stage, source_path):
    if source_stage!="p3-mowing-postconditions":
        return "not_applicable"
    if not source_catalog_valid(source_path):
        return "unverified_source"
    if not isinstance(error_line,str) or not error_line.startswith("psql:"):
        return "error_absent"
    # Only an exact single error line can be classified. Refuse multi-line
    # source text, raw SQL or a composite/multiple source assertion.
    if "\n" in error_line or len(error_line)>2048 or (
            "ERROR:" not in error_line):
        return "unclassified_or_ambiguous"
    matched=[label for label,phrase in PHRASES if phrase in error_line]
    return matched[0] if len(matched)==1 else "unclassified_or_ambiguous"

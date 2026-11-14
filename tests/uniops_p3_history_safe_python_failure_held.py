#!/usr/bin/env python3
"""HELD source-only private signed-run error classifier.

Reads the already-private disposable test log ONLY within the protected job.
Emits fixed, non-sensitive enums. Never emits a traceback, SQL, JWT, actor,
file path, PostgREST response, UUID or arbitrary exception string.
No network, database access, runtime actor changes or production mutation.
"""
import re

EXCEPTION_CLASSES={
    "AssertionError":"source_assertion",
    "NameError":"python_name_error",
    "AttributeError":"python_attribute_error",
    "KeyError":"python_key_error",
    "TypeError":"python_type_error",
    "ValueError":"python_value_error",
    "IndexError":"python_index_error",
    "ImportError":"python_import_error",
    "ModuleNotFoundError":"python_module_missing",
    "FileNotFoundError":"local_file_missing",
    "PermissionError":"local_file_permission",
    "RuntimeError":"python_runtime_error",
    "CalledProcessError":"local_sql_subprocess_error",
    "TimeoutExpired":"local_process_timeout",
    "JSONDecodeError":"python_json_error",
    "SystemExit":"python_system_exit",
    "ConnectionError":"local_transport_error",
}
P3_MARK="P3_6A_SIGNED_RESULT_SNAPSHOT=PASS"
HISTORY_MARK="UNI_OPS_P3_MOWING_AFTER_HISTORY=PASS"
GOVERNOR_MARK="PASS genuine signed governor historic retirement:"
MAX_BYTES=2_000_000

def classify(private_log):
    if not isinstance(private_log,str):
        return ("log_unavailable","log_unavailable")
    # Strictly limit memory and refuse large/corrupted artifacts. No raw data
    # is ever returned or printed even for malformed input.
    if len(private_log.encode("utf8",errors="replace"))>MAX_BYTES:
        return ("log_oversize","not_classified")
    lines=private_log.splitlines()
    exact=set(x.strip() for x in lines)
    if HISTORY_MARK in exact:
        milestone="mowing_conserved_after_history"
    elif GOVernor_receipt_present(lines):
        milestone="governor_receipt_before_conservation"
    elif P3_MARK in exact:
        milestone="mowing_p3_signed_before_history"
    else:
        milestone="mowing_p3_not_proven_in_this_run"
    # Match only the LAST Python traceback's terminal exception class.
    # An exception string can contain user/SQL secrets; NEVER return it.
    last=None
    for line in lines:
        if line.startswith("Traceback (most recent call last):"):
            last=None
        m=re.match(r"^(?:(?:[a-z][a-z0-9_]*\.){0,3})?([A-Za-z][A-Za-z0-9_]*):",line)
        if m:
            last=m[1]
    return milestone,EXCEPTION_CLASSES.get(last,"unknown_or_absent_exception")

def GOVernor_receipt_present(lines):
    # The historical companion's result may be printed on private stdout,
    # but no source receipt is fabricated or assumed if absent.
    return any(x.startswith(GOVERNOR_MARK) for x in lines)

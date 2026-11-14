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
HANDOFF_STAGES=frozenset((
    "pre_snapshot_started","pre_snapshot_captured","fixture_adapter_ready",
    "governor_started","governor_returned",
    "conservation_started","conservation_verified"
))
FIXTURE_STAGES=frozenset((
    "membership_preflight","membership_query_failed","membership_absent",
    "membership_not_exactly_one","membership_confirmed",
    "person_identity_preflight","identity_query_failed",
    "person_identity_misaligned","membership_create_authorized",
    "membership_postseed_not_one","membership_created",
    "seed_apply_started","seed_apply_failed","seed_applied",
    "allocation_preflight","allocation_query_failed",
    "allocation_not_exactly_one","fixture_verified"
))
HANDOFF_PREFIX="UNI_OPS_HISTORY_HANDOFF_STAGE="
FIXTURE_PREFIX="UNI_OPS_HISTORY_FIXTURE_STAGE="

SEED_SQL_KINDS=frozenset((
    "unique_constraint","foreign_key_constraint","check_constraint",
    "not_null_constraint","row_security","permission_denied",
    "missing_column","missing_relation","invalid_enum","data_type",
    "other_postgres_error","unclassified"
))
SEED_PROGRESS=frozenset((
    "not_located","after_one_insert_tag","after_two_insert_tags",
    "after_three_insert_tags"
))
SEED_KIND_PREFIX="UNI_OPS_HISTORY_SEED_SQL_KIND="
SEED_PROGRESS_PREFIX="UNI_OPS_HISTORY_SEED_PROGRESS="

def classify_seed_detail(private_log):
    """Safe finite enums only; no private SQL, psql stdout or stderr exposed."""
    if not isinstance(private_log,str):
        return "log_unavailable","log_unavailable"
    if len(private_log.encode("utf8",errors="replace"))>MAX_BYTES:
        return "log_oversize","log_oversize"
    kind,progress="not_reported","not_reported"
    for line in private_log.splitlines():
        if line.startswith(SEED_KIND_PREFIX):
            value=line[len(SEED_KIND_PREFIX):]
            if value not in SEED_SQL_KINDS:
                return "unverified","unverified"
            kind=value
        elif line.startswith(SEED_PROGRESS_PREFIX):
            value=line[len(SEED_PROGRESS_PREFIX):]
            if value not in SEED_PROGRESS:
                return "unverified","unverified"
            progress=value
    return kind,progress

def classify_stage(private_log):
    """Classify the last fixed source-owned stage, never arbitrary log contents.

    Stage evidence is NOT an authenticated acceptance or conservation receipt.
    """
    if not isinstance(private_log,str):
        return "log_unavailable"
    if len(private_log.encode("utf8",errors="replace"))>MAX_BYTES:
        return "log_oversize"
    latest=None
    for line in private_log.splitlines():
        if line.startswith(HANDOFF_PREFIX):
            value=line[len(HANDOFF_PREFIX):]
            if value not in HANDOFF_STAGES:
                return "unverified_stage"
            latest="handoff_"+value
        elif line.startswith(FIXTURE_PREFIX):
            value=line[len(FIXTURE_PREFIX):]
            if value not in FIXTURE_STAGES:
                return "unverified_stage"
            latest="fixture_"+value
    if latest is not None:
        return latest
    if P3_MARK in {line.strip() for line in private_log.splitlines()}:
        return "p3_checkpoint_before_handoff"
    return "history_stage_not_reached"

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

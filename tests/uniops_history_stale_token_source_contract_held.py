#!/usr/bin/env python3
"""HELD SOURCE-REVIEW PROPOSAL ONLY. No SQL execution or DB access.

One atomic, independently REVIEWABLE, not-approved correction to the historical
retirement stale-impact error and its signed adapter expectation. The original
#2368 source remains immutable and authorized as-is until a separate owner
source-law decision. A proposal is NOT a passing signed receipt or release.
"""
import hashlib

HISTORY_COMMIT = "ddfb0bf5374798301fe076a61d2b944dfb52ff63"
HISTORY_PATH = "candidates/atlas_universal_work_lifecycle_v1/20_native_historical_retirement_candidate.sql"
HISTORY_BLOB = "93f7b9cf0bad5eb536ffa90d3973aabfe75542d9"
BRIDGE_COMMIT = "1be7e54778c7fc6c3941aace036d8c4c4f63c2c1"
BRIDGE_PATH = "tests/uniops_historical_retirement_signed_bridge_held.py"
BRIDGE_BLOB = "f1a4eadb4d0199e8b4d9c1f17738675c281e249d"

OLD_SQL = b"""   RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
   USING ERRCODE='40001'; END IF;"""
NEW_SQL = b"""   RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
   USING ERRCODE='PT409'; END IF;"""
OLD_BRIDGE = b"""    \"\"\"Exact known source denial: stale snapshot is serialization failure.\"\"\"
    if label == "Stale dependency snapshot must not cancel Work":
        return "40001"
    return "42501" """
NEW_BRIDGE = b"""    \"\"\"Proposed review-only non-retryable stale-impact conflict code.\"\"\"
    if label == "Stale dependency snapshot must not cancel Work":
        return "PT409"
    return "42501" """
OLD_STATUS = b"""        if status not in (400, 401, 403, 409) or code != expected_denial_code(label):
            raise HeldProofRefusal("Signed historical denial not established: " + label)"""
NEW_STATUS = b"""        expected = expected_denial_code(label)
        valid_status = status == 409 if expected == "PT409" else status in (400, 401, 403, 409)
        if not valid_status or code != expected:
            raise HeldProofRefusal("Signed historical denial not established: " + label)"""


class SourceLawHold(RuntimeError):
    """Only static labels. Do not forward source contents or private receipts."""


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\\0" + data).hexdigest()


def _replace_exact(original: bytes, old: bytes, new: bytes, label: str) -> bytes:
    if original.count(old) != 1:
        raise SourceLawHold("Unrecognized " + label + " source anchor")
    result = original.replace(old, new, 1)
    if result.count(old) != 0 or result.count(new) != 1:
        raise SourceLawHold("Unreviewed " + label + " source variation")
    return result


def propose_historical_conflict(sql: bytes, bridge: bytes) -> tuple[bytes, bytes]:
    """Derive in-memory review variants after exact independent Git-blob pins.

    No writes, SQL execution, access-control changes or remote service calls.
    Neither variant is authorized to install, merge or test as valid source.
    """
    if not isinstance(sql, bytes) or git_blob_sha(sql) != HISTORY_BLOB:
        raise SourceLawHold("Frozen historical retirement source mismatch")
    if not isinstance(bridge, bytes) or git_blob_sha(bridge) != BRIDGE_BLOB:
        raise SourceLawHold("Frozen signed adapter source mismatch")
    corrected_sql = _replace_exact(sql, OLD_SQL, NEW_SQL, "stale-impact SQLSTATE")
    corrected_bridge = _replace_exact(bridge, OLD_BRIDGE, NEW_BRIDGE, "signed error code")
    corrected_bridge = _replace_exact(
        corrected_bridge, OLD_STATUS, NEW_STATUS, "signed HTTP status guard"
    )
    # A stale token is still a denial; no reviewer may weaken the preflight.
    for sentinel in (
        b"IF md5(v_impact::text) IS DISTINCT FROM p_impact_token THEN",
        b"v_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(",
        b"FOR UPDATE;",
        b"v_actor:=atlas.company_work_native_ledger_owner_self_v1(",
    ):
        if corrected_sql.count(sentinel) != 1:
            raise SourceLawHold("Historical guard or single writer was altered")
    if b"ERRCODE='40001'" in corrected_sql or b'return "40001"' in corrected_bridge:
        raise SourceLawHold("Retryable stale-impact marker remains")
    if b"status == 409 if expected == \"PT409\"" not in corrected_bridge:
        raise SourceLawHold("Exact signed transport conflict guard absent")
    return corrected_sql, corrected_bridge

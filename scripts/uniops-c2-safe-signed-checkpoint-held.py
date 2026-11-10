#!/usr/bin/env python3
"""Expose only fixed C2 signed-test progress and public-source failure points.

The input is one private disposable runner-local C2 signed HTTP log. Never
print SQL, traceback paths, credentials, tokens, user or synthetic actor data.
There is no HTTP, SQL, database, fixture or production access in this module.
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

MARKERS = (
    ("PASS C2 installed disposable owner source matches supplied exact candidate", "installed_source"),
    ("PASS C2 signed owner: attested and verified source records shown; foreign/withdrawn/history denied", "owner_visibility"),
    ("PASS C2 source_verified: current proof admitted, stale native source suppressed", "stale_source"),
    ("PASS C2 other principals and wrong native scope denied", "negative_roles"),
    ("PASS C2 owner-attested withdrawal changes the very next signed L1 read", "owner_withdrawal"),
    ("PASS C2 source_verified withdrawal suppresses original without erasing Work", "verified_withdrawal"),
    ("PASS C2 signed read-only Work/Clock fingerprint and ACL matrix", "complete"),
)
MAX_LOG_BYTES = 131072
FALLBACK = "unclassified"
BEFORE_FIRST = "before_source_match"
LOOKUP = {message: (idx, label) for idx, (message, label) in enumerate(MARKERS)}

# Reviewed revised C2 signer source blob 67aa03f3224b06078559f55c40c3d78c4d2e7f8a.
# These are the nine public-source call sites between owner visibility
# PASS and the later source-proof invalidation PASS. A denied immutable
# booking reassignment is explicitly expected before disposable source removal.
# This mapping cannot authorize an exception; it only classifies a traceback.
SOURCE_TRANSITION_POINTS = {
    180: "immutable_booking_reassignment_denial",
    193: "immutable_l1_source_preserved",
    197: "immutable_l2_source_absent",
    205: "synthetic_source_removal",
    210: "removed_l1_source_absent",
    214: "removed_l2_source_absent",
    218: "persisted_relevance",
    224: "stale_owner_response",
    228: "work_clock_unchanged",
}
PUBLIC_MAIN_FRAME = re.compile(
    r'^\s*File "(?:[^"\r\n]*/)?validate-atlas-c2-case-work-signed-http[.]py", '
    r'line ([0-9]{1,4}), in main$'
)


def classify_log(source: str) -> str:
    matched = [LOOKUP[line] for line in source.splitlines() if line in LOOKUP]
    if not matched:
        return BEFORE_FIRST
    if [idx for idx, _ in matched] != list(range(len(matched))):
        return FALLBACK
    return matched[-1][1]


def classify_source_transition(log: str) -> str:
    frames = [
        int(match.group(1))
        for line in log.splitlines()
        if (match := PUBLIC_MAIN_FRAME.fullmatch(line))
    ]
    if len(frames) != 1:
        return FALLBACK
    return SOURCE_TRANSITION_POINTS.get(frames[0], FALLBACK)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("private_signed_log")
    args = parser.parse_args()
    path = Path(args.private_signed_log)
    verdict = FALLBACK
    point = FALLBACK
    try:
        if (path.is_file() and not path.is_symlink()
                and 0 < path.stat().st_size <= MAX_LOG_BYTES):
            log = path.read_text(encoding="utf-8")
            verdict = classify_log(log)
            if verdict == "owner_visibility":
                point = classify_source_transition(log)
    except (OSError, UnicodeError):
        pass
    print("C2_SIGNED_CHECKPOINT=" + verdict)
    if verdict == "owner_visibility":
        print("C2_SOURCE_TRANSITION_POINT=" + point)


if __name__ == "__main__":
    main()

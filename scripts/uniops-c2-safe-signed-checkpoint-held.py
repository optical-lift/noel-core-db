#!/usr/bin/env python3
"""Expose only a fixed C2 signed-test checkpoint, never its private log.

The input is a private, disposable runner-local signed HTTP log, not a
production log. This source-only classifier does not run SQL or contact HTTP.
Only exact, reviewed PASS lines in their original order are recognized.
No exception messages, actor fields, SQL, URLs or private output are printed.
"""
from __future__ import annotations

import argparse
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


def classify_log(source: str) -> str:
    matched = [LOOKUP[line] for line in source.splitlines() if line in LOOKUP]
    if not matched:
        return BEFORE_FIRST
    # A repeated or out-of-sequence PASS line is not a trustworthy checkpoint.
    if [idx for idx, _ in matched] != list(range(len(matched))):
        return FALLBACK
    return matched[-1][1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("private_signed_log")
    args = parser.parse_args()
    path = Path(args.private_signed_log)
    verdict = FALLBACK
    try:
        if (path.is_file() and not path.is_symlink()
                and 0 < path.stat().st_size <= MAX_LOG_BYTES):
            verdict = classify_log(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError):
        pass
    print("C2_SIGNED_CHECKPOINT=" + verdict)


if __name__ == "__main__":
    main()

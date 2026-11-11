#!/usr/bin/env python3
"""Safe fixed-label receipt for one protected ACCESS-01 disposable SQL clone.

No logs, SQL, source rows, stack traces, credentials, or user-controlled
strings can leave through this program. The owner-gated workflow retains
the actual validator's success/failure decision.
"""
import argparse
import os
import re
from pathlib import Path

MAX_BYTES = 16384
PHASE_CODES = {
    "preflight": "preflight",
    "release-lane custody check": "lane_custody",
    "validation fixture safety check": "fixture_safety",
    "schema dump sanitation": "schema_sanitation",
    "disposable database startup": "local_startup",
    "production custom-role restore": "role_restore",
    "production user-schema restore": "schema_restore",
    "baseline domain schema lint": "baseline_lint",
    "candidate validation fixture application": "fixture_application",
    "candidate migration application": "candidate_install",
    "candidate migration postconditions": "postconditions",
    "genuinely signed local ACCESS-01 Event identity versus wider Ledger disclosure": "signed_actor_matrix",
    "candidate domain schema lint": "candidate_lint",
    "candidate lint delta comparison": "lint_comparison",
    "local database advisors": "local_advisors",
    "complete": "complete",
}


def bounded_plain(path):
    """Reject symlinks, oversize files, binary data and missing files."""
    p = Path(path)
    try:
        if p.is_symlink() or not p.is_file() or p.stat().st_size > MAX_BYTES:
            return None
        b = p.read_bytes()
        if len(b) > MAX_BYTES or b"\x00" in b:
            return None
        return b.decode("utf-8")
    except (OSError, UnicodeError, ValueError):
        return None


def phase_from_summary(summary):
    if summary is None:
        return "unclassified"
    found = set()
    for line in summary.splitlines():
        line = line.strip()
        for label, code in PHASE_CODES.items():
            if line in (
                f"**FAILED during {label}.**",
                f"Validation command exited during \x60{label}\x60.",
            ):
                found.add(code)
    return next(iter(found)) if len(found) == 1 else "unclassified"


def exit_from_file(path):
    contents = bounded_plain(path)
    if contents is not None and re.fullmatch(r"(?:0|[1-9][0-9]{0,2})\s*", contents):
        value = int(contents)
        if 0 <= value <= 255:
            return value
    return None


def classify(exit_code, summary, signed_receipt):
    if exit_code == 0:
        if signed_receipt is not None and any(
            line.startswith("PASS ACCESS-01 signed ")
            for line in signed_receipt.splitlines()
        ):
            return "signed_pass"
        return "missing_signed_receipt"
    if exit_code == 124 or exit_code == 137:
        return "time_bound"
    if exit_code is None:
        return "exit_unknown"
    return phase_from_summary(summary)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone-exit", required=True)
    ap.add_argument("--summary", required=True)
    ap.add_argument("--signed-receipt", required=True)
    args = ap.parse_args()
    code = exit_from_file(args.clone_exit)
    phase = classify(code, bounded_plain(args.summary), bounded_plain(args.signed_receipt))
    if phase not in set(PHASE_CODES.values()) | {
        "unclassified", "signed_pass", "missing_signed_receipt",
        "time_bound", "exit_unknown"
    }:
        phase = "unclassified"
    result = "PASS" if phase == "signed_pass" else "HOLD"
    # Only stable literals and bounded numeric codes are permitted in output.
    print("ACCESS01_DISPOSABLE_PHASE=" + phase)
    print("ACCESS01_DISPOSABLE_RESULT=" + result)
    if phase != "signed_pass":
        print("::error title=ACCESS-01 disposable clone::ACCESS01_DISPOSABLE_PHASE=" + phase)
    else:
        print("::notice title=ACCESS-01 disposable clone::Signed local actor test passed")
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as out:
            out.write(
                "ACCESS-01 disposable clone: **" + result + "**; "
                + "ACCESS01_DISPOSABLE_PHASE=" + phase + ". "
                + "This receipt contains no private diagnostics; production release remains separate.\n"
            )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Print only an allowlisted C2 disposable-validation phase category.

The protected runner's SQL, schema dump, private stderr, credentials and
synthetic actor receipts are NOT read or printed by this classifier.
It accepts only the canonical validator's short summary.md and prints one
public-safe enum; unknown content fails closed to 'unclassified'.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

# All values are fixed, public, test-harness stage labels; never interpolate a
# phase name taken from a private file into a workflow log.
CATEGORIES = {
    "preflight": "preflight",
    "release-lane custody check": "release_lane",
    "validation fixture safety check": "fixture_safety",
    "schema dump sanitation": "schema_sanitation",
    "disposable database startup": "disposable_startup",
    "production custom-role restore": "clone_roles_restore",
    "production user-schema restore": "clone_schema_restore",
    "baseline domain schema lint": "baseline_lint",
    "candidate validation fixture application": "c1_fixture",
    "candidate migration application": "clone_candidate",
    "candidate migration postconditions": "c1_postconditions",
    "signed local HTTP API authorization matrix": "c1_signed_local",
    "held C2 exact native Ledger source proof signed matrix": "c2_signed_local",
    "candidate domain schema lint": "candidate_lint",
    "candidate lint delta comparison": "lint_comparison",
    "local database advisors": "local_advisors",
    "complete": "complete",
}
FALLBACK = "unclassified"


def categorize_summary(summary: str) -> str:
    # The validator writes a trailing exit phase when a summary already exists,
    # otherwise its EXIT trap makes exactly one '**FAILED during ...**' header.
    # These are both public code-defined summary lines, not raw error/SQL text.
    matches = re.findall(r"Validation command exited during `([^\n`]{1,140})`\.", summary)
    if not matches:
        matches = re.findall(r"\*\*FAILED during ([^\n*]{1,140})\.\*\*", summary)
    return CATEGORIES.get(matches[-1], FALLBACK) if matches else FALLBACK


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("summary")
    args = p.parse_args()
    path = Path(args.summary)
    category = FALLBACK
    if path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536:
        try:
            category = categorize_summary(path.read_text(encoding="utf-8"))
        except (UnicodeError, OSError):
            category = FALLBACK
    print("C2_DISPOSABLE_PHASE=" + category)


if __name__ == "__main__":
    main()

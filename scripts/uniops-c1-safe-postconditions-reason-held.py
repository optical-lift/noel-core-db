#!/usr/bin/env python3
"""Held source-only static reason classifier for disposable C1 postconditions.

Reads only the clone-local private psql postconditions.log, never raw schema,
real production data, tokens, SQL, paths, error text or credentials into stdout.
The only public output is a stable fixed token. Never use to bypass a test.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

# Strictly exact messages in the immutable canonical C1 postcondition source.
# No dynamic interpolation of a private log is permitted.
ASSERTION_CODES = {
    "Operating register source tables missing": "assertion_01",
    "Operating document validator failed open or rejected a valid value": "assertion_02",
    "Unsafe direct register table privileges": "assertion_03",
    "Register RLS disabled": "assertion_04",
    "Append-only register revisions not guarded": "assertion_05",
    "Register RPC role grants incorrect": "assertion_06",
    "Exact owner/canonical requirement/no instance generation contract missing": "assertion_07",
    "Cross-organization register entry found": "assertion_08",
    "C1 writer or direct-table privilege contract failed": "assertion_09",
    "C1 public API must be security invoker": "assertion_10",
    "Owner initial register read invalid": "assertion_11",
    "Owner establishment receipt is not non-materializing": "assertion_12",
    "Canonical requirement not recovered from exact owner register": "assertion_13",
    "Owner revision changed Work or returned wrong receipt": "assertion_14",
    "Paused policy improperly retired or concealed canonical requirement": "assertion_15",
    "Stale C1 revision was accepted": "assertion_16",
    "C1 generated Work, allocation, or duplicate requirement": "assertion_17",
    "Seat-only actor read owner operating register": "assertion_18",
    "Seat-only actor authored institutional requirement": "assertion_19",
    "Seat-only actor revised institutional requirement": "assertion_20",
    "Other-Ledger seat opened C1 register": "assertion_21",
    "Unrelated native Ledger opened C1 register": "assertion_22",
    "No-seat signed-in Person read institutional register": "assertion_23",
    "Expired/nonexistent session retained owner access": "assertion_24",
    "Revoked owner authority still read C1 register": "assertion_25",
    "Revoked native seat still read C1 register": "assertion_26",
    "Anonymous actor invoked protected C1 API": "assertion_27",
}
FALLBACK = "unclassified"
MAX_BYTES = 65536
ERROR_LINE = re.compile(r"^(?:psql:[^\r\n]{1,1024}:\d+:\s*)?ERROR:\s+([^\r\n]{1,1024})$")

# Other PostgreSQL errors must be classified without disclosing identifiers.
# Fixed families, never raw error text.
SQL_ERROR_FAMILIES = (
    (re.compile(r"^function .+ does not exist$"), "missing_function"),
    (re.compile(r"^relation .+ does not exist$"), "missing_relation"),
    (re.compile(r"^column .+ does not exist$"), "missing_column"),
    (re.compile(r"^permission denied for .+$"), "permission_denied"),
    (re.compile(r"^duplicate key value violates unique constraint .+$"), "unique_constraint"),
    (re.compile(r"^insert or update on table .+ violates foreign key constraint .+$"), "foreign_key"),
    (re.compile(r"^null value in column .+ violates not-null constraint$"), "not_null"),
    (re.compile(r"^operator does not exist: .+$"), "missing_operator"),
    (re.compile(r"^invalid input syntax for type .+$"), "invalid_input"),
    (re.compile(r"^syntax error at or near .+$"), "syntax_error"),
)


def classify_text(text: str) -> str:
    # An unknown result is not an approval: never infer which assertion failed.
    # Accept one canonical psql error line, not banners/context or user-provided
    # freeform matches anywhere in the log.
    errors = []
    for line in text.splitlines():
        m = ERROR_LINE.fullmatch(line)
        if m:
            errors.append(m.group(1).strip())
    if len(errors) != 1:
        return FALLBACK
    error = errors[0]
    if error in ASSERTION_CODES:
        return ASSERTION_CODES[error]
    for pattern, code in SQL_ERROR_FAMILIES:
        if pattern.fullmatch(error):
            return code
    return FALLBACK


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("postconditions_log")
    args = p.parse_args()
    path = Path(args.postconditions_log)
    result = FALLBACK
    try:
        if path.is_file() and not path.is_symlink() and path.stat().st_size <= MAX_BYTES:
            result = classify_text(path.read_text(encoding="utf-8"))
    except (UnicodeError, OSError):
        result = FALLBACK
    print("C1_POSTCONDITIONS_REASON=" + result)


if __name__ == "__main__":
    main()

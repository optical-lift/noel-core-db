#!/usr/bin/env python3
"""One narrowly scoped, read-only Noel source-fingerprint gate for Moonwell.

This script NEVER exports a snapshot, opens a transfer channel, changes a
database, or authorizes a held release. Use only after a separate owner-gated
protected workflow has selected the exact handoff scope. It emits fixed,
non-sensitive result classes; no SQL, DSN, server error or function body.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from typing import Mapping

EXPECTED_P3_MD5 = "774ad5c6728a615ada5bf4ea823c5498"
FUNCTION = "atlas.evaluate_rhythm_binding_v1(uuid,timestamptz,text)"
SQL = (
    "SELECT coalesce("
    "pg_catalog.md5(pg_catalog.pg_get_functiondef("
    "pg_catalog.to_regprocedure('" + FUNCTION + "'))),"
    "'missing');"
)
ALLOWED_OUTPUT = re.compile(r"^[a-f0-9]{32}$")


def classify(raw: str) -> str:
    """Classify an exact single query result; never leak unexpected contents."""
    lines = raw.splitlines()
    if len(lines) != 1:
        return "unrecognized_result"
    value = lines[0].strip()
    if value == EXPECTED_P3_MD5:
        return "match"
    if value == "missing":
        return "missing_function"
    if ALLOWED_OUTPUT.fullmatch(value):
        return "source_drift"
    return "unrecognized_result"


def probe(
    source_env: Mapping[str, str],
    run=subprocess.run,
) -> str:
    """Read only source metadata; reject unavailable credentials or errors."""
    dsn = source_env.get("NOEL_CORE_DATABASE_URL", "")
    if not dsn or any(ch.isspace() for ch in dsn):
        return "credential_unavailable"
    if not dsn.startswith(("postgresql://", "postgres://")):
        return "unrecognized_credential_form"
    environment = dict(source_env)
    environment.pop("NOEL_CORE_DATABASE_URL", None)
    environment["PGDATABASE"] = dsn
    environment["PGCONNECT_TIMEOUT"] = "15"
    # Database-side read-only transaction default; never allow local rc commands.
    environment["PGOPTIONS"] = (
        "-c default_transaction_read_only=on -c statement_timeout=15000"
    )
    try:
        result = run(
            ["psql", "-X", "-w", "-A", "-t", "-v", "ON_ERROR_STOP=1",
             "-c", SQL],
            env=environment,
            capture_output=True,
            text=True,
            timeout=35,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "query_unavailable"
    if result.returncode != 0:
        return "query_unavailable"
    return classify(result.stdout)


def main() -> int:
    if len(sys.argv) != 1:
        print("BLOCKED moonwell_p3_source_gate=unexpected_arguments")
        return 2
    status = probe(os.environ)
    if status == "match":
        print("PASS moonwell_p3_source_gate=exact_read_only_match")
        return 0
    print("BLOCKED moonwell_p3_source_gate=" + status)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

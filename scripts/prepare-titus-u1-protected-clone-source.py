#!/usr/bin/env python3
"""Assemble U1 HELD source for disposable PROTECTED schema-shape testing only.

This is NOT a migration generator. It cannot inspect, connect, dump or write a
hosted database. Owner-gated workflow must separately supply immutable source
identity, protected schema/roles custody and a temporary local destination.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SOURCE_DIR = "candidates/shared-teaching-course-clean-cutover-v1"
SOURCES = (
    "shared_titus_current_person_signed_candidate.sql",
    "titus_account_context_candidate.sql",
    "titus_institution_account_admission_issuer_candidate.sql",
    "shared_titus_institution_manager_governance_candidate.sql",
    "shared_titus_institution_root_establishment_candidate.sql",
    "titus_institution_account_self_service_candidate.sql",
)
TEST_NAME = "20261118095959_shared_titus_u1_full_schema_TEST_ONLY.sql"
SCOPE = "titus_u1_protected_source_shape_test_only_v1"
FORBIDDEN_ENVS = (
    "NOEL_CORE_DATABASE_URL", "DATABASE_URL", "SUPABASE_DB_URL",
    "SUPABASE_ACCESS_TOKEN", "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_SECRET_KEY",
)


def sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument("--expected-sha", required=True)
    p.add_argument("--test-scope", required=True, choices=(SCOPE,))
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--manifest", type=Path, required=True)
    args = p.parse_args()
    if any(os.environ.get(name) for name in FORBIDDEN_ENVS):
        raise SystemExit("Refusing to assemble U1 test source with hosted credentials")
    if not re.fullmatch("[0-9a-f]{40}", args.expected_sha):
        raise SystemExit("An exact immutable 40-character source SHA is required")
    root = args.source_root.resolve(strict=True)
    current = subprocess.check_output(
        ("git", "-C", str(root), "rev-parse", "HEAD"), text=True
    ).strip()
    if current != args.expected_sha:
        raise SystemExit("Held source commit differs from owner-selected immutable SHA")
    base = (root / SOURCE_DIR).resolve(strict=True)
    if not base.is_relative_to(root):
        raise SystemExit("Candidate path escaped repository")
    destination = args.output.resolve()
    manifest = args.manifest.resolve()
    if destination.name != TEST_NAME:
        raise SystemExit("Only the fixed, nonreleasable U1 TEST_ONLY name is allowed")
    if destination == manifest or destination.exists() or manifest.exists():
        raise SystemExit("Refusing to overwrite an existing source or receipt")
    for pth in (destination, manifest):
        if pth.is_relative_to(root) or "migrations" in pth.parts:
            raise SystemExit("Protected source test output must remain outside repository/migrations")
        if not pth.parent.is_dir():
            raise SystemExit("Test artifacts directory must already exist")

    parts = [
        "-- U1.9 PROTECTED SOURCE-SHAPE TEST ONLY; NOT A RELEASABLE MIGRATION.",
        "-- Apply ONLY to a disposable local PostgreSQL restoration after separate",
        "-- owner-gated, read-only schema/roles capture. No production DDL/DML.",
        "SET app.shared_course_clone = 'approved';",
    ]
    digest = []
    for name in SOURCES:
        path = base / name
        if not path.is_file() or path.is_symlink():
            raise SystemExit("Missing or symlinked held candidate source: " + name)
        source = path.read_text(encoding="utf-8")
        if not source.strip().startswith("-- HELD"):
            raise SystemExit("Unexpected source custody header: " + name)
        if "\\i " in source or "supabase db push" in source.lower():
            raise SystemExit("Unexpected external source or production access in candidate")
        digest.append({"source": f"{SOURCE_DIR}/{name}", "sha256": sha(source)})
        parts.extend(("", "-- SOURCE SEGMENT START " + name, source.rstrip(),
                      "-- SOURCE SEGMENT END " + name))
    bundle = "\n".join(parts) + "\n"
    report = {
        "contractVersion": "titus_u1_protected_source_shape_v1",
        "testScope": SCOPE,
        "sourceSha": current,
        "sourceSegments": digest,
        "scratchSqlFile": TEST_NAME,
        "scratchSqlSha256": sha(bundle),
        "productionAccess": False,
        "releaseAuthorized": False,
        "actualSignedProtectedSchemaTested": False,
    }
    destination.write_text(bundle, encoding="utf-8")
    manifest.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS exact held U1 source-only scratch package: 6 immutable modules, no hosted access")


if __name__ == "__main__":
    main()

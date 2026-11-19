#!/usr/bin/env python3
"""Assemble held T5 teaching source only, for an independently authorized disposable schema clone. Never a release or live database operation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

SOURCES = (
    "candidates/shared-course-class-composition-v1/candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/person_published_definition_candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/person_course_curriculum_snapshot_candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/private_study_person_course_candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/private_study_sealed_unit_candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/private_study_answer_candidate.sql",
    "candidates/shared-teaching-course-clean-cutover-v1/private_study_submission_candidate.sql",
)
PRE = "candidates/shared-teaching-course-clean-cutover-v1/T5_PROTECTED_TEACHING_BASE_TEST_ONLY.sql"
POST = "candidates/shared-teaching-course-clean-cutover-v1/T5_PROTECTED_TEACHING_POSTCONDITIONS_TEST_ONLY.sql"
TEST_NAME = "20261119100000_shared_titus_t5_teaching_TEST_ONLY.sql"
SCOPE = "titus_t5_protected_source_shape_test_only_v1"
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
        raise SystemExit("Refusing to assemble T5 test source with hosted credentials")
    if not re.fullmatch("[0-9a-f]{40}", args.expected_sha):
        raise SystemExit("An exact immutable 40-character source SHA is required")
    root = args.source_root.resolve(strict=True)
    current = subprocess.check_output(
        ("git", "-C", str(root), "rev-parse", "HEAD"), text=True
    ).strip()
    if current != args.expected_sha:
        raise SystemExit("Held source commit differs from owner-selected immutable SHA")
    destination = args.output.resolve()
    manifest = args.manifest.resolve()
    if destination.name != TEST_NAME:
        raise SystemExit("Only the fixed, nonreleasable T5 TEST_ONLY name is allowed")
    if destination == manifest or destination.exists() or manifest.exists():
        raise SystemExit("Refusing to overwrite an existing source or receipt")
    for pth in (destination, manifest):
        if pth.is_relative_to(root) or "migrations" in pth.parts:
            raise SystemExit("Protected source test output must remain outside repository/migrations")
        if not pth.parent.is_dir():
            raise SystemExit("Test artifacts directory must already exist")

    # Read bytes from immutable Git objects, never the mutable worktree.
    def exact(path):
        raw = subprocess.check_output(("git", "-C", str(root), "show", current + ":" + path))
        source = raw.decode("utf-8")
        if not source.strip().startswith("-- HELD"):
            raise SystemExit("Unexpected candidate custody header: " + path)
        if "\\i " in source or "supabase db push" in source.lower():
            raise SystemExit("External source or production access in candidate")
        return source
    parts = [
        "-- T5 PROTECTED SOURCE-SHAPE TEST ONLY; NOT A RELEASABLE MIGRATION.",
        "BEGIN;",
        "SET LOCAL app.shared_course_clone = 'approved';",
        exact(PRE).rstrip(),
    ]
    digest = []
    for name in SOURCES:
        source = exact(name)
        if re.search(r"(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;", source):
            raise SystemExit("Unexpected transaction boundary in held module: " + name)
        digest.append({"source": name, "sha256": sha(source)})
        parts.extend(("", "-- SOURCE SEGMENT START " + name, source.rstrip(),
                      "-- SOURCE SEGMENT END " + name))
    parts.extend(("", exact(POST).rstrip(), "ROLLBACK;"))
    bundle = "\n".join(parts) + "\n"
    report = {
        "contractVersion": "titus_t5_protected_source_shape_v1",
        "testScope": SCOPE,
        "sourceSha": current,
        "sourceSegments": digest,
        "scratchSqlFile": TEST_NAME,
        "scratchSqlSha256": sha(bundle),
        "preflightSha256": sha(exact(PRE)),
        "postconditionsSha256": sha(exact(POST)),
        "protectedRestorePerformed": False,
        "productionAccess": False,
        "releaseAuthorized": False,
        "actualSignedProtectedSchemaTested": False,
    }
    destination.write_text(bundle, encoding="utf-8")
    manifest.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("PASS exact held T5 source-only scratch package: 7 immutable modules, no hosted access")


if __name__ == "__main__":
    main()

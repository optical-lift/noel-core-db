#!/usr/bin/env python3
"""Assemble a non-deploying, ordered SQL scratch candidate from held sources.

NOT a migration generator. Does not connect to Supabase or mutate the database.
The resulting scratch SQL requires a production-shaped disposable schema clone
and signed session acceptance before it can become a governed migration.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates" / "atlas"

# Dependencies follow existing identity and source tables; the two original
# Work and Rhythm subsystems never create alternate task/schedule stores.
SOURCES = (
    "universal_laundry_calibration_without_implicit_rhythm_v1/candidate.sql",
    "governed_legacy_farm_reader_disclosure_v1/candidate.sql",
    "governed_legacy_farm_reader_disclosure_gate0_extension_v1/candidate.sql",
    "governed_legacy_farm_reader_disclosure_gate0_context_v1/candidate.sql",
    "governed_legacy_farm_reader_disclosure_gate0_deep_v1/candidate.sql",
    "universal_subject_bounded_disclosure_v1/candidate.sql",
    "governor_effective_subject_disclosure_review_v1/candidate.sql",
    "original_subject_choices_for_work_decomposition_v1/candidate.sql",
    "universal_original_work_decomposition_v1/candidate.sql",
    "universal_household_canonical_work_custody_v1/candidate.sql",
    "universal_household_canonical_work_guards_v1/candidate.sql",
    "universal_household_rhythm_explicit_decision_v1/candidate.sql",
    "household_laundry_original_work_actual_v1/candidate.sql",
    "household_laundry_original_work_read_v1/candidate.sql",
    "original_subject_work_existing_direct_responsibility_v1/guarded_native_reader_extensions.sql",
    "original_subject_work_existing_direct_responsibility_v1/candidate.sql",
)

def body(relative_path: str) -> str:
    p = BASE / relative_path
    if not p.is_file():
        raise RuntimeError(f"missing original candidate {p}")
    s = p.read_text().strip()
    if not s.startswith("BEGIN;") or not s.endswith("COMMIT;"):
        raise RuntimeError(f"original candidate transaction boundary missing: {relative_path}")
    b = s[len("BEGIN;"):-len("COMMIT;")].strip()
    if re.search(r"(?m)^\s*(?:BEGIN|COMMIT|ROLLBACK);\s*$", b):
        raise RuntimeError(f"nested top-level transaction in {relative_path}")
    return "-- Original held candidate: " + relative_path + "\n" + b + "\n"

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, help="emit local scratch SQL, never production")
    args = parser.parse_args()
    if len(SOURCES) != len(set(SOURCES)):
        raise RuntimeError("duplicate original candidate in bundle")
    sql = "BEGIN;\n-- HELD ATLAS ORIGINAL WORK SOURCE. NOT A RELEASE MIGRATION.\n"
    for source in SOURCES:
        sql += "\n" + body(source)
    sql += "\nCOMMIT;\n"
    if len(re.findall(r"(?m)^BEGIN;\s*$", sql)) != 1 or len(
            re.findall(r"(?m)^COMMIT;\s*$", sql)) != 1:
        raise RuntimeError("composed candidate has multiple transaction boundaries")
    guards = (
        "CREATE OR REPLACE FUNCTION atlas.require_governed_farm_full_disclosure_self_v1",
        "CREATE OR REPLACE FUNCTION atlas.require_household_governor_self_v1",
        "CREATE TABLE atlas.household_rhythm_explicit_decisions_v1",
        "CREATE OR REPLACE FUNCTION atlas.record_household_laundry_wash_started_self_api_v1",
        "CREATE OR REPLACE FUNCTION atlas.owner_direct_assign_existing_original_work_self_api_v1",
    )
    for marker in guards:
        if marker not in sql:
            raise RuntimeError("bundle lost source boundary " + marker)
    # The single governed integrated candidate is a byte-exact view of
    # original source files. A stale bundle fails before any clone request.
    package = BASE / "atlas_universal_original_work_integrated_v1"
    packaged_sql = package / "candidate.sql"
    if not packaged_sql.is_file() or packaged_sql.read_text() != sql:
        raise RuntimeError("integrated SQL candidate differs from exact original sources")
    post_names = tuple(dict.fromkeys(path.split("/")[0] for path in SOURCES))
    post = "-- HELD POSTCONDITIONS: all 14 original source validations, not signed acceptance.\n"
    for name in post_names:
        source = BASE / name / "postconditions.sql"
        if not source.is_file():
            raise RuntimeError("missing original postcondition " + str(source))
        post += ("\n-- Original held postcondition: " + name
                 + "/postconditions.sql\n" + source.read_text().strip() + "\n\n")
    packaged_post = package / "postconditions.sql"
    if not packaged_post.is_file() or packaged_post.read_text() != post:
        raise RuntimeError("integrated postconditions differ from exact original assertions")
    print(f"PASS byte-exact integrated candidate and {len(post_names)} source postconditions")
    # Never use a live database endpoint or an automatic migration filename.
    if args.output:
        dest = args.output.resolve()
        if ROOT in dest.parents:
            raise RuntimeError("scratch output must stay OUTSIDE repository")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(sql)
        print(f"CREATED scratch-only composed SQL {dest} ({len(sql)} bytes)")
    else:
        print(f"PASS assembled {len(SOURCES)} ordered candidates, {len(sql)} bytes, one transaction")
    print("PENDING PostgreSQL disposable production-schema clone and signed proof")

if __name__ == "__main__":
    main()

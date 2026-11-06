#!/usr/bin/env python3
"""HELD test-only assembly input for protected full-schema disposable clone.

No Postgres access, no credentials, no migrations, no user data and no DDL
execution. Emits one exact source-pinned test file ONLY under RUNNER_TEMP.
Actual protected owner-gated harness (on reviewed default branch) alone
controls the real read-only schema snapshot + disposable database lifecycle.
"""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys

P3_SHA = "f9ca3c44065a0d2f8a23821a583fcc0571d2d0fc"
# Each source SHA is the exact Git blob (not the moving head branch).
SOURCE = (
    ("main", "supabase/migrations/20261026010327_atlas_farm_crop_custody_and_work_growing_object_link_v1.sql", "53610c2de7592813a54b31bd5b2055fad61a82a9"),
    ("p3", "candidates/uni_ops_p3_no_auto_successor_v1/14_harvest_bucket_result_no_automatic_preparation_held.sql", "997cc38fc81f0f32249eeea88b1096d61e53b0bb"),
    ("p3", "candidates/uni_ops_p3_no_auto_successor_v1/15_seed_inventory_result_no_auto_shortfall_task_held.sql", "5e5415ea94f8f8309645f2afd66d5ae47e60fbd5"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/01_domain_neutral_source_and_decision_records_held.sql", "41b4dbe53ca71a6f816a99d3944da4ecb8ada443"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/02_private_company_governor_decision_writer_held.sql", "54c5a4201ba07c753ee7714a520f05f569be366d"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/03_private_current_governor_case_receipt_held.sql", "efa708c308378acb40aeb427ad821478a34108f7"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/06_bounded_existing_subject_disclosure_extension_held.sql", "fbdb763e1366a2d6dc4b352f3d96f1b6e731350c"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/04_verified_farm_source_to_company_case_adapter_held.sql", "9a7608ace7c805cd70a057dbec2285400012900f"),
    ("univ", "candidates/uni_ops_universal_company_decision_v1/05_farm_to_one_company_governor_decision_wrapper_held.sql", "5be176df81402feef543c9616953ea71b250634f"),
)

def reject(message):
    raise SystemExit("HELD clone assembly rejected: " + message)

def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--main-checkout", required=True, type=Path)
    parser.add_argument("--p3-checkout", required=True, type=Path)
    parser.add_argument("--universal-checkout", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    temp = os.environ.get("RUNNER_TEMP")
    if not temp:
        reject("RUNNER_TEMP is required; no in-repository migration output")
    temp_root = Path(temp).resolve()
    if not temp_root.is_dir():
        reject("real RUNNER_TEMP directory absent")
    output = args.output.resolve()
    if not output.is_relative_to(temp_root) or output == temp_root:
        reject("output must be in job-owned RUNNER_TEMP, never a release path")
    if output.suffix != ".sql" or output.exists():
        reject("one new test-only SQL file is required")

    roots = {
        "main": args.main_checkout.resolve(),
        "p3": args.p3_checkout.resolve(),
        "univ": args.universal_checkout.resolve(),
    }
    for label, root in roots.items():
        if not (root / ".git").exists():
            reject("missing Git checkout: " + label)
    head = subprocess.check_output(
        ["git", "-C", str(roots["p3"]), "rev-parse", "HEAD"],
        text=True).strip()
    if head != P3_SHA:
        reject("farm P3 source commit changed; manual re-review required")

    validation_file = (roots["univ"] / "candidates/uni_ops_universal_company_decision_v1/deferred_postconditions.sql").resolve()
    if not validation_file.is_relative_to(roots["univ"]) or not validation_file.is_file():
        reject("missing exact original structural validator")
    if git_blob(validation_file.read_bytes()) != "427d195dd76c7fa58b1a5dce58e146778a56e1d9":
        reject("unreviewed structural validator changed; no protected schema access")
    chunks = [
        "-- HELD TEST ONLY. Never install or release this composite.",
        "-- Prepared from exact Git blob-pinned sources; no public API calls.",
        "-- Source order: canonical native Farm custody; P3 physical Harvest/Seed",
        "-- no-auto-successor writers; one Company decision kernel; current",
        "-- Subject disclosure; first Farm adapters; no P3 16/17 governor.",
        r"\set ON_ERROR_STOP on",
    ]
    for label, path, expected in SOURCE:
        file = (roots[label] / path).resolve()
        if not file.is_relative_to(roots[label]) or not file.is_file():
            reject("source missing or escaped checkout: " + path)
        raw = file.read_bytes()
        if git_blob(raw) != expected:
            reject("immutable source SHA changed: " + path)
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            reject("non-text or unsafe source: " + path)
        chunks.extend([
            "\n-- BEGIN HELD EXACT SOURCE " + path,
            text.rstrip("\n"),
            "-- END HELD EXACT SOURCE " + path + "\n",
        ])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(chunks) + "\n", encoding="utf-8")
    print("PASS: exactly nine source-pinned SQL inputs; output restricted to job scratch; no database accessed")
    print("WARNING: genuine signed owner, source/Subject grants and Work consent remain separate gates")

if __name__ == "__main__":
    main()

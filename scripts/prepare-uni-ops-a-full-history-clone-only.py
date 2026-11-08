#!/usr/bin/env python3
"""HELD UNI-OPS option A: exact 11-source + historical 16–22 disposable assembly.

This program never connects to Supabase, executes SQL, signs a person, installs
a migration, or publishes its SQL. It consumes the independently pinned
11-source assembler and verifies all seven independently pinned historical
source Git blobs from the exact historical-lifecycle checkout.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

HISTORY_DIR = "candidates/atlas_universal_work_lifecycle_v1"
HISTORY = (
    ("history-record-and-rls", "16_historical_self_adoption_review_candidate.sql",
     "2bccffbaee2de725f511ca5a67145ae72f7980c3"),
    ("history-governor-readback", "17_historical_self_adoption_review_readback_candidate.sql",
     "bb30f49462ee564197cac036ec701d6c221a5044"),
    ("history-review-postconditions", "18_historical_self_adoption_review_postconditions.sql",
     "48df29f49626d137a5f25b4f09e90e2e6a069de1"),
    ("history-public-transport", "19_historical_self_adoption_public_transport_candidate.sql",
     "a578abb3bbfb810386ce134d23b91981b02a401f"),
    ("history-retirement-bridge", "20_native_historical_retirement_candidate.sql",
     "93f7b9cf0bad5eb536ffa90d3973aabfe75542d9"),
    ("history-retirement-preflight", "21_native_historical_retirement_preflight_transport_candidate.sql",
     "254f214caadb697988e1bfa689d6bd72eeabe08b"),
    ("history-retirement-postconditions", "22_native_historical_retirement_rollback_postconditions.sql",
     "cfceac512ece05b68b0d0f76f0bdaa7aaef23dea"),
)
ORDER = (
    "lifecycle-shadow",
    "history-record-and-rls",
    "lifecycle-single-transition",
    "history-governor-readback",
    "history-public-transport",
    "history-retirement-bridge",
    "history-retirement-preflight",
    "r01-r02-composed-native",
    "u1a-exact-foundry-rulebook",
    "u1b-native-scope-history",
    "u2a-preoriginal-offer",
    "u2b-signed-root-finalize",
    "u2c-single-authority-arbiter",
    "u2c-accepted-only-original-guard",
    "u2c-close-old-standing-bypasses",
    "u2c-schema-and-acl-postconditions",
    "history-review-postconditions",
    "history-retirement-postconditions",
)
ORIGINAL_ASSEMBLER = (
    "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/"
    "tests/prepare_pinned_accepted_first_scratch.py"
)

def stop(message: str) -> None:
    raise SystemExit("HELD OPTION A source assembly rejected: " + message)

def original_module(checkout: Path):
    script = checkout / ORIGINAL_ASSEMBLER
    if not script.is_file() or script.is_symlink():
        stop("immutable original assembler unavailable")
    spec = importlib.util.spec_from_file_location("pinned_11_stages", str(script))
    if spec is None or spec.loader is None:
        stop("cannot load exact 11-source assembler")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def assemble(roots: dict[str, Path], harness: Path):
    module = original_module(harness)
    module.check_checkout("harness", harness) if "harness" in module.PINNED_CHECKOUTS else None
    if len(module.STAGES) != 11 or len(module.PINNED_CHECKOUTS) != 6:
        stop("original 11-source custody contract changed")
    original_receipts, original_parts = module.prepare(roots)
    if len(original_receipts) != 11 or len(original_parts) != 33:
        stop("original 11-source assembly incomplete")
    sources = {}
    receipts = {}
    for index, receipt in enumerate(original_receipts):
        name = receipt["stage"]
        parts = original_parts[index * 3 : index * 3 + 3]
        if parts[0] != "-- BEGIN PINNED STAGE " + name + " blob:" + receipt["blob"] + "\n":
            stop("original pinned stage boundary lost")
        sources[name] = "".join(parts)
        receipts[name] = receipt

    for stage, filename, expected_sha in HISTORY:
        file = roots["lifecycle"] / HISTORY_DIR / filename
        if not file.is_file() or file.is_symlink():
            stop(stage + ": tracked historical source unavailable")
        payload = file.read_bytes()
        actual = module.git_blob(payload)
        if actual != expected_sha:
            stop(stage + ": immutable historical Git blob mismatch")
        content = payload.decode("utf-8")
        required = {
            "history-record-and-rls": (
                "CREATE TABLE atlas.historical_self_adoption_review_events_v1(",
                "FORCE ROW LEVEL SECURITY", "reject_historical_review_mutation_v1"),
            "history-governor-readback": (
                "governor_historical_self_adoption_history_self_api_v1",),
            "history-public-transport": (
                "public.governor_link_historical_self_adoption_self_api_v1",
                "public.report_historical_self_adoption_pending_self_api_v1"),
            "history-retirement-bridge": (
                "governor_retire_historical_work_self_api_v1",
                "work_lifecycle_events_v1_source_table_check"),
            "history-retirement-preflight": (
                "governor_historical_retirement_preflight_self_api_v1",
                "public.governor_retire_historical_work_self_api_v1"),
            "history-review-postconditions": (
                "HELD disposable-clone postconditions",),
            "history-retirement-postconditions": (
                "HELD disposable-clone checks",),
        }.get(stage, ())
        if not all(token in content for token in required):
            stop(stage + ": expected historical source guard missing")
        sources[stage] = (
            "-- BEGIN PINNED STAGE " + stage + " blob:" + actual + "\n"
            + content.rstrip() + "\n"
            + "-- END PINNED STAGE " + stage + "\n\n"
        )
        receipts[stage] = {
            "stage": stage,
            "checkout": "lifecycle",
            "ref": module.PINNED_CHECKOUTS["lifecycle"],
            "path": HISTORY_DIR + "/" + filename,
            "blob": actual,
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
    if len(sources) != 18 or len(set(ORDER)) != 18 or set(sources) != set(ORDER):
        stop("exact 18-stage option A cohort mismatch")
    if ORDER.index("history-record-and-rls") >= ORDER.index("lifecycle-single-transition"):
        stop("historical table must precede held lifecycle transition")
    if ORDER.index("history-retirement-bridge") <= ORDER.index("lifecycle-single-transition"):
        stop("historical retirement bridge requires current lifecycle transition")
    if ORDER[-2:] != ("history-review-postconditions", "history-retirement-postconditions"):
        stop("historical structural postconditions must run last")
    return [receipts[k] for k in ORDER], [sources[k] for k in ORDER]

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--harness", type=Path, required=True)
    for k in ("lifecycle", "r02", "u1a", "u1b", "u2", "u2c"):
        p.add_argument("--" + k, type=Path, required=True)
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    roots = {k: getattr(args, k).resolve() for k in
             ("lifecycle", "r02", "u1a", "u1b", "u2", "u2c")}
    harness = args.harness.resolve()
    module = original_module(harness)
    # Preserve all original output/credential/migration exclusion checks.
    module.validate_safety(args.output)
    receipts, stages = assemble(roots, harness)
    payload = (
        "-- TEST ONLY: OPTION A full source completion + historical cancel.\n"
        "-- No production migration, retained source dump, or signed approval.\n"
        "-- True local governor/worker/outsider GoTrue tests are a separate gate.\n\n"
        + "".join(stages)
    ).encode("utf-8")
    result = {
        "kind": "UNI_OPS_A_FULL_HISTORY_DISPOSABLE_ONLY",
        "success": True, "stage_count": 18, "stages": receipts,
        "scratch_file_sha256": hashlib.sha256(payload).hexdigest(),
        "notVerified": [
            "Full production-schema PostgreSQL lint and postconditions",
            "real signed GoTrue owner/worker/outsider/revoked actor",
            "positive historical evidence and reviewed cancellation",
            "candidate U1A overlap negative and U1B positive",
            "worker accept/decline and exactly one original Work",
            "concurrent replay and independent next eligibility",
            "production release",
        ],
    }
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("xb") as file:
            file.write(payload)
        result["scratch_file"] = str(args.output)
    print(json.dumps(result, sort_keys=True, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())

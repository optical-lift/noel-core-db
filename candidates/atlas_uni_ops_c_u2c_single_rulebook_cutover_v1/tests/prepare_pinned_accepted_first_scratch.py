#!/usr/bin/env python3
"""Source-pinned UNI-OPS-01 U1A/U1B/U2A/U2C scratch assembly ONLY.

This emits one explicitly NONRELEASEABLE SQL file to a temporary location.
It does not connect to a database, authorize a user, run SQL, create a
migration, sign a JWT, merge a PR, or touch production. Exact source blobs
come from independent pinned Noel commit checkouts supplied by the caller.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PINNED_CHECKOUTS = {
    "lifecycle": "ddfb0bf5374798301fe076a61d2b944dfb52ff63",
    "r02": "d48cd444fd261fd5f8c91655b789e50730c1b9f7",
    "u1a": "f9c372d3487ea6af4d29a4ee3b22579b9d94c5ae",
    "u1b": "18be5996faaa0f7a0def1d07c262f53b39e73605",
    "u2": "2be045d7fa51b83416a57c76b1a5508e815b8445",
    "u2c": "1fd28856ff8d3fd99997fc0ae1fcf8714407a407",
}

# Name, checkout, tracked source-relative path, exact Git blob SHA-1.
STAGES = (
    ("lifecycle-shadow", "lifecycle",
     "candidates/atlas_universal_work_lifecycle_v1/04_shadow_release_candidate.sql",
     "e7f4c11b9803508d8eab75527ee6a39703383f43"),
    ("lifecycle-single-transition", "lifecycle",
     "candidates/atlas_universal_work_lifecycle_v1/06_single_transition_authority_private.sql",
     "a6947ae7d5c5d31a75740c2cd2672e9832a7fee8"),
    ("r01-r02-composed-native", "r02",
     "candidates/atlas_universal_continuing_original_work_v1/r02_reality_offering_release_candidate.sql",
     "75d1a83ae01116be9e71bdb778f159753b81327a"),
    ("u1a-exact-foundry-rulebook", "u1a",
     "candidates/atlas_governed_rulebook_u1a_v1/candidate.sql",
     "c7df9269a0726732b27e88764b04fabe0039aee5"),
    ("u1b-native-scope-history", "u1b",
     "candidates/atlas_uni_ops_c_u1b_scoped_rulebook_v1/candidate.sql",
     "ff604f23514b99000a991e1710f94cf1f078c4c1"),
    ("u2a-preoriginal-offer", "u2",
     "candidates/atlas_uni_ops_c_u2_prework_candidate_offer_v1/candidate.sql",
     "5881e9496b850b8ceefc5d1ee395d2c1218dacb3"),
    ("u2b-signed-root-finalize", "u2",
     "candidates/atlas_uni_ops_c_u2_prework_candidate_offer_v1/finalize_accepted_source_bridge_held.sql",
     "666922bbc23475cd6b5a388c8478822ea675db96"),
    ("u2c-single-authority-arbiter", "u2c",
     "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/01_single_authority_arbiter_held.sql",
     "4bf387ad518b4eaffa4d90de8e468906404cd703"),
    ("u2c-accepted-only-original-guard", "u2c",
     "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/02_native_original_writer_acceptance_guard_held.sql",
     "4413d84b042a357567a2334cddccc859650c41dc"),
    ("u2c-close-old-standing-bypasses", "u2c",
     "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/03_public_cutover_held.sql",
     "7c80f60753e5d93cb40d56bbd419d6a02c38158f"),
    ("u2c-schema-and-acl-postconditions", "u2c",
     "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/04_postconditions_held.sql",
     "e67a77508b54ef86d77237d52160d091b2b6ffda"),
)

def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()

def fail(message: str) -> None:
    raise SystemExit("HELD UNI-OPS source pin rejected: " + message)

def check_checkout(label: str, root: Path) -> None:
    if not root.is_dir():
        fail(label + ": missing checkout")
    try:
        current = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        fail(label + ": verified Git checkout required")
    if current != PINNED_CHECKOUTS[label]:
        fail(label + ": immutable checkout head mismatch")

def validate_safety(output: Path | None) -> None:
    if os.environ.get("NOEL_CORE_DATABASE_URL"):
        fail("production database credential must not exist in assembler environment")
    if os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        fail("no service-role credential may be accessible to scratch assembler")
    if output is None:
        return
    runner_temp = os.environ.get("RUNNER_TEMP")
    approved_runner = bool(
        runner_temp and output.parent.resolve() == Path(runner_temp).resolve()
    )
    approved_os_temp = bool(
        re.search(r"/(?:tmp|var/tmp|private/tmp)/", str(output))
    )
    if not output.is_absolute() or not (approved_runner or approved_os_temp):
        fail("scratch output must be under RUNNER_TEMP or an OS temp directory")
    if "TEST_ONLY" not in output.name or output.suffix != ".sql":
        fail("scratch SQL output basename must declare TEST_ONLY.sql")
    if "supabase/migrations" in str(output) or output.exists():
        fail("scratch output may not overwrite any existing file or migration")

def prepare(roots: dict[str, Path]) -> tuple[list[dict[str, str]], list[str]]:
    receipts: list[dict[str, str]] = []
    sql: list[str] = []
    for n, root in roots.items():
        check_checkout(n, root)
    for name, key, relpath, expected_blob in STAGES:
        source = roots[key] / relpath
        if not source.is_file() or source.is_symlink():
            fail(name + ": missing tracked source or source symlink")
        data = source.read_bytes()
        actual = git_blob(data)
        if actual != expected_blob:
            fail(name + ": exact Git source blob differs from reviewed source")
        if len(data) < 350 or (b"CREATE " not in data and name not in (
            "u2c-schema-and-acl-postconditions", "u2c-close-old-standing-bypasses"
        )):
            fail(name + ": unexpectedly incomplete source")
        if name == "u2c-single-authority-arbiter":
            for required in (b"v_u1a_disputed", b"candidateOfferAdmissible",
                             b"resolve_governed_canonical_farm_rule_authority_v1"):
                if required not in data:
                    fail(name + ": missing U1A overlap hold")
        if name == "u2c-accepted-only-original-guard":
            if b"require_accepted_prework_standing_original_v1" not in data:
                fail(name + ": original Work writer lacks acceptance source")
        if name == "u2c-close-old-standing-bypasses":
            for required in (b"REVOKE", b"finalize_accepted_governed_prework_self_api_v1",
                             b"governor_approve_rhythm_opportunity_self_api_v1"):
                if required not in data:
                    fail(name + ": direct Work bypass not enumerated")
        receipts.append({
            "stage": name, "checkout": key,
            "ref": PINNED_CHECKOUTS[key], "path": relpath,
            "blob": actual, "sha256": hashlib.sha256(data).hexdigest(),
        })
        sql.extend([
            "-- BEGIN PINNED STAGE " + name + " blob:" + actual + "\n",
            data.decode("utf-8").rstrip() + "\n",
            "-- END PINNED STAGE " + name + "\n\n",
        ])
    return receipts, sql

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for key in PINNED_CHECKOUTS:
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--output", type=Path,
                        help="EXCLUSIVE temp scratch TEST_ONLY.sql output; omit for pin-only preflight")
    args = parser.parse_args()
    roots = {key: getattr(args, key).resolve() for key in PINNED_CHECKOUTS}
    validate_safety(args.output)
    receipts, sql = prepare(roots)
    out = {
        "kind": "UNI_OPS_ACCEPTED_FIRST_DISPOSABLE_ONLY",
        "success": True,
        "stages": receipts,
        "notVerified": [
            "PostgreSQL compilation", "real GoTrue governor/reviewer/worker",
            "U1A overlap hold", "U1B candidate positive",
            "worker acceptance and one original", "concurrent capacity",
            "Result/Need/no-auto-successor", "production install",
        ],
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        payload = ("-- TEST ONLY: no source authority, no production migration.\n"
                   "-- Actual PG17/GoTrue acceptance must be a SEPARATE protected test.\n\n"
                   + "".join(sql)).encode("utf-8")
        with args.output.open("xb") as f:
            f.write(payload)
        out["scratch_file_sha256"] = hashlib.sha256(payload).hexdigest()
        out["scratch_file"] = str(args.output)
    print(json.dumps(out, sort_keys=True, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())

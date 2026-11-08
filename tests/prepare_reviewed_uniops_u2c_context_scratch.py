#!/usr/bin/env python3
"""TEST ONLY: exactly two reviewed U2C source substitutions in a disposable clone.

The independently pinned 18-stage historical/current assembler runs first.
This wraps its manifest and output; it does not redefine or mutate the trusted
baseline, feature PR, database, auth credentials, or migrations.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

REVIEW_HEAD = "aa117383d693d33dbfe12bdc46fd6c7ae64a7911"
CHANGES = {
    "u2c-accepted-only-original-guard": (
        "4413d84b042a357567a2334cddccc859650c41dc",
        "e07cacd0c5035f05a4017de651cd615a97b2f0f6",
        "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/"
        "02_native_original_writer_acceptance_guard_held.sql",
    ),
    "u2c-schema-and-acl-postconditions": (
        "e67a77508b54ef86d77237d52160d091b2b6ffda",
        "6ac485dc5d11038d8d0d8df5536174791418f046",
        "candidates/atlas_uni_ops_c_u2c_single_rulebook_cutover_v1/"
        "04_postconditions_held.sql",
    ),
}
ORIGINAL_KIND = "UNI_OPS_A_FULL_HISTORY_DISPOSABLE_ONLY"
AMENDED_KIND = "UNI_OPS_U2C_CONTEXT_REVIEW_DISPOSABLE_ONLY"


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise ValueError("U2C disposable review refused: " + reason)


def stage_frame(stage: str, blob: str, payload: bytes) -> bytes:
    require(stage in CHANGES and re.fullmatch(r"[a-f0-9]{40}", blob) is not None,
            "invalid bounded stage")
    return (
        f"-- BEGIN PINNED STAGE {stage} blob:{blob}\n".encode()
        + payload.rstrip() + b"\n"
        + f"-- END PINNED STAGE {stage}\n\n".encode()
    )


def revised_bytes(old_sql: bytes, stages: list[dict], revision: dict[str, bytes]):
    require(len(stages) == 18
            and len({entry.get("stage") for entry in stages}) == 18,
            "18 distinct source stages required")
    require(sum(str(entry["stage"]).startswith("history-") for entry in stages) == 7,
            "seven original historical stages required")
    require(set(revision) == set(CHANGES), "exact two source replacements required")
    result = old_sql
    altered = []
    for entry in stages:
        name = entry["stage"]
        if name not in CHANGES:
            altered.append(dict(entry))
            continue
        old_sha, new_sha, path = CHANGES[name]
        require(entry.get("blob") == old_sha and entry.get("checkout") == "u2c",
                "original stage identity changed: " + name)
        new_data = revision[name]
        require(git_blob(new_data) == new_sha, "reviewed new source blob mismatch: " + name)
        require((b"CREATE " in new_data or name.endswith("postconditions"))
                and len(new_data) > 350,
                "reviewed source incomplete: " + name)
        if name == "u2c-accepted-only-original-guard":
            require(all(token in new_data for token in (
                b"U2C_ACCEPTED_RHYTHM_CONTEXT_ONLY",
                b"o.offer_state='accepted'",
                b"atlas.guard_work_growing_object_context_v1",
                b"physical Work source and exact Ledger custody unproven",
                b"require_accepted_prework_standing_original_v1",
            )), "original writer consent or physical legacy guard lost")
        else:
            require(all(token in new_data for token in (
                b"work_growing_object_context_guard_v1",
                b"U2C_ACCEPTED_RHYTHM_CONTEXT_ONLY",
                b"Original Work",
            )), "review postconditions lost original trigger or source")
        # Existing trusted assembler emitted this wrapped frozen stage, byte
        # identical to its committed checkout; assert exactly one replacement.
        old_b = stage_frame(name, old_sha, b"")  # header only below
        old_header = old_b.split(b"\n", 1)[0] + b"\n"
        end_marker = f"-- END PINNED STAGE {name}\n\n".encode()
        begin = result.find(old_header)
        require(begin >= 0 and result.find(old_header, begin + 1) == -1,
                "original stage marker absent or duplicated: " + name)
        end = result.find(end_marker, begin)
        require(end >= 0 and result.find(end_marker, end + len(end_marker)) == -1,
                "original end marker absent or duplicated: " + name)
        end += len(end_marker)
        result = result[:begin] + stage_frame(name, new_sha, new_data) + result[end:]
        altered.append({
            **entry, "checkout": "u2c_review", "ref": REVIEW_HEAD,
            "path": path, "blob": new_sha,
            "sha256": hashlib.sha256(new_data).hexdigest(),
        })
    require(len(altered) == 18
            and sum(x["checkout"] == "u2c_review" for x in altered) == 2,
            "other source stage changed")
    for entry in altered:
        if entry["stage"] not in CHANGES:
            require(f"-- BEGIN PINNED STAGE {entry['stage']} blob:{entry['blob']}\n".encode() in result,
                    "unmodified source stage missing")
    return result, altered


def run() -> None:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--original", type=Path, required=True)
    cli.add_argument("--original-manifest", type=Path, required=True)
    cli.add_argument("--review-checkout", type=Path, required=True)
    cli.add_argument("--output", type=Path, required=True)
    cli.add_argument("--output-manifest", type=Path, required=True)
    a = cli.parse_args()
    temp = os.environ.get("RUNNER_TEMP", "")
    require(temp and all(
        p.parent.resolve() == Path(temp).resolve()
        for p in (a.original, a.original_manifest, a.output, a.output_manifest)
    ), "all scratch files must remain in RUNNER_TEMP")
    require(a.output.name.endswith("TEST_ONLY.sql")
            and a.output_manifest.suffix == ".json"
            and not a.output.exists() and not a.output_manifest.exists(),
            "new exclusively owned TEST_ONLY output required")
    require(not any(os.environ.get(name) for name in (
        "NOEL_CORE_DATABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"
    )), "secret credentials forbidden during source assembly")
    require(a.original.is_file() and not a.original.is_symlink()
            and a.original_manifest.is_file() and not a.original_manifest.is_symlink(),
            "verified original assembler output required")
    head = subprocess.run(["git", "-C", str(a.review_checkout), "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    require(head == REVIEW_HEAD, "review source checkout drift")
    manifest = json.loads(a.original_manifest.read_text())
    old_data = a.original.read_bytes()
    require(manifest.get("kind") == ORIGINAL_KIND and manifest.get("success") is True,
            "wrong original source family")
    require(manifest.get("stage_count") == 18
            and len(manifest.get("stages", [])) == 18,
            "wrong original stage count")
    require(hashlib.sha256(old_data).hexdigest()
            == manifest.get("scratch_file_sha256"),
            "original scratch digest mismatch")
    review = {}
    for stage, (_, _, path) in CHANGES.items():
        candidate = a.review_checkout / path
        require(candidate.is_file() and not candidate.is_symlink(),
                "review source missing: " + stage)
        review[stage] = candidate.read_bytes()
    data, updated = revised_bytes(old_data, manifest["stages"], review)
    amended = {**manifest, "kind": AMENDED_KIND,
               "source_scope": "16 original immutably pinned + 2 exact U2C review",
               "stages": updated, "stage_count": len(updated),
               "scratch_file_sha256": hashlib.sha256(data).hexdigest()}
    with a.output.open("xb") as stream:
        stream.write(data)
    with a.output_manifest.open("x", encoding="utf-8") as stream:
        json.dump(amended, stream, sort_keys=True)
    # No names, identities, SQL, schema, row data, or secrets in the reporter.
    print("PASS two exact reviewed U2C blobs, sixteen unchanged sources, "
          "seven historical stages; disposable only")


if __name__ == "__main__":
    run()

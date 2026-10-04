#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "supabase" / "migrations"
POLICY_PATH = ROOT / "custody" / "live-custody-reconciliation-policy-v1.json"
BASELINE_PATH = ROOT / "custody" / "production-baseline-v1.json"

SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
REGISTRY_RE = re.compile(r"post-fence-migration-recoveries-v(\d+)\.json$")


def load_json(path: Path):
    return json.loads(path.read_text())


def git_blob(path: Path) -> str:
    return subprocess.check_output(["git", "hash-object", str(path)], text=True).strip()


def fail(message: str) -> None:
    print(f"LIVE_CUSTODY_RECONCILIATION_ERROR={message}")
    raise SystemExit(2)


def load_recovery_registry(policy: dict):
    cfg = policy["recoveryRegistry"]
    first = int(cfg["firstContractVersion"])
    last = int(cfg["lastContractVersion"])
    directory = ROOT / cfg["directory"]
    prefix = cfg["filenamePrefix"]

    latest = {}
    histories = {}
    conflicts = {}
    seen_versions = []

    for version in range(first, last + 1):
        path = directory / f"{prefix}{version}.json"
        if not path.is_file():
            fail(f"missing sealed recovery registry {path.relative_to(ROOT)}")
        data = load_json(path)
        if data.get("contractVersion") != version or data.get("sealed") is not True:
            fail(f"invalid recovery registry contract/seal: {path.relative_to(ROOT)}")
        if data.get("classification") != "retrospective_post_fence_custody_recovery":
            fail(f"unexpected recovery registry classification: {path.relative_to(ROOT)}")
        if version > first:
            expected = f"{prefix}{version - 1}.json"
            if data.get("inherits") != expected:
                fail(f"broken recovery registry inheritance at v{version}: expected {expected!r}")

        seen_versions.append(version)
        rule = str(data.get("rule") or "")
        allows_supersession = "supersed" in rule.lower()

        for row in data.get("recoveries") or []:
            filename = str(row.get("filename") or "")
            sha = str(row.get("gitBlobSha1") or "")
            expected_filename = f"{row.get('version', '')}_{row.get('name', '')}.sql"
            if filename != expected_filename or not SHA1_RE.fullmatch(sha):
                conflicts.setdefault(filename or expected_filename, []).append({
                    "kind": "invalid_registry_row",
                    "registryVersion": version,
                    "row": row,
                })
                continue

            history = histories.setdefault(filename, [])
            if history:
                prior = history[-1]
                if prior["gitBlobSha1"] == sha:
                    conflicts.setdefault(filename, []).append({
                        "kind": "duplicate_registry_row",
                        "priorRegistryVersion": prior["registryVersion"],
                        "registryVersion": version,
                        "gitBlobSha1": sha,
                    })
                elif not allows_supersession:
                    conflicts.setdefault(filename, []).append({
                        "kind": "unapproved_registry_hash_change",
                        "priorRegistryVersion": prior["registryVersion"],
                        "priorGitBlobSha1": prior["gitBlobSha1"],
                        "registryVersion": version,
                        "gitBlobSha1": sha,
                    })

            normalized = {
                "registryVersion": version,
                "registryPath": str(path.relative_to(ROOT)),
                "version": str(row.get("version") or ""),
                "name": str(row.get("name") or ""),
                "filename": filename,
                "gitBlobSha1": sha,
                "logicalOwner": row.get("logicalOwner"),
                "disposition": row.get("disposition"),
                "reason": row.get("reason"),
            }
            history.append(normalized)
            latest[filename] = normalized

    return latest, histories, conflicts, seen_versions


def load_statement_reconciliations(policy: dict):
    cfg = policy["executedStatementReconciliation"]
    path = ROOT / cfg["path"]
    if not path.is_file():
        fail(f"missing executed-statement reconciliation receipt {cfg['path']}")
    actual = git_blob(path)
    expected = cfg["sealedGitBlobSha1"]
    if actual != expected:
        fail(f"executed-statement reconciliation receipt changed: expected {expected}, actual {actual}")

    data = load_json(path)
    if data.get("sealed") is not True or data.get("classification") != "supabase_executed_statement_body_reconciliation":
        fail("invalid executed-statement reconciliation receipt contract")

    rows = {}
    conflicts = {}
    for row in data.get("rows") or []:
        filename = str(row.get("filename") or "")
        pair = (
            str(row.get("canonicalSourceGitBlobSha1") or ""),
            str(row.get("executedBodyGitBlobSha1") or ""),
        )
        if not filename.endswith(".sql") or not all(SHA1_RE.fullmatch(x) for x in pair):
            conflicts.setdefault(filename, []).append({"kind": "invalid_statement_reconciliation", "row": row})
            continue
        if filename in rows:
            conflicts.setdefault(filename, []).append({"kind": "duplicate_statement_reconciliation"})
            continue
        rows[filename] = pair

    if len(rows) != int(cfg["expectedRowCount"]):
        fail(f"expected {cfg['expectedRowCount']} executed-statement reconciliation rows, found {len(rows)}")
    return rows, conflicts


def classify(packet: dict, policy: dict, baseline: dict):
    recovery_latest, recovery_histories, registry_conflicts, registry_versions = load_recovery_registry(policy)
    statement_pairs, statement_conflicts = load_statement_reconciliations(policy)

    global_errors = []
    if packet.get("contractVersion") != 1:
        global_errors.append(f"unexpected packet contractVersion {packet.get('contractVersion')!r}")
    if packet.get("projectRef") != baseline["physicalProject"]["projectRef"]:
        global_errors.append("production project ref does not match baseline")

    expected_fence = baseline["inheritedHistory"]
    fence = packet.get("fence") or {}
    for key in ("migrationCount", "firstVersion", "throughVersion", "ledgerSha256"):
        if fence.get(key) != expected_fence.get(key):
            global_errors.append(f"fence mismatch {key}: expected {expected_fence.get(key)!r}, live {fence.get(key)!r}")

    post_fence = packet.get("postFence") or []
    versions = [str(row.get("version") or "") for row in post_fence]
    if versions != sorted(versions) or len(versions) != len(set(versions)):
        global_errors.append("postFence versions are not strictly ordered and unique")

    current = packet.get("current") or {}
    expected_current_count = expected_fence["migrationCount"] + len(post_fence)
    if current.get("migrationCount") != expected_current_count:
        global_errors.append(
            f"current migrationCount mismatch: expected {expected_current_count}, live {current.get('migrationCount')!r}"
        )
    expected_latest = versions[-1] if versions else expected_fence["throughVersion"]
    if current.get("latestVersion") != expected_latest:
        global_errors.append(
            f"current latestVersion mismatch: expected {expected_latest!r}, live {current.get('latestVersion')!r}"
        )

    cut = str(policy["stableRecoveryCutThroughVersion"])
    rows = []
    counts = Counter()

    for live in post_fence:
        version = str(live.get("version") or "")
        name = str(live.get("name") or "")
        executed = str(live.get("gitBlobSha1") or "")
        filename = f"{version}_{name}.sql"
        path = MIGRATIONS / filename
        exists = path.is_file()
        source = git_blob(path) if exists else None
        recovery = recovery_latest.get(filename)
        recovery_history = recovery_histories.get(filename) or []
        row_registry_conflicts = registry_conflicts.get(filename) or []
        row_statement_conflicts = statement_conflicts.get(filename) or []
        statement_pair = statement_pairs.get(filename)

        evidence = []
        if exists:
            evidence.append("canonical_file_present")
        if recovery:
            evidence.append("sealed_recovery_receipt_present")
        if statement_pair:
            evidence.append("sealed_statement_body_reconciliation_present")

        if row_registry_conflicts or row_statement_conflicts:
            state = "registry_conflict"
            reason = "custody evidence for this migration is internally conflicting"
        elif exists and source == executed:
            state = "canonical_exact"
            reason = "canonical Git source blob equals live executed-statement body hash"
        elif exists and statement_pair == (source, executed):
            state = "canonical_reconciled"
            reason = "canonical source/live executed-body difference is sealed by the two-hash reconciliation receipt"
        elif not exists and recovery and recovery.get("gitBlobSha1") == executed:
            state = "registered_recovery_missing_file"
            reason = "sealed recovery receipt already adjudicates the exact live body, but the canonical SQL file is absent"
        elif not exists and version > cut:
            state = "post_cut_active_tail"
            reason = "live migration is newer than the stable recovery cut and lacks an existing sealed recovery receipt"
        elif not exists:
            state = "unregistered_live_source_gap"
            reason = "live migration has no canonical SQL file and no matching sealed recovery receipt"
        else:
            state = "registry_conflict"
            reason = "canonical file exists but its source/executed-body pair is neither exact nor covered by the sealed two-hash receipt"

        counts[state] += 1
        rows.append({
            "version": version,
            "name": name,
            "filename": filename,
            "state": state,
            "reason": reason,
            "canonicalFilePresent": exists,
            "canonicalSourceGitBlobSha1": source,
            "liveExecutedBodyGitBlobSha1": executed,
            "recoveryReceipt": recovery,
            "recoveryReceiptHistory": recovery_history,
            "statementBodyReconciliation": (
                {
                    "canonicalSourceGitBlobSha1": statement_pair[0],
                    "executedBodyGitBlobSha1": statement_pair[1],
                }
                if statement_pair else None
            ),
            "registryConflicts": row_registry_conflicts + row_statement_conflicts,
            "evidence": evidence,
        })

    blocking_states = set(policy["states"]["blocking"])
    blocking = sum(counts[s] for s in blocking_states)
    materializable = counts["registered_recovery_missing_file"]

    manifest = {
        "contractVersion": 1,
        "classification": "canonical_live_custody_reconciliation_manifest",
        "projectRef": packet.get("projectRef"),
        "fenceVersion": expected_fence["throughVersion"],
        "stableRecoveryCutThroughVersion": cut,
        "liveMigrationCount": current.get("migrationCount"),
        "liveLatestVersion": current.get("latestVersion"),
        "postFenceCount": len(post_fence),
        "summary": {
            "states": dict(sorted(counts.items())),
            "blockingCount": blocking,
            "materializableByExistingReceiptCount": materializable,
            "globalErrorCount": len(global_errors),
        },
        "registry": {
            "versionsLoaded": registry_versions,
            "latestReceiptCount": len(recovery_latest),
            "conflictingFilenameCount": len(registry_conflicts),
        },
        "executedStatementReconciliation": {
            "rowCount": len(statement_pairs),
            "conflictingFilenameCount": len(statement_conflicts),
        },
        "globalErrors": global_errors,
        "rows": rows,
    }
    return manifest


def main():
    parser = argparse.ArgumentParser(description="Classify every live post-fence migration against canonical source and sealed custody evidence.")
    parser.add_argument("packet", type=Path, help="JSON packet from shared_db_custody_release_packet_v1()")
    parser.add_argument("--manifest", type=Path, required=True, help="Path to write the deterministic reconciliation manifest")
    parser.add_argument("--enforce", action="store_true", help="Exit 1 while any blocking state or global contract error remains")
    args = parser.parse_args()

    policy = load_json(POLICY_PATH)
    baseline = load_json(BASELINE_PATH)
    packet = load_json(args.packet)
    manifest = classify(packet, policy, baseline)

    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    summary = manifest["summary"]
    print("LIVE_CUSTODY_RECONCILIATION_SUMMARY=" + json.dumps(summary, sort_keys=True, separators=(",", ":")))
    for state, count in summary["states"].items():
        print(f"LIVE_CUSTODY_STATE {state}={count}")
    print(f"LIVE_CUSTODY_MANIFEST={args.manifest}")

    if args.enforce and (summary["blockingCount"] or summary["globalErrorCount"]):
        print("Live production custody reconciliation FAILED: blocking custody states remain.")
        raise SystemExit(1)
    if args.enforce:
        print("Live production custody reconciliation passed: every live post-fence migration is canonically source-custodied.")


if __name__ == "__main__":
    main()

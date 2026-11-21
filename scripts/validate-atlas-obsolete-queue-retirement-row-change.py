#!/usr/bin/env python3
"""TEST ONLY: bounded Atlas obsolete 2026 queue DML no-loss proof.

This reuses the protected existing PRE1 full-row fingerprint implementation
without modifying its exact trusted Git blob or weakening its verify mode.
Only the three directly authorized historical tables may change; counts
must remain exactly equal for them. The held source itself independently
checks exact 64/75/3 row identities, unmodified non-target rows, and Work.
Source/user authorization: optical-lift/atlas#532.
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

SOURCE = Path(__file__).with_name("validate-atlas-access03c-pre1-local-row-integrity.py")
EXPECTED_CHANGED = frozenset({
    "atlas.tasks",
    "atlas.planned_work_occurrences",
    "atlas.task_release_queue_items",
})

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db-url", required=True)
    ap.add_argument("--snapshot", type=Path, required=True)
    ap.add_argument("--mode", choices=("capture", "verify"), required=True)
    a = ap.parse_args()
    spec = importlib.util.spec_from_file_location("trusted_pre1", SOURCE)
    if not spec or not spec.loader:
        raise RuntimeError("Exact existing PRE1 row integrity source not found")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.local_database_only(a.db_url)
    current = mod.fingerprint(a.db_url)
    if a.mode == "capture":
        data = json.dumps({"version": 1, "tables": current}, sort_keys=True)
        # Existing PRE1 capture enforces exclusive new snapshot and 0600.
        mod.run(a.db_url, "capture", a.snapshot)
        return 0
    before = json.loads(a.snapshot.read_text(encoding="utf-8"))
    if before.get("version") != 1 or not isinstance(before.get("tables"), dict):
        raise RuntimeError("No valid pre-mutation Atlas base-table fingerprint")
    baseline = before["tables"]
    if len(baseline) < 700 or set(current) != set(baseline):
        raise RuntimeError("Unexpected Atlas table schema or incomplete base snapshot")
    changed = frozenset(k for k in current if current[k] != baseline[k])
    if changed != EXPECTED_CHANGED:
        raise RuntimeError("Unexpected Atlas changes in retirement proof: " +
                           ", ".join(sorted(changed.symmetric_difference(EXPECTED_CHANGED))))
    for table in EXPECTED_CHANGED:
        if current[table]["rows"] != baseline[table]["rows"]:
            raise RuntimeError("Original rows inserted or deleted: "+table)
    print("PASS historical retirement: exactly three authorized Atlas base relations changed, "+
          str(len(current)-3)+" other Atlas tables unchanged, all original row counts held")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        # Never print source row contents or database connection details.
        print(str(exc), file=sys.stderr)
        sys.exit(1)

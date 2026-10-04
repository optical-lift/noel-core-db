#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_RECONCILER = ROOT / "scripts" / "reconcile-live-production-custody.py"

spec = importlib.util.spec_from_file_location("live_custody_v1", BASE_RECONCILER)
if spec is None or spec.loader is None:
    raise SystemExit(f"Unable to load {BASE_RECONCILER}")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base_loader = base.load_statement_reconciliations


def load_statement_reconciliations(policy: dict):
    rows, conflicts = base_loader(policy)
    cfg = policy["executedStatementReconciliation"]

    for supplement_cfg in cfg.get("supplements") or []:
        path = ROOT / supplement_cfg["path"]
        if not path.is_file():
            base.fail(f"missing executed-statement reconciliation supplement {supplement_cfg['path']}")

        actual = base.git_blob(path)
        expected = str(supplement_cfg["sealedGitBlobSha1"])
        if actual != expected:
            base.fail(
                f"executed-statement reconciliation supplement changed: expected {expected}, actual {actual}"
            )

        data = base.load_json(path)
        if data.get("sealed") is not True or data.get("classification") != "supabase_executed_statement_body_reconciliation":
            base.fail(f"invalid executed-statement reconciliation supplement contract: {supplement_cfg['path']}")

        supplement_rows = data.get("rows") or []
        expected_count = int(supplement_cfg["expectedRowCount"])
        if len(supplement_rows) != expected_count:
            base.fail(
                f"expected {expected_count} rows in {supplement_cfg['path']}, found {len(supplement_rows)}"
            )

        for row in supplement_rows:
            filename = str(row.get("filename") or "")
            pair = (
                str(row.get("canonicalSourceGitBlobSha1") or ""),
                str(row.get("executedBodyGitBlobSha1") or ""),
            )
            if not filename.endswith(".sql") or not all(base.SHA1_RE.fullmatch(x) for x in pair):
                conflicts.setdefault(filename, []).append(
                    {"kind": "invalid_statement_reconciliation_supplement", "row": row, "path": supplement_cfg["path"]}
                )
                continue
            if filename in rows:
                conflicts.setdefault(filename, []).append(
                    {"kind": "duplicate_statement_reconciliation_across_receipts", "path": supplement_cfg["path"]}
                )
                continue
            rows[filename] = pair

    return rows, conflicts


base.load_statement_reconciliations = load_statement_reconciliations
base.main()

#!/usr/bin/env python3
"""Static regression assertions for cross-product migration isolation.

These are code/config checks, never a substitute for the live global custody
audit or a production schema clone. No secrets, fixtures or research rows.
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = json.loads((root / "custody/release-lanes-v1.json").read_text())
lanes = spec["lanes"]
expected = {"atlas": "atlas_", "wnph": "wnph_", "titus": "titus_", "noel": "noel_", "shared": "shared_"}
assert {k: v["migrationPrefix"] for k, v in lanes.items()} == expected
assert spec["unclassifiedLiveMigrationPolicy"] == "blocking_for_every_release_lane"

def classify(name):
    return next((lane for lane, config in lanes.items()
                 if name.startswith(config["migrationPrefix"])), "unclassified")

def blocks(release_lane, live_name):
    owner = classify(live_name)
    return release_lane == "shared" or owner in (release_lane, "shared", "unclassified")

for own, prefix in expected.items():
    assert classify(prefix + "structural_example_v1") == own
assert classify("legacy_unclassified_change") == "unclassified"
assert not blocks("atlas", "noel_reality_function_v2")
assert not blocks("noel", "atlas_ledger_feature_v2")
assert not blocks("atlas", "titus_private_formation_v2")
assert not blocks("titus", "noel_word_study_v2")
assert blocks("atlas", "atlas_ledger_feature_v2")
assert blocks("noel", "noel_research_view_v2")
assert blocks("atlas", "shared_identity_kernel_v2")
assert blocks("titus", "shared_principal_auth_v2")
assert blocks("atlas", "uncategorized_live_ddl")
assert blocks("noel", "uncategorized_live_ddl")
assert blocks("shared", "noel_unreconciled_v2")

for lane in ("noel", "atlas", "titus", "wnph"):
    assert lanes[lane]["forbiddenSqlFragments"], lane
for fragment in ("atlas.", "titus.", "wnph."):
    assert fragment in lanes["noel"]["forbiddenSqlFragments"]

workflow = (root / ".github/workflows/custody.yml").read_text()
assert "if: github.event_name == 'pull_request'" in workflow
assert "run: bash scripts/reconcile-live-production-custody.sh --report-only" in workflow
assert "if: github.event_name != 'pull_request'" in workflow
assert "run: bash scripts/reconcile-live-production-custody.sh --enforce" in workflow
assert "continue-on-error: true" not in workflow

release = (root / ".github/workflows/production-db-release.yml").read_text()
assert "environment: production" in release
assert "github.ref == 'refs/heads/main'" in release
assert "- noel" in release
assert "run: bash scripts/check-live-production-custody-lane.sh" in release
assert "continue-on-error: true" in release  # audit only; target lane still blocks
assert "run: bash scripts/release-production-migration.sh" in release
print("Domain-isolation regressions PASS: Noel and Atlas scoped independently; shared and unclassified remain blocking; global audit remains strict on main.")

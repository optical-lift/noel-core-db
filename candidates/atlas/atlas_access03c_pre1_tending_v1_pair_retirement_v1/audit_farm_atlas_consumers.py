#!/usr/bin/env python3
"""Read-only exact-commit census of CURRENT farm-atlas app sources.

This does not prove absence from deployed, external, historical or dynamic clients.
"""
import json
import sys
from pathlib import Path

TARGETS = ("tending_task_context_v1", "tending_card_json_v1")
ROOTS = ("app", "components", "lib", "hooks", "services", "src", "pages")
EXTENSIONS = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"}

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def source_inventory(repo):
    inspected = 0
    found = []
    for rootname in ROOTS:
        src = repo / rootname
        if not src.is_dir():
            continue
        for path in src.rglob("*"):
            if not path.is_file() or path.is_symlink() or path.suffix.lower() not in EXTENSIONS:
                continue
            if any(p in ("node_modules", ".next", "dist", "build") for p in path.parts):
                continue
            inspected += 1
            body = path.read_text("utf-8")
            hits = [target for target in TARGETS if target in body]
            if hits:
                found.append({"path": path.relative_to(repo).as_posix(), "names": hits})
    return inspected, sorted(found, key=lambda r: r["path"])

def main():
    require(len(sys.argv) == 2, "Usage: audit_farm_atlas_consumers.py <farm-atlas checkout>")
    repo = Path(sys.argv[1]).resolve(strict=True)
    require(repo.is_dir(), "Missing external checkout")
    routes = {
        "app/api/atlas/tending/task-context/route.ts": 'rpc("tending_task_context_v2"',
        "app/api/atlas/tending/bed/route.ts": 'rpc("tending_bed_v1"',
        "app/api/atlas/tending/route.ts": 'rpc("tending_board_v1"',
    }
    for relative, call in routes.items():
        path = repo / relative
        require(path.is_file(), "Missing expected farm-atlas live route: " + relative)
        require(call in path.read_text("utf-8"), "Live route changed without caller review: " + relative)

    # These names remain in immutable historical migration expectations,
    # NOT current app invocations. Do not rewrite history to pass a gate.
    history = repo / "tests/atlas-narrow-tending-helpers.test.mjs"
    require(history.is_file(), "Missing historical Tending migration test")
    historic_text = history.read_text("utf-8")
    require(all(n in historic_text for n in TARGETS),
            "Historical Tending test inventory changed; inspect before retirement")

    count, hits = source_inventory(repo)
    print("ACCESS03C_PRE1_PINNED_FARM_ATLAS_SOURCE=" +
          json.dumps({"scanned": count, "active_v1_refs": hits,
                      "history_test_preserved": True, "v2_route_preserved": True},
                     sort_keys=True))
    require(count > 150, "Unexpectedly small active application census")
    require(not hits, "Unreviewed ACTIVE farm-atlas v1 use remains; do not retire functions")
    print("PASS: no literal v1 use in pinned active app roots; historical tests retained")
    print("NOT PROVEN: older deployments, other apps, clients, dynamic RPC names")

if __name__ == "__main__":
    main()

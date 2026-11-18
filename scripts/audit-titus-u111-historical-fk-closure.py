#!/usr/bin/env python3
"""U1.11: catalog-only Titus historical dependency audit (not a backup).

Input must be a JSON array of {child,parent} relation names extracted from
pg_catalog foreign keys. Never connects to any database or handles row data.
A dependency report is NOT deletion permission or a retention attestation.
"""
import argparse
from collections import defaultdict, deque
import json
from pathlib import Path
import re
import sys

CONTRACT = "titus_u111_catalog_only_dependency_graph_v1"
ROOTS = (
    "titus.customer_course_drafts_v1",
    "titus.customer_workspace_entitlements_v1",
    "titus.programs",
)
NAME = re.compile(r"[a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*\Z")
MAX_EDGES = 20000


def audit(edges):
    if not isinstance(edges, list) or not 0 < len(edges) <= MAX_EDGES:
        raise ValueError("a bounded nonempty catalog FK edge array is required")
    incoming = defaultdict(set)
    relations = set()
    normalized = set()
    for record in edges:
        if not isinstance(record, dict) or set(record) != {"child", "parent"}:
            raise ValueError("catalog edge must contain only child and parent")
        child, parent = record["child"], record["parent"]
        if not all(isinstance(x, str) and NAME.fullmatch(x) for x in (child, parent)):
            raise ValueError("malformed catalog relation name")
        # Keep duplicates from inflating the evidence or hiding an unreviewed edge.
        normalized.add((child, parent))
        incoming[parent].add(child)
        relations.update((child, parent))
    missing = sorted(set(ROOTS) - relations)
    if missing:
        raise ValueError("required historical root is absent from the catalog graph: "
                         + ",".join(missing))
    descendants = set(ROOTS)
    pending = deque(ROOTS)
    while pending:
        for child in sorted(incoming[pending.popleft()]):
            if child not in descendants:
                descendants.add(child)
                pending.append(child)
    outside = sorted(
        (child, parent) for child, parent in normalized
        if child in descendants and parent not in descendants
    )
    return {
        "contract": CONTRACT,
        "rootRelations": list(ROOTS),
        "observedForeignKeyPairs": len(normalized),
        "historicalDescendantRelations": sorted(descendants),
        "externalForeignKeyReferences": [
            {"child": child, "parent": parent} for child, parent in outside
        ],
        "historicalDescendantCount": len(descendants),
        "externalReferenceCount": len(outside),
        "requiresIndependentRowScopedDispositions": True,
        "actualCustomerRowsRead": False,
        "dataBackupTaken": False,
        "productionWriteAuthorized": False,
        "deletionOrReleaseAuthorized": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edges-json", type=Path, required=True)
    parser.add_argument("--output-json", type=Path)
    args = parser.parse_args()
    if not args.edges_json.is_file() or args.edges_json.stat().st_size > 2_000_000:
        parser.error("catalog-only JSON input is missing or too large")
    try:
        source = json.loads(args.edges_json.read_text(encoding="utf-8"))
        result = audit(source)
    except (ValueError, UnicodeError) as exc:
        parser.error(str(exc))
    serialized = json.dumps(result, sort_keys=True, indent=2) + "\n"
    if args.output_json:
        if args.output_json.exists() or args.output_json.resolve() == args.edges_json.resolve():
            parser.error("refusing to overwrite an existing catalog receipt")
        args.output_json.write_text(serialized, encoding="utf-8")
    else:
        sys.stdout.write(serialized)


if __name__ == "__main__":
    main()

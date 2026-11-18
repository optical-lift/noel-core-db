#!/usr/bin/env python3
"""U1.13: fail-closed historical row-scope review. CATALOG METADATA ONLY.

This program has no database client, credential, network, COPY or pg_dump.
A success means every catalog relationship has an explicit *held* disposition;
it never approves reading a single real row, selecting a live customer,
or deleting historical sources.
"""
import argparse
import json
from collections import defaultdict, deque
from pathlib import Path
import re

NAME = re.compile(r"[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\Z")
CONTRACT = "titus_u113_historical_row_scope_review_v1"
EDGES_CONTRACT = "titus_u113_schema_fk_pairs_metadata_only_v1"
ROOTS = (
    "titus.customer_course_drafts_v1",
    "titus.customer_workspace_entitlements_v1",
    "titus.programs",
)
HISTORIC = {
    "titus.customer_workspaces_v1",
    "titus.customer_workspace_entitlements_v1",
    "titus.customer_course_drafts_v1",
    "titus.customer_course_material_revisions_v1",
    "titus.customer_course_units_v1",
    "titus.customer_course_unit_revisions_v1",
}


def check(manifest, catalog):
    if manifest.get("contractVersion") != CONTRACT:
        raise ValueError("wrong historical scope contract")
    if catalog.get("contractVersion") != EDGES_CONTRACT or catalog.get("rowValuesIncluded") is not False:
        raise ValueError("foreign-key input is not catalog-only")
    if tuple(manifest.get("roots", ())) != ROOTS:
        raise ValueError("historical roots changed without separate review")
    for name in ("customerRowsRead", "dataCaptureAuthorized",
                 "persistentVaultConfigured", "productionWritesAuthorized",
                 "deletionAuthorized"):
        if manifest.get(name) is not False:
            raise ValueError("source-only manifest cannot approve real data or changes")
    if manifest.get("sourceSchemaMetadataOnly") is not True:
        raise ValueError("catalog evidence cannot claim data backup")
    if manifest.get("previousHeldSourceSha") != "f9cabf634d0b660f25d6b7244ff7351623aa4c28":
        raise ValueError("immutable held Course source selector changed")
    edges = catalog.get("foreignKeyPairs")
    if not isinstance(edges, list) or not 0 < len(edges) <= 20000:
        raise ValueError("missing/broad foreign-key catalog")
    children = defaultdict(set)
    normalized = set()
    for edge in edges:
        if not isinstance(edge, dict) or set(edge) != {"child", "parent"}:
            raise ValueError("foreign-key evidence must have only child/parent")
        child, parent = edge["child"], edge["parent"]
        if not all(isinstance(x, str) and NAME.fullmatch(x) for x in (child, parent)):
            raise ValueError("malformed catalog relation")
        normalized.add((child, parent))
        children[parent].add(child)
    if len(normalized) != len(edges):
        raise ValueError("ambiguous duplicate catalog edges")
    found = set(ROOTS)
    queue = deque(ROOTS)
    while queue:
        for child in sorted(children[queue.popleft()]):
            if child not in found:
                found.add(child)
                queue.append(child)
    external = {(child, parent) for child, parent in normalized
                if child in found and parent not in found}
    parents = {parent for _, parent in external}
    dispositions = manifest.get("descendantDispositions")
    ext = manifest.get("externalParentDispositions")
    if not isinstance(dispositions, dict) or set(dispositions) != found:
        raise ValueError("unreviewed new or missing historical descendant relation")
    if not isinstance(ext, dict) or set(ext) != parents:
        raise ValueError("unreviewed external owner/dependency relation")
    if set(manifest.get("protectedCustomerTableScope", ())) != HISTORIC:
        raise ValueError("SK101 six-original preserve scope drift")
    if len(manifest["protectedCustomerTableScope"]) != len(HISTORIC):
        raise ValueError("ambiguous original capture scope")
    for table, record in dispositions.items():
        expected = "preserve_exact_original" if table in HISTORIC else "pending_row_scope_review"
        if not isinstance(record, dict) or record != {
            "disposition": expected, "rowSelector": "not_authorized"
        }:
            raise ValueError("historical row disposition changed without approval")
    for table, record in ext.items():
        expected = ("preserve_exact_original" if table == "titus.customer_workspaces_v1"
                    else "independent_original_do_not_duplicate")
        if not isinstance(record, dict) or record != {
            "disposition": expected, "rowSelector": "not_authorized"
        }:
            raise ValueError("independent source disposition changed without approval")
    # This pinned observation is a time-bounded contract. New schema edges must
    # fail until reviewed; never silently assume the old 39/38/13 coverage.
    if (len(normalized), len(found), len(external), len(parents)) != (168, 39, 38, 13):
        raise ValueError("historical FK graph drift requires renewed review")
    return {
        "contractVersion": CONTRACT,
        "reviewedAtCatalogStructureOnly": True,
        "fkEdges": len(normalized), "dependentRelations": len(found),
        "externalReferences": len(external), "externalParentRelations": len(parents),
        "exactLegacyCustomerSourceRelations": len(HISTORIC),
        "rowSelectionApproved": False, "customerDataAccess": False,
        "backupCreated": False, "restoredRealData": False,
        "deletionAuthorized": False,
        "next": "owner-scoped row predicates, durable vault and separate protected run",
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--catalog", type=Path, required=True)
    args = p.parse_args()
    for file in (args.manifest, args.catalog):
        if not file.is_file() or file.stat().st_size > 300000:
            p.error("missing or oversized structural input")
    try:
        result = check(json.loads(args.manifest.read_text("utf-8")),
                       json.loads(args.catalog.read_text("utf-8")))
    except (ValueError, KeyError, TypeError):
        p.error("historical scope or catalog graph rejected")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()

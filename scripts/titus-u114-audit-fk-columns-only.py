#!/usr/bin/env python3
"""U1.14 source-only FK column reviewer; never reads a database or customer rows.

Input is untrusted catalog JSON from a separately authorized metadata-only
inspection. Matching historical relations does NOT select any particular row,
authorize a backup, or authorize a delete.
"""
import argparse
import json
from pathlib import Path
import re
import sys

REL = re.compile(r"[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\Z")
COL = re.compile(r"[a-z_][a-z0-9_]*\Z")
CONTRACT = "titus_u114_fk_column_catalog_only_v1"
SNAPSHOT = "titus_u113_schema_fk_pairs_metadata_only_v1"
FK_KEYS = {
    "child", "parent", "constraintName", "childColumns", "parentColumns",
    "onDeleteCode", "onUpdateCode", "deferrable", "initiallyDeferred",
}
ACTIONS = {"a", "r", "c", "n", "d"}


def check(catalog, prior):
    if not isinstance(catalog, dict) or set(catalog) != {
        "contractVersion", "rowValuesIncluded", "rowSelectionAuthorized",
        "productionChangesAuthorized", "foreignKeys",
    }:
        raise ValueError("unexpected catalog contract")
    if (catalog["contractVersion"] != CONTRACT
            or catalog["rowValuesIncluded"] is not False
            or catalog["rowSelectionAuthorized"] is not False
            or catalog["productionChangesAuthorized"] is not False):
        raise ValueError("metadata read cannot authorize customer operations")
    if (not isinstance(prior, dict) or prior.get("contractVersion") != SNAPSHOT
            or prior.get("rowValuesIncluded") is not False):
        raise ValueError("missing held U1.13 structural control")
    pairs = prior.get("foreignKeyPairs")
    if (not isinstance(pairs, list) or len(pairs) != 168
            or any(not isinstance(p, dict) or set(p) != {"child", "parent"}
                   for p in pairs)):
        raise ValueError("prior structural control incomplete")
    required = {(p["child"], p["parent"]) for p in pairs}
    if len(required) != 168:
        raise ValueError("duplicate old relation pairs")
    records = catalog.get("foreignKeys")
    if not isinstance(records, list) or len(records) != 170:
        raise ValueError("catalog FK count changed; re-review required")
    observed, constraint_keys = set(), set()
    for record in records:
        if not isinstance(record, dict) or set(record) != FK_KEYS:
            raise ValueError("unknown FK evidence field")
        child, parent, name = (
            record["child"], record["parent"], record["constraintName"]
        )
        if (not isinstance(child, str) or not REL.fullmatch(child)
                or not isinstance(parent, str) or not REL.fullmatch(parent)
                or not isinstance(name, str) or not COL.fullmatch(name)):
            raise ValueError("invalid relation/constraint metadata")
        key = (child, parent, name)
        if key in constraint_keys:
            raise ValueError("duplicated FK constraint")
        constraint_keys.add(key)
        observed.add((child, parent))
        cc, pc = record["childColumns"], record["parentColumns"]
        if (not isinstance(cc, list) or not isinstance(pc, list)
                or not cc or len(cc) != len(pc)
                or len(cc) != len(set(cc)) or len(pc) != len(set(pc))):
            raise ValueError("incomplete or ambiguous FK column alignment")
        if any(not isinstance(c, str) or not COL.fullmatch(c) for c in cc + pc):
            raise ValueError("invalid FK column name")
        if (record["onDeleteCode"] not in ACTIONS
                or record["onUpdateCode"] not in ACTIONS
                or type(record["deferrable"]) is not bool
                or type(record["initiallyDeferred"]) is not bool
                or (record["initiallyDeferred"] and not record["deferrable"])):
            raise ValueError("invalid FK operation metadata")
    if observed != required:
        raise ValueError("historical FK topology drift; return to scope review")
    expansion = verify_course_shell_root_extension(prior)
    return {
        "contract": CONTRACT,
        "catalogConstraintsReviewed": 170,
        "relationPairsMatched": 168,
        "historicalRelationsWithOldCourseRoot": expansion["expandedRelations"],
        "additionalCourseRootRelations": expansion["addedRelations"],
        "recordSelectionAuthorized": False,
        "customerDataRead": False,
        "backupCreated": False,
        "restoredRealData": False,
        "sourceMigrationAuthorized": False,
        "deletionAuthorized": False,
    }



# U1.13's three roots purposely did NOT include the old public course root.
# This fourth-root closure is a separate held structural review; it does not
# authorize deletion of any of the 15 old shells or their shared descendants.
EXPECTED_NEW_COURSE_ROOT_RELATIONS = {
    "titus.courses",
    "titus.course_slots",
    "titus.course_slot_activity_log",
    "titus.course_lesson_placements",
    "titus.course_lesson_prerequisites",
    "titus.course_teachers",
}


def verify_course_shell_root_extension(prior):
    pairs = prior["foreignKeyPairs"]
    children = {}
    for edge in pairs:
        children.setdefault(edge["parent"], set()).add(edge["child"])

    def reachable(roots):
        found = set(roots)
        queue = list(roots)
        for relation in queue:
            for child in sorted(children.get(relation, ())):
                if child not in found:
                    found.add(child)
                    queue.append(child)
        return found

    old_roots = (
        "titus.customer_course_drafts_v1",
        "titus.customer_workspace_entitlements_v1",
        "titus.programs",
    )
    old_scope = reachable(old_roots)
    extended_scope = reachable(old_roots + ("titus.courses",))
    if (len(old_scope) != 39 or len(extended_scope) != 45
            or extended_scope - old_scope != EXPECTED_NEW_COURSE_ROOT_RELATIONS):
        raise ValueError("old Course-shell structural scope requires re-review")
    return {
        "expandedRelations": len(extended_scope),
        "addedRelations": len(extended_scope - old_scope),
        "rowSelectionAuthorized": False,
        "deletionAuthorized": False,
    }


def unique_keys(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError("duplicate JSON key")
        obj[key] = value
    return obj


def load(path):
    file = Path(path)
    if not file.is_file() or file.stat().st_size > 1500000:
        raise ValueError("missing or oversized catalog")
    return json.loads(file.read_text("utf-8"), object_pairs_hook=unique_keys)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog-file", required=True)
    parser.add_argument("--relationship-snapshot", required=True)
    args = parser.parse_args()
    try:
        check(load(args.catalog_file), load(args.relationship_snapshot))
    except (OSError, UnicodeError, ValueError, TypeError, KeyError):
        print("BLOCKED historical FK column metadata review", file=sys.stderr)
        raise SystemExit(2)
    print("PASS metadata FK column topology ONLY; no rows or actions authorized")


if __name__ == "__main__":
    main()

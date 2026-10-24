#!/usr/bin/env python3
"""Block *new* human access/admission by historical Organization Membership.

Production v1 still has 192 historical function readers. This gate does not
pretend they disappeared. It ensures no further separate Person-type authority
is introduced, and that an explicitly retired path cannot silently return.
"""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "architecture/audits/universal-person-legacy-membership-dependencies-20261024.json"
CUTOFF = 20261024213000
RETIRED = {
    "list_foundry_source_custody_reviewers_self_api_v1",
    "request_foundry_source_custody_review_self_api_v1",
    "propose_native_ledger_standing_scope_owner_self_api_v1",
    "assign_native_ledger_company_work_under_scope_owner_self_api_v1",
}
FUNCTION = re.compile(r"\\bCREATE\\s+OR\\s+REPLACE\\s+FUNCTION\\s+(?:\\w+\\.)?(\\w+)\\s*\\(", re.I)
LEGACY = re.compile(r"\\batlas\\.organization_memberships\\b|\\borganization_employee_seats\\b", re.I)
SUBTYPE = re.compile(r"\\b(?:person|human|user|reviewer)_(?:employee|consultant|subscriber)_(?:seat|identity|access)\\b", re.I)


def violations(sql, prior_functions):
    without_comments = re.sub(r"/\\*.*?\\*/", " ", sql, flags=re.S)
    without_comments = re.sub(r"--[^\\n]*", " ", without_comments)
    found = []
    if re.search(r"\\bCREATE\\s+TABLE\\s+(?:atlas\\.)?organization_employee_seats\\b", without_comments, re.I):
        found.append("Physical employee-person seat resurrected")
    if SUBTYPE.search(without_comments):
        found.append("New separate Person access/identity type")
    matches = list(FUNCTION.finditer(without_comments))
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(without_comments)
        body = without_comments[match.start():end]
        name = match.group(1).lower()
        if LEGACY.search(body):
            if name in RETIRED:
                found.append(f"Retired Person authority reintroduced: {name}")
            elif name not in prior_functions:
                found.append(f"New function derives from legacy membership: {name}")
    return found


def main():
    if not BASELINE.exists():
        raise SystemExit("Canonical Person dependency inventory missing")
    items = json.loads(BASELINE.read_text())["functions"]
    prior = {r["function_name"].lower() for r in items}
    issues = []
    migrations = ROOT / "supabase/migrations"
    for path in sorted(migrations.glob("20*.sql")):
        try:
            ver = int(path.name.split("_", 1)[0])
        except ValueError:
            continue
        if ver < CUTOFF:
            continue
        for reason in violations(path.read_text(), prior):
            issues.append(f"{path.relative_to(ROOT)}: {reason}")
    if issues:
        for issue in issues:
            print(issue, file=sys.stderr)
        raise SystemExit(1)
    print("Universal Person authority regression gate passed: no new human subtypes or membership access, and retired routes remain closed.")


if __name__ == "__main__":
    main()

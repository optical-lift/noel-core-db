#!/usr/bin/env python3
"""Fail-closed verification of an OWNER-authored private Titus pilot request.

This reads only the GitHub issue response downloaded by a protected workflow;
it never trusts a caller's email or issue number without an exact owner match.
"""
import json
import re
import sys
from pathlib import Path


def verify(issue: object, email: str, issue_number: str) -> None:
    if not isinstance(issue, dict):
        raise ValueError("Issue JSON must be an object")
    if not isinstance(email, str) or not re.fullmatch(
        r"[^\s@]{1,120}@[^\s@]{1,120}", email
    ):
        raise ValueError("Exact email required")
    if not re.fullmatch(r"[1-9][0-9]{0,6}", issue_number):
        raise ValueError("Exact numeric approval issue required")
    owner = issue.get("user") or {}
    if not isinstance(owner, dict) or owner.get("login") != "optical-lift":
        raise ValueError("Approval must come from the repository owner")
    if issue.get("author_association") != "OWNER":
        raise ValueError("GitHub did not verify owner association")
    if issue.get("state") != "open" or issue.get("number") != int(issue_number):
        raise ValueError("Issue is missing, closed, or not the requested issue")
    title = f"Titus private-pilot issuance request: {email} (source-authorized only)"
    if issue.get("title") != title:
        raise ValueError("Issue title does not exactly authorize target email")
    if issue.get("html_url") != (
        f"https://github.com/optical-lift/noel-core-db/issues/{issue_number}"
    ):
        raise ValueError("Wrong issue source")
    body = issue.get("body")
    if not isinstance(body, str):
        raise ValueError("Authorization body unavailable")
    if f"**Authorized target:** `{email}`" not in body:
        raise ValueError("Exact email not authorized in issue body")
    if "**Grant kind:** `private_pilot`" not in body:
        raise ValueError("Only explicit private-pilot authorization accepted")
    if "No payment may be inferred or invented" not in body:
        raise ValueError("Grant cannot be falsely treated as a purchase")


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("Usage: verify-titus-pilot-approval.py ISSUE_JSON EMAIL NUMBER")
    issue = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    try:
        verify(issue, sys.argv[2], sys.argv[3])
    except (ValueError, KeyError) as exc:
        raise SystemExit(f"DENIED: {exc}") from exc
    print("PASS: exact OWNER issue, target Auth email and private-pilot source approved")


if __name__ == "__main__":
    main()

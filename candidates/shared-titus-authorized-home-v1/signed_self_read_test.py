#!/usr/bin/env python3
"""Read-only, genuine-bearer Titus authorized-home contract test.

This script NEVER signs in, creates users, sets claims, impersonates another
Person or stores credentials. Run against an expressly approved clone/local
PostgREST endpoint after candidate source has been installed and signed tokens
for genuine test subjects have been obtained separately.

Required environment: TITUS_HOME_TEST_URL, TITUS_HOME_TEST_KEY,
TITUS_HOME_TEST_BEARER. Nothing sensitive is echoed.
"""
from __future__ import annotations
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

RPC = "/rest/v1/rpc/titus_authorized_home_self_api_v1"
FORBIDDEN = {"sourceText", "rawText", "accessToken", "email", "sourceBody"}
ALLOWED_ROLES = {"learner", "teacher", "author"}
ALLOWED_KINDS = {"titus_program", "institutional_course"}


def check(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def request(base: str, key: str, bearer: str | None) -> tuple[int, object]:
    headers = {"apikey": key, "Content-Type": "application/json"}
    if bearer:
        headers["Authorization"] = "Bearer " + bearer
    req = urllib.request.Request(
        base.rstrip("/") + RPC, data=b"{}", method="POST", headers=headers
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            body = response.read(300_000)
            return response.status, json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        # No private provider error bodies or bearer bytes in test output.
        return exc.code, None


def main() -> None:
    base = os.environ.get("TITUS_HOME_TEST_URL", "")
    key = os.environ.get("TITUS_HOME_TEST_KEY", "")
    bearer = os.environ.get("TITUS_HOME_TEST_BEARER", "")
    expected_empty = os.environ.get("TITUS_HOME_EXPECT_EMPTY", "true") == "true"

    url = urllib.parse.urlsplit(base)
    local = url.scheme == "http" and url.hostname in {"127.0.0.1", "localhost"}
    if not local:
        check(url.scheme == "https" and url.hostname == "zirqkouammpwxlqfbsvf.supabase.co",
              "Only configured project HTTPS or local isolated PostgREST is allowed")
        check(os.environ.get("TITUS_HOME_ALLOW_LIVE_READ") == "true",
              "Production read requires explicit TITUS_HOME_ALLOW_LIVE_READ=true")
    check(bool(key and bearer), "Signed test key and user bearer required")
    check(url.path in {"", "/"}, "Base URL must not contain an API path")

    anonymous_status, _ = request(base, key, None)
    check(anonymous_status in {401, 403},
          "Anonymous RPC request must be denied at function ACL")
    signed_status, data = request(base, key, bearer)
    check(signed_status == 200 and isinstance(data, dict),
          "Signed current-Person RPC did not return approved JSON")
    check(data.get("contractVersion") == "titus_authorized_home_self_v1",
          "Wrong contract version")
    check(data.get("state") in {"ready", "identity_not_ready"},
          "Unknown source status")
    subjects = data.get("subjects")
    invitations = data.get("pendingInvitations")
    check(isinstance(subjects, list) and len(subjects) <= 100,
          "Invalid source list")
    check(isinstance(invitations, list) and len(invitations) == 0,
          "V1 may not disclose invitations before a governed invitation source exists")
    if data.get("state") == "identity_not_ready":
        check(not subjects and not invitations, "Unresolved identity leaked private subjects")
    else:
        check(isinstance(data.get("personId"), str),
              "Missing canonical Person source identity")
        check(not expected_empty or not subjects,
              "Unestablished private education entitlement detected")

    seen = set()
    for subject in subjects:
        check(isinstance(subject, dict), "Invalid subject")
        check(not (FORBIDDEN & subject.keys()), "Private fields in home result")
        check(subject.get("kind") in ALLOWED_KINDS, "Unknown subject kind")
        check(isinstance(subject.get("title"), str), "Missing subject title")
        check(isinstance(subject.get("id"), str), "Missing exact subject ID")
        check(subject["id"] not in seen, "Duplicate subject")
        seen.add(subject["id"])
        roles = subject.get("roles")
        check(isinstance(roles, list) and roles and
              all(role in ALLOWED_ROLES for role in roles),
              "Invalid current authority role")

    print("PASS: anonymous denied; signed bearer contract/fields validated; "
          "subject count=" + str(len(subjects)) + "; "
          "state=" + data["state"])
    print("NOTE: signed wrong-Person, revoked-session and positive "
          "enrollment tests require separately approved independent fixtures")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Intentionally never print URL, JWT, Person IDs, source bodies or SQL.
        print("FAIL: " + str(exc), file=sys.stderr)
        sys.exit(1)

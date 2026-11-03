#!/usr/bin/env python3
"""Legacy one-Person Titus signed-read diagnostic: isolated clone ONLY.

This helper is deliberately weaker than signed_isolation_matrix.py. A pass
only proves one real bearer can read an exact, bounded self response; it does
NOT prove independent Persons, revocation, withdrawn enrollment or release.

It refuses live/project URLs, even when TITUS_HOME_ALLOW_LIVE_READ is set.
No users, grants, tokens or data are created or altered by this read-only test.
Environment: TITUS_HOME_TEST_URL, TITUS_HOME_TEST_KEY,
TITUS_HOME_TEST_BEARER, optional TITUS_HOME_EXPECT_EMPTY=true|false.
"""
from __future__ import annotations

import os
import sys
from collections.abc import Mapping

from signed_isolation_matrix import (
    MatrixFailure, checked_response, post_rpc, require_local_origin,
)


def read_single_environment(env: Mapping[str, str]) -> tuple[str, str, str, bool]:
    base = require_local_origin(env.get("TITUS_HOME_TEST_URL", ""))
    key = env.get("TITUS_HOME_TEST_KEY", "")
    bearer = env.get("TITUS_HOME_TEST_BEARER", "")
    expectation = env.get("TITUS_HOME_EXPECT_EMPTY", "true")
    if (not key or len(key) > 4096 or "\n" in key
            or key.startswith("sb_secret_")):
        raise MatrixFailure("A bounded publishable clone-only API key is required")
    if not bearer or len(bearer) > 8192 or "\n" in bearer or bearer == key:
        raise MatrixFailure("A distinct bounded signed current-User bearer is required")
    if expectation not in {"true", "false"}:
        raise MatrixFailure("Expected true or false for local entitlement fixture")
    return base, key, bearer, expectation == "true"


def validate_single(
    anonymous: tuple[int, object | None],
    signed: tuple[int, object | None],
    expected_empty: bool,
) -> int:
    if anonymous[0] not in {401, 403}:
        raise MatrixFailure("Anonymous request must actually be denied 401/403")
    state, ids = checked_response(*signed)
    if state != "ready":
        raise MatrixFailure("Signed Person has not resolved to a ready identity")
    if expected_empty and ids:
        raise MatrixFailure("An unapproved educational subject was disclosed")
    if not expected_empty and not ids:
        raise MatrixFailure("Positive enrollment fixture did not return its subject")
    return len(ids)


def run(env: Mapping[str, str]) -> None:
    base, key, bearer, expected_empty = read_single_environment(env)
    anonymous = post_rpc(base, key, None)
    signed = post_rpc(base, key, bearer)
    count = validate_single(anonymous, signed, expected_empty)
    print(f"PASS: isolated one-Person signed reader, bounded subjects={count}")
    print("NOT PROVED: independent signed Persons, source revocation, "
          "offer state, enrollment issuer, or production readiness")
    print("NEXT: signed_isolation_matrix.py on the same disposable clone")


if __name__ == "__main__":
    try:
        run(os.environ)
    except MatrixFailure as exc:
        print("FAIL: " + str(exc), file=sys.stderr)
        sys.exit(1)
    except Exception:
        # Do not echo provider error payloads, URLs, Person IDs or credentials.
        print("FAIL: unexpected internal diagnostic error", file=sys.stderr)
        sys.exit(1)

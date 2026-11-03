#!/usr/bin/env python3
"""Titus source-only, genuine signed bearer acceptance matrix.

Runs on an isolated localhost GoTrue/PostgREST production-schema clone ONLY.
Does not create users/tokens/fixtures, alter database rows or use service_role.
Missing scenarios FAIL the mandatory gate; never count HTTP 404 as a denial.
No access token, Person UUID, subject UUID, title or response body is logged.

The operators must independently establish actual fixture issuer/consent:
  TITUS_MATRIX_URL                         local HTTP origin (localhost only)
  TITUS_MATRIX_PUBLISHABLE_KEY
  TITUS_MATRIX_TARGET_COURSE_ID            issued in disposable clone
  TITUS_MATRIX_LEARNER_BEARER              enrolled / current Person
  TITUS_MATRIX_OTHER_PERSON_BEARER         active unrelated current Person
  TITUS_MATRIX_WRONG_CLIENT_BEARER         genuine foreign-client signed bearer
  TITUS_MATRIX_UNBOUND_BEARER              genuine unbound signed bearer
  TITUS_MATRIX_REVOKED_SESSION_BEARER      genuine revoked-session signed bearer
  TITUS_MATRIX_WITHDRAWN_BEARER            genuine withdrawn-enrollment Person
  TITUS_MATRIX_EXPIRED_BEARER              genuine expired-session bearer

One authorized institutional learner subject is enough to test these denials.
No teacher, author, or Titus-private-Program entitlement is inferred.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

RPC = "/rest/v1/rpc/titus_authorized_home_self_api_v1"
MAX_BYTES = 65536
VERSION = "titus_authorized_home_self_v1"
ALLOWED_TOP_READY = frozenset(
    ("contractVersion", "state", "personId", "subjects", "pendingInvitations")
)
ALLOWED_TOP_NOT_READY = frozenset(
    ("contractVersion", "state", "subjects", "pendingInvitations")
)
ALLOWED_SUBJECT = frozenset(("id", "kind", "title", "subtitle", "roles"))
SCENARIOS = (
    ("learner", "TITUS_MATRIX_LEARNER_BEARER"),
    ("other_person", "TITUS_MATRIX_OTHER_PERSON_BEARER"),
    ("wrong_client", "TITUS_MATRIX_WRONG_CLIENT_BEARER"),
    ("unbound", "TITUS_MATRIX_UNBOUND_BEARER"),
    ("revoked_session", "TITUS_MATRIX_REVOKED_SESSION_BEARER"),
    ("withdrawn", "TITUS_MATRIX_WITHDRAWN_BEARER"),
    ("expired", "TITUS_MATRIX_EXPIRED_BEARER"),
)


class MatrixFailure(Exception):
    """Conceals any token or source material in failure messages."""


def require_local_origin(base: str) -> str:
    value = urllib.parse.urlsplit(base)
    if (value.scheme != "http" or value.hostname not in {"127.0.0.1", "localhost"}
            or value.username is not None or value.password is not None
            or value.path not in {"", "/"} or value.query or value.fragment
            or value.port is None):
        raise MatrixFailure("Only explicit loopback HTTP with a port is allowed")
    return base.rstrip("/")


def read_environment(env: dict[str, str]) -> tuple[str, str, str, dict[str, str]]:
    base = require_local_origin(env.get("TITUS_MATRIX_URL", ""))
    key = env.get("TITUS_MATRIX_PUBLISHABLE_KEY", "")
    target = env.get("TITUS_MATRIX_TARGET_COURSE_ID", "")
    try:
        uuid.UUID(target)
    except (ValueError, AttributeError) as exc:
        raise MatrixFailure("Expected exact clone-only target course UUID") from exc
    if not key or len(key) > 4096 or "\n" in key:
        raise MatrixFailure("A bounded publishable test key is required")
    tokens = {}
    missing = []
    for name, variable in SCENARIOS:
        token = env.get(variable, "")
        if not token or len(token) > 8192 or "\n" in token:
            missing.append(name)
        else:
            tokens[name] = token
    if missing:
        raise MatrixFailure("INCOMPLETE: mandatory independently signed scenarios unavailable: "
                            + ", ".join(missing))
    if len(set(tokens.values())) != len(tokens):
        raise MatrixFailure("Fixture bearers must be distinct; identity cannot be simulated")
    if key in tokens.values():
        raise MatrixFailure("Publishable key is not an authenticated user bearer")
    return base, key, str(uuid.UUID(target)), tokens


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def post_rpc(base: str, key: str, bearer: str | None) -> tuple[int, object | None]:
    headers = {"apikey": key, "Content-Type": "application/json"}
    if bearer is not None:
        headers["Authorization"] = "Bearer " + bearer
    request = urllib.request.Request(base + RPC, data=b"{}", method="POST", headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=12) as response:
            body = response.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise MatrixFailure("Response exceeded field disclosure bound")
            try:
                return response.status, json.loads(body.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise MatrixFailure("Source response is not valid bounded JSON") from exc
    except urllib.error.HTTPError as exc:
        # HTTP error bodies may contain private sources and are never inspected/logged.
        exc.close()
        return exc.code, None
    except (urllib.error.URLError, TimeoutError) as exc:
        raise MatrixFailure("Isolated signed PostgREST endpoint unavailable") from exc


def checked_response(status: int, payload: object | None) -> tuple[str, frozenset[str]]:
    if status != 200 or not isinstance(payload, dict):
        raise MatrixFailure("Expected an authenticated self JSON response")
    if payload.get("contractVersion") != VERSION:
        raise MatrixFailure("Wrong authorized-home source contract")
    state = payload.get("state")
    if state == "identity_not_ready":
        if (set(payload) != ALLOWED_TOP_NOT_READY or payload.get("subjects") != []
                or payload.get("pendingInvitations") != []):
            raise MatrixFailure("Unavailable identity must not disclose a subject or Person")
        return state, frozenset()
    if state != "ready" or set(payload) != ALLOWED_TOP_READY:
        raise MatrixFailure("Source response shape or state not authorized")
    try:
        uuid.UUID(payload["personId"])
    except (KeyError, ValueError, AttributeError, TypeError) as exc:
        raise MatrixFailure("Ready state missing canonical Person identity") from exc
    subjects = payload.get("subjects")
    if not isinstance(subjects, list) or len(subjects) > 100:
        raise MatrixFailure("Unbounded or malformed subject collection")
    if payload.get("pendingInvitations") != []:
        raise MatrixFailure("Institutional-only slice may not disclose private invitations")
    ids: set[str] = set()
    for subject in subjects:
        if not isinstance(subject, dict) or set(subject) != ALLOWED_SUBJECT:
            raise MatrixFailure("Unreviewed private subject fields")
        if (subject["kind"] != "institutional_course" or subject["roles"] != ["learner"]
                or not isinstance(subject["title"], str) or not subject["title"].strip()
                or len(subject["title"]) > 180 or "\n" in subject["title"]
                or not isinstance(subject["subtitle"], str)
                or len(subject["subtitle"]) > 280 or "\n" in subject["subtitle"]):
            raise MatrixFailure("Unsupported subject title, kind, or permission")
        try:
            subject_id = str(uuid.UUID(subject["id"]))
        except (ValueError, TypeError, AttributeError) as exc:
            raise MatrixFailure("Subject ID is not canonical UUID") from exc
        if subject_id in ids:
            raise MatrixFailure("Duplicate subject collection entry")
        ids.add(subject_id)
    return state, frozenset(ids)


def validate_matrix(results: dict[str, tuple[int, object | None]], target: str) -> None:
    anon_status, _ = results["anonymous"]
    if anon_status not in {401, 403}:
        raise MatrixFailure("Anonymous request must yield actual 401/403, never 404")
    enrolled_state, enrolled_ids = checked_response(*results["learner"])
    if enrolled_state != "ready" or target not in enrolled_ids:
        raise MatrixFailure("Independently enrolled learner cannot see verified target")
    distinct_people = {str(uuid.UUID(results["learner"][1]["personId"]))}
    for scenario in ("other_person", "withdrawn"):
        state, ids = checked_response(*results[scenario])
        if state != "ready" or target in ids:
            raise MatrixFailure(scenario + ": target leaked or signed Person not resolved")
        person_id = str(uuid.UUID(results[scenario][1]["personId"]))
        if person_id in distinct_people:
            raise MatrixFailure("Independent signed Personas must resolve to distinct canonical Persons")
        distinct_people.add(person_id)
    for scenario in ("wrong_client", "unbound", "revoked_session", "expired"):
        status, body = results[scenario]
        if status in {401, 403}:
            continue
        if status == 404:
            raise MatrixFailure(scenario + ": 404 is not a proven permission denial")
        state, ids = checked_response(status, body)
        if state != "identity_not_ready" or ids:
            raise MatrixFailure(scenario + ": client/session/Person denial failed")


def run() -> None:
    base, key, target, bearers = read_environment(dict(os.environ))
    results = {"anonymous": post_rpc(base, key, None)}
    for scenario, bearer in bearers.items():
        results[scenario] = post_rpc(base, key, bearer)
    validate_matrix(results, target)
    print("PASS: local signed Titus institutional learner target + unrelated/withdrawn "
          "and wrong-client/unbound/revoked/expired denial matrix")
    print("LIMIT: no teacher/author/private Program, source-disclosure or production approval")


if __name__ == "__main__":
    try:
        run()
    except Exception as exc:
        # Never print raw exception repr: URL/HTTP layers may include credentials.
        if isinstance(exc, MatrixFailure):
            print("FAIL: " + str(exc), file=sys.stderr)
        else:
            print("FAIL: unexpected internal test failure (no private details)", file=sys.stderr)
        sys.exit(1)

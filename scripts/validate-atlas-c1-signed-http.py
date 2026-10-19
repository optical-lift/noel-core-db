#!/usr/bin/env python3
"""Local-only signed GoTrue -> PostgREST -> Atlas C1 authorization probe.

Requires the existing disposable production-schema clone with C1 fixture and
migration already applied, and a running local Supabase Auth/REST stack.
Never contacts production, sends email, or creates a paid seat.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


OWNER = "e5200000-0000-4000-8000-000000000001"
WORKER = "e5200000-0000-4000-8000-000000000002"
OUTSIDER = "e5200000-0000-4000-8000-000000000003"
NO_SEAT = "e5200000-0000-4000-8000-000000000004"
ORG = "e5200000-0000-4000-8000-000000000801"
LEDGER_A = "e5200000-0000-4000-8000-000000000401"
LEDGER_B = "e5200000-0000-4000-8000-000000000402"
UNIT = "e5200000-0000-4000-8000-000000000802"
ROOT_AUTHORITY = "e5200000-0000-4000-8000-000000000601"
ROOT_SEAT = "e5200000-0000-4000-8000-000000000501"
PASSWORD = "C1-local-synthetic-not-for-production-2026!"


def sql(db_url, statement):
    result = subprocess.run(
        ["psql", db_url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", statement],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def local_status():
    result = subprocess.run(
        ["supabase", "status", "-o", "env"],
        capture_output=True, text=True, check=True,
    )
    values = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"')
    api = values.get("API_URL")
    key = values.get("ANON_KEY") or values.get("SUPABASE_ANON_KEY")
    check(bool(api and key), "Local API URL and anon key must be supplied by Supabase CLI")
    parsed = urllib.parse.urlparse(api)
    check(parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost"),
          "Signed HTTP probe must never contact a remote API")
    return api.rstrip("/"), key


def request(api, key, path, body, token=None):
    data = json.dumps(body).encode("utf-8")
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(api + path, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            detail = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            detail = {"message": "non-JSON HTTP error"}
        return exc.code, detail


def jwt_payload(token):
    middle = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(middle + "=" * (-len(middle) % 4)))


def sign_in(api, key, name):
    status, data = request(
        api, key, "/auth/v1/token?grant_type=password",
        {"email": f"atlas-c1-{name}@example.invalid", "password": PASSWORD},
    )
    check(status == 200 and isinstance(data, dict) and data.get("access_token"),
          f"Local GoTrue password sign-in failed for {name}: HTTP {status}, {data}")
    token = data["access_token"]
    claims = jwt_payload(token)
    check(claims.get("role") == "authenticated" and claims.get("session_id"),
          f"GoTrue did not mint a signed authenticated session for {name}")
    return token, claims


def rpc(api, key, name, params, token=None):
    return request(api, key, "/rest/v1/rpc/" + name, params, token)


def allowed(api, key, function, params, token):
    status, payload = rpc(api, key, function, params, token)
    check(status == 200 and isinstance(payload, dict),
          f"Owner positive {function} failed: HTTP {status}, {payload}")
    return payload


def denied(api, key, function, params, token, label):
    status, payload = rpc(api, key, function, params, token)
    check(status in (401, 403) and isinstance(payload, dict),
          f"{label}: denied RPC returned unexpected HTTP {status}: {payload}")
    # All signed, role-authenticated denials must come from the SQL owner
    # guard (42501), not missing/hidden RPC endpoints or malformed inputs.
    if token is not None:
        check(payload.get("code") == "42501",
              f"{label}: expected permission denial 42501, got {payload}")
    print(f"PASS {label}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(re.match(r"^postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres$", args.db_url),
          "Database URI must name disposable local Postgres only")
    api, key = local_status()
    work = Path(args.output)
    work.parent.mkdir(parents=True, exist_ok=True)

    check(sql(args.db_url, f"select count(*) from auth.users where id in ('{OWNER}','{WORKER}','{OUTSIDER}','{NO_SEAT}')") == "4",
          "Required four synthetic C1 identities are absent")
    # These are local fixture identities, not real mailboxes. The password
    # hash is calculated in disposable Postgres and never committed to Git.
    for name, person in (("owner", OWNER), ("worker", WORKER),
                         ("outsider", OUTSIDER), ("no-seat", NO_SEAT)):
        metadata = '{"is_owner":true,"role":"root_governing"}' if name == "worker" else "{}"
        sql(args.db_url, f"""
            update auth.users
            set instance_id='00000000-0000-0000-0000-000000000000'::uuid,
                email='atlas-c1-{name}@example.invalid',
                encrypted_password=extensions.crypt('{PASSWORD}',extensions.gen_salt('bf')),
                email_confirmed_at=now(),
                raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
                raw_user_meta_data='{metadata}'::jsonb
            where id='{person}'::uuid
        """)
    # Ensure PostgREST sees the newly applied public RPCs.
    sql(args.db_url, "notify pgrst, 'reload schema'")
    identities = {name: sign_in(api, key, name)
                  for name in ("owner", "worker", "outsider", "no-seat")}
    for name, expected in (("owner", OWNER), ("worker", WORKER),
                           ("outsider", OUTSIDER), ("no-seat", NO_SEAT)):
        claims = identities[name][1]
        check(claims.get("sub") == expected, f"GoTrue {name} token bound to wrong Person")
        check(sql(args.db_url, f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{expected}'::uuid") == "1",
              f"GoTrue {name} session was not persisted in auth.sessions")
    check(identities["worker"][1].get("user_metadata", {}).get("is_owner") is True,
          "Spoofed user_metadata not present in genuine worker JWT")
    print("PASS four cryptographically signed GoTrue sessions (including forged worker metadata)")

    read = {"p_organization_id": ORG, "p_ledger_id": LEDGER_A, "p_limit": 100}
    token = identities["owner"][0]
    view = allowed(api, key, "operating_requirements_owner_self_api_v1", read, token)
    check(view.get("contractVersion") == "operating_requirements_owner_v1",
          "Owner read returned incorrect contract")
    print("PASS signed owner read")
    doc = {"requiredOutcome": "Animals safely fed and watered",
           "instructions": "Record the actual state",
           "prerequisites": [], "resources": [], "reporting": {}, "escalation": {}}
    receipt = allowed(api, key, "establish_operating_requirement_owner_self_api_v1",
        {"p_organization_id": ORG, "p_ledger_id": LEDGER_A,
         "p_organization_unit_id": UNIT, "p_stable_key": "signed_http_c1",
         "p_summary": "Signed local HTTP proof", "p_document": doc,
         "p_reason": "Clone-local signed owner test"}, token)
    check(receipt.get("ok") is True and receipt.get("instancesGenerated") == 0
          and receipt.get("workItemIds") == [] and receipt.get("allocationChanged") is False,
          "Signed owner establishment unexpectedly materialized Work")
    entry_id = receipt.get("entryId")
    check(isinstance(entry_id, str), "Signed owner missing entry receipt")
    revised = allowed(api, key, "revise_operating_requirement_owner_self_api_v1",
        {"p_entry_id": entry_id, "p_ledger_id": LEDGER_A, "p_document": doc,
         "p_policy_state": "paused", "p_accountable_position_id": None,
         "p_recurrence_rule_id": None, "p_expected_revision": 1,
         "p_reason": "Clone-local signed revision"}, token)
    check(revised.get("revision") == 2 and revised.get("instancesGenerated") == 0,
          "Signed owner revision unexpectedly changed Work")
    check(sql(args.db_url, f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid") == "0"
          and sql(args.db_url, f"select count(*) from atlas.work_allocations where organization_id='{ORG}'::uuid") == "0",
          "Signed owner request created Work or allocations")
    print("PASS signed owner establish/revise without Work generation")

    worker = identities["worker"][0]
    denied(api, key, "operating_requirements_owner_self_api_v1", read, worker, "worker owner-read denied")
    denied(api, key, "establish_operating_requirement_owner_self_api_v1",
        {"p_organization_id": ORG, "p_ledger_id": LEDGER_A,
         "p_organization_unit_id": UNIT, "p_stable_key": "unauthorized_http",
         "p_summary": "Unauthorized request", "p_document": doc,
         "p_reason": "Spoofed worker attempt"}, worker, "worker owner-write denied")
    denied(api, key, "revise_operating_requirement_owner_self_api_v1",
        {"p_entry_id": entry_id, "p_ledger_id": LEDGER_A, "p_document": doc,
         "p_policy_state": "active", "p_accountable_position_id": None,
         "p_recurrence_rule_id": None, "p_expected_revision": 2,
         "p_reason": "Spoofed worker revision"}, worker, "worker owner-revision denied")
    denied(api, key, "operating_requirements_owner_self_api_v1", read,
           identities["outsider"][0], "other-Ledger member denied")
    denied(api, key, "operating_requirements_owner_self_api_v1",
           {"p_organization_id": ORG, "p_ledger_id": LEDGER_B, "p_limit": 100},
           identities["outsider"][0], "unrelated native Ledger denied")
    denied(api, key, "operating_requirements_owner_self_api_v1", read,
           identities["no-seat"][0], "no-seat signed Person denied")
    denied(api, key, "operating_requirements_owner_self_api_v1", read,
           None, "anonymous denied")

    # These mutations only affect the disposable local clone and are never
    # replayed to production. Active signed owner token must lose access.
    sql(args.db_url, f"update atlas.principal_ledger_authorities set status='ended',ended_at=now() where id='{ROOT_AUTHORITY}'::uuid")
    denied(api, key, "operating_requirements_owner_self_api_v1", read, token,
           "revoked root authority denied with live signed JWT")
    sql(args.db_url, f"update atlas.principal_ledger_authorities set status='active',ended_at=null where id='{ROOT_AUTHORITY}'::uuid")
    sql(args.db_url, f"update ledger.seats set seat_state='ended',ended_at=now() where id='{ROOT_SEAT}'::uuid")
    denied(api, key, "operating_requirements_owner_self_api_v1", read, token,
           "revoked native seat denied with live signed JWT")
    sql(args.db_url, f"update ledger.seats set seat_state='active',ended_at=null where id='{ROOT_SEAT}'::uuid")
    owner_session = identities["owner"][1]["session_id"]
    sql(args.db_url, f"delete from auth.sessions where id='{owner_session}'::uuid")
    denied(api, key, "operating_requirements_owner_self_api_v1", read, token,
           "invalidated GoTrue session denied despite signed JWT")
    work.write_text("PASS all signed HTTP authorization cases\n", encoding="utf-8")
    print("PASS all signed HTTP authorization cases")


if __name__ == "__main__":
    main()

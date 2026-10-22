#!/usr/bin/env python3
"""Signed local GoTrue + PostgREST proof of Atlas Ledger occurrence date evidence.

Only uses disposable synthetic identities in a local production-schema clone.
Never reads actual communications, sends email, or contacts a remote host.
"""

import argparse
import base64
import json
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

LEDGER = "f5210000-0000-4000-8000-000000000014"
MEMBER = "f5210000-0000-4000-8000-000000000401"
OUTSIDER = "f5210000-0000-4000-8000-000000000402"
MEMBER_PERSON = "f5210000-0000-4000-8000-000000000002"
OUTSIDER_PERSON = "f5210000-0000-4000-8000-000000000003"
CANONICAL_A = "f5210000-0000-4000-8000-000000000101"
CANONICAL_B = "f5210000-0000-4000-8000-000000000102"
CANONICAL_C = "f5210000-0000-4000-8000-000000000103"
PASSWORD = "Atlas-date-evidence-disposable-local-proof-2026!"

def require(condition, reason):
    if not condition:
        raise AssertionError(reason)

def sql(db_url, query):
    result = subprocess.run(
        ["psql", db_url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", query],
        check=True, text=True, capture_output=True
    )
    return result.stdout.strip()

def local_endpoint():
    result = subprocess.run(
        ["supabase", "status", "-o", "env"], capture_output=True, text=True, check=True
    )
    env = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"')
    api = env.get("API_URL", "")
    key = env.get("ANON_KEY") or env.get("SUPABASE_ANON_KEY")
    parsed = urllib.parse.urlparse(api)
    require(parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost")
            and bool(key), "Refuse nonlocal or missing Supabase REST endpoint")
    return api.rstrip("/"), key

def request(api, key, url, body, token=None):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    action = urllib.request.Request(
        api + url, json.dumps(body).encode(), headers, method="POST"
    )
    try:
        with urllib.request.urlopen(action, timeout=25) as result:
            return result.status, json.loads(result.read().decode())
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode()
        try:
            obj = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            obj = {"message": "Non-JSON HTTP denial"}
        return exc.code, obj

def token_payload(token):
    middle = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(middle + "=" * (-len(middle) % 4)))

def signed_session(api, key, address):
    code, obj = request(
        api, key, "/auth/v1/token?grant_type=password",
        {"email": address, "password": PASSWORD}
    )
    require(code == 200 and isinstance(obj, dict) and obj.get("access_token"),
            f"Local synthetic GoTrue session failed: HTTP {code}")
    token = obj["access_token"]
    claims = token_payload(token)
    require(claims.get("role") == "authenticated" and claims.get("session_id"),
            "No cryptographically signed session claims")
    return token, claims

def rpc(api, key, token, ledger=LEDGER):
    return request(api, key, "/rest/v1/rpc/ledger_occurrence_date_evidence_self_api_v1", {
        "p_ledger_id": ledger, "p_start_date": "2030-10-30",
        "p_end_date": "2030-10-30", "p_timezone_name": "America/Chicago", "p_limit": 50
    }, token)

def denied(api, key, token, label):
    code, obj = rpc(api, key, token)
    require(code in (401, 403) and isinstance(obj, dict),
            f"{label}: permission failure did not deny; HTTP {code}")
    if token is not None:
        require(obj.get("code") == "42501",
                f"{label}: denial must come from source-bound SQL guard, not missing RPC")
    print("PASS", label)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    require(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url
    ), "Refuse any nonlocal database URI")

    api, anon_key = local_endpoint()
    for uid, suffix in ((MEMBER, "member"), (OUTSIDER, "outsider")):
        require(sql(args.db_url, f"SELECT count(*) FROM auth.users WHERE id='{uid}'::uuid") == "1",
                "Missing disposable fixture Auth user")
        address = f"atlas-date-{suffix}@example.invalid"
        spoofed = '{"is_owner":true,"role":"root_governing"}' if suffix == "outsider" else "{}"
        sql(args.db_url, f"""
          UPDATE auth.users SET
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{address}',
            encrypted_password=extensions.crypt('{PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),
            confirmation_token='', recovery_token='', email_change='',
            email_change_token_new='', email_change_token_current='',
            phone_change='', phone_change_token='', reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{spoofed}'::jsonb
          WHERE id='{uid}'::uuid
        """)
        sql(args.db_url, f"""
          INSERT INTO auth.identities
            (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES
            (gen_random_uuid(),'{address}','{uid}'::uuid,
             jsonb_build_object('sub','{uid}','email','{address}'),
             'email',now(),now())
        """)
    sql(args.db_url, "notify pgrst, 'reload schema'")

    member, member_claims = signed_session(
        api, anon_key, "atlas-date-member@example.invalid"
    )
    outsider, outsider_claims = signed_session(
        api, anon_key, "atlas-date-outsider@example.invalid"
    )
    for name, claims, uid in (
        ("member", member_claims, MEMBER),
        ("outsider", outsider_claims, OUTSIDER)
    ):
        require(claims.get("sub") == uid, name + " signed token wrong principal")
        require(sql(args.db_url, f"""
          SELECT count(*) FROM auth.sessions
          WHERE id='{claims['session_id']}'::uuid AND user_id='{uid}'::uuid
        """) == "1", name + " session missing in disposable Auth database")
    require(outsider_claims.get("user_metadata", {}).get("is_owner") is True,
            "Adversarial editable metadata was not included")
    print("PASS signed GoTrue sessions, including forged outsider user_metadata")

    code, response = rpc(api, anon_key, member)
    require(code == 200 and isinstance(response, dict),
            f"Signed Ledger member should read evidence: HTTP {code}, {response}")
    require(response.get("contractVersion") == "ledger_occurrence_date_evidence_v1",
            "Wrong source evidence contract")
    claims = response.get("occurrences")
    require(isinstance(claims, list) and len(claims) == 3,
            "Exact date window should return three distinct synthetic Occurrences")
    ids = [item.get("sourceRef", {}).get("id") for item in claims]
    require(set(ids) == {CANONICAL_A, CANONICAL_B, CANONICAL_C} and len(set(ids)) == 3,
            "Source identity collapse or missing source-local date admission")
    require("Synthetic Restricted Owner Planning" not in json.dumps(response),
            "Owner-only assertion leaked to native Ledger participant")
    differences = {item["sourceRef"]["id"]: item for item in claims}
    a = differences[CANONICAL_A]
    require(a["communityEventAssertions"][0]["differenceCandidates"]["startLocalTime"] is True,
            "First Event's time disagreement lost")
    require(response.get("coverage", {}).get("wholeTemporalFieldComplete") is False,
            "Partial evidence was misrepresented as entire date")
    print("PASS signed member read, distinct same-date identity, source conflict and privacy")

    denied(api, anon_key, outsider, "signed outsider with forged owner metadata denied")
    denied(api, anon_key, None, "anonymous user denied")

    sql(args.db_url, f"""
      UPDATE ledger.seats
      SET seat_state='ended',ended_at=now()
      WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{MEMBER_PERSON}'::uuid
        AND seat_state='active' AND ended_at IS NULL
    """)
    denied(api, anon_key, member, "revoked Ledger seat denies existing signed session")
    sql(args.db_url, f"""
      UPDATE ledger.seats
      SET seat_state='active',ended_at=NULL
      WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{MEMBER_PERSON}'::uuid
        AND seat_state='ended'
    """)
    sql(args.db_url, f"""
      DELETE FROM auth.sessions WHERE id='{member_claims['session_id']}'::uuid
    """)
    denied(api, anon_key, member, "invalidated Auth session denies still-signed token")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        "PASS exact signed date evidence HTTP authorization and denial matrix\n",
        encoding="utf-8"
    )
    print("PASS all signed local HTTP date evidence cases")

if __name__ == "__main__":
    main()

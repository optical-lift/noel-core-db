#!/usr/bin/env python3
"""Signed local GoTrue + PostgREST proof of source-scoped Atlas schedule correction preflight.

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
ROOT = "f5210000-0000-4000-8000-000000000403"
OUTSIDER = "f5210000-0000-4000-8000-000000000402"
MEMBER_PERSON = "f5210000-0000-4000-8000-000000000002"
ROOT_PERSON = "f5210000-0000-4000-8000-000000000004"
ORG = "f5210000-0000-4000-8000-000000000010"
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

def rpc(api, key, token, ledger=LEDGER, occurrence=CANONICAL_A, proposed=False):
    body = {
        "p_organization_id": ORG, "p_ledger_id": ledger,
        "p_occurrence_id": occurrence
    }
    if proposed:
        body["p_proposed_starts_at"] = "2030-10-30T21:00:00Z"
        body["p_proposed_ends_at"] = "2030-10-31T01:00:00Z"
    return request(
        api,key,"/rest/v1/rpc/ledger_occurrence_schedule_correction_preflight_self_api_v1",
        body,token
    )

def denied(api, key, token, label):
    code, obj = rpc(api,key,token)
    require(code in (401,403) and isinstance(obj,dict),
            f"{label}: expected authorization denial, HTTP {code}")
    if token is not None:
        require(obj.get("code")=="42501",
                f"{label}: deny in exact source/Person guard, not unavailable RPC")
    print("PASS",label)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    require(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url
    ),"Refuse nonlocal database")
    api,key=local_endpoint()
    for uid,suffix in ((MEMBER,"member"),(OUTSIDER,"outsider"),(ROOT,"root")):
        require(sql(args.db_url,
          f"SELECT count(*) FROM auth.users WHERE id='{uid}'::uuid")=="1",
          f"Missing disposable Auth fixture: {suffix}")
        address=f"atlas-schedule-{suffix}@example.invalid"
        spoofed='{"is_owner":true,"role":"root_governing"}' if suffix=="outsider" else "{}"
        sql(args.db_url,f"""
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
        sql(args.db_url,f"""
          INSERT INTO auth.identities
            (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES
            (gen_random_uuid(),'{address}','{uid}'::uuid,
             jsonb_build_object('sub','{uid}','email','{address}'),
             'email',now(),now())
        """)
    sql(args.db_url,"notify pgrst, 'reload schema'")
    tokens={}
    for suffix,uid in (("member",MEMBER),("outsider",OUTSIDER),("root",ROOT)):
        token,claims=signed_session(api,key,f"atlas-schedule-{suffix}@example.invalid")
        require(claims.get("sub")==uid, f"{suffix} signed identity mismatch")
        require(sql(args.db_url,f"""
          SELECT count(*) FROM auth.sessions
          WHERE id='{claims['session_id']}'::uuid AND user_id='{uid}'::uuid
        """)=="1",f"{suffix} has no valid server-side Auth session")
        tokens[suffix]=(token,claims)
    require(tokens["outsider"][1].get("user_metadata",{}).get("is_owner") is True,
            "Forged editable owner claims missing")
    print("PASS 3 genuine disposable signed sessions")

    code,ordinary=rpc(api,key,tokens["member"][0])
    require(code==200 and isinstance(ordinary,dict),
            f"Ordinary Ledger participant could not preview: HTTP {code}, {ordinary}")
    require(ordinary.get("contractVersion")=="ledger_occurrence_schedule_preflight_v1",
            "Wrong source preflight contract")
    require(ordinary.get("scope",{}).get("occurrenceId")==CANONICAL_A,
            "Wrong canonical Event or leaked another Event")
    require(ordinary["sourceComparisons"]["startLocalTime"] is True,
            "Source time conflict hidden")
    require(ordinary["dependentSourceImpact"]["evaluation"]=="not_authorized"
            and ordinary["dependentSourceImpact"]["activeResourceClaimCount"] is None,
            "Ordinary participant learned resource count")
    require(ordinary.get("approvedToCommit") is False,
            "A read-only preflight falsely granted source-write authority")
    require("Synthetic Restricted Owner Planning" not in json.dumps(ordinary),
            "Owner-only Event assertion leaked")
    print("PASS connected ordinary Person sees difference, not private dependency counts")

    code,governor=rpc(api,key,tokens["root"][0],proposed=True)
    require(code==200 and isinstance(governor,dict),
            f"Root Person cannot read scoped resource impact: HTTP {code}, {governor}")
    require(governor.get("rootGoverningCandidate") is True
            and governor["dependentSourceImpact"]["activeResourceClaimCount"]==1,
            "Root did not receive one real confirmed claim")
    require(governor["dependentSourceImpact"]["nonCancelledBookingCount"]==0
            and governor["proposedInterval"]["changesCanonicalInterval"] is True,
            "Root dependent source or alternate proposal mismatch")
    require(governor.get("approvedToCommit") is False,
            "Root Ledger authority is not global schedule write permission")
    require("source_owned_schedule_writer_not_released" in governor["commitBlockedReasons"],
            "Unreleased writer was silently treated as available")
    require("Synthetic Restricted Owner Planning" not in json.dumps(governor),
            "Root Ledger relation was wrongly treated as private Organization authority")
    print("PASS signed root sees claim count but cannot write or read private Event")

    code,other=rpc(api,key,tokens["member"][0],occurrence=CANONICAL_B)
    require(code==200 and other.get("scope",{}).get("occurrenceId")==CANONICAL_B,
            "Two independent same-day Events were conflated")
    require(other["sourceComparisons"]["startLocalTime"] is False,
            "Independent Event falsely reported a conflict")
    print("PASS two separate canonical Occurrences on one civil date")

    denied(api,key,tokens["outsider"][0],"Outsider with forged owner metadata")
    denied(api,key,None,"Anonymous client")

    root_token,root_claims=tokens["root"]
    sql(args.db_url,f"""
      UPDATE ledger.seats SET seat_state='ended',ended_at=now()
      WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{ROOT_PERSON}'::uuid
        AND seat_state='active' AND ended_at IS NULL
    """)
    denied(api,key,root_token,"Revoked Ledger connection")
    sql(args.db_url,f"""
      DELETE FROM auth.sessions WHERE id='{root_claims['session_id']}'::uuid
    """)
    denied(api,key,root_token,"Revoked Auth session")
    out=Path(args.output)
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(
      "PASS signed Atlas schedule-preflight native member/root/outsider/revocation matrix\n",
      encoding="utf-8")
    print("PASS all signed local Atlas schedule preflight cases")

if __name__=="__main__":
    main()

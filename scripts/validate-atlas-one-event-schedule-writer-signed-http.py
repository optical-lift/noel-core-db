#!/usr/bin/env python3
"""Signed local GoTrue + PostgREST proof of single-authority canonical Atlas Event schedule correction writer.

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

def write_with_versions(api,key,token,canonical_version,operational_version,
                        action="signed-root-event-correction",
                        start="2030-10-30T21:00:00Z"):
    return request(api,key,
      "/rest/v1/rpc/set_ledger_occurrence_schedule_self_api_v1",{
        "p_organization_id":ORG,
        "p_ledger_id":LEDGER,
        "p_occurrence_id":CANONICAL_A,
        "p_proposed_starts_at":start,
        "p_proposed_ends_at":"2030-10-31T01:00:00Z",
        "p_expected_canonical_updated_at":canonical_version,
        "p_expected_operational_updated_at":operational_version,
        "p_decision_reason":"Verified real Event public schedule is 4 PM through 8 PM.",
        "p_source_action_id":action
      },token)

def denied(code,obj,label):
    require(code in (401,403) and isinstance(obj,dict)
        and obj.get("code")=="42501",
        f"{label}: missing source-level denial (HTTP {code})")
    print("PASS",label)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    require(re.fullmatch(
       r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url
    ),"Refuse any nonlocal database URI")
    api,key=local_endpoint()
    for uid,suffix in ((MEMBER,"member"),(OUTSIDER,"outsider"),(ROOT,"root")):
        require(sql(args.db_url,
            f"SELECT count(*) FROM auth.users WHERE id='{uid}'::uuid")=="1",
            f"Missing synthetic Auth fixture {suffix}")
        email=f"atlas-write-{suffix}@example.invalid"
        spoofed='{"is_owner":true,"role":"root_governing"}' if suffix=="outsider" else "{}"
        sql(args.db_url,f"""
          UPDATE auth.users SET
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{email}',
            encrypted_password=extensions.crypt('{PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),confirmation_token='',recovery_token='',
            email_change='',email_change_token_new='',
            email_change_token_current='',phone_change='',phone_change_token='',
            reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{spoofed}'::jsonb
          WHERE id='{uid}'::uuid
        """)
        sql(args.db_url,f"""
          INSERT INTO auth.identities(id,provider_id,user_id,identity_data,
              provider,created_at,updated_at)
          VALUES(gen_random_uuid(),'{email}','{uid}'::uuid,
              jsonb_build_object('sub','{uid}','email','{email}'),
              'email',now(),now())
        """)
    sql(args.db_url,"notify pgrst, 'reload schema'")
    tokens={}
    for suffix,uid in (("member",MEMBER),("outsider",OUTSIDER),("root",ROOT)):
        token,claims=signed_session(api,key,f"atlas-write-{suffix}@example.invalid")
        require(claims.get("sub")==uid and claims.get("session_id"),
                f"{suffix} signed session identity mismatch")
        require(sql(args.db_url,f"""
            SELECT count(*) FROM auth.sessions
            WHERE id='{claims['session_id']}'::uuid AND user_id='{uid}'::uuid
        """)=="1",f"{suffix} valid Auth session missing")
        tokens[suffix]=(token,claims)
    require(tokens["outsider"][1].get("user_metadata",{}).get("is_owner") is True,
            "Forged editable metadata missing")
    print("PASS actual signed member, outsider and root sessions")

    canonical_version=sql(args.db_url,
      f"SELECT updated_at::text FROM local_intel.occurrences WHERE id='{CANONICAL_A}'::uuid")
    overlay_version=sql(args.db_url,
      "SELECT updated_at::text FROM atlas.community_events "
      "WHERE id='f5210000-0000-4000-8000-000000000301'::uuid")
    code,obj=write_with_versions(api,key,tokens["member"][0],
             canonical_version,overlay_version,action="signed-member-must-deny")
    denied(code,obj,"ordinary Ledger Person cannot rewrite source schedule")
    code,obj=write_with_versions(api,key,tokens["outsider"][0],
             canonical_version,overlay_version,action="signed-outsider-must-deny")
    denied(code,obj,"outsider with forged owner metadata cannot rewrite Event")
    # Anonymous gets PostgREST permission denial, possibly 401 before source.
    code,obj=write_with_versions(api,key,None,
             canonical_version,overlay_version,action="signed-anon-must-deny")
    require(code in (401,403),"Anonymous should not reach source writer")
    print("PASS anonymous caller refused")

    code,result=write_with_versions(api,key,tokens["root"][0],
             canonical_version,overlay_version)
    require(code==200 and isinstance(result,dict) and result.get("ok") is True,
            f"Signed root must correct one Event (HTTP {code}, {result})")
    require(result.get("contractVersion")=="ledger_occurrence_schedule_write_v1"
         and result.get("idempotentReplay") is False
         and result.get("occurrenceId")==CANONICAL_A
         and result.get("resourceClaimsUntouched") is True,
         "Root write did not confirm canonical identity and preserved resources")
    require(sql(args.db_url,f"""
      SELECT count(*) FROM local_intel.occurrences
      WHERE id='{CANONICAL_A}'::uuid AND
        start_at='2030-10-30 21:00+00'::timestamptz
        AND metadata->>'keepMe'='original'
        AND metadata->>'publicEventLocalTime'='4:00 PM–8:00 PM'
    """)=="1","Canonical source data / rich metadata lost")
    require(sql(args.db_url,f"""
      SELECT count(*) FROM ledger.occurrence_resource_claims
      WHERE occurrence_id='{CANONICAL_A}'::uuid
        AND claim_state='confirmed'
        AND starts_at='2030-10-30 21:00+00'::timestamptz
        AND ends_at='2030-10-31 01:00+00'::timestamptz
    """)=="1","Site claim modified or lost")
    print("PASS signed root canonical correction and unchanged resource hold")

    code,replay=write_with_versions(api,key,tokens["root"][0],
             canonical_version,overlay_version)
    require(code==200 and replay.get("idempotentReplay") is True
            and replay.get("receiptId")==result.get("receiptId"),
            "Replay must return same decision, not create a second Event")
    code,stale=write_with_versions(api,key,tokens["root"][0],
             canonical_version,overlay_version,
             action="signed-root-stale-new-action",start="2030-10-30T22:00:00Z")
    require(code >= 400 and stale.get("code")=="40001",
            f"Stale independent source version not rejected: HTTP {code}, {stale}")
    print("PASS replay and stale writer race denial")

    root_token,root_claims=tokens["root"]
    sql(args.db_url,f"""
      UPDATE ledger.seats SET seat_state='ended',ended_at=now()
      WHERE ledger_id='{LEDGER}'::uuid
        AND person_entity_id='{ROOT_PERSON}'::uuid
        AND seat_state='active' AND ended_at IS NULL
    """)
    code,obj=write_with_versions(api,key,root_token,
           canonical_version,overlay_version,action="signed-root-revoked-seat")
    denied(code,obj,"revoked Ledger seat denies formerly signed root")
    sql(args.db_url,f"""
      UPDATE ledger.seats SET seat_state='active',ended_at=NULL
      WHERE ledger_id='{LEDGER}'::uuid AND
       person_entity_id='{ROOT_PERSON}'::uuid AND seat_state='ended'
    """)
    sql(args.db_url,f"""
      DELETE FROM auth.sessions WHERE id='{root_claims['session_id']}'::uuid
    """)
    code,obj=write_with_versions(api,key,root_token,
           canonical_version,overlay_version,action="signed-root-revoked-session")
    denied(code,obj,"revoked Auth session denies root token")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
        "PASS one canonical schedule writer genuine signed session and denial matrix\n",
        encoding="utf-8")
    print("PASS signed local canonical Event write acceptance")

if __name__=="__main__":
    main()

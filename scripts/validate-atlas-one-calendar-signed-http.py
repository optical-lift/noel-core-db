#!/usr/bin/env python3
"""Protected disposable-clone proof of ONE Calendar source read authority.

Three real, locally issued GoTrue access tokens via local PostgREST.
No production connection, real user, external email, or source data mutation.
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
ORG = "f5210000-0000-4000-8000-000000000010"
CONTEXT = "f5210000-0000-4000-8000-000000000050"
EVENT = "f5210000-0000-4000-8000-000000000101"
OTHER_EVENT = "f5210000-0000-4000-8000-000000000102"
ROOT = "f5210000-0000-4000-8000-000000000403"
MEMBER = "f5210000-0000-4000-8000-000000000401"
OUTSIDER = "f5210000-0000-4000-8000-000000000402"
ROOT_PERSON = "f5210000-0000-4000-8000-000000000004"
PASSWORD = "Atlas-disposable-one-calendar-source-proof-2026!"

def check(condition, message):
    if not condition:
        raise AssertionError(message)

def sql(url, query):
    result = subprocess.run(
        ["psql",url,"-X","-A","-t","-v","ON_ERROR_STOP=1","-c",query],
        check=True, capture_output=True, text=True
    )
    return result.stdout.strip()

def endpoint():
    result = subprocess.run(["supabase","status","-o","env"],
                            check=True,capture_output=True,text=True)
    env = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            k,v = line.split("=",1)
            env[k.strip()] = v.strip().strip('"')
    url = env.get("API_URL","")
    key = env.get("ANON_KEY") or env.get("SUPABASE_ANON_KEY")
    parsed = urllib.parse.urlparse(url)
    check(parsed.scheme == "http" and parsed.hostname in ("localhost","127.0.0.1")
          and bool(key),"Refuse missing or nonlocal Supabase API")
    return url.rstrip("/"),key

def post(api,key,path,body,token=None):
    headers={"apikey":key,"Content-Type":"application/json"}
    if token:
        headers["Authorization"]="Bearer "+token
    req=urllib.request.Request(api+path,json.dumps(body).encode(),
                               headers,method="POST")
    try:
        with urllib.request.urlopen(req,timeout=25) as resp:
            return resp.status,json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            data=json.loads(e.read().decode())
        except (UnicodeDecodeError,ValueError):
            data={"message":"Non-JSON HTTP rejection"}
        return e.code,data

def token_claims(token):
    payload=token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload+"="*(-len(payload)%4)))

def read_ledger(api,key,token=None,ledger=LEDGER):
    return post(api,key,"/rest/v1/rpc/ledger_temporal_composer_self_api_v1",{
      "p_ledger_id":ledger,
      "p_start_date":"2030-10-01","p_end_date":"2030-10-31",
      "p_timezone_name":"America/Chicago","p_limit":500
    },token)

def read_context(api,key,token=None,context=CONTEXT):
    return post(api,key,"/rest/v1/rpc/organization_context_temporal_composer_self_api_v2",{
      "p_organization_id":ORG,"p_context_id":context,
      "p_start_date":"2030-10-01","p_end_date":"2030-10-31",
      "p_timezone_name":"America/Chicago","p_limit":500
    },token)

def denied(status,data,label):
    check(status in (401,403) and isinstance(data,dict)
          and data.get("code") in ("42501","28000"),
          f"{label}: source did not deny (HTTP {status}, {data})")
    print("PASS",label)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                       args.db_url) is not None,"Refuse nonlocal database URL")
    api,key=endpoint()
    users={"member":MEMBER,"outsider":OUTSIDER,"root":ROOT}
    for label,uid in users.items():
        check(sql(args.db_url,f"SELECT count(*) FROM auth.users WHERE id='{uid}'::uuid")=="1",
              f"Missing synthetic fixture user {label}")
        email=f"atlas-one-calendar-{label}@example.invalid"
        spoof='{"is_owner":true,"role":"root_governing"}' if label=="outsider" else '{}'
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
            raw_user_meta_data='{spoof}'::jsonb
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
    signed={}
    for label,uid in users.items():
        code,data=post(api,key,"/auth/v1/token?grant_type=password",{
          "email":f"atlas-one-calendar-{label}@example.invalid",
          "password":PASSWORD
        })
        check(code==200 and isinstance(data,dict) and data.get("access_token"),
              f"Local GoTrue did not sign {label}: HTTP {code}")
        token=data["access_token"]
        claims=token_claims(token)
        check(claims.get("sub")==uid and claims.get("role")=="authenticated"
              and claims.get("session_id"),
              f"Signed {label} JWT identity/session missing")
        check(sql(args.db_url,f"""
          SELECT count(*) FROM auth.sessions
          WHERE id='{claims["session_id"]}'::uuid AND user_id='{uid}'::uuid
        """)=="1",f"{label} signed session absent from local Auth")
        signed[label]=(token,claims)
    check(signed["outsider"][1].get("user_metadata",{}).get("is_owner") is True,
          "Missing synthetic attacker-controlled owner metadata")
    print("PASS genuine independent GoTrue member, governor, outsider sessions")

    for label in ("member","outsider"):
        code,data=read_ledger(api,key,signed[label][0])
        denied(code,data,f"{label} denied broad native Ledger Calendar")
    code,data=read_ledger(api,key)
    check(code in (401,403),"Anonymous reached Ledger Calendar")
    print("PASS anonymous Ledger Calendar denied")
    code,data=read_context(api,key,signed["outsider"][0])
    denied(code,data,"foreign Organization outsider denied calendar context")
    code,data=read_context(api,key)
    check(code in (401,403),"Anonymous reached Organization Calendar")
    print("PASS anonymous Organization Calendar denied")

    code,root=read_ledger(api,key,signed["root"][0])
    check(code==200 and isinstance(root,dict)
        and root.get("contractVersion")=="ledger_temporal_composer_v1"
        and root.get("scope",{}).get("id")==LEDGER,
        f"Signed root cannot read exact Ledger temporal composition (HTTP {code}, {root})")
    refs=root.get("contributions",[])
    ids=[c.get("sourceRef",{}) for c in refs]
    actual={r["id"] for r in ids if r.get("authority")=="local_intel"
            and r.get("kind")=="occurrence"}
    check({EVENT,OTHER_EVENT}.issubset(actual)
          and len([r for r in ids if r.get("id")==EVENT
              and r.get("kind")=="occurrence"])==1,
          "Root calendar lost distinct same-day Events or cloned an Event")
    check(any(r.get("authority")=="ledger"
          and r.get("kind")=="occurrence_resource_claim" for r in ids),
          "Ledger resource commitment was hidden or miscast as an Event")
    check(isinstance(root.get("coverage",{}).get("partial"),bool),
          "Ledger composition did not declare source coverage")
    print("PASS signed root sees one canonical Event per identity and typed occupancy")

    for label in ("member","root"):
        code,data=read_context(api,key,signed[label][0])
        check(code==200 and data.get("contractVersion")==
              "organization_context_temporal_composer_v2"
              and data.get("organizationId")==ORG
              and data.get("context",{}).get("contextId")==CONTEXT,
              f"Signed Organization {label} context failed: HTTP {code} {data}")
        refs=[x.get("sourceRef",{}) for x in data.get("contributions",[])]
        check(sum(x.get("id")==EVENT and x.get("kind")=="occurrence"
                  for x in refs)==1
              and not any(x.get("id")==OTHER_EVENT for x in refs),
              "Context projection included a foreign/context-unadmitted Event")
        check(isinstance(data.get("coverage",{}).get("partial"),bool),
              "Context composition did not declare source coverage")
    print("PASS signed Organization membership reads exact, bounded context")
    code,data=read_context(api,key,signed["member"][0],
                           context="f5210000-0000-4000-8000-000000000999")
    check(code>=400,"Foreign Organization context was accepted")
    print("PASS foreign context ID denied")

    # Membership change is a real source-authority change in the local clone.
    sql(args.db_url,f"""
      UPDATE atlas.organization_memberships SET active=false
      WHERE organization_id='{ORG}'::uuid AND user_id='{MEMBER}'::uuid
    """)
    code,data=read_context(api,key,signed["member"][0])
    denied(code,data,"revoked Organization membership denied with same token")
    sql(args.db_url,f"""
      UPDATE atlas.organization_memberships SET active=true
      WHERE organization_id='{ORG}'::uuid AND user_id='{MEMBER}'::uuid
    """)

    sql(args.db_url,f"""
      UPDATE ledger.seats SET seat_state='ended',ended_at=now()
      WHERE ledger_id='{LEDGER}'::uuid
        AND person_entity_id='{ROOT_PERSON}'::uuid
        AND seat_state='active' AND ended_at IS NULL
    """)
    code,data=read_ledger(api,key,signed["root"][0])
    denied(code,data,"revoked native Ledger seat denied governor read")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS real local signed GoTrue+REST Calendar read authority matrix\n",
      encoding="utf-8"
    )
    print("PASS complete disposable signed ONE Calendar read matrix")

if __name__=="__main__":
    main()

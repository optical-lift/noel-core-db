#!/usr/bin/env python3
"""ACCESS-03A: real local GoTrue + REST, disposable production-schema clone ONLY."""
import argparse
import importlib.util
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "access03_existing_auth",HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
FARM="e5200000-0000-4000-8000-000000000b01"
ZONE="e5200000-0000-4000-8000-000000000b21"
CYCLE="e5200000-0000-4000-8000-000000000b22"
BLOCKED=("Fictional Zone A","synthetic-private-zone","fictional-cycle-a",
         "Fictional crop A","synthetic-private-crop")
def check(ok,label):
    if not ok:
        raise AssertionError("ACCESS03 "+label)

def request(api,key,token,path,method="GET",body=None):
    check(bool(re.fullmatch(r"http://(?:127[.]0[.]0[.]1|localhost):[0-9]+",api)),
          "nonlocal REST endpoint forbidden")
    headers={"apikey":key,"Accept-Profile":"atlas"}
    if token:
        headers["Authorization"]="Bearer "+token
    data=None
    if method=="POST":
        headers["Content-Profile"]="atlas"
        headers["Content-Type"]="application/json"
        data=json.dumps(body or {}).encode()
    req=urllib.request.Request(api+path,headers=headers,data=data,method=method)
    try:
        with urllib.request.urlopen(req,timeout=25) as resp:
            raw=resp.read().decode()
            return resp.status,json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw=exc.read().decode()
        try:
            packet=json.loads(raw) if raw else None
        except json.JSONDecodeError:
            packet={"message":"unknown"}
        return exc.code,packet

def private_missing(code,payload,label,signed):
    check(code in (401,403) and isinstance(payload,dict),
          label+" must be an actual SQL denial, never a missing API route")
    if signed:
        check(payload.get("code")=="42501",label+" must be source privilege denial 42501")
    wire=json.dumps(payload)
    check(all(item not in wire for item in BLOCKED),label+" leaked a private hint")
    print("PASS ACCESS03",label)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                            args.db_url)),"nonlocal database forbidden")
    api,key=c1.local_status()
    # The same four GoTrue fixture identities already exist. They are
    # activated only inside the current disposable clone, never production.
    identities=base.setup_auth(args.db_url)
    tokens={}
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("role")=="authenticated"
              and bool(claims.get("session_id")),name+" signed Person mismatch")
        check(c1.sql(args.db_url,f"select count(*) from auth.sessions where "
              f"id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
              name+" local persisted session missing")
        tokens[name]=token
    check(len(tokens)==4,"four signed actors missing")
    check(c1.sql(args.db_url,f"select count(*) from atlas.farm_memberships where "
           f"farm_id='{FARM}'::uuid and user_id='{c1.WORKER}'::uuid "
           "and role='manager' and active")=="1","synthetic manager role missing")
    print("PASS ACCESS03 genuine separate signed owner/manager/outsider/no-seat")

    # The local REST schema is explicitly exposed: 404/406 is a FAIL.
    paths=(
       ("direct zone","/rest/v1/zones?select=id,label,metadata&farm_id=eq."+FARM),
       ("crop invoker view","/rest/v1/v_crop_cycle_registry?select=crop_cycle_id,crop_label,metadata&farm_id=eq."+FARM),
    )
    for label,path in paths:
        for actor in ("owner","worker","outsider","no-seat"):
            code,packet=request(api,key,tokens[actor],path)
            private_missing(code,packet,label+" withheld from "+actor,True)
        code,packet=request(api,key,None,path)
        private_missing(code,packet,label+" denied anonymously",False)

    # Root-governed API must remain usable despite retired direct SELECT.
    body={"p_farm_id":FARM}
    code,packet=request(api,key,tokens["owner"],
                        "/rest/v1/rpc/zone_registry_source_v1","POST",body)
    check(code==200 and isinstance(packet,dict),
          "governing source read stopped after direct-path retirement")
    zones=packet.get("zones")
    check(isinstance(zones,list) and len(zones)==1
          and zones[0].get("id")==ZONE
          and zones[0].get("label")=="Fictional Zone A",
          "root-governed source lost the actual synthetic zone")
    print("PASS ACCESS03 signed root-only guarded source remains usable")

    for actor in ("worker","outsider","no-seat"):
        code,packet=request(api,key,tokens[actor],
                            "/rest/v1/rpc/zone_registry_source_v1","POST",body)
        private_missing(code,packet,"full-zone RPC withheld from "+actor,True)

    code,packet=request(api,key,tokens["owner"],
        "/rest/v1/rpc/governor_farm_current_inventory_options_self_api_v1",
        "POST",{"p_ledger_id":c1.LEDGER_A})
    check(code==200 and isinstance(packet,dict)
          and packet.get("ok") is True
          and any(x.get("farmId")==FARM for x in packet.get("farms",[])),
          "native governor source inventory options unavailable")
    print("PASS ACCESS03 signed current native governor farm options preserved")

    check(c1.sql(args.db_url,f"select count(*) from atlas.zones where id='{ZONE}'::uuid")=="1"
          and c1.sql(args.db_url,f"select count(*) from atlas.crop_cycles where id='{CYCLE}'::uuid")=="1",
          "historical/actual source rows were deleted")
    Path(args.output).write_text("PASS ACCESS03 signed source retirement and no-loss\n")
    print("PASS ACCESS03 signed local direct-reader retirement and no-loss")

if __name__=="__main__":
    main()

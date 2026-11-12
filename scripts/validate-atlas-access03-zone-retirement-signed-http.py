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
    # Diagnostic only: retain the exact negative assertion. Never print
    # headers, tokens, private SQL response bodies or fictional row fields.
    error_code=payload.get("code") if isinstance(payload,dict) else None
    check(code in (401,403) and isinstance(payload,dict),
          label+" must be an actual SQL denial, never a missing API route;"
          +" HTTP="+str(code)+" error_code="+str(error_code))
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


    # Gate 0 CURRENT-SCHEMA extension. These are genuine separate localhost
    # GoTrue sessions against a disposable clone of the live schema, not a
    # live-production user test. The old manager is NOT a governing Ledger root.
    other_readers=(
        ("object crop bed map","object_crop_bed_map_v1",
         {"p_object_id":"e5200000-0000-4000-8000-000000000b03"},
         "objectId","e5200000-0000-4000-8000-000000000b03"),
        ("farm care zone","farm_care_zone_v1",
         {"p_farm_id":FARM,"p_zone_key":"fictional-zone-a",
          "p_history_limit":10},"zoneId",ZONE),
    )
    for label,rpc_name,params,key_name,key_value in other_readers:
        path="/rest/v1/rpc/"+rpc_name
        code,packet=request(api,key,tokens["owner"],path,"POST",params)
        check(code==200 and isinstance(packet,dict) and
              packet.get(key_name)==key_value,
              "governing source "+label+" must return its source identity")
        print("PASS GATE0 signed governor "+label+" positive")
        for actor in ("worker","outsider","no-seat"):
            code,packet=request(api,key,tokens[actor],path,"POST",params)
            private_missing(code,packet,label+" withheld from "+actor,True)
        code,packet=request(api,key,None,path,"POST",params)
        private_missing(code,packet,label+" anonymous denial",False)
    # Missing and existing object IDs must not give a legacy manager a
    # different source-existence signal.
    code,packet=request(api,key,tokens["worker"],
        "/rest/v1/rpc/object_crop_bed_map_v1","POST",
        {"p_object_id":"e5200000-0000-4000-8000-000000000b99"})
    private_missing(code,packet,"unknown object hidden from manager",True)

    # Explicitly expose atlas on LOCALHOST to test actual old direct RLS
    # paths rather than misreporting a 404/406 schema omission as a denial.
    # A signed legacy manager is permitted by current old RLS policy even
    # without native governing authority. A returned fictional source row
    # is a FAILURE of the E05 disclosure criterion, not a production leak
    # claim. Preserve evidence; never mutate live grants or rows.
    old_direct=(
        ("growing_objects",
         "/rest/v1/growing_objects?select=id,label,metadata&farm_id=eq."+FARM,
         "e5200000-0000-4000-8000-000000000b03"),
        ("crop_cycles",
         "/rest/v1/crop_cycles?select=id,crop_label,metadata&farm_id=eq."+FARM,
         CYCLE),
    )
    # Failure invariant: no rows to a legacy manager lacking native governing root.
    direct_leaks=[]
    for relation,path,fictional_id in old_direct:
        # The canonical governing Ledger root must retain actual underlying
        # row access. Without this positive, a blanket deny could falsely
        # pass every old manager negative test while breaking useful readers.
        code,packet=request(api,key,tokens["owner"],path)
        check(code==200 and isinstance(packet,list) and
              any(isinstance(row,dict) and row.get("id")==fictional_id
                  for row in packet),
              "native Ledger governor lost direct "+relation+" positive")
        print("PASS ACCESS03B signed native governor "+relation+" positive")
        for actor in ("worker","outsider","no-seat"):
            code,packet=request(api,key,tokens[actor],path)
            check(code not in (404,406),
                  relation+" missing REST schema is not a negative test")
            if code==200:
                check(isinstance(packet,list),
                      relation+" REST response must be JSON array")
                if packet:
                    direct_leaks.append(relation+" via "+actor)
                    print("UNSAFE GATE0 SIGNED LOCAL DIRECT TABLE READ: "+
                          relation+" returned private fictional rows to "+
                          actor+" lacking native governing root")
                else:
                    print("PASS ACCESS03B signed "+relation+
                          " no source rows for "+actor)
            else:
                private_missing(code,packet,
                                relation+" denied to "+actor,True)
        code,packet=request(api,key,None,path)
        private_missing(code,packet,relation+" denied to anonymous",False)

    # These two authenticated SECURITY INVOKER views depend on at least one
    # target table. They MUST retain catalog grants/definitions and MUST NOT
    # disclose a sampled row to a legacy role. Original ACCESS-03A revoked
    # zone SELECT, so a root's view call MAY ALREADY fail with 42501 before
    # ACCESS-03B. Record that pre-existing positive blocker explicitly; do
    # not fabricate a view-positive result from metadata/ACL alone.
    invoker_views=(
        "farm_care_object_state_v1",
        "v_farm_object_operational_state",
    )
    for view in invoker_views:
        path="/rest/v1/"+view+"?select=farm_id,object_id&farm_id=eq."+FARM+"&limit=1"
        code,packet=request(api,key,tokens["owner"],path)
        check(code not in (404,406),"dependent view route not present: "+view)
        if code==200:
            check(isinstance(packet,list),
                  "owner dependent view must return a JSON array")
            print("PASS ACCESS03B signed governor invoker view REST reachable: "+
                  view+" rows="+str(len(packet)))
        elif code in (401,403) and isinstance(packet,dict) and (
                packet.get("code")=="42501"):
            print("HELD ACCESS03B governor invoker view 42501 (possible "+
                  "pre-existing ACCESS03A zone SELECT dependency): "+view)
        else:
            raise AssertionError("ACCESS03B unexpected governor view response: "+
                                 view+" HTTP "+str(code))
        for actor in ("worker","outsider","no-seat"):
            code,packet=request(api,key,tokens[actor],path)
            check(code not in (404,406),
                  view+" missing REST route is not an actor denial")
            if code==200:
                check(isinstance(packet,list),view+" response must be array")
                if packet:
                    direct_leaks.append(view+" via "+actor)
                    print("UNSAFE GATE0 SIGNED LOCAL DIRECT TABLE READ: "+
                          view+" revealed an operational row to "+actor)
                else:
                    print("PASS ACCESS03B signed invoker view no rows to "+actor)
            else:
                private_missing(code,packet,
                                view+" withheld from "+actor,True)
        code,packet=request(api,key,None,path)
        private_missing(code,packet,view+" anonymous denied",False)

    # A separate legacy farm_hand state may not promote the same Person to
    # native root. This state change occurs ONLY on disposable localhost.
    c1.sql(args.db_url,f"""update atlas.farm_memberships set role='farm_hand'
        where farm_id='{FARM}'::uuid and
        user_id='{c1.WORKER}'::uuid and active""")
    check(c1.sql(args.db_url,f"""select count(*) from atlas.farm_memberships
         where farm_id='{FARM}'::uuid and user_id='{c1.WORKER}'::uuid
         and role='farm_hand' and active""")=="1",
          "local farmhand state transition did not persist")
    for label,rpc_name,params,_,_ in (
        ("zone registry","zone_registry_source_v1",{"p_farm_id":FARM},None,None),
        *other_readers,
    ):
        code,packet=request(api,key,tokens["worker"],
                 "/rest/v1/rpc/"+rpc_name,"POST",params)
        private_missing(code,packet,label+" withheld from farm_hand",True)

    # Assert before writing any PASS summary. This diagnostic deliberately
    # remains red when the old RLS still exposes fictional source material.
    if direct_leaks:
        Path(args.output).write_text(
            "UNSAFE GATE0 SIGNED LOCAL DIRECT TABLE READ: "+
            ",".join(direct_leaks)+"\n")
        raise AssertionError(
            "GATE0 legacy manager obtained fictional source rows through "+
            "direct table REST: "+",".join(direct_leaks)+
            "; source-only RLS repair and signed retest required")
    print("PASS GATE0 signed current-schema three broad RPCs; "+
          "legacy manager/outsider/no-seat/farm_hand/anon negative; "+
          "sampled direct-table paths returned no fictional rows")


    # This is the ONE authenticated-executable invoker function in the
    # inspected source-function census that reads growing_objects directly.
    # A legitimate governor must still detect a synthetic retired object;
    # an old legacy manager lacking native root must not learn that fact.
    retired_id="e5200000-0000-4000-8000-000000000b04"
    c1.sql(args.db_url,f"""update atlas.growing_objects
         set metadata=jsonb_set(metadata,'{canonicalDeleted}','"true"'::jsonb,true)
         where id='{retired_id}'::uuid and farm_id='{FARM}'::uuid""")
    retired_rpc="/rest/v1/rpc/is_retired_growing_object_v1?p_object_id="+retired_id
    code,packet=request(api,key,tokens["owner"],retired_rpc)
    check(code==200 and packet is True,
          "native governor lost positive retired-object invoker check")
    for actor in ("worker","outsider","no-seat"):
        code,packet=request(api,key,tokens[actor],retired_rpc)
        check(code==200 and packet is False,
              "old role learned retired-object existence via invoker "+actor)
    code,packet=request(api,key,None,retired_rpc)
    private_missing(code,packet,"retired-object invoker anon denied",False)
    print("PASS ACCESS03B signed retired-object invoker governor-positive, "+
          "legacy/outsider/no-seat/anon negative")
    c1.sql(args.db_url,f"""update atlas.growing_objects
         set metadata=metadata-'canonicalDeleted'
         where id='{retired_id}'::uuid and farm_id='{FARM}'::uuid""")
    code,packet=request(api,key,tokens["owner"],retired_rpc)
    check(code==200 and packet is False,
          "retired-object invoker did not return to original false state")
    print("PASS ACCESS03B synthetic retired-object marker fully restored")

    # A valid *previously* signed owner JWT must stop reading after their
    # native governing authority is ended; mutation is local clone ONLY.
    c1.sql(args.db_url,f"""update atlas.principal_ledger_authorities
        set status='ended', ended_at=now()
        where id='{c1.ROOT_AUTHORITY}'::uuid and status='active'""")
    check(c1.sql(args.db_url,f"""select count(*)
        from atlas.principal_ledger_authorities
        where id='{c1.ROOT_AUTHORITY}'::uuid
          and status='ended' and ended_at IS NOT NULL""")=="1",
          "native authority revocation fixture did not persist")
    for relation,path,fictional_id in old_direct:
        code,packet=request(api,key,tokens["owner"],path)
        check(code not in (404,406),
              relation+" revoked native owner REST route absent")
        if code==200:
            check(isinstance(packet,list) and
                  not any(isinstance(row,dict) and
                          row.get("id")==fictional_id for row in packet),
                  "revoked native owner still reads "+relation)
        else:
            private_missing(code,packet,
                            relation+" revoked native root denied",True)
    print("PASS ACCESS03B native governing root revocation cuts both tables")
    c1.sql(args.db_url,f"""update atlas.principal_ledger_authorities
        set status='active', ended_at=NULL
        where id='{c1.ROOT_AUTHORITY}'::uuid and status='ended'""")
    for relation,path,fictional_id in old_direct:
        code,packet=request(api,key,tokens["owner"],path)
        check(code==200 and isinstance(packet,list) and
              any(isinstance(row,dict) and row.get("id")==fictional_id
                  for row in packet),
              "restored native governing root did not restore "+relation)
    print("PASS ACCESS03B exact root restoration returns both source rows")

    check(c1.sql(args.db_url,f"select count(*) from atlas.zones where id='{ZONE}'::uuid")=="1"
          and c1.sql(args.db_url,f"select count(*) from atlas.crop_cycles where id='{CYCLE}'::uuid")=="1",
          "historical/actual source rows were deleted")
    Path(args.output).write_text(
        "PASS ACCESS03 signed source retirement and no-loss\n"
        "PASS ACCESS03B signed native two-table policy and no-loss\n")
    print("PASS ACCESS03 signed local direct-reader retirement and no-loss")

if __name__=="__main__":
    main()

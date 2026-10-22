#!/usr/bin/env python3
"""Genuine signed GoTrue/PostgREST prerequisite proof, DISPOSABLE LOCAL CLONE ONLY.

Reuses four synthetic C1 identities and canonical Ledger authority fixture.
It never contacts production, seeds real people, sends mail or places real Work.
"""
import argparse
import importlib.util
import json
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("atlas_c1_local_auth",HERE/"validate-atlas-c1-signed-http.py")
c1=importlib.util.module_from_spec(spec)
spec.loader.exec_module(c1)

ORG=c1.ORG
LEDGER=c1.LEDGER_A
A="e5200000-0000-4000-8000-000000000901"
B="e5200000-0000-4000-8000-000000000902"
C="e5200000-0000-4000-8000-000000000903"
ROOT_PERSON="e5200000-0000-4000-8000-000000000101"
PATH="/rest/v1/rpc/"

def check(test,message): c1.check(test,message)
def sql(db,query): return c1.sql(db,query)
def rpc(api,key,token,name,body): return c1.request(api,key,PATH+name,body,token)
def allow(api,key,token,name,body):
    code,obj=rpc(api,key,token,name,body)
    check(code==200 and isinstance(obj,dict) and obj.get("ok") is True,
          f"Authorized {name} failed (HTTP {code}, response {str(obj)[:250]})")
    return obj
def deny(api,key,token,name,body,label):
    code,obj=rpc(api,key,token,name,body)
    check(code in (401,403) and isinstance(obj,dict),f"{label}: expected denial, HTTP {code}")
    if token is not None:
        check(obj.get("code")=="42501",f"{label}: not source-level 42501 denial: {obj}")
    print("PASS",label)

def action(downstream,prereq,enabled,identifier,reason="Original related Work has a required prerequisite."):
    return {"p_organization_id":ORG,"p_ledger_id":LEDGER,
            "p_downstream_work_item_id":downstream,
            "p_prerequisite_work_item_id":prereq,
            "p_enabled":enabled,"p_reason":reason,"p_source_action_id":identifier}
def read_args(downstream):
    return {"p_organization_id":ORG,"p_ledger_id":LEDGER,
            "p_downstream_work_item_id":downstream}
def setup_auth(db):
    identities=(("owner",c1.OWNER),("worker",c1.WORKER),
                ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT))
    check(sql(db,"select count(*) from auth.users where id in ('"+
          "','".join(uid for _,uid in identities)+"')")=="4",
          "Four synthetic C1 Auth identities missing")
    for name,uid in identities:
        address=f"atlas-c1-{name}@example.invalid"
        metadata='{"is_owner":true,"role":"root_governing"}' if name=="worker" else "{}"
        sql(db,f"""
          update auth.users set
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{address}',
            encrypted_password=extensions.crypt('{c1.PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),
            confirmation_token='',recovery_token='',email_change='',
            email_change_token_new='',email_change_token_current='',
            phone_change='',phone_change_token='',reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{metadata}'::jsonb
          where id='{uid}'::uuid
        """)
        sql(db,f"""
          insert into auth.identities(id,provider_id,user_id,identity_data,
              provider,created_at,updated_at)
          values(gen_random_uuid(),'{address}','{uid}'::uuid,
              jsonb_build_object('sub','{uid}','email','{address}'),
              'email',now(),now())
        """)
    sql(db,"notify pgrst, 'reload schema'")
    return identities

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
          "Prerequisite signed proof refuses nonlocal database URL")
    api,key=c1.local_status()
    identities=setup_auth(args.db_url)
    sessions={}
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and bool(claims.get("session_id")),
              f"{name}: GoTrue signed JWT identity invalid")
        check(sql(args.db_url,f"""select count(*) from auth.sessions
           where id='{claims["session_id"]}'::uuid and user_id='{uid}'::uuid""")=="1",
           f"{name}: real session record missing")
        sessions[name]=(token,claims)
    check(sessions["worker"][1].get("user_metadata",{}).get("is_owner") is True,
          "Synthetic worker spoofed editable user_metadata is missing")
    print("PASS four genuinely signed, separate local Atlas sessions")

    root=sessions["owner"][0]
    original={"p_organization_id":ORG,"p_ledger_id":LEDGER,"p_limit":50}
    candidates=allow(api,key,root,"atlas_work_prerequisite_candidates_self_api_v1",original)
    ids=[x.get("id") for x in candidates.get("items",[])]
    check(set(ids)=={A,B,C},f"Verified Work candidate scope unexpected: {ids}")
    check(all(x.get("ledgerId")==LEDGER and x.get("organizationId")==ORG
              for x in candidates["items"]),"Work candidate identity escaped original Ledger")
    print("PASS exact source-grounded owner Work candidates")

    write=action(A,B,True,"clone-prerequisite-owner-add")
    for name in ("worker","outsider","no-seat"):
        deny(api,key,sessions[name][0],"atlas_work_prerequisite_candidates_self_api_v1",
             original,f"{name} cannot inspect owner-only candidates")
        deny(api,key,sessions[name][0],"atlas_set_work_prerequisite_self_api_v1",
             write,f"{name} cannot forge governing prerequisite writer")
        deny(api,key,sessions[name][0],"atlas_work_prerequisites_self_api_v1",
             read_args(A),f"{name} cannot read owner-only relationship")
    for name,body in (
        ("atlas_work_prerequisite_candidates_self_api_v1",original),
        ("atlas_set_work_prerequisite_self_api_v1",write)):
        deny(api,key,None,name,body,"anonymous caller cannot access "+name)

    receipt=allow(api,key,root,"atlas_set_work_prerequisite_self_api_v1",write)
    relation_id=receipt.get("relationId")
    event_id=receipt.get("recordedEventId")
    check(receipt.get("contractVersion")=="atlas_work_prerequisite_set_v1"
          and receipt.get("active") is True and
          receipt.get("doesNotCreateWork") is True and
          receipt.get("doesNotAutomaticallyBlockWork") is True and
          receipt.get("idempotentReplay") is False and relation_id and event_id,
          "Original owner receipt missing exact relation/audit identity")
    source=allow(api,key,root,"atlas_work_prerequisites_self_api_v1",read_args(A))
    matches=[x for x in source.get("relations",[])
             if x.get("relationId")==relation_id and
             x.get("prerequisiteWorkItemId")==B and x.get("active") is True]
    check(len(matches)==1,"Original Work relation not reread by canonical identity")
    audit=allow(api,key,root,"atlas_work_prerequisite_event_self_api_v1",
                {"p_organization_id":ORG,"p_ledger_id":LEDGER,
                 "p_recorded_event_id":event_id})
    check(audit.get("relationId")==relation_id and
          audit.get("sourceActionId")==write["p_source_action_id"] and
          audit.get("actorPersonId")==ROOT_PERSON and
          audit.get("actionKind")=="establish" and audit.get("afterActive") is True,
          "Actor-attributed original event did not match source")
    print("PASS authorized establish with independently reread relation and event")

    replay=allow(api,key,root,"atlas_set_work_prerequisite_self_api_v1",write)
    check(replay.get("idempotentReplay") is True and
          replay.get("relationId")==relation_id and replay.get("recordedEventId")==event_id,
          "Same source action replay changed the original link/event")
    altered=dict(write,p_reason="A different reason must not reuse an old action ID")
    code,obj=rpc(api,key,root,"atlas_set_work_prerequisite_self_api_v1",altered)
    check(code>=400 and isinstance(obj,dict) and obj.get("code")=="23505",
          f"Conflicting source action reused the same idempotency key: HTTP {code}")
    print("PASS idempotent replay and same-key conflict denial")

    withdrawal=action(A,B,False,"clone-prerequisite-owner-withdraw",
                      "Original Work prerequisite no longer applies.")
    removed=allow(api,key,root,"atlas_set_work_prerequisite_self_api_v1",withdrawal)
    check(removed.get("relationId")==relation_id and removed.get("active") is False,
          "Withdrawal replaced or failed to inactivate original relation")
    removed_source=allow(api,key,root,"atlas_work_prerequisites_self_api_v1",read_args(A))
    check(any(x.get("relationId")==relation_id and x.get("active") is False
              for x in removed_source.get("relations",[])),
          "Original relation disappeared after withdrawal")
    print("PASS original link withdrawal preserved source and history")

    # Opposing writes race through the SAME protected RPC using two distinct
    # genuine signed sessions for the governing principal.
    second_token,second_claims=c1.sign_in(api,key,"owner")
    check(second_claims.get("session_id")!=sessions["owner"][1].get("session_id"),
          "Race needs distinct real GoTrue sessions")
    barrier=threading.Barrier(3)
    forward=action(A,B,True,"clone-prerequisite-race-forward")
    reverse=action(B,A,True,"clone-prerequisite-race-reverse")
    def race(token,body):
        barrier.wait(timeout=10)
        return rpc(api,key,token,"atlas_set_work_prerequisite_self_api_v1",body)
    with ThreadPoolExecutor(max_workers=2) as pool:
        one=pool.submit(race,root,forward)
        two=pool.submit(race,second_token,reverse)
        barrier.wait(timeout=10)
        outcomes=[one.result(timeout=40),two.result(timeout=40)]
    ok=[x for x in outcomes if x[0]==200 and isinstance(x[1],dict) and x[1].get("ok")]
    blocked=[x for x in outcomes if x[0]>=400 and isinstance(x[1],dict)
             and x[1].get("code")=="23514"]
    check(len(ok)==1 and len(blocked)==1,
          f"Concurrent reverse Work links violated no-cycle invariant: {outcomes}")
    active=sql(args.db_url,f"""select count(*) from atlas.work_item_relations
       where organization_id='{ORG}'::uuid and relation_kind='depends_on' and active""")
    check(active=="1","Two opposing active dependency edges were admitted")
    check(sql(args.db_url,f"""select count(*) from atlas.work_items
       where organization_id='{ORG}'::uuid""")=="3",
       "Dependency authoring generated duplicate Work")
    check(sql(args.db_url,f"""select count(*) from atlas.work_item_prerequisite_events_v1
       where organization_id='{ORG}'::uuid""")=="3",
       "Rejected race or idempotent retries generated extra historical events")
    print("PASS real two-session opposing write race, cycle rejection and atomic history")

    sql(args.db_url,f"""update atlas.principal_ledger_authorities
        set status='ended',ended_at=now()
        where id='{c1.ROOT_AUTHORITY}'::uuid""")
    deny(api,key,root,"atlas_work_prerequisite_candidates_self_api_v1",
         original,"revoked governing authority denies prior signed root")
    sql(args.db_url,f"""update atlas.principal_ledger_authorities
        set status='active',ended_at=NULL
        where id='{c1.ROOT_AUTHORITY}'::uuid""")
    sql(args.db_url,f"""delete from auth.sessions where
        id='{sessions["owner"][1]["session_id"]}'::uuid""")
    deny(api,key,root,"atlas_work_prerequisite_candidates_self_api_v1",
         original,"revoked real signed session denies prior governing root")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
        "PASS synthetic signed Atlas owner/worker/outsider/no-seat prerequisite matrix; original source/event; replay; conflicting concurrent cycles; authority/session revocation\n",encoding="utf-8")
    print("PASS all disposable, genuinely authenticated Work prerequisite proof cases")

if __name__=="__main__":
    main()

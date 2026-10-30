#!/usr/bin/env python3
"""ONLY a disposable local production-schema clone. Genuine separate GoTrue
sessions + REST calls; no production database URL, HTTP host, or real Person.
A missing RPC (404/PGRST202) is NEVER an authorization denial.
"""
import argparse
import datetime
import importlib.util
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("atlas_native_work_base",
    HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
ORG=c1.ORG
LEDGER=c1.LEDGER_A
OTHER=c1.LEDGER_B
WORK_EVENT="e5200000-0000-4000-8000-000000000901"
WORK_DIRECT="e5200000-0000-4000-8000-000000000902"
ALLOCATION="e5200000-0000-4000-8000-000000000983"
OWNER_SEAT=c1.ROOT_SEAT
READ="read_native_original_work_text_owner_self_api_v1"
EDIT="revise_native_original_work_text_owner_self_api_v1"
OWN_RESULTS="read_native_original_work_own_results_self_api_v1"
DATE="owner_set_connected_person_work_day_self_api_v1"
MY_WORK="connected_person_my_work_self_api_v1"

def check(v,message): base.check(v,message)
def sql(db,statement): return base.sql(db,statement)
def rpc(api,key,token,name,args): return base.rpc(api,key,token,name,args)
def allow(api,key,token,name,args):
    code,obj=rpc(api,key,token,name,args)
    check(code==200 and isinstance(obj,dict) and obj.get("ok") is True,
          f"{name}: signed source returned HTTP {code}, {str(obj)[:230]}")
    return obj
def deny(api,key,token,name,args,label):
    code,obj=rpc(api,key,token,name,args)
    check(code in (401,403) and isinstance(obj,dict) and
          (token is None or obj.get("code")=="42501"),
          f"{label}: expected source 42501, never 404: HTTP {code}, {str(obj)[:200]}")
    print("PASS",label)
def identity_args(work=WORK_EVENT,ledger=LEDGER):
    return {"p_organization_id":ORG,"p_ledger_id":ledger,"p_work_item_id":work}
def date_args(day,ledger=LEDGER):
    return {"p_work_item_id":WORK_DIRECT,"p_ledger_id":ledger,
            "p_service_date":day,"p_reason":"schedule_updated_in_Atlas_notebook"}
def inspect_work(api,key,token):
    packet=allow(api,key,token,MY_WORK,
        {"p_limit":100,"p_after_allocation_id":None})
    check(packet.get("scheduleReadAcrossAllDates") is True
          and packet.get("optionalRequestsExcluded") is True,
          "Person My Work source lost complete all-date signed contract")
    records=[r for r in packet.get("items",[]) if r.get("workItemId")==WORK_DIRECT]
    check(len(records)==1 and records[0].get("allocationId")==ALLOCATION,
          "Connected recipient did not read exactly one original Work allocation")
    return records[0],packet

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url),
          "Refuse every nonlocal database URL")
    api,key=c1.local_status()
    base.setup_auth(args.db_url)
    sessions={}
    for name,expected in (("owner",c1.OWNER),("worker",c1.WORKER),
                          ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==expected and claims.get("session_id"),
              "GoTrue wrong canonical identity or no session")
        check(sql(args.db_url,"select count(*) from auth.sessions where id='"+
              claims["session_id"]+"'::uuid and user_id='"+expected+"'::uuid")=="1",
              "Session missing from local Auth")
        sessions[name]=token
    owner=sessions["owner"]; worker=sessions["worker"]
    outsider=sessions["outsider"];noseat=sessions["no-seat"]
    print("PASS four separately signed local GoTrue identities")
    detail=allow(api,key,owner,READ,identity_args())
    version=detail.get("updatedAt")
    check(detail.get("workItemId")==WORK_EVENT and detail.get("canEdit") is True
          and detail.get("title")=="Synthetic event refreshments" and version,
          "Owner did not read original native text and exact stale-write version")
    for name,token in (("worker",worker),("outsider",outsider),("unbound",noseat)):
        deny(api,key,token,READ,identity_args(),name+" native owner read")
        deny(api,key,token,EDIT,{**identity_args(),
             "p_expected_updated_at":version,"p_new_title":"Forged clone edit",
             "p_new_instructions":"Cannot edit another owner task"},
             name+" native owner edit")
        deny(api,key,token,OWN_RESULTS,{**identity_args(),"p_limit":30},
             name+" owner-only Result notes")
        deny(api,key,token,DATE,date_args(None),name+" owner scheduling")
    deny(api,key,None,READ,identity_args(),"anonymous owner detail")
    deny(api,key,owner,READ,identity_args(ledger=OTHER),"other-Ledger owner scope")
    changed=allow(api,key,owner,EDIT,{**identity_args(),
        "p_expected_updated_at":version,"p_new_title":"Synthetic event water station",
        "p_new_instructions":"Bring cups and fill the dispenser"})
    check(changed.get("workItemId")==WORK_EVENT and changed.get("changed") is True
          and changed.get("revisionEventId") and changed.get("oneOriginalWorkId") is True,
          "Edit minted another Work or lacked a persisted audit receipt")
    readback=allow(api,key,owner,READ,identity_args())
    check(readback.get("title")=="Synthetic event water station"
          and readback.get("instructions")=="Bring cups and fill the dispenser"
          and readback.get("updatedAt")==changed.get("updatedAt")
          and readback.get("updatedAt")!=version,
          "Owner's updated original Work text not independently reread")
    second=allow(api,key,owner,EDIT,{**identity_args(),
        "p_expected_updated_at":changed["updatedAt"],
        "p_new_title":changed["title"],
        "p_new_instructions":changed["instructions"]})
    check(second.get("changed") is False and sql(args.db_url,
          "select count(*) from atlas.native_work_text_revision_events_v1 "
          f"where work_item_id='{WORK_EVENT}'::uuid")=="1",
          "Idempotent no-op must not fabricate another revision event")
    code,stale=rpc(api,key,owner,EDIT,{**identity_args(),
        "p_expected_updated_at":version,
        "p_new_title":"Stale edit must not apply",
        "p_new_instructions":"No stale overwrite"})
    check(code!=200 and isinstance(stale,dict) and stale.get("code")=="40001",
          f"Stale source version must reject with SQLSTATE 40001, got {code} {stale}")
    check(sql(args.db_url,
          f"select title from atlas.work_items where id='{WORK_EVENT}'::uuid")==
          "Synthetic event water station","Stale write altered original Work")
    print("PASS signed owner edit/readback; idempotent and stale reject; original ID")
    # Two notes on exactly the same original Work. The owner may read ONLY the
    # owner's own narrative. This fixture never goes to production.
    for i,(userid,note) in enumerate(((c1.OWNER,"SYNTH_OWNER_NOTE_PRIVATE"),
                                      (c1.WORKER,"SYNTH_WORKER_NOTE_WITHHELD"))):
        sql(args.db_url,"insert into atlas.work_execution_results "
            "(organization_id,work_item_id,reported_by_user_id,result_kind,"
            "result_contract_key,idempotency_key,payload) values "
            f"('{ORG}'::uuid,'{WORK_EVENT}'::uuid,'{userid}'::uuid,"
            "'partial','ordinary_company_work_worker_attestation_v1',"
            f"'clone-native-report-{i}',jsonb_build_object('note','{note}'))")
    notes=allow(api,key,owner,OWN_RESULTS,{**identity_args(),"p_limit":30})
    check(notes.get("ownReporterOnly") is True and
          notes.get("otherPeopleReportsDisclosed") is False,
          "Own Result contract removed signed reporter isolation")
    encoded=json.dumps(notes)
    check("SYNTH_OWNER_NOTE_PRIVATE" in encoded and
          "SYNTH_WORKER_NOTE_WITHHELD" not in encoded and
          len(notes.get("items",[]))==1,
          "Other worker's written Result leaked into owner's private reader")
    print("PASS signed own-Result narrative isolated from another reporter")
    initial,_=inspect_work(api,key,worker)
    check(initial.get("workOn") is None,"Preplanning Work should be undated")
    today=datetime.date.fromisoformat(sql(args.db_url,"select current_date"))
    first=(today+datetime.timedelta(days=1)).isoformat()
    second_day=(today+datetime.timedelta(days=2)).isoformat()
    planned=allow(api,key,owner,DATE,date_args(first))
    check(planned.get("workItemId")==WORK_DIRECT and planned.get("newWorkCreated") is False
          and planned.get("planId"),"Owner date planned a copy or returned no Plan ID")
    first_plan=planned["planId"]
    dated,_=inspect_work(api,key,worker)
    check(dated.get("workOn")==first,"Worker's all-date Work missed owner plan")
    moved=allow(api,key,owner,DATE,date_args(second_day))
    check(moved.get("workItemId")==WORK_DIRECT and moved.get("planId")==first_plan,
          "Moving work day minted a second plan or Work")
    after,_=inspect_work(api,key,worker)
    check(after.get("workOn")==second_day,"Worker did not receive moved date")
    unplanned=allow(api,key,owner,DATE,date_args(None))
    check(unplanned.get("workItemId")==WORK_DIRECT and
          unplanned.get("state") in ("unplanned","already_unplanned"),
          "Owner clearing work day failed")
    final,_=inspect_work(api,key,worker)
    check(final.get("workOn") is None,"Clearing a plan must restore undated Work")
    check(sql(args.db_url,"select count(*) from atlas.work_execution_plans "
          f"where work_item_id='{WORK_DIRECT}'::uuid")=="1" and
          sql(args.db_url,"select count(*) from atlas.work_items where "
          f"id in ('{WORK_EVENT}'::uuid,'{WORK_DIRECT}'::uuid)")=="2",
          "Date transitions fabricated Work or plans")
    print("PASS signed original Work owner plan, move, clear and recipient readback")
    # Closing native authority must work for still-signed JWTs. No 404 counts.
    sql(args.db_url,f"update ledger.seats set seat_state='ended',ended_at=now() "
                    f"where id='{OWNER_SEAT}'::uuid")
    deny(api,key,owner,READ,identity_args(),"revoked owner seat read")
    deny(api,key,owner,DATE,date_args(first),"revoked owner seat writer")
    sql(args.db_url,f"update ledger.seats set seat_state='active',ended_at=null "
                    f"where id='{OWNER_SEAT}'::uuid")
    sql(args.db_url,
        "update ledger.seats set seat_state='ended',ended_at=now() "
        "where id='e5200000-0000-4000-8000-000000000502'::uuid")
    code,body=rpc(api,key,worker,MY_WORK,
        {"p_limit":100,"p_after_allocation_id":None})
    check(code!=404 and
          (code in (401,403) or
           (code==200 and isinstance(body,dict) and all(
            x.get("workItemId")!=WORK_DIRECT for x in body.get("items",[])))),
          "Revoked worker ledger seat retained discoverable original Work")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
        "PASS real separate local signed owner/worker/outsider/no-seat; native text "
        "edit/stale/audit/own Result isolation; work date plan/move/clear; recipient "
        "readback, own Ledger and seat revocation. NO production changes.\n")
    print("PASS native editing, scheduling and source isolation signed clone")

if __name__=="__main__":
    main()

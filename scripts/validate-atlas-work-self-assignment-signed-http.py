#!/usr/bin/env python3
"""Genuine local GoTrue / PostgREST self-assignment proof; disposable database only.
Uses existing synthetic C1 Person/Ledger fixture and never contacts production.
A missing RPC (404) cannot establish a successful permission denial.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "work_self_auth",HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
check=c1.check
ORG=c1.ORG
LEDGER=c1.LEDGER_A
OTHER_LEDGER=c1.LEDGER_B
SELF_PERSON="e5200000-0000-4000-8000-000000000101"
OTHER_PERSON="e5200000-0000-4000-8000-000000000102"
OUTSIDER_PERSON="e5200000-0000-4000-8000-000000000103"
UNCONNECTED_PERSON="e5200000-0000-4000-8000-000000000104"
SELF_WORK="e5200000-0000-4000-8000-000000000971"
OTHER_WORK="e5200000-0000-4000-8000-000000000972"
CHOICES="connected_ledger_person_choices_self_api_v1"
ASSIGN="owner_direct_assign_existing_original_work_self_api_v1"

def sql(db,statement): return c1.sql(db,statement)
def rpc(api,key,token,name,args):
    return c1.request(api,key,"/rest/v1/rpc/"+name,args,token)
def accepted(api,key,token,name,args):
    status,data=rpc(api,key,token,name,args)
    check(status==200 and isinstance(data,dict) and data.get("ok") is True,
          f"{name} not signed-successful: {status} {str(data)[:220]}")
    return data
def denied(api,key,token,name,args,label):
    status,data=rpc(api,key,token,name,args)
    check(status in (401,403) and isinstance(data,dict) and
          (token is None or data.get("code")=="42501"),
          f"{label}: source permission denial required, not 404: {status} {str(data)[:220]}")
    print("PASS",label)
def args(work,person,action,reason="Exact fictional Work responsibility under native Ledger governance."):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_work_item_id=work,
       p_target_person_id=person,p_service_date=None,p_action_id=action,p_reason=reason)
def choices(api,key,token,ledger):
    after=None;got=[];seen=set()
    for n in range(10):
        packet=accepted(api,key,token,CHOICES,
            dict(p_ledger_id=ledger,p_limit=1,p_after_person_id=after))
        check(packet.get("contractVersion")=="connected_ledger_person_choices_v1"
          and packet.get("ledgerId")==ledger and isinstance(packet.get("items"),list),
          "Source-returned Person chooser identity/contract mismatch")
        rows=packet["items"]
        check(len(rows)<=1 and all(isinstance(x,dict) for x in rows),
              "Page-size or shape violated")
        for row in rows:
            value=row.get("personId")
            check(value not in seen and bool(row.get("name")),"Duplicate/unnamed Person")
            seen.add(value);got.append(value)
        if packet.get("hasMore") is False:
            check(packet.get("nextPersonId") is None,"Terminal cursor must be NULL")
            return got
        next_id=packet.get("nextPersonId")
        check(len(rows)==1 and next_id==rows[0]["personId"] and
              next_id!=after,"Cursor does not match its one-item page")
        after=next_id
    raise AssertionError("Person choices pagination did not terminate")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    opt=p.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",opt.db_url)),
          "Refusing a nonlocal database")
    api,key=c1.local_status()
    identities=base.setup_auth(opt.db_url)
    sessions={}
    sql(opt.db_url,"notify pgrst, 'reload schema'")
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),
              f"Incorrect local GoTrue session: {name}")
        check(sql(opt.db_url,f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
              "Signed token without a persisted corresponding local session")
        sessions[name]=(token,claims)
    root=sessions["owner"][0]
    worker=sessions["worker"][0]
    outsider=sessions["outsider"][0]
    no_seat=sessions["no-seat"][0]
    check(sessions["worker"][1].get("user_metadata",{}).get("is_owner") is True,
          "Missing spoofable worker JWT metadata to test rejection")
    print("PASS genuine signed local owner/worker/outsider/no-seat sessions")

    root_choices=choices(api,key,root,LEDGER)
    worker_choices=choices(api,key,worker,LEDGER)
    check(root_choices==[SELF_PERSON,OTHER_PERSON] and
          worker_choices==[SELF_PERSON,OTHER_PERSON],
          f"Connected Person choices, self-inclusion, pagination: {root_choices} {worker_choices}")
    for token,label in ((outsider,"other-Ledger Person"),(no_seat,"unconnected Person"),(None,"anonymous")):
        denied(api,key,token,CHOICES,
               dict(p_ledger_id=LEDGER,p_limit=1,p_after_person_id=None),
               label+" may not enumerate governed Ledger People")

    original_count=sql(opt.db_url,
        f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")
    check(original_count=="6","Fictional original+split Work fixture must be exact")
    owner_action="e5200000-0000-4000-8000-000000000981"
    direct=args(SELF_WORK,SELF_PERSON,owner_action)
    for token,label in ((worker,"worker"),(outsider,"outsider"),(no_seat,"no-seat"),(None,"anonymous")):
        denied(api,key,token,ASSIGN,direct,
               label+" cannot forge governor self-assignment")
    denied(api,key,root,ASSIGN,args(SELF_WORK,OUTSIDER_PERSON,
             "e5200000-0000-4000-8000-000000000982"),
           "governor cannot assign Work to disconnected Person from another Ledger")
    denied(api,key,root,ASSIGN,args(SELF_WORK,UNCONNECTED_PERSON,
             "e5200000-0000-4000-8000-000000000983"),
           "governor cannot grant unconnected Person Work")

    assigned=accepted(api,key,root,ASSIGN,direct)
    allocation=assigned.get("allocationId")
    check(assigned.get("contractVersion")=="original_subject_work_direct_responsibility_v1"
          and assigned.get("workItemId")==SELF_WORK
          and assigned.get("targetPersonId")==SELF_PERSON
          and assigned.get("responsibilityEstablished") is True
          and assigned.get("scheduleState")=="unscheduled"
          and assigned.get("plannedServiceDate") is None
          and assigned.get("planId") is None
          and assigned.get("newWorkCreated") is False
          and assigned.get("newTaskCreated") is False
          and assigned.get("employeeSeatRequired") is False
          and assigned.get("workerAttestedAsSelf") is False
          and bool(allocation),"Signed governor self-assignment receipt invalid")
    assert_count=f"select count(*) from atlas.work_allocations where work_item_id='{SELF_WORK}'::uuid and state='active' and assignee_canonical_person_id='{SELF_PERSON}'::uuid"
    check(sql(opt.db_url,assert_count)=="1","One native responsible allocation required")
    check(sql(opt.db_url,f"select count(*) from atlas.work_execution_plans where work_item_id='{SELF_WORK}'::uuid")=="0",
          "An unscheduled assignment must not create a plan")
    replay=accepted(api,key,root,ASSIGN,direct)
    check(replay.get("allocationId")==allocation and replay.get("idempotent") is True,
          "Same action replay must return original allocation")

    for changed,label in (
        (dict(direct,p_reason="Changed reason cannot reuse a previous source action."),"changed exact action"),
        (args(SELF_WORK,OTHER_PERSON,"e5200000-0000-4000-8000-000000000984"),"conflicting active recipient"),
        (args("e5200000-0000-4000-8000-000000000901",SELF_PERSON,
              "e5200000-0000-4000-8000-000000000985"),"non-decomposed original")):
        status,body=rpc(api,key,root,ASSIGN,changed)
        check(status>=400 and status!=404 and isinstance(body,dict) and
             body.get("code") in ("23514","23505"),
              f"{label}: rejected source action required: {status} {str(body)[:170]}")
    other=accepted(api,key,root,ASSIGN,args(OTHER_WORK,OTHER_PERSON,
           "e5200000-0000-4000-8000-000000000986"))
    check(other.get("targetPersonId")==OTHER_PERSON and
          other.get("workItemId")==OTHER_WORK and other.get("newWorkCreated") is False,
          "Original Work assignment to other Person regressed")
    check(sql(opt.db_url,
          f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")=="6",
          "An assignment/replay generated or destroyed original Work")
    check(sql(opt.db_url,
          f"select count(*) from atlas.work_allocations where work_item_id in ('{SELF_WORK}'::uuid,'{OTHER_WORK}'::uuid) and state='active'")=="2",
          "One exact allocation per original Work required")

    sql(opt.db_url,f"update atlas.principal_ledger_authorities set status='ended',ended_at=now() where id='{c1.ROOT_AUTHORITY}'::uuid")
    denied(api,key,root,ASSIGN,args("e5200000-0000-4000-8000-000000000972",SELF_PERSON,
           "e5200000-0000-4000-8000-000000000987"),
           "revoked root cannot assign")
    sql(opt.db_url,f"update atlas.principal_ledger_authorities set status='active',ended_at=null where id='{c1.ROOT_AUTHORITY}'::uuid")
    sql(opt.db_url,f"update ledger.seats set seat_state='ended',ended_at=now() where id='{c1.ROOT_SEAT}'::uuid")
    denied(api,key,root,CHOICES,dict(p_ledger_id=LEDGER,p_limit=1,p_after_person_id=None),
           "revoked seat cannot enumerate Persons")
    sql(opt.db_url,f"update ledger.seats set seat_state='active',ended_at=null where id='{c1.ROOT_SEAT}'::uuid")
    sql(opt.db_url,f"delete from auth.sessions where id='{sessions['owner'][1]['session_id']}'::uuid")
    denied(api,key,root,CHOICES,dict(p_ledger_id=LEDGER,p_limit=1,p_after_person_id=None),
           "revoked signed session cannot enumerate Persons")

    Path(opt.output).parent.mkdir(parents=True,exist_ok=True)
    Path(opt.output).write_text(
        "PASS genuine local GoTrue/REST native Person chooser, governor self-assignment, "
        "other Person assignment, no plan/duplicate, replay, forbidden actor/target, "
        "root/seat/session revocation\n",encoding="utf-8")
    print("PASS all genuine signed self-assignment proof cases")

if __name__=="__main__":
    main()

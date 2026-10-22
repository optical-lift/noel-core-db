#!/usr/bin/env python3
"""READ-ONLY worker prerequisite contract acceptance, disposable LOCAL Auth+REST.

Creates an original responsible allocation solely via the existing authenticated
Atlas connected-Ledger direct assignment API. Never fabricates an allocation,
pretends a membership/employee seat, calls production or sends actual mail.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "work_prerequisite_local_signed", HERE/"validate-atlas-work-prerequisite-signed-http.py")
original=importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)
c1=original.c1

ORG=c1.ORG
LEDGER=c1.LEDGER_A
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"
PREREQUISITE="e5200000-0000-4000-8000-000000000902"
UNASSIGNED="e5200000-0000-4000-8000-000000000903"
RPC="connected_person_work_prerequisites_self_api_v1"

def check(value,message): c1.check(value,message)
def sql(db,query): return c1.sql(db,query)
def call(api,key,token,name,body):
    return original.rpc(api,key,token,name,body)
def allow(api,key,token,name,body):
    return original.allow(api,key,token,name,body)
def deny(api,key,token,name,body,label):
    return original.deny(api,key,token,name,body,label)

def read(org,ledger,downstream):
    return dict(p_organization_id=org,p_ledger_id=ledger,
                p_downstream_work_item_id=downstream)

def verify_active(receipt,work_id,prereq_id):
    check(receipt.get("contractVersion")=="connected_person_work_prerequisites_v1",
          "Worker reader contractVersion incorrect")
    check(receipt.get("organizationId")==ORG and receipt.get("ledgerId")==LEDGER,
          "Worker reader wrong institution/Ledger")
    check(receipt.get("downstreamWorkItemId")==work_id and
          receipt.get("personId")==WORKER_PERSON,
          "Worker reader not scoped to authenticated recipient of original Work")
    check(receipt.get("sourceScope")=="original_responsible_person_downstream_work",
          "Worker reader scope is broader than exact responsible allocation")
    check(receipt.get("onlyCurrentLedgerEvidence") is True and
          receipt.get("activeRelationsOnly") is True and
          receipt.get("doesNotAuthorizeRelationChanges") is True and
          receipt.get("doesNotInferCompletionOrSatisfaction") is True,
          "Worker response implies authority or computed satisfaction")
    items=receipt.get("relations")
    check(isinstance(items,list) and len(items)==1,
          "Worker should read precisely one active original dependency")
    link=items[0]
    check(link.get("downstreamWorkItemId")==work_id and
          link.get("prerequisiteWorkItemId")==prereq_id and
          link.get("title")=="Clone work: replacement sprayer arrives" and
          link.get("relationKind")=="depends_on" and link.get("active") is True,
          "Wrong original Work relationship or title exposed to allocated worker")
    return link

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
          "Refuse all nonlocal database URLs")
    api,key=c1.local_status()
    identities=original.setup_auth(args.db_url)
    sessions={}
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),
              "Missing real signed Person/session identity")
        sessions[name]=(token,claims)
    worker=sessions["worker"][0]
    root=sessions["owner"][0]
    check(sessions["worker"][1].get("user_metadata",{}).get("is_owner") is True,
          "Worker fake editable owner metadata not present")

    # Actual original worker assignment is authored through the existing
    # direct assignment RPC. The canonical server itself creates Work,
    # Ledger relevance, allocation, execution plan and history.
    created=allow(api,key,root,"connected_ledger_direct_assign_self_api_v1",{
      "p_ledger_id":LEDGER,
      "p_recipient_person_id":WORKER_PERSON,
      "p_sentence":"Synthetic downstream work after replacement sprayer arrives",
      "p_execution_date":"2030-10-30",
      "p_source_action_id":"clone-worker-prereq-original-assignment"
    })
    work_id=created.get("workItemId")
    allocation_id=created.get("allocationId")
    check(created.get("contractVersion")=="ledger_connected_direct_assignment_v1"
          and created.get("createdNow") is True
          and created.get("employeeSeatRequired") is False
          and work_id and allocation_id,
          "Original direct-assignment receipt missing canonical Person/Work identity")
    check(sql(args.db_url,f"""
      select count(*) from atlas.work_allocations a
      join atlas.work_items w on w.id=a.work_item_id
      where a.id='{allocation_id}'::uuid
        and a.work_item_id='{work_id}'::uuid
        and a.assignee_canonical_person_id='{WORKER_PERSON}'::uuid
        and a.assignee_membership_id is null
        and a.establishment_basis_kind='ledger_connection_direct_assignment'
        and a.establishment_basis->>'nativeLedgerId'='{LEDGER}'
        and a.state='active' and w.work_state='open'
    """)=="1","Responsible native Person Work allocation was not source-created")
    print("PASS real direct Ledger Person assignment without employee seat")

    original_args=read(ORG,LEDGER,work_id)
    before=allow(api,key,worker,RPC,original_args)
    check(before.get("relations")==[],"Read-before-prerequisite must be genuinely empty")
    deny(api,key,worker,RPC,read(ORG,LEDGER,PREREQUISITE),
         "Connected Person cannot read a different, unassigned Work")
    deny(api,key,worker,RPC,read(ORG,LEDGER,UNASSIGNED),
         "Connected Person cannot browse other Ledger Work")
    deny(api,key,worker,RPC,read(ORG,c1.LEDGER_B,work_id),
         "One active native connection cannot read another Ledger")
    for name in ("outsider","no-seat"):
        deny(api,key,sessions[name][0],RPC,original_args,
             f"{name} cannot read assigned Person original Work")
    deny(api,key,None,RPC,original_args,"anonymous cannot read Person Work")
    deny(api,key,worker,"atlas_work_prerequisites_self_api_v1",original_args,
         "Worker stays forbidden from governing source reader")
    deny(api,key,worker,"atlas_set_work_prerequisite_self_api_v1",
         original.action(work_id,PREREQUISITE,True,"illegal-worker-write"),
         "Worker stays forbidden from governing relation mutation")
    print("PASS genuine member scope, outsider/seat/other Work denials")

    established=allow(api,key,root,"atlas_set_work_prerequisite_self_api_v1",
       original.action(work_id,PREREQUISITE,True,
                       "clone-worker-read-established-prerequisite"))
    link_id=established.get("relationId")
    check(link_id and established.get("active") is True,"Original owner link missing")
    view=allow(api,key,worker,RPC,original_args)
    relation=verify_active(view,work_id,PREREQUISITE)
    check(relation.get("relationId")==link_id,
          "Worker's relationship not the canonical original relation ID")
    print("PASS worker readback of source-backed original prerequisite title and ID")

    remove=allow(api,key,root,"atlas_set_work_prerequisite_self_api_v1",
       original.action(work_id,PREREQUISITE,False,
                       "clone-worker-read-withdraw-prerequisite",
                       "Original dependency no longer applies."))
    check(remove.get("relationId")==link_id and remove.get("active") is False,
          "Owner withdrawal did not preserve original relation")
    after=allow(api,key,worker,RPC,original_args)
    check(after.get("relations")==[],"Worker's current view retains withdrawn Work")
    check(sql(args.db_url,f"""
       select count(*) from atlas.work_item_relations
       where id='{link_id}'::uuid and active=false and relation_kind='depends_on'
    """)=="1","Canonical withdrawn history not preserved")
    print("PASS withdrawn relation disappears from worker current view, not history")

    # Revocation acts on real disposable native Ledger records and session.
    sql(args.db_url,f"""
      update ledger.seats set seat_state='ended',ended_at=now()
      where id='e5200000-0000-4000-8000-000000000502'::uuid""")
    deny(api,key,worker,RPC,original_args,"Ended Ledger connection denies worker")
    sql(args.db_url,f"""
      update ledger.seats set seat_state='active',ended_at=null
      where id='e5200000-0000-4000-8000-000000000502'::uuid""")
    sql(args.db_url,f"""
      delete from auth.sessions where id='{sessions["worker"][1]["session_id"]}'::uuid""")
    deny(api,key,worker,RPC,original_args,"Revoked real GoTrue session denies worker")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
       "PASS local-only genuine Person direct-assignment; current Work prerequisite read; denial matrix; withdrawal and Auth/seat revocation\n",
       encoding="utf-8")
    print("PASS genuine signed connected Person prerequisite projection")

if __name__=="__main__":
    main()

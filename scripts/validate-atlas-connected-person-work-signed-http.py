#!/usr/bin/env python3
"""Signed local GoTrue/PostgREST Work disclosure proof (C1 synthetic fixture).

Requires disposable full-schema clone with the already-established fixture
validation/fixtures/20261024231215_shared_native_ledger_standing_work_person_only_v1.sql
and the new Work-only reader candidate applied. NEVER operates on production.
No forged JWT or service-role substitution can count as signed proof.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "native_standing",HERE/"validate-shared-native-standing-work-signed-http.py")
standing=importlib.util.module_from_spec(spec)
spec.loader.exec_module(standing)
c1=standing.c1
base=standing.work
FN="connected_person_authorized_ledger_work_self_api_v1"
LEGACY_MY_WORK="connected_person_my_work_self_api_v1"

def need(ok,message):
    c1.check(ok,message)

def request(api,key,token,ledger):
    return c1.rpc(api,key,FN,{"p_ledger_id":ledger,"p_limit":100,
                              "p_after_allocation_id":None},token)

def my_work(api,key,token):
    # Existing shipped Atlas My Work path: separate from the held strict reader.
    return c1.rpc(api,key,LEGACY_MY_WORK,{
        "p_limit":100,"p_after_allocation_id":None},token)

def denied(api,key,token,ledger,label):
    status,data=request(api,key,token,ledger)
    need(status in (200,401,403),f"{label}: unexpected HTTP {status}")
    if status==200:
        need(isinstance(data,dict) and data=={"ok":False,"code":"not_found"},
             f"{label}: response must be uniform not_found (not leaked records)")
    print("PASS",label)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    need(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
        "Refuse nonlocal database URL")

    identities=base.setup_auth(a.db_url)
    api,key=c1.local_status()
    tokens={}
    for label,user_id in identities:
        token,claims=c1.sign_in(api,key,label)
        need(claims.get("sub")==user_id and bool(claims.get("session_id")),
             f"{label}: genuine GoTrue session required")
        need(c1.sql(a.db_url,f"select count(*) from auth.sessions "
             f"where id='{claims['session_id']}'::uuid "
             f"and user_id='{user_id}'::uuid")=="1",
             f"{label}: real session record missing")
        tokens[label]=(token,claims)

    # This fixture historically predated personal.atlases; add native personal
    # books for the disposable synthetic People. No real Person is changed.
    for person in (standing.WORKER_PERSON,
                   "e5200000-0000-4000-8000-000000000101",
                   "e5200000-0000-4000-8000-000000000103"):
        c1.sql(a.db_url,f"insert into personal.atlases(person_entity_id) "
               f"values('{person}'::uuid) on conflict(person_entity_id) do nothing")

    owner=tokens["owner"][0]
    worker=tokens["worker"][0]
    outsider=tokens["outsider"][0]
    no_seat=tokens["no-seat"][0]
    ledger=standing.LEDGER
    other_ledger="e5200000-0000-4000-8000-000000000402"

    need(c1.sql(a.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "No synthetic employee/member seats may exist")
    denied(api,key,None,ledger,"anonymous cannot read Work")
    denied(api,key,outsider,ledger,"other-Ledger Person cannot read Worker Work")
    denied(api,key,no_seat,ledger,"canonical Person with no native Seat denied")
    denied(api,key,worker,other_ledger,"connected Person cannot enumerate other Ledger")

    # Establish a REAL source-authorized native Work allocation using existing
    # root-governor proposal, independent worker acceptance, and signed assignment.
    scope=standing.allowed(api,key,owner,standing.PROPOSE,
                           standing.proposal(standing.WORKER_PERSON),
                           "governor proposes synthetic exact Ledger standing scope").get("scopeId")
    need(bool(scope),"Proposed scope identity missing")
    standing.allowed(api,key,worker,standing.ACCEPT,
                     {"p_scope_id":scope,"p_decision":"accept"},
                     "worker accepts separate signed native standing scope")
    assigned=standing.allowed(api,key,owner,standing.ASSIGN,
        standing.assignment(standing.TASK_A,scope),
        "governor assigns existing synthetic Work A without new Work")
    need(assigned.get("newWorkCreated") is False,
         "Read-boundary test unexpectedly created institutional Work")

    status,data=request(api,key,worker,ledger)
    need(status==200 and isinstance(data,dict) and data.get("ok") is True,
         f"Worker's signed positive read failed: {status}: {str(data)[:250]}")
    items=data.get("items")
    need(isinstance(items,list),"Worker items must be an array")
    ids={x.get("workItemId") for x in items if isinstance(x,dict)}
    need(standing.TASK_A in ids,"Authorized Work A missing (empty result is NOT a pass)")
    need(standing.TASK_B not in ids and
         "e5200000-0000-4000-8000-000000000903" not in ids,
         "Other unassigned Work leaked")
    allowed_fields={"workItemId","allocationId","ledgerId","title","workState",
                    "canReportOrdinaryCompletion"}
    need(all(isinstance(x,dict) and set(x)<=allowed_fields for x in items),
         "Undeclared institutional Work fields leaked")
    need(data.get("includesInstructions") is False and
         data.get("includesFarmSourceContext") is False and
         data.get("permissionAuditComplete") is False,
         "Projected Work made an unauthorized source-disclosure assertion")
    need("Owner-only validation movement" not in json.dumps(data),
         "Ledger owner-private history leaked")
    need("Clone work: replacement sprayer arrives" not in json.dumps(data),
         "Unassigned title leaked")

    # Gate 0 cannot be proved by installing a newly narrow RPC while the
    # existing public connected_person_my_work_self_api_v1 remains readable.
    # Both should return the actual accepted Work A and withhold source detail.
    old_status,old_data=my_work(api,key,worker)
    need(old_status==200 and isinstance(old_data,dict) and old_data.get("ok") is True,
         f"Existing My Work positive source read failed: {old_status}")
    old_items=old_data.get("items")
    need(isinstance(old_items,list),"Existing My Work list must be an array")
    old_ids={x.get("workItemId") for x in old_items if isinstance(x,dict)}
    need(standing.TASK_A in old_ids,
         "Secure My Work cutover removed truly assigned original Worker Work")
    need(standing.TASK_B not in old_ids,
         "Existing My Work list leaked unassigned original Work")
    need(all(x.get("workRelevanceVerified") is True for x in old_items),
         "Existing My Work included Work without proven exact Ledger relevance")
    need(all(x.get("instructions") is None for x in old_items),
         "Existing My Work leaked unapproved institutional Work instructions")
    print("PASS existing My Work matches authorized narrow-source boundary")

    # Genuine same-JWT deny as soon as the native Seat ends, then restore only
    # the synthetic Seat to isolate session revocation from Seat revocation.
    seat="e5200000-0000-4000-8000-000000000502"
    c1.sql(a.db_url,f"update ledger.seats set ended_at=now() where id='{seat}'::uuid")
    denied(api,key,worker,ledger,"ended native Seat denies retained worker JWT")
    c1.sql(a.db_url,f"update ledger.seats set ended_at=null where id='{seat}'::uuid")
    restored=request(api,key,worker,ledger)
    need(restored[0]==200 and restored[1].get("ok") is True,
         "Seat restoration did not isolate signed session test")

    # Simulate a revoked/removed exact Work relevance *in this disposable
    # clone only*, without deleting the Work identity or its allocation.
    # A Ledger connection and real active allocation alone cannot continue
    # disclosing a Work title after source attribution has been withdrawn.
    relevance_count=c1.sql(a.db_url,
        "select count(*) from atlas.company_work_native_ledger_relevance "
        f"where work_item_id='{standing.TASK_A}'::uuid "
        f"and ledger_id='{standing.LEDGER}'::uuid "
        "and attribution_state='active'")
    need(int(relevance_count)>0,"Synthetic Work relevance fixture absent")
    c1.sql(a.db_url,
        "delete from atlas.company_work_native_ledger_relevance "
        f"where work_item_id='{standing.TASK_A}'::uuid "
        f"and ledger_id='{standing.LEDGER}'::uuid")
    strict_lost=request(api,key,worker,ledger)
    need(strict_lost[0]==200 and isinstance(strict_lost[1],dict) and
         strict_lost[1].get("ok") is True and
         standing.TASK_A not in {
             x.get("workItemId") for x in strict_lost[1].get("items",[])
             if isinstance(x,dict)},
         "Strict reader still disclosed Work whose exact Ledger relevance ended")
    old_lost=my_work(api,key,worker)
    need(old_lost[0]==200 and isinstance(old_lost[1],dict) and
         old_lost[1].get("ok") is True and
         standing.TASK_A not in {
             x.get("workItemId") for x in old_lost[1].get("items",[])
             if isinstance(x,dict)},
         "OLDER PUBLIC MY WORK BYPASS: Work title/metadata returned after source relevance withdrawn")
    need(c1.sql(a.db_url,
         "select count(*) from atlas.work_items "
         f"where id='{standing.TASK_A}'::uuid and work_state='open'")=="1",
         "Negative disclosure test must not erase original Work")
    print("PASS legacy My Work loses an original Work when relevance is revoked")

    sid=tokens["worker"][1]["session_id"]
    c1.sql(a.db_url,f"delete from auth.sessions where id='{sid}'::uuid")
    denied(api,key,worker,ledger,"deleted GoTrue session denies retained valid JWT")
    old_revoked_status,old_revoked_data=my_work(api,key,worker)
    need(old_revoked_status in (401,403) or
         (old_revoked_status==200 and old_revoked_data=={"ok":False,"code":"not_found"}),
         "Old My Work must deny the SAME JWT after its genuine GoTrue session is revoked")
    need(c1.sql(a.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "Signed Work read created a prohibited employee membership")
    Path(a.output).write_text(
        "PASS local independent GoTrue owner/worker/outsider/no-seat; "
        "real signed Work scope acceptance and assignment; exact visible Work; "
        "withheld Work/title/source denied, including original My Work route; "
        "relevance-removal bypass closed; wrong-Ledger, ended Seat and "
        "revoked-session denials; no memberships or new Work.\n",
        encoding="utf-8")
    print("PASS source-isolated connected Person Work read on signed local clone")

if __name__=="__main__":
    main()

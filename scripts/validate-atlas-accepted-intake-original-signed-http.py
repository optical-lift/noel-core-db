#!/usr/bin/env python3
"""Protected disposable signed proof for post-v2 accepted original Ledger Work.

Run ONLY after C1 fictional fixture, reciprocal fixture, v2 review migration
and held compatibility candidate have all been installed on localhost clone.
No production API, person or Work may be touched by this script.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "ledger_v2_signed", HERE/"validate-atlas-ledger-intake-disposition-v2-signed-http.py")
v2=importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
base=v2.base
c1=v2.c1
ELM=c1.LEDGER_A
OTHER=c1.LEDGER_B
ORG="e5200000-0000-4000-8000-000000000801"
OWNER_PERSON="e5200000-0000-4000-8000-000000000101"
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"
SUBMIT="submit_ledger_work_self_api_v1"
OWNER_WORK="company_work_accountability_native_ledger_self_api_v1"
DIRECT="owner_direct_assign_existing_original_work_self_api_v1"
ELIGIBLE="accepted_ledger_intake_owner_assignment_source_self_api_v1"
STATUS="ledger_work_submission_status_self_api_v1"
PROPOSE="propose_native_ledger_exact_work_scope_owner_self_api_v1"
RESPOND="respond_native_ledger_standing_scope_self_api_v1"
ASSIGN_SCOPE="assign_native_ledger_company_work_under_scope_owner_self_api_v1"
MY_WORK="connected_person_my_work_self_api_v1"
REPORT="report_connected_person_company_work_self_api_v1"
PLACE="connected_person_place_work_self_api_v1"
UUID=re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",re.I)

def check(condition,message):v2.must(condition,message)
def allow(*args):return v2.allow(*args)
def deny(*args):return v2.deny(*args)
def sql(db,statement):return v2.sql(db,statement)
def work_page(api,key,token):
    status,out=base.rpc(api,key,token,OWNER_WORK,{
        "p_organization_id":ORG,"p_ledger_id":ELM,
        "p_scope":"native_ledger","p_limit":200,"p_after_work_item_id":None})
    # Established owner Work source is a source-verified packet without an
    # `ok` field. Do not retrofit a fabricated success property into its API.
    check(status==200 and isinstance(out,dict) and
          out.get("contractVersion")=="company_work_accountability_native_ledger_v1"
          and out.get("selectedNativeLedgerId")==ELM
          and isinstance(out.get("items"),list),
          "Expected source-authorized ordinary Ledger Work, not intake-only queue")
    return out["items"]
def mine(api,key,token,work):
    out=allow(api,key,token,MY_WORK,{"p_limit":100,"p_after_allocation_id":None})
    check(out.get("sourceScope")=="active_responsible_person_native_ledger_work",
          "My Work must be source-authoritative")
    found=[x for x in out.get("items",[]) if x.get("workItemId")==work]
    check(len(found)==1,f"Signed worker did not see exactly one original {work}")
    return found[0]
def submit(api,key,worker,action,title):
    r=allow(api,key,worker,SUBMIT,{
        "p_ledger_id":ELM,"p_title":title,
        "p_attention_date_proposal":"2026-11-05",
        "p_source_action_id":action})
    check(r.get("createdNow") is True and r.get("assignedToPerson") is False,
          "Submission must create exactly one original, not a Person assignment")
    check(UUID.fullmatch(r.get("intakeId","")) and UUID.fullmatch(r.get("workItemId","")),
          "Submitted original identifier must be canonical UUID")
    return r
def accepted(api,key,root,r,title):
    d=v2.review(api,key,root,r["intakeId"],"accepted_for_ledger",0,
                "Fictional original actionable by exact Ledger",
                title,"Fictional authorized operational instructions")
    check(d.get("workItemId")==r["workItemId"],"Acceptance changed original Work ID")
    return d
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(
       r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
       "This signed proof may only run on disposable localhost")
    api,key=c1.local_status()
    base.setup_auth(args.db_url)
    tokens={}
    for name,user in (("owner",c1.OWNER),("worker",c1.WORKER),
                      ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==user and claims.get("session_id"),
              "Independent real GoTrue session required for "+name)
        tokens[name]=token
    root=tokens["owner"]; worker=tokens["worker"]
    outsider=tokens["outsider"]; no_seat=tokens["no-seat"]
    before=sql(args.db_url,"SELECT count(*) FROM atlas.work_items")
    people=sql(args.db_url,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")

    a=submit(api,key,worker,"accepted-original-direct-001","Fictional direct obligation")
    b=submit(api,key,worker,"accepted-original-consent-002","Fictional scoped request")
    c=submit(api,key,worker,"accepted-original-never-reviewed-003",
             "Fictional pending alternate-evidence original")
    # Synthetic local database fixture: even if a second owner attestation is
    # associated with a pending original, review is a mandatory intake law.
    sql(args.db_url,
        "INSERT INTO atlas.company_work_native_ledger_relevance "
        "(organization_id,work_item_id,ledger_id,evidence_kind,"
        "attestation_source_ref,attestation_reason,established_by_person_id) "
        f"VALUES ('{ORG}'::uuid,'{c['workItemId']}'::uuid,'{ELM}'::uuid,"
        "'owner_attested','synthetic:pending-intake-bypass-attempt',"
        "'Disposable alternate evidence must not defeat final root review',"
        f"'{OWNER_PERSON}'::uuid)")
    check(all(x.get("workItemId") not in [a["workItemId"],b["workItemId"],c["workItemId"]]
              for x in work_page(api,key,root)),
          "PENDING intake leaked as approved native Ledger Work")
    for item in (a,b):
        pa={"p_organization_id":ORG,"p_ledger_id":ELM,
            "p_work_item_id":item["workItemId"]}
        deny(api,key,root,ELIGIBLE,pa,"pending original cannot be directly assigned")
        deny(api,key,root,DIRECT,{**pa,"p_target_person_id":WORKER_PERSON,
             "p_service_date":None,"p_action_id":"e5200000-0000-4000-8000-000000000a41",
             "p_reason":"Synthetic proposal pending governor review"},
             "pending intake cannot bypass root review")
    # Even an additional owner_attested relevance must not skip intake review.
    deny(api,key,root,PROPOSE,{
        "p_organization_id":ORG,"p_ledger_id":ELM,
        "p_worker_person_id":WORKER_PERSON,"p_work_item_id":c["workItemId"],
        "p_terms":"Synthetic alternate-attested pending intake must stay blocked",
        "p_valid_until":None},
        "alternate owner attestation cannot bypass exact intake review")
    # Pending participant attestation alone cannot authorize exact Work
    # standing consent, even under a real signed root.
    deny(api,key,root,PROPOSE,{
        "p_organization_id":ORG,"p_ledger_id":ELM,
        "p_worker_person_id":WORKER_PERSON,"p_work_item_id":b["workItemId"],
        "p_terms":"Synthetic unapproved original cannot create an assignable scope",
        "p_valid_until":None},
        "pending participant attestation cannot establish an accepted exact-Work scope")
    deny(api,key,worker,OWNER_WORK,{
        "p_organization_id":ORG,"p_ledger_id":ELM,"p_scope":"native_ledger",
        "p_limit":200,"p_after_work_item_id":None},"worker cannot inspect owner Ledger Work")
    deny(api,key,outsider,ELIGIBLE,{
        "p_organization_id":ORG,"p_ledger_id":ELM,"p_work_item_id":a["workItemId"]},
        "outsider cannot discover accepted source")
    deny(api,key,None,ELIGIBLE,{
        "p_organization_id":ORG,"p_ledger_id":ELM,"p_work_item_id":a["workItemId"]},
        "anonymous cannot discover exact Work")
    accepted(api,key,root,a,"Fictional direct accepted original")
    accepted(api,key,root,b,"Fictional consent accepted original")
    rows=work_page(api,key,root)
    for item in (a,b):
        selected=[x for x in rows if x.get("workItemId")==item["workItemId"]]
        check(len(selected)==1 and
              selected[0].get("responsibility",{}).get("allocationId") is None,
              "Accepted original should appear as ONE unassigned normal Ledger Work")
    current=allow(api,key,worker,STATUS,{"p_ledger_id":ELM,"p_limit":50,
        "p_after_created_at":None,"p_after_intake_id":None})
    check(current.get("contractVersion")=="ledger_work_submitter_status_v1"
          and {x.get("intakeId") for x in current.get("items",[])}.issuperset(
              {a["intakeId"],b["intakeId"]})
          and current.get("rootInboxDisclosed") is False,
          "Author-own submission status leaked or omitted source originals")
    for actor,label in ((outsider,"outsider"),(no_seat,"unconnected")):
        deny(api,key,actor,STATUS,{"p_ledger_id":ELM,"p_limit":50,
             "p_after_created_at":None,"p_after_intake_id":None},
             label+" cannot enumerate author status")
    directargs={"p_organization_id":ORG,"p_ledger_id":ELM,
        "p_work_item_id":a["workItemId"],"p_target_person_id":WORKER_PERSON,
        "p_service_date":None,"p_action_id":"e5200000-0000-4000-8000-000000000a42",
        "p_reason":"Synthetic direct obligation after exact acceptance"}
    d=allow(api,key,root,DIRECT,directargs)
    check(d.get("contractVersion")=="ledger_intake_direct_responsibility_v1"
          and d.get("workItemId")==a["workItemId"]
          and d.get("scheduleState")=="unscheduled"
          and d.get("newWorkCreated") is False
          and d.get("acceptanceQuestionCreated") is False
          and d.get("responsibilityEstablished") is True,
          "Direct obligation silently created a date, acceptance request or duplicate")
    idem=allow(api,key,root,DIRECT,directargs)
    check(idem.get("idempotent") is True
          and idem.get("allocationId")==d.get("allocationId"),
          "Exact replay must preserve original allocation")
    mine(api,key,worker,a["workItemId"])
    deny(api,key,worker,PLACE,{"p_work_item_id":a["workItemId"],
         "p_service_date":"2026-11-06","p_reason":"Unauthorized worker date change"},
         "responsibility does not delegate Company scheduling")
    scope=allow(api,key,root,PROPOSE,{
        "p_organization_id":ORG,"p_ledger_id":ELM,
        "p_worker_person_id":WORKER_PERSON,"p_work_item_id":b["workItemId"],
        "p_terms":"Synthetic bounded exact original Work responsibility",
        "p_valid_until":None})
    scopeid=scope.get("scopeId")
    check(isinstance(scopeid,str) and UUID.fullmatch(scopeid)
          and scope.get("workAssigned") is False
          and scope.get("workerConsentRecorded") is False,
          "Native proposal must not fabricate acceptance")
    deny(api,key,root,RESPOND,{"p_scope_id":scopeid,"p_decision":"accept"},
         "root cannot consent for independent Person")
    # This is a *state constraint*, not an identity/permission denial:
    # a legitimately signed governor must receive PostgreSQL 23514 while
    # consent is still proposed. Preserve the generic signed 42501 denial
    # helper for actual unauthorized callers.
    pre_allocations=sql(args.db_url,
        "SELECT count(*) FROM atlas.work_allocations "
        f"WHERE work_item_id='{b['workItemId']}'::uuid AND state='active'")
    rejection,body=base.rpc(api,key,root,ASSIGN_SCOPE,{
        "p_work_item_id":b["workItemId"],"p_scope_id":scopeid,
        "p_reason":"Synthetic unaccepted proposal cannot assign responsibility"})
    check(rejection==400 and isinstance(body,dict)
          and body.get("code")=="23514"
          and body.get("message")==
             "Open Work and currently accepted Person/Ledger standing scope required",
          "Unaccepted scope must fail via actual source-state constraint 23514")
    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_allocations "
       f"WHERE work_item_id='{b['workItemId']}'::uuid AND state='active'")==
       pre_allocations,"Rejected unaccepted scope changed original allocations")
    print("PASS denied unaccepted exact-Work scope without an allocation")
    consent=allow(api,key,worker,RESPOND,{"p_scope_id":scopeid,"p_decision":"accept"})
    check(consent.get("personConsentRecorded") is True
          and consent.get("assignmentCreated") is False,
          "Signed consent is not assignment")
    scoped=allow(api,key,root,ASSIGN_SCOPE,{
        "p_work_item_id":b["workItemId"],"p_scope_id":scopeid,
        "p_reason":"Synthetic assignment after independent Person consent"})
    check(scoped.get("workItemId")==b["workItemId"]
          and scoped.get("newWorkCreated") is False,
          "Consent path replaced original or created new Work")
    mine(api,key,worker,b["workItemId"])
    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_items")==
          str(int(before)+3),"Submission/assignment created shadow Work")
    check(sql(args.db_url,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")==people,
          "Submission created shadow People")

    # This is a real Result, not notification delivery or a comment.
    reported=allow(api,key,worker,REPORT,{"p_work_item_id":a["workItemId"],
        "p_result_kind":"blocked","p_idempotency_key":"signed-accepted-original-blocked-001",
        "p_payload":{"note":"Fictional blocker needs source-governed attention"}})
    check(reported.get("ok") is True,"Worker blocked Result not accepted by source")
    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_execution_results "
       f"WHERE work_item_id='{a['workItemId']}'::uuid AND result_kind='blocked'")=="1",
       "Worker blocked Result absent from original history")
    status=work_page(api,key,root)
    check(any(x.get("workItemId")==a["workItemId"] and x.get("latestWorkerReport")
              for x in status),"Governor Ledger Work does not expose Result history")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
       "PASS real signed clone: pending excluded, same original accepted, own status, "
       "source-denied outsiders, direct assignment unscheduled/idempotent, "
       "independent native Person consent and assignment, forbidden worker schedule, "
       "original blocked Result and no shadow Work/People. DISPOSABLE ONLY.\n")
    print("PASS accepted Ledger intake signed original lifecycle; NO production mutation")
if __name__=="__main__":main()

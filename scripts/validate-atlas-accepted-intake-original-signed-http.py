#!/usr/bin/env python3
"""Protected disposable signed proof for post-v2 accepted original Ledger Work.

Run ONLY after C1 fictional fixture, reciprocal fixture, v2 review migration
and held compatibility candidate have all been installed on localhost clone.
No production API, person or Work may be touched by this script.
"""
import argparse
import importlib.util
import re
import time
from concurrent.futures import ThreadPoolExecutor
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
NEEDS="ledger_accepted_original_needs_assignment_root_self_api_v1"
STATUS="ledger_work_submission_status_self_api_v1"
PROPOSE="propose_native_ledger_exact_work_scope_owner_self_api_v1"
RESPOND="respond_native_ledger_standing_scope_self_api_v1"
ASSIGN_SCOPE="assign_native_ledger_company_work_under_scope_owner_self_api_v1"
MY_WORK="connected_person_my_work_self_api_v1"
REPORT="report_connected_person_company_work_self_api_v1"
PLACE="connected_person_place_work_self_api_v1"
DELEGATE="decide_original_work_assignment_delegation_self_api_v1"
DELEGATION="original_work_assignment_delegation_self_api_v1"
UUID=re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",re.I)

def check(condition,message):v2.must(condition,message)
def allow(*args):return v2.allow(*args)
def deny(*args):return v2.deny(*args)
def sql(db,statement):return v2.sql(db,statement)
def assignment_snapshot(db,work):
    """Hash fictional original state, not private payloads in workflow output."""
    check(UUID.fullmatch(work or "") is not None,"Exact synthetic Work required")
    return sql(db,
        "SELECT md5(jsonb_build_object("
        "'work',(SELECT to_jsonb(w) FROM atlas.work_items w "
        f"WHERE w.id='{work}'::uuid),"
        "'allocations',(SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) "
        f"FROM atlas.work_allocations a WHERE a.work_item_id='{work}'::uuid),"
        "'plans',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) "
        f"FROM atlas.work_execution_plans p WHERE p.work_item_id='{work}'::uuid),"
        "'planEvents',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) "
        f"FROM atlas.work_execution_plan_events e WHERE e.work_item_id='{work}'::uuid),"
        "'standingScopes',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) "
        "FROM atlas.company_work_standing_assignment_scopes s "
        f"WHERE s.covered_work_item_id='{work}'::uuid),"
        "'intake',(SELECT to_jsonb(i) FROM atlas.ledger_work_intakes i "
        f"WHERE i.work_item_id='{work}'::uuid),"
        "'workCount',(SELECT count(*) FROM atlas.work_items),"
        "'peopleCount',(SELECT count(*) FROM reality.entities WHERE entity_kind='person'),"
        "'principalCount',(SELECT count(*) FROM atlas.principals))::text)")
def deny_assignment_without_change(db,api,key,actor,arguments,label):
    before=assignment_snapshot(db,arguments["p_work_item_id"])
    deny(api,key,actor,DIRECT,arguments,label)
    check(assignment_snapshot(db,arguments["p_work_item_id"])==before,
          "Denied original-Work assignment changed durable state: "+label)
def reject_assignment_without_change(db,api,key,actor,arguments,source_code,label):
    before=assignment_snapshot(db,arguments["p_work_item_id"])
    status,out=base.rpc(api,key,actor,DIRECT,arguments)
    check(status in (400,409) and isinstance(out,dict) and out.get("code")==source_code,
          "Expected actual source constraint "+source_code+": "+label)
    check(assignment_snapshot(db,arguments["p_work_item_id"])==before,
          "Rejected assignment changed durable state: "+label)
def delegation_state(api,key,worker):
    out=allow(api,key,worker,DELEGATION,{"p_organization_id":ORG,"p_ledger_id":ELM})
    check(out.get("contractVersion")=="original_work_assignment_delegation_self_v1"
          and out.get("personId")==WORKER_PERSON
          and out.get("operation")=="assign_accepted_original_work"
          and out.get("assignmentWriterEnabled") is True
          and out.get("rosterDisclosed") is False and out.get("workDisclosed") is False,
          "Self-only delegation source must describe only the integrated assignment operation")
    return out
def delegation_lifecycle(db,api,key,root,worker,outsider,no_seat,directargs):
    """Preserve R02A administration proof while R02B consumes the grant."""
    table="atlas.ledger_original_work_assignment_delegation_events_v1"
    work=directargs["p_work_item_id"]
    unchanged=assignment_snapshot(db,work)
    future=sql(db,"SELECT (clock_timestamp()+interval '1 day')::text")
    def decision(revision,kind,n,expiry=None):
        return {"p_organization_id":ORG,"p_ledger_id":ELM,
                "p_delegate_person_id":WORKER_PERSON,"p_decision":kind,
                "p_expected_revision":revision,"p_valid_until":expiry,
                "p_action_id":"e5200000-0000-4000-8000-"+f"{0xb000+n:012x}",
                "p_reason":"Fictional exact Ledger assignment authority decision"}
    initial=delegation_state(api,key,worker)
    check(initial.get("revision")==0 and initial.get("grantEffective") is False,
          "Connection/metadata/other Ledger root must not fabricate delegation")
    grant=decision(0,"grant",1,future)
    for token,label in ((worker,"worker/another Ledger root"),(outsider,"outsider"),
                        (no_seat,"unconnected"),(None,"anonymous")):
        deny(api,key,token,DELEGATE,grant,label+" cannot issue an assignment grant")
    for token,label in ((outsider,"outsider"),(no_seat,"unconnected"),(None,"anonymous")):
        deny(api,key,token,DELEGATION,{"p_organization_id":ORG,"p_ledger_id":ELM},
             label+" cannot inspect another Ledger's grants")
    deny(api,key,root,DELEGATE,{**grant,"p_ledger_id":OTHER},
         "a root on one Ledger cannot administer another Ledger's grants")
    deny(api,key,root,DELEGATE,{**grant,
         "p_delegate_person_id":"e5200000-0000-4000-8000-000000000103"},
         "grant target must have the current exact native connection")
    check(sql(db,f"SELECT count(*) FROM {table}")=="0",
          "Denied grant attempts appended authority")
    receipt=allow(api,key,root,DELEGATE,grant)
    check(receipt.get("contractVersion")=="original_work_assignment_delegation_decision_v1"
          and receipt.get("revision")==1 and receipt.get("decision")=="grant"
          and receipt.get("currentlyEffective") is True
          and receipt.get("actorPersonId")==OWNER_PERSON
          and receipt.get("delegatePersonId")==WORKER_PERSON
          and receipt.get("operation")=="assign_accepted_original_work"
          and receipt.get("assignmentWriterEnabled") is True
          and all(receipt.get(k) is False for k in
                  ("workCreated","allocationCreated","planCreated","rootAuthorityCreated")),
          "Signed grant receipt widened scope or claimed an operational effect")
    event=receipt.get("eventId")
    check(UUID.fullmatch(event or "") is not None,"Canonical grant event required")
    own=delegation_state(api,key,worker)
    check(own.get("grantEffective") is True and own.get("eventId")==event,
          "Independent signed Person cannot reread the grant")
    root_self=allow(api,key,root,DELEGATION,{"p_organization_id":ORG,"p_ledger_id":ELM})
    check(root_self.get("revision")==0 and root_self.get("eventId") is None,
          "Self-only reader exposed the governor's target's grant")
    idem=allow(api,key,root,DELEGATE,grant)
    check(idem.get("idempotent") is True and idem.get("eventId")==event
          and sql(db,f"SELECT count(*) FROM {table}")=="1",
          "Exact grant replay duplicated authority history")
    code,body=base.rpc(api,key,root,DELEGATE,{**grant,"p_reason":"Changed fictional retry"})
    check(code==409 and body.get("code")=="23505","Grant action collision must source-reject")
    v2.stale(api,key,root,DELEGATE,decision(0,"revoke",2),
             "stale grant revision cannot overwrite history")
    # Actual concurrent signed decisions over the same source revision.
    with ThreadPoolExecutor(max_workers=2) as pool:
        attempts=list(pool.map(lambda n:base.rpc(api,key,root,DELEGATE,
                         decision(1,"revoke",n)),(3,4)))
    successes=[obj for code,obj in attempts if code==200 and obj.get("ok") is True]
    stale=[obj for code,obj in attempts if code in (400,409,500) and obj.get("code")=="40001"]
    check(len(successes)==1 and successes[0].get("revision")==2 and len(stale)==1,
          "Concurrent grant decisions must yield one revision and one genuine stale rejection")
    own=delegation_state(api,key,worker)
    check(own.get("grantEffective") is False and own.get("decision")=="revoke"
          and own.get("revision")==2,"Revocation failed to suppress prior grant")
    deny_assignment_without_change(db,api,key,worker,directargs,
        "revoked delegate cannot enter the actual assignment writer")
    # Even DB-owner writes cannot erase or amend original decision evidence.
    sql(db,f"""DO $immutable$ BEGIN
      BEGIN UPDATE {table} SET reason='Changed immutable fictional decision'
        WHERE id='{event}'::uuid;
        RAISE EXCEPTION 'Delegation UPDATE immutability was not enforced';
      EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
      BEGIN DELETE FROM {table} WHERE id='{event}'::uuid;
        RAISE EXCEPTION 'Delegation DELETE immutability was not enforced';
      EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
      BEGIN TRUNCATE {table};
        RAISE EXCEPTION 'Delegation TRUNCATE immutability was not enforced';
      EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
    END $immutable$;""")
    regrant=allow(api,key,root,DELEGATE,decision(2,"grant",5,future))
    check(regrant.get("revision")==3 and regrant.get("currentlyEffective") is True,
          "A new signed decision must establish a new auditable grant epoch")
    reject_assignment_without_change(db,api,key,worker,directargs,"23505",
        "a genuine delegate cannot claim a prior root's assignment action")
    # Only fictional local fixture connectivity is changed/restored here.
    sql(db,"UPDATE ledger.seats SET seat_state='ended',ended_at=now() "
        f"WHERE ledger_id='{ELM}'::uuid AND person_entity_id='{WORKER_PERSON}'::uuid")
    try:
        deny(api,key,worker,DELEGATION,{"p_organization_id":ORG,"p_ledger_id":ELM},
             "ended connection denies grant readback with the same valid JWT")
        deny_assignment_without_change(db,api,key,worker,directargs,
            "ended connection denies assignment with the same JWT")
        deny(api,key,root,DELEGATE,decision(3,"grant",6,future),
             "disconnected target cannot receive another grant")
        revoked=allow(api,key,root,DELEGATE,decision(3,"revoke",7))
        check(revoked.get("revision")==4,"Root must be able to revoke a disconnected Person")
    finally:
        sql(db,"UPDATE ledger.seats SET seat_state='active',ended_at=NULL "
            f"WHERE ledger_id='{ELM}'::uuid AND person_entity_id='{WORKER_PERSON}'::uuid")
    own=delegation_state(api,key,worker)
    check(own.get("revision")==4 and own.get("grantEffective") is False,
          "Reconnection resurrected an older revoked grant")
    expiry=sql(db,"SELECT (clock_timestamp()+interval '12 seconds')::text")
    expiring=decision(4,"grant",8,expiry)
    expiring_receipt=allow(api,key,root,DELEGATE,expiring)
    stop=time.monotonic()+24
    while True:
        own=delegation_state(api,key,worker)
        if own.get("grantEffective") is False:break
        check(time.monotonic()<stop,"Grant expiry failed at source")
        time.sleep(0.5)
    check(own.get("revision")==5 and own.get("eventId")==expiring_receipt.get("eventId"),
          "Expiry must retain the newest decision, never revive older authority")
    deny_assignment_without_change(db,api,key,worker,directargs,
        "expired delegate cannot replay an assignment through the actual writer")
    expired_replay=allow(api,key,root,DELEGATE,expiring)
    check(expired_replay.get("idempotent") is True
          and expired_replay.get("eventId")==expiring_receipt.get("eventId")
          and expired_replay.get("currentlyEffective") is False,
          "Replay renewed an expired grant")
    final=allow(api,key,root,DELEGATE,decision(5,"grant",9))
    check(final.get("revision")==6 and final.get("currentlyEffective") is True,
          "Explicit revocation-lifetime grant must be recorded as a new epoch")
    check(sql(db,f"SELECT count(*) FROM {table}")=="6",
          "Replay/collision/concurrency lost or duplicated grant decisions")
    check(assignment_snapshot(db,work)==unchanged,
          "Grant lifecycle changed Work/Person/allocation/plan/consent state")
    print("PASS native grant/revoke, self-only signed readback, CAS/concurrency, expiry, "
          "immutable history, connection withdrawal, no Work effects from administration")
def delegated_assignment_lifecycle(db,api,key,root,worker,claims,pending):
    """R02B: real signed nonroot execution of the existing source operation."""
    first=submit(api,key,worker,"accepted-original-delegated-004","Fictional delegated original")
    second=submit(api,key,worker,"accepted-original-delegated-005","Fictional next-epoch original")
    for item in (first,second):accepted(api,key,root,item,"Fictional accepted delegated original")
    work_count=sql(db,"SELECT count(*) FROM atlas.work_items")
    people_count=sql(db,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")
    principal_count=sql(db,"SELECT count(*) FROM atlas.principals")
    plan_count=sql(db,"SELECT count(*) FROM atlas.work_execution_plans")
    plan_event_count=sql(db,"SELECT count(*) FROM atlas.work_execution_plan_events")
    grant=delegation_state(api,key,worker)
    check(grant.get("revision")==6 and grant.get("grantEffective") is True,
          "Need the independently signed current grant, not a fabricated permission row")
    arguments={"p_organization_id":ORG,"p_ledger_id":ELM,
        "p_work_item_id":first["workItemId"],"p_target_person_id":OWNER_PERSON,
        "p_service_date":None,"p_action_id":"e5200000-0000-4000-8000-000000000c01",
        "p_reason":"Fictional delegated accepted-original direct obligation"}
    deny_assignment_without_change(db,api,key,worker,{**arguments,"p_ledger_id":OTHER},
        "an exact ELM grant cannot authorize the other Ledger")
    deny_assignment_without_change(db,api,key,worker,
        {**arguments,"p_work_item_id":pending["workItemId"]},
        "delegation cannot bypass pending intake even with alternate owner attestation")
    deny_assignment_without_change(db,api,key,worker,
        {**arguments,"p_work_item_id":"e5200000-0000-4000-8000-000000000971"},
        "accepted-intake assignment delegation cannot authorize decomposed Subject Work")
    deny_assignment_without_change(db,api,key,worker,
        {**arguments,"p_service_date":"2026-11-06"},
        "delegated assignment cannot create an execution plan")
    for name,payload in (
        (OWNER_WORK,{"p_organization_id":ORG,"p_ledger_id":ELM,"p_scope":"native_ledger",
                     "p_limit":200,"p_after_work_item_id":None}),
        (NEEDS,{"p_ledger_id":ELM,"p_limit":50,"p_after_work_item_id":None}),
        (ELIGIBLE,{"p_organization_id":ORG,"p_ledger_id":ELM,
                   "p_work_item_id":first["workItemId"]})):
        deny(api,key,worker,name,payload,"assignment grant cannot widen root reader "+name)
    deny(api,key,worker,DELEGATE,{"p_organization_id":ORG,"p_ledger_id":ELM,
        "p_delegate_person_id":OWNER_PERSON,"p_decision":"grant","p_expected_revision":0,
        "p_valid_until":None,"p_action_id":"e5200000-0000-4000-8000-000000000b11",
        "p_reason":"Fictional delegate cannot grant onward authority"},
        "assignment delegation is not grant administration")
    receipt=allow(api,key,worker,DIRECT,arguments)
    check(receipt.get("contractVersion")=="ledger_intake_direct_responsibility_v1"
          and receipt.get("workItemId")==first["workItemId"]
          and receipt.get("targetPersonId")==OWNER_PERSON
          and receipt.get("authorizationBasis")=="delegated_exact_existing_accepted_original_work_v1"
          and receipt.get("delegationEventId")==grant.get("eventId")
          and receipt.get("scheduleState")=="unscheduled" and receipt.get("planId") is None
          and receipt.get("assignmentNew") is True
          and all(receipt.get(k) is False for k in
              ("newWorkCreated","newTaskCreated","acceptanceQuestionCreated","employeeSeatRequired")),
          "Delegate did not establish exactly one unscheduled same-original responsibility")
    allocation=receipt.get("allocationId")
    check(UUID.fullmatch(allocation or "") is not None,"Canonical allocation required")
    check(sql(db,"SELECT count(*) FROM atlas.work_allocations a "
        "JOIN atlas.ledger_original_work_assignment_delegation_events_v1 e "
        "ON e.id::text=a.establishment_basis->>'delegationEventId' "
        f"WHERE a.id='{allocation}'::uuid AND e.id='{grant['eventId']}'::uuid "
        "AND e.revision=6 AND e.decision='grant' "
        f"AND e.actor_person_id='{OWNER_PERSON}'::uuid "
        f"AND e.delegate_person_id='{WORKER_PERSON}'::uuid "
        f"AND a.establishment_basis->>'senderPersonId'='{WORKER_PERSON}' "
        f"AND a.assignee_canonical_person_id='{OWNER_PERSON}'::uuid "
        "AND a.assignee_membership_id IS NULL AND a.assigned_by_membership_id IS NULL")=="1",
        "Allocation lost independently signed actor, grant epoch or Person-native provenance")
    idem=allow(api,key,worker,DIRECT,arguments)
    check(idem.get("idempotent") is True and idem.get("allocationId")==allocation
          and idem.get("delegationEventId")==grant["eventId"],"Delegate retry is not stable")
    mine(api,key,root,first["workItemId"])
    reject_assignment_without_change(db,api,key,worker,
        {**arguments,"p_reason":"Changed fictional delegated retry"},"23505",
        "changed retry cannot replace signed decision")
    reject_assignment_without_change(db,api,key,root,arguments,"23505",
        "a root cannot claim another signed actor's assignment receipt")
    reject_assignment_without_change(db,api,key,worker,
        {**arguments,"p_target_person_id":WORKER_PERSON},"23514",
        "delegate cannot replace an existing responsibility")
    sql(db,"UPDATE ledger.seats SET seat_state='ended',ended_at=now() "
        f"WHERE ledger_id='{ELM}'::uuid AND person_entity_id='{WORKER_PERSON}'::uuid")
    try:deny_assignment_without_change(db,api,key,worker,arguments,
        "disconnection denies replay of the delegate's own successful action")
    finally:sql(db,"UPDATE ledger.seats SET seat_state='active',ended_at=NULL "
        f"WHERE ledger_id='{ELM}'::uuid AND person_entity_id='{WORKER_PERSON}'::uuid")
    session=claims["session_id"]
    check(UUID.fullmatch(session) is not None,"Real signed session required")
    old_expiry=sql(db,f"SELECT quote_nullable(not_after) FROM auth.sessions WHERE id='{session}'::uuid")
    sql(db,f"UPDATE auth.sessions SET not_after=now()-interval '1 minute' WHERE id='{session}'::uuid")
    try:deny_assignment_without_change(db,api,key,worker,arguments,
        "expired session denies own assignment replay while grant and issuer remain active")
    finally:sql(db,f"UPDATE auth.sessions SET not_after={old_expiry} WHERE id='{session}'::uuid")
    control={"p_organization_id":ORG,"p_ledger_id":ELM,"p_delegate_person_id":WORKER_PERSON,
        "p_decision":"revoke","p_expected_revision":6,"p_valid_until":None,
        "p_action_id":"e5200000-0000-4000-8000-000000000b12",
        "p_reason":"Fictional revoke after delegated assignment proof"}
    allow(api,key,root,DELEGATE,control)
    deny_assignment_without_change(db,api,key,worker,arguments,
        "signed revocation denies retry of a previously successful delegated assignment")
    new_grant=allow(api,key,root,DELEGATE,{**control,"p_decision":"grant",
        "p_expected_revision":7,"p_action_id":"e5200000-0000-4000-8000-000000000b13"})
    check(new_grant.get("revision")==8 and new_grant.get("eventId")!=grant["eventId"],
          "Regrant must preserve a distinct decision epoch")
    reject_assignment_without_change(db,api,key,worker,arguments,"23505",
        "new grant epoch cannot impersonate a prior allocation decision")
    next_arguments={**arguments,"p_work_item_id":second["workItemId"],
        "p_action_id":"e5200000-0000-4000-8000-000000000c02"}
    competing={**next_arguments,"p_action_id":"e5200000-0000-4000-8000-000000000c03"}
    with ThreadPoolExecutor(max_workers=2) as pool:
        attempts=list(pool.map(lambda a:base.rpc(api,key,worker,DIRECT,a),
                               (next_arguments,competing)))
    successes=[(a,out) for a,(status,out) in zip((next_arguments,competing),attempts)
               if status==200 and out.get("ok") is True]
    rejected=[out for status,out in attempts if status==400 and out.get("code")=="23514"]
    check(len(successes)==1 and len(rejected)==1
          and successes[0][1].get("delegationEventId")==new_grant["eventId"],
          "Competing delegated actions must establish only one auditable responsibility")
    for item in (first,second):
        check(sql(db,"SELECT count(*) FROM atlas.work_allocations "
            f"WHERE work_item_id='{item['workItemId']}'::uuid AND state='active' "
            "AND allocation_role='responsible'")=="1","Duplicate responsibility after delegated execution")
    check(sql(db,"SELECT count(*) FROM atlas.work_items")==work_count
          and sql(db,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")==people_count
          and sql(db,"SELECT count(*) FROM atlas.principals")==principal_count
          and sql(db,"SELECT count(*) FROM atlas.work_execution_plans")==plan_count
          and sql(db,"SELECT count(*) FROM atlas.work_execution_plan_events")==plan_event_count,
          "Delegated assignment created Work/People/Principals or implicit plans/events")
    print("PASS signed native delegate same-original unscheduled assignment, exact grant provenance, "
          "retry/actor/epoch isolation, concurrent responsibility, withdrawn authority, no reader elevation")
    return successes[0][0]

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
    signed_claims={}
    for name,user in (("owner",c1.OWNER),("worker",c1.WORKER),
                      ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==user and claims.get("session_id"),
              "Independent real GoTrue session required for "+name)
        tokens[name]=token
        signed_claims[name]=claims
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
    needsargs={"p_ledger_id":ELM,"p_limit":1,"p_after_work_item_id":None}
    initial=allow(api,key,root,NEEDS,needsargs)
    check(initial.get("contractVersion")=="ledger_accepted_original_needs_assignment_v1"
          and initial.get("totalNeedsAssignment")==0 and initial.get("items")==[]
          and initial.get("hasMore") is False,
          "Pending originals, including alternate-attested pending original, must be excluded")
    for actor,label in ((worker,"worker"),(outsider,"outsider"),
                        (no_seat,"unconnected"),(None,"anonymous")):
        deny(api,key,actor,NEEDS,needsargs,label+" cannot discover Needs Assignment")
    accepted(api,key,root,a,"Fictional direct accepted original")
    accepted(api,key,root,b,"Fictional consent accepted original")
    rows=work_page(api,key,root)
    for item in (a,b):
        selected=[x for x in rows if x.get("workItemId")==item["workItemId"]]
        check(len(selected)==1 and
              selected[0].get("responsibility",{}).get("allocationId") is None,
              "Accepted original should appear as ONE unassigned normal Ledger Work")
    first=allow(api,key,root,NEEDS,needsargs)
    check(first.get("totalNeedsAssignment")==2
          and first.get("returnedCount")==1
          and first.get("hasMore") is True
          and len(first.get("items",[]))==1
          and first["items"][0].get("assignedToPerson") is False,
          "Exact root Needs Assignment must return one paged accepted original")
    cursor=first.get("nextWorkItemId")
    check(UUID.fullmatch(cursor or "") is not None
          and first["items"][0].get("workItemId")==cursor,
          "Needs Assignment cursor must identify the exact original")
    second=allow(api,key,root,NEEDS,{**needsargs,"p_after_work_item_id":cursor})
    found=first["items"]+second.get("items",[])
    check(second.get("totalNeedsAssignment")==2
          and second.get("returnedCount")==1
          and second.get("hasMore") is False
          and {x.get("workItemId") for x in found}==
              {a["workItemId"],b["workItemId"]}
          and all(x.get("intakeId") in {a["intakeId"],b["intakeId"]}
                  and x.get("workState")=="open" for x in found),
          "Exact Needs Assignment collection must paginate without pending or duplicate Work")
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
    # The worker is already a genuine root of OTHER, and GoTrue really signed
    # their user-editable owner metadata. Neither is exact ELM delegation.
    check(signed_claims["worker"].get("user_metadata",{}).get("is_owner") is True,
          "Missing genuine signed spoofable metadata negative fixture")
    check(sql(args.db_url,"SELECT count(*) FROM atlas.principal_ledger_authorities a "
       "JOIN atlas.principals p ON p.id=a.principal_id "
       f"WHERE p.person_id='{WORKER_PERSON}'::uuid AND a.ledger_id='{OTHER}'::uuid "
       "AND p.status='active' AND a.status='active' AND a.ended_at IS NULL")=="1",
       "Worker must have real independent root authority on the other Ledger")
    for actor,label in ((worker,"connected worker with owner metadata and another Ledger root"),
                        (outsider,"outsider"),(no_seat,"unconnected Person"),
                        (None,"anonymous")):
        deny_assignment_without_change(args.db_url,api,key,actor,directargs,
            label+" cannot assign an accepted original without exact authority")
    deny_assignment_without_change(args.db_url,api,key,worker,
        {**directargs,"p_ledger_id":OTHER},
        "another Ledger root cannot relabel the accepted original's Ledger")
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
    direct_needs=allow(api,key,root,NEEDS,{**needsargs,"p_limit":50})
    check(direct_needs.get("totalNeedsAssignment")==1
          and [x.get("workItemId") for x in direct_needs.get("items",[])]==
              [b["workItemId"]],
          "Direct responsibility must remove only its original from Needs Assignment")
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
    # Accepting responsibility is not receiving governor authority. Exercise
    # the actual signed direct writer, not just a hidden UI or list endpoint.
    deny_assignment_without_change(args.db_url,api,key,worker,
        {**directargs,"p_work_item_id":b["workItemId"],
         "p_target_person_id":OWNER_PERSON,
         "p_action_id":"e5200000-0000-4000-8000-000000000a43"},
        "accepted exact-Work responsibility scope is not assignment delegation")
    scope_snapshot=assignment_snapshot(args.db_url,b["workItemId"])
    deny(api,key,worker,ASSIGN_SCOPE,{
        "p_work_item_id":b["workItemId"],"p_scope_id":scopeid,
        "p_reason":"Synthetic recipient cannot act as assigning governor"},
        "consenting recipient cannot invoke the governor scope-assignment writer")
    check(assignment_snapshot(args.db_url,b["workItemId"])==scope_snapshot,
          "Denied recipient scope-assignment changed original state")
    scoped=allow(api,key,root,ASSIGN_SCOPE,{
        "p_work_item_id":b["workItemId"],"p_scope_id":scopeid,
        "p_reason":"Synthetic assignment after independent Person consent"})
    check(scoped.get("workItemId")==b["workItemId"]
          and scoped.get("newWorkCreated") is False,
          "Consent path replaced original or created new Work")
    final_needs=allow(api,key,root,NEEDS,{**needsargs,"p_limit":50})
    check(final_needs.get("totalNeedsAssignment")==0
          and final_needs.get("items")==[]
          and final_needs.get("hasMore") is False,
          "Exact consent assignment must remove its original, not create a shadow task")
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
    delegation_lifecycle(args.db_url,api,key,root,worker,outsider,no_seat,directargs)
    delegate_arguments=delegated_assignment_lifecycle(args.db_url,api,key,root,worker,
        signed_claims["worker"],c)
    # Fixture-only authority revocation, with the SAME still-existing signed
    # GoTrue session. No restore/regrant or production authority mutation.
    root_authority=sql(args.db_url,
        "SELECT a.id::text FROM atlas.principal_ledger_authorities a "
        "JOIN atlas.principals p ON p.id=a.principal_id "
        f"WHERE p.person_id='{OWNER_PERSON}'::uuid AND a.ledger_id='{ELM}'::uuid "
        "AND a.authority_kind='root_governing' AND a.status='active' "
        "AND a.ended_at IS NULL")
    check(UUID.fullmatch(root_authority or "") is not None,
          "Expected one exact synthetic root authority to revoke")
    sql(args.db_url,"UPDATE atlas.principal_ledger_authorities "
        f"SET status='ended',ended_at=now() WHERE id='{root_authority}'::uuid "
        "AND status='active'")
    root_session=signed_claims["owner"]["session_id"]
    check(UUID.fullmatch(root_session) is not None,"Exact genuine session required")
    check(sql(args.db_url,"SELECT count(*) FROM auth.sessions "
       f"WHERE id='{root_session}'::uuid AND user_id='{c1.OWNER}'::uuid")=="1",
       "Authority revocation proof must retain the genuine signed session")
    deny_assignment_without_change(args.db_url,api,key,root,directargs,
        "ended exact Ledger root cannot replay a former assignment with a valid session")
    check(delegation_state(api,key,worker).get("grantEffective") is False,
          "Grantor root withdrawal failed to invalidate the still-recorded grant")
    deny_assignment_without_change(args.db_url,api,key,worker,delegate_arguments,
        "ended grantor authority denies replay of the delegate's successful assignment")
    worker_session=signed_claims["worker"]["session_id"]
    check(UUID.fullmatch(worker_session) is not None,"Exact signed delegate session required")
    sql(args.db_url,"UPDATE auth.sessions SET not_after=now()-interval '1 minute' "
        f"WHERE id='{worker_session}'::uuid AND user_id='{c1.WORKER}'::uuid")
    deny(api,key,worker,DELEGATION,{"p_organization_id":ORG,"p_ledger_id":ELM},
         "ended delegate session denies readback despite unexpired JWT")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
       "PASS real signed clone: pending excluded, same original accepted, own status, "
       "source-denied outsiders, direct assignment unscheduled/idempotent, "
       "independent native Person consent and assignment, forbidden worker schedule, "
       "original blocked Result, no shadow Work/People, source-denied assignment by "
       "metadata/other-Ledger roots/consenting recipients/ended roots, unchanged denied "
       "Work/allocation/plan state. Native grant/revoke and self-only status, immutable "
       "history, replay/CAS/concurrency, expiry, connection/grantor/session withdrawal "
       "PASS; no Work effects from grant administration. R02B signed nonroot delegate "
       "same-original unscheduled assignment and grant provenance PASS; actor/epoch/retry isolation, "
       "concurrent single responsibility, source-denied pending/wrong-Ledger/scheduling/reader elevation "
       "and revoked/disconnected/expired-session/ended-issuer replay PASS. No shadow Work/People or "
       "implicit plans. Atlas capability/UI, broader permissions, browser and release remain HELD. "
       "DISPOSABLE ONLY.\n")
    print("PASS accepted Ledger intake signed original lifecycle; NO production mutation")
if __name__=="__main__":main()

#!/usr/bin/env python3
"""Signed local GoTrue/PostgREST Work disclosure proof (C1 synthetic fixture).

Requires disposable full-schema clone with the held governor-review candidate,
three original Person-reader source cutovers and the already-established fixture
validation/fixtures/20261024231215_shared_native_ledger_standing_work_person_only_v1.sql
and the new Work-only reader candidate applied. NEVER operates on production.
No forged JWT or service-role substitution can count as signed proof.
"""
import argparse
import importlib.util
import hashlib
import json
import re
import uuid
from datetime import date, timedelta
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
ORIGINAL_TODAY="connected_person_company_work_today_self_api_v1"
ORIGINAL_DATED="connected_person_company_work_day_self_api_v1"
GOVERNOR_REVIEW="connected_person_effective_disclosure_review_self_api_v1"
GOVERNOR_DECIDE="governor_decide_connected_person_work_field_self_api_v1"
APPROVED_FIELDS="connected_person_work_approved_fields_self_api_v1"
SYNTHETIC_PRIVATE_INSTRUCTIONS="Clone private instructions — governor field review only"

def need(ok,message):
    c1.check(ok,message)

def request(api,key,token,ledger):
    return c1.rpc(api,key,FN,{"p_ledger_id":ledger,"p_limit":100,
                              "p_after_allocation_id":None},token)

def my_work(api,key,token):
    # Existing shipped Atlas My Work path: separate from the held strict reader.
    return c1.rpc(api,key,LEGACY_MY_WORK,{
        "p_limit":100,"p_after_allocation_id":None},token)

def original_today(api,key,token):
    # Distinct existing all-date Today RPC; its own source must be secure.
    return c1.rpc(api,key,ORIGINAL_TODAY,{"p_limit":100},token)

def dated_work(api,key,token,day):
    return c1.rpc(api,key,ORIGINAL_DATED,{"p_date":day},token)

def governor_review(api,key,token,ledger,person):
    return c1.rpc(api,key,GOVERNOR_REVIEW,{
        "p_ledger_id":ledger,"p_person_entity_id":person},token)

def decide_field(api,key,token,ledger,work,person,field,decision,reason,
                 expected=None,request_id=None):
    return c1.rpc(api,key,GOVERNOR_DECIDE,{
        "p_ledger_id":ledger,"p_work_item_id":work,
        "p_person_entity_id":person,"p_field_key":field,
        "p_decision":decision,"p_reason":reason,
        "p_request_id":request_id or str(uuid.uuid4()),
        "p_expected_value_sha256":expected,"p_valid_until":None},token)

def approved_fields(api,key,token,ledger,work):
    return c1.rpc(api,key,APPROVED_FIELDS,{
        "p_ledger_id":ledger,"p_work_item_id":work},token)

def source_sha(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

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

    # Test-only source text is never made available to a worker merely by
    # responsible allocation. The already authorized root governor can
    # inspect the exact field candidate before deciding a later grant.
    c1.sql(a.db_url,
        "update atlas.work_items set instructions="
        f"'{SYNTHETIC_PRIVATE_INSTRUCTIONS}' "
        f"where id='{standing.TASK_A}'::uuid")
    gov_status,gov_data=governor_review(api,key,owner,ledger,standing.WORKER_PERSON)
    need(gov_status==200 and isinstance(gov_data,dict) and gov_data.get("ok") is True,
         "Signed root governor cannot inspect this exact connected Person review")
    need(gov_data.get("verificationStatus")=="verification_incomplete" and
         gov_data.get("mayCertifyNonDisclosure") is False,
         "Governor candidate preview falsely certified existing effective disclosure")
    preview=gov_data.get("preliminaryWorkFieldReview")
    need(isinstance(preview,dict) and
         preview.get("status")=="governor_review_inputs_only" and
         preview.get("workFieldsRequireSeparateDecisions") is True and
         preview.get("hasMoreCandidateWork") is False and
         isinstance(preview.get("items"),list),
         "Governor review must return a bounded explicitly unapproved source preview")
    work_candidates=preview["items"]
    matched=[x for x in work_candidates if x.get("workItemId")==standing.TASK_A]
    need(len(matched)==1 and matched[0].get("instructionsCandidate")==
         SYNTHETIC_PRIVATE_INSTRUCTIONS and
         matched[0].get("titleFieldDecisionStatus")=="not_evaluated" and
         matched[0].get("instructionsFieldDecisionStatus")=="not_evaluated",
         "Governor field candidate does not show exact source without fake permission")
    need(all(x.get("workItemId")!=standing.TASK_B for x in work_candidates),
         "Governor target review should not enumerate unrelated unassigned Work")
    worker_review=governor_review(api,key,worker,ledger,standing.WORKER_PERSON)
    need(worker_review[0] in (200,401,403) and
         (worker_review[0]!=200 or worker_review[1]=={"ok":False,"code":"not_found"}),
         "Connected Person obtained governor-only instructions via preview RPC")
    stranger_review=governor_review(api,key,outsider,ledger,standing.WORKER_PERSON)
    need(stranger_review[0] in (200,401,403) and
         (stranger_review[0]!=200 or
          stranger_review[1]=={"ok":False,"code":"not_found"}),
         "Outsider could preview exact Work fields without Ledger authority")
    wrong_ledger_review=governor_review(
        api,key,owner,other_ledger,standing.WORKER_PERSON)
    need(wrong_ledger_review[0] in (200,401,403) and
         (wrong_ledger_review[0]!=200 or
          wrong_ledger_review[1]=={"ok":False,"code":"not_found"}),
         "Root governor of one Ledger previewed another Ledger's Work fields")
    missing_review=governor_review(
        api,key,owner,ledger,"e5200000-0000-4000-8000-000000000104")
    need(missing_review[0] in (200,401,403) and
         (missing_review[0]!=200 or
          missing_review[1]=={"ok":False,"code":"not_found"}),
         "Governor review exposed a connected Person shell for non-seat target")
    print("PASS governor-only Work fields are visible for adjudication, not recipient grant")

    candidate=matched[0]
    title_text=candidate["titleCandidate"]
    title_hash=candidate["titleCandidateSha256"]
    private_hash=candidate["instructionsCandidateSha256"]
    need(title_hash==source_sha(title_text) and
         private_hash==source_sha(SYNTHETIC_PRIVATE_INSTRUCTIONS),
         "Governor must receive an exact source-text SHA256, not a loose Work field approval")

    # Allocations and Seats are NOT Work title or instructions grants.
    pre_status,pre_data=request(api,key,worker,ledger)
    need(pre_status==200 and isinstance(pre_data,dict) and
         standing.TASK_A not in {
             x.get("workItemId") for x in pre_data.get("items",[])
             if isinstance(x,dict)},
         "Even the newly narrow Work API revealed a title before governor approval")
    first_fields=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(first_fields[0] in (200,401,403) and
         (first_fields[0]!=200 or
          first_fields[1]=={"ok":False,"code":"not_found"}),
         "Connected Person could inspect Work instructions before any field approval")
    old_before=my_work(api,key,worker)
    today_before=original_today(api,key,worker)
    for label,response in (("My Work",old_before),("Today",today_before)):
        need(response[0]==200 and isinstance(response[1],dict) and
             standing.TASK_A not in {
                 x.get("workItemId") for x in response[1].get("items",[])
                 if isinstance(x,dict)},
             f"Original {label} reader leaked Work title without governor field decision")

    # The signer must send the hash of EXACTLY what was previewed. An edit
    # between review and approval fails rather than approving changed words.
    bad_hash=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","allow",
        "Governor approves the exact original Work title.",
        expected="0"*64)
    need(bad_hash[0] in (200,401,403) and
         (bad_hash[0]!=200 or bad_hash[1]=={"ok":False,"code":"not_found"}),
         "Governor approved Work text with a mismatched preview SHA256")
    worker_grant=decide_field(api,key,worker,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","allow",
        "Worker must not approve their own Work field.",expected=title_hash)
    need(worker_grant[0] in (200,401,403) and
         (worker_grant[0]!=200 or worker_grant[1]=={"ok":False,"code":"not_found"}),
         "Connected Person successfully granted their own field")
    title_request=str(uuid.uuid4())
    title_approval=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","allow",
        "Governor approves this Work title and no other fields.",
        expected=title_hash,request_id=title_request)
    need(title_approval[0]==200 and
         title_approval[1].get("contractVersion")==
           "connected_person_work_field_decision_v1" and
         title_approval[1].get("decision")=="allow" and
         title_approval[1].get("idempotent") is False,
         "Governed title-only field approval failed")
    repeated=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","allow",
        "Governor approves this Work title and no other fields.",
        expected=title_hash,request_id=title_request)
    need(repeated[0]==200 and repeated[1].get("idempotent") is True
         and repeated[1].get("decisionId")==title_approval[1].get("decisionId"),
         "Exact idempotent Work title decision minted duplicate authority")
    rerouted=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"instructions","allow",
        "Governor approval request ID cannot be replayed across fields.",
        expected=private_hash,request_id=title_request)
    need(rerouted[0] in (200,401,403) and
         (rerouted[0]!=200 or rerouted[1]=={"ok":False,"code":"not_found"}),
         "One signed approval request could be replayed to grant another field")
    title_only=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(title_only[0]==200 and title_only[1].get("fields")=={"title":title_text},
         "Approved Work title must be returned with NO unapproved instructions")
    print("PASS exact signed governor SHA-bound title approval; instructions still withheld")

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
    need(SYNTHETIC_PRIVATE_INSTRUCTIONS not in json.dumps(old_data),
         "Unapproved governor preview instruction appeared in connected Person My Work")
    print("PASS existing My Work matches authorized narrow-source boundary")
    today_status,today_data=original_today(api,key,worker)
    need(today_status==200 and isinstance(today_data,dict) and
         today_data.get("ok") is True and
         today_data.get("contractVersion")=="connected_person_company_work_today_v1",
         "Existing Person Today source did not return its exact governed contract")
    today_items=today_data.get("items")
    need(isinstance(today_items,list),"Person Today Work must be an array")
    today_ids={x.get("workItemId") for x in today_items if isinstance(x,dict)}
    need(standing.TASK_A in today_ids and standing.TASK_B not in today_ids,
         "Original Today cannot lose real Work A or expose unrelated Work B")
    need(all(x.get("instructions") is None and x.get("sourceId") is None and
             x.get("sourceType") is None and x.get("sourceDate") is None
             for x in today_items),
         "Original Today leaks unapproved instructions/source identity/history")
    need(SYNTHETIC_PRIVATE_INSTRUCTIONS not in json.dumps(today_data),
         "Unapproved governor Work instruction appeared in ordinary Person Today")
    print("PASS current all-date Person Today retains only original authorized Work")

    # The existing dated Work reader is a distinct public API used to open
    # the original Work detail and confirm honest source-native completion.
    # Placement uses the REAL signed worker command, never a new mock task.
    test_day=(date.today()+timedelta(days=1)).isoformat()
    placed=standing.allowed(api,key,worker,"connected_person_place_work_self_api_v1",
        {"p_work_item_id":standing.TASK_A,
         "p_service_date":test_day,
         "p_reason":"Synthetic worker independently places original Work on a day."},
        "signed worker places canonical synthetic Work without making a new Work item")
    need(placed.get("newWorkCreated") is False and
         placed.get("executionDate")==test_day and placed.get("workItemId")==standing.TASK_A,
         "Signed placement failed source receipt parity")
    day_status,day_data=dated_work(api,key,worker,test_day)
    need(day_status==200 and isinstance(day_data,dict) and
         day_data.get("contractVersion")=="connected_person_company_work_day_v1"
         and day_data.get("date")==test_day, "Existing dated Work read failed")
    day_items=day_data.get("items")
    need(isinstance(day_items,list),"Original dated Work items must be an array")
    day_ids={x.get("workItemId") for x in day_items if isinstance(x,dict)}
    need(standing.TASK_A in day_ids and standing.TASK_B not in day_ids,
         "Dated source dropped legitimate Work or exposed unassigned Work")
    need(all(x.get("instructions") is None and x.get("taskClassification") is None
             for x in day_items),
         "Original dated Work reader disclosed unapproved instructions/metadata")
    need(all(x.get("allocationId") and x.get("planId") and
             x.get("executionDate")==test_day and x.get("exposureDate")==test_day
             for x in day_items),
         "Original dated Work lost its exact plan/allocation identity")
    denied_day=dated_work(api,key,outsider,test_day)
    need(denied_day[0] in (200,401,403) and
         (denied_day[0]!=200 or
          (isinstance(denied_day[1],dict) and
           all(x.get("workItemId")!=standing.TASK_A
               for x in denied_day[1].get("items",[]) if isinstance(x,dict)))),
         "An independently signed outsider read the worker's original dated Work")
    need(SYNTHETIC_PRIVATE_INSTRUCTIONS not in json.dumps(day_data),
         "Unapproved governor Work instruction appeared in original dated Work")
    print("PASS original dated Work positive assignment, plan and field deny")

    instructions_approval=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"instructions","allow",
        "Governor expressly shares the exact instructions on only Work A.",
        expected=private_hash)
    need(instructions_approval[0]==200 and
         instructions_approval[1].get("decision")=="allow",
         "Exact single Work instructions approval failed")
    approved_now=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(approved_now[0]==200 and approved_now[1].get("fields")=={
        "title":title_text,"instructions":SYNTHETIC_PRIVATE_INSTRUCTIONS},
        "Worker did not receive ONLY the two approved Work fields")
    need(SYNTHETIC_PRIVATE_INSTRUCTIONS in json.dumps(my_work(api,key,worker)[1])
         and SYNTHETIC_PRIVATE_INSTRUCTIONS in
             json.dumps(original_today(api,key,worker)[1])
         and SYNTHETIC_PRIVATE_INSTRUCTIONS in
             json.dumps(dated_work(api,key,worker,test_day)[1]),
         "Original Work readers did not honor the same positive instructions grant")
    other_work=approved_fields(api,key,worker,ledger,standing.TASK_B)
    need(other_work[0] in (200,401,403) and
         (other_work[0]!=200 or
          other_work[1]=={"ok":False,"code":"not_found"}),
         "One Work grant exposed unassigned Work B")
    wrong_ledger=approved_fields(api,key,worker,other_ledger,standing.TASK_A)
    need(wrong_ledger[0] in (200,401,403) and
         (wrong_ledger[0]!=200 or
          wrong_ledger[1]=={"ok":False,"code":"not_found"}),
         "One Ledger approval opened another Ledger's source")
    foreign=approved_fields(api,key,outsider,ledger,standing.TASK_A)
    need(foreign[0] in (200,401,403) and
         (foreign[0]!=200 or
          foreign[1]=={"ok":False,"code":"not_found"}),
         "Outsider retrieved assigned worker's approved instruction")
    print("PASS approved Work instruction appears only on exact signed Person/Ledger/Work")

    changed_text="Clone changed instructions were NOT yet approved"
    c1.sql(a.db_url,"update atlas.work_items set instructions="
        f"'{changed_text}' where id='{standing.TASK_A}'::uuid")
    text_changed=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(text_changed[0]==200 and
         text_changed[1].get("fields")=={"title":title_text},
         "Changed instructions leaked under governor approval of older source words")
    for surface,packet in (
        ("My Work",my_work(api,key,worker)),
        ("Today",original_today(api,key,worker)),
        ("Dated",dated_work(api,key,worker,test_day)),
    ):
        need(packet[0]==200 and changed_text not in json.dumps(packet[1]) and
             SYNTHETIC_PRIVATE_INSTRUCTIONS not in json.dumps(packet[1]),
             f"{surface} leaked changed or withdrawn Work instructions")
    stale_preview=governor_review(api,key,owner,ledger,standing.WORKER_PERSON)
    stale_items=stale_preview[1].get("preliminaryWorkFieldReview",{}).get("items",[])
    stale=[x for x in stale_items if x.get("workItemId")==standing.TASK_A]
    need(len(stale)==1 and
         stale[0].get("instructionsFieldDecisionStatus")=="source_changed" and
         stale[0].get("titleFieldDecisionStatus")=="approved",
         "Governor preview must show stale instructions and still-approved title")
    stale_reapprove=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"instructions","allow",
        "Governor cannot silently reapprove changed unreviewed instructions.",
        expected=private_hash)
    need(stale_reapprove[0] in (200,401,403) and
         (stale_reapprove[0]!=200 or
          stale_reapprove[1]=={"ok":False,"code":"not_found"}),
         "Changed Work field was approved using the obsolete reviewed hash")
    new_hash=source_sha(changed_text)
    new_approval=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"instructions","allow",
        "Governor separately reviews and approves the changed Work instructions.",
        expected=new_hash)
    need(new_approval[0]==200 and
         new_approval[1].get("decision")=="allow",
         "Changed Work text could not be independently reapproved")
    changed_approved=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(changed_approved[0]==200 and
         changed_approved[1].get("fields",{}).get("instructions")==changed_text,
         "Governor's new exact-field approval did not authorize changed words")

    deny_instructions=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"instructions","deny",
        "Governor revokes previously shared Work instructions after review.")
    need(deny_instructions[0]==200 and
         deny_instructions[1].get("decision")=="deny",
         "Exact Work instructions revocation did not append a decision")
    revoked_fields=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(revoked_fields[0]==200 and
         revoked_fields[1].get("fields")=={"title":title_text},
         "Revoking one field exposed instructions or incorrectly revoked title")
    for surface,packet in (
        ("My Work",my_work(api,key,worker)),
        ("Today",original_today(api,key,worker)),
        ("Dated",dated_work(api,key,worker,test_day))
    ):
        need(packet[0]==200 and
             changed_text not in json.dumps(packet[1]) and
             SYNTHETIC_PRIVATE_INSTRUCTIONS not in json.dumps(packet[1]),
             f"{surface} returned revoked instructions through alternate source")
    deny_title=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","deny",
        "Governor revokes original Work title as a separate field decision.")
    need(deny_title[0]==200 and deny_title[1].get("decision")=="deny",
         "Revoking the independent Work title field failed")
    after_both=approved_fields(api,key,worker,ledger,standing.TASK_A)
    need(after_both[0] in (200,401,403) and
         (after_both[0]!=200 or
          after_both[1]=={"ok":False,"code":"not_found"}),
         "Worker still retrieved Work fields after title and instructions denied")
    for surface,packet in (
        ("narrow",request(api,key,worker,ledger)),
        ("My Work",my_work(api,key,worker)),
        ("Today",original_today(api,key,worker)),
        ("Dated",dated_work(api,key,worker,test_day))
    ):
        need(packet[0]==200 and
             standing.TASK_A not in {
               x.get("workItemId") for x in packet[1].get("items",[])
               if isinstance(x,dict)},
             f"{surface} still listed Work title after title field revocation")
    count=c1.sql(a.db_url,
        "select count(*) from atlas.connected_person_work_field_decision_events_v1 "
        f"where work_item_id='{standing.TASK_A}'::uuid")
    need(int(count)>=5, "Field decision history was overwritten instead of appended")
    recovered=decide_field(api,key,owner,ledger,standing.TASK_A,
        standing.WORKER_PERSON,"title","allow",
        "Governor explicitly restores the approved title for Seat revocation test.",
        expected=title_hash)
    need(recovered[0]==200 and recovered[1].get("decision")=="allow",
         "Independent title reapproval after revocation failed")
    print("PASS changed source, separate revocations, append-only history and restoration")

    # Genuine same-JWT deny as soon as the native Seat ends, then restore only
    # the synthetic Seat to isolate session revocation from Seat revocation.
    seat="e5200000-0000-4000-8000-000000000502"
    c1.sql(a.db_url,f"update ledger.seats set ended_at=now() where id='{seat}'::uuid")
    denied(api,key,worker,ledger,"ended native Seat denies retained worker JWT")
    day_ended=dated_work(api,key,worker,test_day)
    need(day_ended[0] in (200,401,403) and
         (day_ended[0]!=200 or
          (isinstance(day_ended[1],dict) and
           all(x.get("workItemId")!=standing.TASK_A
               for x in day_ended[1].get("items",[]) if isinstance(x,dict)))),
         "Dated original Work exposed assigned Work after Seat termination")
    old_ended=original_today(api,key,worker)
    need(old_ended[0] in (200,401,403) and
         (old_ended[0]!=200 or (
             isinstance(old_ended[1],dict) and
             standing.TASK_A not in {
                 item.get("workItemId") for item in old_ended[1].get("items",[])
                 if isinstance(item,dict)})),
         "Existing Today leaks Work after native Ledger Seat ends")
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
    today_lost=original_today(api,key,worker)
    need(today_lost[0]==200 and isinstance(today_lost[1],dict) and
         standing.TASK_A not in {
             item.get("workItemId") for item in today_lost[1].get("items",[])
             if isinstance(item,dict)},
         "OLDER PERSON TODAY BYPASS: Work still visible after relevance removal")
    print("PASS older Today loses original Work whose Ledger relevance is removed")
    day_lost=dated_work(api,key,worker,test_day)
    need(day_lost[0]==200 and isinstance(day_lost[1],dict) and
         all(x.get("workItemId")!=standing.TASK_A
             for x in day_lost[1].get("items",[]) if isinstance(x,dict)),
         "OLDER DATED WORK BYPASS: Work remains exposed after exact relevance deletion")
    print("PASS original dated Work hides revoked Ledger-relevance items")

    sid=tokens["worker"][1]["session_id"]
    c1.sql(a.db_url,f"delete from auth.sessions where id='{sid}'::uuid")
    denied(api,key,worker,ledger,"deleted GoTrue session denies retained valid JWT")
    old_revoked_status,old_revoked_data=my_work(api,key,worker)
    need(old_revoked_status in (401,403) or
         (old_revoked_status==200 and old_revoked_data=={"ok":False,"code":"not_found"}),
         "Old My Work must deny the SAME JWT after its genuine GoTrue session is revoked")
    gov_session_check=governor_review(
        api,key,worker,ledger,standing.WORKER_PERSON)
    need(gov_session_check[0] in (200,401,403) and
         (gov_session_check[0]!=200 or
          gov_session_check[1]=={"ok":False,"code":"not_found"}),
         "Revoked worker session obtained governor Work preview")
    day_revoked=dated_work(api,key,worker,test_day)
    need(day_revoked[0] in (401,403) or
         (day_revoked[0]==200 and
          day_revoked[1]=={"ok":False,"code":"not_found"}),
         "Dated Work must deny a revoked GoTrue session with the same JWT")
    today_revoked=original_today(api,key,worker)
    need(today_revoked[0] in (401,403) or
         (today_revoked[0]==200 and
          today_revoked[1]=={"ok":False,"code":"not_found"}),
         "Existing Today must deny a revoked GoTrue session with the same JWT")
    need(c1.sql(a.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "Signed Work read created a prohibited employee membership")
    Path(a.output).write_text(
        "PASS local independent GoTrue owner/worker/outsider/no-seat; "
        "real signed Work scope acceptance and assignment; exact visible Work; "
        "withheld Work/title/source denied on My Work, Today and dated Work; "
        "relevance-removal bypass closed; wrong-Ledger, ended Seat and "
        "revoked-session denials; no memberships or new Work.\n",
        encoding="utf-8")
    print("PASS source-isolated connected Person Work read on signed local clone")

if __name__=="__main__":
    main()

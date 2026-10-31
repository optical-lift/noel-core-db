#!/usr/bin/env python3
"""Signed owner, worker, outsider, ended-root v2 intake on disposable 127.0.0.1 only."""
import argparse,datetime,importlib.util,json,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("reciprocal_fixture",
    HERE/"validate-atlas-ledger-reciprocal-signed-http.py")
v1=importlib.util.module_from_spec(spec);spec.loader.exec_module(v1)
base=v1.base
c1=v1.c1
ELM=c1.LEDGER_A
ANNA_LEDGER=c1.LEDGER_B
ANNA_ROOT=v1.ANNA_ROOT
SUBMIT="submit_ledger_work_self_api_v1"
DECIDE_V1="decide_ledger_work_intake_root_self_api_v1"
QUEUE="ledger_work_review_queue_root_self_api_v2"
REVIEW="review_ledger_work_intake_root_self_api_v2"
STATUS="ledger_work_submission_status_self_api_v1"

def must(test,message):base.check(test,message)
def sql(db,statement):
    try:return base.sql(db,statement)
    except subprocess.CalledProcessError as exc:
        raise AssertionError('Disposable SQL assertion failed: '+(exc.stderr or '').strip()[-1400:]) from exc
def allow(api,key,token,name,args):
    status,obj=base.rpc(api,key,token,name,args)
    must(status==200 and isinstance(obj,dict) and obj.get("ok") is True,
         f"Signed allow {name}: {status} {str(obj)[:180]}")
    return obj
def deny(api,key,token,name,args,reason):
    code,obj=base.rpc(api,key,token,name,args)
    must(code in (401,403) and isinstance(obj,dict) and
         (token is None or obj.get("code")=="42501"),
         f"NOT signed denial {reason}: {code} {str(obj)[:160]}")
    print("PASS denied",reason)
def stale(api,key,token,name,args,reason):
    code,obj=base.rpc(api,key,token,name,args)
    must(code in (400,409,500) and isinstance(obj,dict) and obj.get("code")=="40001",
         f"NOT source stale CAS {reason}: {code} {str(obj)[:160]}")
    print("PASS stale",reason)
def queue(api,key,token,ledger):
    out=allow(api,key,token,QUEUE,{"p_ledger_id":ledger,"p_limit":100})
    must(out.get("contractVersion")=="ledger_work_root_review_queue_v2"
      and out.get("ledgerId")==ledger and out.get("isPersonalWorkObligation") is False
      and out.get("notificationDeliveryClaimed") is False
      and out.get("supportsReject") is True
      and out.get("supportsSameOriginalEdit") is True,
      "Queue v2 source receipt absent")
    return out
def review(api,key,token,intake,decision,revision,reason,title=None,instructions=None):
    args={"p_intake_id":intake,"p_decision":decision,
      "p_expected_revision":revision,"p_reason":reason,
      "p_title":title,"p_instructions":instructions}
    out=allow(api,key,token,REVIEW,args)
    must(out.get("contractVersion")=="ledger_work_root_disposition_v2"
      and out.get("reviewState")==decision and out.get("revision")==revision+1
      and out.get("sameOriginalWork") is True
      and out.get("personWorkAssignmentCreated") is False
      and out.get("personalTodayChanged") is False
      and out.get("workPlanCreated") is False
      and out.get("notificationDeliveryClaimed") is False,
      "Final review claimed new assignment, plan or duplicate Work")
    return out
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    a=parser.parse_args()
    must(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
         "Only disposable localhost PostgreSQL permitted")
    api,key=c1.local_status()
    base.setup_auth(a.db_url)
    tokens={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        must(claims.get("sub")==uid and claims.get("session_id"),
             "Expected independent actual GoTrue signed session")
        tokens[name]=token
    root=tokens["owner"];worker=tokens["worker"]
    outsider=tokens["outsider"];no_seat=tokens["no-seat"]
    people=sql(a.db_url,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")
    principals=sql(a.db_url,"SELECT count(*) FROM atlas.principals")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.principal_ledger_authorities "
        f"WHERE ledger_id='{ELM}'::uuid AND status='active' "
        f"AND authority_kind='root_governing'")=="1",
        "Existing exact Elm root fixture missing")
    root_queue=queue(api,key,root,ELM)
    must(root_queue.get("pendingCount")==0, "Unexpected fictional intake baseline")
    for actor,who in [(worker,"worker"),(outsider,"outsider"),
                      (no_seat,"unbound")]:
        deny(api,key,actor,QUEUE,{"p_ledger_id":ELM,"p_limit":100},
             who+" cannot see Elm review queue")
    deny(api,key,None,QUEUE,{"p_ledger_id":ELM,"p_limit":100},
         "anon cannot see root queue")
    deny(api,key,root,QUEUE,{"p_ledger_id":ANNA_LEDGER,"p_limit":100},
         "Elm root cannot see separate Anna Ledger queue")

    p={"p_ledger_id":ELM,"p_title":"Fictional work to clarify",
       "p_attention_date_proposal":None,
       "p_source_action_id":"disposition-v2-signed-needs-details-001"}
    sent=allow(api,key,worker,SUBMIT,p)
    one=sent["workItemId"];intake=sent["intakeId"]
    must(sent.get("createdNow") is True and
         sent.get("assignedToPerson") is False,"Worker submission created a personal obligation")
    pending=queue(api,key,root,ELM)
    must(pending.get("pendingCount")==1 and
         any(x.get("intakeId")==intake and x.get("revision")==0 and
             x.get("reviewState")=="submitted" for x in pending.get("items",[])),
         "Root's v2 queue missed original")
    deny(api,key,worker,REVIEW,{"p_intake_id":intake,
         "p_decision":"rejected","p_expected_revision":0,
         "p_reason":"Unauthorized reject","p_title":None,"p_instructions":None},
         "worker cannot reject someone else's intake")
    deny(api,key,outsider,REVIEW,{"p_intake_id":intake,
         "p_decision":"rejected","p_expected_revision":0,
         "p_reason":"Unauthorized reject","p_title":None,"p_instructions":None},
         "outsider cannot reject")

    # Historic v1 action is already in production. It placed real Venue Work
    # into needs_details revision 1, then the old submitted-only queue hid it.
    ask=allow(api,key,root,DECIDE_V1,{"p_intake_id":intake,
       "p_decision":"needs_details","p_expected_revision":0,
       "p_reason":"Please clarify scope of synthetic submission"})
    must(ask.get("revision")==1,"V1 follow-up revision not recorded")
    pending=queue(api,key,root,ELM)
    x=[x for x in pending["items"] if x.get("intakeId")==intake]
    must(len(x)==1 and x[0].get("reviewState")=="needs_details"
      and x[0].get("revision")==1
      and x[0].get("lastReviewReason")=="Please clarify scope of synthetic submission",
      "V2 failed to recover revision 1 unresolved Work")
    stale(api,key,root,REVIEW,{"p_intake_id":intake,
      "p_decision":"accepted_for_ledger","p_expected_revision":0,
      "p_reason":"Stale", "p_title":"Stale","p_instructions":"No"},
      "older revision cannot rewrite original")
    decision=review(api,key,root,intake,"accepted_for_ledger",1,
       "Original Work is actionable","Clarified original Work","Visit site and check sign")
    must(decision.get("workItemId")==one and decision.get("workState")=="open",
         "Editing acceptance created another Work")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.work_items WHERE id='{one}'::uuid "
          f"AND title='Clarified original Work' "
          f"AND instructions='Visit site and check sign' AND work_state='open'")=="1",
         "Edited original not the same Work")
    must(queue(api,key,root,ELM)["pendingCount"]==0,
         "Accepted original did not leave pending Today")
    reread=allow(api,key,worker,SUBMIT,p)
    must(reread.get("workItemId")==one and reread.get("intakeId")==intake
      and reread.get("createdNow") is False,
      "Source-action retry after editing duplicated original")
    status=allow(api,key,worker,STATUS,{"p_intake_id":intake})
    must(status.get("reviewState")=="accepted_for_ledger" and
      status.get("title")=="Clarified original Work",
      "Submitter does not see same original's updated status")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.ledger_work_intake_decisions "
          f"WHERE intake_id='{intake}'::uuid AND revision IN (1,2)")=="2",
         "Historic needs-details + edited-accept decision history lost")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.work_allocations "
          f"WHERE work_item_id='{one}'::uuid")=="0",
         "Acceptance created person allocation")

    # Independent rejection test also proves the real historical original is
    # retained while its execution state transitions to cancelled.
    rejected_payload={"p_ledger_id":ELM,
      "p_title":"Synthetic proposal to decline","p_attention_date_proposal":None,
      "p_source_action_id":"disposition-v2-signed-rejected-002"}
    reject_sent=allow(api,key,worker,SUBMIT,rejected_payload)
    reject_intake=reject_sent["intakeId"];reject_work=reject_sent["workItemId"]
    denied=review(api,key,root,reject_intake,"rejected",0,
      "This proposed work does not belong in the governing Ledger")
    must(denied.get("workItemId")==reject_work and denied.get("workState")=="cancelled",
         "Rejection did not cancel same Work")
    must(queue(api,key,root,ELM)["pendingCount"]==0,
         "Rejected Work remains pending Today")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.work_items "
          f"WHERE id='{reject_work}'::uuid AND work_state='cancelled'")=="1",
         "Canceled historical Work missing")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.ledger_work_intake_decisions "
          f"WHERE intake_id='{reject_intake}'::uuid AND decision='rejected'")=="1",
         "Rejection historical decision lost")
    replay=allow(api,key,worker,SUBMIT,rejected_payload)
    must(replay.get("workItemId")==reject_work and replay.get("createdNow") is False,
         "Canceled original duplicated by same-key replay")

    # Reciprocal root remains strict; ending one's exact root invalidates the
    # very same GoTrue JWT with no sign-out/re-sign-in.
    anna=queue(api,key,worker,ANNA_LEDGER)
    must(anna.get("ledgerId")==ANNA_LEDGER,"Reciprocal root not admitted")
    sql(a.db_url,f"UPDATE atlas.principal_ledger_authorities "
      f"SET status='ended',ended_at=now() "
      f"WHERE id='{ANNA_ROOT}'::uuid AND status='active'")
    deny(api,key,worker,QUEUE,{"p_ledger_id":ANNA_LEDGER,"p_limit":100},
         "ended root cannot read private queue with still-valid JWT")
    deny(api,key,worker,REVIEW,{"p_intake_id":reject_intake,
      "p_decision":"rejected","p_expected_revision":0,
      "p_reason":"No","p_title":None,"p_instructions":None},
      "worker still cannot review Elm intake after losing separate root")
    must(sql(a.db_url,"SELECT count(*) FROM reality.entities WHERE entity_kind='person'")==people
      and sql(a.db_url,"SELECT count(*) FROM atlas.principals")==principals,
      "Intake operations created shadow Person or Principal")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text("PASS signed root/worker/outsider, v1 needs_details recovered, "
      "edited same original, reject historic original, stale CAS, submission replay, "
      "root isolation and ended authority. DISPOSABLE CLONE ONLY.\n")
    print("PASS v2 signed Ledger intake disposition, no production mutation")
if __name__=="__main__":main()

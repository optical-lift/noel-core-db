#!/usr/bin/env python3
"""Protected LOCAL disposable clone only. Three signed People, one original Work.

Prerequisites: current released native intake/journal sources, exact C1 synthetic
fixture, held participation candidate + reader + postconditions, W07 candidate.
Do not run on production. Exercise the exact candidate REST wrappers, not test-only adapters. This is not a production grant.
"""
import argparse
import importlib.util
import re
import uuid
from datetime import date, timedelta
from pathlib import Path

ROOT=Path(__file__).resolve().parents[4]
spec=importlib.util.spec_from_file_location("shared_base",ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
ORG,LEDGER,OTHER_LEDGER=c1.ORG,c1.LEDGER_A,c1.LEDGER_B
OWNER="e5200000-0000-4000-8000-000000000101"
WORKER="e5200000-0000-4000-8000-000000000102"
OTHER="e5200000-0000-4000-8000-000000000103"
SEAT="e5200000-0000-4000-8000-000000000579"
READ="connected_person_my_work_self_api_v2"
CHANGE="owner_change_native_work_participation_self_api_v1"
ROSTER="owner_native_work_participation_roster_self_api_v1"
NOTES="read_native_original_work_comments_self_api_v1"
WRITE="append_native_original_work_comment_self_api_v1"
REPORT="report_connected_person_company_work_self_api_v1"

def check(cond,msg): base.check(cond,msg)
def ident(): return str(uuid.uuid4())

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    opts=parser.parse_args()
    db=opts.db_url
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",db)),"Refuse nonlocal database")
    api,key=c1.local_status()
    check(bool(re.match(r"^http://127[.]0[.]0[.]1:[0-9]+(?:/|$)",api)),"Refuse nonlocal HTTP")
    def sql(query): return base.sql(db,query)
    check(sql(f"select count(*) from reality.entities where id in ('{OWNER}'::uuid,'{WORKER}'::uuid,'{OTHER}'::uuid) and stable_key like 'c1-validation-%'")=="3","Synthetic fixture only")
    sessions={}
    for name,uid in base.setup_auth(db):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),"Bad separate signed session")
        check(sql(f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1","Missing signed session")
        sessions[name]=(token,claims)
    root,worker,other,outside=(sessions[name][0] for name in ("owner","worker","outsider","no-seat"))
    # Exact candidate REST wrappers already installed by clone migration; no test-only adapter.
    sql("NOTIFY pgrst,'reload schema'")
    # Wait for local schema reload only. Missing RPC is never a denial proof.
    import time
    for _ in range(30):
        code,packet=base.rpc(api,key,root,READ,{"p_limit":100,"p_after_allocation_id":None})
        if code==200 and isinstance(packet,dict) and packet.get("ok") is True: break
        time.sleep(1)
    else: raise AssertionError("Clone REST schema failed to expose exact reader")
    def ok(token,rpc,args): return base.allow(api,key,token,rpc,args)
    def deny(token,rpc,args,codes=("42501",)):
        status,obj=base.rpc(api,key,token,rpc,args)
        check(status>=400 and status!=404 and isinstance(obj,dict) and obj.get("code") in codes,
              "Expected signed source denial: "+rpc+" "+str(status)+" "+str(obj)[:130])
    def record():
        d=ok(root,"record_ledger_work_self_api_v2",dict(p_ledger_id=LEDGER,p_title="Synthetic shared original",p_attention_date_proposal=None,p_source_action_id=ident()))
        check(d["reviewState"]=="accepted_for_ledger" and d["assignedToPerson"] is False,"Governor record assigned itself")
        return d["workItemId"]
    def scope(w): return dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_work_item_id=w)
    def assign(w):
        return ok(root,"work_focus_owner_reassign_direct_self_api_v1",dict(scope(w),p_expected_allocation_id=None,p_target_person_id=WORKER,p_reason="Synthetic ordinary direct responsibility",p_source_action_id=ident()))["newAllocationId"]
    def change(w,primary,action="add",allocation=None):
        return dict(scope(w),p_target_person_id=OTHER,p_expected_primary_allocation_id=primary,p_action=action,p_source_action_id=ident(),p_expected_participant_allocation_id=allocation)
    def rows(token,w):
        d=ok(token,READ,dict(p_limit=100,p_after_allocation_id=None))
        check(d["contractVersion"]=="connected_person_my_work_v2" and d["hasMore"] is False,"Bounded clone page incomplete")
        return [x for x in d["items"] if x["workItemId"]==w]
    def notes(token,w):
        return ok(token,NOTES,dict(scope(w),p_limit=40,p_after_recorded_at=None,p_after_comment_id=None))["items"]
    def write(token,w,body):
        return ok(token,WRITE,dict(scope(w),p_source_action_id=ident(),p_body=body))
    def counts():
        return tuple(sql("select count(*) from "+table) for table in ("atlas.work_items","atlas.tasks","atlas.organization_memberships","atlas.work_execution_plans","atlas.work_execution_results","atlas.work_result_acceptances"))
    w=record(); primary=assign(w); request=change(w,primary)
    deny(root,CHANGE,request)
    # Existing synthetic third Person gains native Ledger connection only.
    sql(f"insert into ledger.seats(id,ledger_id,person_entity_id,seat_state,seat_basis) values ('{SEAT}'::uuid,'{LEDGER}'::uuid,'{OTHER}'::uuid,'active','{{\"cloneFixture\":true}}'::jsonb)")
    check(not rows(root,w) and len(rows(worker,w))==1 and not rows(other,w),"Premature assignment")
    deny(other,NOTES,dict(scope(w),p_limit=40,p_after_recorded_at=None,p_after_comment_id=None))
    deny(worker,CHANGE,request);deny(other,CHANGE,request);deny(outside,CHANGE,request)
    deny(root,CHANGE,dict(request,p_ledger_id=OTHER_LEDGER))
    baseline=counts()
    d=ok(root,CHANGE,request);part=d["allocationId"]
    check(d["targetPersonId"]==OTHER and d["actorPersonId"]==OWNER and d["recipientAttested"] is False and d["primaryResponsibilityChanged"] is False,"Wrong actor or changed primary")
    check(ok(root,CHANGE,request)["allocationId"]==part,"Duplicate replay")
    deny(root,CHANGE,dict(request,p_source_action_id=ident()),("23505",))
    check(counts()==baseline,"Participant established duplicated Work, membership, plan or result")
    roster=ok(root,ROSTER,scope(w))
    check(roster["actorPersonId"]==OWNER and roster["primaryPersonId"]==WORKER
          and roster["primaryAllocationId"]==primary and roster["items"]==[{"personId":OTHER,"allocationId":part}],"Exact roster mismatch")
    for tok in (worker,other,outside): deny(tok,ROSTER,scope(w))
    choices=ok(root,"connected_ledger_person_choices_self_api_v1",dict(p_ledger_id=LEDGER,p_limit=100,p_after_person_id=None))
    check(choices["contractVersion"]=="connected_ledger_person_choices_v1"
          and {WORKER,OTHER}.issubset({p["personId"] for p in choices["items"]}),"Source picker cannot name connected assigned People")
    a,b=rows(worker,w),rows(other,w)
    check(not rows(root,w) and len(a)==len(b)==1 and not rows(outside,w),"Two People carry same original, governor absent")
    check(a[0]["allocationId"]==primary and a[0]["allocationRole"]=="responsible" and b[0]["allocationId"]==part and b[0]["allocationRole"]=="participant" and b[0]["canPlace"] is False,"Roles confused")
    check(a[0]["planId"] is None and b[0]["planId"] is None,"Undated work invented a plan")
    one=write(worker,w,"Synthetic list\n- Window\n- Door")
    two=write(other,w,"Synthetic second Person list\n- Floor\n- Walls")
    for token in (root,worker,other):
        seen={x["commentId"]:x["body"] for x in notes(token,w)}
        check(seen.get(one["commentId"])==one["body"] and seen.get(two["commentId"])==two["body"],"Reciprocal multiline readback failed")
    deny(outside,NOTES,dict(scope(w),p_limit=40,p_after_recorded_at=None,p_after_comment_id=None))
    report=dict(p_work_item_id=w,p_result_kind="completed",p_idempotency_key=ident(),p_payload={"note":"Synthetic signed actual"})
    deny(other,REPORT,report)
    sql(f"update ledger.seats set seat_state='ended',ended_at=now() where id='{SEAT}'::uuid")
    check(not rows(other,w) and len(rows(worker,w))==1,"Revocation failed")
    deny(other,NOTES,dict(scope(w),p_limit=40,p_after_recorded_at=None,p_after_comment_id=None))
    sql(f"update ledger.seats set seat_state='active',ended_at=null where id='{SEAT}'::uuid")
    removed=ok(root,CHANGE,change(w,primary,"remove",part))
    check(removed["allocationId"]==part and not rows(other,w) and len(rows(worker,w))==1,"Removal changed other responsibility")
    again=ok(root,CHANGE,change(w,primary))
    check(again["allocationId"]!=part,"New participation reused ended allocation")
    result=ok(worker,REPORT,report)
    check(result["workItemId"]==w and result["workState"]=="completed","Original completion failed")
    check(not rows(worker,w) and not rows(other,w) and not rows(root,w),"Terminal original remains active")
    check(sql(f"select count(*) from atlas.work_allocations where work_item_id='{w}'::uuid and allocation_role='participant' and state='released'")== "2","Participant history not released")
    check(sql(f"select count(*) from atlas.work_execution_results where work_item_id='{w}'::uuid")== "1","Falsely attributed another Result")
    print("PASS signed three-Person unscheduled shared Work, multiline notes, revocation, remove, terminal identity",flush=True)
    # Do not manufacture a legacy owner membership to make scheduling pass.
    # Reuse the actual native plan writer. If it still depends on membership,
    # this test must fail and block the scheduled/shared Today claim.
    scheduled=record(); carrier=assign(scheduled)
    ok(root,CHANGE,change(scheduled,carrier))
    today=date.fromisoformat(sql("select (now() at time zone 'UTC')::date"))
    def plan(day):
        return ok(root,"owner_set_connected_person_work_day_self_api_v1",dict(p_work_item_id=scheduled,p_ledger_id=LEDGER,p_service_date=day.isoformat(),p_reason="Synthetic original shared work day"))
    plan(today); x,y=rows(worker,scheduled),rows(other,scheduled)
    check(len(x)==len(y)==1 and x[0]["planId"]==y[0]["planId"] and x[0]["exposureDate"]==y[0]["exposureDate"]==today.isoformat(),"Shared day differs")
    tomorrow=today+timedelta(days=1);plan(tomorrow)
    x,y=rows(worker,scheduled),rows(other,scheduled)
    check(x[0]["planId"]==y[0]["planId"] and x[0]["exposureDate"]==y[0]["exposureDate"]==tomorrow.isoformat() and not rows(root,scheduled),"Reschedule changed original or governor admission")
    # Exercise the actual browser self-join and leave source, independent of
    # the third-party assignment scenario above. Exact own allocation replay.
    me=record(); main=assign(me)
    eligible="native_original_work_self_participation_self_api_v1"
    join="join_native_original_work_self_api_v1"
    leave="leave_native_original_work_self_api_v1"
    pre=ok(root,eligible,scope(me))
    check(pre["canJoin"] is True and pre["canLeave"] is False and pre["primaryAllocationId"]==main,"Self eligibility mismatch")
    jargs=dict(scope(me),p_source_action_id=ident())
    for tok in (worker,other,outside):
        deny(tok,eligible,scope(me));deny(tok,join,jargs)
    before=counts()
    j=ok(root,join,jargs);own=j["allocationId"]
    check(j["allocationRole"]=="participant" and j["personId"]==OWNER and j["workCopied"] is False
          and j["primaryResponsibilityChanged"] is False and j["resultRecorded"] is False,"Invalid join receipt")
    check(ok(root,join,jargs)["allocationId"]==own and len(rows(root,me))==1 and len(rows(worker,me))==1,"Self join or replay failed")
    check(counts()==before,"Self join altered Work, legacy membership, plan or Result")
    pre=ok(root,eligible,scope(me))
    check(pre["canLeave"] is True and pre["participantAllocationId"]==own and pre["canJoin"] is False,"Joined state mismatch")
    leaveargs=dict(scope(me),p_participant_allocation_id=own)
    deny(worker,leave,leaveargs)
    deny(root,leave,dict(leaveargs,p_participant_allocation_id=main))
    check(ok(root,leave,leaveargs)["allocationState"]=="released" and not rows(root,me) and len(rows(worker,me))==1,"Self leave changed primary")
    check(ok(root,leave,leaveargs)["idempotent"] is True,"Self leave replay not stable")
    # Actual wrapper ACLs must deny unsigned callers, not simply omit routes.
    deny(None,READ,dict(p_limit=100,p_after_allocation_id=None))
    deny(None,CHANGE,change(me,main))
    check(counts()==before,"Self leave altered Work, legacy membership, plan or Result")
    Path(opts.output).parent.mkdir(parents=True,exist_ok=True)
    Path(opts.output).write_text("PASS three signed People, two carriers, one original, reciprocal notes, revocation, terminal, scheduled and rescheduled, exact REST wrappers, roster and self join/leave\n")

if __name__=="__main__": main()

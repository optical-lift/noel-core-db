#!/usr/bin/env python3
"""Signed local clone acceptance: governor recording, ordinary own Result journal."""
import argparse
import importlib.util
import re
import uuid
from datetime import date,timedelta
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location("journal_base",ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
ORG,LEDGER=c1.ORG,c1.LEDGER_A
OWNER="e5200000-0000-4000-8000-000000000101"
WORKER="e5200000-0000-4000-8000-000000000102"
RECORD="record_ledger_work_self_api_v2"
PREFLIGHT="work_focus_owner_reassignment_preflight_self_api_v1"
ASSIGN="work_focus_owner_reassign_direct_self_api_v1"
REPORT="report_connected_person_company_work_self_api_v1"
DAY="connected_person_company_work_day_self_api_v2"
ACTIVITY="today_work_assignment_activity_self_api_v1"
def check(cond,message): base.check(cond,message)
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
    sessions={}
    for name,uid in base.setup_auth(db):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),"Bad signed session")
        check(base.sql(db,f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1","Missing session")
        sessions[name]=(token,claims)
    root,worker=sessions["owner"][0],sessions["worker"][0]
    def ok(token,rpc,args): return base.allow(api,key,token,rpc,args)
    def denied(token,rpc,args,codes=("42501",)):
        status,obj=base.rpc(api,key,token,rpc,args)
        check(status>=400 and status!=404 and isinstance(obj,dict) and (obj.get("code") in codes or (token is None and status==401)),f"Denied {rpc}: {status} {str(obj)[:150]}")
    def args(title):
        return dict(p_ledger_id=LEDGER,p_title=title,p_attention_date_proposal=None,p_source_action_id=ident())
    def context(work):
        return dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_work_item_id=work)
    def assign(work,to):
        return ok(root,ASSIGN,dict(context(work),p_expected_allocation_id=None,p_target_person_id=to,p_reason="Synthetic original",p_source_action_id=ident()))
    def report(work,day=None):
        payload={"note":"Synthetic completed result"}
        if day is not None: payload.update(performedOnCivilDate=day,performedOnTimezone="UTC")
        return dict(p_work_item_id=work,p_result_kind="completed",p_idempotency_key=ident(),p_payload=payload)
    def journal(token,day,work):
        data=ok(token,DAY,dict(p_date=day,p_timezone="UTC"))
        check(data["date"]==day and data["contractVersion"]=="connected_person_company_work_day_v2","Wrong journal contract")
        return [x for x in data["items"] if x["workItemId"]==work]
    today=date.fromisoformat(base.sql(db,"select (now() at time zone 'UTC')::date"))
    yesterday=(today-timedelta(days=1)).isoformat()
    tomorrow=(today+timedelta(days=1)).isoformat()
    today=today.isoformat()
    old_args=args("Synthetic old proposal")
    old=ok(root,"submit_ledger_work_self_api_v1",old_args)
    check(old["reviewState"]=="submitted","Legacy proposal path changed")
    check(ok(root,RECORD,old_args)["reviewState"]=="submitted","Replay adjudicated an existing pending original")
    owner_args=args("Synthetic governor original")
    recorded=ok(root,RECORD,owner_args);work=recorded["workItemId"]
    check(recorded["contractVersion"]=="ledger_work_record_v2" and recorded["reviewState"]=="accepted_for_ledger"
          and recorded["assignedToPerson"] is False and recorded["personDayPlacementEstablished"] is False,"Governor self-review not removed")
    check(ok(root,RECORD,owner_args)["workItemId"]==work,"Retry changed original")
    check(base.sql(db,f"select count(*) from atlas.ledger_work_intake_decisions where intake_id='{recorded['intakeId']}'::uuid and decision='accepted_for_ledger'")=="1","Exactly one governing decision required")
    check(ok(root,PREFLIGHT,context(work))["canAssign"] is True,"Governor original not assignable")
    pending=ok(worker,RECORD,args("Synthetic participant proposal"))
    check(pending["reviewState"]=="submitted","Participant gained governor acceptance")
    denied(worker,PREFLIGHT,context(work))
    denied(None,RECORD,args("Synthetic anonymous"))
    denied(sessions["outsider"][0],RECORD,args("Synthetic outsider"))
    # Deliberately choose yesterday, while reporting today, with no plan.
    allocation=assign(work,OWNER)
    denied(worker,REPORT,report(work,yesterday))
    denied(root,REPORT,report(work,tomorrow),("22023",))
    action=report(work,yesterday)
    result=ok(root,REPORT,action)
    check(result["workState"]=="completed","Own Result did not complete original")
    check(ok(root,REPORT,action)["resultId"]==result["resultId"],"Repeat created another Result")
    rows=journal(root,yesterday,work)
    check(len(rows)==1 and rows[0]["journalBasis"]=="performed_on_day"
          and rows[0]["performedOn"]==yesterday and rows[0]["planId"] is None
          and rows[0]["latestResultId"]==result["resultId"],"Explicit actual day must contain one unscheduled completed original")
    check(not journal(root,today,work),"Recorded date wrongly substituted for performed date")
    check(not journal(worker,yesterday,work),"Other Person can inspect private own completion")
    # Prior clients omit actual date; expose recorded day honestly, never backfill.
    prior=ok(root,RECORD,args("Synthetic recorded-only original"))["workItemId"]
    assign(prior,OWNER)
    ok(root,REPORT,report(prior))
    prior_rows=journal(root,today,prior)
    check(len(prior_rows)==1 and prior_rows[0]["journalBasis"]=="recorded_on_day"
          and prior_rows[0]["performedOn"] is None and prior_rows[0]["planId"] is None,"Recorded-only evidence invented an actual day")
    other=ok(root,RECORD,args("Synthetic other Person responsibility"))["workItemId"]
    assign(other,WORKER)
    activity=ok(root,ACTIVITY,dict(p_date=today,p_timezone="UTC",p_limit=100))
    ids={x["workItemId"] for x in activity["items"]}
    check(other in ids and work not in ids and prior not in ids,"Self assignment must not become outgoing dispatch")
    check(base.sql(db,f"select count(*) from atlas.work_execution_plans where work_item_id in ('{work}'::uuid,'{prior}'::uuid,'{other}'::uuid)")=="0","Invented plan")
    base.sql(db,f"delete from auth.sessions where id='{sessions['owner'][1]['session_id']}'::uuid")
    denied(root,DAY,dict(p_date=yesterday,p_timezone="UTC"))
    denied(root,RECORD,args("Synthetic revoked"))
    Path(opts.output).parent.mkdir(parents=True,exist_ok=True)
    Path(opts.output).write_text("PASS signed governor recording, participant review, performed and recorded day, own-vs-other responsibility and revoked authority\n")
if __name__=="__main__": main()

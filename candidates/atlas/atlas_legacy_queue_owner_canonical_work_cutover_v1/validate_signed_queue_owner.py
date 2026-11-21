#!/usr/bin/env python3
"""Real signed GoTrue -> local PostgREST exact Ledger queue-owner proof, disposable only."""
import argparse,importlib.util,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parents[3]/"scripts"
spec=importlib.util.spec_from_file_location("existing_signed_ledger",
    HERE/"validate-atlas-ledger-reciprocal-signed-http.py")
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
c1=base.c1
ORG=c1.ORG
LEDGER=c1.LEDGER_A
OTHER=c1.LEDGER_B
READ="company_work_legacy_queue_owner_self_api_v1"
DECIDE="decide_company_work_legacy_queue_owner_self_api_v1"
Q1="e5200000-0000-4000-8000-000000000d21"
Q2="e5200000-0000-4000-8000-000000000d22"
Q3="e5200000-0000-4000-8000-000000000d23"
Q4="e5200000-0000-4000-8000-000000000d24"
T1="e5200000-0000-4000-8000-000000000d11"
T2="e5200000-0000-4000-8000-000000000d12"
T3="e5200000-0000-4000-8000-000000000d13"
EXISTING="e5200000-0000-4000-8000-000000000901"
def must(ok,msg):base.must(ok,msg)
def sql(url,s):return base.sql(url,s)
def rpc(api,key,token,fn,args):return base.rpc(api,key,token,fn,args)
def accepted(api,key,token,fn,args):
    status,out=rpc(api,key,token,fn,args)
    must(status==200 and isinstance(out,dict) and out.get("ok") is True,
         f"Owner RPC {fn} failed: {status} {str(out)[:180]}")
    return out
def denied(api,key,token,fn,args,label):
    status,out=rpc(api,key,token,fn,args)
    must(status in (401,403) and isinstance(out,dict)
      and (token is None or out.get("code")=="42501"),
      f"{label}: wrong denial category {status} {str(out)[:160]}")
    print("PASS forbidden",label)
def get(byid,items):
    matches=[r for r in items if r.get("queueItemId")==byid]
    must(len(matches)==1,f"Missing exact queue row {byid[-3:]}")
    return matches[0]
def req(row,decision,work=None,reason="The current verified owner reviewed this exact original"):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_queue_item_id=row["queueItemId"],
      p_expected_queue_state=row["queueState"],
      p_expected_queue_updated_at=row["queueUpdatedAt"],
      p_expected_task_id=row["sourceTaskId"],
      p_expected_task_status=row["sourceTaskStatus"],
      p_expected_task_title=row["sourceTaskTitle"],
      p_decision=decision,p_reason=reason,p_existing_work_item_id=work)
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--db-url",required=True);ap.add_argument("--output",required=True)
    a=ap.parse_args()
    must(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
        "Refuse any non-disposable DB URL")
    api,key=c1.local_status()
    base.base.setup_auth(a.db_url)
    sessions={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        must(claims.get("sub")==uid and claims.get("session_id"),
             "Invalid signed local GoTrue identity")
        sessions[name]=(token,claims)
    owner=sessions["owner"][0]
    params=dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_limit=100)
    page=accepted(api,key,owner,READ,params)
    must(page.get("contractVersion")=="company_work_legacy_queue_owner_v1"
         and page.get("nativeLedgerId")==LEDGER and page.get("ownerReviewOnly") is True
         and page.get("noCanonicalWorkCreated") is True and
         page.get("noScheduleOrQueueStateChanged") is True,
         "Owner source/authority receipt missing")
    rows=page.get("items")
    must(isinstance(rows,list) and len(rows)>=4,"Synthetic queue evidence absent")
    r1,r2,r3,r4=(get(q,rows) for q in (Q1,Q2,Q3,Q4))
    must(r1["sourceTaskId"]==T1 and r1["taskLinkedDecisionPossible"] is True
         and r2["sourceTaskId"]==T2 and r2["queueDisagreesWithOldTask"] is True
         and r4["sourceTaskId"] is None and r4["noTaskMeansSeparateOriginalNeedReview"] is True,
         "Source disagreement or Taskless evidence lost")
    denied(api,key,None,READ,params,"anonymous cannot read originals")
    for name in ("worker","outsider","no-seat"):
        denied(api,key,sessions[name][0],READ,params,name+" cannot read owner originals")
        denied(api,key,sessions[name][0],DECIDE,req(r1,"matched_existing_work",EXISTING),
               name+" cannot decide owner originals")
    denied(api,key,owner,READ,dict(params,p_ledger_id=OTHER),
           "one Ledger root cannot cross to another Ledger")
    before_work=sql(a.db_url,f"SELECT count(*) FROM atlas.work_items WHERE organization_id='{ORG}'::uuid")
    before_queue=sql(a.db_url,
      f"SELECT md5(string_agg(id::text||':'||state||':'||updated_at::text, ',' ORDER BY id)) "
      f"FROM atlas.task_release_queue_items WHERE id IN ('{Q1}'::uuid,'{Q2}'::uuid,'{Q3}'::uuid,'{Q4}'::uuid)")
    match=accepted(api,key,owner,DECIDE,req(r1,"matched_existing_work",EXISTING))
    must(match.get("state")=="matched" and match.get("workItemId")==EXISTING
         and match.get("newWorkCreated") is False and match.get("queueStateChanged") is False
         and match.get("planCreated") is False and match.get("responsibilityEstablished") is False,
         "Owner exact-original match falsely issued Work or Plan")
    must(sql(a.db_url,f"SELECT original_assignee_canonical_person_id::text "
      f"FROM atlas.company_work_legacy_task_reviews_v1 "
      f"WHERE source_task_id='{T1}'::uuid")
      =="e5200000-0000-4000-8000-000000000102",
      "Original canonical Person provenance not preserved from the signed source")
    replay=accepted(api,key,owner,DECIDE,req(r1,"matched_existing_work",EXISTING))
    must(replay.get("state")=="already_reviewed" and replay.get("workItemId")==EXISTING,
         "Idempotent owner source decision not recovered")
    not_now=accepted(api,key,owner,DECIDE,req(r2,"not_current"))
    must(not_now.get("state")=="not_current" and not_now.get("workItemId") is None,
         "Historical no-longer-current source not recorded correctly")
    stale=req(r3,"not_current")
    stale["p_expected_queue_updated_at"]="2020-01-01T00:00:00Z"
    code,out=rpc(api,key,owner,DECIDE,stale)
    must(code in (400,409,422) and isinstance(out,dict) and out.get("code")=="23514",
         f"Stale source was accepted or wrong error: {code} {str(out)[:160]}")
    code,out=rpc(api,key,owner,DECIDE,req(r4,"not_current"))
    must(code in (400,422) and isinstance(out,dict) and out.get("code")=="22023",
         "Taskless occurrence was falsely treated as Task")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.work_items WHERE organization_id='{ORG}'::uuid")==before_work,
         "Review accidentally created original Work")
    must(sql(a.db_url,
      f"SELECT count(*) FROM atlas.company_work_legacy_task_reviews_v1 WHERE organization_id='{ORG}'::uuid"
      f" AND source_task_id IN ('{T1}'::uuid,'{T2}'::uuid,'{T3}'::uuid)")=="2",
      "Owner decisions missing, duplicated, or created from stale Task")
    must(sql(a.db_url,
      f"SELECT md5(string_agg(id::text||':'||state||':'||updated_at::text, ',' ORDER BY id)) "
      f"FROM atlas.task_release_queue_items WHERE id IN ('{Q1}'::uuid,'{Q2}'::uuid,'{Q3}'::uuid,'{Q4}'::uuid)")==before_queue,
      "Legacy queue source state changed")
    # Withdraw live governing authority in the DISPOSABLE C1 clone only.
    sql(a.db_url,f"UPDATE atlas.principal_ledger_authorities SET status='ended', ended_at=now() "
      f"WHERE id='{c1.ROOT_AUTHORITY}'::uuid")
    must(sql(a.db_url,f"SELECT count(*) FROM atlas.principal_ledger_authorities "
      f"WHERE id='{c1.ROOT_AUTHORITY}'::uuid AND status='ended' "
      f"AND ended_at IS NOT NULL")=="1",
      "Native synthetic root was not ended with its required timestamp")
    denied(api,key,owner,READ,params,"revoked native root cannot read")
    denied(api,key,owner,DECIDE,req(r3,"not_current"),"revoked native root cannot decide")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text("PASS signed original queue owner, wrong Ledger, "
      "outsider, no-seat, anonymous, revocation, stale, replay and no Work creation\n")
if __name__=="__main__":main()

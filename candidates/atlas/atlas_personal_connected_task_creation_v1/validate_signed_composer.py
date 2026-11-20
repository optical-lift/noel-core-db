#!/usr/bin/env python3
"""Held exact Personal original assignment lifecycle. Fictional localhost clone only."""
import argparse
import importlib.util
import re
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location("atlas_work_auth",ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
READ="read_personal_task_assignment_self_api_v1"
CHANGE="change_personal_task_assignment_self_api_v1"
DAY="atlas_task_day_self_api_v1"
BACKLOG="person_open_task_backlog_self_api_v1"
SENT="personal_sent_original_tasks_self_api_v1"
NOTE="append_personal_task_progress_self_api_v1"
NOTES="read_personal_task_progress_self_api_v1"
DONE="set_atlas_task_done_self_api_v1"
EDIT_READ="read_personal_task_text_date_self_api_v1"
EDIT="amend_personal_task_text_date_self_api_v1"
A="a6300000-0000-4000-8000-000000000201"
B="a6300000-0000-4000-8000-000000000206"
PRIVATE="a6300000-0000-4000-8000-000000000205"
TRANSFER="a6300000-0000-4000-8000-000000000204"
MEMBER="a6300000-0000-4000-8000-000000000302"
OWNER="e5200000-0000-4000-8000-000000000101"
PEER="e5200000-0000-4000-8000-000000000102"
OUTSIDER="e5200000-0000-4000-8000-000000000103"

def check(value,label): c1.check(value,label)
def change(task,rev,primary,others=(),action=None):
 return {"p_task_id":task,"p_expected_revision":rev,
         "p_primary_person_id":primary,"p_participant_person_ids":list(others),
         "p_source_action_id":action or str(uuid.uuid4())}
def exact(task): return {"p_task_id":task}
def note(task,text): return {"p_task_id":task,"p_source_action_id":str(uuid.uuid4()),"p_note":text}
def main():
 p=argparse.ArgumentParser();p.add_argument("--db-url",required=True);p.add_argument("--output",required=True)
 args=p.parse_args()
 check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),"Local database only")
 sql=lambda q:c1.sql(args.db_url,q)
 check(sql("select count(*) from atlas.task_entries where id::text like 'a6300000-%'")=="6","Fictional originals required")
 api,key=c1.local_status()
 base.setup_auth(args.db_url)
 tokens={}
 for who,uid in (("owner",c1.OWNER),("worker",c1.WORKER),("outsider",c1.OUTSIDER)):
  token,claims=c1.sign_in(api,key,who)
  check(claims.get("sub")==uid and claims.get("session_id"),"Distinct signed actor required")
  check(sql(f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1","Actual local session required")
  tokens[who]=token
 o,w,x=(tokens[k] for k in ("owner","worker","outsider"))
 def rpc(token,name,payload): return c1.rpc(api,key,name,payload,token)
 def ok(token,name,payload):
  code,body=rpc(token,name,payload)
  if code>=400 and isinstance(body,dict):
   # Only synthetic clone actors/payloads; bounded source error, never tokens or raw packet.
   print(f'Clone RPC {name}: {str(body.get("message", ""))[:240]}',flush=True)
  check(code==200 and isinstance(body,dict) and body.get("ok") is True,f"{name} failed HTTP {code}; code={body.get('code') if isinstance(body,dict) else 'non-object'}")
  return body
 def deny(token,name,payload,codes=("42501",)):
  code,body=rpc(token,name,payload)
  check(code>=400 and code!=404 and isinstance(body,dict) and body.get("code") in codes,f"{name}: expected {codes}, got HTTP {code}")
 def ids(token,name,payload): return {row["id"] for row in ok(token,name,payload)["items"]}
 day={"p_date":"2030-11-04"};backlog={"p_date":"2030-11-05","p_limit":100}
 work_count=sql("select count(*) from atlas.work_items")
 task_count=sql("select count(*) from atlas.task_entries")
 choices="personal_connected_task_choices_self_api_v1"
 create="create_connected_personal_task_self_api_v1"
 self_ledger="create_self_ledger_task_self_api_v1"
 ledger="e5200000-0000-4000-8000-000000000401"
 def payload(peer):
  return {"p_sentence":"Clone one-save Personal","p_due_date":day["p_date"],
          "p_recipient_person_id":peer,"p_source_action_id":str(uuid.uuid4())}
 def unchanged_failed(token,name,args,codes=("42501",)):
  before=sql("select count(*) from atlas.task_entries")
  before_work=sql("select count(*) from atlas.work_items")
  deny(token,name,args,codes)
  check(sql("select count(*) from atlas.task_entries")==before and
        sql("select count(*) from atlas.work_items")==before_work,"Failed command leaves no original")
 check(ok(o,choices,{})["items"]==[] and ok(w,choices,{})["items"]==[],"No peers before connection")
 unchanged_failed(o,create,payload(PEER))
 deny(None,choices,{},("42501","PGRST301"))
 invite=ok(o,"household_identity_invite_create_self_api_v1",{"p_member_id":MEMBER})
 ok(w,"household_identity_invite_accept_self_api_v1",{"p_token":invite["token"]})
 check({q["personId"] for q in ok(o,choices,{})["items"]}=={PEER},"Owner exact peer")
 check({q["personId"] for q in ok(w,choices,{})["items"]}=={OWNER},"Reciprocal exact peer")
 check(ok(x,choices,{})["items"]==[],"Unrelated Person no peer disclosure")
 unchanged_failed(o,create,payload(OUTSIDER))
 args1=payload(PEER)
 first=ok(o,create,args1);tid=first["task"]["id"]
 check(first["assignment"]["revision"]==1 and first["acceptanceRequired"] is False,"One original assignment")
 second=ok(o,create,args1)
 check(second["task"]["id"]==tid and second["assignment"]["assignmentEventId"]==first["assignment"]["assignmentEventId"],"Exact replay")
 check(tid not in ids(o,DAY,day) and tid in ids(o,SENT,{}) and tid in ids(w,DAY,day) and tid in ids(w,BACKLOG,backlog),"Original in correct notebooks")
 deny(x,READ,exact(tid))
 unchanged_failed(o,create,{**args1,"p_due_date":"2030-11-06"},("23505",))
 unchanged_failed(o,create,{**args1,"p_recipient_person_id":OUTSIDER})
 reverse=ok(w,create,payload(OWNER))["task"]["id"]
 check(reverse in ids(o,DAY,day) and reverse in ids(w,SENT,{}),"Reciprocal one-save")
 race_args=payload(PEER)
 with ThreadPoolExecutor(max_workers=2) as pool:
  futures=[pool.submit(ok,o,create,race_args) for _ in range(2)]
  race=[f.result(timeout=40) for f in futures]
 check(race[0]["task"]["id"]==race[1]["task"]["id"] and race[0]["assignment"]["assignmentEventId"]==race[1]["assignment"]["assignmentEventId"],"Concurrent retry one original")
 ok(w,"household_identity_link_disconnect_self_api_v1",{"p_member_id":MEMBER})
 unchanged_failed(o,create,payload(PEER))
 deny(w,READ,exact(tid))
 check(sql("select count(*) from atlas.task_entries")==str(int(task_count)+3),"Precisely three connected originals")
 check(sql("select count(*) from atlas.work_items")==work_count,"No Company copies")
 ledger_args={"p_ledger_id":ledger,"p_sentence":"Clone self Ledger","p_execution_date":day["p_date"],"p_source_action_id":str(uuid.uuid4())}
 unchanged_failed(w,self_ledger,ledger_args)
 unchanged_failed(x,self_ledger,ledger_args)
 one=ok(o,self_ledger,ledger_args);two=ok(o,self_ledger,ledger_args)
 check(one==two and one["responsiblePersonId"]==OWNER and one["acceptanceRequired"] is False,"Self original exact replay")
 packet=ok(o,"connected_person_company_work_day_self_api_v2",{"p_date":day["p_date"],"p_timezone":"America/Chicago"})
 check(any(row["workItemId"]==one["workItemId"] and row["allocationId"]==one["allocationId"] and row["planId"]==one["planId"] for row in packet["items"]),"Self Work exact signed day read")
 unchanged_failed(o,self_ledger,{**ledger_args,"p_execution_date":"2030-11-06"},("23505",))
 check(sql("select count(*) from atlas.work_items")==str(int(work_count)+1),"Exactly one Ledger original")
 check(sql("select count(*) from atlas.task_entries")==str(int(task_count)+3),"No personal duplicate")
 # Actual contextual source tests: the same author creates Ledger Work and
 # Event-linked Work, with zero Personal copies or implicit Event-date placement.
 contextual="create_contextual_ledger_work_self_api_v1"
 org="e5200000-0000-4000-8000-000000000801"
 event_a="a6300000-0000-4000-8000-000000000411"
 event_b="a6300000-0000-4000-8000-000000000412"
 event_read="ledger_occurrence_shared_work_self_api_v1"
 def bound(event,person=None,date=None,unassigned=False):
  return {"p_organization_id":org,"p_ledger_id":ledger,"p_occurrence_id":event,
    "p_sentence":"Synthetic bound composer original","p_recipient_person_id":person,
    "p_execution_date":date,"p_unassigned":unassigned,"p_source_action_id":str(uuid.uuid4())}
 def event_args(event):
  return {"p_organization_id":org,"p_ledger_id":ledger,"p_occurrence_id":event}
 def ledger_item(work):
  code,packet=rpc(o,"company_work_accountability_native_ledger_self_api_v1",{
   "p_organization_id":org,"p_ledger_id":ledger,"p_scope":"native_ledger",
   "p_limit":200,"p_after_work_item_id":None})
  check(code==200 and isinstance(packet,dict) and packet.get("contractVersion")=="company_work_accountability_native_ledger_v1"
   and packet.get("organizationId")==org and packet.get("selectedNativeLedgerId")==ledger
   and packet.get("scopeMode")=="native_ledger" and isinstance(packet.get("items"),list)
   and packet.get("facts",{}).get("privatePersonalAtlasNotRead") is True,"Exact signed Ledger reader contract")
  rows=[row for row in packet["items"] if row.get("workItemId")==work]
  check(len(rows)==1 and rows[0].get("organizationId")==org and rows[0].get("selectedNativeLedgerId")==ledger
   and rows[0].get("nativeLedgerRelevance")=="established_for_selected_ledger","One original in exact Ledger")
  return rows[0]
 base_work=int(sql("select count(*) from atlas.work_items"))
 for event,person,date in [(None,None,None),(event_a,None,None),(event_a,PEER,None),(event_b,PEER,day["p_date"]),(event_b,None,day["p_date"])]:
  args2=bound(event,person,date)
  result=ok(o,contextual,args2);work=result["workItemId"]
  check(result["responsiblePersonId"]==(person or OWNER) and result["executionDate"]==date and result["oneCanonicalWorkIdentity"] is True,"Exact chosen responsibility and optional date")
  check(result==ok(o,contextual,args2),"Existing original exact replay")
  item=ledger_item(work)
  check(item is not None and item["title"]==args2["p_sentence"] and item["responsibility"]["allocationId"]==result["allocationId"] and item["responsibility"]["assigneePersonId"]==(person or OWNER),"Same original in signed Ledger Work")
  if date is None:
   check(result["planId"] is None and sql(f"select count(*) from atlas.work_execution_plans where work_item_id='{work}'")=="0","No invented day")
  else:
   packet=ok(w if person==PEER else o,"connected_person_company_work_day_self_api_v2",{"p_date":date,"p_timezone":"America/Chicago"})
   check(any(row["workItemId"]==work and row["planId"]==result["planId"] for row in packet["items"]),"Original dated responsibility on recipient day")
  if event:
   check(any(row["workItemId"]==work and row["state"]=="open" for row in ok(o,event_read,event_args(event))["work"]),"Exact same original in Event")
   unchanged_failed(o,contextual,{**args2,"p_occurrence_id":event_b if event==event_a else event_a},("23505",))
  else:
   unchanged_failed(o,contextual,{**args2,"p_occurrence_id":event_a},("23505",))
  unchanged_failed(o,contextual,{**args2,"p_sentence":"Changed original"},("23505",))
 unassigned=bound(event_a,unassigned=True)
 result=ok(o,contextual,unassigned)
 check(result["responsiblePersonId"] is None and result["allocationId"] is None and result["planId"] is None,"Explicit unassigned is distinct")
 unchanged_failed(o,contextual,{**unassigned,"p_unassigned":False},("23505",))
 check(any(row["workItemId"]==result["workItemId"] for row in ok(o,event_read,event_args(event_a))["work"]),"Unassigned original in Event")
 unchanged_failed(w,contextual,bound(event_a))
 unchanged_failed(x,contextual,bound(event_a))
 deny(x,event_read,event_args(event_a))
 unchanged_failed(o,contextual,bound(str(uuid.uuid4())))
 unchanged_failed(o,contextual,bound(event_a,OUTSIDER))
 deny(None,contextual,bound(event_a),("42501","PGRST301"))
 check(sql("select count(*) from atlas.work_items")==str(base_work+6),"Six exact institutional originals, no failed-write leftovers")
 check(sql("select count(*) from atlas.task_entries")==str(int(task_count)+3),"No Personal copies")
 Path(args.output).write_text("PASS signed reciprocal atomic creation, rollback, race, privacy, self Ledger placement, and bound Ledger/Event original creation.\n")
 print("PASS compact composer signed proof")
if __name__=="__main__": main()

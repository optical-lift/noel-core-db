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
 details="Synthetic supporting instructions, not progress"
 own={"p_sentence":"Details on one original","p_due_date":None,"p_source_action_id":"daily:"+str(uuid.uuid4()),"p_details":details}
 writer="create_personal_task_initial_details_self_api_v1"
 first=ok(o,writer,own);tid=first["task"]["id"]
 check(first["task"]["details"]==details and ok(o,writer,own)["task"]["id"]==tid,"Private details and replay")
 check(ok(o,READ,exact(tid))["task"]["details"]==details,"Original details read")
 deny(x,READ,exact(tid));deny(None,writer,own,("42501","PGRST301"))
 unchanged_failed(o,writer,{**own,"p_details":"Changed retry"},("23505",))
 shared={**payload(PEER),"p_due_date":None,"p_details":details}
 writer="create_connected_personal_task_initial_details_self_api_v1"
 first=ok(o,writer,shared);tid=first["task"]["id"]
 check(ok(w,READ,exact(tid))["task"]["details"]==details,"Recipient receives author instructions")
 check(ok(o,writer,shared)["task"]["id"]==tid,"Shared details retry")
 unchanged_failed(o,writer,{**shared,"p_details":"Wrong details"},("23505",))
 unchanged_failed(o,writer,{**shared,"p_recipient_person_id":OUTSIDER,"p_source_action_id":str(uuid.uuid4())})
 deny(x,READ,exact(tid))
 check(ok(o,NOTES,{"p_task_id":tid,"p_limit":20})["items"]==[],"Instructions are not a progress report")
 org="e5200000-0000-4000-8000-000000000801"
 # Use exact fixture organization, Ledger and Event bindings, not inferred title.
 event="a6300000-0000-4000-8000-000000000411"
 work_writer="create_contextual_ledger_work_initial_details_self_api_v1"
 for occurrence in (None,event):
  for target,date in ((OWNER,None),(PEER,None),(PEER,day["p_date"])):
   p={"p_organization_id":org,"p_ledger_id":ledger,"p_occurrence_id":occurrence,"p_sentence":"Synthetic contextual details","p_recipient_person_id":target,"p_execution_date":date,"p_unassigned":False,"p_source_action_id":str(uuid.uuid4()),"p_details":details}
   first=ok(o,work_writer,p);wid=first["workItemId"]
   check(first["instructions"]==details and ok(o,work_writer,p)["workItemId"]==wid,"Contextual initial instructions exact replay")
   text_read=ok(o,"read_native_original_work_text_owner_self_api_v1",{"p_organization_id":org,"p_ledger_id":ledger,"p_work_item_id":wid})
   check(text_read["instructions"]==details,"Independent owner original instructions")
   unchanged_failed(o,work_writer,{**p,"p_details":"Different instructions"},("23505",))
   deny(x,work_writer,{**p,"p_source_action_id":str(uuid.uuid4())})
 p={"p_organization_id":org,"p_ledger_id":ledger,"p_occurrence_id":None,"p_sentence":"Synthetic unassigned details","p_recipient_person_id":None,"p_execution_date":None,"p_unassigned":True,"p_source_action_id":str(uuid.uuid4()),"p_details":details}
 first=ok(o,work_writer,p);check(ok(o,"ledger_work_submission_status_self_api_v1",{"p_intake_id":first["intakeId"]})["instructions"]==details,"Submitter can read original details")
 deny(x,"ledger_work_submission_status_self_api_v1",{"p_intake_id":first["intakeId"]})
 Path(args.output).write_text("PASS initial details same original, sender/recipient, contextual work, retries and denial.\\n")
if __name__=="__main__": main()

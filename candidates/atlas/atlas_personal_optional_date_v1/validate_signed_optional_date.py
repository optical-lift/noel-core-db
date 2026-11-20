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
 # Signed creation, date clearing, retry, read scope and completion.
 undated={"p_date":None}
 own_args={"p_sentence":"Synthetic undated own","p_due_date":None,"p_source_action_id":str(uuid.uuid4())}
 own=ok(o,"create_atlas_task_self_api_v1",own_args)["task"]
 check(own["dueDate"] is None,"No implicit date")
 own_id=own["id"]
 check(ok(o,"create_atlas_task_self_api_v1",own_args)["task"]==own,"Exact null replay")
 unchanged_failed(o,"create_atlas_task_self_api_v1",{**own_args,"p_due_date":day["p_date"]},("23505",))
 check(own_id in ids(o,DAY,undated) and own_id not in ids(o,DAY,day) and own_id not in ids(o,BACKLOG,backlog),"Undated isolated from dated notebook and backlog")
 check(own_id not in ids(w,DAY,undated) and own_id not in ids(x,DAY,undated),"Private undated only owner")
 deny(x,READ,exact(own_id))
 deny(None,DAY,undated,("42501","PGRST301"))
 deny(None,"create_atlas_task_self_api_v1",own_args,("42501","PGRST301"))
 move={"p_task_id":own_id,"p_expected_revision":0,"p_new_sentence":own["sentence"],"p_new_due_date":day["p_date"]}
 result=ok(o,EDIT,move)
 check(result["oldDueDate"] is None and result["dueDate"]==day["p_date"] and result["amendmentRevision"]==1,"Original moved from undated to day")
 check(own_id not in ids(o,DAY,undated) and own_id in ids(o,DAY,day),"Same original on selected day")
 check(ok(o,EDIT,move)["amendmentEventId"]==result["amendmentEventId"],"Date amendment replay")
 clear={**move,"p_expected_revision":1,"p_new_due_date":None}
 result=ok(o,EDIT,clear)
 check(result["dueDate"] is None and result["amendmentRevision"]==2,"Clear returns to undated")
 check(own_id in ids(o,DAY,undated) and own_id not in ids(o,DAY,day),"Original returns to undated")
 check(ok(o,EDIT,clear)["amendmentEventId"]==result["amendmentEventId"],"Clear replay")
 archive="set_personal_task_archive_self_api_v1";archived="personal_archived_tasks_day_self_api_v1"
 ok(o,archive,{"p_task_id":own_id,"p_archived":True})
 check(own_id not in ids(o,DAY,undated) and own_id in ids(o,archived,undated),"Archived undated recoverable")
 ok(o,archive,{"p_task_id":own_id,"p_archived":False})
 args1={**payload(PEER),"p_due_date":None}
 first=ok(o,create,args1);tid=first["task"]["id"]
 check(first["task"]["dueDate"] is None and first["assignment"]["revision"]==1,"Undated assignment atomic")
 replay=ok(o,create,args1)
 check(replay["task"]==first["task"] and replay["assignment"]["assignmentEventId"]==first["assignment"]["assignmentEventId"],"Shared undated exact replay")
 check(tid not in ids(o,DAY,undated) and tid in ids(o,SENT,{}) and tid in ids(w,DAY,undated) and tid not in ids(w,DAY,day),"Sent and received same original undated")
 read=ok(w,READ,exact(tid))
 check(read["ownerPersonId"]==OWNER and read["task"]["dueDate"] is None and read["ownerName"],"Sender provenance and null date")
 deny(x,READ,exact(tid));deny(x,DONE,{"p_task_id":tid,"p_done":True})
 deny(w,EDIT,{"p_task_id":tid,"p_expected_revision":0,"p_new_sentence":"Denied recipient edit","p_new_due_date":day["p_date"]})
 unchanged_failed(o,create,{**args1,"p_due_date":day["p_date"]},("23505",))
 ok(w,NOTE,note(tid,"Synthetic undated progress"))
 check(ok(w,DONE,{"p_task_id":tid,"p_done":True})["task"]["status"]=="done","Recipient can complete undated original")
 check(ok(w,DONE,{"p_task_id":tid,"p_done":False})["task"]["status"]=="open","Recipient can reopen undated original")
 race_args={**payload(PEER),"p_due_date":None}
 with ThreadPoolExecutor(max_workers=2) as pool:
  race=[f.result(timeout=40) for f in [pool.submit(ok,o,create,race_args) for _ in range(2)]]
 check(race[0]["task"]["id"]==race[1]["task"]["id"],"Concurrent null-date retry one original")
 ok(w,"household_identity_link_disconnect_self_api_v1",{"p_member_id":MEMBER})
 deny(w,READ,exact(tid));check(tid not in ids(w,DAY,undated),"Revocation removes undated access")
 check(sql("select count(*) from atlas.task_entries")==str(int(task_count)+3),"No duplicate original")
 check(sql("select count(*) from atlas.work_items")==work_count,"No parallel institutional copy")
 Path(args.output).write_text("PASS true undated Personal original, explicit date/clear, ownership, reciprocal assignment, archive, progress, retry and revocation.\\n")
if __name__=="__main__": main()

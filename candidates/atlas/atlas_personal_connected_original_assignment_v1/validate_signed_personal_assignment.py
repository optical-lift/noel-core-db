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
  check(code==200 and isinstance(body,dict) and body.get("ok") is True,f"{name} failed HTTP {code}; code={body.get('code') if isinstance(body,dict) else 'non-object'}")
  return body
 def deny(token,name,payload,codes=("42501",)):
  code,body=rpc(token,name,payload)
  check(code>=400 and code!=404 and isinstance(body,dict) and body.get("code") in codes,f"{name}: expected {codes}, got HTTP {code}")
 def ids(token,name,payload): return {row["id"] for row in ok(token,name,payload)["items"]}
 day={"p_date":"2030-11-04"};backlog={"p_date":"2030-11-05","p_limit":100}
 work_count=sql("select count(*) from atlas.work_items")
 initial=ok(o,READ,exact(A))
 check(initial["revision"]==0 and initial["primaryPersonId"]==OWNER and initial["choices"]==[],"Initial self only")
 deny(w,READ,exact(A));deny(o,CHANGE,change(A,0,PEER));deny(x,NOTES,exact(A))
 def connect():
  invite=ok(o,"household_identity_invite_create_self_api_v1",{"p_member_id":MEMBER})
  accepted=ok(w,"household_identity_invite_accept_self_api_v1",{"p_token":invite["token"]})
  check(accepted["state"]=="connected" and accepted["accessGranted"] is False,"Connection alone never grants task read")
 connect()
 check({q["personId"] for q in ok(o,READ,exact(A))["choices"]}=={PEER},"Owner sees only connected peer")
 check({q["personId"] for q in ok(w,READ,exact(B))["choices"]}=={OWNER},"Reciprocal choice without second invitation")
 check(ok(x,"create_atlas_task_self_api_v1",{"p_sentence":"Synthetic independent task","p_due_date":"2030-11-04","p_source_action_id":"clone-outsider-only"})["task"]["id"],"Outsider has actual personal authority")
 deny(w,READ,exact(A));deny(w,NOTES,exact(PRIVATE));deny(o,CHANGE,change(A,0,OUTSIDER))
 deny(o,CHANGE,change(TRANSFER,0,PEER),("23514",))
 deny(None,READ,exact(A),("42501","PGRST301"));deny(None,CHANGE,change(A,0,PEER),("42501","PGRST301"))
 before=ok(o,NOTE,note(A,"Synthetic note before share"))
 share=change(A,0,OWNER,[PEER])
 receipt=ok(o,CHANGE,share)
 check(receipt["taskId"]==A and receipt["revision"]==1 and receipt["acceptanceRequired"] is False and receipt["recipientAttested"] is False and receipt["newTaskCreated"] is False,"Exact non-acceptance assignment receipt")
 check(ok(o,CHANGE,share)["assignmentEventId"]==receipt["assignmentEventId"],"Same action same event")
 deny(o,CHANGE,change(A,0,PEER),("PT409",))
 check(A in ids(o,DAY,day) and A in ids(w,DAY,day) and A in ids(w,BACKLOG,backlog),"One original appears in both active readers")
 check(A not in ids(x,DAY,day) and PRIVATE not in ids(w,DAY,day),"Unrelated original remains private")
 deny(w,READ,exact(PRIVATE));deny(w,CHANGE,change(A,1,PEER));deny(x,NOTE,note(A,"Forbidden"))
 check(ok(w,READ,exact(A))["choices"]==[],"Recipient cannot browse sender contacts")
 second=ok(w,NOTE,note(A,"Synthetic recipient update"))
 hist=ok(o,NOTES,exact(A))["items"]
 check({n["progressId"] for n in hist}=={before["progressId"],second["progressId"]},"One original progress sequence")
 check(next(n for n in hist if n["progressId"]==second["progressId"])["authoredBySelf"] is False,"True author")
 check(next(n for n in ok(w,NOTES,exact(A))["items"] if n["progressId"]==second["progressId"])["authoredBySelf"] is True,"Recipient self attribution")
 completed=ok(w,DONE,{"p_task_id":A,"p_done":True})
 check(completed["task"]["id"]==A and completed["task"]["status"]=="done" and completed.get("completionEventId"),"Actual completing actor receipt")
 check(ok(o,DONE,{"p_task_id":A,"p_done":True})["idempotent"] is True,"No duplicate completion")
 check(sql(f"select count(*) from atlas.personal_task_shared_completion_events_v1 where task_id='{A}' and actor_person_id='{PEER}' and after_status='done'")=="1","Exactly one peer completion")
 check(ok(o,READ,exact(A))["task"]["status"]=="done","Shared completion observed")
 ok(w,DONE,{"p_task_id":A,"p_done":False})
 # Two different authenticated people issue Done concurrently on the shared original.
 # Use the same barrier pattern as the existing signed Work prerequisite proof.
 barrier=threading.Barrier(3)
 def finish(token):
  barrier.wait(timeout=10)
  return rpc(token,DONE,{"p_task_id":A,"p_done":True})
 with ThreadPoolExecutor(max_workers=2) as pool:
  one=pool.submit(finish,o);two=pool.submit(finish,w)
  barrier.wait(timeout=10)
  outcomes=[one.result(timeout=40),two.result(timeout=40)]
 check(all(code==200 and isinstance(body,dict) and body.get("ok") is True
  and body["task"]["id"]==A and body["task"]["status"]=="done"
  for code,body in outcomes),"Concurrent signed completion must converge")
 winners=[(actor,body) for actor,(_,body) in zip((OWNER,PEER),outcomes) if body.get("completionEventId")]
 retries=[body for _,body in outcomes if body.get("idempotent") is True]
 check(len(winners)==1 and len(retries)==1,"One completion event and one idempotent response")
 actor,event=winners[0]
 check(sql(f"select count(*) from atlas.personal_task_shared_completion_events_v1 where task_id='{A}' and after_status='done'")=="2","One new completion across concurrent requests")
 check(sql(f"select actor_person_id::text from atlas.personal_task_shared_completion_events_v1 where id='{event['completionEventId']}'")==actor,"Concurrent winner retains actual signed actor")
 ok(o,DONE,{"p_task_id":A,"p_done":False})
 sent=ok(o,CHANGE,change(A,1,PEER))
 check(sent["revision"]==2 and A not in ids(o,DAY,day) and A not in ids(o,BACKLOG,backlog),"Sent original leaves sender's active responsibility")
 check(A in ids(o,SENT,{}) and A in ids(w,DAY,day),"Sent original retained and recipient active")
 check(not ok(o,READ,exact(A))["assignedToSelf"],"Sender not assigned")
 # The sender retains text/date custody independent of active responsibility.
 edit=ok(o,EDIT_READ,exact(A))
 check(edit["canEdit"] is True and edit["taskId"]==A,"Exact sent owner may amend")
 deny(w,EDIT_READ,exact(A));deny(x,EDIT_READ,exact(A))
 changed_day={"p_date":"2030-11-03"}
 amendment={"p_task_id":A,"p_expected_revision":edit["amendmentRevision"],
  "p_new_sentence":"Synthetic sent amendment","p_new_due_date":changed_day["p_date"]}
 deny(w,EDIT,amendment);deny(x,EDIT,amendment)
 changed=ok(o,EDIT,amendment)
 check(changed["taskId"]==A and changed["amendmentRevision"]==edit["amendmentRevision"]+1
  and changed["oldDueDate"]==day["p_date"] and changed["oneOriginalTaskId"] is True,"Sent owner amendment receipt")
 reread=ok(o,EDIT_READ,exact(A))
 check(reread["sentence"]==amendment["p_new_sentence"] and reread["dueDate"]==changed_day["p_date"]
  and reread["amendmentRevision"]==changed["amendmentRevision"],"Independent exact owner readback")
 peer=ok(w,READ,exact(A))
 check(peer["task"]["sentence"]==reread["sentence"] and peer["task"]["dueDate"]==reread["dueDate"]
  and peer["revision"]==sent["revision"] and peer["primaryPersonId"]==PEER,"Recipient sees amended original without changing assignment")
 check(A not in ids(o,DAY,day) and A not in ids(o,DAY,changed_day)
  and A not in ids(w,DAY,day) and A in ids(w,DAY,changed_day) and A in ids(o,SENT,{}),"Moved original stays sent and only recipient day changes")
 check(ok(o,EDIT,amendment)["amendmentEventId"]==changed["amendmentEventId"],"Sent amendment replay preserves event")
 deny(o,EDIT,{**amendment,"p_new_sentence":"Stale different edit"},("PT409",))
 restored=ok(o,EDIT,{**amendment,"p_expected_revision":changed["amendmentRevision"],
  "p_new_sentence":edit["sentence"],"p_new_due_date":edit["dueDate"]})
 check(restored["amendmentRevision"]==changed["amendmentRevision"]+1 and A in ids(w,DAY,day)
  and A not in ids(o,DAY,day),"Restored date for remaining fictional lifecycle; responsibility retained")
 deny(o,DONE,{"p_task_id":A,"p_done":True})
 deny(o,"delete_unlinked_personal_task_self_api_v1",exact(A),("23514",))
 deny(o,"set_personal_task_archive_self_api_v1",{"p_task_id":A,"p_archived":True},("23514",))
 # Reverse direction uses the SAME relationship, not a second connection.
 ok(w,CHANGE,change(B,0,OWNER))
 check(B in ids(o,DAY,day) and B in ids(w,SENT,{}),"Reciprocal direct send")
 ok(w,"household_identity_link_disconnect_self_api_v1",{"p_member_id":MEMBER})
 deny(w,READ,exact(A));deny(w,NOTES,exact(A));deny(w,NOTE,note(A,"after disconnect"))
 deny(w,DONE,{"p_task_id":A,"p_done":True})
 deny(o,READ,exact(B));deny(o,CHANGE,change(A,2,PEER,[OWNER]))
 check(A not in ids(w,DAY,day) and B not in ids(o,DAY,day),"Both directions revoked")
 check(len(ok(o,NOTES,exact(A))["items"])==2,"Original shared history retained")
 connect()
 deny(w,READ,exact(A));deny(o,READ,exact(B))
 ok(o,CHANGE,change(A,2,OWNER))
 check(A in ids(o,DAY,day),"Explicit owner recovery")
 check(sql("select count(*) from atlas.work_items")==work_count,"No duplicate institutional Work")
 check(sql(f"select count(*) from atlas.task_entries where id='{A}'")=="1","Original remains unique")
 Path(args.output).write_text("PASS independent signed reciprocal send/share, one original/day/backlog, author, concurrent completion, sent amendment, replay, privacy, revoke/reconnect and recovery.\n")
 print("PASS connected original signed lifecycle")
if __name__=="__main__": main()

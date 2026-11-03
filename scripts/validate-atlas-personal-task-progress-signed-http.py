#!/usr/bin/env python3
"""Signed GoTrue/PostgREST original personal task progress. DISPOSABLE LOCAL ONLY."""
import argparse
import importlib.util
import re
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
 "atlas_work_auth",HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

TASK="a6300000-0000-4000-8000-000000000201"
DONE="a6300000-0000-4000-8000-000000000202"
ARCHIVED="a6300000-0000-4000-8000-000000000203"
TRANSFERRED="a6300000-0000-4000-8000-000000000204"
DELETE="a6300000-0000-4000-8000-000000000205"
FOREIGN="a6300000-0000-4000-8000-000000000206"
OWNER_PRINCIPAL="e5200000-0000-4000-8000-000000000111"
APPEND="append_personal_task_progress_self_api_v1"
READ="read_personal_task_progress_self_api_v1"
ACTION="33333333-3333-4333-8333-333333333331"

def check(ok,why): c1.check(ok,why)
def sql(db,s): return c1.sql(db,s)
def rpc(api,key,token,name,args): return c1.rpc(api,key,name,args,token)
def call(api,key,token,name,args):
 code,body=rpc(api,key,token,name,args)
 check(code==200 and isinstance(body,dict) and body.get("ok") is True,
       f"{name}: signed call failed HTTP {code} {str(body)[:400]}")
 return body
def denied(api,key,token,name,args,label,codes=("42501",)):
 code,body=rpc(api,key,token,name,args)
 check(code>=400 and code!=404 and isinstance(body,dict),
       f"{label}: expected real source denial, not HTTP {code} {body}")
 check(body.get("code") in codes,
       f"{label}: source code not {codes}: HTTP {code} {body}")
def a(task,ident,note):
 return {"p_task_id":task,"p_source_action_id":ident,"p_note":note}
def read(task,limit=50,cursor=None):
 p={"p_task_id":task,"p_limit":limit}
 if cursor:p.update(p_before_recorded_at=cursor["beforeRecordedAt"],
                    p_before_id=cursor["beforeId"])
 return p
def main():
 p=argparse.ArgumentParser()
 p.add_argument("--db-url",required=True);p.add_argument("--output",required=True)
 args=p.parse_args()
 check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
       "Refuse remote database for personal progress signed probe")
 check(sql(args.db_url,
    "select count(*) from atlas.task_entries where id::text like 'a6300000-%'")=="6",
       "Six synthetic task originals required")
 api,key=c1.local_status()
 base.setup_auth(args.db_url)
 sessions={}
 for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),("outsider",c1.OUTSIDER)):
  token,claims=c1.sign_in(api,key,name)
  check(claims.get("sub")==uid and claims.get("session_id"),
        "Genuine separate GoTrue session missing")
  check(sql(args.db_url,
    f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
        "Persisted local session missing")
  sessions[name]=token
 owner=sessions["owner"];second=sessions["worker"];outsider=sessions["outsider"]
 print("PASS signed distinct local owner, second owner, outsider sessions")
 initial_work=sql(args.db_url,"select count(*) from atlas.work_items")
 initial=call(api,key,owner,READ,read(TASK))
 check(initial.get("taskId")==TASK and initial.get("items")==[] and not initial.get("hasMore"),
       "Source-owned first progress read should be empty")
 own2=call(api,key,second,READ,read(FOREIGN))
 check(own2.get("taskId")==FOREIGN and own2.get("items")==[],
       "Independent owner should read only own original")
 for who,token in (("second owner",second),("outsider",outsider)):
  denied(api,key,token,READ,read(TASK),who+" foreign read")
  denied(api,key,token,APPEND,a(TASK,ACTION,"Forged note"),who+" foreign append")
 code,anon=rpc(api,key,None,READ,read(TASK))
 check(code in (401,403) and isinstance(anon,dict) and anon.get("code")!="PGRST202",
       "Anonymous read denial cannot be missing RPC")
 code,anon=rpc(api,key,None,APPEND,a(TASK,ACTION,"Forged"))
 check(code in (401,403) and isinstance(anon,dict) and anon.get("code")!="PGRST202",
       "Anonymous append denial cannot be missing RPC")
 print("PASS original-only reader/writer and anonymous denial")
 for task in (DONE,ARCHIVED,TRANSFERRED):
  denied(api,key,owner,APPEND,a(task,ACTION,"Forbidden"),"nonopen or transferred original",
         codes=("23514",))
 for payload in (a(TASK,ACTION,""),a(TASK,ACTION," "*6),
                 {"p_task_id":TASK,"p_source_action_id":None,"p_note":"Missing action"}):
  denied(api,key,owner,APPEND,payload,"invalid source note",codes=("22023",))
 first=call(api,key,owner,APPEND,a(TASK,ACTION,"I made progress."))
 check(first.get("taskId")==TASK and first.get("progressId") and
       first.get("idempotent") is False and first.get("note")=="I made progress.",
       "First progress did not have exact receipt")
 replay=call(api,key,owner,APPEND,a(TASK,ACTION,"I made progress."))
 check(replay.get("idempotent") is True and replay.get("progressId")==first.get("progressId"),
       "Same action should recover same original event")
 denied(api,key,owner,APPEND,a(TASK,ACTION,"Changed text"),"changed replay",codes=("PT409",))
 denied(api,key,owner,APPEND,a(DELETE,ACTION,"I made progress."),"reused action on different task",
        codes=("PT409",))
 for i in range(2,5):
  ident=f"33333333-3333-4333-8333-{i:012d}"
  call(api,key,owner,APPEND,a(TASK,ident,f"Progress note {i}."))
 page1=call(api,key,owner,READ,read(TASK,2))
 check(len(page1.get("items",[]))==2 and page1.get("hasMore") is True
       and page1.get("nextCursor"),"First bounded page and cursor missing")
 page2=call(api,key,owner,READ,read(TASK,2,page1["nextCursor"]))
 check(len(page2.get("items",[]))==2 and page2.get("hasMore") is False,
       "Second page lost previously recorded history")
 both={x["progressId"] for x in page1["items"]+page2["items"]}
 check(len(both)==4 and first["progressId"] in both,
       "Progress pages repeated or skipped source IDs")
 check(sql(args.db_url,f"select count(*) from atlas.personal_task_progress_events_v1 where task_id='{TASK}'")=="4",
       "Idempotent writer created duplicate events")
 check(sql(args.db_url,f"select status from atlas.task_entries where id='{TASK}'")=="open",
       "Progress note silently mutated Done state")
 check(sql(args.db_url,"select count(*) from atlas.work_items")==initial_work,
       "Personal note created or modified institutional Work")
 print("PASS progress original, idempotence, content conflict, history pages, no Work changes")
 sql(args.db_url,f"""update atlas.personal_atlas_access_grants
   set state='revoked',revoked_at=now() where principal_id='{OWNER_PRINCIPAL}'""")
 denied(api,key,owner,READ,read(TASK),"revoked read")
 denied(api,key,owner,APPEND,a(TASK,"77777777-7777-4777-8777-777777777777","After revoke"),
        "revoked append")
 sql(args.db_url,f"""update atlas.personal_atlas_access_grants
   set state='active',revoked_at=NULL where principal_id='{OWNER_PRINCIPAL}'""")
 cleanup=call(api,key,owner,APPEND,a(DELETE,"44444444-4444-4444-8444-444444444444","To delete."))
 check(cleanup.get("taskId")==DELETE,"Deletion target was not the original")
 deleted=call(api,key,owner,"delete_unlinked_personal_task_self_api_v1",{"p_task_id":DELETE})
 check(deleted.get("deletedTaskId")==DELETE and deleted.get("permanentlyDeleted") is True,
       "Original personal source did not confirm deletion")
 check(sql(args.db_url,f"select count(*) from atlas.personal_task_progress_events_v1 where task_id='{DELETE}'")=="0",
       "Original deletion left private progress orphan")
 print("PASS revoked existing signed session and permanent original privacy cascade")
 Path(args.output).write_text(
  "PASS signed local owner/second owner/outsider/anonymous, exact source append and "
  "read, page cursor, idempotent replay, stale/reused action, completed/archived/"
  "transferred and revoked denials, no Work shadow, original private cleanup.\n")

if __name__=="__main__":
 main()

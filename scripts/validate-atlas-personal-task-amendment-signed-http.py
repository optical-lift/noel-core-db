#!/usr/bin/env python3
"""Real local GoTrue/PostgREST personal-task amendment proof.
Disposable production-schema clone only: never contact remote APIs or write live data.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("atlas_work_base",
    HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

OWNER_PRINCIPAL="e5200000-0000-4000-8000-000000000111"
FOREIGN_PRINCIPAL="a6300000-0000-4000-8000-000000000112"
TASK="a6300000-0000-4000-8000-000000000201"
DONE="a6300000-0000-4000-8000-000000000202"
ARCHIVED="a6300000-0000-4000-8000-000000000203"
TRANSFERRED="a6300000-0000-4000-8000-000000000204"
DELETABLE="a6300000-0000-4000-8000-000000000205"
FOREIGN="a6300000-0000-4000-8000-000000000206"
READ="read_personal_task_text_date_self_api_v1"
AMEND="amend_personal_task_text_date_self_api_v1"
D0="2030-11-04"
D1="2030-11-05"

def check(ok,label):
    c1.check(ok,label)

def sql(db,statement):
    return c1.sql(db,statement)

def rpc(api,key,token,name,args):
    return c1.rpc(api,key,name,args,token)

def allow(api,key,token,name,args):
    code,body=rpc(api,key,token,name,args)
    check(code==200 and isinstance(body,dict) and body.get("ok") is True,
          f"{name}: expected signed success, got HTTP {code} {str(body)[:350]}")
    return body

def deny(api,key,token,name,args,label,codes=("42501",)):
    code,body=rpc(api,key,token,name,args)
    check(code>=400 and code!=404 and isinstance(body,dict),
          f"{label}: never accept 404/missing RPC, got {code} {body}")
    check(body.get("code") in codes,
          f"{label}: expected source error {codes}, got HTTP {code} {body}")
    return body

def amend_args(task,rev,text,day):
    return {"p_task_id":task,"p_expected_revision":rev,
      "p_new_sentence":text,"p_new_due_date":day}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
          "Refuse all nonlocal database URLs")
    check(sql(args.db_url,"select count(*) from atlas.task_entries where id::text like 'a6300000-%'")=="6",
          "Exactly six synthetic task originals required")
    api,key=c1.local_status()
    base.setup_auth(args.db_url)
    signed={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),
              f"{name} must hold a distinct signed GoTrue session")
        check(sql(args.db_url,
          f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
          "Session not persisted by local Auth")
        signed[name]=token
    owner,foreign,outsider=signed["owner"],signed["worker"],signed["outsider"]
    print("PASS independent signed local GoTrue sessions")
    before_count=sql(args.db_url,"select count(*) from atlas.work_items")
    original=allow(api,key,owner,READ,{"p_task_id":TASK})
    check(original.get("taskId")==TASK and original.get("amendmentRevision")==0 and
      original.get("sentence")=="Synthetic original one" and original.get("canEdit") is True,
      "Original owner reader lost identity, text or revision")
    other=allow(api,key,foreign,READ,{"p_task_id":FOREIGN})
    check(other.get("taskId")==FOREIGN and other.get("canEdit") is True,
      "Other Person cannot read their own synthetic original")
    deny(api,key,foreign,READ,{"p_task_id":TASK},"foreign task read")
    deny(api,key,outsider,READ,{"p_task_id":TASK},"unrelated task read")
    code,anon=rpc(api,key,None,READ,{"p_task_id":TASK})
    check(code in (401,403) and isinstance(anon,dict) and anon.get("code")!="PGRST202",
          "Anonymous denial must not be missing RPC")
    for name,token in (("other owner",foreign),("outsider",outsider)):
        deny(api,key,token,AMEND,amend_args(TASK,0,"Forgery",D0),name+" write")
    print("PASS owner/outsider/anonymous original isolation")
    for task,label in ((DONE,"completed"),(ARCHIVED,"archived"),(TRANSFERRED,"transferred")):
        deny(api,key,owner,AMEND,amend_args(task,0,"Forbidden",D0),label,
             codes=("23514",))
    print("PASS linked, completed and archived original write denial")
    first=allow(api,key,owner,AMEND,amend_args(TASK,0,"Corrected text",D0))
    check(first.get("taskId")==TASK and first.get("amendmentRevision")==1 and
          first.get("changed") is True and first.get("oldDueDate")==D0,
          "Text-only edit did not retain original and first revision")
    second=allow(api,key,owner,AMEND,amend_args(TASK,1,"Corrected text",D1))
    check(second.get("amendmentRevision")==2 and second.get("oldDueDate")==D0,
          "Date-only edit did not retain original and second revision")
    third=allow(api,key,owner,AMEND,amend_args(TASK,2,"Both corrected",D0))
    check(third.get("amendmentRevision")==3 and third.get("changed") is True,
          "Combined edit did not advance exact source once")
    noop=allow(api,key,owner,AMEND,amend_args(TASK,3,"Both corrected",D0))
    check(noop.get("changed") is False and noop.get("amendmentRevision")==3,
          "No-op manufactured history")
    replay=allow(api,key,owner,AMEND,amend_args(TASK,2,"Both corrected",D0))
    check(replay.get("idempotent") is True and replay.get("amendmentEventId")==third.get("amendmentEventId"),
          "Interrupted exact payload replay did not recover original receipt")
    deny(api,key,owner,AMEND,amend_args(TASK,0,"Older state",D1),
         "stale revision",codes=("PT409",))
    deny(api,key,owner,AMEND,amend_args(TASK,2,"Changed replay",D0),
         "conflicting replay",codes=("PT409",))
    check(sql(args.db_url,
      f"select count(*) from atlas.personal_task_amendment_events_v1 where task_id='{TASK}'")=="3",
      "Duplicate revisions or missing amendment history")
    final=allow(api,key,owner,READ,{"p_task_id":TASK})
    check(final.get("sentence")=="Both corrected" and final.get("dueDate")==D0 and
          final.get("amendmentRevision")==3 and final.get("taskId")==TASK,
          "Final original source reread differs")
    check(sql(args.db_url,"select count(*) from atlas.work_items")==before_count,
          "Editing personal original created or mutated institutional Work")
    print("PASS text, date, combined, noop, stale, exact retry, one original")
    # Revocation must take effect with the SAME existing signed session.
    sql(args.db_url,f"""update atlas.personal_atlas_access_grants
      set state='revoked',revoked_at=now() where principal_id='{OWNER_PRINCIPAL}'""")
    deny(api,key,owner,READ,{"p_task_id":TASK},"revoked Principal read")
    deny(api,key,owner,AMEND,amend_args(TASK,3,"After revoke",D0),"revoked Principal edit")
    sql(args.db_url,f"""update atlas.personal_atlas_access_grants
      set state='active',revoked_at=null where principal_id='{OWNER_PRINCIPAL}'""")
    print("PASS signed session cannot survive personal access revocation")
    changed=allow(api,key,owner,AMEND,amend_args(DELETABLE,0,"To delete",D0))
    check(changed.get("amendmentRevision")==1,"Deletion target amendment not recorded")
    deleted=allow(api,key,owner,"delete_unlinked_personal_task_self_api_v1",
      {"p_task_id":DELETABLE})
    check(deleted.get("ok") is True,"Signed original task deletion failed")
    check(sql(args.db_url,
      f"select count(*) from atlas.personal_task_amendment_events_v1 where task_id='{DELETABLE}'")=="0",
      "Permanent original deletion left orphaned private amendment text")
    check(sql(args.db_url,
      f"select count(*) from atlas.task_entries where id='{DELETABLE}'")=="0",
      "Permanent original deletion left task row")
    Path(args.output).write_text(
      "PASS signed GoTrue owner, second Person, outsider, anonymous; revision-checked original "
      "text-only, date-only, both, no-op, exact replay, conflict, transferred/completed/archived, "
      "revoked access and permanent deletion on a disposable clone\n")
    print("PASS all signed personal task amendment checks")

if __name__=="__main__":
    main()

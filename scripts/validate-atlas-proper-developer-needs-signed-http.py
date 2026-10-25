#!/usr/bin/env python3
"""Signed local-only create/read/note/transition probe of the developer Workbench.
Runs only on disposable production-schema clone; never uses real customer data.
"""
import argparse
import importlib.util
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("local_foundry",ROOT/"validate-shared-foundry-workspace-signed-http.py")
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base); c1=base.c1
SUBJECT="f1900000-0000-4000-8000-000000000499"
OTHER_SUBJECT="f1900000-0000-4000-8000-000000000498"
REQUEST="f1900000-0000-4000-8000-0000000009a1"
NEED="f1900000-0000-4000-8000-0000000009a2"
TRANSITION="f1900000-0000-4000-8000-0000000009a3"
NEW_TITLE="Track the real client workflow"
NEW_DETAIL="An original business capability is missing; confirm its operating path and then verify actual use."
def need(ok,text): c1.check(ok,text)
def rpc(api,key,token,fn,args):return c1.rpc(api,key,fn,args,token)
def deny(api,key,token,fn,args,label):
 status,result=rpc(api,key,token,fn,args)
 need(status in (401,403),label+": status "+str(status))
 print("PASS "+label)
def main():
 parser=argparse.ArgumentParser();parser.add_argument("--db-url",required=True);parser.add_argument("--output",required=True)
 args=parser.parse_args()
 need(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),"Signed probe must run on localhost only")
 db=lambda sql:c1.sql(args.db_url,sql)
 need(db("select count(*) from foundry.events where workspace_id like 'FW-FICTIONAL-INVENTORY-%'")=="3","Fictional two-format histories missing")
 api,key=c1.local_status();base.setup_auth(args.db_url)
 signed={}
 for label,uid in (("foundry-owner",base.OWNER),("foundry-other",base.OTHER),("foundry-noprincipal",base.NO_PRINCIPAL)):
  token,claims=c1.sign_in(api,key,label)
  need(claims.get("sub")==uid and claims.get("session_id"),"Genuine GoTrue session required")
  signed[label]=(token,claims)
 operator=signed["foundry-owner"][0]
 reader="implementation_discovery_subject_work_self_api_v1"
 writer="create_implementation_discovery_need_self_api_v1"
 activity="record_implementation_discovery_activity_self_api_v1"
 subject_args={"p_subject_entity_id":SUBJECT}
 create_args={"p_subject_entity_id":SUBJECT,"p_request_id":REQUEST,"p_title":NEW_TITLE,"p_detail":NEW_DETAIL}
 for who,tok in (("anonymous",None),("ordinary Principal",signed["foundry-other"][0]),("unbound user",signed["foundry-noprincipal"][0])):
  deny(api,key,tok,reader,subject_args,who+" cannot read cross-client work")
  deny(api,key,tok,writer,create_args,who+" cannot add developer needs")
 original={tbl:db("select count(*) from "+tbl) for tbl in ("foundry.events","atlas.implementation_cases","atlas.implementation_case_sources","foundry.workspace_authority_registry_v1")}
 status,before=rpc(api,key,operator,reader,subject_args)
 need(status==200 and before.get("items")==[] and before["sourceReadAuthorized"] is False,"Initial signed empty developer workspace failed")
 status,created=rpc(api,key,operator,writer,create_args)
 need(status==200 and created.get("ok") and created.get("created") is True,"Create developer need failed: "+str(created))
 need(db("select count(*) from atlas.implementation_discovery_needs_v1")=="1","Saved need not persisted in correct table")
 status,replay=rpc(api,key,operator,writer,create_args)
 need(status==200 and replay.get("created") is False and replay.get("needId")==created.get("needId"),"Idempotent create failed")
 changed=dict(create_args);changed["p_title"]="Different meaning same request"
 status,_=rpc(api,key,operator,writer,changed)
 need(status in (400,409,422),"Changed request content improperly accepted")
 status,after=rpc(api,key,operator,reader,subject_args)
 item=after["items"][0]
 need(status==200 and len(after["items"])==1 and item["detail"]==NEW_DETAIL and item["state"]=="identified","Persisted developer work inaccessible")
 need(item["activity"][0]["kind"]=="opened","Missing append-only provenance")
 need("synthetic confidential example" not in str(after) and "original_private_source" not in str(after),"Private Foundry testimony leaked")
 need(item["id"]==created["needId"],"Need identity not stable")
 note_args={"p_need_id":item["id"],"p_request_id":NEED,"p_action":"note",
            "p_note":"Testable developer observation with specific next steps.","p_next_state":None}
 status,note_result=rpc(api,key,operator,activity,note_args)
 need(status==200 and note_result.get("ok"),"Append note failed "+str(note_result))
 status,replayed=rpc(api,key,operator,activity,note_args)
 need(status==200 and replayed.get("replayed") is True,"Note retry not idempotent")
 altered=dict(note_args);altered["p_note"]="Changed notes must not reuse prior UUID."
 status,_=rpc(api,key,operator,activity,altered)
 need(status in (400,409,422),"Conflicting replay changed original note")
 transition_args={"p_need_id":item["id"],"p_request_id":TRANSITION,"p_action":"state_changed",
                  "p_note":"Engineering has started validating the underlying operating path.","p_next_state":"building"}
 status,transition=rpc(api,key,operator,activity,transition_args)
 need(status==200 and transition.get("ok"),"Development state transition failed "+str(transition))
 status,latest=rpc(api,key,operator,reader,subject_args)
 need(status==200 and latest["items"][0]["state"]=="building" and len(latest["items"][0]["activity"])==3,"Date-stamped state and note did not persist")
 status,second=rpc(api,key,operator,reader,{"p_subject_entity_id":OTHER_SUBJECT})
 need(status==200 and second["items"]==[],"Developer note incorrectly leaked to another business")
 for tbl,count in original.items():
  need(db("select count(*) from "+tbl)==count,"Developer work must never mutate original source or cases: "+tbl)
 db("delete from auth.sessions where id='"+signed["foundry-owner"][1]["session_id"]+"'::uuid")
 deny(api,key,operator,reader,subject_args,"revoked operator cannot read")
 deny(api,key,operator,writer,{**create_args,"p_request_id":"f1900000-0000-4000-8000-0000000009a4"},"revoked operator cannot write")
 Path(args.output).write_text("PASS signed operator, denied anonymous/ordinary/unbound/revoked, real needs + notes + updates, idempotence, no source/case mutation or testimony access\n")
 print("PASS Atlas Proper actioned developer work")
if __name__=="__main__":main()

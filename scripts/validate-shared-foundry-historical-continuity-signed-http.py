#!/usr/bin/env python3
"""Signed LOCAL GoTrue + PostgREST proof for historical Foundry continuity.
Runs only in a disposable full-schema clone with fictional subjects.
Does not access a production API, real mailbox, or real Foundry archive.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("foundry_base",
 HERE/"validate-shared-foundry-workspace-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

WID="FW-FICTIONAL-001"
CANDIDATES="list_foundry_historical_recovery_candidates_self_api_v1"
CLAIM="recover_foundry_historical_workspace_self_api_v1"
HISTORY="list_foundry_workspace_history_self_api_v1"
EVENT="get_foundry_workspace_event_self_api_v1"
CONTEXT="get_foundry_existing_implementation_context_self_api_v1"
HANDOFF="identify_foundry_as_personal_implementation_source_self_api_v1"
OWNER="f1900000-0000-4000-8000-000000000201"

def need(ok,message): c1.check(ok,message)
def query(db,q): return c1.sql(db,q)
def call(api,key,token,fn,args): return c1.rpc(api,key,fn,args,token)
def yes(api,key,token,fn,args,label):
  status,body=call(api,key,token,fn,args)
  need(status==200 and isinstance(body,dict) and body.get("ok") is True,
       f"{label}: got {status} {str(body)[:300]}")
  print("PASS",label)
  return body
def no(api,key,token,fn,args,label):
  status,body=call(api,key,token,fn,args)
  need(status in (401,403) and isinstance(body,dict),
       f"{label}: unexpected response {status} {str(body)[:300]}")
  if token:
    need(body.get("code")=="42501",
       f"{label}: wrong denial {str(body)[:300]}")
  print("PASS",label)

def main():
  parser=argparse.ArgumentParser()
  parser.add_argument("--db-url",required=True)
  parser.add_argument("--output",required=True)
  args=parser.parse_args()
  need(bool(re.fullmatch(
    r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
    "Historical Foundry signed proof refuses remote DB")
  need(query(args.db_url,
    "select count(*) from foundry.events where workspace_id='FW-FICTIONAL-001'")=="2",
    "Fictional original event fixture missing")
  need(query(args.db_url,
    "select count(*) from atlas.principal_ledger_authorities where principal_id='"+
     OWNER+"'::uuid and status='active'")=="2",
    "Fictional source owner's two roots missing")
  api,key=c1.local_status()
  base.setup_auth(args.db_url)
  signed={}
  for label,uid in (("foundry-owner",base.OWNER),("foundry-other",base.OTHER),
                    ("foundry-noprincipal",base.NO_PRINCIPAL)):
    token,claims=c1.sign_in(api,key,label)
    need(claims.get("sub")==uid and claims.get("session_id"),
         "Real local signed JWT/session missing")
    signed[label]=(token,claims)
  owner=signed["foundry-owner"][0]
  other=signed["foundry-other"][0]
  unbound=signed["foundry-noprincipal"][0]
  no(api,key,None,CANDIDATES,{},"anonymous recovery candidate index")
  no(api,key,unbound,CANDIDATES,{},"unbound signed Principal index")
  owner_index=yes(api,key,owner,CANDIDATES,{},"signed owner lists matching original")
  need(len(owner_index.get("items",[]))==1,"Owner candidate must be exact")
  owner_item=owner_index["items"][0]
  need(owner_item.get("workspaceId")==WID and owner_item.get("eventCount")==2,
       "Original source candidate or count changed")
  other_index=yes(api,key,other,CANDIDATES,{},"shared root has non-disclosing index")
  need(all(x.get("workspaceId")!=WID for x in other_index.get("items",[])),
       "Partial-Ledger governor must never see private original")
  claim_args={"p_workspace_id":WID,
   "p_request_id":"f1900000-0000-4000-8000-000000000701",
   "p_confirm_original_history":True}
  no(api,key,None,CLAIM,claim_args,"anonymous historical claim")
  no(api,key,other,CLAIM,claim_args,"second root cannot take source")
  no(api,key,unbound,CLAIM,claim_args,"unbound user cannot claim")
  status,not_confirmed=call(api,key,owner,CLAIM,
    {**claim_args,"p_confirm_original_history":False})
  need(status>=400,"Claim cannot proceed without explicit human confirmation")
  original={
    "events":query(args.db_url,
      "select string_agg(event_id,',' order by sequence) from foundry.events "+
      "where workspace_id='FW-FICTIONAL-001'"),
    "case":query(args.db_url,
      "select count(*) from atlas.implementation_cases"),
    "ledgers":query(args.db_url,"select count(*) from ledger.ledgers")
  }
  done=yes(api,key,owner,CLAIM,claim_args,"signed owner recovers SAME original workspace")
  need(done.get("workspaceId")==WID and done.get("originalEventCount")==2
       and done.get("replayed") is False and done.get("canonicalAtlasMutation") is False,
       "Recovery did not preserve originals or truth boundary")
  replay=yes(api,key,owner,CLAIM,claim_args,"replayed claim is idempotent")
  need(replay.get("replayed") is True,
       "Same UUID must not create another claim")
  need(query(args.db_url,
    "select count(*) from foundry.events where workspace_id='FW-FICTIONAL-001'")=="3",
       "Recovery receipt should be exactly one append")
  need(query(args.db_url,
    "select string_agg(event_id,',' order by sequence) from foundry.events "+
    "where workspace_id='FW-FICTIONAL-001' and sequence<=2")==original["events"],
    "Historic event IDs or order changed")
  no(api,key,None,HISTORY,{"p_workspace_id":WID},"anonymous original history")
  no(api,key,other,HISTORY,{"p_workspace_id":WID},"shared root original history denied")
  no(api,key,unbound,HISTORY,{"p_workspace_id":WID},"unbound original history denied")
  page=yes(api,key,owner,HISTORY,
    {"p_workspace_id":WID,"p_after_sequence":0,"p_limit":2},
    "owner reads chronological page")
  need([x["sequence"] for x in page.get("items",[])]==[1,2]
       and page.get("totalEvents")==3 and page.get("nextAfterSequence")==2,
       "Original ordering and cursor failed")
  second=yes(api,key,owner,HISTORY,
    {"p_workspace_id":WID,"p_after_sequence":2,"p_limit":2},
    "owner continues chronology")
  need([x["sequence"] for x in second.get("items",[])]==[3],
       "Recovery receipt missing from history")
  no(api,key,other,EVENT,
    {"p_workspace_id":WID,"p_event_id":"fictional-old-event-1"},
    "separate Principal cannot inspect full original")
  detail=yes(api,key,owner,EVENT,
    {"p_workspace_id":WID,"p_event_id":"fictional-old-event-1"},
    "signed owner opens exact historical envelope")
  need(detail.get("envelope",{}).get("provisional_subject",{}).get("label")
       =="Fictional source subject","Original envelope was not preserved")
  context=yes(api,key,owner,CONTEXT,{"p_workspace_id":WID},
    "owner sees existing case and Ledger onboarding references")
  need(context.get("caseWasCreated") is False and context.get("ledgerWasCreated") is False
       and context.get("sourceAccessGrant") is False
       and len(context.get("ledgers",[]))==2
       and context.get("personalImplementationCaseId"),
       "Context must reference existing records, not create authority")
  no(api,key,other,CONTEXT,{"p_workspace_id":WID},
     "partial-Ledger governor cannot infer private case context")
  no(api,key,other,HANDOFF,{"p_workspace_id":WID},
     "partial-Ledger governor cannot register original source")
  linked=yes(api,key,owner,HANDOFF,{"p_workspace_id":WID},
     "owner identifies existing source in existing Personal Implementation case")
  again=yes(api,key,owner,HANDOFF,{"p_workspace_id":WID},
     "repeated source handoff remains idempotent")
  need(linked.get("implementationCaseSourceId")==again.get("implementationCaseSourceId")
       and linked.get("sourceState")=="identified"
       and linked.get("sourceReadAuthorized") is False
       and linked.get("caseWasCreated") is False,
       "Source identification granted access or duplicated record")
  need(query(args.db_url,"select count(*) from atlas.implementation_cases")==original["case"]
       and query(args.db_url,"select count(*) from ledger.ledgers")==original["ledgers"],
       "Handoff may not duplicate Personal Case or Ledger")
  need(query(args.db_url,
    "select count(*) from atlas.implementation_case_sources where "+
    "provider_key='foundry_workspace' and source_state='identified' "+
    "and authorized_by_user_id is null")=="1",
       "Identified source must not become connected/authorized")
  query(args.db_url,
    f"delete from auth.sessions where id='{signed['foundry-owner'][1]['session_id']}'::uuid")
  no(api,key,owner,HISTORY,{"p_workspace_id":WID},
     "revoked real session denied historical read")
  no(api,key,owner,HANDOFF,{"p_workspace_id":WID},
     "revoked real session denied source identification")
  no(api,key,owner,CLAIM,claim_args,
     "revoked real session denied idempotent claim")
  Path(args.output).write_text(
    "PASS fictional signed GoTrue owner, shared governor, anonymous, unbound, "+
    "original preservation, cursor, idempotence, case handoff, revoked session\n",
    encoding="utf-8")
  print("PASS signed historical Foundry continuation")

if __name__=="__main__":main()

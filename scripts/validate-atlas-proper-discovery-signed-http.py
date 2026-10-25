#!/usr/bin/env python3
"""Local signed proof for Atlas Proper's read-only Foundry inventory.
Never contacts production or sees real historical source material.
"""
import argparse
import importlib.util
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
 "existing_signed_foundry",ROOT/"validate-shared-foundry-workspace-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
RPC="implementation_foundry_discovery_inventory_self_api_v1"

def need(condition,message):
 c1.check(condition,message)

def request(api,key,token):
 return c1.rpc(api,key,RPC,{},token)

def denied(api,key,token,label):
 status,response=request(api,key,token)
 need(status in (401,403) and isinstance(response,dict),
      f"{label}: expected denial, got {status}")
 if token is not None:
  need(response.get("code")=="42501",f"{label}: expected 42501")
 print("PASS",label)

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--db-url",required=True)
 parser.add_argument("--output",required=True)
 args=parser.parse_args()
 need(bool(re.fullmatch(
  r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
  args.db_url)),"Never use a remote database for signed inventory tests")
 db=lambda sql:c1.sql(args.db_url,sql)
 need(db("select count(*) from foundry.events where workspace_id like 'FW-FICTIONAL-INVENTORY-%'")=="3",
      "Two fictional source formats are required")
 api,key=c1.local_status()
 base.setup_auth(args.db_url)
 signed={}
 for label,uid in (("foundry-owner",base.OWNER),
                   ("foundry-other",base.OTHER),
                   ("foundry-noprincipal",base.NO_PRINCIPAL)):
  token,claims=c1.sign_in(api,key,label)
  need(claims.get("sub")==uid and claims.get("session_id"),
       "Genuine local signed session missing")
  signed[label]=(token,claims)
 operator=signed["foundry-owner"][0]
 ordinary=signed["foundry-other"][0]
 outsider=signed["foundry-noprincipal"][0]

 denied(api,key,None,"anonymous cannot enumerate clients")
 denied(api,key,ordinary,"ordinary signed Principal has no operator access")
 denied(api,key,outsider,"signed user without practitioner rights denied")
 before={table:db("select count(*) from "+table) for table in
   ("foundry.events","ledger.ledgers","atlas.implementation_cases",
    "atlas.implementation_case_sources","foundry.workspace_authority_registry_v1")}
 status,result=request(api,key,operator)
 need(status==200 and isinstance(result,dict) and result.get("ok") is True,
      f"Active independent practitioner inventory failed: {status} {str(result)[:260]}")
 need(result.get("contractVersion")=="atlas_proper_discovery_inventory_v1",
      "Wrong inventory contract")
 for prop in ("caseCreated","sourceReadAuthorized","canonicalMutation","aiCarrierAccess"):
  need(result.get(prop) is False,prop+" must be false")
 items=result.get("items",[])
 need(len(items)==2,"Both resolved business Foundry formats must project")
 summaries={item["subjectLabel"]:item for item in items}
 need(set(summaries)=={"Fictional Company A","Fictional Company B"},
      "Only two verified institutional subjects allowed")
 need(len(summaries["Fictional Company A"]["ledgers"])==1 and
      len(summaries["Fictional Company B"]["ledgers"])==1,
      "Canonical Ledger resolution incorrect")
 need(summaries["Fictional Company A"]["archives"][0]["eventCount"]==2 and
      summaries["Fictional Company B"]["archives"][0]["eventCount"]==1,
      "Original Foundry event counts incorrect")
 for item in items:
  need(item["caseAssociation"]=="not_evaluated" and
       item["requirementStatus"]=="not_yet_adjudicated" and
       item["originalTestimonyIncluded"] is False,
       "Inventory inferred Implementation truth")
  for archive in item["archives"]:
   need(archive["sourceAccess"]=="not_granted" and
        archive["reviewState"]=="awaiting_scoped_source_review",
        "Source content or permission was promoted")
  need(all(ledger["onboardingState"]=="completed" for ledger in item["ledgers"]),
       "Existing Ledger onboarding must be read, not rerun")
 forbidden=("original_private_source","synthetic confidential example",
            "envelope","payload","eventTypes")
 need(not any(value in str(result) for value in forbidden),
      "A private envelope or inferred research claim leaked into inventory")
 status,again=request(api,key,operator)
 need(status==200 and again==result,"Read-only inventory must be repeatable")
 for table,count in before.items():
  need(db("select count(*) from "+table)==count,
       "Discovery must not mutate "+table)
 db("delete from auth.sessions where id='"+
    signed["foundry-owner"][1]["session_id"]+"'::uuid")
 denied(api,key,operator,"revoked operator session is denied immediately")
 Path(args.output).write_text(
  "PASS real local GoTrue practitioner/ordinary/outsider/anonymous, "
  "two canonical Foundry encodings, metadata-only, idempotence, "
  "zero customer mutations and session revocation\n",encoding="utf8")
 print("PASS Atlas Proper inventory signed isolation")

if __name__=="__main__":
 main()

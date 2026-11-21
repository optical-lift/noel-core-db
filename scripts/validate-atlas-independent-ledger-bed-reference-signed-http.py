#!/usr/bin/env python3
"""Held first proof: independent Venue Ledger Work references original Flower Bed.

Run ONLY on a disposable local PG17 full-schema clone with four real local
GoTrue sessions and PostgREST. Never contact production. This script is
NOT currently wired into protected CI; no PASS is claimed until executed.
Requires C1 + fictional_venue_extension fixture, HELD_source_candidate.sql
for ledger_work_existing_object_reference_v1, and clone_test_api_DISPOSABLE_ONLY.
The OLD Flower->Venue offer/accept code is NOT an input or prerequisite.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import re
import uuid
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "independent_ledger_fixture",
    HERE/"validate-atlas-work-prerequisite-signed-http.py")
if spec is None or spec.loader is None:
    raise RuntimeError("Required signed local GoTrue fixture helper not available")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

ORG=c1.ORG
FLOWER=c1.LEDGER_A
VENUE=c1.LEDGER_B
BED="e5200000-0000-4000-8000-000000000b03"
VENUE_WORK="e5200000-0000-4000-8000-000000000b20"
FLOWER_WORK="e5200000-0000-4000-8000-000000000901"
VENUE_PERSON="e5200000-0000-4000-8000-000000000103"
RPC="clone_test_ledger_work_existing_bed_reference_v1"

def check(ok,reason):
    if not ok: raise AssertionError(reason)

def literal(x):
    return "'"+str(x).replace("'","''")+"'"

def sql(db,s):
    return c1.sql(db,s)

def args_for(work=VENUE_WORK,bed=BED,action="venue-independent-bed-reference"):
    return {
        "p_organization_id":ORG,
        "p_ledger_id":VENUE,
        "p_work_item_id":work,
        "p_bed_id":bed,
        "p_source_action_id":action,
    }

def rpc(api,key,token,payload):
    return c1.rpc(api,key,RPC,payload,token)

def deny(api,key,token,payload,label):
    code,data=rpc(api,key,token,payload)
    check(code in (401,403) and isinstance(data,dict) and
          data.get("code")=="42501",
          f"{label}: expected source-level 42501 denial, got HTTP {code}: {str(data)[:200]}")
    print("PASS",label)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(
        r"postgres(?:ql)?://[^@\s]+@127[.]0[.]0[.]1:[0-9]+/postgres",
        args.db_url)),"Refuse non-local database or protected production source")
    db=args.db_url
    check(sql(db,"SELECT current_setting('server_version_num')::integer/10000")=="17",
          "PG17 disposable full-schema clone required")
    api,key=c1.local_status()
    check(sql(db,"SELECT count(*) FROM atlas.growing_objects WHERE id="+
        literal(BED)+"::uuid AND stable_key='clone-upick-bed-3'")=="1",
          "Fictional original Flower Bed 3 missing")
    check(sql(db,"SELECT count(*) FROM atlas.work_items WHERE id="+
        literal(VENUE_WORK)+"::uuid AND work_state='open'")=="1",
          "Fictional existing Venue Work missing")
    check(sql(db,"SELECT count(*) FROM atlas.company_work_native_ledger_relevance WHERE "+
        "work_item_id="+literal(VENUE_WORK)+"::uuid AND ledger_id="+
        literal(VENUE)+"::uuid AND attribution_state='active'")=="1",
          "Real source relevance to Venue Work must be fixture-established")
    check(sql(db,"SELECT atlas.person_has_native_ledger_connection_v1('"+
        ORG+"'::uuid,'"+VENUE+"'::uuid,'"+VENUE_PERSON+"'::uuid)")=="t",
          "Venue governor must have actual source-current native connection")
    before_work=int(sql(db,"SELECT count(*) FROM atlas.work_items"))
    before_beds=int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))
    before_flower_custody=int(sql(db,
        "SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 WHERE "+
        "ledger_id="+literal(FLOWER)+"::uuid AND custody_state='active'"))
    before_context=int(sql(db,"SELECT count(*) FROM atlas.work_item_context_links"))
    before_refs=int(sql(db,"SELECT count(*) FROM atlas.ledger_work_existing_bed_references_v1"))

    base.setup_auth(db)
    actors={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("role")=="authenticated"
              and bool(claims.get("session_id")),
              "Independent signed GoTrue identity required: "+name)
        check(sql(db,"SELECT count(*) FROM auth.sessions WHERE id="+
             literal(claims["session_id"])+"::uuid AND user_id="+
             literal(uid)+"::uuid")=="1",
             "Session must really exist in local auth.sessions")
        actors[name]=(token,claims)

    venue=actors["outsider"][0]
    deny(api,key,actors["owner"][0],args_for(),
         "Flower root cannot write Venue reference just by owning Bed")
    deny(api,key,actors["worker"][0],args_for(),
         "Flower worker cannot borrow Venue author's permission")
    deny(api,key,actors["no-seat"][0],args_for(),
         "No-seat Person cannot attach Venue Work to Bed")
    deny(api,key,venue,args_for(work=FLOWER_WORK),
         "Venue governor cannot link Flower-only Work as Venue Work")
    deny(api,key,venue,args_for(bed="e5200000-0000-4000-8000-00000000dead"),
         "Venue governor cannot manufacture nonexistent physical Bed")

    code,result=rpc(api,key,venue,args_for())
    check(code==200 and isinstance(result,dict) and result.get("ok") is True
          and result.get("idempotent") is False,
          f"Genuine independently authorized Venue reference failed: HTTP {code}: {str(result)[:180]}")
    ref=str(uuid.UUID(result["referenceId"]))
    check(result.get("workItemId")==VENUE_WORK and result.get("bedId")==BED
          and result.get("ledgerId")==VENUE,
          "Reference must carry exact existing original identities")
    check(result.get("newWorkCreated") is False
          and result.get("newObjectCreated") is False
          and result.get("physicalCustodyChanged") is False
          and result.get("otherLedgerReadGranted") is False,
          "Reference-only receipt must not imply physical rights or duplicate data")
    check(set(result)=={
        "ok","referenceId","idempotent","ledgerId","workItemId","bedId",
        "newWorkCreated","newObjectCreated","physicalCustodyChanged",
        "otherLedgerReadGranted"},
        "No private Bed condition, metadata or foreign-Ledger Work may leak via receipt")
    code,replay=rpc(api,key,venue,args_for())
    check(code==200 and replay.get("idempotent") is True
          and replay.get("referenceId")==ref,
          "Replay must return the same one reference, not duplicate it")
    code,collision=rpc(api,key,venue,args_for(
        bed="e5200000-0000-4000-8000-000000000b04"))
    check(code==409 and isinstance(collision,dict)
          and collision.get("code")=="23505",
          "Changed Bed under same action key must be rejected")
    check(sql(db,"SELECT count(*) FROM atlas.ledger_work_existing_bed_references_v1")==
          str(before_refs+1),"Only one new target Ledger reference may exist")
    check(sql(db,"SELECT recorded_by_person_id FROM atlas.ledger_work_existing_bed_references_v1 "+
          "WHERE id="+literal(ref)+"::uuid")==VENUE_PERSON,
          "Real Venue Person must be historically attributed")
    check(sql(db,"SELECT count(*) FROM atlas.work_items")==str(before_work),
          "No Work duplicated by reference")
    check(sql(db,"SELECT count(*) FROM atlas.growing_objects")==str(before_beds),
          "No real-world Bed duplicated by reference")
    check(sql(db,"SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 WHERE "+
          "ledger_id="+literal(FLOWER)+"::uuid AND custody_state='active'")==
          str(before_flower_custody),"Flower custody must remain unchanged")
    check(sql(db,"SELECT count(*) FROM atlas.work_item_context_links")==str(before_context),
          "Existing Flower physical Work guard must NOT be bypassed by writing context")
    check(sql(db,"SELECT work_state FROM atlas.work_items WHERE id="+
          literal(VENUE_WORK)+"::uuid")=="open",
          "Referencing does not complete Venue original Work")

    # An existing GoTrue JWT must stop authorizing at the next operation once
    # its actual session has been removed from the disposable local database.
    claims=actors["outsider"][1]
    sql(db,"DELETE FROM auth.sessions WHERE id="+literal(claims["session_id"])+"::uuid")
    deny(api,key,venue,args_for(action="revoked-same-token-reference"),
         "Revoked current signed Venue session cannot establish new reference")

    print("PASS independent Venue original Work -> one original Flower Bed reference")
    print("PASS no Flower offer/accept input, no Bed/Work duplication, no crop custody transfer")
    print("HELD: real signed clone execution is the required proof; no production release")
    Path(args.output).write_text(json.dumps({
      "contract":"independent_native_ledger_original_bed_reference_v1",
      "status":"PASS","referenceId":ref,"existingWorkId":VENUE_WORK,
      "originalBedId":BED,"noNewBed":True,"noNewWork":True,
      "separateFlowerCustody":True,"revokedSessionDenied":True
    },indent=2)+"\n")

if __name__=="__main__":
    main()

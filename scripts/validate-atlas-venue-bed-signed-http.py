#!/usr/bin/env python3
"""TRUE signed local GoTrue -> PostgREST Venue-use test. DISPOSABLE CLONE ONLY.

The public "clone_test_*" RPCs exist only in disposable-clone SQL. The held
source procedures remain ungranted in real Noel. Never contact production.
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
    "venue_signed_source_base",HERE/"validate-atlas-work-prerequisite-signed-http.py")
if spec is None or spec.loader is None:
    raise RuntimeError("Existing signed auth fixture helper required")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

FLOWER=c1.LEDGER_A
VENUE=c1.LEDGER_B
BED="e5200000-0000-4000-8000-000000000b03"
OTHER_BED="e5200000-0000-4000-8000-000000000b05"
VENUE_WORK="e5200000-0000-4000-8000-000000000b20"
WRONG_WORK="e5200000-0000-4000-8000-000000000901"
VENUE_PERSON="e5200000-0000-4000-8000-000000000103"
FLOWER_PERSON="e5200000-0000-4000-8000-000000000101"
RPCS={
  "offer":"clone_test_venue_bed_offer_v1",
  "accept":"clone_test_venue_bed_accept_v1",
  "link":"clone_test_venue_bed_link_v1",
  "withdraw":"clone_test_venue_bed_withdraw_v1",
}

def check(ok,why):
    if not ok: raise AssertionError(why)

def lit(value):
    return "'"+str(value).replace("'","''")+"'"

def sql(db,statement):
    return c1.sql(db,statement)

def user_rpc(api,key,token,method,args):
    return c1.rpc(api,key,RPCS[method],args,token)

def accepted(api,key,token,method,args,expect="uuid"):
    code,result=user_rpc(api,key,token,method,args)
    check(code==200,f"Signed accepted {method} was HTTP {code}; the local source did not allow it")
    if expect=="uuid":
        check(isinstance(result,str),"Accepted source must return one UUID only")
        return str(uuid.UUID(result))
    check(expect=="bool" and result is True,"Expected boolean accepted receipt")
    return True

def refused(api,key,token,method,args,reason):
    code,body=user_rpc(api,key,token,method,args)
    check(code in (401,403) and isinstance(body,dict),
        f"{reason}: expected actual signed source denial, got HTTP {code}")
    check(body.get("code")=="42501",
        f"{reason}: denial must come from SQL authorization, not missing RPC or caller syntax")
    print("PASS",reason)

def offer_args(bed=BED,action="venue-offer-a"):
    return {
      "p_flower_ledger_id":FLOWER,"p_venue_ledger_id":VENUE,
      "p_bed_id":bed,"p_source_action_id":action,
    }

def accept_args(offer):
    return {"p_offer_id":offer}

def link_args(use,work=VENUE_WORK,action="venue-work-link-a",
              reviewed_key="disposable-venue-work-near-bed",
              reviewed_bed="clone-upick-bed-3"):
    return {
      "p_use_authorization_id":use,
      "p_work_item_id":work,"p_source_action_id":action,
      "p_human_review":{
        "humanConfirmed":True,
        "reviewedWorkStableKey":reviewed_key,
        "reviewedBedStableKey":reviewed_bed
      }
    }

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(
      r"postgres(?:ql)?://[^@\s]+@127[.]0[.]0[.]1:[0-9]+/postgres",
      args.db_url)),"Refuse non-local protected source or production database")
    db=args.db_url
    api,key=c1.local_status()
    check(sql(db,"SELECT current_setting('server_version_num')::integer/10000")=="17",
      "Only PG17 disposable clone is admissible")
    check(sql(db,"SELECT count(*) FROM atlas.growing_objects WHERE id="
      +lit(BED)+"::uuid AND stable_key='clone-upick-bed-3'")=="1",
      "Fictional original Bed not present")
    check(sql(db,"SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 WHERE "
      "ledger_id="+lit(FLOWER)+"::uuid AND custody_state='active'")=="1",
      "Fictional Flower original custody missing")
    check(sql(db,"SELECT count(*) FROM atlas.principal_ledger_authorities WHERE "
      "ledger_id="+lit(VENUE)+"::uuid AND status='active' AND authority_kind='root_governing'")=="1",
      "Distinct Venue governing Principal not established by fictional source")

    base.setup_auth(db)
    actors={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("role")=="authenticated"
              and bool(claims.get("session_id")), "Genuine GoTrue identity mismatch: "+name)
        check(sql(db,"SELECT count(*) FROM auth.sessions WHERE id="
                  +lit(claims["session_id"])+"::uuid AND user_id="+lit(uid)+"::uuid")=="1",
              "GoTrue session not persisted locally: "+name)
        actors[name]=(token,claims)
    owner=actors["owner"][0]
    venue=actors["outsider"][0]
    worker=actors["worker"][0]
    noseat=actors["no-seat"][0]
    print("PASS four independent genuinely signed local actors")

    # Neither role names nor editable claims allow worker authority.
    refused(api,key,worker,"offer",offer_args(),"ordinary Flower worker cannot offer Bed")
    refused(api,key,noseat,"offer",offer_args(),"unseated Person cannot offer Bed")
    refused(api,key,venue,"offer",offer_args(),"Venue root cannot forge Flower offer")
    refused(api,key,owner,"offer",offer_args(bed="e5200000-0000-4000-8000-00000000dead"),
            "Flower owner cannot offer nonexistent Bed")
    baseline_work=int(sql(db,"SELECT count(*) FROM atlas.work_items"))
    baseline_bed=int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))
    baseline_context=int(sql(db,"SELECT count(*) FROM atlas.work_item_context_links"))
    offer=accepted(api,key,owner,"offer",offer_args())
    check(accepted(api,key,owner,"offer",offer_args())==offer,
          "Source action replay must be idempotent")
    check(sql(db,"SELECT use_state FROM atlas.venue_bed_shared_use_authorizations_v1 "
       "WHERE id="+lit(offer)+"::uuid")=="offered","Offer must not grant use by itself")

    refused(api,key,owner,"accept",accept_args(offer),
            "Flower root cannot accept as a Venue root")
    refused(api,key,worker,"accept",accept_args(offer),
            "Ordinary worker cannot accept Venue use")
    refused(api,key,noseat,"accept",accept_args(offer),
            "No-seat actor cannot accept Venue use")
    refused(api,key,venue,"accept",accept_args("e5200000-0000-4000-8000-00000000dead"),
            "No existence oracle for guessed offer")
    check(accepted(api,key,venue,"accept",accept_args(offer))==offer,
          "Venue root accepted the exact original offer")
    check(accepted(api,key,venue,"accept",accept_args(offer))==offer,
          "Venue accept replay must be idempotent")

    refused(api,key,owner,"link",link_args(offer),
            "Flower owner cannot substitute for Venue Work governor")
    refused(api,key,worker,"link",link_args(offer),
            "Worker cannot self-authorize Venue Work reference")
    refused(api,key,venue,"link",link_args(offer,work=WRONG_WORK),
            "Wrong-Ledger existing Work is not Venue Work")
    refused(api,key,venue,"link",link_args(offer,reviewed_bed="another-bed"),
            "Client review cannot substitute unrelated Bed identity")
    ref=accepted(api,key,venue,"link",link_args(offer))
    check(accepted(api,key,venue,"link",link_args(offer))==ref,
          "Venue Work-source action replay must be idempotent")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 WHERE "
       "id="+lit(ref)+"::uuid AND work_item_id="+lit(VENUE_WORK)+"::uuid AND "
       "bed_id="+lit(BED)+"::uuid AND venue_ledger_id="+lit(VENUE)+"::uuid")=="1",
       "Venue ref must point to the same existing original Work and Bed")
    check(int(sql(db,"SELECT count(*) FROM atlas.work_items"))==baseline_work,
       "Reference must never make another original Work")
    check(int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))==baseline_bed,
       "Reference must never make another original Bed")
    check(int(sql(db,"SELECT count(*) FROM atlas.work_item_context_links"))==baseline_context,
       "Source-specific reference cannot bypass Flower's original link guard")
    check(sql(db,"SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 "
       "WHERE ledger_id="+lit(VENUE)+"::uuid")=="0",
       "Venue must never obtain crop custody from use grant")
    print("PASS exact Venue reference without duplicate original or custody transfer")

    accepted(api,key,owner,"withdraw",{"p_use_id":offer},expect="bool")
    check(sql(db,"SELECT use_state FROM atlas.venue_bed_shared_use_authorizations_v1 "
       "WHERE id="+lit(offer)+"::uuid")=="withdrawn","Flower root withdrawal did not terminate use")
    refused(api,key,venue,"link",link_args(offer,action="after-withdrawal"),
            "Revocation stops already signed Venue governor")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 "
      "WHERE id="+lit(ref)+"::uuid")=="1","Historical Venue reference receipt must persist")
    print("PASS withdrawal denies current permission and preserves original reference receipt")

    new_offer=accepted(api,key,owner,"offer",offer_args(action="venue-offer-b"))
    check(new_offer!=offer,"New use must have a new source identity")
    accepted(api,key,venue,"accept",accept_args(new_offer))
    fresh=accepted(api,key,venue,"link",link_args(new_offer,action="venue-link-after-reapproval"))
    check(fresh!=ref,"A fresh grant must permit a separate auditable reference receipt")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 "
       "WHERE bed_id="+lit(BED)+"::uuid AND work_item_id="+lit(VENUE_WORK)+"::uuid")=="2",
       "New grant must not overwrite former grant historical receipt")
    print("PASS distinct grant can lawfully reapprove the same existing original Work")

    # End the Venue Seat: a still-valid GoTrue JWT cannot conjure native Seat.
    sql(db,"UPDATE ledger.seats SET seat_state='ended',ended_at=now() WHERE "
       "ledger_id="+lit(VENUE)+"::uuid AND person_entity_id="+lit(VENUE_PERSON)+"::uuid")
    refused(api,key,venue,"withdraw",{"p_use_id":new_offer},
            "Ended native Venue Seat prevents a valid-session root operation")
    # Flower can still withdraw despite Venue's Seat ending.
    accepted(api,key,owner,"withdraw",{"p_use_id":new_offer},expect="bool")

    # End Flower's actual GoTrue session: reusing its SAME old JWT must be
    # refused by reality_access_self_api_v1(), not by HTTP token expiry.
    session=actors["owner"][1]["session_id"]
    sql(db,"DELETE FROM auth.sessions WHERE id="+lit(session)+"::uuid "
       "AND user_id="+lit(c1.OWNER)+"::uuid")
    refused(api,key,owner,"offer",offer_args(action="revoked-signed-token"),
            "Revoked same-JWT session cannot issue new Flower offer")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS genuine local signed Flower/Venue/worker/outsider/no-seat denial;"
      " two-party offer-accept-link-withdraw/reapproval;"
      " Work/Bed original identity unchanged;"
      " ended Seat and same-JWT GoTrue revocation.\n",
      encoding="utf-8")
    print("PASS venue Bed signed source matrix; no production mutation")

if __name__=="__main__":
    main()

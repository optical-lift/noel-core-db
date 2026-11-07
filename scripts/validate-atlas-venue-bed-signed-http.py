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
VENUE_EVENT="e5200000-0000-4000-8000-000000000b40"
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
    check(sql(db,"SELECT count(*) FROM atlas.growing_objects WHERE "
      "farm_id='e5200000-0000-4000-8000-000000000b01'::uuid "
      "AND id IN ("+lit(BED)+"::uuid,"+lit(OTHER_BED)+"::uuid)")=="2",
      "The two distinct synthetic Bed identities are not present")
    check(sql(db,"SELECT count(*) FROM atlas.work_items WHERE "
      "id="+lit(WRONG_WORK)+"::uuid "
      "AND stable_key='clone-flower-original-work-901'")=="1",
      "Wrong-Ledger Work must actually exist for a meaningful negative test")

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
    conflict_code,conflict_body=user_rpc(
        api,key,owner,"offer",offer_args(bed=OTHER_BED,action="venue-offer-a"))
    check(conflict_code==409 and isinstance(conflict_body,dict)
          and conflict_body.get("code")=="23505",
          "An existing action ID must not be replayed against a different Bed")
    print("PASS source-action idempotence cannot be laundered across Beds")

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

    check(sql(db,"SELECT establishment_basis_kind FROM atlas.work_allocations WHERE "
      "id='e5200000-0000-4000-8000-000000000a23'::uuid")
          =="legacy_governed_reconstruction",
          "Original Flower Work responsibility requires exact native source-issued basis")
    
    # POSITIVE native source parity: after the independent Venue reference is
    # present, the *original*, still-open Flower Work must remain joinable to
    # the *same* Bed through the already released Flower governed context
    # writer. This is NOT the Venue reference writer. Synthetic source Task,
    # exact zone, active current allocation, Organization Unit, Ledger crop
    # custody and all reviewed stable keys must independently exist.
    flower_read={"p_ledger_id":FLOWER,"p_work_item_id":WRONG_WORK}
    for name,token in (("ordinary worker",worker),
                       ("other Ledger root",venue),("unseated",noseat)):
        code,body=c1.rpc(api,key,
           "work_growing_object_context_review_self_api_v1",flower_read,token)
        check(code==200 and isinstance(body,dict)
              and body.get("ok") is False and "candidates" not in body,
              "Source Flower Bed candidate review leaked to "+name)
    code,review=c1.rpc(api,key,
        "work_growing_object_context_review_self_api_v1",flower_read,owner)
    check(code==200 and isinstance(review,dict) and review.get("ok") is True,
          "Flower source governor lost original Work/Bed review after Venue reference")
    allowed_beds={c.get("objectId") for c in review.get("candidates",[])}
    check(BED in allowed_beds and OTHER_BED not in allowed_beds,
          "Original exact task zone must admit Flower Bed 3 and exclude withheld Bed 5")
    flower_link={
      "p_ledger_id":FLOWER,"p_work_item_id":WRONG_WORK,
      "p_object_id":BED,
      "p_review":{"humanConfirmed":True,
                  "reviewedWorkStableKey":"clone-flower-original-work-901",
                  "reviewedObjectKey":"clone-upick-bed-3"}
    }
    for name,token in (("ordinary worker",worker),
                       ("other Ledger root",venue),("unseated",noseat)):
        code,body=c1.rpc(api,key,
           "establish_work_growing_object_context_self_api_v1",flower_link,token)
        check(code==200 and isinstance(body,dict)
              and body.get("ok") is False and not body.get("contextId"),
              "Unauthorized actor can establish Flower physical Work: "+name)
    code,physical=c1.rpc(api,key,
        "establish_work_growing_object_context_self_api_v1",flower_link,owner)
    check(code==200 and isinstance(physical,dict)
          and physical.get("ok") is True and physical.get("created") is True
          and physical.get("confersAccess") is False,
          "Signed original Flower Work-to-same-Bed positive admission failed")
    context_id=str(uuid.UUID(physical["contextId"]))
    code,replay=c1.rpc(api,key,
        "establish_work_growing_object_context_self_api_v1",flower_link,owner)
    check(code==200 and isinstance(replay,dict)
          and replay.get("ok") is True and replay.get("created") is False
          and replay.get("contextId")==context_id,
          "Existing Flower context replay must return the same original relation")
    check(sql(db,"SELECT count(*) FROM atlas.work_item_context_links WHERE "
      "id="+lit(context_id)+"::uuid AND work_item_id="+lit(WRONG_WORK)+"::uuid "
      "AND subject_domain='spatial' AND subject_kind='growing_object' "
      "AND subject_id="+lit(BED)+"::uuid AND relation_kind='acts_on'")=="1",
      "Original Flower physical Work relation missing from canonical context")
    check(int(sql(db,"SELECT count(*) FROM atlas.work_items"))==baseline_work
          and int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))==baseline_bed,
          "Flower positive link must not invent original Work or Bed")
    check(sql(db,"SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 "
      "WHERE ledger_id="+lit(VENUE)+"::uuid")=="0",
      "Independent original Flower link must not transfer crop custody to Venue")
    print("PASS genuine signed Flower original Work-to-same-Bed link and replay after Venue")

    # Native Event positive parity: the Venue's ALREADY-EXISTING canonical
    # Work is independently source-relevant and the Event already has exact
    # Ledger plus Organization Occurrence bindings. Link it through the
    # RELEASED public ordinary Event-Work source rather than the temporary
    # Venue Bed-use permission. No Event checklist work is issued.
    event_args={
      "p_organization_id":c1.ORG,"p_ledger_id":VENUE,
      "p_occurrence_id":VENUE_EVENT,"p_work_item_id":VENUE_WORK,
      "p_source_action_id":"clone-event-existing-work-link-a",
    }
    check(sql(db,"SELECT count(*) FROM ledger.occurrence_calendar_bindings WHERE "
       "ledger_id="+lit(VENUE)+"::uuid AND occurrence_id="+lit(VENUE_EVENT)
       +"::uuid AND binding_state='active'")=="1",
       "Exact original native Venue Event source binding absent")
    for name,token in (("Flower root",owner),
                       ("ordinary Flower worker",worker),
                       ("no native seat",noseat)):
        code,result=c1.rpc(api,key,
          "link_existing_ledger_event_work_self_api_v1",event_args,token)
        check(code in (401,403) and isinstance(result,dict)
              and result.get("code")=="42501",
              f"{name} must not link another Ledger's original Event Work")
    code,linked=c1.rpc(api,key,
          "link_existing_ledger_event_work_self_api_v1",event_args,venue)
    check(code==200 and isinstance(linked,dict)
          and linked.get("ok") is True
          and linked.get("workItemId")==VENUE_WORK
          and linked.get("idempotent") is False
          and linked.get("workCustodyChanged") is False,
          f"Real signed Venue native Event Work link failed: {code}, {str(linked)[:500]}")
    event_link=str(uuid.UUID(linked["contextLinkId"]))
    code,replayed=c1.rpc(api,key,
          "link_existing_ledger_event_work_self_api_v1",event_args,venue)
    check(code==200 and isinstance(replayed,dict)
          and replayed.get("ok") is True
          and replayed.get("idempotent") is True
          and replayed.get("contextLinkId")==event_link,
          "Native Event existing Work source replay must be idempotent")
    check(sql(db,"SELECT count(*) FROM atlas.work_item_context_links WHERE "
      "id="+lit(event_link)+"::uuid AND work_item_id="+lit(VENUE_WORK)+"::uuid "
      "AND subject_domain='temporal' AND subject_kind='occurrence' "
      "AND subject_id="+lit(VENUE_EVENT)+"::uuid AND relation_kind='for'")=="1",
      "Native original Venue Event Work must occupy the canonical temporal context")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 WHERE "
      "id="+lit(ref)+"::uuid AND bed_id="+lit(BED)+"::uuid "
      "AND work_item_id="+lit(VENUE_WORK)+"::uuid")=="1",
      "Original independent Venue-Bed receipt must survive Event link")
    check(sql(db,"SELECT count(*) FROM atlas.work_item_context_links WHERE "
      "id="+lit(context_id)+"::uuid AND subject_id="+lit(BED)+"::uuid "
      "AND work_item_id="+lit(WRONG_WORK)+"::uuid")=="1",
      "Original independent Flower physical link must survive Venue Event link")
    check(int(sql(db,"SELECT count(*) FROM atlas.work_items"))==baseline_work
          and int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))==baseline_bed,
          "Native Event may not copy existing Work or Flower Bed")
    check(sql(db,"SELECT work_state FROM atlas.work_items WHERE "
      "id="+lit(VENUE_WORK)+"::uuid")=="open",
      "Event link does not complete ordinary existing Venue Work")
    # The ordinary Event shared-checklist Done operation has a DISTINCT
    # source contract. It MUST NOT complete an Event-linked pre-existing Work
    # merely because both share the same Occurrence.
    done_args=dict(event_args)
    done_args["p_source_action_id"]="clone-event-checklist-forged-done"
    code,result=c1.rpc(api,key,
         "mark_ledger_occurrence_shared_work_done_self_api_v1",done_args,venue)
    check(code in (401,403) and isinstance(result,dict)
          and result.get("code")=="42501",
          "Event checklist Done cannot launder ordinary existing Venue Work completion")
    check(sql(db,"SELECT work_state FROM atlas.work_items WHERE "
      "id="+lit(VENUE_WORK)+"::uuid")=="open",
      "Rejected checklist Done must preserve ordinary existing Work as open")
    print("PASS signed native Event existing Work link/replay; checklist Done cannot substitute for Work result")

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

    # Either governing source is permitted to withdraw; use a genuine signed
    # Venue actor for this second independent direction.
    accepted(api,key,venue,"withdraw",{"p_use_id":new_offer},expect="bool")
    check(sql(db,"SELECT use_state FROM atlas.venue_bed_shared_use_authorizations_v1 "
      "WHERE id="+lit(new_offer)+"::uuid")=="withdrawn",
      "Venue root withdrawal did not end its own approved Bed-use")
    refused(api,key,venue,"link",link_args(new_offer,action="after-venue-withdraw"),
            "Venue withdrawal immediately blocks later references")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 "
      "WHERE id="+lit(fresh)+"::uuid")=="1",
      "Venue withdrawal must preserve historical approved reference")
    print("PASS independent signed Venue withdrawal and historical custody")

    # A third valid current grant isolates Seat-ending proof from withdrawal.
    active_offer=accepted(api,key,owner,"offer",offer_args(action="venue-offer-c"))
    accepted(api,key,venue,"accept",accept_args(active_offer))
    # End Venue Seat: an already signed GoTrue JWT cannot replace native Seat.
    sql(db,"UPDATE ledger.seats SET seat_state='ended',ended_at=now() WHERE "
       "ledger_id="+lit(VENUE)+"::uuid AND person_entity_id="+lit(VENUE_PERSON)+"::uuid")
    refused(api,key,venue,"withdraw",{"p_use_id":active_offer},
            "Ended native Venue Seat prevents a valid-session root operation")
    # Flower can still withdraw despite Venue's Seat ending.
    accepted(api,key,owner,"withdraw",{"p_use_id":active_offer},expect="bool")

    # End Flower's actual GoTrue session: reusing its SAME old JWT must be
    # refused by reality_access_self_api_v1(), not by HTTP token expiry.
    session=actors["owner"][1]["session_id"]
    sql(db,"DELETE FROM auth.sessions WHERE id="+lit(session)+"::uuid "
       "AND user_id="+lit(c1.OWNER)+"::uuid")
    refused(api,key,owner,"offer",offer_args(action="revoked-signed-token"),
            "Revoked same-JWT session cannot issue new Flower offer")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS real signed native Event already-existing Work positive link/replay;"
      " ordinary Event checklist Done unable to complete unrelated original Work;"
      "PASS genuine signed ORIGINAL Flower Work-to-Bed positive parity after Venue link;"
      " authorized Flower-only canonical context/replay;" 
      " no duplicate originals or Venue crop-custody transfer;"
      " independent local Flower/Venue/worker/outsider/no-seat denial;"
      " two-party offer-accept-link-withdraw/reapproval;"
      " Work/Bed original identity unchanged;"
      " ended Seat and same-JWT GoTrue revocation.\n",
      encoding="utf-8")
    print("PASS venue Bed signed source matrix; no production mutation")

if __name__=="__main__":
    main()

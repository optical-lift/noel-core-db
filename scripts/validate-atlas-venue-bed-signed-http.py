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

    # Independent original Flower *worker Result/Done* gate. The fictional
    # employee carrier and source-linked task are not permission by themselves.
    # Signatures, native employee Seat, credential, Position appointment,
    # delegated responsibility, real owner plan and canonical projected Worker
    # Day must all succeed through the released source.
    worker_link={
      "p_organization_id":c1.ORG,
      "p_organization_membership_id":"e5200000-0000-4000-8000-000000000a22",
      "p_position_id":"e5200000-0000-4000-8000-000000000a34",
      "p_reason":"Fictional owner source appointment for signed clone parity"
    }
    status,appointment=c1.rpc(api,key,
       "organization_owner_appoint_employee_position_api_v1",worker_link,owner)
    check(status==200 and isinstance(appointment,dict)
          and appointment.get("state") in ("appointed","unchanged"),
          f"Original Flower worker Position requires signed owner appointment: {status}, {str(appointment)[:300]}")
    check(sql(db,"SELECT count(*) FROM atlas.organization_position_appointments "
          "WHERE organization_membership_id='e5200000-0000-4000-8000-000000000a22'::uuid "
          "AND position_id='e5200000-0000-4000-8000-000000000a34'::uuid "
          "AND status='active'")=="1",
          "Owner-issued original Flower worker appointment was not recorded")
    today=sql(db,"SELECT (now() AT TIME ZONE 'America/Chicago')::date")
    monday=sql(db,"SELECT date_trunc('week',"
      "(now() AT TIME ZONE 'America/Chicago')::date::timestamp)::date")
    plan_args={"p_organization_id":c1.ORG,"p_week_start":monday,
       "p_plans":[{"workItemId":WRONG_WORK,"serviceDate":today}]}
    status,planned=c1.rpc(api,key,
       "organization_management_plan_company_work_week_api_v1",plan_args,owner)
    check(status==200 and isinstance(planned,dict)
          and planned.get("ok") is not False,
          f"Original Flower Work requires signed owner canonical plan: {status}, {str(planned)[:400]}")
    plan_id=sql(db,"SELECT id FROM atlas.work_execution_plans WHERE "
      "work_item_id="+lit(WRONG_WORK)+"::uuid AND "
      "assignee_membership_id='e5200000-0000-4000-8000-000000000a22'::uuid "
      "AND plan_state='active' AND exposure_service_date="+lit(today)+"::date "
      "ORDER BY created_at DESC LIMIT 1")
    check(bool(plan_id), "Signed owner plan did not establish exact current-day Work")
    check(str(uuid.UUID(plan_id))==plan_id,
          "Signed owner plan must return a source-bound UUID")

    status,refresh=c1.rpc(api,key,
       "company_work_worker_day_refresh_self_api_v1",
       {"p_start_date":today,"p_days":1},worker)
    check(status==200 and isinstance(refresh,dict)
          and refresh.get("ok") is True
          and int(refresh.get("eligibleDeliveryContexts",0))>=1,
          f"Signed worker cannot refresh genuine employee Worker Day: {status}, {str(refresh)[:420]}")
    projection_id=sql(db,"SELECT id FROM atlas.worker_week_projection WHERE "
       "farm_id='e5200000-0000-4000-8000-000000000b01'::uuid AND "
       "membership_id='e5200000-0000-4000-8000-000000000a36'::uuid AND "
       "organization_id="+lit(c1.ORG)+"::uuid AND "
       "organization_membership_id='e5200000-0000-4000-8000-000000000a22'::uuid "
       "AND source_kind='work_item' AND source_id="+lit(WRONG_WORK)+"::uuid "
       "AND planned_date="+lit(today)+"::date AND "
       "delivery_payload->>'projectionAuthority'='work_execution_plans' "
       "AND delivery_payload->>'managerPlanId'="+lit(plan_id)+" "
       "AND delivery_payload->>'canonicalCompanyWorkProjection'='true' "
       "AND delivery_payload->>'source'='company_work_employee_plan_projection_v1' "
       "LIMIT 1")
    check(bool(projection_id),
          "Worker projection was not derived from canonical owner-issued Work plan")
    check(sql(db,"SELECT count(*) FROM atlas.worker_week_projection_sources WHERE "
       "projection_id="+lit(projection_id)+"::uuid AND "
       "work_item_id="+lit(WRONG_WORK)+"::uuid AND source_role='required'")=="1",
       "Worker delivery carrier must require exactly original canonical Flower Work")

    report_args={"p_projection_id":projection_id,"p_result_kind":"completed",
       "p_idempotency_key":"clone-original-flower-worker-done-a",
       "p_payload":{"cloneOnly":True,"workItemId":WRONG_WORK,
                    "outcome":"synthetic original Flower Bed Work completed"}}
    for name,token in (("Flower owner not employee",owner),
                       ("Venue governor not employee",venue),
                       ("unseated Person",noseat)):
        st,result=c1.rpc(api,key,
          "worker_report_company_work_projection_self_api_v1",report_args,token)
        check(st in (401,403) and isinstance(result,dict)
              and result.get("code")=="42501",
              "Worker Result source must deny "+name+" without employee context")
    status,reported=c1.rpc(api,key,
      "worker_report_company_work_projection_self_api_v1",report_args,worker)
    check(status==200 and isinstance(reported,dict)
          and reported.get("resultId") and reported.get("workItemId")==WRONG_WORK,
          f"Signed current Flower worker could not report original Work: {status}, {str(reported)[:430]}")
    result_id=str(uuid.UUID(reported["resultId"]))
    check(sql(db,"SELECT work_state FROM atlas.work_items WHERE "
         "id="+lit(WRONG_WORK)+"::uuid")=="open",
         "Manager-acceptance Work must remain OPEN after worker's reported Done")
    status,replayed=c1.rpc(api,key,
      "worker_report_company_work_projection_self_api_v1",report_args,worker)
    check(status==200 and isinstance(replayed,dict)
          and replayed.get("state")=="deduplicated"
          and replayed.get("resultId")==result_id,
          "Signed worker's same result must be an idempotent report, not new Work")
    check(sql(db,"SELECT count(*) FROM atlas.work_execution_results WHERE "
      "work_item_id="+lit(WRONG_WORK)+"::uuid AND id="+lit(result_id)+"::uuid "
      "AND result_kind='completed' AND "
      "reported_by_user_id="+lit(c1.WORKER)+"::uuid")=="1",
      "Original source worker completion result must be a distinct authentic receipt")

    # Owner decision may be exposed by production's published public RPC.
    # If not, an invoker-only temporary clone wrapper calls that SAME existing
    # owner-authenticated source. Record which transport was actually tested.
    published=sql(db,"SELECT to_regprocedure("
      "'public.organization_owner_decide_company_work_result_api_v1(uuid,text,text)'"
      ") IS NOT NULL")=="t"
    decision_rpc=("organization_owner_decide_company_work_result_api_v1"
      if published else "clone_test_flower_owner_accept_result_v1")
    accept_result={"p_execution_result_id":result_id,"p_decision":"accepted",
                   "p_reason":"Synthetic governor acceptance of source worker's completion"}
    for name,token in (("ordinary worker",worker),
                       ("Venue governor",venue),
                       ("unseated",noseat)):
        st,res=c1.rpc(api,key,decision_rpc,accept_result,token)
        check(st in (401,403) and isinstance(res,dict)
              and res.get("code")=="42501",
              "Original Work manager acceptance must deny "+name)
    st,approved=c1.rpc(api,key,decision_rpc,accept_result,owner)
    check(st==200 and isinstance(approved,dict)
       and approved.get("decision")=="accepted"
       and approved.get("workItemId")==WRONG_WORK,
       f"Signed Flower institutional owner could not accept worker Done: {st}, {str(approved)[:430]}")
    check(sql(db,"SELECT work_state FROM atlas.work_items WHERE "
        "id="+lit(WRONG_WORK)+"::uuid")=="completed",
        "Only signed manager approval should complete original Flower Work")
    check(sql(db,"SELECT count(*) FROM atlas.work_result_acceptances WHERE "
        "execution_result_id="+lit(result_id)+"::uuid AND decision='accepted'")=="1",
        "Signed owner acceptance must preserve one source-issued result receipt")
    check(sql(db,"SELECT count(*) FROM atlas.work_item_context_links WHERE "
        "id="+lit(context_id)+"::uuid AND work_item_id="+lit(WRONG_WORK)+"::uuid "
        "AND subject_id="+lit(BED)+"::uuid")=="1",
        "Original Flower physical context must survive legitimate Work completion")
    check(sql(db,"SELECT count(*) FROM atlas.venue_bed_work_references_v1 WHERE "
        "id="+lit(ref)+"::uuid AND bed_id="+lit(BED)+"::uuid")=="1",
        "Existing independent Venue reference must survive Flower Work Done")
    check(int(sql(db,"SELECT count(*) FROM atlas.work_items"))==baseline_work
          and int(sql(db,"SELECT count(*) FROM atlas.growing_objects"))==baseline_bed,
          "Signed original Work completion cannot duplicate original Work or Bed")
    print("PASS independent signed Flower Worker Day original report and owner acceptance; "
          "owner-decision transport="+("published" if published else "disposable clone only"))

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
      "PASS genuine signed original Flower Worker Day report + owner acceptance source;"
      " published/clone owner-transport distinction printed in local diagnostics;"
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

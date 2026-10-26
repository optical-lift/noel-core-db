#!/usr/bin/env python3
"""Disposable LOCAL signed Bed 3 + Laundry source acceptance, never production.

Requires integrated original Work migration and fictional fixture. Real distinct
GoTrue JWT/session identities; canonical Person + native Ledger authority.
Event regression is separate and remains mandatory before production release.
"""
import argparse
import importlib.util
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "universal_work_base",ROOT/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
PERSON="e5200000-0000-4000-8000-000000000102"
PARENT="e5200000-0000-4000-8000-000000000b10"
BED3="e5200000-0000-4000-8000-000000000b03"
BED4="e5200000-0000-4000-8000-000000000b04"
FARM="e5200000-0000-4000-8000-000000000b01"
HOUSEHOLD="e5200000-0000-4000-8000-000000000c01"
LAUNDRY="e5200000-0000-4000-8000-000000000c03"
check=base.check

def rpc(api,key,token,name,payload):
    return base.rpc(api,key,token,name,payload)
def ok(api,key,token,name,payload):
    status,data=rpc(api,key,token,name,payload)
    check(status==200 and isinstance(data,dict) and data.get("ok") is True,
          f"{name}: genuine bearer call failed {status}: {str(data)[:200]}")
    return data
def deny(api,key,token,name,payload,label):
    status,data=rpc(api,key,token,name,payload)
    check(status in (401,403) and isinstance(data,dict) and
          (token is None or data.get("code")=="42501"),
          f"{label}: signed source denial failed {status}: {str(data)[:200]}")
    print("PASS",label)
def subject(work,bed):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                p_work_item_id=work,p_subject_domain="spatial",
                p_subject_kind="growing_object",p_subject_id=bed)
def action(bed,cls,kind,identifier):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                p_target_person_id=PERSON,p_subject_domain="spatial",
                p_subject_kind="growing_object",p_subject_id=bed,
                p_disclosure_class=cls,p_decision_kind=kind,
                p_source_action_id=identifier,
                p_reason="Exact synthetic Bed visibility authorized for one assigned Work.")
def sql(db,query):
    return base.sql(db,query)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                            args.db_url)), "Refuse any nonlocal DB URL")
    check(sql(args.db_url,"select count(*) from atlas.growing_objects where id in "
          f"('{BED3}'::uuid,'{BED4}'::uuid)")=="2","Synthetic Beds 3 and 4 missing")
    check(sql(args.db_url,f"select count(*) from atlas.household_kernel_instances "
              f"where id='{LAUNDRY}'::uuid")=="1","Original synthetic Laundry missing")
    api,key=c1.local_status()
    sessions={}
    for name,uid in base.setup_auth(args.db_url):
        bearer,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and bool(claims.get("session_id")),
              "No real independent signed GoTrue session: "+name)
        check(sql(args.db_url,"select count(*) from auth.sessions where "
                  f"id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
              "Bearer token lacks real local session: "+name)
        sessions[name]=bearer
    owner,worker,outsider=sessions["owner"],sessions["worker"],sessions["outsider"]
    print("PASS independently signed local governor, connected Person and outsider")

    parts=[
      dict(subjectDomain="spatial",subjectKind="growing_object",subjectId=BED3,
           title="Measure and stake synthetic U-Pick Bed 3",
           instructions="Measure and install stakes for Bed 3 only.",
           resultContractKey="ordinary_company_work_worker_attestation_v1",
           confirmWorkerAttestationAuthority=True),
      dict(subjectDomain="spatial",subjectKind="growing_object",subjectId=BED4,
           title="Measure and stake synthetic U-Pick Bed 4",
           instructions="Measure and install stakes for Bed 4 only.",
           resultContractKey="ordinary_company_work_manager_acceptance_v1",
           confirmWorkerAttestationAuthority=False)
    ]
    split=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_parent_work_item_id=PARENT,p_parts=parts,
      p_action_id="e5200000-0000-4000-8000-000000000d01",
      p_decision_reason="Two physical Beds need separate original Work and completion.")
    deny(api,key,worker,"split_original_canonical_work_owner_self_api_v1",
         split,"Worker cannot decompose owner Work")
    packet=ok(api,key,owner,"split_original_canonical_work_owner_self_api_v1",split)
    check(packet.get("parentHistoryPreserved") is True and
          packet.get("childrenUnassigned") is True and
          packet.get("parentWorkItemId")==PARENT and len(packet.get("children",[]))==2,
          "Original combined Work was not preserved and split")
    same=ok(api,key,owner,"split_original_canonical_work_owner_self_api_v1",split)
    check(same.get("idempotent") is True and
          same.get("decompositionId")==packet.get("decompositionId"),
          "Split retry minted another original Work group")
    children={c["subjectId"]:c for c in packet["children"]}
    check(set(children)=={BED3,BED4},"Wrong independent original Beds")
    bed3,bed4=children[BED3]["workItemId"],children[BED4]["workItemId"]
    check(bed3!=bed4 and bed3!=PARENT and bed4!=PARENT
          and children[BED3]["resultContractKey"]==
            "ordinary_company_work_worker_attestation_v1"
          and children[BED4]["resultContractKey"]==
            "ordinary_company_work_manager_acceptance_v1",
          "Independent Bed Work or completion contract corrupted")
    check(sql(args.db_url,f"select work_state from atlas.work_items where id='{PARENT}'")
          =="superseded","Parent Work was not preserved as superseded history")

    assign=dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_work_item_id=bed3,
      p_target_person_id=PERSON,p_service_date="2030-10-30",
      p_action_id="e5200000-0000-4000-8000-000000000d02",
      p_reason="Assign only this original Bed 3 Work to the connected Person.")
    deny(api,key,worker,"owner_direct_assign_existing_original_work_self_api_v1",
         assign,"Worker cannot self-assign original Bed Work")
    a=ok(api,key,owner,"owner_direct_assign_existing_original_work_self_api_v1",assign)
    check(a.get("workItemId")==bed3 and a.get("targetPersonId")==PERSON
          and a.get("plannedServiceDate")=="2030-10-30"
          and a.get("newWorkCreated") is False and a.get("newTaskCreated") is False
          and a.get("acceptanceQuestionCreated") is False
          and a.get("employeeSeatRequired") is False,
          "Existing original Work assignment minted a task, seat or offer")
    retry=ok(api,key,owner,"owner_direct_assign_existing_original_work_self_api_v1",assign)
    check(retry.get("idempotent") is True and
          retry.get("allocationId")==a.get("allocationId"),
          "Retry minted a different direct allocation")
    mine=ok(api,key,worker,"connected_person_my_work_self_api_v1",
            {"p_limit":50,"p_after_allocation_id":None})
    visible=[x for x in mine.get("items",[]) if x.get("workItemId")==bed3]
    check(len(visible)==1 and visible[0].get("workOn")=="2030-10-30"
          and all(x.get("workItemId")!=bed4 for x in mine.get("items",[])),
          "Signed Person's existing My Work page missed Bed 3 or leaked Bed 4")
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         subject(bed3,BED3),"Responsibility alone cannot discover Bed identity")
    decision=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                action(BED3,"identity","grant",
                       "e5200000-0000-4000-8000-000000000d03"))
    check(decision.get("currentlyGranted") is True,"Signed identity grant not recorded")
    card=ok(api,key,worker,"connected_person_original_work_subject_self_api_v1",
            subject(bed3,BED3))
    check(card.get("subjectId")==BED3
          and card.get("subjectLabel")=="Synthetic U-Pick Bed 3"
          and card.get("conditionDisclosed") is False
          and card.get("notesAndMetadataDisclosed") is False
          and card.get("cropPlacementDetailsDisclosed") is False
          and card.get("fullFarmReaderAccessGranted") is False,
          "Bed 3 read accidentally included withheld metadata")
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         subject(bed4,BED4),"Bed 4 not disclosed through Bed 3 assignment")
    deny(api,key,outsider,"connected_person_original_work_subject_self_api_v1",
         subject(bed3,BED3),"Unconnected Person cannot read Bed 3")

    # This worker simultaneously holds a live *inherited* farm_hand membership.
    # The new exact Bed 3 Work allocation and governor-granted identity must
    # NEVER reopen whole-farm historic readers. A missing ID must not turn
    # a denial into an existence oracle.
    check(sql(args.db_url,
        f"select count(*) from atlas.farm_memberships where farm_id='{FARM}'::uuid "
        f"and user_id='{c1.WORKER}'::uuid and role='farm_hand' and active")=="1",
        "No realistic older farm_hand membership in signed fixture")
    old_farm_reads=(
      ("zone_registry_source_v1",{"p_farm_id":FARM}),
      ("object_crop_bed_map_v1",{"p_object_id":BED3}),
      ("farm_care_zone_v1",
       {"p_farm_id":FARM,"p_zone_key":"u-pick","p_history_limit":25}),
      ("farm_snapshot_for_member_v1",{"p_farm_id":FARM}),
      ("bed_components_state_v1",{"p_bed_id":BED3}),
    )
    for old_reader,old_args in old_farm_reads:
        deny(api,key,worker,old_reader,old_args,
             "Inherited farm_hand cannot bypass source governor gate via "+old_reader)
    print("PASS signed legacy membership cannot reopen five whole-farm readers")

    actual=ok(api,key,worker,"report_connected_person_company_work_self_api_v1",
          dict(p_work_item_id=bed3,p_result_kind="completed",
               p_idempotency_key="clone-universal-bed3-physical-actual",
               p_payload={"physicalActual":"Stakes installed on fictional Bed 3"}))
    check(actual.get("workItemId")==bed3 and
          sql(args.db_url,f"select work_state from atlas.work_items where id='{bed3}'")
          =="completed" and
          sql(args.db_url,f"select work_state from atlas.work_items where id='{bed4}'")
          =="open","Bed 3 worker completion also changed Bed 4")
    print("PASS signed Bed 3 direct Work, bounded grant and independent Actual")

    initial=ok(api,key,owner,"household_laundry_current_self_api_v1",{})
    check(initial.get("householdId")==HOUSEHOLD and
          initial.get("instanceId")==LAUNDRY and
          initial.get("workItemId") is None and
          initial.get("rhythmCurrentlyEstablished") is False,
          "Laundry calibration wrongly invented Work or Rhythm")
    deny(api,key,worker,"household_laundry_current_self_api_v1",{},
         "Household member lacks automatic governor visibility")
    obs=ok(api,key,owner,"record_household_laundry_observation_self_api_v1",
           dict(p_kernel_instance_id=LAUNDRY,
                p_action_id="e5200000-0000-4000-8000-000000000d04",
                p_observation="The fictional hamper is physically ready."))
    check(obs.get("workCreated") is False,"Observation fabricated Work")
    made=ok(api,key,owner,"establish_household_laundry_original_work_self_api_v1",
        dict(p_kernel_instance_id=LAUNDRY,p_observation_id=obs["observationId"],
             p_action_id="e5200000-0000-4000-8000-000000000d05",
             p_self_carried=True,p_assignee_household_member_id=None))
    washing=made["workItemId"]
    check(made.get("clockAdmitted") is False,"Laundry Need fabricated dated Work")
    rhythm=ok(api,key,owner,"household_laundry_explicit_rhythm_decide_self_api_v1",
        dict(p_kernel_instance_id=LAUNDRY,
             p_action_id="e5200000-0000-4000-8000-000000000d06",
             p_decision_kind="establish",p_renew_after_days=3,
             p_decision_reason="Review the next physical wash after three days."))
    check(rhythm.get("currentlyEstablished") is True and
          rhythm.get("workCreated") is False and
          rhythm.get("automaticCalibrationRhythmCreated") is False,
          "Rhythm decision inferred new Work")
    wash=dict(p_work_item_id=washing,
       p_action_id="e5200000-0000-4000-8000-000000000d07",
       p_note="Started the fictional wash.")
    deny(api,key,worker,"record_household_laundry_wash_started_self_api_v1",wash,
         "Unassigned Household member cannot claim physical Actual")
    receipt=ok(api,key,owner,"record_household_laundry_wash_started_self_api_v1",wash)
    check(receipt.get("workCompleted") is True and
          receipt.get("laundryCompletelyDone") is False
          and bool(receipt.get("rhythmSatisfactionId")),
          "Wash-started Actual was not bounded to this Work/Rhythm")
    again=ok(api,key,owner,"record_household_laundry_wash_started_self_api_v1",wash)
    check(again.get("idempotent") is True and
          again.get("careResultId")==receipt.get("careResultId"),
          "Physical-Actual replay created duplicate Result")
    deny(api,key,worker,"record_household_laundry_wash_started_self_api_v1",wash,
         "Forbidden member cannot retrieve a completed Actual receipt")
    now=ok(api,key,owner,"household_laundry_current_self_api_v1",{})
    check(now.get("workItemId") is None and
          now.get("lastCompletedWorkItemId")==washing,
          "Completed Work lost its history or blocked next Laundry cycle")
    print("PASS signed Laundry Need, Work, separate Rhythm, physical Actual and replay")
    Path(args.output).write_text(
        "PASS signed original Bed 3 + Laundry synthetic local source acceptance\n"
        "PENDING independent Event regression and complete alternative-reader sweep\n"
        "NO real Person or production Work altered\n")

if __name__=="__main__":
    main()

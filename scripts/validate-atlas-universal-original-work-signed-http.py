#!/usr/bin/env python3
"""Disposable LOCAL signed Bed 3 + Laundry source acceptance, never production.

Requires integrated original Work migration and fictional fixture. Real distinct
GoTrue JWT/session identities; canonical Person + native Ledger authority.
Event regression is separate and remains mandatory before production release.
"""
import argparse
import importlib.util
import re
import json
import subprocess
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

# Original and residual historical readers belong to the INTERNAL atlas schema, not the
# public PostgREST API. A PGRST202/404 must never count as a source denial.
# Execute the same SQL guard with the claims from a genuinely signed local
# GoTrue session, verified against the live disposable auth.sessions table.
def deny_internal_legacy(db,api,key,bearer,name,params):
    claims=c1.jwt_payload(bearer)
    uid=claims.get("sub")
    sid=claims.get("session_id")
    check(claims.get("role")=="authenticated" and uid==c1.WORKER and
          bool(re.fullmatch(r"[0-9a-f-]{36}",str(sid))),
          "Real signed worker GoTrue session required for old reader")
    check(sql(db,f"select count(*) from auth.sessions where "
              f"id='{sid}'::uuid and user_id='{uid}'::uuid")=="1",
          "Signed local session was not recorded")
    check(sql(db,"select count(*) from pg_proc p join pg_namespace n on "
              "n.oid=p.pronamespace where n.nspname='public' and "
              f"p.proname='{name}'")=="0",
          "Historical broad reader unexpectedly exposed in public")
    status,body=rpc(api,key,bearer,name,params)
    check(status==404 and isinstance(body,dict)
          and body.get("code")=="PGRST202",
          f"Unexpected public legacy reader result: {name} {status} {body}")
    calls={
      "zone_registry_source_v1":f"atlas.zone_registry_source_v1('{FARM}'::uuid)",
      "object_crop_bed_map_v1":f"atlas.object_crop_bed_map_v1('{BED3}'::uuid)",
      "farm_care_zone_v1":f"atlas.farm_care_zone_v1('{FARM}'::uuid,'u-pick'::text,25)",
      "farm_snapshot_for_member_v1":f"atlas.farm_snapshot_for_member_v1('{FARM}'::uuid)",
      "bed_components_state_v1":f"atlas.bed_components_state_v1('{BED3}'::uuid)",
      "farm_day_task_cards_v1":f"atlas.farm_day_task_cards_v1('{FARM}'::uuid,'2030-10-30'::date)",
      "home_task_cards_v2":f"atlas.home_task_cards_v2('{FARM}'::uuid,NULL::text,NULL::date,NULL::date)",
      "seed_inventory_dashboard_v1":f"atlas.seed_inventory_dashboard_v1('{FARM}'::uuid)",
      "task_cards_v1":f"atlas.task_cards_v1('{FARM}'::uuid,NULL::uuid)",
      "tending_task_context_v1":f"atlas.tending_task_context_v1('{FARM}'::uuid,'{PARENT}'::uuid,NULL::text)",
      "tending_task_context_v2":f"atlas.tending_task_context_v2('{FARM}'::uuid,'{PARENT}'::uuid,'clone-upick-bed-3'::text,NULL::text)",
      "worker_day_state_transition_cards_v1":f"atlas.worker_day_state_transition_cards_v1('{FARM}'::uuid,'{PARENT}'::uuid,'2030-10-30'::date)",
      "worker_future_day_projection_source_v1":f"atlas.worker_future_day_projection_source_v1('{FARM}'::uuid,'{PARENT}'::uuid,'2030-10-30'::date,'2030-11-06'::date)",
    }
    check(name in calls,"Unexpected legacy read")
    encoded=json.dumps(claims,separators=(",",":")).replace("'","''")
    query=("BEGIN;\nSET LOCAL ROLE authenticated;\n"
           "SELECT set_config('request.jwt.claims','" + encoded + "',true);\n"
           "SELECT set_config('request.jwt.claim.sub','" + uid + "',true);\n"
           "SELECT " + calls[name] + ";\nROLLBACK;\n")
    result=subprocess.run(["psql",db,"-X","-A","-t",
        "-v","ON_ERROR_STOP=1","-v","VERBOSITY=verbose","-c",query],
        text=True,capture_output=True,check=False)
    check(result.returncode!=0 and
          re.search(r"\b42501\b",result.stderr) and
          "Source unavailable to this Person." in result.stderr,
          f"Authenticated internal {name} failed to enforce governor "
          f"source permission: {result.stderr[-600:]}")
    print("PASS internal legacy source guard for signed worker:",name)

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
    def check_bed3_original_work_surfaces(expected):
        # Same canonical original Work ID across independently signed Person
        # My Work, Today and dated Work. No absent grant or revocation may
        # reveal it in any of these readers.
        for name,params in (
          ("connected_person_my_work_self_api_v1",
            {"p_limit":50,"p_after_allocation_id":None}),
          ("connected_person_company_work_today_self_api_v1",{"p_limit":100}),
          ("connected_person_company_work_day_self_api_v1",{"p_date":"2030-10-30"}),
        ):
            packet=ok(api,key,worker,name,params)
            count=sum(x.get("workItemId")==bed3 for x in packet.get("items",[]))
            check(count==expected,
                  f"{name} leaked or lost Bed 3 original Work (expected={expected},got={count})")



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
    # Allocation without an identity grant must not leak Bed 3 through
    # Work titles, instructions, Today or dated Work.
    undisclosed=ok(api,key,worker,"connected_person_my_work_self_api_v1",
                   {"p_limit":50,"p_after_allocation_id":None})
    check(all(x.get("workItemId")!=bed3 for x in undisclosed.get("items",[])),
          "Source disclosed Bed 3 Work before governor-granted identity")
    check_bed3_original_work_surfaces(0)
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         subject(bed3,BED3),"Responsibility alone cannot discover Bed identity")
    decision=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                action(BED3,"identity","grant",
                       "e5200000-0000-4000-8000-000000000d03"))
    check(decision.get("currentlyGranted") is True,"Signed identity grant not recorded")
    # Exact Bed identity may be visible without its physical condition.
    # Free-text Work instructions can encode condition, so those remain
    # unavailable until both field classes are granted.
    identity_card=ok(api,key,worker,"connected_person_original_work_subject_self_api_v1",
                     subject(bed3,BED3))
    check(identity_card.get("subjectId")==BED3
          and identity_card.get("subjectLabel")=="Synthetic U-Pick Bed 3"
          and identity_card.get("conditionDisclosed") is False
          and identity_card.get("notesAndMetadataDisclosed") is False
          and identity_card.get("cropPlacementDetailsDisclosed") is False
          and identity_card.get("fullFarmReaderAccessGranted") is False,
          "Identity-only grant leaked Bed condition or private farm details")
    check_bed3_original_work_surfaces(0)
    condition=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                 action(BED3,"condition","grant",
                        "e5200000-0000-4000-8000-000000000d22"))
    check(condition.get("currentlyGranted") is True,
          "Signed condition grant not recorded")
    mine=ok(api,key,worker,"connected_person_my_work_self_api_v1",
            {"p_limit":50,"p_after_allocation_id":None})
    visible=[x for x in mine.get("items",[]) if x.get("workItemId")==bed3]
    check(len(visible)==1 and visible[0].get("workOn")=="2030-10-30"
          and visible[0].get("title")=="Measure and stake synthetic U-Pick Bed 3"
          and all(x.get("workItemId")!=bed4 for x in mine.get("items",[])),
          "Signed Person's current identity grant must admit Bed 3, not Bed 4")
    check_bed3_original_work_surfaces(1)
    card=ok(api,key,worker,"connected_person_original_work_subject_self_api_v1",
            subject(bed3,BED3))
    check(card.get("subjectId")==BED3
          and card.get("subjectLabel")=="Synthetic U-Pick Bed 3"
          and card.get("conditionDisclosed") is True
          and card.get("notesAndMetadataDisclosed") is False
          and card.get("cropPlacementDetailsDisclosed") is False
          and card.get("fullFarmReaderAccessGranted") is False,
          "Condition grant cannot reopen notes, metadata or crop details")
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         subject(bed4,BED4),"Bed 4 not disclosed through Bed 3 assignment")
    deny(api,key,outsider,"connected_person_original_work_subject_self_api_v1",
         subject(bed3,BED3),"Unconnected Person cannot read Bed 3")

    # Current disclosure controls are dynamic. Withholding immediately
    # closes ordinary Work/Today and detail reads; new grant opens same original
    # Work ID without creating a task, plan or fresh allocation.
    revoke=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
              action(BED3,"identity","withhold",
                     "e5200000-0000-4000-8000-000000000d20"))
    check(revoke.get("currentlyGranted") is False,
          "Revocation did not become current")
    hidden=ok(api,key,worker,"connected_person_my_work_self_api_v1",
              {"p_limit":50,"p_after_allocation_id":None})
    check(all(x.get("workItemId")!=bed3 for x in hidden.get("items",[])),
          "Revoked Bed 3 leaked through signed My Work")
    check_bed3_original_work_surfaces(0)
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         subject(bed3,BED3),"Revoked Subject identity must not read")
    restore=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
               action(BED3,"identity","grant",
                      "e5200000-0000-4000-8000-000000000d21"))
    check(restore.get("currentlyGranted") is True,"Regrant not current")
    restored=ok(api,key,worker,"connected_person_my_work_self_api_v1",
                {"p_limit":50,"p_after_allocation_id":None})
    check(sum(x.get("workItemId")==bed3 for x in restored.get("items",[]))==1,
          "Regrant must restore exactly one existing original Work")
    check_bed3_original_work_surfaces(1)
    # Withholding only condition is sufficient to close all free-text
    # Work readers; Bed identity remains separately admitted in the
    # bounded Subject detail.
    condition_withhold=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                         action(BED3,"condition","withhold",
                                "e5200000-0000-4000-8000-000000000d23"))
    check(condition_withhold.get("currentlyGranted") is False,
          "Condition withhold was not current")
    check_bed3_original_work_surfaces(0)
    masked=ok(api,key,worker,"connected_person_original_work_subject_self_api_v1",
              subject(bed3,BED3))
    check(masked.get("conditionDisclosed") is False,
          "Condition withhold still leaked physical condition")
    condition_restore=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                        action(BED3,"condition","grant",
                               "e5200000-0000-4000-8000-000000000d24"))
    check(condition_restore.get("currentlyGranted") is True,
          "Condition regrant did not restore Work content admission")
    check_bed3_original_work_surfaces(1)

    # A historical creator/governor agenda is a separate title reader.
    # Even where the owner can lawfully see all Work in the native review,
    # the legacy agenda cannot be used as a new route to discover governed
    # growing-object Work. Ordinary non-Subject Work remains untouched.
    agenda=ok(api,key,owner,"connected_ledger_person_agenda_self_api_v1",
              {"p_ledger_id":LEDGER,"p_person_id":PERSON,
               "p_date":"2030-10-30","p_limit":150})
    check(all(x.get("workItemId") not in (bed3,bed4)
              for x in agenda.get("items",[])),
          "Legacy Person agenda reopened original growing-object Work titles")
    print("PASS signed original Bed exclusion from legacy Person agenda")

    # This worker simultaneously holds a live *inherited* farm_hand membership.
    # The new exact Bed 3 Work allocation and governor-granted identity must
    # NEVER reopen whole-farm historic readers. A missing ID must not turn
    # a denial into an existence oracle.
    check(sql(args.db_url,
        f"select count(*) from atlas.farm_memberships where farm_id='{FARM}'::uuid "
        f"and user_id='{c1.WORKER}'::uuid and role='farm_hand' and active")=="1",
        "No realistic older farm_hand membership in signed fixture")
    old_farm_reads=(
       ("farm_day_task_cards_v1",{}),
       ("home_task_cards_v2",{}),
       ("seed_inventory_dashboard_v1",{}),
       ("task_cards_v1",{}),
       ("tending_task_context_v1",{}),
       ("tending_task_context_v2",{}),
       ("worker_day_state_transition_cards_v1",{}),
       ("worker_future_day_projection_source_v1",{}),
      ("zone_registry_source_v1",{"p_farm_id":FARM}),
      ("object_crop_bed_map_v1",{"p_object_id":BED3}),
      ("farm_care_zone_v1",
       {"p_farm_id":FARM,"p_zone_key":"u-pick","p_history_limit":25}),
      ("farm_snapshot_for_member_v1",{"p_farm_id":FARM}),
      ("bed_components_state_v1",{"p_bed_id":BED3}),
    )
    for old_reader,old_args in old_farm_reads:
        deny_internal_legacy(args.db_url,api,key,worker,old_reader,old_args)
    print("PASS thirteen signed internal broad-farm source denials")

    actual=ok(api,key,worker,"report_connected_person_company_work_self_api_v1",
          dict(p_work_item_id=bed3,p_result_kind="completed",
               p_idempotency_key="clone-universal-bed3-physical-actual",
               p_payload={"physicalActual":"Stakes installed on fictional Bed 3"}))
    check(actual.get("workItemId")==bed3 and
          sql(args.db_url,f"select work_state from atlas.work_items where id='{bed3}'")
          =="completed" and
          sql(args.db_url,f"select work_state from atlas.work_items where id='{bed4}'")
          =="open","Bed 3 worker completion also changed Bed 4")
    # Signed governor readback must see the SAME original Work/Result after
    # the Person's physical attestation. A successful worker RPC alone is
    # insufficient, and a result report is not permission to read elsewhere.
    status,governor_page=rpc(api,key,owner,
      "company_work_accountability_native_ledger_self_api_v1",
      dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_scope="native_ledger",
           p_limit=200,p_after_work_item_id=None))
    check(status==200 and isinstance(governor_page,dict) and
          governor_page.get("contractVersion")==
            "company_work_accountability_native_ledger_v1" and
          governor_page.get("selectedNativeLedgerId")==LEDGER and
          governor_page.get("scopeMode")=="native_ledger",
          f"Native governor could not read source Work ledger {status}: "
          f"{str(governor_page)[:200]}")
    governor_original=[row for row in governor_page.get("items",[])
                       if row.get("workItemId")==bed3]
    check(len(governor_original)==1,
          "Governor ledger lost or duplicated same original Bed 3 Work")
    governor_record=governor_original[0]
    check(governor_record.get("workState")=="completed" and
          governor_record.get("nativeLedgerRelevance")==
            "established_for_selected_ledger" and
          governor_record.get("latestWorkerReport",{}).get("resultId")==
            actual.get("resultId") and
          governor_record.get("latestWorkerReport",{}).get("resultKind")==
            "completed" and
          governor_record.get("latestAcceptedResult",{}).get("resultId")==
            actual.get("resultId") and
          governor_record.get("latestAcceptedResult",{}).get("decision")==
            "accepted" and
          governor_record.get("lastResponsibleAllocation",{}).get("allocationId")==
            a.get("allocationId") and
          governor_record.get("lastResponsibleAllocation",{}).get("allocationState")==
            "completed",
          "Governor's original Ledger Work did not read back Person's exact "
          "accepted Result, allocation history and immutable Work ID")
    check(all(row.get("workItemId")!=bed4 or row.get("workState")=="open"
              for row in governor_page.get("items",[])),
          "Bed 3 acceptance also closed independent Bed 4 Work")
    print("PASS signed Person physical Actual -> exact native governor Ledger "
          "Result readback; Bed 4 independent")
    print("PASS signed Bed 3 direct Work, bounded grant and independent Actual")

    # Gate B: a separately governed original Bed may be assigned without
    # creating Today placement. The actual signed bearer, not an owner estimate,
    # must see it in My Work only AFTER both current Subject grants.
    undated=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_work_item_id=bed4,p_target_person_id=PERSON,p_service_date=None,
      p_action_id="e5200000-0000-4000-8000-000000000d08",
      p_reason="Establish Bed 4 responsibility now and schedule the work independently.")
    deny(api,key,worker,"owner_direct_assign_existing_original_work_self_api_v1",
         undated,"Worker cannot invent an unscheduled original Work duty")
    b4=ok(api,key,owner,"owner_direct_assign_existing_original_work_self_api_v1",undated)
    check(b4.get("workItemId")==bed4 and b4.get("targetPersonId")==PERSON and
          b4.get("planId") is None and b4.get("plannedServiceDate") is None and
          b4.get("scheduleState")=="unscheduled" and
          b4.get("responsibilityEstablished") is True and
          b4.get("newWorkCreated") is False and
          b4.get("acceptanceQuestionCreated") is False,
          "Undated assignment fabricated a Work, plan or acceptance question")
    check(sql(args.db_url,"select count(*) from atlas.work_execution_plans "+
          f"where work_item_id='{bed4}'::uuid")=="0",
          "Undated assignment inserted an execution plan anyway")
    again_b4=ok(api,key,owner,"owner_direct_assign_existing_original_work_self_api_v1",
                undated)
    check(again_b4.get("idempotent") is True and
          again_b4.get("allocationId")==b4.get("allocationId") and
          again_b4.get("planId") is None,
          "Undated assignment retry introduced a competing responsibility or plan")
    before_b4=ok(api,key,worker,"connected_person_my_work_self_api_v1",
                 {"p_limit":50,"p_after_allocation_id":None})
    check(all(row.get("workItemId")!=bed4 for row in before_b4.get("items",[])),
          "Undated Work title escaped before original Bed 4 Subject grant")
    for cls,ident in (("identity","e5200000-0000-4000-8000-000000000d09"),
                      ("condition","e5200000-0000-4000-8000-000000000d0a")):
        granted=ok(api,key,owner,"governor_set_subject_disclosure_self_api_v1",
                   action(BED4,cls,"grant",ident))
        check(granted.get("currentlyGranted") is True,
              "Native governor could not grant the exact additional Bed")
    now_b4=ok(api,key,worker,"connected_person_my_work_self_api_v1",
              {"p_limit":50,"p_after_allocation_id":None})
    matching=[row for row in now_b4.get("items",[])
              if row.get("workItemId")==bed4]
    check(len(matching)==1 and matching[0].get("allocationId")==b4.get("allocationId")
          and matching[0].get("scheduleState")=="unscheduled"
          and matching[0].get("planId") is None and
          matching[0].get("workOn") is None,
          "Source did not expose exactly one signed unscheduled original Work")
    absent_day=ok(api,key,worker,"connected_person_company_work_day_self_api_v1",
                  {"p_date":"2030-10-31"})
    check(all(row.get("workItemId")!=bed4
              for row in absent_day.get("items",[])),
          "Merely assigning a Person fabricated a dated Today obligation")
    print("PASS signed undated original Work responsibility, disclosure and no plan")

    # A dated Work obligation is a separately recorded decision over the SAME
    # existing allocation. No governor-only Work detail is copied or replaced.
    schedule=dict(p_work_item_id=bed4,p_service_date="2030-10-31",
                  p_reason="The actual responsible Person now selected a work-on date.")
    deny(api,key,outsider,"connected_person_place_work_self_api_v1",
         schedule,"Unconnected Person cannot schedule someone else's Work")
    placed=ok(api,key,worker,"connected_person_place_work_self_api_v1",schedule)
    check(placed.get("workItemId")==bed4 and placed.get("state")=="placed"
          and placed.get("executionDate")=="2030-10-31"
          and bool(placed.get("planId")) and placed.get("newWorkCreated") is False,
          "Scheduling did not place the original undated Work")
    check(sql(args.db_url,f"select count(*) from atlas.work_allocations "
              f"where work_item_id='{bed4}'::uuid and state='active' "
              "and allocation_role='responsible'")=="1",
          "Scheduling duplicated the original active responsibility")
    signed_day=ok(api,key,worker,"connected_person_company_work_day_self_api_v1",
                  {"p_date":"2030-10-31"})
    dated=[item for item in signed_day.get("items",[])
           if item.get("workItemId")==bed4]
    check(len(dated)==1 and dated[0].get("allocationId")==b4["allocationId"]
          and dated[0].get("planId")==placed["planId"]
          and dated[0].get("executionDate")=="2030-10-31",
          "Signed Person Day lost exact allocation, plan, or original Work")
    same_day=ok(api,key,worker,"connected_person_place_work_self_api_v1",schedule)
    check(same_day.get("idempotent") is True
          and same_day.get("planId")==placed["planId"],
          "Same-day placement retried by minting a new plan")
    shifted=ok(api,key,worker,"connected_person_place_work_self_api_v1",
               dict(p_work_item_id=bed4,p_service_date="2030-11-01",
                    p_reason="Actual responsible Person moved work to the next day."))
    check(shifted.get("workItemId")==bed4
          and shifted.get("executionDate")=="2030-11-01"
          and shifted.get("planId")==placed["planId"],
          "Rescheduling minted an unrelated plan or Work")
    # The exact signed My Work reader must distinguish an explicit move
    # from an overdue original plan: only the rescheduled plan event proves
    # the original date, not an inferred rollover or task creation date.
    moved_read=ok(api,key,worker,"connected_person_my_work_self_api_v1",
                  {"p_limit":50,"p_after_allocation_id":None})
    moved_rows=[row for row in moved_read.get("items",[])
                if row.get("workItemId")==bed4]
    check(len(moved_rows)==1 and
          moved_rows[0].get("workOn")=="2030-11-01" and
          moved_rows[0].get("verifiedMovedFromDate")=="2030-10-31" and
          moved_rows[0].get("allocationId")==b4.get("allocationId"),
          "Signed reader cannot prove true original rescheduling of same Work")
    check(sql(args.db_url,
          "select count(*) from atlas.work_execution_plan_events "
          f"where work_item_id='{bed4}'::uuid and "
          f"plan_id='{placed['planId']}'::uuid and "
          "event_kind='rescheduled' and "
          "from_planned_service_date='2030-10-31'::date and "
          "to_planned_service_date='2030-11-01'::date")=="1",
          "Displayed moved date lacks one persisted original plan event")
    print("PASS signed original Work movement provenance and no phantom migration")

    old_day=ok(api,key,worker,"connected_person_company_work_day_self_api_v1",
               {"p_date":"2030-10-31"})
    new_day=ok(api,key,worker,"connected_person_company_work_day_self_api_v1",
               {"p_date":"2030-11-01"})
    check(all(item.get("workItemId")!=bed4 for item in old_day.get("items",[]))
          and sum(item.get("workItemId")==bed4 for item in new_day.get("items",[]))==1,
          "Rescheduling left a phantom duplicate on the old day")
    # Bed 4 uses manager acceptance, not worker-attestation completion.
    status,result=rpc(api,key,worker,"report_connected_person_company_work_self_api_v1",
                      dict(p_work_item_id=bed4,p_result_kind="completed",
                           p_idempotency_key="clone-bed4-manager-result-not-automatic",
                           p_payload={"claim":"physical Bed 4 work finished"}))
    check(status in (400,403,409,422) and isinstance(result,dict)
          and result.get("code")=="23514",
          "Worker attestation improperly accepted manager-governed Bed 4")
    check(sql(args.db_url,f"select work_state from atlas.work_items "
              f"where id='{bed4}'::uuid")=="open",
          "Rejected manager-only Work report closed original Bed 4")
    cleared=ok(api,key,worker,"connected_person_place_work_self_api_v1",
               dict(p_work_item_id=bed4,p_service_date=None,
                    p_reason="Return exact responsibility to unscheduled My Work."))
    check(cleared.get("state")=="unplanned"
          and cleared.get("workItemId")==bed4,
          "Clearing a day erased original Work responsibility")
    undated_again=ok(api,key,worker,"connected_person_my_work_self_api_v1",
                     {"p_limit":50,"p_after_allocation_id":None})
    original_after=[item for item in undated_again.get("items",[])
                    if item.get("workItemId")==bed4]
    check(len(original_after)==1
          and original_after[0].get("allocationId")==b4["allocationId"]
          and original_after[0].get("scheduleState")=="unscheduled",
          "Unplanning lost or duplicated the Person's original Work")
    print("PASS signed original Work: undated -> dated -> moved -> undated, "
          "same allocation, correct Result authority")

    # Ordinary ORIGINAL Work uses the released standing-responsibility route;
    # it must NOT go through the decomposition-only writer or mint another
    # Work identity. A one-time accepted scope is not a per-task question.
    ordinary="e5200000-0000-4000-8000-000000000901"
    # This is still the SAME seeded synthetic original Work. Classify its
    # source as an original legacy task to prove the released accepted-scope
    # assignment binds the standard ordinary physical Result contract.
    # No duplicate work item or production task is created.
    check(sql(args.db_url,
          f"select count(*) from atlas.work_items where id='{ordinary}'::uuid "
          "and source_object_type is null and result_contract_key is null")=="1",
          "Synthetic existing ordinary Work was already re-contracted")
    sql(args.db_url,
        f"update atlas.work_items set source_object_type='legacy_task' "
        f"where id='{ordinary}'::uuid and source_object_type is null")
    original_count=sql(args.db_url,"select count(*) from atlas.work_items")
    scope_args=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_worker_person_id=PERSON,p_work_item_id=ordinary,
      p_terms="Synthetic worker agrees to this one original mowing Work only; nothing about sprayers, pruning, or other Work is admitted.",
      p_valid_until=None)
    deny(api,key,worker,
         "propose_native_ledger_exact_work_scope_owner_self_api_v1",scope_args,
         "Worker cannot pose as original Ledger governor proposing exact scope")
    scope=ok(api,key,owner,
             "propose_native_ledger_exact_work_scope_owner_self_api_v1",scope_args)
    check(scope.get("coverageMode")=="exact_work" and
          scope.get("coveredWorkItemId")==ordinary,
          "Exact scope proposal did not source-bind the one original Work")
    sid=scope.get("scopeId")
    check(bool(sid) and scope.get("workerConsentRecorded") is False,
          "Standing-scope proposal incorrectly fabricated Person consent")
    before_scope=ok(api,key,worker,"native_ledger_standing_scopes_self_api_v1",{})
    check(any(row.get("scopeId")==sid and row.get("coverageMode")=="exact_work"
              and row.get("coveredWorkItemId")==ordinary and row.get("state")=="proposed"
              for row in before_scope.get("incoming",[])),
          "Worker cannot review exact proposed Work before giving consent")
    response=ok(api,key,worker,"respond_native_ledger_standing_scope_self_api_v1",
                dict(p_scope_id=sid,p_decision="accept"))
    check(response.get("state")=="active"
          and response.get("assignmentCreated") is False,
          "One-time standing acceptance fabricated a new Work assignment")
    unrelated="e5200000-0000-4000-8000-000000000902"
    wrong_args=dict(p_work_item_id=unrelated,p_scope_id=sid,
      p_reason="This is a different original Work and must be denied despite same Ledger.")
    # The real owner may inspect both original Work IDs; an exact accepted
    # scope mismatch is a source CHECK failure (23514), not a 42501
    # authorization failure for an unconnected outsider. HTTP 400 is NOT
    # success: require precisely the invariant violation and no side effect.
    mismatch_status,mismatch_result=rpc(
      api,key,owner,"assign_native_ledger_company_work_under_scope_owner_self_api_v1",
      wrong_args)
    check(mismatch_status==400 and isinstance(mismatch_result,dict) and
          mismatch_result.get("code")=="23514" and
          mismatch_result.get("message")==
            "Open Work and currently accepted Person/Ledger standing scope required",
          "Exact Work agreement did not enforce source constraint: "+
          f"{mismatch_status} {str(mismatch_result)[:200]}")
    print("PASS exact accepted scope rejects a DIFFERENT original Work by 23514")
    check(sql(args.db_url,"select count(*) from atlas.work_allocations "
      f"where work_item_id='{unrelated}'::uuid and state='active'")=="0",
      "Scope mismatch was only a UI denial; unrelated Work was assigned")
    ordinary_args=dict(p_work_item_id=ordinary,p_scope_id=sid,
      p_reason="Assign the existing source-backed ordinary Ledger Work without imposing a day.")
    deny(api,key,worker,"assign_native_ledger_company_work_under_scope_owner_self_api_v1",
         ordinary_args,"Worker cannot self-assign ordinary original Work")
    ordinary_receipt=ok(api,key,owner,
           "assign_native_ledger_company_work_under_scope_owner_self_api_v1",
           ordinary_args)
    ordinary_allocation=ordinary_receipt.get("allocationId")
    check(ordinary_receipt.get("workItemId")==ordinary
          and ordinary_receipt.get("coverageMode")=="exact_work"
          and ordinary_receipt.get("coveredWorkItemId")==ordinary
          and ordinary_receipt.get("responsiblePersonId")==PERSON
          and ordinary_receipt.get("newWorkCreated") is False
          and ordinary_receipt.get("workerAcceptancePerTaskRequired") is False
          and bool(ordinary_allocation),
          "Original ordinary Work assignment minted duplicate Work or question")
    check(sql(args.db_url,"select count(*) from atlas.work_items")==original_count,
          "Ordinary responsibility created another original Work row")
    check(sql(args.db_url,
          f"select count(*) from atlas.work_execution_plans where work_item_id='{ordinary}'::uuid")=="0",
          "Ordinary direct assignment fabricated an execution plan")
    ordinary_mine=ok(api,key,worker,"connected_person_my_work_self_api_v1",
            {"p_limit":100,"p_after_allocation_id":None})
    ordinary_rows=[item for item in ordinary_mine.get("items",[])
                   if item.get("workItemId")==ordinary]
    check(len(ordinary_rows)==1
          and ordinary_rows[0].get("allocationId")==ordinary_allocation
          and ordinary_rows[0].get("scheduleState")=="unscheduled"
          and ordinary_rows[0].get("planId") is None,
          "Existing ordinary Work did not reach signed My Work unscheduled")
    ordinary_placed=ok(api,key,worker,"connected_person_place_work_self_api_v1",
          dict(p_work_item_id=ordinary,p_service_date="2030-11-02",
               p_reason="Responsible Person independently scheduled existing ordinary Work."))
    check(ordinary_placed.get("workItemId")==ordinary
          and ordinary_placed.get("executionDate")=="2030-11-02"
          and bool(ordinary_placed.get("planId")),
          "Ordinary Work cannot use the shared Person-native date writer")
    dated_ordinary=ok(api,key,worker,
                      "connected_person_company_work_day_self_api_v1",
                      {"p_date":"2030-11-02"})
    check(sum(item.get("workItemId")==ordinary for item in
              dated_ordinary.get("items",[]))==1,
          "Ordinary original Work was not in selected signed Person Day")
    still_work=sql(args.db_url,"select count(*) from atlas.work_allocations "
              f"where work_item_id='{ordinary}'::uuid and id='{ordinary_allocation}'::uuid "
              "and state='active' and establishment_basis_kind='delegated_under_standing_scope'")
    check(still_work=="1","Ordinary scheduling invented another responsibility basis")
    check(sql(args.db_url,
          f"select result_contract_key from atlas.work_items where id='{ordinary}'::uuid")
          =="ordinary_company_work_worker_attestation_v1",
          "Released under-scope assignment failed to bind eligible original legacy Result")
    deny(api,key,outsider,"report_connected_person_company_work_self_api_v1",
         dict(p_work_item_id=ordinary,p_result_kind="completed",
              p_idempotency_key="clone-unconnected-mow-cannot-complete",
              p_payload={"physicalActual":"Unconnected outsider falsely claims mowing"}),
         "Outsider cannot complete assigned original ordinary Work")
    ordinary_actual=ok(api,key,worker,
      "report_connected_person_company_work_self_api_v1",
      dict(p_work_item_id=ordinary,p_result_kind="completed",
           p_idempotency_key="clone-existing-legacy-mow-actual",
           p_payload={"physicalActual":"Original synthetic walkways mowed."}))
    check(ordinary_actual.get("workItemId")==ordinary and
          ordinary_actual.get("resultKind")=="completed" and
          ordinary_actual.get("workState")=="completed" and
          bool(ordinary_actual.get("resultId")),
          "Signed Person could not report accepted physical Result on original Work")
    status,ordinary_ledger=rpc(api,key,owner,
      "company_work_accountability_native_ledger_self_api_v1",
      dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_scope="native_ledger",
           p_limit=200,p_after_work_item_id=None))
    check(status==200 and isinstance(ordinary_ledger,dict) and
          ordinary_ledger.get("contractVersion")==
            "company_work_accountability_native_ledger_v1",
          "Root governor original Ledger read unavailable after physical completion")
    ordinary_found=[x for x in ordinary_ledger.get("items",[])
                    if x.get("workItemId")==ordinary]
    check(len(ordinary_found)==1 and
          ordinary_found[0].get("workState")=="completed" and
          ordinary_found[0].get("latestWorkerReport",{}).get("resultId")==
            ordinary_actual.get("resultId") and
          ordinary_found[0].get("latestAcceptedResult",{}).get("resultId")==
            ordinary_actual.get("resultId") and
          ordinary_found[0].get("latestAcceptedResult",{}).get("decision")=="accepted",
          "Root Ledger did not read signed legacy Work's exact completed Result")
    check(sql(args.db_url,"select count(*) from atlas.work_items")==original_count,
          "Original legacy Work result minted a second task")
    print("PASS signed existing ordinary Ledger Work: accepted standing scope, "
          "one original legacy_task, separate date, authorized physical Actual and "
          "exact governing Ledger Result readback")




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

    # The historical organization planning browser RPC is an alternate Work
    # title/Result reader, INCLUDING Work with no subject context links.
    # Prove the internal source guard, not a 404 or merely absent old membership.
    # These memberships and the synthetic unlinked Work exist in this disposable
    # clone ONLY, after all original Bed/Laundry tests finish.
    secret_work="e5200000-0000-4000-8000-000000000b99"
    check(sql(args.db_url,f"select count(*) from atlas.work_items "
          f"where id='{secret_work}'::uuid")=="0",
          "Synthetic unlinked legacy Work ID already in use")
    sql(args.db_url,
      "insert into atlas.work_items(id,organization_id,title,work_state,source_object_type) "
      f"values('{secret_work}'::uuid,'{ORG}'::uuid,"
      "'Private synthetic withheld Bed 5 result, never for historical manager','open',"
      "'legacy_task')")
    check(sql(args.db_url,f"select count(*) from atlas.work_item_context_links "
          f"where work_item_id='{secret_work}'::uuid")=="0",
          "Unlinked alternative-reader probe unexpectedly has a context link")
    old_member=sql(args.db_url,
      "select count(*) from atlas.organization_memberships "
      f"where organization_id='{ORG}'::uuid and user_id='{c1.WORKER}'::uuid")
    if old_member=="0":
        sql(args.db_url,
          "insert into atlas.organization_memberships("
          "id,organization_id,user_id,person_id,role,active) values("
          "'e5200000-0000-4000-8000-000000000b07'::uuid,"
          f"'{ORG}'::uuid,'{c1.WORKER}'::uuid,'{PERSON}'::uuid,"
          "'member',true)")
    else:
        sql(args.db_url,"update atlas.organization_memberships set "
            "active=true,role='member' where "
            f"organization_id='{ORG}'::uuid and user_id='{c1.WORKER}'::uuid")
    sql(args.db_url,"update atlas.farm_memberships set role='manager' "
        f"where farm_id='{FARM}'::uuid and user_id='{c1.WORKER}'::uuid "
        "and active")
    check(sql(args.db_url,"select count(*) from atlas.organization_memberships "
          f"where organization_id='{ORG}'::uuid and user_id='{c1.WORKER}'::uuid "
          "and role='member' and active")=="1" and
          sql(args.db_url,"select count(*) from atlas.farm_memberships "
          f"where farm_id='{FARM}'::uuid and user_id='{c1.WORKER}'::uuid "
          "and role='manager' and active")=="1",
          "Probe must actually carry old organization AND manager access")
    deny(api,key,worker,"organization_management_company_work_planning_queue_api_v1",
         {"p_organization_id":ORG,"p_window_start":None,"p_window_end":None},
         "Signed old organization/farm manager cannot enumerate unlinked Work")
    print("PASS signed old manager denied historical unlinked Work title/Result read")

    Path(args.output).write_text(
        "PASS signed original Bed 3 + Laundry synthetic local source acceptance\n"
        "PENDING independent Event regression and complete alternative-reader sweep\n"
        "NO real Person or production Work altered\n")

if __name__=="__main__":
    main()

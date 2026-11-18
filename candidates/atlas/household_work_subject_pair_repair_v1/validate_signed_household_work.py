#!/usr/bin/env python3
"""Exact original Laundry Work seam proof on a disposable local clone only.
Reuse the canonical original Work synthetic fixture and signed C1 helpers.
No release, no production users, no replacement identity, no policy bypass.
"""
import argparse
import importlib.util
import re
from pathlib import Path
from uuid import UUID

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location("original_work_prerequisite",
    ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
HOUSEHOLD="e5200000-0000-4000-8000-000000000c01"
INSTANCE="e5200000-0000-4000-8000-000000000c03"
OWNER_PERSON="e5200000-0000-4000-8000-000000000101"
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    base.check(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
      "Only disposable local database allowed")
    api,key=c1.local_status()
    def sql(stmt): return base.sql(args.db_url,stmt)
    base.check(sql(f"select count(*) from atlas.household_kernel_instances where id='{INSTANCE}' and household_id='{HOUSEHOLD}' and state='active'")=="1","Original synthetic fixture required")
    base.check(sql(f"select count(*) from atlas.household_need_occurrences_v1 where household_id='{HOUSEHOLD}'")=="0","Fresh unused synthetic fixture required")
    tokens={}
    for name,uid in base.setup_auth(args.db_url):
        token,claims=c1.sign_in(api,key,name)
        sid=str(UUID(claims["session_id"]))
        base.check(claims.get("sub")==uid and sql(f"select count(*) from auth.sessions where id='{sid}' and user_id='{uid}'")=="1","Genuine independently signed session required")
        tokens[name]=token
    def ok(name,body=None): return base.allow(api,key,tokens["owner"],name,body or {})
    def deny(actor,name,body):
        base.deny(api,key,tokens.get(actor),name,body,"original Household authority: "+str(actor))
    initial=ok("household_laundry_current_self_api_v1")
    base.check(initial["instanceId"]==INSTANCE and initial["workItemId"] is None,"No manufactured current Work")
    obs=ok("record_household_laundry_observation_self_api_v1",{"p_kernel_instance_id":INSTANCE,
        "p_action_id":"e5200000-0000-4000-8000-000000000d04","p_observation":"Fictional test load is physically ready."})
    base.check(obs["workCreated"] is False,"Observation cannot itself create Work")
    observe_id=str(UUID(obs["observationId"]))
    establish={"p_kernel_instance_id":INSTANCE,"p_observation_id":observe_id,
       "p_action_id":"e5200000-0000-4000-8000-000000000d05","p_self_carried":True,
       "p_assignee_household_member_id":None}
    for actor in ("worker","outsider","no-seat",None):
        deny(actor,"establish_household_laundry_original_work_self_api_v1",establish)
    made=ok("establish_household_laundry_original_work_self_api_v1",establish)
    work=str(UUID(made["workItemId"])); need=str(UUID(made["needOccurrenceId"]))
    allocation=str(UUID(made["allocationId"]))
    base.check(made["assignedCanonicalPersonId"]==OWNER_PERSON and made["clockAdmitted"] is False,"Exact self carrier; no invented Clock")
    base.check(sql(f"select count(*) from atlas.work_item_context_links where household_id='{HOUSEHOLD}' and organization_id is null and work_item_id='{work}' and subject_domain='household' and subject_kind='kernel_instance' and subject_id='{INSTANCE}' and relation_kind='acts_on'")=="1","The repaired exact native subject link must persist")
    base.check(sql(f"select count(*) from atlas.work_allocations where work_item_id='{work}' and id='{allocation}' and assignee_canonical_person_id='{OWNER_PERSON}' and state='active' and allocation_role='responsible'")=="1","Same responsible allocation")
    replay=ok("establish_household_laundry_original_work_self_api_v1",establish)
    base.check(replay["workItemId"]==work and replay["needOccurrenceId"]==need and replay["noNewWorkCreated"] is True,"No duplicate Work on retry")
    current=ok("household_laundry_current_self_api_v1")
    base.check(current["workItemId"]==work and current["needOccurrenceId"]==need and current["carrierAllocationId"]==allocation,"Signed current original receipt must match")
    # Same original, independently signed native Person responsibility read.
    params={"p_limit":50,"p_after_allocation_id":None}
    packet=ok("household_person_my_work_self_api_v1",params)
    mine=[w for w in packet["items"] if w["workItemId"]==work]
    base.check(len(mine)==1 and mine[0]["allocationId"]==allocation and mine[0]["householdId"]==HOUSEHOLD
      and mine[0]["scopeKind"]=="household" and mine[0]["organizationId"] is None and mine[0]["ledgerId"] is None
      and mine[0]["scheduleState"]=="unscheduled" and mine[0]["workOn"] is None and mine[0]["clockAdmitted"] is False,
      "The native My Work source must return the same undated original responsibility")
    for actor in ("worker","outsider","no-seat"):
        status,payload=base.rpc(api,key,tokens[actor],"household_person_my_work_self_api_v1",params)
        base.check((status==200 and payload.get("ok") is True and all(w["workItemId"]!=work for w in payload["items"]))
          or (status in (401,403) and payload.get("code")=="42501"),"Another Person cannot see this self-carried Work")
    deny(None,"household_person_my_work_self_api_v1",params)
    focus={"p_household_id":HOUSEHOLD,"p_work_item_id":work}
    base.check(ok("household_original_work_focus_self_api_v1",focus)["workItemId"]==work,"Same original focus")
    for actor in ("worker","outsider","no-seat",None):
        deny(actor,"household_original_work_focus_self_api_v1",focus)
    wash={"p_work_item_id":work,"p_action_id":"e5200000-0000-4000-8000-000000000d07","p_note":"Fictional test wash actually started."}
    deny("worker","record_household_laundry_wash_started_self_api_v1",wash)
    receipt=ok("record_household_laundry_wash_started_self_api_v1",wash)
    base.check(receipt["workCompleted"] is True and receipt["laundryCompletelyDone"] is False,"Only original wash-start Work completes")
    again=ok("record_household_laundry_wash_started_self_api_v1",wash)
    base.check(again["idempotent"] is True and again["careResultId"]==receipt["careResultId"],"Same accepted physical result")
    now=ok("household_laundry_current_self_api_v1")
    base.check(now["workItemId"] is None and now["lastCompletedWorkItemId"]==work,"History retained, no automatic successor")
    finished=ok("household_person_my_work_self_api_v1",params)
    base.check(all(w["workItemId"]!=work for w in finished["items"]),"Accepted physical Actual removes only this original from open attention")
    Path(args.output).write_text("PASS signed original Household subject-pair seam: observation, exact Work/link/allocation, replay, independent denials, physical Actual and original history. No Clock admission or duplicate Work.\n")
if __name__=="__main__": main()

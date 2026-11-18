#!/usr/bin/env python3
"""Exact original Laundry Work seam proof on a disposable local clone only.
Reuse the canonical original Work synthetic fixture and signed C1 helpers.
No release, no production users, no replacement identity, no policy bypass.
"""
import argparse
import importlib.util
import re
import time
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
    tokens={}; session_ids={}
    for name,uid in base.setup_auth(args.db_url):
        token,claims=c1.sign_in(api,key,name)
        sid=str(UUID(claims["session_id"]))
        base.check(claims.get("sub")==uid and sql(f"select count(*) from auth.sessions where id='{sid}' and user_id='{uid}'")=="1","Genuine independently signed session required")
        tokens[name]=token; session_ids[name]=sid
    def ok(name,body=None): return base.allow(api,key,tokens["owner"],name,body or {})
    def deny(actor,name,body):
        base.deny(api,key,tokens.get(actor),name,body,"original Household authority: "+str(actor))
    initial=ok("household_laundry_current_self_api_v1")
    base.check(initial["instanceId"]==INSTANCE and initial["workItemId"] is None,"No manufactured current Work")
    params={"p_limit":50,"p_after_allocation_id":None}
    before=ok("household_person_my_work_self_api_v1",params)
    base.check(not before["items"],"Fresh owner fixture may not fabricate Household responsibility")
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
    # Exact accepted wash-start receipt is the sole process anchor.
    reader="household_laundry_reassessment_self_api_v1"
    writer="record_household_laundry_reassessment_self_api_v1"
    interval=ok(reader)
    blocked,payload=base.rpc(api,key,tokens["owner"],"record_household_laundry_observation_self_api_v1",
      {"p_kernel_instance_id":INSTANCE,"p_action_id":"e5200000-0000-4000-8000-000000000d90",
       "p_observation":"A new hamper while original load washing."})
    base.check(blocked>=400 and payload.get("code")=="23514","Do not silently displace running load")
    base.check(interval["state"]=="needs_interval" and interval["workItemId"]==work
      and interval["processResultId"]==receipt["careResultId"]
      and interval["observationId"]==now["lastObservationId"],"Accepted actual, not inferred effort, anchors elapsed process")
    command={"p_work_item_id":work,"p_observation_id":interval["observationId"],
      "p_elapsed_minutes":1,"p_action_id":"e5200000-0000-4000-8000-000000000d81"}
    for actor in ("worker","outsider","no-seat",None):
        deny(actor,writer,command)
        status,payload=base.rpc(api,key,tokens.get(actor),reader,{})
        base.check((status==200 and payload.get("state")=="not_applicable")
          or (status in (401,403) and payload.get("code")=="42501"),"No other actor's process disclosed")
    count_query=f"""select
       (select count(*) from atlas.work_items where household_id='{HOUSEHOLD}')::text||':'||
       (select count(*) from atlas.household_need_occurrences_v1 where household_id='{HOUSEHOLD}')::text||':'||
       (select count(*) from atlas.care_observation_events where scope_id='{HOUSEHOLD}')::text||':'||
       (select count(*) from atlas.care_result_events where scope_id='{HOUSEHOLD}')::text"""
    before_counts=sql(count_query)
    recorded=ok(writer,command)
    base.check(recorded["state"]=="waiting" and recorded["elapsedMinutes"]==1
      and recorded["physicalCompletionInferred"] is False and recorded["workCreated"] is False
      and recorded["clockAdmitted"] is False,"One explicit elapsed minute, with no invented work or completion")
    evidence=str(UUID(recorded["evidenceId"]))
    base.check(sql(f"""select count(*) from atlas.care_current_state c join atlas.evidence_records e
      on e.id::text=c.metadata->>'laundryReassessmentEvidenceId'
      where e.id='{evidence}' and c.scope_id='{HOUSEHOLD}' and c.last_observation_id='{interval["observationId"]}'
      and c.next_reassess_at=e.effective_until and c.condition_state='washing'""")=="1","Exact source pointer and expected reassessment")
    repeat=ok(writer,command)
    base.check(repeat["idempotent"] is True and repeat["evidenceId"]==evidence,"Same expectation replay")
    for change in ({"p_elapsed_minutes":2},{"p_action_id":"e5200000-0000-4000-8000-000000000d82"},{"p_observation_id":observe_id}):
        status,payload=base.rpc(api,key,tokens["owner"],writer,dict(command,**change))
        base.check(status>=400 and payload.get("code") in ("23505","23514"),"Reject competing or stale expectation")
    # No false fixture timestamps. Observe real elapsed time in this disposable test.
    deadline=time.monotonic()+80
    while True:
        due=ok(reader)
        if due["state"]=="due":break
        base.check(due["state"]=="waiting" and time.monotonic()<deadline,"Expected server-timed due transition")
        time.sleep(2)
    base.check(due["evidenceId"]==evidence and due["physicalCompletionInferred"] is False
      and due["workCreated"] is False and due["clockAdmitted"] is False,"Due is only an expectation")
    base.check(sql(count_query)==before_counts,"Time passage creates no new Work, Need, observation or result")
    still_writer="record_household_laundry_still_running_self_api_v1"
    still={"p_work_item_id":work,"p_observation_id":interval["observationId"],
      "p_elapsed_minutes":12,"p_action_id":"e5200000-0000-4000-8000-000000000d86"}
    for actor in ("worker","outsider","no-seat",None): deny(actor,still_writer,still)
    still_running=ok(still_writer,still)
    base.check(still_running["state"]=="waiting" and still_running["observationId"]!=interval["observationId"]
       and still_running["processResultId"]==receipt["careResultId"],"Actual still-running observation anchors new expectation")
    base.check(ok(still_writer,still)["evidenceId"]==still_running["evidenceId"],"Same running observation replay")
    interval=still_running
    finish_writer="record_household_laundry_wash_finished_self_api_v1"
    finish={"p_work_item_id":work,"p_observation_id":interval["observationId"],
       "p_action_id":"e5200000-0000-4000-8000-000000000d83","p_self_carried":True}
    for actor in ("worker","outsider","no-seat",None):
        deny(actor,finish_writer,finish)
    wet=ok(finish_writer,finish)
    dry_work=str(UUID(wet["workItemId"]))
    base.check(dry_work!=work and wet["conditionState"]=="wet_ready_for_drying" and wet["laundryCompletelyDone"] is False,
        "Physical finish establishes a distinct drying Work")
    base.check(ok(reader)["state"]=="not_applicable","Finished observation withdraws old reassessment")
    repeated=ok(finish_writer,finish)
    base.check(repeated["idempotent"] is True and repeated["workItemId"]==dry_work,"Same drying original on replay")
    dry_rows=ok("household_person_my_work_self_api_v1",params)["items"]
    base.check(sum(w["workItemId"]==dry_work and w["resultContractKey"]=="household_laundry_begin_drying_v1" for w in dry_rows)==1,
        "Drying appears in the same Person Work source")
    status,payload=base.rpc(api,key,tokens["owner"],finish_writer,dict(finish,p_action_id="e5200000-0000-4000-8000-000000000d84"))
    base.check(status>=400 and payload.get("code")=="23514","No second drying original from old wash")
    dry_args={"p_work_item_id":dry_work,"p_action_id":"e5200000-0000-4000-8000-000000000d85","p_note":"Fictional drying began."}
    deny("worker","record_household_laundry_drying_started_self_api_v1",dry_args)
    dry=ok("record_household_laundry_drying_started_self_api_v1",dry_args)
    base.check(dry["workCompleted"] is True and dry["laundryCompletelyDone"] is False,"Only drying start completes")
    base.check(ok("record_household_laundry_drying_started_self_api_v1",dry_args)["careResultId"]==dry["careResultId"],"Dry start replay")
    base.check(ok("household_laundry_current_self_api_v1")["lastCompletedWorkItemId"]==work,"Wash-start history not relabeled")
    dry_interval=ok(reader)
    base.check(dry_interval["state"]=="needs_interval" and dry_interval["processKind"]=="drying"
       and dry_interval["workItemId"]==dry_work,"Drying owns a distinct elapsed process")
    dry_check=ok(writer,{"p_work_item_id":dry_work,"p_observation_id":dry_interval["observationId"],
      "p_elapsed_minutes":30,"p_action_id":"e5200000-0000-4000-8000-000000000d87"})
    base.check(dry_check["state"]=="waiting" and dry_check["processResultId"]==dry["careResultId"],"Drying estimate anchored to original dry start")
    done_writer="record_household_laundry_dry_finished_self_api_v1"
    done={"p_work_item_id":dry_work,"p_observation_id":dry_check["observationId"],
      "p_action_id":"e5200000-0000-4000-8000-000000000d88","p_self_carried":True}
    for actor in ("worker","outsider","no-seat",None): deny(actor,done_writer,done)
    ready=ok(done_writer,done)
    return_work=str(UUID(ready["workItemId"]))
    base.check(ready["conditionState"]=="dry_ready_for_return" and return_work not in (work,dry_work),"Observed dry load establishes exact next Work")
    base.check(ok(done_writer,done)["workItemId"]==return_work,"Replay preserves return Work")
    base.check(ok(reader)["state"]=="not_applicable","Dry finish withdraws elapsed attention")
    final={"p_work_item_id":return_work,"p_action_id":"e5200000-0000-4000-8000-000000000d89","p_note":"Fictional dry load returned to use."}
    deny("worker","record_household_laundry_returned_to_use_self_api_v1",final)
    result=ok("record_household_laundry_returned_to_use_self_api_v1",final)
    base.check(result["workCompleted"] is True and result["loadReturnedToUse"] is True
      and result["laundryCompletelyDone"] is False,"Only this tracked load returned; no whole Household assertion")
    base.check(ok("record_household_laundry_returned_to_use_self_api_v1",final)["careResultId"]==result["careResultId"],"Exact return receipt replay")
    base.check(ok("household_laundry_current_self_api_v1")["currentCondition"]=="returned_to_use","Actual return state retained")
    base.check(not ok("household_person_my_work_self_api_v1",params)["items"],"Completed tracked load leaves no phantom Work")
    # A second real observation in the fictional clone can establish a
    # distinct Work assigned to an actual signed member, not the governor.
    next_obs=ok("record_household_laundry_observation_self_api_v1",{
        "p_kernel_instance_id":INSTANCE,
        "p_action_id":"e5200000-0000-4000-8000-000000000d14",
        "p_observation":"Second fictional load is physically ready."})
    base.check(ok(reader)["state"]=="not_applicable","Superseded physical observation must not restore stale attention")
    status,payload=base.rpc(api,key,tokens["owner"],writer,command)
    base.check(status>=400 and payload.get("code")=="23514","Old expectation replay cannot restore a superseded process")
    member="e5200000-0000-4000-8000-000000000c02"
    next_work=ok("establish_household_laundry_original_work_self_api_v1",dict(establish,
       p_observation_id=next_obs["observationId"],
       p_action_id="e5200000-0000-4000-8000-000000000d15",
       p_self_carried=False,p_assignee_household_member_id=member))
    next_id=str(UUID(next_work["workItemId"]))
    base.check(next_id!=work,"New observation creates a separate original, not resurrection")
    mine=ok("household_person_my_work_self_api_v1",params)
    base.check(not any(w["workItemId"]==next_id for w in mine["items"]),
      "Governance alone is not personal responsibility")
    worker=base.allow(api,key,tokens["worker"],"household_person_my_work_self_api_v1",params)
    base.check(sum(w["workItemId"]==next_id and w["allocationId"]==next_work["allocationId"]
       and w["householdId"]==HOUSEHOLD for w in worker["items"])==1,
       "Exact signed member allocation must be visible to that member")
    # Local fixture change only; verify same live bearer loses access
    # immediately on member revocation; no credential or permission change on production.
    sql(f"update atlas.household_members set active=false where id='{member}' and household_id='{HOUSEHOLD}'")
    worker=base.allow(api,key,tokens["worker"],"household_person_my_work_self_api_v1",params)
    base.check(all(w["workItemId"]!=next_id for w in worker["items"]),"Revoked member cannot read assigned Household Work")
    deny("worker","household_original_work_focus_self_api_v1",{"p_household_id":HOUSEHOLD,"p_work_item_id":next_id})
    # Revoke the synthetic owner's actual GoTrue session without altering the
    # still-issued bearer; it may no longer invoke the authenticated reader.
    sql(f"delete from auth.sessions where id='{session_ids['owner']}' and user_id='{c1.OWNER}'")
    deny("owner",reader,{})
    deny("owner",writer,command)
    deny("owner","household_person_my_work_self_api_v1",params)
    deny("owner","household_original_work_focus_self_api_v1",{"p_household_id":HOUSEHOLD,"p_work_item_id":next_id})
    Path(args.output).write_text("PASS signed Laundry elapsed reassessment: same accepted actual, independent denials, explicit interval, real elapsed waiting/due, idempotence, stale/revoked refusal and no phantom Work or physical result.\n")
if __name__=="__main__": main()

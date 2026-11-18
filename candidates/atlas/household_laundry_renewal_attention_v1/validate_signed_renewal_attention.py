"""Signed renewal checks to attach after the existing held lifecycle's closed-load proof.

Only the disposable driver supplies ok/deny/rpc/sql and its synthetic scope.
No session factory, alternate authority, time override, or production runner.
"""
from uuid import UUID
from datetime import datetime

def check_after_closed_load(*,ok,deny,owner_rpc,sql,check,household,instance,closed_result_id):
    read="household_laundry_renewal_attention_self_api_v1"
    write="record_household_laundry_renewal_not_ready_self_api_v1"
    def stamp(value): return datetime.fromisoformat(value.replace("Z","+00:00"))
    def safe(p):
        check(p["workCreated"] is False and p["needCreated"] is False and
              p["clockAdmitted"] is False and p["physicalNeedInferred"] is False,
              "Renewal attention is neither Need, Work nor Clock admission")
    def counts():
        return sql(f"""select
          (select count(*) from atlas.work_items where household_id='{household}')::text||':'||
          (select count(*) from atlas.household_need_occurrences_v1 where household_id='{household}')::text||':'||
          (select count(*) from atlas.care_result_events where scope_id='{household}')::text||':'||
          (select count(*) from atlas.care_observation_events where scope_id='{household}')::text""")
    household=str(UUID(household)); instance=str(UUID(instance)); closed_result_id=str(UUID(closed_result_id))
    check(household=="e5200000-0000-4000-8000-000000000c01" and instance=="e5200000-0000-4000-8000-000000000c03",
          "Exact disposable original Household fixture required")
    before=counts()
    calibration=ok("calibrate_personal_laundry_kernel_self_api_v1",{"p_input":{
        "laundryLocation":"home","usualPattern":"little_most_days","expectedMinutes":45}})
    check(calibration["instance"]["id"]==instance,"Original instance identity is preserved")
    proposal=ok(read); safe(proposal)
    check(proposal["state"]=="proposal" and proposal["renewAfterDays"]==1 and
          proposal["decisionId"] is None and proposal["expectedCheckAt"] is None,
          "Declared pattern offers a decision; no schedule is established")
    check(counts()==before,"Calibration and proposal do not issue or complete Work")
    rhythm="household_laundry_explicit_rhythm_decide_self_api_v1"
    decision={"p_kernel_instance_id":instance,
       "p_action_id":"e5200000-0000-4000-8000-000000000da1","p_decision_kind":"establish",
       "p_renew_after_days":1,"p_decision_reason":"Fictional owner accepts a daily condition check."}
    for actor in ("worker","outsider","no-seat",None): deny(actor,rhythm,decision)
    accepted=ok(rhythm,decision)
    check(accepted["workCreated"] is False and accepted["currentlyEstablished"] is True,
          "One existing governing decision, no work")
    waiting=ok(read);safe(waiting)
    check(waiting["state"]=="waiting" and waiting["decisionId"]==accepted["decisionId"]
          and waiting["observationId"]==proposal["observationId"] and
          (stamp(waiting["expectedCheckAt"])-stamp(waiting["washStartedAt"])).total_seconds()==86400,
          "Exact original wash actual plus accepted interval")
    negative={"p_instance_id":instance,"p_observation_id":waiting["observationId"],
              "p_decision_id":accepted["decisionId"],"p_action_id":"e5200000-0000-4000-8000-000000000da2"}
    for actor in ("worker","outsider","no-seat",None): deny(actor,write,negative)
    status,payload=owner_rpc(write,negative)
    check(status>=400 and payload.get("code")=="23514","An early check cannot assert a due response")
    check(counts()==before,"No phantom observation, Work, Need or Result")
    withdraw=dict(decision,p_action_id="e5200000-0000-4000-8000-000000000da3",
                  p_decision_kind="withdraw",p_renew_after_days=None,
                  p_decision_reason="Fictional owner withdraws the inspection rhythm.")
    check(ok(rhythm,withdraw)["currentlyEstablished"] is False,"Existing decision withdrawn")
    check(ok(read)["state"]=="not_applicable","Withdrawal does not resurrect the proposal")
    status,payload=owner_rpc(write,negative)
    check(status>=400 and payload.get("code")=="23514","Superseded decision cannot write an observation")
    check(counts()==before,"Withdrawal preserves existing physical state")
    again=dict(decision,p_action_id="e5200000-0000-4000-8000-000000000da4")
    check(ok(rhythm,again)["currentlyEstablished"] is True,"Explicit re-establishment only")
    safe(ok(read))
    check(ok(read)["state"]=="waiting","Accepted rhythm waits again")
    check(sql(f"select count(*) from atlas.care_result_events where id='{closed_result_id}' and scope_id='{household}' and condition_after='returned_to_use'")=="1",
          "Closed physical Result remains exactly the original")
    check(counts()==before,"Original Work and Need counts unchanged")
    # The existing driver then makes the next real ready observation. The
    # separate historical-disposable test must prove actual due + negative
    # renewal without changing a signed historical timestamp. No time override.
    return "proposal_wait_withdrawal_preservation_pass"

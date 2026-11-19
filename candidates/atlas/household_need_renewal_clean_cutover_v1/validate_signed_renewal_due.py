"""Due renewal proof, to be attached only to an isolated historical fixture.

The caller must use genuine independent localhost GoTrue signed users and
a separately admitted fictional historical closed load. This probe does not
manufacture a due time, modify prior actuals, or install a test clock.
"""
from datetime import datetime
from uuid import UUID

HOUSEHOLD="e5200000-0000-4000-8000-000000000c01"
INSTANCE="e5200000-0000-4000-8000-000000000c03"

def check_due_renewal(*,ok,deny,owner_rpc,sql,check,household,instance):
    check(str(UUID(household))==HOUSEHOLD and str(UUID(instance))==INSTANCE,
          "Exact fictional disposable scope required")
    read="household_laundry_renewal_attention_self_api_v1"
    write="record_household_laundry_renewal_not_ready_self_api_v1"
    def stamp(value): return datetime.fromisoformat(value.replace("Z","+00:00"))
    def safe(p):
        check(all(p[k] is False for k in ("workCreated","needCreated","clockAdmitted","physicalNeedInferred")),
              "An anticipated inspection never issues Work or asserts Need")
    def census():
        return sql(f"""select jsonb_build_object(
          'work',(select jsonb_agg(to_jsonb(w) order by w.id) from atlas.work_items w where household_id='{HOUSEHOLD}'),
          'need',(select jsonb_agg(to_jsonb(n) order by n.id) from atlas.household_need_occurrences_v1 n where household_id='{HOUSEHOLD}'),
          'result',(select jsonb_agg(to_jsonb(r) order by r.id) from atlas.care_result_events r where scope_id='{HOUSEHOLD}'),
          'execution',(select jsonb_agg(to_jsonb(r) order by r.id) from atlas.work_execution_results r where household_id='{HOUSEHOLD}'),
          'acceptance',(select jsonb_agg(to_jsonb(a) order by a.id) from atlas.work_result_acceptances a where household_id='{HOUSEHOLD}'),
          'rhythm',(select jsonb_agg(to_jsonb(r) order by r.id) from atlas.household_rhythms r where household_id='{HOUSEHOLD}'),
          'decision',(select jsonb_agg(to_jsonb(d) order by d.decision_seq) from atlas.household_need_renewal_decisions_v1 d where household_id='{HOUSEHOLD}'),
          'satisfaction',(select jsonb_agg(to_jsonb(s) order by s.id) from atlas.rhythm_satisfactions s where household_id='{HOUSEHOLD}')
        )::text""")
    def observation_count():
        return int(sql(f"select count(*) from atlas.care_observation_events where scope_kind='household' and scope_id='{HOUSEHOLD}'"))
    due=ok(read);safe(due)
    check(due["state"]=="due" and due["householdId"]==HOUSEHOLD and due["instanceId"]==INSTANCE,
          "Genuine already-elapsed historical anchor required; no clock override")
    check(stamp(due["expectedCheckAt"])<=stamp(due["asOf"]) and
          (stamp(due["expectedCheckAt"])-stamp(due["anchorAt"])).total_seconds()==due["renewAfterDays"]*86400,
          "Accepted interval is genuinely due at database time")
    check(ok("household_laundry_current_self_api_v1")["workItemId"] is None,
          "No existing Work before checking renewed Need")
    old=str(UUID(due["observationId"])); closed=str(UUID(due["closedLoadObservationId"]))
    decision=str(UUID(due["decisionId"]))
    before=census(); observations=observation_count()
    command={"p_instance_id":INSTANCE,"p_observation_id":old,
             "p_decision_id":decision,"p_action_id":"e5200000-0000-4000-8000-000000000db1"}
    for actor in ("worker","outsider","no-seat",None): deny(actor,write,command)
    for change in ({"p_instance_id":"e5200000-0000-4000-8000-000000000db2"},
                   {"p_observation_id":"e5200000-0000-4000-8000-000000000db3"},
                   {"p_decision_id":"e5200000-0000-4000-8000-000000000db4"}):
        status,payload=owner_rpc(write,dict(command,**change))
        check(status>=400 and payload.get("code") in ("23514","23505","42501"),"Reject stale or wrong source")
    check(census()==before and observation_count()==observations,"Denied actions preserve every original")
    again_due=ok(read);safe(again_due)
    check(again_due["state"]=="due" and again_due["observationId"]==old and
          census()==before and observation_count()==observations,"Reading due does not mutate anything")
    after=ok(write,command);safe(after)
    fresh=str(UUID(after["observationId"]))
    check(after["state"]=="waiting" and after["idempotent"] is False and fresh!=old and
          after["closedLoadObservationId"]==closed and after["decisionId"]==decision and
          after["washStartedAt"]==due["washStartedAt"] and
          after["renewAfterDays"]==due["renewAfterDays"] and
          (stamp(after["expectedCheckAt"])-stamp(after["anchorAt"])).total_seconds()==due["renewAfterDays"]*86400 and
          stamp(after["expectedCheckAt"])>stamp(after["asOf"]),"Negative actual renews same eligibility from observation")
    check(sql(f"""select count(*) from atlas.care_observation_events o
          join atlas.care_current_state c on c.last_observation_id=o.id
          where o.id='{fresh}' and o.scope_kind='household' and o.scope_id='{HOUSEHOLD}'
            and o.subject_id='{INSTANCE}' and o.condition_state='accumulating'
            and o.inferred_from_clock=false and o.metadata->>'previousObservationId'='{old}'
            and o.metadata->>'closedLoadObservationId'='{closed}'
            and o.metadata->>'renewalDecisionId'='{decision}' and c.condition_state='accumulating'
            and c.scope_id='{HOUSEHOLD}'""")=="1","One genuine condition observation, original closed load conserved")
    replay=ok(write,command);safe(replay)
    check(replay["idempotent"] is True and replay["observationId"]==fresh and
          replay["expectedCheckAt"]==after["expectedCheckAt"],"Exact action replay is not another observation")
    for change in ({"p_action_id":"e5200000-0000-4000-8000-000000000db5"},
                   {"p_observation_id":fresh}):
        status,payload=owner_rpc(write,dict(command,**change))
        check(status>=400 and payload.get("code") in ("23514","23505"),"Competing or changed intent rejected")
    check(census()==before and observation_count()==observations+1,
          "Exactly one observation appended; all Work/Need/Result/Rhythm records identical")
    ready=ok("record_household_laundry_observation_self_api_v1",{
         "p_kernel_instance_id":INSTANCE,"p_action_id":"e5200000-0000-4000-8000-000000000db6",
         "p_observation":"Fictional household now has enough laundry for a load."})
    check(ready["workCreated"] is False and ok(read)["state"]=="not_applicable",
          "Physical readiness replaces anticipated attention, not automatic Work")
    status,payload=owner_rpc(write,command)
    check(status>=400 and payload.get("code")=="23514","Late observation replay cannot resurrect attention")
    check(census()==before and observation_count()==observations+2,
          "Original history conserved after genuine new readiness")
    return "PASS signed due renewal: no mutation by time/read; one negative actual, exact replay, stale denial, renewed waiting, actual ready supersedes attention; no phantom Work."

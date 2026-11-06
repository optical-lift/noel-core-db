#!/usr/bin/env python3
"""Disposable-only real GoTrue bearer proof of one Event checklist state Done.

Runs AFTER the canonical signed Event schedule test, against exact held native
completion packet on a local PG17+PostgREST clone, never a live database.
Existing first-party Event and shared Work public RPCs; no invented Done API.
"""
import argparse
import importlib.util
import re
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "signed_schedule_base",
    BASE / "scripts" / "validate-atlas-one-event-schedule-writer-signed-http.py",
)
schedule = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(schedule)
ORG = schedule.ORG
LEDGER = schedule.LEDGER
OCC = schedule.CANONICAL_A
OTHER = schedule.CANONICAL_B
PERSON = schedule.MEMBER_PERSON
MEMBER = schedule.MEMBER

def check(statement, reason):
    if not statement:
        raise AssertionError(reason)

def scalar(db, query):
    return schedule.sql(db, query)

def call(api, key, token, rpc, payload):
    return schedule.request(api, key, "/rest/v1/rpc/" + rpc, payload, token)

def permitted(api, key, token, rpc, payload):
    status, result = call(api, key, token, rpc, payload)
    check(status == 200 and isinstance(result, dict) and result.get("ok") is True,
          f"{rpc} signed POST expected source receipt, got HTTP {status}: {str(result)[:250]}")
    return result

def denied(api, key, token, rpc, payload, label):
    status, result = call(api, key, token, rpc, payload)
    check(status in (401,403) and isinstance(result,dict)
          and result.get("code") == "42501",
          f"{label} expected genuine SQLSTATE 42501, got HTTP {status}: {str(result)[:240]}")
    print("PASS", label)

def qid(value):
    check(isinstance(value,str) and bool(re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", value)),
        "Exact synthetic original row ID required")
    return value

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
        "Only disposable localhost PostgreSQL 17 is allowed")
    api, key = schedule.local_endpoint()
    # The canonical signed Event schedule regression ran immediately before
    # this test and initialized the synthetic member/outsider GoTrue identities.
    member, claims = schedule.signed_session(
        api, key, "atlas-write-member@example.invalid")
    outsider, outside_claims = schedule.signed_session(
        api, key, "atlas-write-outsider@example.invalid")
    for token_claims, uid in ((claims, MEMBER),(outside_claims,schedule.OUTSIDER)):
        check(token_claims.get("sub")==uid and token_claims.get("session_id"),
              "Separate genuine synthetic signer and session ID required")
        check(scalar(args.db_url,
            f"SELECT count(*) FROM auth.sessions WHERE id='{token_claims['session_id']}'::uuid "
            f"AND user_id='{uid}'::uuid")=="1",
            "A token without a current recorded GoTrue session is not admitted")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM ledger.seats WHERE ledger_id='{LEDGER}'::uuid "
        f"AND person_entity_id='{PERSON}'::uuid AND seat_state='active'")=="1",
        "Exact connected Person's synthetic Ledger seat is absent")
    print("PASS two independent genuine signed Event Person sessions and live seats")

    create = dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                  p_occurrence_id=OCC,
                  p_sentence="Set out and count chairs for synthetic Gathering",
                  p_source_action_id="signed-event-shared-work-20261105-create")
    mark_fn="mark_ledger_occurrence_shared_work_done_self_api_v1"
    create_fn="create_ledger_occurrence_shared_work_self_api_v1"
    denied(api,key,outsider,create_fn,create,
           "outsider cannot create Work in someone else's exact Event")
    response=permitted(api,key,member,create_fn,create)
    work=qid(response.get("workItemId"))
    check(response.get("created") is True
      and response.get("idempotent") is False
      and response.get("assignmentCreated") is False
      and response.get("workerDayCreated") is False
      and response.get("workState")=="open",
      "Original shared Event creation must not invent worker/Date/assignment")
    duplicate=permitted(api,key,member,create_fn,create)
    check(duplicate.get("workItemId")==work and duplicate.get("idempotent") is True
       and duplicate.get("created") is False,
       "Same source action created duplicate original Work")
    check(scalar(args.db_url,
       f"SELECT count(*) FROM atlas.work_items WHERE id='{work}'::uuid "
       f"AND source_object_type='ledger_occurrence_shared_work' "
       f"AND result_contract_key='ledger_occurrence_shared_confirmation_v1' "
       f"AND work_state='open'")=="1",
       "Source-bound shared Event original Work missing before Done")
    check(scalar(args.db_url,
       f"SELECT count(*) FROM atlas.work_allocations WHERE work_item_id='{work}'::uuid")=="0",
       "Shared checklist is not delegated worker obligation")

    action="signed-event-state-confirmed-once-20261105"
    mark=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
              p_occurrence_id=OCC,p_work_item_id=work,
              p_source_action_id=action)
    denied(api,key,outsider,mark_fn,mark,
           "unconnected signed outsider cannot confirm exact Event Work")
    denied(api,key,member,mark_fn,{**mark,"p_occurrence_id":OTHER},
           "other canonical Event must not control original Work")
    recorded=permitted(api,key,member,mark_fn,mark)
    result_id=qid(recorded.get("resultId"))
    receipt_id=qid(recorded.get("acceptanceId"))
    event_id=qid(recorded.get("eventId"))
    check(recorded.get("workState")=="completed"
       and recorded.get("alreadyDone") is False
       and recorded.get("idempotent") is False
       and recorded.get("physicalPerformerAsserted") is False
       and recorded.get("personalPerformanceNotClaimed") is True
       and recorded.get("markedByPersonId")==PERSON
       and recorded.get("originalResultId")==result_id
       and recorded.get("acceptedEvidenceId")==receipt_id,
       "One signed shared Event Done must preserve Result/Acceptance and no-physical-performer receipt")
    check(recorded.get("eventReceipt",{}).get("eventId")==event_id,
       "Existing Event API must contain exact same one universal lifecycle receipt")
    check(scalar(args.db_url,f"""
       SELECT count(*) FROM atlas.work_execution_results result
       JOIN atlas.work_result_acceptances accepted
         ON accepted.execution_result_id=result.id
       WHERE result.id='{result_id}'::uuid AND result.work_item_id='{work}'::uuid
         AND result.reported_by_user_id='{MEMBER}'::uuid
         AND result.result_kind='completed'
         AND result.responsible_allocation_id IS NULL
         AND result.payload->>'stateAssertion'='ordinary_shared_work_marked_done'
         AND result.payload->>'personalPerformanceNotClaimed'='true'
         AND result.payload->'performedByPersonId'='null'::jsonb
         AND result.metadata->>'notWorkerResult'='true'
         AND accepted.id='{receipt_id}'::uuid AND accepted.decision='accepted'
         AND accepted.acceptance_kind='shared_checklist_state_confirmation'
         AND accepted.evidence->>'physicalPerformerAsserted'='false'
     """)=="1","Exact source Result/Acceptance must carry no asserted physical performer")
    check(scalar(args.db_url,f"""
       SELECT count(*) FROM atlas.work_lifecycle_events_v1
       WHERE work_item_id='{work}'::uuid
         AND event_kind='work_transition_applied'
         AND source_row_id='{receipt_id}'::uuid
         AND from_state='open' AND to_state='completed'
         AND actor_user_id='{MEMBER}'::uuid
         AND evidence_refs->>'personalPerformanceNotClaimed'='true'
     """)=="1","Must have exactly one source-backed authoritative transition")
    print("PASS signed Person marked exact shared Event state with one accepted Result and one non-performance Done")

    again=permitted(api,key,member,mark_fn,mark)
    check(again.get("idempotent") is True and again.get("eventId")==event_id
          and again.get("resultId")==result_id
          and again.get("markedByPersonId")==PERSON
          and again.get("physicalPerformerAsserted") is False,
          "Same signed action replay must preserve first actor and same one Done")
    second=permitted(api,key,member,mark_fn,
        {**mark,"p_source_action_id":"distinct-event-action-after-done-20261105"})
    check(second.get("alreadyDone") is True
          and second.get("newTransitionApplied") is False
          and second.get("markedByPersonId") is None,
          "Distinct action after Done must not adopt prior completion as new physical actor")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_execution_results WHERE work_item_id='{work}'::uuid")=="1",
        "Second action or replay fabricated a new original Result")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_lifecycle_events_v1 "
        f"WHERE work_item_id='{work}'::uuid AND event_kind='work_transition_applied'")=="1",
        "Second action or replay caused duplicate immutable Done")
    print("PASS exact action replay and distinct action leave one Done and one original Result")

    # The state-confirming Person's Ledger participation can be withdrawn.
    scalar(args.db_url,
        f"UPDATE ledger.seats SET seat_state='ended',ended_at=now() "
        f"WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{PERSON}'::uuid "
        "AND seat_state='active'")
    denied(api,key,member,mark_fn,mark,
           "revoked Ledger connection must close even prior signed Event action")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_lifecycle_events_v1 "
        f"WHERE work_item_id='{work}'::uuid AND event_kind='work_transition_applied'")=="1",
        "Permission revocation must preserve only original Done")
    check(scalar(args.db_url,
        f"SELECT work_state FROM atlas.work_items WHERE id='{work}'::uuid")=="completed",
        "Revoking a connection cannot erase prior historical Work state")
    Path(args.output).write_text(
       "PASS independently signed shared Event checklist original Work, state-only Result, "
       "one universal Done, legacy receipt, two replay modes, outsider/wrong Event/revoked denials\n"
       "NOT PROVEN: live Event UI, historical cancellation, production, concurrent sessions\n",
       encoding="utf-8")
    print("PASS signed shared Event checklist completion, same-action replay and current permission withdrawal")

if __name__=="__main__":
    main()

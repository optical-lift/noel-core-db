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

    # Source ACL on the *current production-shaped schema* independently
    # gates Event Work creation. The held completion packet must not mint an
    # execute privilege for that out-of-scope writer. Read current cloned ACL.
    create = dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                  p_occurrence_id=OCC,
                  p_sentence="Set out and count chairs for synthetic Gathering",
                  p_source_action_id="signed-event-shared-work-20261105-create")
    mark_fn="mark_ledger_occurrence_shared_work_done_self_api_v1"
    create_fn="create_ledger_occurrence_shared_work_self_api_v1"
    check(scalar(args.db_url,
        "SELECT has_function_privilege('authenticated',"
        "'atlas.create_ledger_occurrence_shared_work_self_api_v1(uuid,uuid,uuid,text,text)','EXECUTE')"
        )=="f","The schema unexpectedly grants Event create: separate source permission review")
    check(scalar(args.db_url,
        "SELECT has_function_privilege('authenticated',"
        "'atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(uuid,uuid,uuid,uuid,text)','EXECUTE')"
        )=="t","Existing signed Person Event state-confirmation RPC is not admitted")
    denied(api,key,outsider,create_fn,create,
           "out-of-scope Event creation remains ACL-denied to outsider")
    denied(api,key,member,create_fn,create,
           "connected Person Event creation currently ACL-denied; no new grant")
    # Mimic *preexisting* source-authored Work only in a disposable fixture.
    # No accepted Result, lifecycle Done, API authority, browser grant or
    # physical performance is inserted. The following signed mark POST is
    # the first and only source-authorized terminal transition.
    work="f5210000-0000-4000-8000-000000000a91"
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_items WHERE id='{work}'::uuid")=="0",
        "Fixture Work ID must not collide with existing original")
    scalar(args.db_url,f"""
      BEGIN;
      INSERT INTO atlas.work_items (
        id,organization_id,title,work_state,source_object_type,source_object_id,
        result_contract_key,created_by_user_id,stable_key,metadata
      ) VALUES (
        '{work}'::uuid,'{ORG}'::uuid,
        'Set out and count chairs for synthetic Gathering','open',
        'ledger_occurrence_shared_work','{OCC}'::uuid,
        'ledger_occurrence_shared_confirmation_v1',
        '{MEMBER}'::uuid,
        'ledger-occurrence-shared:'||md5(
          '{LEDGER}:{OCC}:{PERSON}:signed-event-shared-work-20261105-create'),
        jsonb_build_object(
          'sourceContract','ledger_occurrence_shared_work_v1',
          'ledgerId','{LEDGER}','occurrenceId','{OCC}',
          'sourceActionId','signed-event-shared-work-20261105-create',
          'createdByPersonId','{PERSON}',
          'custody','institutional','ordinarySharedChecklist',true,
          'exclusiveAssigneeAuthority',false,'workerDayRequired',false,
          'physicalPerformerNotInferred',true,
          'syntheticFixtureOnly',true)
      );
      INSERT INTO atlas.company_work_native_ledger_relevance(
        organization_id,work_item_id,ledger_id,evidence_kind,
        attestation_source_ref,attestation_reason,established_by_person_id
      ) VALUES ('{ORG}'::uuid,'{work}'::uuid,'{LEDGER}'::uuid,
        'participant_attested','atlas.work_items:{work}',
        'Disposable preexisting Event work; no real Person or Work',
        '{PERSON}'::uuid);
      SELECT atlas.attach_work_item_context_internal_v1(
         '{work}'::uuid,'temporal','occurrence','{OCC}'::uuid,'for',null,
         jsonb_build_object('source','synthetic_existing_event_original',
            'createdByPersonId','{PERSON}','ledgerId','{LEDGER}'),
         '{{"purpose":"ordinary_shared_work"}}'::jsonb);
      COMMIT;
    """)
    check(scalar(args.db_url,
       f"SELECT count(*) FROM atlas.work_items WHERE id='{work}'::uuid "
       f"AND source_object_type='ledger_occurrence_shared_work' "
       f"AND result_contract_key='ledger_occurrence_shared_confirmation_v1' "
       f"AND work_state='open'")=="1",
       "Current-schema fixture failed to establish existing source-compliant Event Work")
    check(scalar(args.db_url,
       f"SELECT count(*) FROM atlas.work_allocations WHERE work_item_id='{work}'::uuid")=="0",
       "Existing shared checklist does not imply a worker assignment")
    check(scalar(args.db_url,
       f"SELECT count(*) FROM atlas.work_execution_results WHERE work_item_id='{work}'::uuid")=="0",
       "Fixture must never fabricate source Result or accepted Done")
    print("PASS original shared Event Work exists only as source-shaped disposable fixture; live create ACL remains DENIED")

    # TEST-ONLY DATA CUSTODY: current-schema dumps are deliberately schema-only;
    # they do not carry production policy ROWS. The exact policy was independently
    # confirmed read-only in Noel production on 2026-11-05. Rehydrate ONLY this
    # source-owned existing policy in disposable PG17; no grants, no new policy
    # decision, no application SQL, and no real Event Work/Result/Done imported.
    policy="ledger_occurrence_shared_confirmation_v1"
    policy_rows=scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_result_contract_policies "
        f"WHERE contract_key='{policy}'")
    check(policy_rows in ("0","1"),"Invalid shared Event policy duplicate count")
    if policy_rows == "0":
        scalar(args.db_url,"""
          INSERT INTO atlas.work_result_contract_policies
            (contract_key,source_domain,acceptance_mode,active,description,metadata)
          VALUES (
            'ledger_occurrence_shared_confirmation_v1',
            'organization','domain_adapter',true,
            'Authorized Ledger collaborator confirms an ordinary Event checklist state; performer not inferred.',
            jsonb_build_object(
              'source','ledger_occurrence_shared_work_v1',
              'workerDayRequired',false,
              'physicalPerformerAsserted',false,
              'responsibleAllocationRequired',false)
          )
        """)
    check(scalar(args.db_url,"""
       SELECT count(*) FROM atlas.work_result_contract_policies
       WHERE contract_key='ledger_occurrence_shared_confirmation_v1'
         AND source_domain='organization'
         AND acceptance_mode='domain_adapter'
         AND active
         AND metadata->>'source'='ledger_occurrence_shared_work_v1'
         AND metadata->>'workerDayRequired'='false'
         AND metadata->>'physicalPerformerAsserted'='false'
         AND metadata->>'responsibleAllocationRequired'='false'
    """)=="1","Shared Event policy must match current existing source")
    print("PASS existing active source policy restored in schema-only disposable fixture")

    action="signed-event-state-confirmed-once-20261105"
    mark=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
              p_occurrence_id=OCC,p_work_item_id=work,
              p_source_action_id=action)
    denied(api,key,outsider,mark_fn,mark,
           "unconnected signed outsider cannot confirm exact Event Work")
    denied(api,key,member,mark_fn,{**mark,"p_occurrence_id":OTHER},
           "other canonical Event must not control original Work")
    denied(api,key,member,mark_fn,mark,
           "native Ledger seat alone does not disclose private Event identity")
    # The canonical Event scheduling oracle revoked its old signed governor
    # session after restoring the root seat. A NEW genuine GoTrue login is
    # necessary; reusing its revoked bearer would falsely test authorization.
    root,root_claims=schedule.signed_session(
        api,key,"atlas-write-root@example.invalid")
    check(root_claims.get("sub")==schedule.ROOT and root_claims.get("session_id"),
          "Genuine source-governing Person reauthentication required")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM auth.sessions "
        f"WHERE id='{root_claims['session_id']}'::uuid "
        f"AND user_id='{schedule.ROOT}'::uuid")=="1",
        "Governor must have a new valid signed session")
    recorded=permitted(api,key,root,mark_fn,mark)
    result_id=qid(recorded.get("resultId"))
    receipt_id=qid(recorded.get("acceptanceId"))
    event_id=qid(recorded.get("eventId"))
    check(recorded.get("workState")=="completed"
       and recorded.get("alreadyDone") is False
       and recorded.get("idempotent") is False
       and recorded.get("physicalPerformerAsserted") is False
       and recorded.get("personalPerformanceNotClaimed") is True
       and recorded.get("markedByPersonId")==schedule.ROOT_PERSON
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
         AND result.reported_by_user_id='{schedule.ROOT}'::uuid
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
         AND actor_user_id='{schedule.ROOT}'::uuid
         AND evidence_refs->>'personalPerformanceNotClaimed'='true'
     """)=="1","Must have exactly one source-backed authoritative transition")
    print("PASS signed governing Person marked exact shared Event state with one accepted Result and one non-performance Done")

    again=permitted(api,key,root,mark_fn,mark)
    check(again.get("idempotent") is True and again.get("eventId")==event_id
          and again.get("resultId")==result_id
          and again.get("markedByPersonId")==schedule.ROOT_PERSON
          and again.get("physicalPerformerAsserted") is False,
          "Same signed action replay must preserve first actor and same one Done")
    second=permitted(api,key,root,mark_fn,
        {**mark,"p_source_action_id":"distinct-event-action-after-done-20261105"})
    check(second.get("alreadyDone") is True
          and second.get("newTransitionApplied") is False
          and second.get("markedByPersonId") is None
          and second.get("historicalRecordedCompletion") is False
          and second.get("eventId")==event_id,
          "Distinct action after Done must not adopt prior completion as new physical actor")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_execution_results WHERE work_item_id='{work}'::uuid")=="1",
        "Second action or replay fabricated a new original Result")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_lifecycle_events_v1 "
        f"WHERE work_item_id='{work}'::uuid AND event_kind='work_transition_applied'")=="1",
        "Second action or replay caused duplicate immutable Done")
    print("PASS exact action replay and distinct action leave one Done and one original Result")

    # The exact root-governing Person's Ledger participation can be withdrawn.
    scalar(args.db_url,
        f"UPDATE ledger.seats SET seat_state='ended',ended_at=now() "
        f"WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{schedule.ROOT_PERSON}'::uuid "
        "AND seat_state='active'")
    denied(api,key,root,mark_fn,mark,
           "revoked governor Ledger seat must close even prior signed Event action")
    check(scalar(args.db_url,
        f"SELECT count(*) FROM atlas.work_lifecycle_events_v1 "
        f"WHERE work_item_id='{work}'::uuid AND event_kind='work_transition_applied'")=="1",
        "Permission revocation must preserve only original Done")
    check(scalar(args.db_url,
        f"SELECT work_state FROM atlas.work_items WHERE id='{work}'::uuid")=="completed",
        "Revoking a connection cannot erase prior historical Work state")
    Path(args.output).write_text(
       "PASS independently signed root-governor *preexisting* shared Event checklist Work Done, state-only Result, "
       "one universal Done, legacy receipt, two replay modes, member-without-event-disclosure/outsider/wrong Event/revoked denials\n"
       "BLOCKED: native signed Person Event creation and ordinary Person Event identity disclosure by current ACL/source. Signed root-governor-only completion is not broad Event authorization. NOT PROVEN: live Event UI, historical cancellation, production, concurrent sessions\n",
       encoding="utf-8")
    print("PASS signed shared Event checklist completion, same-action replay and current permission withdrawal")

if __name__=="__main__":
    main()

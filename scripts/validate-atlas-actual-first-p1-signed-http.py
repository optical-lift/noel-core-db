#!/usr/bin/env python3
"""HELD P1 signed worker Activity -> assigned original -> typed care Result.

Entry is an explicit --p1-recognition-proof hook AFTER the existing C1
governor issues one genuine original, BEFORE the C1 direct-care Result calls.
Uses four real local GoTrue bearer sessions. All data is synthetic on a
fresh, operator-verified disposable PostgreSQL/GoTrue/PostgREST clone ONLY.
No production, retained clone, CI workflow, or fixture credentials.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from zoneinfo import ZoneInfo


def prove(db, api, key, tokens, work, *, signed_source, rpc, sql, literal,
          check, farm_id, state_id):
    owner, worker, outsider = tokens["owner"], tokens["worker"], tokens["outsider"]
    user_worker = "e5200000-0000-4000-8000-000000000002"
    person_worker = "e5200000-0000-4000-8000-000000000102"
    p1_rpc = "recognize_assigned_care_activity_self_api_v1"
    work_literal = literal(work) + "::uuid"

    def number(query):
        return int(sql(db, query))

    def count(table, extra):
        return number("select count(*) from " + table + " where " + extra)

    def deny(token, activity, target, kind, condition, *, code="42501"):
        status, payload = rpc(api, key, token, p1_rpc, dict(
            p_activity_log_id=activity, p_work_item_id=target,
            p_actual_kind=kind, p_condition_after=condition))
        allowed = (409,) if code == "23505" else ((400, 403) if token is not None else (401, 403))
        check(status in allowed
              and isinstance(payload, dict) and payload.get("code")==code,
              "P1 signed denial missing or replaced by an RPC error: " +
              str(status) + " " + str(payload)[:400])

    def manual_log(label, sentence):
        # This exact existing private writer is invoked ONLY by the isolated
        # clone operator with the genuine GoTrue JWT/session, not by a forged
        # SQL role. It is not represented as an available public log RPC.
        event = (
            "(SELECT to_jsonb(t) FROM atlas.record_worker_activity_log_v1("
            + literal(farm_id) + "::uuid,"
            + "(now() AT TIME ZONE 'America/Chicago')::date,"
            + literal(sentence) + "::text,"
            + literal("p1-signed-disposable-" + label) + "::text,"
            + "NULL::uuid,NULL::timestamptz,NULL::timestamptz,NULL::text"
            + ") AS t)"
        )
        result = signed_source(db, worker, event)
        check(result.get("replayed") is False and result.get("field_log_id"),
              "First-party manual Activity was not established by worker")
        return result["field_log_id"]

    expected_signature=(
        "public.recognize_assigned_care_activity_self_api_v1("
        "uuid,uuid,text,text)")
    check(sql(db,"select to_regprocedure("+literal(expected_signature)+") is not null")=="t",
          "P1 public RPC absent from the disposable clone")
    check(sql(db,
          "select has_function_privilege('authenticated',"
          "to_regprocedure("+literal(expected_signature)+"),'EXECUTE')")=="t",
          "P1 signed public RPC has no authenticated permission")

    baseline = {
        "work": count("atlas.work_items", "source_object_id="+literal(state_id)+"::uuid"),
        "results": count("atlas.work_execution_results", "work_item_id="+work_literal),
        "acceptances": count("atlas.work_result_acceptances", "work_item_id="+work_literal),
        "links": number("select count(*) from atlas.assigned_care_activity_recognition_links_v1"),
        "clock": count("atlas.work_execution_plans", "work_item_id="+work_literal),
    }
    check(baseline["work"]==1 and baseline["results"]==0 and
          baseline["acceptances"]==0 and baseline["links"]==0,
          "Signed P1 must start with one already-assigned open original and zero Actuals")
    check(count("atlas.work_items",
          "id="+work_literal+" and work_state='open'"
          " and source_object_type='rhythm_state'"
          " and result_contract_key='continuing_care_actual_v1'"
          " and metadata->>'sourceContract'='continuing_original_work_v1'"
          " and not (metadata ? 'sourceStandingCampaignId')")==1,
          "P1 original is absent, campaign-linked, or not a qualifying care Work")
    check(count("atlas.work_allocations",
          "work_item_id="+work_literal
          +" and assignee_canonical_person_id="+literal(person_worker)+"::uuid"
          +" and allocation_role='responsible' and state in ('active','completed')"
          +" and establishment_basis_kind in ("
          +"'person_connection_receiver_uptake','delegated_under_standing_scope',"
          +"'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')")==1,
          "P1 worker has no exact prior accepted responsible allocation")

    deny(outsider, "a1100000-0000-4000-8000-000000000001",
         work, "weeded_full", "clear")
    check(count("atlas.work_execution_results","work_item_id="+work_literal)==0,
          "Outsider preflight mutated Result")

    activity=manual_log(
        "positive", "Weeded the synthetic Bed 3 row and observed it clear.")
    activity_lit=literal(activity)+"::uuid"
    check(count("atlas.field_logs",
          "id="+activity_lit+" and source='worker_manual_log'"
          " and actor_user_id="+literal(user_worker)+"::uuid"
          " and actor_membership_id is not null"
          " and retracted_at is null")==1,
          "Worker Activity does not belong to the signed first-party source")

    # A real unrelated original cannot acquire a care Result just because
    # the recipient knows its Work ID. A forged/missing Work is also denied.
    deny(worker, activity, "e5200000-0000-4000-8000-000000000b10",
         "weeded_full", "clear")
    deny(worker, activity, "00000000-0000-4000-8000-000000000091",
         "weeded_full", "clear")
    deny(owner, activity, work, "weeded_full", "clear")
    deny(outsider, activity, work, "weeded_full", "clear")
    deny(worker, activity, work, "weeded_full", "heavy", code="22023")
    check(count("atlas.work_execution_results","work_item_id="+work_literal)==0,
          "Wrong Work/actor/condition created an Actual")

    def recognize():
        return rpc(api, key, worker, p1_rpc, dict(
            p_activity_log_id=activity, p_work_item_id=work,
            p_actual_kind="weeded_full", p_condition_after="clear"))

    # The first two legitimate requests deliberately race for one Activity.
    # Source row FOR UPDATE must serialize and preserve one accepted Result.
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(recognize) for _ in range(2)]
        results=[f.result() for f in futures]
    receipts=[]
    for status, payload in results:
        check(status==200 and isinstance(payload,dict) and payload.get("ok") is True,
              "Simultaneous P1 signed recognition was not accepted: "
              +str(status)+" "+str(payload)[:400])
        receipts.append(payload)
    a,b=receipts
    for value in receipts:
        check(value.get("contractVersion")=="assigned_care_activity_recognition_v1"
              and value.get("activityLogId")==activity
              and value.get("workItemId")==work
              and value.get("workState")=="completed"
              and value.get("recognizedActualKind")=="weeded_full"
              and value.get("recognizedConditionAfter")=="clear"
              and value.get("noNewWorkCreated") is True
              and value.get("noClockAdmission") is True
              and value.get("nextCampaignAuthorized") is False
              and value.get("retrospectiveOriginalCreated") is False,
              "P1 recognition returned incorrect source/Result/continuation contract")
    check(a.get("workResultId")==b.get("workResultId")
          and a.get("recognitionLinkId")==b.get("recognitionLinkId")
          and sorted([a.get("idempotent"),b.get("idempotent")])==[False,True],
          "P1 concurrent recognition produced non-idempotent or forked Result")

    replay_status,replay=recognize()
    check(replay_status==200 and replay.get("idempotent") is True
          and replay.get("workResultId")==a["workResultId"]
          and replay.get("recognitionLinkId")==a["recognitionLinkId"],
          "Sequential P1 replay was not exactly idempotent")
    deny(worker, activity, work, "weeded_partial", "row_readable",
         code="23505")
    check(count("atlas.work_execution_results","work_item_id="+work_literal)==1
          and count("atlas.work_result_acceptances","work_item_id="+work_literal)==1
          and count("atlas.assigned_care_activity_recognition_links_v1",
                    "activity_log_id="+activity_lit+" and work_item_id="+work_literal
                    +" and execution_result_id="+literal(a["workResultId"])+"::uuid"
                    +" and actor_user_id="+literal(user_worker)+"::uuid"
                    +" and actor_person_id="+literal(person_worker)+"::uuid")==1
          and count("atlas.work_lifecycle_events_v1",
                    "work_item_id="+work_literal
                    +" and event_kind='work_transition_applied'")==1
          and count("atlas.rhythm_satisfactions",
                    "rhythm_state_id="+literal(state_id)+"::uuid"
                    +" and satisfaction_kind='full'")==1,
          "P1 did not establish exactly one source-qualified Actual, link and Done")
    check(count("atlas.work_items","source_object_id="+literal(state_id)+"::uuid")
          ==baseline["work"]
          and count("atlas.work_execution_plans","work_item_id="+work_literal)
          ==baseline["clock"],
          "P1 minted a new Work or silently admitted Clock scheduling")

    retracted=manual_log(
        "withdrawn", "Started another synthetic inspection, then withdrew the testimony.")
    retract_result=signed_source(
        db,worker,
        "pg_catalog.jsonb_build_object('ok',"
        "atlas.retract_worker_activity_log_v1("+literal(retracted)+"::uuid))")
    check(retract_result.get("ok") is True,"Signed worker retraction did not persist")
    deny(worker,retracted,work,"weeded_full","clear")
    check(count("atlas.work_execution_results","work_item_id="+work_literal)==1,
          "Withdrawn Activity created another Result")

    # Deliberately simulate a revocation ONLY in disposable fixture data; the
    # bearer remains signed, and its *current* farm membership must now deny.
    sql(db,"update atlas.farm_memberships set active=false where user_id="
        +literal(user_worker)+"::uuid and farm_id="
        +literal(farm_id)+"::uuid")
    deny(worker,activity,work,"weeded_full","clear")
    check(count("atlas.work_execution_results","work_item_id="+work_literal)==1,
          "Revoked farm membership replay modified original Actual")

    print("PASS P1 genuine signed worker manual Activity -> one assigned original -> typed physical Result")
    print("PASS P1 real bearer concurrent first recognition, exact replay, wrong actor/Work, withdrawn and revoked denials")
    print("PASS P1 one Result/acceptance/link/Done, no new Work or Clock admission")
    return ("PASS isolated P1 genuine signed manual Activity, assigned original, "
            "typed Actual, concurrent replay and negative source proof.\n"
            "NOT PROVEN: production, full P2-P5, general Event/Household, "
            "Atlas UI or source-release authority.\n")

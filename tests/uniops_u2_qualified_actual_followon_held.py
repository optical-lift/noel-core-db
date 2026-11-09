#!/usr/bin/env python3
"""HELD UNI-OPS U2 -> U4 typed Actual probe on a disposable LOCAL clone only.

Optional extension to the exact accepted-first U2 signed test. It exercises the
already-authored, source-guarded care Actual API, not P1 manual Activity
recognition. Source P1 currently forbids campaign-tagged originals and is NOT
replaced, weakened, or declared accepted by this probe.

Test-only: no source SQL, API grants, live Person, production or deployment.
"""
import re
from uuid import UUID

ORG = "e5200000-0000-4000-8000-000000000801"
LEDGER = "e5200000-0000-4000-8000-000000000401"
STATE = "e5200000-0000-4000-8000-000000000d05"
WORKER_PERSON = "e5200000-0000-4000-8000-000000000102"
ACTION = "e5200000-0000-4000-8000-000000000e13"
ACTUAL_RPC = "record_continuing_care_actual_self_api_v1"

# These are exact source-authored denial classes; no JWT, SQL, actor IDs,
# messages returned by PostgREST or private traceback ever leave this probe.
# Never accept a dynamic failure reason as an output class.
U4_DENIAL_CLASSES = {
    "U4 probe requires a disposable loopback PG": "local_only_gate",
    "U4 requires the exact existing canonical Work": "original_work_id_gate",
    "U4 requires independent signed actor sessions": "signed_actor_sessions_gate",
    "U4 internal table reference changed": "source_table_name_gate",
    "U4 source-authenticated physical Actual RPC is NOT in clone": "public_actual_signature_gate",
    "U4 authenticated source writer has no exact RPC permission": "public_actual_execute_gate",
    "U4 requires one actual accepted-first, campaign-provenant original": "campaign_original_gate",
    "U4 requires original Work accepted by the actual canonical Person": "responsible_person_gate",
    "U4 requires current native Ledger relevance": "native_ledger_gate",
    "U4 requires a genuine original subject link": "physical_subject_gate",
    "U4 must start before any original Result or acceptance": "pre_result_empty_gate",
    "U4 nonrecipient unexpectedly performed exact original Work": "nonrecipient_permission_gate",
    "U4 mismatched claimed physical condition was not rejected": "invalid_condition_gate",
    "U4 negative cases changed the physical Result": "negative_result_mutation_gate",
    "U4 signed first physical Result/one Done failed; hold source cutover": "signed_result_done_receipt_gate",
    "U4 physical Result and domain acceptance are not exact originals": "qualified_result_acceptance_gate",
    "U4 qualified Result did not create one canonical terminal transition": "one_terminal_transition_gate",
    "U4 signed retry produced a second Result or changed its identity": "idempotent_replay_gate",
    "U4 Result/Done produced an unauthorized successor, task, offer or plan": "zero_successor_gate",
    "U4 duplicate execution after replay": "single_result_after_replay_gate",
}

def require(ok, reason):
    if not ok:
        print("U4_SIGNED_FAILURE_GATE="+U4_DENIAL_CLASSES.get(reason,"unclassified_probe_assertion"),flush=True)
        raise AssertionError(reason)


def local_only(db_url):
    return bool(re.fullmatch(
        r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
        db_url or ""))

def valid_uuid(value):
    try:
        return str(UUID(str(value))) == str(value)
    except (TypeError, ValueError, AttributeError):
        return False

def accepted_receipt(receipt, work):
    return (
        isinstance(receipt, dict)
        and receipt.get("ok") is True
        and receipt.get("workItemId") == work
        and receipt.get("physicalActualContractVersion") == "continuing_care_actual_v1"
        and receipt.get("workState") == "completed"
        and receipt.get("noNewWorkCreated") is True
        and receipt.get("noClockAdmission") is True
        and valid_uuid(receipt.get("workResultId"))
    )

def prove(db_url, api, anon_key, tokens, work, *, sql, rpc):
    """Call only after actual signed U2 offer/acceptance/finalization.

    sql(db_url, query) is the trusted disposable local psql helper.
    rpc(api, key, token, rpc_name, args) is the existing GoTrue/REST helper.
    The governor's and worker's tokens must have been signed independently by
    the parent U2 test; neither the SQL fixture nor this function signs an actor.
    No SQL mutation is performed by this test helper itself.
    """
    print("U4_SIGNED_PROBE_ENTERED=yes",flush=True)
    require(local_only(db_url), "U4 probe requires a disposable loopback PG")
    require(valid_uuid(work), "U4 requires the exact existing canonical Work")
    require(isinstance(tokens, dict)
            and all(isinstance(tokens.get(k), str) and tokens[k]
                    for k in ("owner", "worker", "outsider")),
            "U4 requires independent signed actor sessions")
    work_ref = "'" + work + "'::uuid"

    def count(table, condition="true"):
        require(bool(re.fullmatch(r"[a-z_]+[.][a-z_]+", table)),
                "U4 internal table reference changed")
        return int(sql(db_url, "select count(*) from "+table+" where "+condition))

    signature = (
        "public.record_continuing_care_actual_self_api_v1"
        "(uuid,uuid,text,text,integer,text,date)"
    )
    require(sql(db_url,
                "select to_regprocedure('"+signature+"') is not null") == "t",
            "U4 source-authenticated physical Actual RPC is NOT in clone")
    require(sql(db_url,
                "select has_function_privilege('authenticated',"
                "to_regprocedure('"+signature+"'),'EXECUTE')") == "t",
            "U4 authenticated source writer has no exact RPC permission")

    original = (
        "id="+work_ref+
        " and organization_id='"+ORG+"'::uuid"
        " and source_object_type='rhythm_state'"
        " and source_object_id='"+STATE+"'::uuid"
        " and work_state='open'"
        " and result_contract_key='continuing_care_actual_v1'"
        " and metadata->>'sourceContract'='continuing_original_work_v1'"
        " and metadata ? 'sourceStandingCampaignId'"
        " and metadata->>'sourceAdmissionMode'='owner_standing_visit_v1'"
    )
    require(count("atlas.work_items",original)==1,
            "U4 requires one actual accepted-first, campaign-provenant original")
    require(count("atlas.work_allocations",
                  "work_item_id="+work_ref+
                  " and assignee_canonical_person_id='"+WORKER_PERSON+"'::uuid"
                  " and allocation_role='responsible' and state='active'")==1,
            "U4 requires original Work accepted by the actual canonical Person")
    require(count("atlas.company_work_native_ledger_relevance",
                  "work_item_id="+work_ref+
                  " and ledger_id='"+LEDGER+"'::uuid"
                  " and attribution_state='active'")==1,
            "U4 requires current native Ledger relevance")
    require(count("atlas.work_item_context_links",
                  "work_item_id="+work_ref+
                  " and subject_domain='spatial' and subject_kind='growing_object'"
                  " and subject_id='e5200000-0000-4000-8000-000000000d01'::uuid"
                  " and relation_kind='acts_on'")==1,
            "U4 requires a genuine original subject link")
    require(count("atlas.work_execution_results","work_item_id="+work_ref)==0
            and count("atlas.work_result_acceptances","work_item_id="+work_ref)==0,
            "U4 must start before any original Result or acceptance")

    baseline = {
        "originals":count("atlas.work_items","organization_id='"+ORG+"'::uuid"),
        "tasks":count("atlas.tasks","organization_id='"+ORG+"'::uuid"),
        "offers":count("atlas.governed_prework_candidate_offers_v1"),
        "plans":count("atlas.work_execution_plans",
                      "work_item_id="+work_ref),
    }
    payload = {
        "p_work_item_id":work,
        "p_action_id":ACTION,
        "p_actual_kind":"mowed_full",
        "p_condition_after":"resting",
        "p_minutes":15,
        "p_note":"Completed the fictional mowing area.",
        "p_recheck_on":None,
    }

    def call(actor, args=payload):
        return rpc(api,anon_key,tokens[actor],ACTUAL_RPC,args)

    # Each negative uses the SAME genuine source-checked RPC; never grant
    # outsider or owner performer's rights or invent a test-only Work writer.
    for actor in ("outsider","owner"):
        status, response = call(actor)
        require(status in (401,403) and isinstance(response,dict)
                and response.get("code")=="42501",
                "U4 nonrecipient unexpectedly performed exact original Work")
    invalid = dict(payload,p_condition_after="too_wet")
    status, response = call("worker",invalid)
    require(status==400 and isinstance(response,dict)
            and response.get("code")=="22023",
            "U4 mismatched claimed physical condition was not rejected")
    require(count("atlas.work_execution_results","work_item_id="+work_ref)==0,
            "U4 negative cases changed the physical Result")

    status, response = call("worker")
    require(status==200 and accepted_receipt(response,work),
            "U4 signed first physical Result/one Done failed; hold source cutover")
    result_ref = "'" + response["workResultId"] + "'::uuid"
    require(count("atlas.work_execution_results",
                  "id="+result_ref+" and work_item_id="+work_ref
                  +" and result_contract_key='continuing_care_actual_v1'")==1
            and count("atlas.work_result_acceptances",
                      "work_item_id="+work_ref
                      +" and execution_result_id="+result_ref
                      +" and decision='accepted'"
                      " and acceptance_kind='source_qualified_physical_actual'")==1,
            "U4 physical Result and domain acceptance are not exact originals")
    require(count("atlas.work_items",
                  "id="+work_ref+" and work_state='completed'")==1
            and count("atlas.work_lifecycle_events_v1",
                      "work_item_id="+work_ref+
                      " and event_kind='work_transition_applied'")==1,
            "U4 qualified Result did not create one canonical terminal transition")

    status, replay = call("worker")
    require(status==200 and accepted_receipt(replay,work)
            and replay["workResultId"]==response["workResultId"]
            and replay.get("idempotent") is True,
            "U4 signed retry produced a second Result or changed its identity")

    require(count("atlas.work_items",
                  "organization_id='"+ORG+"'::uuid")==baseline["originals"]
            and count("atlas.tasks",
                      "organization_id='"+ORG+"'::uuid")==baseline["tasks"]
            and count("atlas.governed_prework_candidate_offers_v1")==baseline["offers"]
            and count("atlas.work_execution_plans",
                      "work_item_id="+work_ref)==baseline["plans"],
            "U4 Result/Done produced an unauthorized successor, task, offer or plan")
    require(count("atlas.work_execution_results","work_item_id="+work_ref)==1
            and count("atlas.work_result_acceptances","work_item_id="+work_ref)==1,
            "U4 duplicate execution after replay")
    print("PASS UNI-OPS accepted-first original to independently signed typed Actual, Result and one Done")
    print("PASS UNI-OPS zero new original/task/offer/plan; outsider, owner and invalid-condition denied")
    return True

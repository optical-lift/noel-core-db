#!/usr/bin/env python3
"""Held signed LOCAL clone proof; never runs against production.
Use the existing trusted C1 synthetic fixture in a fresh disposable PG17 clone.
Run after applying candidate and postconditions. No new runner or credentials.
"""
import argparse
import importlib.util
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "native_intake_existing_fixture", ROOT / "scripts/validate-atlas-work-prerequisite-signed-http.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1 = base.c1
ORG, LEDGER, OTHER_LEDGER = c1.ORG, c1.LEDGER_A, c1.LEDGER_B
OWNER = "e5200000-0000-4000-8000-000000000101"
WORKER = "e5200000-0000-4000-8000-000000000102"
OUTSIDER = "e5200000-0000-4000-8000-000000000103"
PREFLIGHT = "work_focus_owner_reassignment_preflight_self_api_v1"
WRITE = "work_focus_owner_reassign_direct_self_api_v1"
REPORT = "report_connected_person_company_work_self_api_v1"
def check(cond, message):
    base.check(cond, message)
def ident():
    return str(uuid.uuid4())
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    opts = parser.parse_args()
    db = opts.db_url
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", db)),
          "Refusing nonlocal PostgreSQL")
    api, key = c1.local_status()
    check(bool(re.match(r"^http://127[.]0[.]0[.]1:[0-9]+(?:/|$)", api)),
          "Refusing nonlocal signed HTTP")
    sessions = {}
    for name, uid in base.setup_auth(db):
        token, claims = c1.sign_in(api, key, name)
        check(claims.get("sub") == uid and claims.get("session_id"), "Bad signed session")
        check(base.sql(db, f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid") == "1",
              "No persisted signed session")
        sessions[name] = (token, claims)
    root, worker = sessions["owner"][0], sessions["worker"][0]
    def ok(token, rpc, args):
        return base.allow(api, key, token, rpc, args)
    def denied(token, rpc, args, codes=("42501",), label="denial"):
        status, obj = base.rpc(api, key, token, rpc, args)
        check(status >= 400 and status != 404 and isinstance(obj, dict)
              and (obj.get("code") in codes or (token is None and status == 401)),
              f"{label}: expected source denial, got {status} {str(obj)[:180]}")
    def count(query):
        return base.sql(db, query)
    def submit():
        response = ok(root, "submit_ledger_work_self_api_v1", {
            "p_ledger_id": LEDGER, "p_title": "Synthetic nonfarm intake responsibility",
            "p_attention_date_proposal": None, "p_source_action_id": ident()})
        check(response.get("assignedToPerson") is False and response.get("personDayPlacementEstablished") is False,
              "Initial custody must be unassigned and unscheduled")
        return response
    def accept(receipt):
        reply = ok(root, "review_ledger_work_intake_root_self_api_v2", {
            "p_intake_id": receipt["intakeId"], "p_decision": "accepted_for_ledger",
            "p_expected_revision": 0, "p_reason": "Synthetic root acceptance",
            "p_title": "Synthetic nonfarm intake responsibility", "p_instructions": None})
        check(reply.get("workItemId") == receipt["workItemId"] and reply.get("sameOriginalWork") is True,
              "Root review must retain original")
    def context(work, ledger=LEDGER):
        return dict(p_organization_id=ORG, p_ledger_id=ledger, p_work_item_id=work)
    def command(work, target, old=None, ledger=LEDGER):
        return dict(context(work, ledger), p_expected_allocation_id=old,
                    p_target_person_id=target, p_reason="Synthetic responsibility decision",
                    p_source_action_id=ident())
    def mywork(token, work):
        reply = ok(token, "connected_person_my_work_self_api_v1", {
            "p_limit": 100, "p_after_allocation_id": None})
        return [item for item in reply["items"] if item.get("workItemId") == work]
    def report(work, kind="completed"):
        return dict(p_work_item_id=work, p_result_kind=kind,
                    p_idempotency_key=ident(), p_payload={"note":"Synthetic actual result"})
    original_count = int(count(f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid"))
    first = submit(); work = first["workItemId"]
    first_command = command(work, OWNER)
    denied(root, PREFLIGHT, context(work), label="unaccepted intake preflight")
    denied(root, WRITE, first_command, label="unaccepted intake write")
    accept(first)
    initial = ok(root, PREFLIGHT, context(work))
    check(initial.get("canAssign") is True and initial.get("currentAllocationId") is None,
          "Accepted original should admit initial responsibility")
    for name in ("worker","outsider","no-seat"):
        tok = sessions[name][0]
        denied(tok, PREFLIGHT, context(work), label=name + " preflight")
        denied(tok, WRITE, first_command, label=name + " assignment")
    denied(None, WRITE, first_command, label="anonymous assignment")
    denied(root, WRITE, command(work, OUTSIDER), label="disconnected target")
    denied(root, WRITE, command(work, OWNER, ledger=OTHER_LEDGER), label="wrong Ledger")
    first_result = ok(root, WRITE, first_command)
    a = first_result["newAllocationId"]
    check(first_result.get("currentResponsiblePersonId") == OWNER and first_result.get("workItemId") == work
          and first_result.get("newWorkCreated") is False, "Self assignment exact receipt")
    check(ok(root, WRITE, first_command).get("newAllocationId") == a, "Retry new allocation")
    denied(root, WRITE, dict(first_command,p_reason="Altered same action"), ("23505",), "changed retry")
    check(len(mywork(root, work)) == 1 and not mywork(worker, work), "Self My Work readback")
    second_command = command(work, WORKER, a)
    b = ok(root, WRITE, second_command)["newAllocationId"]
    check(len(mywork(worker, work)) == 1 and not mywork(root, work), "Transfer to connected Person")
    denied(root, WRITE, command(work, OWNER, a), ("40001",), "stale original allocation")
    back = command(work, OWNER, b)
    c = ok(root, WRITE, back)["newAllocationId"]
    check(c not in (a,b) and len(mywork(root, work)) == 1 and not mywork(worker, work), "Transfer back to self")
    check(ok(root, WRITE, back)["newAllocationId"] == c, "Transfer replay")
    check(count(f"select count(*) from atlas.work_allocations where work_item_id='{work}'::uuid and state='released'") == "2",
          "Prior responsibility history missing")
    check(count(f"select count(*) from atlas.work_allocations where work_item_id='{work}'::uuid and state='active' and allocation_role='responsible'") == "1",
          "Only one active original responsibility")
    check(count(f"select count(*) from atlas.work_execution_plans where work_item_id='{work}'::uuid") == "0",
          "Unscheduled responsibility invented a plan")
    denied(worker, REPORT, report(work), label="former responsible Person cannot report")
    partial = ok(root, REPORT, report(work,"partial"))
    check(partial.get("workItemId") == work and partial.get("workState") == "open", "Partial wrong original")
    denied(root, WRITE, command(work, WORKER, c), ("23514",), "prior Result transfer must hold")
    done = report(work)
    result = ok(root, REPORT, done)
    check(result.get("workItemId") == work and result.get("workState") == "completed" and result.get("resultId"),
          "Own Done did not close exact original")
    replay = ok(root, REPORT, done)
    check(replay.get("resultId") == result.get("resultId"), "Result replay duplicated")
    check(not mywork(root, work), "Completed original still in active notebook")
    check(count(f"select count(*) from atlas.work_execution_results where work_item_id='{work}'::uuid") == "2",
          "One partial and one completed Result required")
    check(count(f"select count(*) from atlas.work_result_acceptances where work_item_id='{work}'::uuid and decision='accepted'") == "1",
          "One completion acceptance required")
    second = submit(); accept(second)
    new_work = second["workItemId"]
    fresh = command(new_work, OWNER)
    base.sql(db, f"update atlas.principal_ledger_authorities set status='ended',ended_at=now() where id='{c1.ROOT_AUTHORITY}'::uuid")
    denied(root, WRITE, fresh, label="revoked root")
    base.sql(db, f"update atlas.principal_ledger_authorities set status='active',ended_at=null where id='{c1.ROOT_AUTHORITY}'::uuid")
    base.sql(db, f"update ledger.seats set seat_state='ended',ended_at=now() where id='{c1.ROOT_SEAT}'::uuid")
    denied(root, WRITE, fresh, label="revoked seat")
    base.sql(db, f"update ledger.seats set seat_state='active',ended_at=null where id='{c1.ROOT_SEAT}'::uuid")
    base.sql(db, f"delete from auth.sessions where id='{sessions['owner'][1]['session_id']}'::uuid")
    denied(root, WRITE, fresh, label="revoked session")
    check(int(count(f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")) == original_count+2,
          "Only the two explicit synthetic submissions may create originals")
    Path(opts.output).parent.mkdir(parents=True, exist_ok=True)
    Path(opts.output).write_text("PASS native intake signed self-assignment, transfer, replay, denial, own Result and original identity\n")
if __name__ == "__main__":
    main()

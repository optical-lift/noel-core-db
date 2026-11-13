#!/usr/bin/env python3
"""Genuine distinct local GoTrue + PostgREST W07 comment proof.

DISPOSABLE production-schema clone ONLY. Requires the existing synthetic C1
fixture, synthetic native-Work allocation fixture, and held W07 candidate SQL.
No production URL, real Person, email, notification, or actual Work creation.
A missing RPC (404/PGRST202) is a FAILURE, not permission denial.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "w07_existing_signed_helper",
    HERE / "validate-atlas-work-prerequisite-signed-http.py",
)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1 = base.c1
ORG = c1.ORG
LEDGER = c1.LEDGER_A
OTHER_LEDGER = c1.LEDGER_B
WORK = "e5200000-0000-4000-8000-000000000902"
WRONG_WORK = "e5200000-0000-4000-8000-000000000901"
ALLOC = "e5200000-0000-4000-8000-000000000983"
ACTION_OWNER = "e5200000-0000-4000-8000-000000000d01"
ACTION_WORKER = "e5200000-0000-4000-8000-000000000d02"
ACTION_THIRD = "e5200000-0000-4000-8000-000000000d03"
BODY_OWNER = "SYNTH_W07_OWNER_COMMENT_LOCAL_ONLY"
BODY_WORKER = "SYNTH_W07_WORKER_COMMENT_LOCAL_ONLY"
BODY_THIRD = "SYNTH_W07_OWNER_SECOND_LOCAL_ONLY"
READ = "read_native_original_work_comments_self_api_v1"
WRITE = "append_native_original_work_comment_self_api_v1"


def check(value, message):
    base.check(value, message)


def sql(db_url, statement):
    return base.sql(db_url, statement)


def rpc(api, key, token, name, args):
    return base.rpc(api, key, token, name, args)


def permitted(api, key, token, name, args):
    code, packet = rpc(api, key, token, name, args)
    check(code == 200 and isinstance(packet, dict) and packet.get("ok") is True,
          "%s: missing signed source success; HTTP %s (%s)" %
          (name, code, str(packet)[:180]))
    return packet


def forbidden(api, key, token, name, args, description):
    code, packet = rpc(api, key, token, name, args)
    check(code in (401, 403) and isinstance(packet, dict)
          and packet.get("code") == "42501",
          "%s: expected real 42501, NEVER 404/unavailable; got %s, %s" %
          (description, code, str(packet)[:160]))
    check(BODY_OWNER not in json.dumps(packet)
          and BODY_WORKER not in json.dumps(packet),
          description + ": denial leaked a comment")
    print("PASS", description)


def scope(work=WORK, ledger=LEDGER):
    return {"p_organization_id": ORG,
            "p_ledger_id": ledger,
            "p_work_item_id": work}


def write_args(action, body, work=WORK, ledger=LEDGER):
    return {**scope(work, ledger),
            "p_source_action_id": action,
            "p_body": body}


def read_args(work=WORK, ledger=LEDGER, limit=40, after=None):
    return {**scope(work, ledger),
            "p_limit": limit,
            "p_after_recorded_at": after[0] if after else None,
            "p_after_comment_id": after[1] if after else None}


def check_read(packet, expected_ids):
    check(packet.get("contractVersion") == "native_original_work_comments_v1"
          and packet.get("organizationId") == ORG
          and packet.get("ledgerId") == LEDGER
          and packet.get("workItemId") == WORK
          and packet.get("containsWorkResults") is False
          and packet.get("isNotificationInbox") is False
          and packet.get("authorsPreservedInCanonicalSource") is True
          and packet.get("authorIdentityDisclosure") == "self_boolean_only",
          "W07 read changed exact Work contract")
    rows = packet.get("items")
    check(isinstance(rows, list) and isinstance(packet.get("hasMore"), bool),
          "W07 read missing bounded list and cursor")
    check({x.get("commentId") for x in rows} == set(expected_ids)
          and len(rows) == len(expected_ids),
          "W07 signed read lost or duplicated original comment IDs")
    check(all(x.get("workItemId") == WORK and
              isinstance(x.get("authoredBySelf"), bool) and
              x.get("recordedAt") for x in rows),
          "W07 original read must include signed source timestamp / self flag")
    check("authorPersonId" not in json.dumps(rows)
          and "author_person_id" not in json.dumps(rows),
          "W07 reader leaked another Person's canonical identity")
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
        args.db_url)),
        "W07 REFUSES nonlocal database")
    api, key = c1.local_status()
    check(bool(re.match(r"^https?://(?:127[.]0[.]0[.]1|localhost):[0-9]+", api)),
          "W07 REFUSES nonlocal REST/GoTrue")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.work_items
        WHERE organization_id='%s'::uuid
        AND id='%s'::uuid AND work_state='open'
    """ % (ORG, WORK)) == "1",
          "Synthetic original Work must exist and be open")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.work_allocations
        WHERE id='%s'::uuid AND work_item_id='%s'::uuid
          AND assignee_canonical_person_id='%s'::uuid
          AND state='active'
          AND establishment_basis_kind='person_connection_receiver_uptake'
    """ % (ALLOC, WORK, c1.WORKER)) == "1",
          "Real synthetic receiver-accepted responsibility required")
    check(sql(args.db_url,
        "SELECT count(*) FROM atlas.native_original_work_comments_v1") == "0",
        "W07 local comments must begin empty")
    work_before = sql(args.db_url, "SELECT count(*) FROM atlas.work_items")
    results_before = sql(args.db_url,
                         "SELECT count(*) FROM atlas.work_execution_results")
    sessions = {}
    for label, expected in base.setup_auth(args.db_url):
        token, claims = c1.sign_in(api, key, label)
        check(claims.get("sub") == expected
              and claims.get("role") == "authenticated"
              and claims.get("session_id"),
              "W07 distinct signed identity failed: " + label)
        check(sql(args.db_url, """
             SELECT count(*) FROM auth.sessions
             WHERE id='%s'::uuid AND user_id='%s'::uuid
        """ % (claims["session_id"], expected)) == "1",
              "W07 live local session record absent: " + label)
        sessions[label] = token
    check(set(sessions) == {"owner", "worker", "outsider", "no-seat"},
          "W07 genuine four-session fixture incomplete")
    print("PASS W07 four distinct signed synthetic Auth sessions")

    owner = sessions["owner"]
    worker = sessions["worker"]
    outsider = sessions["outsider"]
    no_seat = sessions["no-seat"]
    check_read(permitted(api,key,owner,READ,read_args()), [])
    check_read(permitted(api,key,worker,READ,read_args()), [])
    for label,token in [("outsider",outsider),("no seat",no_seat)]:
        forbidden(api,key,token,READ,read_args(),label+" read")
        forbidden(api,key,token,WRITE,write_args(ACTION_OWNER,"unauthorized"),
                  label+" write")
    forbidden(api,key,worker,READ,read_args(WRONG_WORK), "wrong original Work")

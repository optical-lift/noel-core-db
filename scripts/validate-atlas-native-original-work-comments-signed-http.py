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
    forbidden(api,key,worker,WRITE,
              write_args(ACTION_OWNER,"wrong original",WRONG_WORK),
              "worker cannot write unassigned Work")
    forbidden(api,key,owner,READ,read_args(WORK,OTHER_LEDGER),
              "native governor wrong Ledger read")
    forbidden(api,key,owner,WRITE,
              write_args(ACTION_OWNER,"wrong Ledger",WORK,OTHER_LEDGER),
              "native governor wrong Ledger write")
    forbidden(api,key,worker,READ,read_args(WORK,OTHER_LEDGER),
              "worker wrong Ledger read")
    forbidden(api,key,None,READ,read_args(),
              "unsigned anonymous read")
    forbidden(api,key,None,WRITE,write_args(ACTION_OWNER,"anonymous"),
              "unsigned anonymous write")

    owner_receipt=permitted(api,key,owner,WRITE,
                            write_args(ACTION_OWNER,BODY_OWNER))
    check(owner_receipt.get("contractVersion")==
          "native_original_work_comment_write_v1"
          and owner_receipt.get("workItemId")==WORK
          and owner_receipt.get("ledgerId")==LEDGER
          and owner_receipt.get("body")==BODY_OWNER
          and owner_receipt.get("idempotent") is False
          and owner_receipt.get("originalWorkStateUnchanged") is True
          and owner_receipt.get("isWorkResult") is False
          and owner_receipt.get("notificationDelivered") is False,
          "Owner append was not canonical signed ordinary Work comment")
    owner_id=owner_receipt.get("commentId")
    check(owner_id and owner_receipt.get("recordedAt"),
          "Original comment identity and source time missing")

    other_view=permitted(api,key,worker,READ,read_args())
    worker_items=check_read(other_view,[owner_id])
    check(worker_items[0].get("body")==BODY_OWNER
          and worker_items[0].get("authoredBySelf") is False,
          "Responsible worker did not independently read owner's signed ink")

    worker_receipt=permitted(api,key,worker,WRITE,
                             write_args(ACTION_WORKER,BODY_WORKER))
    worker_id=worker_receipt.get("commentId")
    check(worker_id and worker_id!=owner_id
          and worker_receipt.get("body")==BODY_WORKER
          and worker_receipt.get("notificationDelivered") is False,
          "Worker ordinary note created no distinct canonical comment")
    owner_view=permitted(api,key,owner,READ,read_args())
    owner_rows=check_read(owner_view,[owner_id,worker_id])
    check({r.get("body") for r in owner_rows}=={BODY_OWNER,BODY_WORKER}
          and any(r.get("commentId")==worker_id and
                  r.get("authoredBySelf") is False for r in owner_rows),
          "Owner cannot independently read second authorized author's note")
    worker_view=permitted(api,key,worker,READ,read_args())
    check_read(worker_view,[owner_id,worker_id])
    check(any(r.get("commentId")==worker_id and
              r.get("authoredBySelf") is True
              for r in worker_view["items"]),
          "Worker must recognize their own original authored note")

    replay=permitted(api,key,owner,WRITE,
                     write_args(ACTION_OWNER,BODY_OWNER))
    check(replay.get("commentId")==owner_id
          and replay.get("idempotent") is True
          and replay.get("recordedAt")==owner_receipt.get("recordedAt"),
          "Same action retry lost its original signed receipt")
    conflict_status,conflict=rpc(api,key,owner,WRITE,
                   write_args(ACTION_OWNER,"SYNTH_DIFFERENT_BODY"))
    check(conflict_status==409 and isinstance(conflict,dict)
          and conflict.get("code")=="23505",
          "Same action ID attempted silent body overwrite")

    third=permitted(api,key,owner,WRITE,
                    write_args(ACTION_THIRD,BODY_THIRD))
    third_id=third.get("commentId")
    first_page=permitted(api,key,worker,READ,read_args(limit=2))
    check(first_page.get("hasMore") is True
          and first_page.get("nextRecordedAt")
          and first_page.get("nextCommentId"),
          "W07 bounded source-first page missing continuation")
    first_ids={r.get("commentId") for r in first_page["items"]}
    check(len(first_ids)==2, "W07 first page must contain exactly two")
    cursor=(first_page["nextRecordedAt"],first_page["nextCommentId"])
    second_page=permitted(api,key,worker,READ,
                          read_args(limit=2,after=cursor))
    check(second_page.get("hasMore") is False,
          "W07 last page cannot claim an unknown continuation")
    second_ids={r.get("commentId") for r in second_page["items"]}
    check(first_ids.isdisjoint(second_ids)
          and first_ids | second_ids=={owner_id,worker_id,third_id},
          "W07 cursor skipped or duplicated an original comment")

    invalid_status, invalid=rpc(api,key,owner,WRITE,
                                write_args(ACTION_OWNER," "))
    check(invalid_status in (400,422)
          and isinstance(invalid,dict)
          and invalid.get("code")=="22023",
          "Blank body must reject before new Work comment")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.native_original_work_comments_v1
        WHERE organization_id='%s'::uuid
          AND ledger_id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (ORG,LEDGER,WORK))=="3",
          "Three unique signed actions must create only three comments")

    # Revoke the synthetic worker's accepted responsibility. We do NOT
    # impersonate a real account or mutate the user's Production Work.
    sql(args.db_url, """
      UPDATE atlas.work_allocations SET state='released',
        released_at=now(),release_reason='clone:w07-access-withdrawn'
      WHERE id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (ALLOC,WORK))
    forbidden(api,key,worker,READ,read_args(),
              "revoked worker must lose historical note read")
    forbidden(api,key,worker,WRITE,
              write_args(ACTION_WORKER,BODY_WORKER),
              "revoked worker must not recover replay without current read")
    check_read(permitted(api,key,owner,READ,read_args()),
               [owner_id,worker_id,third_id])

    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_items")==
          work_before,"W07 comments manufactured another original Work")
    check(sql(args.db_url,
              "SELECT count(*) FROM atlas.work_execution_results")==
          results_before,"W07 ordinary comments manufactured a Work Result")
    check(sql(args.db_url, """
      SELECT count(*) FROM atlas.work_items
      WHERE id='%s'::uuid AND work_state='open'
    """ % WORK)=="1","W07 comments changed original Work state")
    print("PASS W07 real synthetic GoTrue signed governor/worker readback and "
          "source denial, exact Work/Ledger, immutable action replay, "
          "cursor paging, revocation, no Work/Result/notification")
    Path(args.output).write_text(
      "PASS W07 signed local GoTrue 4 identities, exact Work read/write, "
      "cross-person refresh, original idempotent replay and collision denial, "
      "page cursor, signed revocation, no new Work or Work Result\n",
      encoding="utf-8"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Genuine GoTrue + PostgREST ACCESS-02 My Work proof, DISPOSABLE CLONE ONLY.

Four independently signed synthetic C1 sessions. All DB mutations occur on
127.0.0.1 inside the protected full-schema clone, never production.
"""
import argparse
import json
import re
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("access02_existing_auth",
    HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
check=base.check
sql=base.sql
rpc=base.rpc
allow=base.allow
ORG=base.ORG
LEDGER=base.LEDGER
WORK_A="e5200000-0000-4000-8000-000000000901"
WORK_B="e5200000-0000-4000-8000-000000000902"
ALLOC_A="e5200000-0000-4000-8000-000000000951"
ALLOC_B="e5200000-0000-4000-8000-000000000952"
PERSON="e5200000-0000-4000-8000-000000000102"
OWNER="e5200000-0000-4000-8000-000000000101"
TITLE_A="Clone work: clear walkways"
TITLE_B="Clone work: replacement sprayer arrives"
SECRET_A="Synthetic instructions for Work 901 - Ledger A only."
SECRET_B="Synthetic instructions for Work 902 - Ledger A only."
RPC="connected_person_my_work_self_api_v1"

def args(limit=50, after=None):
    return {"p_limit":limit,"p_after_allocation_id":after}

def mine(api,key,token,limit=50,after=None):
    data=allow(api,key,token,RPC,args(limit,after))
    check(data.get("contractVersion")=="connected_person_my_work_v1" and
          data.get("personId") is not None and
          isinstance(data.get("items"),list) and
          isinstance(data.get("hasMore"),bool),
          "ACCESS-02 current My Work JSONB source contract missing")
    return data

def check_items(page, ids):
    rows=page.get("items",[])
    check([r.get("workItemId") for r in rows]==list(ids),
          "ACCESS-02 unexpected Work page identity: "+repr(
           [r.get("workItemId") for r in rows]))
    check(all(r.get("workRelevanceVerified") is True for r in rows),
          "ACCESS-02 displayed row without verified native Ledger relevance")

def check_no_field_leak(packet):
    wire=json.dumps(packet,separators=(",",":"),sort_keys=True)
    check(WORK_A not in wire and ALLOC_A not in wire
          and TITLE_A not in wire and SECRET_A not in wire,
          "ACCESS-02 withdrawn Work identifier/title/instructions/pagination leaked")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
        "ACCESS-02 forbids nonlocal database URL")
    api,key=c1.local_status()
    check(bool(re.match(r"^https?://(127[.]0[.]0[.]1|localhost):[0-9]+",api)),
          "ACCESS-02 forbids nonlocal GoTrue/REST endpoint")
    check(sql(a.db_url,f"""SELECT count(*) FROM atlas.work_allocations
         WHERE id IN ('{ALLOC_A}'::uuid,'{ALLOC_B}'::uuid)
         AND organization_id='{ORG}'::uuid AND state='active'
         AND assignee_canonical_person_id='{PERSON}'::uuid
         AND establishment_basis->>'nativeLedgerId'='{LEDGER}'""")=="2",
          "ACCESS-02 synthetic direct Work allocations missing")
    check(sql(a.db_url,f"""SELECT count(*) FROM atlas.work_items
      WHERE id IN ('{WORK_A}'::uuid,'{WORK_B}'::uuid)
      AND organization_id='{ORG}'::uuid AND work_state='open'""")=="2",
          "ACCESS-02 two independent synthetic originals missing")
    check(sql(a.db_url,f"""SELECT count(*) FROM atlas.company_work_native_ledger_relevance
      WHERE ledger_id='{LEDGER}'::uuid AND attribution_state='active'
      AND evidence_kind='owner_attested'
      AND work_item_id IN ('{WORK_A}'::uuid,'{WORK_B}'::uuid)""")=="2",
          "ACCESS-02 two independent verified relevance witnesses required")
    before=(sql(a.db_url,"SELECT count(*) FROM atlas.work_items"),
            sql(a.db_url,"SELECT count(*) FROM atlas.work_allocations"))
    sessions={}
    for label,uid in base.setup_auth(a.db_url):
        token,claims=c1.sign_in(api,key,label)
        check(claims.get("sub")==uid
              and claims.get("role")=="authenticated"
              and bool(claims.get("session_id")),
              "ACCESS-02 genuine separate signed "+label+" failed")
        check(sql(a.db_url,f"""SELECT count(*) FROM auth.sessions WHERE
         id='{claims['session_id']}'::uuid AND user_id='{uid}'::uuid""")=="1",
              "ACCESS-02 GoTrue session not persisted: "+label)
        sessions[label]=(token,claims)
    check(len({x[1].get("session_id") for x in sessions.values()})==4,
          "ACCESS-02 requires four genuinely distinct local GoTrue sessions")
    worker=sessions["worker"][0]
    outsider=sessions["outsider"][0]
    no_seat=sessions["no-seat"][0]
    root=sessions["owner"][0]

    # Positive same signed Person and two independent, source-verified Works.
    page=mine(api,key,worker)
    check(page.get("personId")==PERSON,"ACCESS-02 wrong recipient identity")
    check_items(page,[WORK_A,WORK_B])
    check(page.get("hasMore") is False and page.get("nextAllocationId") is None,
          "ACCESS-02 initial page count/cursor mismatch")
    check(page["items"][0].get("title")==TITLE_A and
          page["items"][0].get("instructions")==SECRET_A and
          page["items"][0].get("allocationId")==ALLOC_A and
          page["items"][1].get("title")==TITLE_B and
          page["items"][1].get("instructions")==SECRET_B and
          page["items"][1].get("allocationId")==ALLOC_B,
          "ACCESS-02 positive original title/instruction/assignment not preserved")
    first=mine(api,key,worker,1)
    check_items(first,[WORK_A])
    check(first.get("hasMore") is True and first.get("nextAllocationId")==ALLOC_A,
          "ACCESS-02 positive cursor/count drift")
    second=mine(api,key,worker,1,ALLOC_A)
    check_items(second,[WORK_B])
    check(second.get("hasMore") is False and second.get("nextAllocationId") is None,
          "ACCESS-02 final positive cursor missing")
    print("PASS ACCESS-02 two independent signed eligible Work details and pagination")

    # No other signed Person inherits a colleague's assigned Work; spoofed
    # worker user_metadata root claims are not a permission source.
    for label,token in (("owner",root),("outsider",outsider),
                        ("no-seat",no_seat)):
        response=mine(api,key,token)
        check_items(response,[])
        check_no_field_leak(response)
        check(WORK_B not in json.dumps(response),
              "ACCESS-02 other actor received another Person's original Work")
        print("PASS ACCESS-02 withheld other signed actor:",label)
    code,packet=rpc(api,key,None,RPC,args())
    check(code in (401,403) and isinstance(packet,dict),
          "ACCESS-02 anonymous REST request was not denied")
    print("PASS ACCESS-02 anonymous transport denial")

    # Revoke ONLY native relevance, keeping Work/assignment/seat/subject
    # unchanged. This is deliberately distinct from Work cancellation or Done.
    sql(a.db_url,f"""UPDATE atlas.company_work_native_ledger_relevance
      SET attribution_state='withdrawn',withdrawn_at=now(),
          withdrawn_by_person_id='{OWNER}'::uuid,
          withdrawal_reason='ACCESS-02 synthetic withdrawal, not Work cancellation'
      WHERE work_item_id='{WORK_A}'::uuid
        AND ledger_id='{LEDGER}'::uuid AND attribution_state='active'""")
    check(sql(a.db_url,f"""SELECT count(*) FROM atlas.company_work_native_ledger_relevance
        WHERE work_item_id='{WORK_A}'::uuid AND ledger_id='{LEDGER}'::uuid
        AND attribution_state='withdrawn'""")=="1",
          "ACCESS-02 true native relevance withdrawal missing")

    withheld=mine(api,key,worker)
    check_items(withheld,[WORK_B])
    check_no_field_leak(withheld)
    check(withheld.get("hasMore") is False and
          withheld.get("nextAllocationId") is None,
          "ACCESS-02 withdrawn Work left a count or next-page hint")
    single=mine(api,key,worker,1)
    check_items(single,[WORK_B])
    check_no_field_leak(single)
    check(single.get("hasMore") is False and
          single.get("nextAllocationId") is None,
          "ACCESS-02 withdrawn Work leaked through one-item paging")
    after=mine(api,key,worker,1,ALLOC_B)
    check_items(after,[])
    check_no_field_leak(after)
    check(after.get("hasMore") is False,
          "ACCESS-02 withdrawn Work leaked after allowed cursor")
    check(single["items"][0].get("instructions")==SECRET_B,
          "ACCESS-02 withholding unrelated legitimate Work details")
    check(sql(a.db_url,f"""SELECT count(*) FROM atlas.work_allocations
        WHERE id IN ('{ALLOC_A}'::uuid,'{ALLOC_B}'::uuid)
        AND state='active'""")=="2",
          "ACCESS-02 withdrawal silently released a Work obligation")
    print("PASS ACCESS-02 signed revoked native relevance hides title, details, count and cursor")

    # Relevance evidence is append-only: the released trigger permits only
    # active->withdrawn, never reopening the withdrawn historical row.
    # Re-attest the same fictional native Work by INSERTING a new evidence
    # row. Preserve the old withdrawal and the original Work/allocation.
    sql(a.db_url,f"""INSERT INTO atlas.company_work_native_ledger_relevance
      (organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
       attestation_source_ref,attestation_reason,established_by_person_id)
      VALUES('{ORG}'::uuid,'{WORK_A}'::uuid,'{LEDGER}'::uuid,
        'serves_purpose','owner_attested','clone:access02-reattest-901',
        'Independent synthetic new relevance after immutable withdrawal',
        '{OWNER}'::uuid)""")
    check(sql(a.db_url,f"""SELECT count(*) FROM
         atlas.company_work_native_ledger_relevance
         WHERE ledger_id='{LEDGER}'::uuid AND work_item_id='{WORK_A}'::uuid
           AND attribution_state='withdrawn'""")=="1"
         and sql(a.db_url,f"""SELECT count(*) FROM
         atlas.company_work_native_ledger_relevance
         WHERE ledger_id='{LEDGER}'::uuid AND work_item_id='{WORK_A}'::uuid
           AND attribution_state='active'""")=="1",
          "ACCESS-02 reattestation must preserve original withdrawn evidence")
    restored=mine(api,key,worker)
    check_items(restored,[WORK_A,WORK_B])
    check(restored["items"][0].get("allocationId")==ALLOC_A and
          restored["items"][0].get("instructions")==SECRET_A,
          "ACCESS-02 reattested original did not return same source/authority")
    print("PASS ACCESS-02 independent current relevance restored without new original")

    # End the native Person Seat while the signed session stays active.
    sql(a.db_url,f"""UPDATE ledger.seats SET seat_state='ended',
      ended_at=now() WHERE ledger_id='{LEDGER}'::uuid
      AND person_entity_id='{PERSON}'::uuid AND seat_state='active'""")
    check(sql(a.db_url,f"""SELECT count(*) FROM ledger.seats
        WHERE ledger_id='{LEDGER}'::uuid AND person_entity_id='{PERSON}'::uuid
          AND seat_state='ended' AND ended_at IS NOT NULL""")=="1",
          "ACCESS-02 signed ended Seat test failed to change fixture")
    gone=mine(api,key,worker)
    check_items(gone,[])
    check_no_field_leak(gone)
    check(WORK_B not in json.dumps(gone),
          "ACCESS-02 ended Seat leaked original Work")
    print("PASS ACCESS-02 ended native Seat removes all Work without invalidating JWT")

    after_counts=(sql(a.db_url,"SELECT count(*) FROM atlas.work_items"),
                  sql(a.db_url,"SELECT count(*) FROM atlas.work_allocations"))
    check(before==after_counts,
          "ACCESS-02 reader test fabricated or deleted original Work/allocation")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text(
        "PASS ACCESS-02 signed current worker, revoked relevance, restored original, "
        "sibling Work, exact paging, outsider, owner, no-seat, anon and ended Seat\n",
        encoding="utf-8")
    print("PASS ACCESS-02 genuine four-session disposable local signed My Work privacy matrix")

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""HELD C2 signed GoTrue/PostgREST Case -> original Work disclosure probe.

TEST ONLY. Reuses C1's local-only HTTP helpers, *after* C1's original signed
establish/revise probe and the separate synthetic C2 SQL fixture. This script
does not install SQL, create a user, grant permissions or trigger a workflow.
Never use a remote DB or PostgREST endpoint.
"""
from __future__ import annotations

import argparse
import json
import re
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
C1 = runpy.run_path(str(ROOT / "scripts/validate-atlas-c1-signed-http.py"),
                    run_name="c2_import_c1_helpers")
sql = C1["sql"]
check = C1["check"]
local_status = C1["local_status"]
sign_in = C1["sign_in"]
allowed = C1["allowed"]
denied = C1["denied"]

OWNER = C1["OWNER"]
WORKER = C1["WORKER"]
OUTSIDER = C1["OUTSIDER"]
NO_SEAT = C1["NO_SEAT"]
ORG = C1["ORG"]
LEDGER_A = C1["LEDGER_A"]
LEDGER_B = C1["LEDGER_B"]
ROOT_AUTHORITY = C1["ROOT_AUTHORITY"]
ROOT_SEAT = C1["ROOT_SEAT"]
OWNER_PERSON = "e5200000-0000-4000-8000-000000000101"
W_L1 = "e5200000-0000-4000-8000-000000000c21"
W_L2 = "e5200000-0000-4000-8000-000000000c22"
W_WITHDRAWN = "e5200000-0000-4000-8000-000000000c23"
W_OLD_LINK = "e5200000-0000-4000-8000-000000000c24"
W_VERIFIED = "e5200000-0000-4000-8000-000000000c25"
W_STALE = "e5200000-0000-4000-8000-000000000c26"
B_STALE = "e5200000-0000-4000-8000-000000000b26"
RELEVANCE_VERIFIED = "e5200000-0000-4000-8000-000000000e25"
RELEVANCE_L1 = "e5200000-0000-4000-8000-000000000e21"
RPC = "operating_requirements_owner_self_api_v1"


def fingerprint(db_url):
    """Read-only snapshot of all Atlas Work and Clock table rows in local clone."""
    tables = sql(db_url, """
        select tablename from pg_catalog.pg_tables
        where schemaname='atlas' and
        (tablename like 'work\\_%' escape '\\'
         or tablename like '%clock%'
         or (tablename like 'company_work\\_%' escape '\\'
             and tablename <> 'company_work_native_ledger_relevance'))
        order by tablename
    """).splitlines()
    check("work_items" in tables and "work_allocations" in tables,
          "C2 clone missing canonical Work/Allocation tables")
    snapshots = {}
    for table in tables:
        check(re.fullmatch(r"[a-z][a-z0-9_]*", table) is not None,
              "C2 fingerprint table name escaped expected alphabet")
        snapshots[table] = sql(db_url, f"""
            select count(*)::text || ':' ||
                   coalesce(md5(string_agg(to_jsonb(t)::text, '|'
                        order by to_jsonb(t)::text)), '')
            from atlas.{table} t
        """)
    return snapshots


def read_owner(api, key, token, extra_forbidden=()):
    read = {"p_organization_id": ORG, "p_ledger_id": LEDGER_A, "p_limit": 200}
    packet = allowed(api, key, RPC, read, token)
    check(packet.get("contractVersion") == "operating_requirements_owner_v1"
          and packet.get("organizationId") == ORG
          and packet.get("nativeLedgerId") == LEDGER_A,
          "C2 read wrong exact owner/native Ledger source contract")
    entries = packet.get("registerEntries")
    check(isinstance(entries, list), "C2 owner packet lacks registerEntries")
    exact = [r for r in entries if isinstance(r, dict)
             and r.get("stable_key") == "signed_http_c1"]
    check(len(exact) == 1, "C2 signed original Case absent or duplicated")
    links = exact[0].get("canonical_work")
    check(isinstance(links, list), "C2 canonical_work missing/not array")
    ids = [w.get("workItemId") for w in links if isinstance(w, dict)]
    check(len(ids) == len(links) and len(set(ids)) == len(ids),
          "C2 Work disclosure contains malformed/duplicate IDs")
    check(not ({W_L2, W_WITHDRAWN, W_OLD_LINK} & set(ids)),
          "C2 foreign, withdrawn or inactive historical original disclosed")
    # Do not rely on the local app-side filter. Test raw source RPC payload.
    serialized = json.dumps(packet, sort_keys=True)
    for secret in (W_L2, W_WITHDRAWN, W_OLD_LINK,
                   "C2 FOREIGN L2 ONLY NOT DISCLOSABLE",
                   "C2 WITHDRAWN L1 NOT DISCLOSABLE", *extra_forbidden):
        check(secret not in serialized,
              "C2 returned forbidden Work ID/title elsewhere in owner payload")
    return ids


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                       args.db_url) is not None,
          "C2 must use a disposable loopback PostgreSQL URI only")
    check(sql(args.db_url, "select current_setting('server_version_num')::integer/10000") == "17",
          "C2 requires disposable PG17")
    check(sql(args.db_url, "select current_setting('uni_ops.disposable_clone',true)") == "true",
          "C2 explicit disposable clone guard absent")
    check(sql(args.db_url, f"""
        select count(*) from auth.users
        where id in ('{OWNER}','{WORKER}','{OUTSIDER}','{NO_SEAT}')
    """) == "4", "C2 requires exactly four C1 synthetic GoTrue principals")
    check(sql(args.db_url, f"""
        select count(*) from atlas.work_items
        where id in ('{W_L1}','{W_L2}','{W_WITHDRAWN}','{W_OLD_LINK}',
                     '{W_VERIFIED}','{W_STALE}')
    """) == "6", "C2 fixture Work missing")
    check(sql(args.db_url, f"""
        select count(*) from atlas.company_work_native_ledger_relevance
        where id in ('{RELEVANCE_L1}',
          'e5200000-0000-4000-8000-000000000e22',
          'e5200000-0000-4000-8000-000000000e23',
          'e5200000-0000-4000-8000-000000000e24',
          '{RELEVANCE_VERIFIED}', 'e5200000-0000-4000-8000-000000000e26')
    """) == "6", "C2 fixture relevance missing")

    api, key = local_status()  # rejects every non-loopback API
    identities = {name: sign_in(api, key, name)
                  for name in ("owner", "worker", "outsider", "no-seat")}
    for name, expected in (("owner", OWNER), ("worker", WORKER),
                           ("outsider", OUTSIDER), ("no-seat", NO_SEAT)):
        token, claims = identities[name]
        check(claims.get("sub") == expected and claims.get("session_id"),
              "C2 token principal/session mismatch")
        check(sql(args.db_url, f"""
            select count(*) from auth.sessions
            where user_id='{expected}'::uuid
              and id='{claims['session_id']}'::uuid
        """) == "1", "C2 missing current real GoTrue auth session")
    check(identities["worker"][1].get("user_metadata", {}).get("is_owner") is True,
          "C2 expects existing C1 forged worker metadata negative control")
    owner = identities["owner"][0]
    start = fingerprint(args.db_url)
    check(set(read_owner(api, key, owner)) == {W_L1, W_VERIFIED, W_STALE},
          "C2 current signed owner did not see exact L1 attested + two live source proofs")
    check(start == fingerprint(args.db_url), "C2 owner read mutated Work or Clock")
    print("PASS C2 signed owner: attested and verified source records shown; foreign/withdrawn/history denied")

    # Keep the persisted source_verified record active, but move ONLY its
    # fictional native source object to L2. The exact source resolver must
    # immediately stop proving relevance to L1. No original Work is updated.
    check(sql(args.db_url, f"""
        update ledger.booking_requests set ledger_id='{LEDGER_B}'::uuid
        where id='{B_STALE}'::uuid and ledger_id='{LEDGER_A}'::uuid
        returning 1
    """) == "1", "C2 disposable stale-source fixture update failed")
    check(sql(args.db_url, f"""
        select count(*) from atlas.company_work_native_ledger_exact_source_v1(
          '{W_STALE}'::uuid,'{LEDGER_A}'::uuid)
    """) == "0", "C2 stale source still independently proves L1")
    check(sql(args.db_url, f"""
        select count(*) from atlas.company_work_native_ledger_exact_source_v1(
          '{W_STALE}'::uuid,'{LEDGER_B}'::uuid)
    """) == "1", "C2 changed source did not become L2 specific")
    check(sql(args.db_url, f"""
        select count(*) from atlas.company_work_native_ledger_relevance
        where work_item_id='{W_STALE}'::uuid
          and ledger_id='{LEDGER_A}'::uuid
          and evidence_kind='source_verified' and attribution_state='active'
    """) == "1", "C2 stale negative lacks persisted active source_verified evidence")
    check(set(read_owner(api, key, owner,
                         extra_forbidden=(W_STALE, "C2 SOURCE PROOF WILL GO STALE")))
          == {W_L1, W_VERIFIED},
          "C2 signed raw L1 reader disclosed stale source_verified original")
    check(start == fingerprint(args.db_url),
          "C2 source-proof invalidation unexpectedly changed original Work/Result/Clock")
    print("PASS C2 source_verified: current proof admitted, stale native source suppressed")

    params = {"p_organization_id": ORG, "p_ledger_id": LEDGER_A, "p_limit": 200}
    for label in ("worker", "outsider", "no-seat"):
        denied(api, key, RPC, params, identities[label][0],
               "C2 " + label + " denied")
    denied(api, key, RPC, params, None, "C2 anonymous denied")
    denied(api, key, RPC,
           {**params, "p_ledger_id": LEDGER_B}, identities["outsider"][0],
           "C2 other native Ledger without root denied")
    denied(api, key, RPC,
           {**params, "p_organization_id": "e5200000-0000-4000-8000-000000000899"},
           owner, "C2 wrong Organization denied")
    check(start == fingerprint(args.db_url),
          "C2 denied reads mutated Work, Result or Clock")
    print("PASS C2 other principals and wrong native scope denied")

    # Revocation is local test-only, with immutable relevance history preserved.
    check(sql(args.db_url, f"""
        update atlas.company_work_native_ledger_relevance
        set attribution_state='withdrawn',withdrawn_at=now(),
            withdrawn_by_person_id='{OWNER_PERSON}'::uuid,
            withdrawal_reason='C2 disposable signed withdrawal proof'
        where id='{RELEVANCE_L1}'::uuid
          and attribution_state='active'
        returning 1
    """) == "1", "C2 exact synthetic L1 relevance withdrawal failed")
    check(read_owner(api, key, owner,
                     extra_forbidden=(W_STALE, "C2 SOURCE PROOF WILL GO STALE")) == [W_VERIFIED],
          "C2 withdrawn L1 owner-attested evidence remained visible")
    check(start == fingerprint(args.db_url),
          "C2 relevance withdrawal improperly mutated Work, Result or Clock")
    print("PASS C2 owner-attested withdrawal changes the very next signed L1 read")

    # Distinguish historical withdrawal of a source_verified attribution
    # from invalidation of the underlying exact source FK.
    check(sql(args.db_url, f"""
        update atlas.company_work_native_ledger_relevance
        set attribution_state='withdrawn',withdrawn_at=now(),
            withdrawn_by_person_id='{OWNER_PERSON}'::uuid,
            withdrawal_reason='C2 disposable source-verified withdrawal proof'
        where id='{RELEVANCE_VERIFIED}'::uuid and attribution_state='active'
        returning 1
    """) == "1", "C2 current source_verified evidence withdrawal failed")
    check(read_owner(api, key, owner,
                     extra_forbidden=(W_STALE, "C2 SOURCE PROOF WILL GO STALE",
                                      W_VERIFIED, "C2 SOURCE VERIFIED L1 VALID")) == [],
          "C2 source_verified evidence withdrawal remained visible")
    check(start == fingerprint(args.db_url),
          "C2 verified evidence withdrawal altered original Work/Result/Clock")
    print("PASS C2 source_verified withdrawal suppresses original without erasing Work")

    # Reuse C1's live-root/seat/session revocation semantics, in disposable
    # Postgres only; never create a new privilege or substitute service role.
    sql(args.db_url, f"""
        update atlas.principal_ledger_authorities
        set status='ended',ended_at=now()
        where id='{ROOT_AUTHORITY}'::uuid
    """)
    denied(api, key, RPC, params, owner, "C2 revoked native root denied")
    sql(args.db_url, f"""
        update atlas.principal_ledger_authorities
        set status='active',ended_at=null
        where id='{ROOT_AUTHORITY}'::uuid
    """)
    sql(args.db_url, f"""
        update ledger.seats set seat_state='ended',ended_at=now()
        where id='{ROOT_SEAT}'::uuid
    """)
    denied(api, key, RPC, params, owner, "C2 ended native seat denied")
    sql(args.db_url, f"""
        update ledger.seats set seat_state='active',ended_at=null
        where id='{ROOT_SEAT}'::uuid
    """)
    sql(args.db_url, f"""
        delete from auth.sessions where id='{identities['owner'][1]['session_id']}'::uuid
    """)
    denied(api, key, RPC, params, owner, "C2 ended GoTrue session denied")
    check(start == fingerprint(args.db_url),
          "C2 signed revocation tests mutated Work, Result or Clock")
    Path(args.output).write_text(
        "C2 HELD synthetic signed owner, source-verified active/stale, negative and revocation assertions PASS\n"
        "Protected carrier/runner pin and production release remain OPEN\n",
        encoding="utf-8")
    print("PASS C2 signed read-only Work/Clock fingerprint and ACL matrix")


if __name__ == "__main__":
    main()

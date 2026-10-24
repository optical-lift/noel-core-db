#!/usr/bin/env python3
"""Atlas Build 1: genuine local GoTrue/PostgREST original capture filing proof.

Requires disposable local production-schema clone with deterministic weight
synthetic fixture and THIS candidate applied. Never contacts production.
"""
import argparse
import importlib.util
import re
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("atlas_weight", ROOT / "validate-atlas-person-weight-signed-http.py")
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
auth = w.auth


def ok(condition, label):
    auth.check(condition, label)


def call(api, key, token, function, body):
    status, payload = auth.rpc(api, key, function, body, token)
    ok(status == 200 and isinstance(payload, dict) and payload.get("ok") is True,
       f"{function}: HTTP {status}, {str(payload)[:240]}")
    return payload


def denied(api, key, token, function, body, label):
    status, payload = auth.rpc(api, key, function, body, token)
    ok(status in (401, 403), f"{label}: expected permission denied, got {status}")
    if token:
        ok(isinstance(payload, dict) and payload.get("code") == "42501",
           f"{label}: signed authorization guard not enforced")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    ok(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url)),
       "Only disposable 127.0.0.1 database URLs are allowed")
    ok(auth.sql(args.db_url, f"select count(*) from auth.users where id in ('{w.ONE}','{w.TWO}')") == "2",
       "Two synthetic weight fixture users required")
    w.setup_auth(args.db_url)
    api, key = auth.local_status()
    a, claim_a = auth.sign_in(api, key, "weight-one")
    b, claim_b = auth.sign_in(api, key, "weight-two")
    for c, uid in [(claim_a, w.ONE), (claim_b, w.TWO)]:
        ok(c.get("sub") == uid and bool(c.get("session_id")),
           "Cryptographically signed session must match fixture user")
        ok(auth.sql(args.db_url,
            f"select count(*) from auth.sessions where id='{c['session_id']}'::uuid and user_id='{uid}'::uuid") == "1",
           "Real persisted Auth session required")

    get = lambda token, function, params: call(api, key, token, function, params)
    collections_a = get(a, "person_collections_self_api_v1", {})
    collections_b = get(b, "person_collections_self_api_v1", {})
    health_a = [v for v in collections_a["items"] if v.get("spreadKey") == "personal.health"]
    health_b = [v for v in collections_b["items"] if v.get("spreadKey") == "personal.health"]
    ok(len(health_a) == len(health_b) == 1, "One Health Collection per signed Person")
    dest_a, dest_b = health_a[0]["spreadInstanceId"], health_b[0]["spreadInstanceId"]
    ok(dest_a != dest_b, "Private Person Collection addresses must differ")
    index_a = get(a, "atlas_notebook_index_self_api_v1", {})
    index_b = get(b, "atlas_notebook_index_self_api_v1", {})
    for index, own, foreign in [(index_a, dest_a, dest_b), (index_b, dest_b, dest_a)]:
        spread_ids = [str(item.get("spreadInstanceId")) for item in index.get("items", [])]
        ok(own in spread_ids and foreign not in spread_ids, "Index exposes only own canonical Health")
    denied(api, key, None, "person_collections_self_api_v1", {}, "Anon collection list")

    # One synthetically authored existing capture is the only textual source.
    first = w.FIRST
    denied(api, key, b, "person_file_capture_self_api_v1",
           {"p_capture_id": first, "p_destination_spread_id": dest_b},
           "Foreign Person cannot file A's source even into B's Collection")
    denied(api, key, a, "person_file_capture_self_api_v1",
           {"p_capture_id": first, "p_destination_spread_id": dest_b},
           "A cannot file source into B's Collection")
    denied(api, key, b, "person_collection_sources_self_api_v1",
           {"p_spread_instance_id": dest_a, "p_limit": 100}, "B cannot read A's Health")
    # The preexisting original-capture contract conceals foreign captures
    # with P0002 (not-found) instead of disclosing their existence.
    status, foreign_capture = auth.rpc(api, key, "personal_reality_capture_self_api_v1",
                                       {"p_capture_id": first}, b)
    # PostgREST maps SQLSTATE P0002 (PL/pgSQL no_data_found class) to HTTP 500.
    # That status alone does NOT establish a denial. Require the EXACT
    # owner-scoped P0002 source code and refuse all successful responses.
    # Keep the existing public original-capture RPC unchanged.
    concealed = (
        isinstance(foreign_capture, dict)
        and (
            (status == 500 and foreign_capture.get("code") == "P0002")
            or (status in (401, 403) and foreign_capture.get("code") == "42501")
        )
    )
    ok(concealed,
       f"Foreign signed Person must not read source or infer its contents: HTTP {status} {str(foreign_capture)[:220]}")

    # Auto intent without approval is not a successful filing.
    no = get(a, "person_file_capture_self_api_v1",
             {"p_capture_id": first, "p_destination_spread_id": None})
    ok(no.get("routed") is False, "Unapproved automatic classification must not route")

    manual = get(a, "person_file_capture_self_api_v1",
                 {"p_capture_id": first, "p_destination_spread_id": dest_a})
    ok(manual.get("routed") is True and manual.get("captureId") == first,
       "Manual owner filing must preserve original source ID")
    again = get(a, "person_file_capture_self_api_v1",
                {"p_capture_id": first, "p_destination_spread_id": dest_a})
    ok(again.get("idempotent") is True and again.get("receiptId") == manual.get("receiptId"),
       "Retry must not create duplicate receipt")

    original = get(a, "personal_reality_capture_self_api_v1", {"p_capture_id": first})
    ok(original.get("capture", {}).get("id") == first, "Original capture still readable")
    got = get(a, "person_collection_sources_self_api_v1",
              {"p_spread_instance_id": dest_a, "p_limit": 100})
    matches = [v for v in got["items"] if v.get("captureId") == first]
    ok(len(matches) == 1 and matches[0].get("receiptId") == manual.get("receiptId"),
       "Health read must return SAME capture and SAME receipt")
    ok(matches[0].get("testimony") == original["capture"]["testimony"],
       "Health must read original testimony, not a copied note")

    # Create an additional collection solely in the disposable test DB.
    principal = auth.sql(args.db_url,
        f"select id from atlas.principals where status='active' and user_id='{w.ONE}'::uuid limit 1")
    aux = auth.sql(args.db_url, f"""
      insert into atlas.notebook_spread_instances(
        principal_id,spread_key,scope_kind,scope_id,subject_domain,subject_kind,
        subject_id,purpose_key,horizon_key,thread_key,creation_mode,spread_state,title,section_key
      ) values (
        '{principal}'::uuid,'personal.fixture-other','person','{w.ONE}',
        'personal','private_fixture_collection','{principal}','collection',
        'permanent','personal.fixture-other','explicit','open','Other Fixture Collection','Private'
      ) returning id
    """).strip()
    moved = get(a, "person_file_capture_self_api_v1",
                {"p_capture_id": first, "p_destination_spread_id": aux})
    ok(moved.get("eventKind") == "moved", "Moving must append a new event")
    gone = get(a, "person_collection_sources_self_api_v1",
               {"p_spread_instance_id": dest_a, "p_limit": 100})
    ok(first not in {x["captureId"] for x in gone["items"]},
       "Old Collection must no longer project moved original")
    back = get(a, "person_file_capture_self_api_v1",
               {"p_capture_id": first, "p_destination_spread_id": dest_a})
    ok(back.get("eventKind") == "moved", "Move back must preserve movement history")
    now = get(a, "person_collection_sources_self_api_v1",
              {"p_spread_instance_id": dest_a, "p_limit": 100})
    ok(len([x for x in now["items"] if x.get("captureId") == first]) == 1,
       "Move back must leave exactly one source active")

    # Race two truly signed calls against the same already-filed original.
    def attempt(_):
        return get(a, "person_file_capture_self_api_v1",
                   {"p_capture_id": first, "p_destination_spread_id": dest_a})
    with ThreadPoolExecutor(max_workers=2) as pool:
        raced = list(pool.map(attempt, range(2)))
    ok(len({r["receiptId"] for r in raced}) == 1,
       "Concurrent duplicate filing must not produce two receipts")

    date = auth.sql(args.db_url, f"""
      select (now() at time zone home_timezone)::date
        from atlas.principals where id='{principal}'::uuid
    """)
    today = get(a, "person_today_filing_receipts_self_api_v1", {"p_date": date})
    ok(len([x for x in today["items"] if x.get("captureId") == first]) == 1,
       "Today must show one CURRENT movement receipt, never older duplicates")
    ok(auth.sql(args.db_url, f"""
        select count(*) from atlas.personal_reality_captures where id='{first}'::uuid
    """) == "1", "No second original capture may be created by filing")
    ok(auth.sql(args.db_url, f"""
        select count(*) from atlas.person_collection_filing_events_v1 where capture_id='{first}'::uuid
    """) == "3", "Only original filing and two moves should exist")
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text("PASS genuine local signed sessions, private Index, file/move/retry/readback, current Today receipt\n")
    print("PASS Build 1 local signed source filing proof")


if __name__ == "__main__":
    main()

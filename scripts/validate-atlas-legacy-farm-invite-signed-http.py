#!/usr/bin/env python3
"""Exact held farm-invitation retirement: genuine local GoTrue member-read parity.

Test only. Relies on the existing Noel production-schema clone controller and
original C1 signed HTTP helpers. Never connects to production or copies live rows.
"""
import argparse
import hashlib
import json
import re
import runpy
import urllib.error
import urllib.request
from pathlib import Path

HELP = runpy.run_path(str(Path(__file__).with_name("validate-atlas-c1-signed-http.py")))
sql = HELP["sql"]
local_status = HELP["local_status"]
sign_in = HELP["sign_in"]
jwt_payload = HELP["jwt_payload"]
OWNER = HELP["OWNER"]
WORKER = HELP["WORKER"]
OUTSIDER = HELP["OUTSIDER"]
NO_SEAT = HELP["NO_SEAT"]
PASSWORD = HELP["PASSWORD"]
FARM_A = "e5200000-0000-4000-8000-000000000851"
FARM_B = "e5200000-0000-4000-8000-000000000852"
FIELDS = ("record_kind", "record_id", "user_id", "email", "display_name",
          "role", "worker_key", "active", "status", "created_at")
REMOVED = (
    "accept_membership_invite_v1(uuid)",
    "owner_get_membership_invite_v1(uuid,uuid)",
    "owner_mark_membership_invite_error_v1(uuid,uuid,text)",
    "owner_mark_membership_invite_sent_v1(uuid,uuid,uuid)",
    "owner_prepare_membership_invite_v1(uuid,text,text,text,text)",
    "owner_revoke_membership_invite_v1(uuid,uuid)",
    "pending_membership_invite_for_current_user_v1(uuid)",
)


def ensure(value, message):
    if not value:
        raise AssertionError(message)


def bootstrap_local_gotrue(db_url):
    # Match existing C1 local fixture and real GoTrue password authentication.
    # Credentials are fictional, installed only in the disposable local clone.
    for name, person in (("owner", OWNER), ("worker", WORKER),
                         ("outsider", OUTSIDER), ("no-seat", NO_SEAT)):
        metadata = '{"is_owner":true,"role":"root_governing"}' if name == "worker" else "{}"
        sql(db_url, f"""
          UPDATE auth.users
          SET instance_id='00000000-0000-0000-0000-000000000000'::uuid,
              email='atlas-c1-{name}@example.invalid',
              encrypted_password=extensions.crypt('{PASSWORD}',extensions.gen_salt('bf')),
              email_confirmed_at=now(),
              confirmation_token='', recovery_token='', email_change='',
              email_change_token_new='', email_change_token_current='',
              phone_change='', phone_change_token='', reauthentication_token='',
              raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
              raw_user_meta_data='{metadata}'::jsonb
          WHERE id='{person}'::uuid
        """)
        sql(db_url, f"""
          INSERT INTO auth.identities
            (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES (gen_random_uuid(),'atlas-c1-{name}@example.invalid',
                  '{person}'::uuid,
                  jsonb_build_object('sub','{person}',
                                     'email','atlas-c1-{name}@example.invalid'),
                  'email',now(),now())
        """)
    ensure(sql(db_url, """SELECT count(*) FROM auth.users
        WHERE id IN ('e5200000-0000-4000-8000-000000000001',
                     'e5200000-0000-4000-8000-000000000002',
                     'e5200000-0000-4000-8000-000000000003',
                     'e5200000-0000-4000-8000-000000000004')
          AND email_confirmed_at IS NOT NULL""") == "4",
          "Local C1 signed identities missing")


def rpc(api, key, token, farm_id):
    headers = {"apikey": key, "Content-Type": "application/json",
               "Content-Profile": "atlas", "Accept-Profile": "atlas"}
    if token:
        headers["Authorization"] = "Bearer " + token
    request = urllib.request.Request(
        api + "/rest/v1/rpc/owner_list_farm_members_v1",
        data=json.dumps({"p_farm_id": farm_id}).encode("utf-8"),
        headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            data = response.read().decode("utf-8")
            return response.status, json.loads(data) if data else None
    except urllib.error.HTTPError as exc:
        data = exc.read().decode("utf-8")
        try:
            payload = json.loads(data) if data else None
        except json.JSONDecodeError:
            payload = {"non_json_error": True}
        return exc.code, payload


def acl_fingerprint(db_url):
    return sql(db_url, """SELECT
      md5(coalesce(string_agg(to_jsonb(fm)::text,'|' ORDER BY fm.id::text),''))
      FROM atlas.farm_memberships fm""")


def shape_and_counts(db_url):
    query = """SELECT
      (SELECT count(*) FROM atlas.farm_memberships)::text || ':' ||
      (SELECT count(*) FROM atlas.organization_memberships)::text || ':' ||
      (SELECT count(*) FROM atlas.work_items)::text || ':' ||
      (SELECT count(*) FROM atlas.tasks)::text || ':' ||
      (SELECT count(*) FROM atlas.work_requirements)::text || ':' ||
      (SELECT count(*) FROM atlas.task_release_queue_items)::text"""
    return sql(db_url, query)


def tests(api, key, tokens):
    results = {}
    for actor, farm, expected in (
        ("owner", FARM_A, 3), ("outsider", FARM_B, 1)):
        status, value = rpc(api, key, tokens[actor][0], farm)
        ensure(status == 200 and isinstance(value, list),
               f"Signed positive owner membership read failed: {actor}, HTTP {status}")
        ensure(len(value) == expected and
               all(isinstance(row, dict) and tuple(row.keys()) == FIELDS
                   and row.get("record_kind") == "membership" for row in value),
               f"Unexpected owner member projection: {actor}")
        ensure(all(row["email"].endswith("@example.invalid") for row in value),
               "Nonfictional member data in test response")
        results[actor] = value
    for actor, farm in (
        ("worker", FARM_A), ("outsider", FARM_A),
        ("no-seat", FARM_A), ("owner", FARM_B)):
        status, value = rpc(api, key, tokens[actor][0], farm)
        ensure(status in (401, 403) and isinstance(value, dict)
               and value.get("code") == "42501",
               f"Signed nonowner denial failed: {actor}, HTTP {status}")
    anonymous, anon_data = rpc(api, key, None, FARM_A)
    ensure(anonymous in (401, 403, 404) and
           (not isinstance(anon_data, list)),
           f"Anonymous member list disclosed: HTTP {anonymous}")
    ensure(tokens["worker"][1].get("user_metadata", {}).get("is_owner") is True,
           "Missing intentional forged user_metadata negative control")
    return results


def verify_post_drop(db_url):
    ensure(sql(db_url, "SELECT to_regclass('atlas.farm_membership_invites') IS NULL") == "t",
           "Old farm invite table remains")
    for identity in REMOVED:
        ensure(sql(db_url, f"SELECT to_regprocedure('atlas.{identity}') IS NULL") == "t",
               "Old invite-only RPC remains: " + identity)
    ensure(sql(db_url, """SELECT
      has_function_privilege('authenticated',
           'atlas.owner_list_farm_members_v1(uuid)'::regprocedure,'EXECUTE')
      AND NOT has_function_privilege('anon',
           'atlas.owner_list_farm_members_v1(uuid)'::regprocedure,'EXECUTE')""") == "t",
           "Original member-list API ACL changed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--phase", required=True, choices=("before", "after"))
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()
    ensure(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                        args.db_url), "REFUSE nonlocal database URI")
    ensure(Path(args.state_file).is_absolute() and Path(args.receipt).is_absolute(),
           "Local scratch state paths required")
    api, key = local_status()
    if args.phase == "before":
        bootstrap_local_gotrue(args.db_url)
    tokens = {name: sign_in(api, key, name)
              for name in ("owner", "worker", "outsider", "no-seat")}
    for name, person in (("owner", OWNER), ("worker", WORKER),
                         ("outsider", OUTSIDER), ("no-seat", NO_SEAT)):
        ensure(tokens[name][1].get("sub") == person and
               tokens[name][1].get("session_id"),
               "Signed GoTrue principal mismatch")
    records = tests(api, key, tokens)
    current = {"owner_rows": records, "member_hash": acl_fingerprint(args.db_url),
               "counts": shape_and_counts(args.db_url)}
    if args.phase == "before":
        ensure(sql(args.db_url,
                   "SELECT count(*) FROM atlas.farm_membership_invites") == "0",
               "Original invite table not empty")
        ensure(current["counts"].split(":")[0] == "4",
               "Exactly four synthetic memberships required")
        ensure(not Path(args.state_file).exists(), "Refuse snapshot overwrite")
        Path(args.state_file).write_text(json.dumps(current, sort_keys=True),
                                         encoding="utf-8")
        print("PASS held legacy farm member signed original baseline (local)")
    else:
        ensure(Path(args.state_file).is_file(), "Original signed baseline missing")
        baseline = json.loads(Path(args.state_file).read_text(encoding="utf-8"))
        ensure(current == baseline, "Owner member rows or unrelated counts changed")
        verify_post_drop(args.db_url)
        Path(args.receipt).write_text(
            "PASS HELD farm invitation source retirement signed owner/nonowner "
            "original-row parity, ACL and no-loss (local only)\n", encoding="utf-8")
        print("PASS held legacy farm member signed before/after parity (local)")


if __name__ == "__main__":
    main()

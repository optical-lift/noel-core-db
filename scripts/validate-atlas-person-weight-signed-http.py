#!/usr/bin/env python3
"""Real local GoTrue/PostgREST proof for Person-only weight grammar.

Requires an isolated Supabase production-schema clone with synthetic fixture.
No remote API, paid Supabase branch, production user, or external mailbox.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("atlas_local_auth", ROOT / "validate-atlas-c1-signed-http.py")
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)

ONE = "a1400000-0000-4000-8000-000000000001"
TWO = "a1400000-0000-4000-8000-000000000002"
FIRST = "a1400000-0000-4000-8000-000000000501"
BEFORE = "a1400000-0000-4000-8000-000000000502"
FOREIGN = "a1400000-0000-4000-8000-000000000503"
FUTURE = "a1400000-0000-4000-8000-000000000504"


def expect(ok, why):
    auth.check(ok, why)


def call(api, key, token, name, body):
    return auth.rpc(api, key, name, body, token)


def accepted(api, key, token, name, body):
    code, out = call(api, key, token, name, body)
    expect(code == 200 and isinstance(out, dict) and out.get("ok") is True,
           f"{name} response not authorized or not verified: HTTP {code} {str(out)[:400]}")
    return out


def denied(api, key, token, name, body, label):
    code, obj = call(api, key, token, name, body)
    expect(code in (401, 403) and isinstance(obj, dict),
           f"{label}: request was not denied: HTTP {code} {str(obj)[:250]}")
    if token:
        expect(obj.get("code") == "42501", f"{label}: denial must be source 42501: {obj}")


def setup_auth(db):
    for name, user in (("weight-one", ONE), ("weight-two", TWO)):
        email = f"atlas-c1-{name}@example.invalid"
        mutable = '{"is_owner":true}' if name == "weight-two" else "{}"
        auth.sql(db, f"""
            update auth.users set
              instance_id='00000000-0000-0000-0000-000000000000'::uuid,
              email='{email}',
              encrypted_password=extensions.crypt('{auth.PASSWORD}', extensions.gen_salt('bf')),
              email_confirmed_at=now(),
              confirmation_token='',recovery_token='',email_change='',
              email_change_token_new='',email_change_token_current='',
              phone_change='',phone_change_token='',reauthentication_token='',
              raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
              raw_user_meta_data='{mutable}'::jsonb
            where id='{user}'::uuid
        """)
        auth.sql(db, f"""
            insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at)
            values(gen_random_uuid(),'{email}','{user}'::uuid,
              jsonb_build_object('sub','{user}','email','{email}'), 'email',now(),now())
        """)
    auth.sql(db, "notify pgrst, 'reload schema'")


def insert_future(db):
    auth.sql(db, f"""
        insert into atlas.evidence_records(
          id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,
          evidence_kind,source_kind,source_key,value,provenance)
        values(
          'a1400000-0000-4000-8000-000000000404','person','{ONE}',
          'health','person_body','body','first_party_testimony',
          'personal_notebook_daily_log','weight-future',
          '{{"sourceText":"I weighed 171 pounds today."}}','{{"localFixture":true}}')
    """)
    auth.sql(db, f"""
        insert into atlas.personal_reality_captures(
          id,principal_id,owner_user_id,source_action_id,testimony,evidence_id,
          capture_state,source_surface,capture_context,metadata,captured_at)
        values(
          '{FUTURE}','a1400000-0000-4000-8000-000000000201','{ONE}',
          'weight-proof-future','I weighed 171 pounds today.',
          'a1400000-0000-4000-8000-000000000404','captured',
          'personal_notebook_daily_log',
          jsonb_build_object('notebookDate',(now() at time zone 'UTC')::date::text),
          '{{"notebookEntryKind":"raw_note"}}',now()+interval '1 second')
    """)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    expect(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url)),
           "Signed measurement proof refuses any remote database")
    expect(auth.sql(args.db_url,
      f"select count(*) from auth.users where id in ('{ONE}','{TWO}')") == "2",
      "Two synthetic people must exist")
    api, key = auth.local_status()
    setup_auth(args.db_url)
    first, first_claims = auth.sign_in(api, key, "weight-one")
    second, second_claims = auth.sign_in(api, key, "weight-two")
    for claim, expected in ((first_claims, ONE), (second_claims, TWO)):
        expect(claim.get("sub") == expected and bool(claim.get("session_id")),
               "Local GoTrue session identity must match the synthetic Person")
        expect(auth.sql(args.db_url,
          f"select count(*) from auth.sessions where id='{claim['session_id']}'::uuid and user_id='{expected}'::uuid") == "1",
          "Locally signed JWT must be backed by an actual Auth session")
    expect(second_claims.get("user_metadata", {}).get("is_owner") is True,
           "Synthetic foreign JWT must carry editable misleading metadata")
    print("PASS two genuinely signed separate GoTrue sessions")

    preview = {"p_capture_id": FIRST}
    denied(api, key, None, "person_measurement_recognition_self_api_v1",
           preview, "anonymous preview")
    denied(api, key, second, "person_measurement_recognition_self_api_v1",
           preview, "foreign Person preview")
    denied(api, key, second, "set_person_measurement_rule_self_api_v1",
           {"p_capture_id": FIRST, "p_approve": True}, "foreign Person approval")

    initial = accepted(api, key, first, "person_measurement_recognition_self_api_v1", preview)
    expect(initial.get("recognition") == "approval_required", "First use must ask for permission")
    expect(initial.get("interpretation", {}).get("value") == 172,
           "Original weight number must survive server recognition")
    action = {"p_capture_id": FIRST, "p_approve": True}
    approved = accepted(api, key, first, "set_person_measurement_rule_self_api_v1", action)
    expect(approved.get("approved") is True, "First approval must be confirmed")
    stamp = approved.get("approvalAt")
    again = accepted(api, key, first, "set_person_measurement_rule_self_api_v1", action)
    expect(again.get("approvalAt") == stamp and again.get("approvalSourceCaptureId") == FIRST,
           "Same approval must be idempotent")
    accepted(api, key, first, "set_person_measurement_rule_self_api_v1",
             {"p_capture_id": BEFORE, "p_approve": True})
    reread = accepted(api, key, first, "person_measurement_recognition_self_api_v1", preview)
    expect(reread.get("recognition") == "approved_rule", "Rule must remain approved")
    insert_future(args.db_url)
    future = accepted(api, key, first, "person_measurement_recognition_self_api_v1",
                      {"p_capture_id": FUTURE})
    expect(future.get("recognition") == "approved_rule",
           "Future matching sentence must reuse approved rule")

    history = accepted(api, key, first, "person_body_weight_history_self_api_v1",
                       {"p_days": 30, "p_timezone": "UTC"})
    ids = {row.get("captureId") for row in history.get("items", [])}
    expect(ids == {FIRST, FUTURE},
           f"Original first and future source identities must be the only entries: {ids}")
    expect(history.get("truncated") is False and history.get("ruleApproved") is True,
           "History must report complete matching source coverage")
    foreign_history = accepted(api, key, second, "person_body_weight_history_self_api_v1",
                               {"p_days": 30, "p_timezone": "UTC"})
    expect(foreign_history.get("ruleApproved") is False and
           not foreign_history.get("items"), "Other Person's unapproved history must be empty")

    cancelled = accepted(api, key, first, "set_person_measurement_rule_self_api_v1",
                         {"p_capture_id": FIRST, "p_approve": False})
    expect(cancelled.get("approved") is False, "Standing rule revocation must be confirmed")
    after = accepted(api, key, first, "person_body_weight_history_self_api_v1",
                     {"p_days": 30, "p_timezone": "UTC"})
    expect(after.get("ruleApproved") is False and not after.get("items"),
           "Revocation must suppress derived readings")
    expect(auth.sql(args.db_url,
      f"select count(*) from atlas.personal_reality_captures where id in ('{FIRST}','{BEFORE}','{FOREIGN}','{FUTURE}')") == "4",
      "Original Person testimony must survive approval/revocation unchanged")
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(
      "PASS real local GoTrue and PostgREST person-only weight rule approval, reuse, separation, history, revocation\n",
      encoding="utf-8")
    print("PASS true signed local Person weight history authorization")


if __name__ == "__main__":
    main()

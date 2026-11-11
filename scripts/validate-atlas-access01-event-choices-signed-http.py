#!/usr/bin/env python3
"""ACCESS-01: REAL signed local GoTrue+REST only. No remote endpoints or production data.

Run only after the held candidate, reviewed schema and fictional Event fixtures have
been loaded into a disposable full-schema clone with local Auth and PostgREST.
This file does not create users, grants, schema or a production workflow.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "access01_base_event_signed", HERE / "validate-atlas-one-event-schedule-writer-signed-http.py")
ev = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ev)

WORK_B = "f5210000-0000-4000-8000-000000000902"
WORK_B_TITLE = "Private unrelated Event B preparation"
RPC_PEOPLE = "ledger_event_attention_people_self_api_v1"
RPC_CHOICES = "event_existing_work_choices_self_api_v1"
RPC_INDEX = "ledger_occurrence_shared_index_self_api_v1"
RPC_EVENT = "ledger_occurrence_shared_work_self_api_v1"
RPC_DECIDE = "governor_set_subject_disclosure_self_api_v1"


def check(condition, label):
    ev.require(condition, label)


def rpc(api, key, token, method, params):
    return ev.request(api, key, "/rest/v1/rpc/" + method, params, token)


def allowed(api, key, token, method, params, label):
    status, packet = rpc(api, key, token, method, params)
    check(status == 200 and isinstance(packet, dict) and packet.get("ok") is True,
          f"{label}: independently signed positive read not established, HTTP {status}")
    return packet


def denied(api, key, token, method, params, label):
    status, packet = rpc(api, key, token, method, params)
    check(status in (401, 403) and isinstance(packet, dict) and
          (token is None or packet.get("code") == "42501"),
          f"{label}: source denial 42501 required, not HTTP {status}")
    print("PASS denied", label)


def event_params():
    return dict(p_organization_id=ev.ORG, p_ledger_id=ev.LEDGER,
                p_occurrence_id=ev.CANONICAL_A)


def choose_params():
    return dict(**event_params(), p_query="")


def decision(kind, action_id):
    return dict(p_organization_id=ev.ORG, p_ledger_id=ev.LEDGER,
                p_target_person_id=ev.MEMBER_PERSON,
                p_subject_domain="event", p_subject_kind="occurrence",
                p_subject_id=ev.CANONICAL_A, p_disclosure_class="identity",
                p_decision_kind=kind, p_source_action_id=action_id,
                p_reason="Fictional narrow Event disclosure for signed ACCESS-01 verification.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url)),
          "ACCESS-01 refuses a nonlocal database URL")
    api, key = ev.local_endpoint()  # Refuses a nonlocal API URL.
    check(ev.sql(args.db_url, "select count(*) from atlas.work_items where "
          f"id='{WORK_B}'::uuid and title='{WORK_B_TITLE}' and work_state='open'") == "1",
          "Exact standalone fictional other-Event Work fixture required")
    check(ev.sql(args.db_url, "select count(*) from local_intel.occurrences where "
          f"id in ('{ev.CANONICAL_A}'::uuid,'{ev.CANONICAL_B}'::uuid)") == "2",
          "Two original fictional Occurrences required")
    before_work_count = ev.sql(args.db_url, "select count(*) from atlas.work_items")

    # Establish distinct REAL local GoTrue password sessions; metadata is not
    # authority. The fixture's canonical Person/Principal identities stay intact.
    sessions = {}
    for uid, label in ((ev.MEMBER, "member"), (ev.OUTSIDER, "outsider"),
                       (ev.ROOT, "root")):
        check(ev.sql(args.db_url,
              f"select count(*) from auth.users where id='{uid}'::uuid") == "1",
              "Expected distinct synthetic Auth user: " + label)
        email = "atlas-access01-" + label + "@example.invalid"
        ev.sql(args.db_url, f"""
          UPDATE auth.users SET
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{email}',
            encrypted_password=extensions.crypt('{ev.PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),confirmation_token='',recovery_token='',
            email_change='',email_change_token_new='',
            email_change_token_current='',phone_change='',phone_change_token='',
            reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{{"is_owner":true,"role":"root_governing"}}'::jsonb
          WHERE id='{uid}'::uuid
        """)
        ev.sql(args.db_url, f"""INSERT INTO auth.identities
          (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES(gen_random_uuid(),'{email}','{uid}'::uuid,
                 jsonb_build_object('sub','{uid}','email','{email}'),
                 'email',now(),now())""")
    ev.sql(args.db_url, "notify pgrst, 'reload schema'")
    for uid, label in ((ev.MEMBER, "member"), (ev.OUTSIDER, "outsider"),
                       (ev.ROOT, "root")):
        token, claims = ev.signed_session(api, key,
                    "atlas-access01-" + label + "@example.invalid")
        check(claims.get("sub") == uid and bool(claims.get("session_id")),
              "Independent signed session identity mismatch: " + label)
        check(ev.sql(args.db_url, "select count(*) from auth.sessions where "
             f"id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid") == "1",
             "Signed GoTrue session was not persisted: " + label)
        sessions[label] = token
    root, member, outsider = (sessions[k] for k in ("root", "member", "outsider"))

    # Baseline: Event is privately withheld and roster/choices remain root-only.
    initially = allowed(api, key, member, RPC_INDEX,
                        {"p_ledger_id": ev.LEDGER}, "private Event index")
    check(initially.get("events") == [], "Unshared Event title visible before grant")
    denied(api, key, member, RPC_PEOPLE, event_params(), "ungranted Person roster")
    denied(api, key, member, RPC_CHOICES, choose_params(), "ungranted Work choices")
    denied(api, key, outsider, RPC_PEOPLE, event_params(), "outside Person roster")
    denied(api, key, outsider, RPC_CHOICES, choose_params(), "outside Work choices")
    denied(api, key, None, RPC_PEOPLE, event_params(), "anonymous Person roster")
    denied(api, key, None, RPC_CHOICES, choose_params(), "anonymous Work choices")

    owner_people = allowed(api, key, root, RPC_PEOPLE, event_params(), "root roster")
    people = owner_people.get("people")
    check(isinstance(people, list) and
          {ev.MEMBER_PERSON, ev.ROOT_PERSON}.issubset(
              {x.get("personEntityId") for x in people if isinstance(x, dict)}),
          "Exact root could not read its genuinely connected Ledger personnel")
    owner_choices = allowed(api, key, root, RPC_CHOICES,
                            choose_params(), "root unrelated Work choices")
    choices = owner_choices.get("choices")
    check(isinstance(choices, list) and len(choices) == 1 and
          choices[0].get("workItemId") == WORK_B and
          choices[0].get("title") == WORK_B_TITLE,
          "Exact root did not see only the genuine unrelated Work option")

    grant = allowed(api, key, root, RPC_DECIDE,
                    decision("grant", "f5210000-0000-4000-8000-000000000704"),
                    "exact signed Event identity grant")
    check(grant.get("currentlyGranted") is True, "Signed Event grant receipt not established")
    visible = allowed(api, key, member, RPC_INDEX,
                      {"p_ledger_id": ev.LEDGER}, "recipient original Event")
    check([x.get("id") for x in visible.get("events", [])] == [ev.CANONICAL_A],
          "Recipient cannot see exactly the authorized Event, or adjacent Event leaked")
    event_work = allowed(api, key, member, RPC_EVENT,
                         event_params(), "recipient authorized Event detail")
    check(event_work.get("work") == [],
          "Event identity grant leaked private linked Work")
    denied(api, key, member, RPC_PEOPLE, event_params(),
           "Event-only recipient still cannot enumerate Ledger personnel")
    denied(api, key, member, RPC_CHOICES, choose_params(),
           "Event-only recipient still cannot search unrelated Ledger Work")
    # Existing signed owner retains both operations after somebody else's grant.
    allowed(api, key, root, RPC_PEOPLE, event_params(), "root roster after grant")
    allowed(api, key, root, RPC_CHOICES, choose_params(), "root Work choices after grant")

    withheld = allowed(api, key, root, RPC_DECIDE,
                       decision("withhold", "f5210000-0000-4000-8000-000000000705"),
                       "signed Event identity revocation")
    check(withheld.get("currentlyGranted") is False, "Source Event revocation did not persist")
    hidden = allowed(api, key, member, RPC_INDEX,
                     {"p_ledger_id": ev.LEDGER}, "Event removed after revocation")
    check(hidden.get("events") == [], "Event identity stayed visible after withhold")
    denied(api, key, member, RPC_PEOPLE, event_params(), "re-grant not implied by Event history")
    denied(api, key, member, RPC_CHOICES, choose_params(), "old Event grant does not expose Work")

    # Real source authority ends even when a signed JWT remains valid.
    ev.sql(args.db_url, "UPDATE atlas.principal_ledger_authorities SET status='ended', "
           "ended_at=now() WHERE ledger_id='" + ev.LEDGER + "'::uuid AND "
           "authority_kind='root_governing' AND status='active' AND principal_id IN "
           "(select id from atlas.principals where person_id='" + ev.ROOT_PERSON + "'::uuid)")
    denied(api, key, root, RPC_PEOPLE, event_params(), "ended exact root roster")
    denied(api, key, root, RPC_CHOICES, choose_params(), "ended exact root Work search")
    check(ev.sql(args.db_url, "select count(*) from atlas.work_items") == before_work_count,
          "Access checks manufactured or destroyed canonical Work")
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_text(
        "PASS ACCESS-01 signed root/recipient/outsider/anonymous, Event-only granted and "
        "revoked, private roster and unrelated Work withheld, source root ended; "
        "local fictional full-schema clone ONLY.\\n", encoding="utf-8")
    print("PASS ACCESS-01 Event recipient access distinct from roster and Work search")


if __name__ == "__main__":
    main()

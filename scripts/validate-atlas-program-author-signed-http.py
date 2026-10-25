#!/usr/bin/env python3
"""Real local GoTrue/PostgREST Program author privacy and versioning proof.

Runs ONLY against an isolated production-schema clone with fictional fixture users.
No real account, remote API, mailbox, program recipient, or production connection.
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

AUTHOR = "a1580000-0000-4000-8000-000000000001"
OTHER = "a1580000-0000-4000-8000-000000000002"
UNBOUND = "a1580000-0000-4000-8000-000000000003"
GRANT = "a1580000-0000-4000-8000-000000000301"
CREATE = "personal_training_author_create_self_api_v1"
READ = "personal_training_author_read_self_api_v1"
SAVE = "personal_training_author_save_self_api_v1"
APPROVE = "personal_training_author_approve_self_api_v1"


def expect(ok, label):
    auth.check(ok, label)


def rpc(api, key, token, method, params):
    return auth.rpc(api, key, method, params, token)


def accepted(api, key, token, method, params):
    code, value = rpc(api, key, token, method, params)
    expect(code == 200 and isinstance(value, dict) and value.get("ok") is True,
           f"Expected successful signed {method}; HTTP {code} {str(value)[:350]}")
    return value


def denied(api, key, token, method, params, label):
    code, value = rpc(api, key, token, method, params)
    expect(code in (401, 403) and isinstance(value, dict),
           f"{label}: expected permission denial, got {code} {str(value)[:350]}")
    if token:
        expect(value.get("code") == "42501",
               f"{label}: must fail via canonical authorization 42501, not a missing route: {value}")
    print("PASS", label)


def rejected(api, key, token, method, params, sqlstate, label):
    code, value = rpc(api, key, token, method, params)
    expect(code >= 400 and isinstance(value, dict) and value.get("code") == sqlstate,
           f"{label}: expected SQLSTATE {sqlstate}, got HTTP {code} {str(value)[:350]}")
    print("PASS", label)


def packet():
    return {
        "contract": "personal_training_program_author_source_v1",
        "title": "Fictional trail preparation",
        "purpose": "Train controlled lowering on stairs.",
        "approvalStanding": "draft_requires_governed_human_review",
        "sources": [
            {"key": "s-public", "locator": "synthetic:instructions",
             "disclosure": "recipient_disclosed"},
            {"key": "s-private", "locator": "synthetic:private-reference",
             "disclosure": "author_private"},
        ],
        "components": [{
            "key": "downhill-1", "kind": "session",
            "label": "Practice controlled descent",
            "instructions": "Use a supported stable small step.",
            "sourceKeys": ["s-public"],
            "function": {"key": "controlled_lowering",
                         "intendedChange": "Develop repeatable controlled lowering."},
            "alternatives": [{
                "key": "press-1", "instructions": "Use a leg press machine.",
                "relation": "partial_author_claim", "authorApproved": False,
                "rationale": "Force contribution does not establish downhill equivalence.",
            }],
        }],
    }


def setup_auth(db):
    for name, uid in (("program-author", AUTHOR), ("program-other", OTHER),
                      ("program-unbound", UNBOUND)):
        email = f"atlas-c1-{name}@example.invalid"
        metadata = '{"is_owner":true,"role":"program_owner"}' if uid == OTHER else "{}"
        auth.sql(db, f"""
            update auth.users set
              instance_id='00000000-0000-0000-0000-000000000000'::uuid,
              email='{email}',
              encrypted_password=extensions.crypt('{auth.PASSWORD}',extensions.gen_salt('bf')),
              email_confirmed_at=now(),
              confirmation_token='', recovery_token='',email_change='',
              email_change_token_new='',email_change_token_current='',
              phone_change='', phone_change_token='', reauthentication_token='',
              raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
              raw_user_meta_data='{metadata}'::jsonb
            where id='{uid}'::uuid
        """)
        auth.sql(db, f"""
            insert into auth.identities
              (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
            values(gen_random_uuid(),'{email}','{uid}'::uuid,
              jsonb_build_object('sub','{uid}','email','{email}'),'email',now(),now())
        """)
    auth.sql(db, "notify pgrst, 'reload schema'")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    expect(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url)),
        "Signed Program proof refuses remote database URIs")
    expect(auth.sql(args.db_url,
        f"select count(*) from auth.users where id in ('{AUTHOR}','{OTHER}','{UNBOUND}')") == "3",
        "All three fictional Auth people must exist")
    api, key = auth.local_status()
    setup_auth(args.db_url)
    author, author_claims = auth.sign_in(api, key, "program-author")
    other, other_claims = auth.sign_in(api, key, "program-other")
    unbound, unbound_claims = auth.sign_in(api, key, "program-unbound")
    for claims, expected in ((author_claims, AUTHOR),(other_claims, OTHER),
                             (unbound_claims, UNBOUND)):
        expect(claims.get("sub") == expected and claims.get("session_id"),
               "Each token must identify its own genuinely signed GoTrue session")
        expect(auth.sql(args.db_url,
          f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{expected}'::uuid") == "1",
          "GoTrue token has no durable matching local Auth session")
    expect(other_claims.get("user_metadata", {}).get("is_owner") is True,
           "Misleading attacker-controlled JWT user_metadata fixture must be present")
    print("PASS three separate genuine signed sessions; forged other-person metadata ignored")

    base = packet()
    args_create = {"p_packet": base, "p_request_key": "signed-create-0001"}
    denied(api,key,None,READ,{"p_program_id":None},"anonymous author list")
    denied(api,key,None,CREATE,args_create,"anonymous Program creation")
    denied(api,key,unbound,READ,{"p_program_id":None},"unbound signed account read")
    denied(api,key,unbound,CREATE,args_create,"unbound signed account create")

    created = accepted(api,key,author,CREATE,args_create)
    pid, digest = created["programId"],created["packetDigest"]
    expect(created["draftRevision"] == 1 and created["standing"]=="author_draft",
           "Create must establish private draft only")
    again=accepted(api,key,author,CREATE,args_create)
    expect(again["programId"] == pid and again["packetDigest"] == digest,
           "Idempotent create must not duplicate source")
    rejected(api,key,author,CREATE,{
        "p_packet":{**base,"title":"Changed title"},
        "p_request_key":"signed-create-0001"
    },"23505","conflicting create replay")
    denied(api,key,other,READ,{"p_program_id":pid},"foreign source reader")
    denied(api,key,other,SAVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_packet":base,"p_request_key":"other-save-0001"
    },"foreign author edit")
    denied(api,key,other,APPROVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_expected_digest":digest,"p_request_key":"other-approve-0001"
    },"foreign author approval")

    listed=accepted(api,key,author,READ,{"p_program_id":None})
    expect(any(v["programId"]==pid for v in listed["items"]), "Author-only list lost draft")
    before=accepted(api,key,author,READ,{"p_program_id":pid})
    expect(before["draftPacket"] == base and before["versions"] == [],
           "Original source including private reference must be returned only to author")
    rejected(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_expected_digest":"0"*64,"p_request_key":"signed-wrong-digest-1"
    },"40001","wrong reviewed-source digest")
    v1=accepted(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_expected_digest":digest,"p_request_key":"signed-approve-0001"
    })
    expect(v1["versionNumber"]==1 and v1["standing"]=="author_reviewed",
           "Only canonical signed review creates version one")
    v1_again=accepted(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_expected_digest":digest,"p_request_key":"signed-approve-0001"
    })
    expect(v1_again["versionId"]==v1["versionId"],
           "Exact review replay changed immutable version")

    revised={**base,"components":[{**base["components"][0],
        "instructions":"Repeat controlled descent twice using the stable step."}]}
    save_args={"p_program_id":pid,"p_expected_revision":1,
               "p_packet":revised,"p_request_key":"signed-save-0001"}
    save=accepted(api,key,author,SAVE,save_args)
    expect(save["draftRevision"]==2, "Draft save did not advance revision")
    save_again=accepted(api,key,author,SAVE,save_args)
    expect(save_again["draftRevision"]==2, "Exact edit replay duplicated revision")
    rejected(api,key,author,SAVE,{**save_args,"p_packet":base},
             "23505","edit request key changed content")
    rejected(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":1,
        "p_expected_digest":digest,"p_request_key":"signed-stale-approval"
    },"40001","stale reviewed-source revision")

    v2=accepted(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":2,
        "p_expected_digest":save["packetDigest"],"p_request_key":"signed-approve-0002"
    })
    expect(v2["versionNumber"]==2, "Expected a second immutable approved version")
    history=accepted(api,key,author,READ,{"p_program_id":pid})
    expect(len(history["versions"])==2
       and history["versions"][1]["packet"]==base
       and history["versions"][0]["packet"]==revised,
       "Original reviewed version was overwritten by a later draft")
    more={**base,"title":"Third synthetic revision"}
    saved3=accepted(api,key,author,SAVE,{
        "p_program_id":pid,"p_expected_revision":2,"p_packet":more,
        "p_request_key":"signed-save-0002"
    })
    expect(saved3["draftRevision"]==3,"Third draft did not establish revision")
    rejected(api,key,author,SAVE,save_args,
             "40001","historical edit replay after later revision")

    # With a still-valid signed JWT, a revoked server-side entitlement must
    # suppress both reading private history and saving new source immediately.
    auth.sql(args.db_url,f"""
       update atlas.personal_atlas_access_grants
          set state='revoked',revoked_at=now()
        where id='{GRANT}'::uuid
    """)
    denied(api,key,author,READ,{"p_program_id":pid},
           "revoked entitlement author read with still-valid JWT")
    denied(api,key,author,SAVE,{
        "p_program_id":pid,"p_expected_revision":3,"p_packet":more,
        "p_request_key":"signed-revoked-save"
    },"revoked entitlement author write with still-valid JWT")
    denied(api,key,author,APPROVE,{
        "p_program_id":pid,"p_expected_revision":3,
        "p_expected_digest":saved3["packetDigest"],"p_request_key":"signed-revoked-approval"
    },"revoked entitlement author approval with still-valid JWT")

    expect(auth.sql(args.db_url,
      "select count(*) from atlas.personal_training_programs") == "1",
      "Signed test unexpectedly created extra programs")
    expect(auth.sql(args.db_url,
      "select count(*) from atlas.personal_training_program_versions") == "2",
      "Signed test unexpectedly altered approved history")
    expect(auth.sql(args.db_url,
      "select count(*) from atlas.personal_training_program_edit_receipts") == "2",
      "Signed test unexpectedly altered edit receipts")
    expect(auth.sql(args.db_url,
      "select count(*) from atlas.personal_training_programs where draft_packet ? 'recipient'") == "0",
      "Authored source improperly established recipient")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS signed Program author create, read, save, review, versions, "
      "foreign/anonymous/unbound denials, stale/replay, and active grant revocation\n",
      encoding="utf-8")
    print("PASS real local GoTrue/PostgREST Program author authority and revocation")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""U1A signed acceptance on FRESH fictional Supabase local clone ONLY.

Preconditions: production-shaped schema, canonical C1 synthetic fixture,
held U1A candidate+postconditions, U1A fictional add-on fixture, local Auth/REST.
The source-owning protected clone controller, not this script, provisions,
destroys and keeps production credentials away from the test.
No signed JWT is synthesized: every actor signs into local GoTrue.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "u1a_native_signed_c1",
    ROOT / "scripts" / "validate-atlas-work-prerequisite-signed-http.py",
)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("STOP: canonical signed C1 helper missing")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)
c1 = base.c1

ORG = c1.ORG
LEDGER = c1.LEDGER_A
OWNER_PERSON = "e5200000-0000-4000-8000-000000000101"
REVIEWER_PRINCIPAL = "e5200000-0000-4000-8000-000000000112"
BED = "e5200000-0000-4000-8000-000000000b03"
NEED = "ec310000-0000-4000-8000-000000000001"
ACTION = "ec310000-0000-4000-8000-000000000021"
PAUSE_ACTION = "ec310000-0000-4000-8000-000000000022"
RETIRE_ACTION = "ec310000-0000-4000-8000-000000000023"
RULE = "fictional_bed3_restorative_maintenance"
POLICY = {
    "eligibilityMode": "standing_stewardship",
    "desiredOutcome": "Document the state of fictional Bed 3 accurately",
    "standingPurpose": "Inspect and document this fictional governed Subject",
    "seasonKeys": ["fictional_test_only"],
}
ORIGINAL = "Inspect fictional Bed 3 and record what is physically present."
PATH = "/rest/v1/rpc/"


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def sql(db, statement):
    return c1.sql(db, statement)


def rpc(api, key, token, name, payload):
    return base.rpc(api, key, token, name, payload)


def allow(api, key, token, name, payload):
    status, obj = rpc(api, key, token, name, payload)
    check(status == 200 and isinstance(obj, dict) and obj.get("ok") is True,
          f"Authorized {name} did not complete: {status} {str(obj)[:250]}")
    return obj


def denied(api, key, token, name, payload, description):
    status, obj = rpc(api, key, token, name, payload)
    check(status in (401, 403) and isinstance(obj, dict)
          and (token is None or obj.get("code") == "42501"),
          f"{description}: required native 42501, not absent RPC/malformed request: "
          f"{status} {str(obj)[:240]}")
    print("PASS", description)


def rejected_replay(api, key, token, name, payload):
    status, obj = rpc(api, key, token, name, payload)
    check(status in (400, 409) and isinstance(obj, dict)
          and obj.get("code") == "23505",
          f"Changed same-action replay must fail unique decision: {status} {str(obj)[:230]}")
    print("PASS changed same-action decision rejected")


def adopt(workspace, entry, decision, action, expected=None, policy=None):
    return {
        "p_organization_id": ORG, "p_ledger_id": LEDGER,
        "p_requirement_id": NEED, "p_rule_key": RULE,
        "p_policy": POLICY if policy is None else policy,
        "p_workspace_id": workspace, "p_entry_id": entry,
        "p_segment_index": 0, "p_decision": decision,
        "p_expected_previous_version_id": expected, "p_action_id": action,
    }


def read():
    return {"p_organization_id": ORG, "p_ledger_id": LEDGER,
            "p_requirement_id": NEED, "p_rule_key": RULE}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(bool(re.fullmatch(
        r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:54322/postgres", args.db_url)),
        "Only the fresh local Supabase PostgreSQL 127.0.0.1:54322/postgres is admitted")
    check(sql(args.db_url, "select current_database()") == "postgres",
          "Wrong local disposable database")
    check(sql(args.db_url, f"select count(*) from atlas.growing_objects where id='{BED}'::uuid") == "1"
          and sql(args.db_url, f"select count(*) from reality.entities where id='{BED}'::uuid "
                         "and entity_kind='growing_object' and identity_state='canonical'") == "1",
          "Exact fictional native + canonical Subject absent")
    check(sql(args.db_url, f"select count(*) from atlas.work_requirements where id='{NEED}'::uuid "
                         "and source_object_type='reality_entity' and state='active'") == "1",
          "Exact fictional canonical Requirement absent")
    check(sql(args.db_url, "select count(*) from atlas.governed_rulebook_versions_v1") == "0",
          "Rulebook must begin entirely unapproved")
    check(sql(args.db_url, f"select count(*) from atlas.principals where id='{REVIEWER_PRINCIPAL}'::uuid "
                         "and user_id='e5200000-0000-4000-8000-000000000002'::uuid") == "1",
          "Independent connected human reviewer Principal not established")
    work_before = sql(args.db_url, f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")
    need_before = sql(args.db_url, f"select count(*) from atlas.work_requirements where organization_id='{ORG}'::uuid")
    for signature in (
        "public.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)",
        "public.read_governed_rulebook_current_self_api_v1(uuid,uuid,uuid,text)",
    ):
        check(sql(args.db_url, "select (to_regprocedure('" + signature + "') is not null)::text") == "t",
              "U1A signed public transport missing: " + signature)

    api, key = c1.local_status()
    identities = base.setup_auth(args.db_url)
    signed = {}
    for name, uid in identities:
        token, claims = c1.sign_in(api, key, name)
        check(claims.get("sub") == uid and claims.get("session_id"),
              "Real local GoTrue session mismatch for " + name)
        check(sql(args.db_url, "select count(*) from auth.sessions where id='"
                  + claims["session_id"] + "'::uuid and user_id='" + uid + "'::uuid") == "1",
              "GoTrue session must be persisted in actual auth.sessions")
        signed[name] = (token, claims)
    check(len(set(v[0] for v in signed.values())) == 4,
          "Four independent GoTrue-issued sessions required")
    owner, worker, outsider = (signed[x][0] for x in ("owner","worker","outsider"))
    check(signed["worker"][1].get("user_metadata",{}).get("is_owner") is True,
          "Spoofed worker metadata negative test is required")
    print("PASS four authentic GoTrue sessions, worker metadata spoof is not authority")

    # A current root independently grants disclosure on the exact already
    # existing fictional spatial source; these are not generated by U1A.
    for index, klass in enumerate(("identity","condition"), start=1):
        allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",{
            "p_organization_id":ORG, "p_ledger_id":LEDGER,
            "p_target_person_id":OWNER_PERSON,"p_subject_domain":"spatial",
            "p_subject_kind":"growing_object","p_subject_id":BED,
            "p_disclosure_class":klass,"p_decision_kind":"grant",
            "p_source_action_id":f"ec310000-0000-4000-8000-00000000000{index}",
            "p_reason":"Fictional Bed 3 exact source review requires current native Subject disclosure."
        })

    # A Foundry workspace is provisional evidence only.
    ws = allow(api,key,owner,"prepare_foundry_workspace_self_api_v1",{
        "p_request_id":"ec310000-0000-4000-8000-000000000010",
        "p_subject_label":"Fictional C1 Bed 3, not real Elm",
        "p_provisional_field":"Fictional field care operating practice",
        "p_custody_scope_kind":"verified_self",
    })["workspaceId"]
    saved = allow(api,key,owner,"capture_foundry_reality_input_self_api_v1",{
        "p_workspace_id":ws,
        "p_request_id":"ec310000-0000-4000-8000-000000000011",
        "p_original_text":ORIGINAL,
        "p_segments":[{"kind":"operating_instruction","text":ORIGINAL}],
        "p_source_kind":"operator_statement",
        "p_observed_at":None,
    })
    entry = saved["entryId"]
    check(sql(args.db_url, "select count(*) from foundry.events where event_id='"
              +entry+"' and event_type='foundry_reality_input_v1'")=="1",
          "Original immutable human Foundry Event not present")
    before = allow(api,key,owner,"read_governed_rulebook_current_self_api_v1",read())
    check(before.get("state")=="not_established", "Not approved must not resemble policy")
    denied(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
           adopt(ws,entry,"active",ACTION), "Pending custody cannot adopt")
    check(sql(args.db_url,"select count(*) from atlas.governed_rulebook_versions_v1")=="0",
          "Denied pending custody must not write a version")

    # Native independent worker/reviewer signs source custody, but that
    # reviewer is never allowed to govern the Ledger's Rulebook.
    review = allow(api,key,owner,"request_foundry_source_custody_review_self_api_v1",{
        "p_workspace_id":ws,
        "p_request_id":"ec310000-0000-4000-8000-000000000012",
        "p_reviewer_principal_id":REVIEWER_PRINCIPAL,
        "p_claim_basis_kind":"first_party",
        "p_source_refs":[entry],
        "p_permitted_human_actions":["analyze"],
        "p_scope_description":"Review only the exact fictional original instruction for Bed 3.",
        "p_claimed_authority_basis":"The reviewer is a separately signed connected human; this is only a fictional source.",
    })
    case = review["caseId"]
    denied(api,key,owner,"decide_foundry_source_custody_review_self_api_v1",
           {"p_case_id":case, "p_decision":"approve",
            "p_review_basis":"Fictional source for test only; no operational rights."},
           "Source owner cannot independently review own evidence")
    approved = allow(api,key,worker,"decide_foundry_source_custody_review_self_api_v1",{
        "p_case_id":case,"p_decision":"approve",
        "p_review_basis":"I independently reviewed the exact fictional owner-authored source and approved analysis only.",
    })
    check(approved.get("reviewState")=="approved"
          and approved.get("workspaceCustodyState")=="pending",
          "Independent review must approve CASE without promoting workspace")

    denied(api,key,worker,"adopt_governed_rulebook_version_self_api_v1",
           adopt(ws,entry,"active",ACTION),"Source reviewer cannot govern Rulebook")
    denied(api,key,outsider,"adopt_governed_rulebook_version_self_api_v1",
           adopt(ws,entry,"active",ACTION),"Outsider cannot govern Rulebook")
    denied(api,key,None,"adopt_governed_rulebook_version_self_api_v1",
           adopt(ws,entry,"active",ACTION),"Anonymous cannot use Rulebook transport")

    first = allow(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
                  adopt(ws,entry,"active",ACTION))
    check(first.get("ruleVersion")==1 and first.get("replayed") is False
          and first.get("policyExecutable") is False
          and first.get("workCreated") is False,
          "Initial signed U1A must create only immutable, non-executable policy")
    version = first["ruleVersionId"]
    check(allow(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
                adopt(ws,entry,"active",ACTION)).get("replayed") is True,
          "Identical action must replay without a second version")
    changed = dict(POLICY)
    changed["desiredOutcome"] = "Changed instruction is not an idempotent replay."
    rejected_replay(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
                    adopt(ws,entry,"active",ACTION,policy=changed))
    current = allow(api,key,owner,"read_governed_rulebook_current_self_api_v1",read())
    check(current.get("ruleVersionId")==version and current.get("sourceReviewCurrent") is True,
          "Signed root must read same immutable version with current approval")

    paused = allow(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
                   adopt(ws,entry,"paused",PAUSE_ACTION,expected=version))
    check(paused.get("ruleVersion")==2 and paused.get("policyExecutable") is False,
          "Explicit pause must append exactly one nonexecuting version")
    retired = allow(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
                    adopt(ws,entry,"retired",RETIRE_ACTION,
                          expected=paused["ruleVersionId"]))
    check(retired.get("ruleVersion")==3,
          "Explicit retirement must append exactly one version")
    historical = allow(api,key,owner,"read_governed_rulebook_current_self_api_v1",read())
    check(historical.get("ruleStatus")=="retired"
          and historical.get("ruleVersionId")==retired.get("ruleVersionId"),
          "Retired latest version must win instead of older active")

    allow(api,key,worker,"revoke_foundry_source_custody_review_self_api_v1",{
        "p_case_id":case,
        "p_reason":"Fictional source-review revocation to verify immutable history and current denial.",
    })
    after = allow(api,key,owner,"read_governed_rulebook_current_self_api_v1",read())
    check(after.get("sourceReviewCurrent") is False and after.get("ruleVersion")==3,
          "Source review withdrawal must be explicit while original history remains")
    denied(api,key,owner,"adopt_governed_rulebook_version_self_api_v1",
           adopt(ws,entry,"retired","ec310000-0000-4000-8000-000000000024",
                 expected=retired["ruleVersionId"]),
           "Withdrawn source custody cannot authorize a new decision")

    check(sql(args.db_url,"select count(*) from atlas.governed_rulebook_versions_v1")=="3"
          and sql(args.db_url,"select count(*) from atlas.governed_rulebook_bindings_v1")=="3",
          "Three append-only decisions and one binding per version required")
    check(sql(args.db_url, f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")==work_before
          and sql(args.db_url, f"select count(*) from atlas.work_requirements where organization_id='{ORG}'::uuid")==need_before,
          "U1A MUST NOT create, modify or duplicate canonical original Work or Need")
    result = Path(args.output)
    result.parent.mkdir(parents=True,exist_ok=True)
    result.write_text("PASS: genuine independent GoTrue custody review and U1A root authority; "
                      "pending/worker/outsider/anonymous/changed replay/withdrawn denied; "
                      "3 immutable versions, zero Work/Need side effects.\n",
                      encoding="utf8")
    print("PASS U1A signed fictional source approval, revocation and no Work/Need effects")
    print("HOLD: concurrent approvals, seat withdrawal, nonfarm identity and production release")


if __name__=="__main__":
    main()

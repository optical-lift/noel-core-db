#!/usr/bin/env python3
"""Disposable-only U1A-compatible universal common-source signed probe.

Not a production transport, source adapter, Foundry approval or Work issuer.
Requires already completed original U1A signed fixture on fresh localhost
GoTrue/PostgREST PG17 and one synthetic public TEST ONLY RPC wrapper.
"""
import argparse
import importlib.util
import os
import re
from pathlib import Path


def check(ok, message):
    if not ok:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--u1a-helper", required=True)
    args = parser.parse_args()

    port = os.environ.get("U1A_DISPOSABLE_DB_PORT", "")
    project = os.environ.get("U1A_DISPOSABLE_PROJECT_DIR", "")
    check(bool(re.fullmatch(r"[1-9][0-9]{3,4}", port))
          and 20000 <= int(port) <= 65000
          and bool(re.fullmatch(
              r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:"
              + re.escape(port) + r"/postgres", args.db_url))
          and bool(project)
          and Path.cwd().resolve() == Path(project).resolve(),
          "STOP: universal common-source probe must run ONLY in fresh local clone")
    helper = Path(args.u1a_helper).resolve()
    check(helper.is_file()
          and helper.name == "validate_signed_u1a_local_clone_v1.py"
          and "candidates/atlas_governed_rulebook_u1a_v1" in str(helper),
          "Original signed U1A provenance helper must be pinned")
    spec = importlib.util.spec_from_file_location(
        "u1a_real_go_true_source_helper", helper)
    check(spec is not None and spec.loader is not None,
          "Original U1A genuine signed source helper unavailable")
    u1a = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(u1a)
    c1 = u1a.c1
    sql = lambda statement: c1.sql(args.db_url, statement)
    check(sql("select current_database()") == "postgres",
          "Wrong disposable database")
    api, key = c1.local_status()
    check(sql("select count(*) from atlas.work_requirements "
              f"where id='{u1a.NEED}'::uuid and state='active' "
              "and source_object_type='reality_entity'") == "1",
          "The SAME exact preexisting U1A synthetic Requirement is required")
    inner_sig = ("atlas.universal_rulebook_common_source_"
                 "preflight_internal_v1(uuid,uuid,uuid)")
    wrapper_sig = "public.universal_rulebook_common_test_self_api_v1(uuid,uuid,uuid)"
    check(sql(f"select (to_regprocedure('{inner_sig}') is not null)::text") == "true",
          "Exact new private common source must be installed on disposable only")
    for role in ("anon", "authenticated", "service_role"):
        check(sql("select has_function_privilege('"+role+"',"
                  f"to_regprocedure('{inner_sig}'),'EXECUTE')::text") == "false",
              "Direct common-source grant would bypass source-owner boundary")
    check(sql(f"select (to_regprocedure('{wrapper_sig}') is not null)::text") == "true",
          "Exact transient signed-only RPC wrapper not installed")

    # Original signed U1A test already configured the four synthetic users;
    # re-insertion would duplicate auth.identities, so only sign in again.
    signed = {}
    for name, uid in (("owner", c1.OWNER),
                      ("worker", c1.WORKER),
                      ("outsider", c1.OUTSIDER),
                      ("no-seat", c1.NO_SEAT)):
        token, claims = c1.sign_in(api, key, name)
        check(claims.get("sub") == uid and bool(claims.get("session_id")),
              "Genuine separate local GoTrue session required")
        signed[name] = (token, claims)
    check(len({item[1]["session_id"] for item in signed.values()}) == 4,
          "Four distinct GoTrue session records required")

    before = (
        sql(f"select count(*) from atlas.work_items "
            f"where organization_id='{u1a.ORG}'::uuid"),
        sql(f"select count(*) from atlas.work_requirements "
            f"where organization_id='{u1a.ORG}'::uuid"),
        sql("select count(*) from atlas.governed_rulebook_versions_v1"),
    )
    payload = dict(p_organization_id=u1a.ORG,p_ledger_id=u1a.LEDGER,
                   p_requirement_id=u1a.NEED)
    name = "universal_rulebook_common_test_self_api_v1"

    def call(token, arguments=None):
        return u1a.rpc(api,key,token,name,payload if arguments is None else arguments)

    owner = signed["owner"][0]
    status, result = call(owner)
    check(status == 200 and isinstance(result,dict) and
          result.get("ok") is True and
          result.get("state") == "common_checks_only_not_admitted" and
          result.get("subjectEntityId") == u1a.BED and
          result.get("requirementId") == u1a.NEED,
          "Current genuinely signed root must pass only COMMON source checks")
    for flag in ("domainAdapterAccepted","independentSourceReviewAccepted",
                 "policyAdoptable","policyExecutable","workCreated",
                 "clockAdmitted","successorWorkCreated"):
        check(result.get(flag) is False,
              "Universal common preflight illegally promoted " + flag)
    check(result.get("declaredSubjectDomain") == "spatial",
          "Declared domain may be read but never promoted into authority")
    print("PASS current genuine signed root: COMMON ONLY, every authority flag denied")

    for wrong_actor in ("worker","outsider","no-seat"):
        status, data = call(signed[wrong_actor][0])
        check(status in (401,403) and isinstance(data,dict)
              and data.get("code") == "42501",
              "Signed " + wrong_actor + " must fail exact native authority")
        print("PASS wrong actor denied:",wrong_actor)
    status, data = call(None)
    check(status in (401,403), "Anonymous must fail signed-only transport")
    print("PASS anonymous denied")

    wrong_req = dict(payload,p_requirement_id="eb510000-0000-4000-8000-000000000999")
    status, data = call(owner,wrong_req)
    check(status in (401,403) and isinstance(data,dict)
          and data.get("code") == "42501",
          "Nonexistent Requirement must not disclose or admit")
    wrong_ledger = dict(payload,p_ledger_id="eb510000-0000-4000-8000-000000000998")
    status, data = call(owner,wrong_ledger)
    check(status in (401,403) and isinstance(data,dict)
          and data.get("code") == "42501",
          "No current root on unknown Ledger")
    print("PASS wrong Requirement and Ledger denied")

    # Locally revoke this TEST SESSION (not a real or remote session).
    session_id = signed["owner"][1]["session_id"]
    sql("delete from auth.sessions where id='"+session_id+"'::uuid")
    status, data = call(owner)
    check(status in (401,403) and isinstance(data,dict)
          and data.get("code") == "42501",
          "Deleted GoTrue session must not retain remembered root authority")
    print("PASS revoked owner session denied")

    after = (
        sql(f"select count(*) from atlas.work_items "
            f"where organization_id='{u1a.ORG}'::uuid"),
        sql(f"select count(*) from atlas.work_requirements "
            f"where organization_id='{u1a.ORG}'::uuid"),
        sql("select count(*) from atlas.governed_rulebook_versions_v1"),
    )
    check(before == after, "Common source probe created Work, Need or policy")
    Path(args.output).write_text(
        "PASS universal COMMON exact source: genuine signed native root, "
        "wrong actor/Need/Ledger/anonymous/revoked denied; "
        "zero policy or Work rights; zero Work/Need/policy side effects.\n",
        encoding="utf8",
    )
    print("PASS universal source signed negative/positive matrix, no admission")


if __name__ == "__main__":
    main()

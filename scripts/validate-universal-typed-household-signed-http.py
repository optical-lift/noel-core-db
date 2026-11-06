#!/usr/bin/env python3
"""C1 first-party signed Household native source proof on DISPOSABLE clone only.

Requires exact preexisting C1 fixture, current signed U1A acceptance completed,
and only a disposable authenticated wrapper around a private new source.
Not a real Household observation, domain admission, or product transport.
"""
import argparse
import importlib.util
import os
import re
from pathlib import Path

HOUSEHOLD = "e5200000-0000-4000-8000-000000000c01"
NATIVE_INSTANCE = "e5200000-0000-4000-8000-000000000c03"
WRONG_HOUSEHOLD = "e5200000-0000-4000-8000-000000000c09"
WRONG_INSTANCE = "e5200000-0000-4000-8000-000000000c08"
RPC = "universal_typed_household_test_self_api_v1"

def check(condition, description):
    if not condition:
        raise AssertionError(description)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    parser.add_argument("--u1a-helper",required=True)
    args=parser.parse_args()

    port=os.environ.get("U1A_DISPOSABLE_DB_PORT","")
    project=os.environ.get("U1A_DISPOSABLE_PROJECT_DIR","")
    check(bool(re.fullmatch(r"[1-9][0-9]{3,4}",port))
          and 20000<=int(port)<=65000
          and bool(re.fullmatch(
            r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:"
            +re.escape(port)+r"/postgres",args.db_url))
          and bool(project)
          and Path.cwd().resolve()==Path(project).resolve(),
          "STOP: only fresh local PostgreSQL clone and current project allowed")

    path=Path(args.u1a_helper).resolve()
    check(path.is_file()
          and path.name=="validate_signed_u1a_local_clone_v1.py"
          and "candidates/atlas_governed_rulebook_u1a_v1" in str(path),
          "Exact original signed U1A source helper unavailable")
    spec=importlib.util.spec_from_file_location("household_original_signed_c1",path)
    check(spec is not None and spec.loader is not None,
          "Original C1 signed helper not importable")
    u1a=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(u1a)
    c1=u1a.c1
    sql=lambda stmt:c1.sql(args.db_url,stmt)
    check(sql("select current_database()")=="postgres",
          "Only the disposable database is allowed")
    check(sql("select count(*) from atlas.households where id='"
        +HOUSEHOLD+"'::uuid and status='active'")=="1",
          "Synthetic native Household missing")
    check(sql("select count(*) from atlas.household_kernel_instances where id='"
        +NATIVE_INSTANCE+"'::uuid and household_id='"+HOUSEHOLD
        +"'::uuid and state='active'")=="1",
          "The original independent nonfarm C1 native Subject must exist")
    check(sql("select count(*) from atlas.household_members where household_id='"
        +HOUSEHOLD+"'::uuid and user_id='"+c1.WORKER+"'::uuid and active")=="1",
          "Worker must genuinely be a Household member, but not governor")
    check(sql("select count(*) from atlas.care_observation_events where "
          "subject_domain='household' and scope_id='"+HOUSEHOLD+"'::uuid")=="0",
          "Household state must begin truly unobserved")
    check(sql("select count(*) from atlas.household_need_occurrences_v1 "
          "where household_id='"+HOUSEHOLD+"'::uuid")=="0",
          "The synthetic native Household must have no manufactured Need")
    inner="atlas.universal_rulebook_household_native_evidence_internal_v1(uuid,uuid)"
    wrapper="public.universal_typed_household_test_self_api_v1(uuid,uuid)"
    check(sql("select (to_regprocedure('"+inner+"') is not null)::text")=="true"
          and sql("select (to_regprocedure('"+wrapper+"') is not null)::text")=="true",
          "Exact private source and disposable signed wrapper must compile")
    for role in ("anon","authenticated","service_role"):
        check(sql("select has_function_privilege('"+role+"',"
             "to_regprocedure('"+inner+"'),'EXECUTE')::text")=="false",
             "Private Household native source must never be directly public")

    api,key=c1.local_status()
    signed={}
    # The *unchanged* original U1A acceptance already prepared C1's four
    # synthetic auth users. Re-sign in; never create or impersonate an actor.
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and bool(claims.get("session_id"))
             and sql("select count(*) from auth.sessions where id='"
                +claims["session_id"]+"'::uuid and user_id='"+uid+"'::uuid")=="1",
             "Current genuinely signed recorded GoTrue Person session required")
        signed[name]=(token,claims)
    check(len({v[1]["session_id"] for v in signed.values()})==4,
          "Four distinct current GoTrue sessions required")
    check(signed["worker"][1].get("user_metadata",{}).get("is_owner") is True,
          "Worker metadata spoof denial must remain part of this proof")

    before=(
       sql("select count(*) from atlas.work_items where household_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.household_need_occurrences_v1 where household_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.care_observation_events where scope_kind='household' and scope_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.governed_rulebook_versions_v1"),
       sql("select count(*) from atlas.work_requirements"),
    )
    base={"p_household_id":HOUSEHOLD,"p_kernel_instance_id":NATIVE_INSTANCE}
    def call(name,params=None):
        token=signed[name][0] if name is not None else None
        return u1a.rpc(api,key,token,RPC,base if params is None else params)
    def denial(name,label,params=None):
        status,data=call(name,params)
        check(status in (401,403) and isinstance(data,dict)
              and (name is None or data.get("code")=="42501"),
              "Require genuine native Household denial for "+label
              +": "+str((status,data))[:230])
        print("PASS",label)

    status,payload=call("owner")
    check(status==200 and isinstance(payload,dict) and payload.get("ok") is True
          and payload.get("state")=="native_subject_only_not_canonical"
          and payload.get("custodyKind")=="household"
          and payload.get("nativeSubjectVerified") is True
          and payload.get("nativeSubjectId")==NATIVE_INSTANCE,
          "Exact current independent Household Root must verify only native Subject")
    check(payload.get("currentObservationSourceVerified") is False
          and payload.get("openNeedSourceVerified") is False,
          "Must NOT invent first-party physical condition/Need from a kernel")
    for flag in (
      "canonicalRealityBindingVerified","commonRequirementVerified",
      "independentFoundryReviewVerified","domainAdmissionAuthorized",
      "policyAdoptable","policyExecutable","workCreated",
      "clockAdmitted","successorWorkCreated"
    ):
        check(payload.get(flag) is False,
              "Household native evidence must not grant "+flag)
    print("PASS genuine root native Subject only; zero observation/Need/policy authority")

    denial("worker","Household worker/member cannot substitute governor")
    denial("outsider","non-Household Person cannot govern")
    denial("no-seat","unconnected Person cannot govern")
    denial(None,"anonymous cannot reach temporary signed transport")
    denial("owner","wrong Household denied",
           dict(base,p_household_id=WRONG_HOUSEHOLD))
    denial("owner","wrong native instance denied",
           dict(base,p_kernel_instance_id=WRONG_INSTANCE))

    # Delete ONLY a local auth.session, not a real signed user. The now-revoked
    # signed credential MUST fail despite a still-valid cryptographic JWT.
    old_session=signed["owner"][1]["session_id"]
    sql("delete from auth.sessions where id='"+old_session+"'::uuid")
    denial("owner","deleted local GoTrue root session denied")

    after=(
       sql("select count(*) from atlas.work_items where household_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.household_need_occurrences_v1 where household_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.care_observation_events where scope_kind='household' and scope_id='"+HOUSEHOLD+"'::uuid"),
       sql("select count(*) from atlas.governed_rulebook_versions_v1"),
       sql("select count(*) from atlas.work_requirements"),
    )
    check(before==after,
          "Read-only native source verifier must produce zero Work/Need/observation/policy")
    Path(args.output).write_text(
      "PASS signed Household typed NATIVE source (not canonical): current governor,"
      " member-worker/outsider/no-seat/anonymous/wrong Household/instance/revoked"
      " session denied; zero observed condition, zero native Need, zero"
      " canonical Rulebook/Work/Need side effects.\n",
      encoding="utf8")
    print("PASS typed Household native source signed matrix and zero side effects")

if __name__=="__main__":
    main()

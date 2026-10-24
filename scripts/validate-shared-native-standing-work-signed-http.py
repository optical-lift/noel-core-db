#!/usr/bin/env python3
"""Genuine signed no-membership standing-Work proof on LOCAL disposable clone.

This test is intentionally only routed by the exact candidate filename. It
uses real GoTrue sessions and public PostgREST RPCs, not forged SQL JWTs,
synthetic employee seats, production resources, or any real subjects.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "local_signed_work_baseline", HERE/"validate-atlas-work-prerequisite-signed-http.py")
work=importlib.util.module_from_spec(spec)
spec.loader.exec_module(work)
c1=work.c1
ORG=c1.ORG
LEDGER=c1.LEDGER_A
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"
PROPOSE="propose_native_ledger_standing_scope_owner_self_api_v1"
ACCEPT="respond_native_ledger_standing_scope_self_api_v1"
ASSIGN="assign_native_ledger_company_work_under_scope_owner_self_api_v1"
REVOKE="revoke_company_work_standing_scope_self_api_v1"
TASK_A="e5200000-0000-4000-8000-000000000901"
TASK_B="e5200000-0000-4000-8000-000000000902"


def need(condition, explanation):
    c1.check(condition, explanation)


def request(api,key,token,rpc,params):
    return c1.rpc(api,key,rpc,params,token)


def allowed(api,key,token,rpc,params,label):
    status,payload=request(api,key,token,rpc,params)
    need(status==200 and isinstance(payload,dict) and payload.get("ok") is True,
         f"{label}: expected successful signed RPC, got {status} / {str(payload)[:360]}")
    print("PASS",label)
    return payload


def forbidden(api,key,token,rpc,params,label,codes=("42501",)):
    status,payload=request(api,key,token,rpc,params)
    need(status in (400,401,403,409) and isinstance(payload,dict),
         f"{label}: action not denied by RPC: {status} / {str(payload)[:360]}")
    need(payload.get("code") in codes or (token is None and status in (401,403)),
         f"{label}: wrong denial reason: {status} / {str(payload)[:360]}")
    print("PASS",label)


def proposal(worker):
    return dict(
        p_organization_id=ORG,p_ledger_id=LEDGER,p_worker_person_id=worker,
        p_organization_unit_id=None,p_coverage_mode="ledger_all_work",
        p_operation_class=None,
        p_terms="Test-only accepted ongoing responsibility for the same exact native Ledger; do not assign any other organization work.",
        p_valid_until=None)


def assignment(item,scope):
    return dict(p_work_item_id=item,p_scope_id=scope,
                p_reason="Test-only direct responsibility under an exact accepted Ledger standing scope")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    need(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
         "Refuse nonlocal database URL")
    identities=work.original.setup_auth(args.db_url)
    api,key=c1.local_status()
    signed={}
    for name,user_id in identities:
        token,claims=c1.sign_in(api,key,name)
        need(claims.get("sub")==user_id and bool(claims.get("session_id")),
             f"{name} is not a genuine signed GoTrue session")
        signed[name]=token
    owner=signed["owner"]
    worker=signed["worker"]
    outsider=signed["outsider"]
    need(c1.sql(args.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "Standing-Work test must have ZERO legacy organization memberships")
    need(c1.sql(args.db_url,
      "select count(*) from atlas.principal_ledger_authorities where ledger_id='"
      +LEDGER+"'::uuid and authority_kind='root_governing' and status='active'")=="1",
      "Single canonical root authority fixture missing")
    print("PASS genuine GoTrue owner/worker/outsider with zero organization memberships")

    scope_args=proposal(WORKER_PERSON)
    forbidden(api,key,worker,PROPOSE,scope_args,
              "worker cannot become governor with editable owner metadata")
    forbidden(api,key,outsider,PROPOSE,scope_args,
              "outsider cannot propose native responsibility")
    forbidden(api,key,None,PROPOSE,scope_args,
              "anonymous caller cannot propose standing responsibility")
    receipt=allowed(api,key,owner,PROPOSE,scope_args,
                    "signed native governing Person proposes without membership")
    scope=receipt.get("scopeId")
    need(bool(scope) and receipt.get("employeeSeatRequired") is False
         and receipt.get("workerConsentRecorded") is False,
         "Proposed scope conferred responsibility without consent")
    need(c1.sql(args.db_url,f"""
        select count(*) from atlas.company_work_standing_assignment_scopes
        where id='{scope}'::uuid
          and proposed_by_membership_id is null
          and worker_membership_id is null
          and worker_person_id='{WORKER_PERSON}'::uuid
          and scope_state='proposed'
    """)=="1","Native proposal incorrectly created an employee/member record")

    forbidden(api,key,owner,ASSIGN,assignment(TASK_A,scope),
              "owner cannot assign before worker has accepted",("23514",))
    forbidden(api,key,outsider,ACCEPT,{"p_scope_id":scope,"p_decision":"accept"},
              "outsider cannot accept another person's scope")

    inbox=allowed(api,key,worker,"native_ledger_standing_scopes_self_api_v1",{},
                  "recipient sees original proposed scope")
    need(any(x.get("scopeId")==scope for x in inbox.get("incoming",[])),
         "Receiver did not see governed incoming scope")
    accepted=allowed(api,key,worker,ACCEPT,{"p_scope_id":scope,"p_decision":"accept"},
                     "worker independently accepts exact standing scope")
    need(accepted.get("state")=="active" and accepted.get("assignmentCreated") is False,
         "Acceptance itself fabricated a task assignment")

    forbidden(api,key,worker,ASSIGN,assignment(TASK_A,scope),
              "worker cannot assign themselves by impersonating governor")
    result=allowed(api,key,owner,ASSIGN,assignment(TASK_A,scope),
                   "governing Person directly assigns existing task without membership")
    allocation=result.get("allocationId")
    need(bool(allocation) and result.get("responsiblePersonId")==WORKER_PERSON
         and result.get("newWorkCreated") is False,
         "Direct responsibility receipt is incorrect")
    need(c1.sql(args.db_url,f"""
      select count(*) from atlas.work_allocations
      where id='{allocation}'::uuid and work_item_id='{TASK_A}'::uuid
        and assignee_canonical_person_id='{WORKER_PERSON}'::uuid
        and assignee_membership_id is null and assigned_by_membership_id is null
        and establishment_basis_kind='delegated_under_standing_scope'
        and establishment_basis->>'scopeId'='{scope}'
    """)=="1","Original allocation failed canonical Person and provenance check")
    need(c1.sql(args.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "Assignment created a prohibited legacy membership")

    revoked=allowed(api,key,worker,REVOKE,
                    {"p_scope_id":scope,"p_reason":"Fictional worker withdraws future standing consent"},
                    "worker revokes continued standing responsibility")
    need(revoked.get("state")=="revoked" and
         revoked.get("newAutoAssignmentsPermitted") is False,
         "Revoked scope incorrectly remains permissive")
    forbidden(api,key,owner,ASSIGN,assignment(TASK_B,scope),
              "revocation blocks future assignments under old scope",("23514",))
    need(c1.sql(args.db_url,"select count(*) from atlas.organization_memberships")=="0",
         "Any test action fabricated membership")
    Path(args.output).write_text(
      "PASS actual owner/worker/outsider GoTrue sessions; no memberships; "
      "governed proposal; recipient consent; original assignment; exact Person "
      "provenance; revocation; stranger and anonymous denials; no invented task.\n")
    print("PASS signed no-membership native standing-Work end-to-end proof")


if __name__=="__main__":
    main()

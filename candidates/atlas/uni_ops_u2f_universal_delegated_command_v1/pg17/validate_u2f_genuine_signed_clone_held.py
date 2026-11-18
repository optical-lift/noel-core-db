#!/usr/bin/env python3
"""U2F genuine-signed actor acceptance RUNNER SOURCE, NEVER standalone authority.

DO NOT RUN until independently owner-approved exact source and protected,
disposable CURRENT-SCHEMA PostgreSQL/GoTrue/PostgREST clone is already prepared.
No connected production host, production record, installation, GRANT or
workflow invocation is authorized by this script's presence.

Requires the existing synthetic C1 + reciprocal Ledger fixture, the private
HELD U2F06 SQL installed in that disposable clone, and the separately
authorized 08_signed_clone_only_rpc_bridge_held.sql clone-only HTTP wrapper.
The caller of this script must perform those steps only through a reviewed
external owner-protected workflow; this runner does not create them.

Outputs only fixed progress labels. Never print JWTs, user IDs, private SQL,
PostgREST bodies, passwords, credentials or source row contents.
"""
import argparse
import importlib.util
import ipaddress
import re
import urllib.parse
from pathlib import Path

ROOT=Path(__file__).resolve().parents[4]
SOURCE=ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py"
assert SOURCE.exists(), "Canonical signed HTTP helper is missing"
spec=importlib.util.spec_from_file_location("u2f_canonical_signed",SOURCE)
signed=importlib.util.module_from_spec(spec)
spec.loader.exec_module(signed)
c1=signed.c1

ROOT_RECEIPT_A=c1.ROOT_AUTHORITY
ROOT_RECEIPT_B="e5200000-0000-4000-8000-000000000602"
LEDGER_A=c1.LEDGER_A
LEDGER_B=c1.LEDGER_B
REVIEW_KEY="u2f_root_reaffirmation_review_v1"
AUTHORITY_KEY="ledger_governing_root_v1"
ADMIT="uni_ops_u2f_signed_clone_reaffirm_v1"
REVOKE="uni_ops_u2f_signed_clone_revoke_v1"
ATTESTATION="I reaffirm this exact Ledger authority"

def require(ok,message):
    if not ok:
        raise AssertionError(message)

def local_only(db_url,api_url):
    parsed=urllib.parse.urlparse(db_url)
    require(parsed.scheme in ("postgres","postgresql")
            and parsed.hostname=="127.0.0.1"
            and parsed.path=="/postgres"
            and parsed.port is not None
            and not parsed.query and not parsed.fragment,
            "STOP: exact loopback-only disposable PostgreSQL URL required")
    api=urllib.parse.urlparse(api_url)
    require(api.scheme=="http" and api.hostname in ("127.0.0.1","localhost")
            and api.port is not None and not api.username
            and not api.password and not api.query and not api.fragment,
            "STOP: no remote, TLS-production or secret-bearing HTTP URL")
    require(ipaddress.ip_address("127.0.0.1").is_loopback,
            "Loopback source guard failed")

def q(db,statement):
    return c1.sql(db,statement)

def count(db,statement):
    value=q(db,statement)
    require(re.fullmatch(r"[0-9]+",value or "") is not None,
            "Unexpected count response")
    return int(value)

def rpc(api,key,token,action,params):
    return c1.rpc(api,key,action,params,token)

def allow(api,key,token,action,params,label):
    status,payload=rpc(api,key,token,action,params)
    require(status==200 and isinstance(payload,dict),
            label+": signed operation did not return success class")
    # All payload fields are private and must remain local to this runner.
    return payload

def deny(api,key,token,action,params,label):
    status,payload=rpc(api,key,token,action,params)
    require(status in (400,401,403,409)
            and isinstance(payload,dict)
            and payload.get("code")=="42501",
            label+": expected exact source-owned denial class")
    print("PASS "+label,flush=True)

def admission(root,ledger):
    return {"p_original_root_id":root,"p_native_ledger_id":ledger,
            "p_explicit_attestation":ATTESTATION}

def withdrawal(id_):
    return {"p_native_responsibility_id":id_,
            "p_reason":"Signed fictional review withdrawn without governing approval"}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    a=parser.parse_args()
    require(re.fullmatch(
        r"postgres(?:ql)?://[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
        a.db_url) is not None,
        "STOP: no non-loopback / remote DB connector")
    output=Path(a.output).resolve()
    require(output.is_relative_to(Path("/tmp").resolve()),
            "Only temporary local test receipts may be written")
    api,key=c1.local_status()
    local_only(a.db_url,api)

    # Exact synthetic fixture preconditions: no real rows are copied here.
    require(count(a.db_url,"SELECT count(*) FROM auth.users WHERE id IN ("+
              ",".join("'"+x+"'" for x in
                (c1.OWNER,c1.WORKER,c1.OUTSIDER,c1.NO_SEAT))+")")==4,
            "STOP: four fictional C1 users not present")
    require(count(a.db_url,"SELECT count(*) FROM atlas.principal_ledger_authorities WHERE "
             "id IN ('"+ROOT_RECEIPT_A+"','"+ROOT_RECEIPT_B+"') "
             "AND status='active' AND authority_kind='root_governing'")==2,
            "STOP: exact two fictional original roots not present")
    require(count(a.db_url,"SELECT count(*) FROM ledger.seat_responsibilities "
             "WHERE responsibility_key IN ('"+REVIEW_KEY+"','"+AUTHORITY_KEY+"')")==0,
            "STOP: test clone not clean of native root/review records")
    require(count(a.db_url,"SELECT count(*) FROM pg_catalog.pg_proc p "
             "JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace "
             "WHERE n.nspname='public' AND p.proname IN "
             "('"+ADMIT+"','"+REVOKE+"')")==2,
            "STOP: only owner-protected clone wrapper may be used")
    before=count(a.db_url,"SELECT count(*) FROM atlas.work_items")
    # Existing code intentionally does not print bearer token/claims.
    identities=signed.setup_auth(a.db_url)
    sessions={}
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        require(claims.get("sub")==uid and claims.get("session_id"),
                "GoTrue signed identity/session mismatch")
        require(count(a.db_url,"SELECT count(*) FROM auth.sessions "
                      "WHERE id='"+claims["session_id"]+"'::uuid "
                      "AND user_id='"+uid+"'::uuid")==1,
                "Signed session not persisted in local auth.sessions")
        sessions[name]=(token,claims)
    require(len({c[0] for c in sessions.values()})==4,
            "Expected four distinct real local bearer tokens")
    print("PASS genuine GoTrue/HTTP sessions for four fictional actors",flush=True)

    owner=sessions["owner"][0]
    worker=sessions["worker"][0]
    outsider=sessions["outsider"][0]
    no_seat=sessions["no-seat"][0]

    for name,token in (("worker",worker),("outsider",outsider),("no-seat",no_seat)):
        deny(api,key,token,ADMIT,admission(ROOT_RECEIPT_A,LEDGER_A),
             name+" cannot reaffirm another Principal's exact original root")
    deny(api,key,owner,ADMIT,admission(ROOT_RECEIPT_B,LEDGER_B),
         "owner cannot borrow another Ledger root")
    deny(api,key,worker,ADMIT,admission(ROOT_RECEIPT_A,LEDGER_B),
         "worker cannot mispair original root and Ledger")
    deny(api,key,outsider,REVOKE,
         withdrawal("00000000-0000-4000-8000-000000000999"),
         "outsider cannot revoke unrelated root candidate")

    # Real user-signed GoTrue/PostgREST transport positive against private
    # held review-only candidate; never a native governing authority.
    owner_row=allow(api,key,owner,ADMIT,admission(ROOT_RECEIPT_A,LEDGER_A),
                    "owner native root review")
    require(owner_row.get("candidateRecorded") is True
            and owner_row.get("governingRootVerified") is False
            and owner_row.get("delegatedWorkAuthorized") is False
            and owner_row.get("independentSourceAdjudication") is False,
            "Owner review receipt overstated governing authority")
    owner_id=owner_row.get("nativeResponsibilityId")
    require(bool(owner_id),"Owner review returned no exact native record")
    print("PASS signed original owner creates only review candidate",flush=True)

    worker_row=allow(api,key,worker,ADMIT,admission(ROOT_RECEIPT_B,LEDGER_B),
                     "worker's own original native root review")
    require(worker_row.get("candidateRecorded") is True
            and worker_row.get("governingRootVerified") is False
            and worker_row.get("delegatedWorkAuthorized") is False,
            "Worker review receipt overstated native authority")
    worker_id=worker_row.get("nativeResponsibilityId")
    require(bool(worker_id) and worker_id!=owner_id,
            "Two independent Ledger reviews collided")
    print("PASS second genuinely signed Principal on distinct native Ledger",flush=True)

    require(count(a.db_url,"SELECT count(*) FROM ledger.seat_responsibilities "
                  "WHERE responsibility_key='"+REVIEW_KEY+"'")==2,
            "Wrong review count after independently signed positive actions")
    require(count(a.db_url,"SELECT count(*) FROM ledger.seat_responsibilities "
                  "WHERE responsibility_key='"+AUTHORITY_KEY+"'")==0,
            "Review candidate was elevated to canonical root permission")
    require(count(a.db_url,"SELECT count(*) FROM atlas.work_items")==before,
            "Review spawned Work without original issue authorization")

    deny(api,key,worker,REVOKE,withdrawal(owner_id),
         "other Principal cannot revoke owner's review")
    deny(api,key,owner,REVOKE,withdrawal(worker_id),
         "owner cannot revoke worker's separate Ledger review")
    first=allow(api,key,owner,REVOKE,withdrawal(owner_id),
                "owner native review revocation")
    require(first.get("revoked") is True and first.get("replayed") is False
            and first.get("delegatedWorkAuthorized") is False,
            "Owner revocation failed or authorized Work")
    replay=allow(api,key,owner,REVOKE,withdrawal(owner_id),
                 "owner revocation replay")
    require(replay.get("revoked") is True and replay.get("replayed") is True,
            "Owner revoke replay changed history")
    print("PASS signed per-Ledger revocation and idempotent replay",flush=True)

    # Verify that deleting a real local session rejects the *same*
    # still-valid JWT via the extra current-auth.sessions guard.
    owner_session=sessions["owner"][1]["session_id"]
    q(a.db_url,"DELETE FROM auth.sessions WHERE id='"+owner_session+"'::uuid")
    deny(api,key,owner,ADMIT,admission(ROOT_RECEIPT_A,LEDGER_A),
         "revoked real session cannot admit prior governing claim")
    deny(api,key,owner,REVOKE,withdrawal(owner_id),
         "revoked real session cannot replay prior revocation")
    print("PASS invalidated true session denied despite bearer JWT",flush=True)

    second=allow(api,key,worker,REVOKE,withdrawal(worker_id),
                 "worker's own native review revocation")
    require(second.get("revoked") is True
            and second.get("delegatedWorkAuthorized") is False,
            "Worker's own review withdrawal failed")
    require(count(a.db_url,"SELECT count(*) FROM ledger.seat_responsibilities "
                  "WHERE responsibility_key='"+REVIEW_KEY+"' AND responsibility_state='ended'")==2,
            "Two review histories were not preserved as ended")
    require(count(a.db_url,"SELECT count(*) FROM ledger.seat_responsibilities "
                  "WHERE responsibility_key='"+AUTHORITY_KEY+"'")==0,
            "Governing root was established by a review workflow")
    require(count(a.db_url,"SELECT count(*) FROM atlas.work_items")==before,
            "Signed review accidentally created Work")
    print("PASS exact canonical Work count and zero native root grants",flush=True)

    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(
        "U2F_GENUINE_SIGNED_LOCAL_CLONE=PASS\n"
        "INDEPENDENT_SOURCE_ADJUDICATION=NO\n"
        "CANONICAL_NATIVE_GOVERNING_ROOT_GRANTS=ZERO\n"
        "DELEGATED_AGENT_WORK_COMMAND=NOT_RUN\n"
        "PRODUCTION_MUTATION=NONE\n",encoding="utf-8")
    print("U2F signed review-only acceptance complete in disposable local clone",flush=True)

if __name__=="__main__":
    main()

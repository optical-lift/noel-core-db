#!/usr/bin/env python3
"""U2F bridge SQL and ACL *synthetic-only* PostgreSQL 17 integration.

Runs in the default disposable postgres DB on the already-started isolated
GitHub Actions PostgreSQL service, never any live schema, GoTrue or PostgREST.
SET ROLE + fabricated auth claims are NOT genuine signed authentication.
No production URL, secrets, SQL dump, or network service is used.
"""
import json
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[3]
FIXTURE=HERE/"signed_clone_bridge_fixture.sql"
PRIVATE=HERE.parent/"06_signed_native_root_lifecycle_held.sql"
BRIDGE=HERE.parent/"08_signed_clone_only_rpc_bridge_held.sql"
ATTEST="I reaffirm this exact Ledger authority"
SYNTHETIC_GUC="u2f_owner_authorized_clone_only_v1"

ORIGINAL_A="e5200000-0000-4000-8000-000000000601"
ORIGINAL_B="e5200000-0000-4000-8000-000000000602"
LEDGER_A="e5200000-0000-4000-8000-000000000401"
LEDGER_B="e5200000-0000-4000-8000-000000000402"
USER_A="e5200000-0000-4000-8000-000000000001"
USER_B="e5200000-0000-4000-8000-000000000002"
SESSION_A="e5200000-0000-4000-8000-000000000011"
SESSION_B="e5200000-0000-4000-8000-000000000012"

ENV={**os.environ,"PGDATABASE":"postgres"}
ENV.pop("PGOPTIONS",None)

def run(sql, blocked=False, special_env=None):
    env={**ENV,**(special_env or {})}
    p=subprocess.run(
        ["psql","-X","-A","-t","-q","-v","ON_ERROR_STOP=1"],
        input=sql,text=True,capture_output=True,cwd=REPO,env=env,check=False,
    )
    if blocked:
        if p.returncode==0 or "ERROR:" not in p.stderr:
            raise AssertionError("a denied synthetic statement did not fail closed")
        return p.stderr
    if p.returncode:
        # These are synthetic SQL errors only; never emit SQL rows or credentials.
        raise AssertionError("isolated synthetic PostgreSQL failed: "+p.stderr[:800])
    return p.stdout.strip()

def json_receipt(text,label):
    receipts=[json.loads(line) for line in text.splitlines() if line.startswith("{")]
    if len(receipts)!=1:
        raise AssertionError(label+": expected exactly one synthetic JSON receipt")
    return receipts[0]

def synthetic_actor(user,session,statement):
    claim=json.dumps({"session_id":session})
    return (
        "BEGIN;\n"
        "SET LOCAL request.jwt.claim.sub = '"+user+"';\n"
        "SET LOCAL request.jwt.claims = '"+claim+"';\n"
        "SET LOCAL ROLE authenticated;\n"
        +statement+"\nCOMMIT;\n"
    )

def admit(original,ledger):
    return ("SELECT public.uni_ops_u2f_signed_clone_reaffirm_v1("
            f"'{original}'::uuid,'{ledger}'::uuid,'{ATTEST}');")

def revoke(record):
    return ("SELECT public.uni_ops_u2f_signed_clone_revoke_v1("
            f"'{record}'::uuid,'Fictional signed review withdrawn');")

def count(table,where="TRUE"):
    return int(run(f"SELECT count(*) FROM {table} WHERE {where};"))

def assert_denied(sql):
    run(sql,blocked=True)

run("\\i "+str(FIXTURE.relative_to(REPO))+
    "\n\\i "+str(PRIVATE.relative_to(REPO))+"\n")
assert count("atlas.principal_ledger_authorities",
             "id::text LIKE 'e5200000-%'")==2

# A fake discriminator setting alone does not establish a clone. This
# nonsetting rejection is tested only in a known disposable PG17 service.
assert_denied("\\i "+str(BRIDGE.relative_to(REPO))+"\n")
assert run("SELECT pg_catalog.to_regprocedure("
           "'public.uni_ops_u2f_signed_clone_reaffirm_v1(uuid,uuid,text)') IS NULL;")=="t"

run("\\i "+str(BRIDGE.relative_to(REPO))+"\n",
    special_env={"PGOPTIONS":"-c uniops.disposable_signed="+SYNTHETIC_GUC})
for signature in (
    "public.uni_ops_u2f_signed_clone_reaffirm_v1(uuid,uuid,text)",
    "public.uni_ops_u2f_signed_clone_revoke_v1(uuid,text)",
):
    for role,allowed in (("anon",False),("authenticated",True),("service_role",False)):
        actual=run("SELECT pg_catalog.has_function_privilege("
                   f"'{role}','{signature}','EXECUTE');")
        if actual!=("t" if allowed else "f"):
            raise AssertionError("temporary public wrapper EXECUTE violated exact role scope")
    assert run("SELECT p.prosecdef FROM pg_catalog.pg_proc p "
               "WHERE p.oid='"+signature+"'::regprocedure;")=="t"

# Verify ACL enforcement rather than trusting a SELECT from pg_catalog alone.
assert_denied("BEGIN;\nSET LOCAL ROLE anon;\n"+admit(ORIGINAL_A,LEDGER_A)+"\nROLLBACK;")
assert_denied("BEGIN;\nSET LOCAL ROLE service_role;\n"+admit(ORIGINAL_A,LEDGER_A)+"\nROLLBACK;")
assert count("ledger.actions")==0
assert count("ledger.seat_responsibilities")==0

# A real signed transport is separately protected; these session claims
# are synthetic and only establish the PostgreSQL behavior behind that test.
assert_denied(synthetic_actor(USER_A,SESSION_A,admit(ORIGINAL_B,LEDGER_B)))
assert_denied(synthetic_actor(USER_B,SESSION_B,admit(ORIGINAL_A,LEDGER_A)))
assert count("ledger.seat_responsibilities")==0

a=json_receipt(run(synthetic_actor(USER_A,SESSION_A,admit(ORIGINAL_A,LEDGER_A))),"A")
b=json_receipt(run(synthetic_actor(USER_B,SESSION_B,admit(ORIGINAL_B,LEDGER_B))),"B")
for row in (a,b):
    assert row["candidateRecorded"] is True
    for field in ("governingRootVerified","delegatedWorkAuthorized",
                  "independentSourceAdjudication","legacyRootRetirementAuthorized"):
        if row[field] is not False:
            raise AssertionError("review-only receipt elevated authority")
a_id=a["nativeResponsibilityId"]
b_id=b["nativeResponsibilityId"]
assert a_id!=b_id
assert count("ledger.seat_responsibilities",
             "responsibility_key='u2f_root_reaffirmation_review_v1'")==2
assert count("ledger.seat_responsibilities",
             "responsibility_key='ledger_governing_root_v1'")==0

assert_denied(synthetic_actor(USER_B,SESSION_B,revoke(a_id)))
assert_denied(synthetic_actor(USER_A,SESSION_A,revoke(b_id)))
first=json_receipt(run(synthetic_actor(USER_A,SESSION_A,revoke(a_id))),"revoke A")
again=json_receipt(run(synthetic_actor(USER_A,SESSION_A,revoke(a_id))),"replay A")
assert first["revoked"] is True and first["replayed"] is False
assert again["revoked"] is True and again["replayed"] is True
assert count("ledger.actions")==3
assert count("ledger.seat_responsibilities",
             "responsibility_key='ledger_governing_root_v1'")==0
assert count("ledger.seat_responsibilities",
             f"id='{b_id}'::uuid AND responsibility_state='active'")==1

# Native-review history is one-time and may not be deleted/regranted.
assert_denied(synthetic_actor(USER_A,SESSION_A,admit(ORIGINAL_A,LEDGER_A)))
assert count("ledger.seat_responsibilities")==2
assert run("SELECT (to_regclass('atlas.work_items') IS NULL)::text;")=="true"
print("U2F_12_SQL_BRIDGE_SYNTHETIC_POSTGRES17=PASS")
print("TEMP_BRIDGE_EXACT_ROLE_ACL=PASS")
print("EXACT_TWO_LEDGER_REVIEW_AND_REVOCATION=PASS")
print("GENUINE_GOTRUE_OR_POSTGREST=NOT_TESTED")
print("CANONICAL_ROOT_GRANTS=ZERO")
print("PRODUCTION_MUTATION=NONE")

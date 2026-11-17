#!/usr/bin/env python3
"""HELD/test-only: canonical active Personal Atlas grant for C1 fictional governor.

This does NOT invent a purchase or give every Ledger owner a subscription.
Only an owner-approved disposable PG clone may use the EXISTING privileged
public.grant_personal_atlas_access_v1 function. All source ACL/Principal/Person/
root Ledger and outsider negative preconditions are checked first.

NO production URL, network DB host, public artifacts, DDL, RLS or GRANT SQL.
No raw SQL, rows, errors or credentials are printed by this helper.
"""
import argparse
import os
import re
import subprocess

C1_PRINCIPAL="e5200000-0000-4000-8000-000000000111"
C1_OWNER="e5200000-0000-4000-8000-000000000001"
C1_PERSON="e5200000-0000-4000-8000-000000000101"
C1_WORKER="e5200000-0000-4000-8000-000000000002"
C1_OUTSIDER="e5200000-0000-4000-8000-000000000003"
C1_LEDGER="e5200000-0000-4000-8000-000000000401"
GRANT_KIND="uniops_disposable_native_governor_signed_test_v1"
RPC="public.grant_personal_atlas_access_v1(uuid,text,jsonb)"
STAGES=frozenset(("environment","actor_and_root","source_acl",
                  "preexisting_access","canonical_grant","postcondition"))
stage="environment"


def local_only(db_url):
    return bool(re.fullmatch(
        r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
        db_url or ""))


def source_queries():
    """Return only fixed SQL against the synthetic C1 fixture and source grant."""
    actor=(
        "SELECT count(*) FROM atlas.principals p "
        "JOIN atlas.principal_ledger_authorities a ON a.principal_id=p.id "
        f"WHERE p.id='{C1_PRINCIPAL}'::uuid "
        f"AND p.user_id='{C1_OWNER}'::uuid "
        f"AND p.person_id='{C1_PERSON}'::uuid "
        "AND p.status='active' "
        f"AND a.ledger_id='{C1_LEDGER}'::uuid "
        "AND a.authority_kind='root_governing' AND a.status='active'")
    acl=(
        f"SELECT CASE WHEN to_regprocedure('{RPC}') IS NOT NULL "
        f"AND NOT has_function_privilege('anon',to_regprocedure('{RPC}'),'EXECUTE') "
        f"AND NOT has_function_privilege('authenticated',to_regprocedure('{RPC}'),'EXECUTE') "
        f"AND has_function_privilege('postgres',to_regprocedure('{RPC}'),'EXECUTE') "
        "THEN '1' ELSE '0' END")
    before=(
        "SELECT count(*) FROM atlas.personal_atlas_access_grants "
        f"WHERE principal_id='{C1_PRINCIPAL}'::uuid AND state='active'")
    grant=(
        f"SELECT public.grant_personal_atlas_access_v1('{C1_PRINCIPAL}'::uuid,"
        f"'{GRANT_KIND}',"
        "'{\"disposableCloneOnly\":true,\"issuer\":\"existing_source_authority\","
        "\"test\":\"native_governor_personal_atlas_admission\"}'::jsonb)")
    after=(
        "SELECT count(*) FROM atlas.personal_atlas_access_grants "
        f"WHERE principal_id='{C1_PRINCIPAL}'::uuid AND state='active' "
        f"AND grant_kind='{GRANT_KIND}' "
        "AND basis->>'disposableCloneOnly'='true'")
    negatives=(
        "SELECT count(*) FROM atlas.personal_atlas_access_grants g "
        "JOIN atlas.principals p ON p.id=g.principal_id "
        f"WHERE p.user_id IN ('{C1_WORKER}'::uuid,'{C1_OUTSIDER}'::uuid) "
        f"AND g.grant_kind='{GRANT_KIND}' AND g.state='active'")
    return {"actor":actor,"acl":acl,"before":before,"grant":grant,
            "after":after,"negatives":negatives}


def run_local(db_url,query):
    result=subprocess.run(["psql",db_url,"-X","-At","-v","ON_ERROR_STOP=1",
         "-c",query],text=True,capture_output=True,timeout=15,check=False)
    if result.returncode:
        raise RuntimeError("Private local SQL failure")
    return result.stdout.strip()


def authorize(db_url):
    global stage
    if not local_only(db_url):
        raise RuntimeError("Refuse non-loopback PostgreSQL")
    if (os.environ.get("CI")!="true"
        or os.environ.get("GITHUB_ACTIONS")!="true"
        or os.environ.get("GITHUB_REPOSITORY")!="optical-lift/noel-core-db"
        or os.environ.get("ATLAS_NATIVE_GOVERNOR_TEST_GRANT_ENABLED")!="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("Refuse unauthorized governor fixture")
    sql=source_queries()
    stage="actor_and_root"
    if run_local(db_url,sql["actor"])!="1":
        raise RuntimeError("Signed root source not exact")
    stage="source_acl"
    if run_local(db_url,sql["acl"])!="1":
        raise RuntimeError("Canonical privileged grant source unavailable")
    stage="preexisting_access"
    if run_local(db_url,sql["before"])!="0" or run_local(db_url,sql["negatives"])!="0":
        raise RuntimeError("Synthetic governor/outsider test access was not clean")
    stage="canonical_grant"
    new_id=run_local(db_url,sql["grant"])
    if not re.fullmatch(
        r"[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}",new_id):
        raise RuntimeError("Canonical grant receipt invalid")
    stage="postcondition"
    if run_local(db_url,sql["after"])!="1" or run_local(db_url,sql["negatives"])!="0":
        raise RuntimeError("Canonical governor access or outsider denial unverified")
    print("PASS ATLAS_NATIVE_GOVERNOR_AUTHORIZED_TEST_GRANT=PASS")
    print("ATLAS_PRODUCTION_CHANGE=NONE")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    args=parser.parse_args()
    try:
        authorize(args.db_url)
    except Exception:
        print("BLOCKED ATLAS_NATIVE_GOVERNOR_TEST_GRANT=NOT_VERIFIED")
        print("ATLAS_NATIVE_GOVERNOR_GRANT_STAGE="+(stage if stage in STAGES else "unclassified"))
        raise SystemExit(1)


if __name__=="__main__":
    main()

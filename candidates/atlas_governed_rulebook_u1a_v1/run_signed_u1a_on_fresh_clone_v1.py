#!/usr/bin/env python3
"""Guarded runner for held U1A signed test on ALREADY STARTED fresh Supabase clone.

Requires approved schema-only provisioning and original C1 fictional baseline.
No production URLs, no server startup, no automatic restore/release, no real data.
The entire local database must be destroyed after the signed test (even on fail).
"""
import argparse
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TEST = HERE / "validate_signed_u1a_local_clone_v1.py"
CANDIDATE = HERE / "candidate.sql"
POST = HERE / "postconditions.sql"
FIXTURE = HERE / "signed_u1a_fictional_fixture_v1.sql"
BRANCH = "candidate/atlas-u1a-governed-rulebook-adoption-20261103"


def stop(message):
    raise SystemExit("STOP: " + message)


def run(args, **opts):
    proc = subprocess.run(args, capture_output=True, text=True, **opts)
    if proc.returncode:
        stop("Local test step failed (destroy disposable clone). "
             + (proc.stderr or proc.stdout)[-750:])
    return proc.stdout.strip()


def query(db, text):
    return run(["psql", db, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
                "-c", text])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db-url", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--confirm-fresh-disposable", action="store_true")
    args = ap.parse_args()
    if not re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:54322/postgres",
                        args.db_url):
        stop("Only local fresh Supabase PostgreSQL 127.0.0.1:54322/postgres")
    if not args.confirm_fresh_disposable:
        stop("Explicit --confirm-fresh-disposable required: this DB is destroyed after test")
    if not all(x.is_file() for x in (TEST,CANDIDATE,POST,FIXTURE)):
        stop("Missing exact held source or test fixture")
    if run(["git","-C",str(ROOT),"rev-parse","--show-toplevel"]) != str(ROOT):
        stop("Unrecognized Git repository")
    if run(["git","-C",str(ROOT),"symbolic-ref","--short","HEAD"]) != BRANCH:
        stop("Checkout must be the known held U1A branch")
    if run(["git","-C",str(ROOT),"status","--porcelain","--untracked-files=all"]):
        stop("Cannot test uncommitted or untracked source")
    sha = run(["git","-C",str(ROOT),"rev-parse","HEAD"])
    if not re.fullmatch(r"[0-9a-f]{40}",sha):
        stop("Invalid immutable candidate SHA")
    print("U1A exact held source",sha)

    # Supabase status must identify running local Auth and REST, not any API
    # supplied by this runner. No local services are started here.
    spec = importlib.util.spec_from_file_location(
       "u1a_preflight_c1",ROOT/"scripts"/"validate-atlas-c1-signed-http.py")
    if spec is None or spec.loader is None:
        stop("Canonical signed C1 helper missing")
    c1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(c1)
    c1.local_status()

    if query(args.db_url, "select current_database()||':'||current_setting('port')"
             "||':'||inet_server_addr()::text") != "postgres:54322:127.0.0.1":
        stop("Not the disposable local Supabase database")
    preflight = """SELECT CASE WHEN
       (SELECT count(*) FROM auth.users WHERE id IN (
         'e5200000-0000-4000-8000-000000000001'::uuid,
         'e5200000-0000-4000-8000-000000000002'::uuid,
         'e5200000-0000-4000-8000-000000000003'::uuid,
         'e5200000-0000-4000-8000-000000000004'::uuid))=4
       AND (SELECT count(*) FROM atlas.growing_objects WHERE
         id='e5200000-0000-4000-8000-000000000b03'::uuid)=1
       AND (SELECT count(*) FROM atlas.work_items WHERE id IN (
         'e5200000-0000-4000-8000-000000000901'::uuid,
         'e5200000-0000-4000-8000-000000000902'::uuid,
         'e5200000-0000-4000-8000-000000000903'::uuid))=3
       AND to_regclass('foundry.source_custody_review_cases_v1') IS NOT NULL
       AND to_regclass('atlas.work_requirements') IS NOT NULL
       AND to_regprocedure('atlas.foundry_current_signed_principal_v1()') IS NOT NULL
       AND to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)') IS NOT NULL
       AND to_regclass('atlas.governed_rulebook_versions_v1') IS NULL
       AND to_regclass('atlas.governed_rulebook_bindings_v1') IS NULL
       AND NOT EXISTS (SELECT 1 FROM reality.entities WHERE id=
         'e5200000-0000-4000-8000-000000000b03'::uuid)
       THEN 'FRESH_SYNTHETIC' ELSE 'REFUSE' END;"""
    if query(args.db_url,preflight)!="FRESH_SYNTHETIC":
        stop("This is not the exact fresh synthetic C1 clone. No SQL installed")
    for f in (CANDIDATE,POST):
        data=f.read_text(encoding="utf8")
        if re.search(r"(?im)^\s*(?:COMMIT\b|ROLLBACK\b|BEGIN\s*;|\\(?:connect|i|!))",data):
            stop("Unreviewed SQL transaction/psql command in "+f.name)
    # This COMMIT is permitted only for the guarded disposable clone:
    # real GoTrue and PostgREST sign-in is a separate connection.
    bundle=("BEGIN;\nSET LOCAL statement_timeout='60s';\n"
            +CANDIDATE.read_text(encoding="utf8")+"\n"
            +POST.read_text(encoding="utf8")+"\nCOMMIT;\n")
    run(["psql",args.db_url,"-X","-v","ON_ERROR_STOP=1"],input=bundle)
    print("PASS U1A candidate SQL/postconditions in disposable clone")
    run(["psql",args.db_url,"-X","-v","ON_ERROR_STOP=1",
         "-f",str(FIXTURE)])
    print("PASS guarded fictional Subject and Requirement")
    result=subprocess.run([sys.executable,str(TEST),"--db-url",args.db_url,
                           "--output",args.output],text=True)
    if result.returncode:
        stop("Signed test failed; destroy fresh disposable clone without retaining it")
    print("PASS U1A genuine signed local source proof (not production)")
    print("DESTROY disposable Auth/REST/Postgres clone now; no release authorized.")


if __name__=="__main__":
    main()

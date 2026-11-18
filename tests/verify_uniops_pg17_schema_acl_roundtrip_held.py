#!/usr/bin/env python3
"""Entirely fictional PG17 round-trip of the exact source-owned function ACL.

This does not touch production or restore any actual Atlas schema/roles.
It uses ephemeral fake roles/databases on the disposable GitHub PG17 service;
pg_dump --schema-only mirrors the essential Supabase CLI v2.116.0 dump
flags, and the CREATE OR REPLACE sanitation mirrors the CLI source.
"""
import os
from pathlib import Path
import re
import subprocess

import reconcile_uniops_native_governor_acl_local_held as acl

ROOT=Path(__file__).resolve().parent
CANONICAL=ROOT.parent/"supabase/migrations"/acl.MIGRATION
BASE="postgresql://postgres:postgres@127.0.0.1:54322/"
ORIGINAL="postgres"
CLONE="fictional_acl_restore_complete"
NO_GRANTS="fictional_acl_restore_without_grants"
RPC=acl.RPC

def command(argv, *, input_sql=None):
    result=subprocess.run(argv,input=input_sql,text=True,capture_output=True,
                          check=False,timeout=90)
    if result.returncode:
        raise RuntimeError("fictional_pg17_command_refused")
    return result.stdout

def sql(db,query):
    return command(["psql",BASE+db,"-X","-At","-v","ON_ERROR_STOP=1",
                    "-c",query]).strip()

def restore(db,source):
    command(["psql",BASE+db,"-X","-At","-v","ON_ERROR_STOP=1"],input_sql=source)

def source_function():
    raw=CANONICAL.read_text(encoding="utf8")
    needle="create or replace function "+RPC.split("(")[0]+"("
    if raw.count(needle)!=1 or raw.count(acl.REVOKE)!=1 or raw.count(acl.GRANT)!=1:
        raise RuntimeError("fictional_pg17_canonical_source_refused")
    tail=raw.split(needle,1)[1]
    return needle+tail.split("$function$;",1)[0]+"$function$;"

def sanitized_dump(raw):
    # The two source-critical transforms from Supabase CLI v2.116.0:
    # - CREATE SCHEMA IF NOT EXISTS
    # - CREATE OR REPLACE FUNCTION (rather than CREATE FUNCTION)
    # Crucially this does not remove or invent any GRANT/REVOKE.
    lines=[]
    for line in raw.splitlines(keepends=True):
        if line.startswith('CREATE SCHEMA "'):
            line=line.replace("CREATE SCHEMA ","CREATE SCHEMA IF NOT EXISTS ",1)
        if line.startswith('CREATE FUNCTION "'):
            line=line.replace("CREATE FUNCTION ","CREATE OR REPLACE FUNCTION ",1)
        lines.append(line)
    return "".join(lines)

def without_function_acl(raw):
    out=[]
    for line in raw.splitlines(keepends=True):
        if (re.match(r'^(GRANT|REVOKE) .* ON FUNCTION "public"."grant_personal_atlas_access_v1"\(',line)):
            continue
        out.append(line)
    return "".join(out)

def main():
    if (os.environ.get("CI")!="true" or os.environ.get("GITHUB_ACTIONS")!="true"
        or os.environ.get("GITHUB_REPOSITORY")!="optical-lift/noel-core-db"
        or os.environ.get("ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")!="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("fictional_pg17_environment_refused")
    source_md5=acl.source_fingerprint(CANONICAL)
    sql(ORIGINAL,
        "CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; "
        "CREATE ROLE service_role NOLOGIN; CREATE SCHEMA IF NOT EXISTS atlas;")
    sql(ORIGINAL,"SET check_function_bodies=off; "+source_function())
    sql(ORIGINAL,acl.REVOKE+" "+acl.GRANT)
    before=sql(ORIGINAL,acl.ACL)
    if acl.classify(before,source_md5)!="protected":
        raise RuntimeError("fictional_pg17_source_not_protected")

    dumped=command(["pg_dump",BASE+ORIGINAL,"--schema-only",
                    "--quote-all-identifier","--role","postgres",
                    "--schema","public"])
    # Require the exact function's statements present in the original
    # schema-only dump, to distinguish ACL omission from role semantics.
    function_acl_lines=[
        x for x in dumped.splitlines()
        if ("ON FUNCTION" in x and '"grant_personal_atlas_access_v1"' in x
            and (x.startswith("REVOKE ") or x.startswith("GRANT ")))
    ]
    if not any(x.startswith("REVOKE ") and "PUBLIC" in x for x in function_acl_lines):
        raise RuntimeError("fictional_pg17_dump_missing_public_revoke")
    if not any(x.startswith("GRANT ") and '"service_role"' in x for x in function_acl_lines):
        raise RuntimeError("fictional_pg17_dump_missing_service_grant")

    sql(ORIGINAL,"CREATE DATABASE "+CLONE+";")
    sql(ORIGINAL,"CREATE DATABASE "+NO_GRANTS+";")
    schema=sanitized_dump(dumped)
    restore(CLONE,schema)
    recovered=sql(CLONE,acl.ACL)
    outcome=acl.compare_readonly_acl_observations(before,recovered,source_md5)
    if outcome!="acl_parity_canonical_observations_match":
        raise RuntimeError("fictional_pg17_roundtrip_acl_not_canonical")

    # DELIBERATELY NEGATIVE fictional control: do not do this in the real
    # pipeline. Omitting just the function's ACL reproduces the *class* of
    # source-vs-clone divergence, but is NOT proof that production did so.
    modified=without_function_acl(schema)
    if modified==schema:
        raise RuntimeError("fictional_pg17_negative_control_not_modified")
    restore(NO_GRANTS,modified)
    missing=sql(NO_GRANTS,acl.ACL)
    if (acl.compare_readonly_acl_observations(before,missing,source_md5)
        !="acl_parity_clone_differs_from_canonical_source"):
        raise RuntimeError("fictional_pg17_negative_acl_not_detected")
    if acl.classify(missing,source_md5)=="protected":
        raise RuntimeError("fictional_pg17_negative_acl_treated_as_protected")
    print("PASS PG17_SYNTHETIC_SCHEMA_ONLY_DUMP_RETAINS_CANONICAL_FUNCTION_GRANTS")
    print("PASS PG17_SYNTHETIC_FUNCTION_ACL_FULL_ROUNDTRIP_EQUALS_CANONICAL")
    print("PASS PG17_SYNTHETIC_STRIPPED_ACL_CONTROL_YIELDS_CLONE_DIVERGENCE")
    print("LIMIT PRODUCTION_CLONE_CAUSE_NOT_IDENTIFIED")
    print("ATLAS_PRODUCTION_CHANGE=NONE")

if __name__=="__main__":
    main()

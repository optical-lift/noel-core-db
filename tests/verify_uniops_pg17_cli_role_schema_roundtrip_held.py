#!/usr/bin/env python3
"""Supabase CLI v2.116.0 role-only THEN schema-only fictional PG17 restore.

No live URLs, permissions or production credentials. Two separate
PostgreSQL 17 service containers, private ephemeral output with no data.
Verifies CLI reserved-role filtering, independent clone role preconditions,
source-owned function ACL restoration and unchanged owner/body.
"""
import os
from pathlib import Path
import re
import subprocess
import tempfile

import reconcile_uniops_native_governor_acl_local_held as acl
from inspect_uniops_acl_readonly_source_clone_held import sanitize_schema

ROOT=Path(__file__).resolve().parent
CANONICAL=ROOT.parent/"supabase/migrations"/acl.MIGRATION
SOURCE="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
CLONE="postgresql://postgres:postgres@127.0.0.1:54323/postgres"
BASELINE_ROLES=("anon","authenticated","service_role")
FAKE_ROLE="fictional_cli_member_parent"

def command(argv,*,cwd=None,timeout=300):
    try:
        run=subprocess.run(argv,cwd=cwd,text=True,capture_output=True,
                           stdin=subprocess.DEVNULL,check=False,timeout=timeout)
    except (OSError,subprocess.SubprocessError):
        raise RuntimeError("fictional_cli_command_refused") from None
    if run.returncode:
        raise RuntimeError("fictional_cli_command_refused")
    return run.stdout.strip()

def sql(url,query):
    return command(["psql",url,"-X","-At","-v","ON_ERROR_STOP=1",
                    "-c",query],timeout=40)

def restore(url,file):
    command(["psql",url,"-X","-At","-v","ON_ERROR_STOP=1",
             "-f",str(file)],timeout=120)

def source_function():
    raw=CANONICAL.read_text(encoding="utf8")
    name="create or replace function public.grant_personal_atlas_access_v1("
    if raw.count(name)!=1 or raw.count(acl.REVOKE)!=1 or raw.count(acl.GRANT)!=1:
        raise RuntimeError("fictional_cli_source_refused")
    return name+raw.split(name,1)[1].split("$function$;",1)[0]+"$function$;"

def baseline(url):
    create=("DO $fictional$ BEGIN "
            +" ".join(
                "IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='"+role+"') "
                "THEN CREATE ROLE "+role+" NOLOGIN; END IF;"
                for role in BASELINE_ROLES)
            +" END $fictional$;")
    sql(url,create)
    if sql(url,"SELECT COUNT(*) FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role')")!="3":
        raise RuntimeError("fictional_cli_baseline_roles_refused")

def inspect_roles_file(path):
    text=path.read_text(encoding="utf8")
    if len(text)>200000 or not text.strip().endswith("RESET ALL;"):
        raise RuntimeError("fictional_cli_roles_dump_invalid")
    # Pinned CLI v2.116.0 comments out any CREATE or ALTER of reserved
    # roles, and GRANT custom membership TO a reserved role.
    for role in BASELINE_ROLES+("postgres",):
        if re.search(r'^(?:CREATE|ALTER) ROLE "'+re.escape(role)+r'"',text,re.M):
            raise RuntimeError("fictional_cli_reserved_roles_not_filtered")
    if not re.search(r'^CREATE ROLE "'+FAKE_ROLE+r'";$',text,re.M):
        raise RuntimeError("fictional_cli_custom_role_missing")
    if re.search(r'^GRANT "'+FAKE_ROLE+r'" TO "service_role"',text,re.M):
        raise RuntimeError("fictional_cli_reserved_membership_not_filtered")

def inspect_schema_file(path):
    text=path.read_text(encoding="utf8")
    if len(text)>1000000:
        raise RuntimeError("fictional_cli_schema_dump_too_large")
    # These ACL statements are the decisive ones; exact quoting is emitted
    # by pg_dump, not guessed from the original lower-case migration.
    lines=[x for x in text.splitlines() if
           '"grant_personal_atlas_access_v1"' in x and "ON FUNCTION" in x
           and (x.startswith("GRANT ") or x.startswith("REVOKE "))]
    if not any(x.startswith("REVOKE ") and "PUBLIC" in x for x in lines):
        raise RuntimeError("fictional_cli_schema_public_revoke_missing")
    if not any(x.startswith("GRANT ") and '"service_role"' in x for x in lines):
        raise RuntimeError("fictional_cli_schema_service_role_grant_missing")
    if "COPY " in text or "INSERT INTO " in text:
        raise RuntimeError("fictional_cli_schema_contains_data")
    return text

def main():
    if (os.environ.get("CI")!="true"
        or os.environ.get("GITHUB_ACTIONS")!="true"
        or os.environ.get("GITHUB_REPOSITORY")!="optical-lift/noel-core-db"
        or os.environ.get("ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")!="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("fictional_cli_environment_refused")
    if command(["supabase","--version"]).splitlines()[-1]!="2.116.0":
        raise RuntimeError("fictional_cli_binary_version_refused")
    expected_md5=acl.source_fingerprint(CANONICAL)
    baseline(SOURCE)
    sql(SOURCE,"CREATE SCHEMA IF NOT EXISTS atlas;")
    sql(SOURCE,"SET check_function_bodies=off; "+source_function())
    sql(SOURCE,acl.REVOKE+" "+acl.GRANT)
    sql(SOURCE,"CREATE ROLE "+FAKE_ROLE+" NOLOGIN; GRANT "+FAKE_ROLE+" TO service_role;")
    original=sql(SOURCE,acl.ACL)
    if acl.classify(original,expected_md5)!="protected":
        raise RuntimeError("fictional_cli_source_acl_not_canonical")
    if sql(SOURCE,"SELECT pg_has_role('service_role','"+FAKE_ROLE+"','member')")!="t":
        raise RuntimeError("fictional_cli_source_membership_missing")

    # Independent clone's reserved roles exist before role-only restore.
    # Supabase itself ordinarily creates these, not the roles-only export.
    baseline(CLONE)
    if sql(CLONE,"SELECT to_regprocedure('"+acl.RPC+"') IS NULL")!="t":
        raise RuntimeError("fictional_cli_clone_not_empty")

    with tempfile.TemporaryDirectory(prefix="uniops-cli-roles-schema-") as d:
        directory=Path(d)
        # CLI requires a local config but no local Supabase process here.
        command(["supabase","init","--force"],cwd=directory,timeout=60)
        roles=directory/"roles.sql"
        schema=directory/"schema.sql"
        sanitized=directory/"schema-restorable.sql"
        command(["supabase","db","dump","--db-url",SOURCE,"--role-only",
                 "--file",str(roles)],cwd=directory)
        if not roles.is_file():
            raise RuntimeError("fictional_cli_role_export_missing")
        inspect_roles_file(roles)
        restore(CLONE,roles)
        if sql(CLONE,"SELECT 1 FROM pg_roles WHERE rolname='"+FAKE_ROLE+"'")!="1":
            raise RuntimeError("fictional_cli_custom_role_not_restored")
        if sql(CLONE,"SELECT pg_has_role('service_role','"+FAKE_ROLE+"','member')")!="f":
            raise RuntimeError("fictional_cli_reserved_role_membership_unexpected")
        if sql(CLONE,"SELECT to_regprocedure('"+acl.RPC+"') IS NULL")!="t":
            raise RuntimeError("fictional_cli_role_stage_created_function")

        command(["supabase","db","dump","--db-url",SOURCE,"--file",str(schema)],
                 cwd=directory)
        if not schema.is_file():
            raise RuntimeError("fictional_cli_schema_export_missing")
        inspect_schema_file(schema)
        sanitize_schema(schema,sanitized)
        restore(CLONE,sanitized)
        clone=sql(CLONE,acl.ACL)
        if acl.compare_readonly_acl_observations(original,clone,expected_md5)!="acl_parity_canonical_observations_match":
            raise RuntimeError("fictional_cli_full_roundtrip_acl_diverged")

    print("PASS PG17_FICTIONAL_PINNED_CLI_ROLE_EXPORT_EXCLUDES_RESERVED_ROLE_DDL")
    print("PASS PG17_FICTIONAL_PINNED_CLI_RESERVED_MEMBERSHIP_FILTER_REPRODUCED")
    print("PASS PG17_FICTIONAL_PINNED_CLI_SCHEMA_RETAINS_FUNCTION_ACL")
    print("PASS PG17_FICTIONAL_PINNED_CLI_ROLE_THEN_SCHEMA_RESTORE_MATCHES_NINE_FIELDS")
    print("LIMIT SUPABASE_MANAGED_CLONE_NOT_YET_REPRODUCED")
    print("LIMIT REAL_CLONE_DIVERGENCE_CAUSE_NOT_IDENTIFIED")
    print("ATLAS_PRODUCTION_CHANGE=NONE")

if __name__=="__main__":
    main()

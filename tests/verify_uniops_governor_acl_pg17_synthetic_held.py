#!/usr/bin/env python3
"""Entirely fictional PG17 ACL restore acceptance; no production or signed actors."""
import os
from pathlib import Path
import subprocess
import sys
import reconcile_uniops_native_governor_acl_local_held as acl

ROOT=Path(__file__).resolve().parent
MIGRATION=ROOT.parent/"supabase/migrations/20260912203347_personal_atlas_access_grants_v1.sql"
HELPER=ROOT/"reconcile_uniops_native_governor_acl_local_held.py"
URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
RPC="public.grant_personal_atlas_access_v1(uuid,text,jsonb)"
CREATE="create or replace function public.grant_personal_atlas_access_v1("

def sql(statement):
    p=subprocess.run(["psql",URL,"-X","-At","-v","ON_ERROR_STOP=1","-c",statement],
                     text=True,capture_output=True,timeout=30,check=False)
    if p.returncode:
        raise RuntimeError("fictional local PG17 fixture refused")
    return p.stdout.strip()

def check_helper(succeed,marker):
    env={**os.environ,"ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY":"true",
         "ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true"}
    env.pop("NOEL_CORE_DATABASE_URL",None)
    env.pop("SUPABASE_SERVICE_ROLE_KEY",None)
    p=subprocess.run([sys.executable,str(HELPER),"--db-url",URL,
                      "--canonical-migration",str(MIGRATION)],
                     env=env,text=True,capture_output=True,timeout=35)
    if succeed:
        if p.returncode or marker not in p.stdout:
            raise RuntimeError("fictional PG17 ACL acceptance failed")
    elif (p.returncode==0 or
          "ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=clone_acl_nondefault_privileges" not in p.stdout
          or p.stderr):
        raise RuntimeError("fictional PG17 unexpected ACL not refused")

def main():
    if (os.environ.get("CI")!="true" or os.environ.get("GITHUB_ACTIONS")!="true"
        or os.environ.get("GITHUB_REPOSITORY")!="optical-lift/noel-core-db"
        or os.environ.get("ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")!="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("fictional PG17 environment refused")
    raw=MIGRATION.read_text(encoding="utf8")
    if raw.count(CREATE)!=1:
        raise RuntimeError("canonical fixture missing")
    part=raw.split(CREATE,1)[1]
    if "$function$;" not in part:
        raise RuntimeError("canonical fixture incomplete")
    source_function=CREATE+part.split("$function$;",1)[0]+"$function$;"
    # No Atlas rows or purchases exist. The function body is never invoked.
    sql("CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN; "
        "CREATE ROLE service_role NOLOGIN; CREATE SCHEMA IF NOT EXISTS atlas;")
    sql("SET check_function_bodies=off; "+source_function)
    initial=sql("SELECT p.proacl IS NULL,"
        "has_function_privilege('anon',p.oid,'EXECUTE'),"
        "has_function_privilege('authenticated',p.oid,'EXECUTE'),"
        "has_function_privilege('postgres',p.oid,'EXECUTE') "
        "FROM pg_proc p WHERE p.oid=to_regprocedure('"+RPC+"')")
    if initial!="t|t|t|t":
        raise RuntimeError("PostgreSQL default source ACL not reproduced")
    # Both observations are from this entirely fictional local PG17 database.
    source_md5=acl.source_fingerprint(MIGRATION)
    source_observation=sql(acl.ACL)
    check_helper(True,"PASS ATLAS_NATIVE_GOVERNOR_CLONE_ACL=EXACT_CANONICAL_FUNCTION_ACL_RESTORED")
    protected_observation=sql(acl.ACL)
    if (acl.compare_readonly_acl_observations(
            source_observation,protected_observation,source_md5)
            !="acl_parity_clone_canonical_source_not"):
        raise RuntimeError("fictional source/clone canonical transition misclassified")
    if (acl.compare_readonly_acl_observations(
            protected_observation,protected_observation,source_md5)
            !="acl_parity_canonical_observations_match"):
        raise RuntimeError("fictional protected parity misclassified")
    after=sql("SELECT "
        "has_function_privilege('anon',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('authenticated',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('service_role',to_regprocedure('"+RPC+"'),'EXECUTE')")
    if after!="f|f|t":
        raise RuntimeError("canonical deny/allow postconditions failed")
    check_helper(True,"PASS ATLAS_NATIVE_GOVERNOR_CLONE_ACL=ALREADY_PROTECTED")
    sql("GRANT EXECUTE ON FUNCTION "+RPC+" TO anon;")
    if (acl.compare_readonly_acl_observations(
            protected_observation,sql(acl.ACL),source_md5)
            !="acl_parity_clone_differs_from_canonical_source"):
        raise RuntimeError("fictional unwanted grant divergence misclassified")
    check_helper(False,"")
    forbidden=sql("SELECT "
        "has_function_privilege('anon',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('authenticated',to_regprocedure('"+RPC+"'),'EXECUTE')")
    if forbidden!="t|f":
        raise RuntimeError("refused unexpected ACL was modified")
    # The four named-role booleans would all look correct if an unrelated
    # fictional role had EXECUTE. Guard the full explicit ACL, not just them.
    sql("REVOKE EXECUTE ON FUNCTION "+RPC+" FROM anon; "
        "CREATE ROLE fictional_extra_execute NOLOGIN; "
        "GRANT EXECUTE ON FUNCTION "+RPC+" TO fictional_extra_execute;")
    subset=sql("SELECT "
        "has_function_privilege('anon',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('authenticated',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('postgres',to_regprocedure('"+RPC+"'),'EXECUTE'),"
        "has_function_privilege('service_role',to_regprocedure('"+RPC+"'),'EXECUTE')")
    if subset!="f|f|t|t":
        raise RuntimeError("fictional additional grantee test not isolated")
    check_helper(False,"")
    still=sql("SELECT has_function_privilege("
        "'fictional_extra_execute',to_regprocedure('"+RPC+"'),'EXECUTE')")
    if still!="t":
        raise RuntimeError("fictional extra grant was silently changed")
    sql("REVOKE EXECUTE ON FUNCTION "+RPC+" FROM fictional_extra_execute;")
    check_helper(True,"PASS ATLAS_NATIVE_GOVERNOR_CLONE_ACL=ALREADY_PROTECTED")
    # service_role must not be able to delegate its EXECUTE to new roles.
    sql("GRANT EXECUTE ON FUNCTION "+RPC+" TO service_role WITH GRANT OPTION;")
    check_helper(False,"")
    sql("REVOKE GRANT OPTION FOR EXECUTE ON FUNCTION "+RPC+" FROM service_role;")
    check_helper(True,"PASS ATLAS_NATIVE_GOVERNOR_CLONE_ACL=ALREADY_PROTECTED")
    print("PASS PG17_SYNTHETIC_READONLY_ACL_PARITY_CLASSIFICATION")
    print("PASS PG17_SYNTHETIC_EXTRA_ROLE_EXECUTE_REFUSED_UNCHANGED")
    print("PASS PG17_SYNTHETIC_SERVICE_ROLE_GRANT_OPTION_REFUSED")
    print("PASS PG17_SYNTHETIC_DEFAULT_FUNCTION_ACL_RESTORED_EXACTLY")
    print("PASS PG17_SYNTHETIC_ALREADY_PROTECTED_NOOP")
    print("PASS PG17_SYNTHETIC_UNEXPECTED_ACL_REFUSED_UNCHANGED")
    print("ATLAS_PRODUCTION_CHANGE=NONE")

if __name__=="__main__":
    main()

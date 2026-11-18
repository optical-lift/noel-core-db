#!/usr/bin/env python3
"""HELD fictional governor: restore canonical function ACL ONLY in disposable clone.

This is not a migration or a license grant. It never contacts production,
copies production rows, prints private ACL state, or changes public API rights.
Fail closed unless the clone has exactly PostgreSQL's default PUBLIC EXECUTE
state for the original source-matched function, or is already protected.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess

RPC="public.grant_personal_atlas_access_v1(uuid,text,jsonb)"
MIGRATION="20260912203347_personal_atlas_access_grants_v1.sql"
SOURCE_BLOB="d6ce8f5e7422e36a4b5352007a32d82ae29d6d4c"
REVOKE="revoke all on function public.grant_personal_atlas_access_v1(uuid,text,jsonb) from public, anon, authenticated;"
GRANT="grant execute on function public.grant_personal_atlas_access_v1(uuid,text,jsonb) to service_role;"
WHO="SELECT current_user,current_database(),pg_is_in_recovery()"
ACL=(
    "SELECT pg_get_userbyid(p.proowner),p.prosecdef,md5(p.prosrc),"
    "(p.proacl IS NULL),"
    "has_function_privilege('anon',p.oid,'EXECUTE'),"
    "has_function_privilege('authenticated',p.oid,'EXECUTE'),"
    "has_function_privilege('postgres',p.oid,'EXECUTE'),"
    "has_function_privilege('service_role',p.oid,'EXECUTE') "
    "FROM pg_proc p WHERE p.oid=to_regprocedure('"+RPC+"')"
)

REFUSAL_STAGES=frozenset(['clone_acl_environment_refused','clone_acl_source_refused','clone_acl_principal_refused','clone_acl_probe_refused','clone_acl_function_missing','clone_acl_owner_mismatch','clone_acl_security_mismatch','clone_acl_body_mismatch','clone_acl_nondefault_privileges','clone_acl_default_privileges','clone_acl_transaction_refused','clone_acl_postcondition_refused','clone_acl_unknown_refused'])

def classify_refusal(snapshot,source_md5):
    """Return only a finite safe enum; never return observed ACL fields."""
    if not isinstance(snapshot,str):
        return "clone_acl_probe_refused"
    if not snapshot:
        return "clone_acl_function_missing"
    fields=snapshot.split("|")
    if len(fields)!=8:
        return "clone_acl_probe_refused"
    owner,definer,body,is_default,anon,authenticated,postgres,service=fields
    if owner!="postgres":
        return "clone_acl_owner_mismatch"
    if definer!="t":
        return "clone_acl_security_mismatch"
    if body!=source_md5:
        return "clone_acl_body_mismatch"
    if any(x not in ("t","f") for x in (is_default,anon,authenticated,postgres,service)):
        return "clone_acl_probe_refused"
    if is_default=="f":
        return "clone_acl_nondefault_privileges"
    return "clone_acl_default_privileges"

def local_only(url):
    return bool(re.fullmatch(
        r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
        url or ""))

def source_fingerprint(path):
    p=Path(path)
    if p.name!=MIGRATION or not p.is_file() or p.is_symlink() or p.stat().st_size>10000:
        raise ValueError("canonical migration unavailable")
    data=p.read_bytes()
    blob=hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
    if blob!=SOURCE_BLOB:
        raise ValueError("canonical migration source changed")
    source=data.decode("utf8")
    if source.count(REVOKE)!=1 or source.count(GRANT)!=1:
        raise ValueError("canonical migration ACL not exact")
    prefix="create or replace function public.grant_personal_atlas_access_v1("
    if source.count(prefix)!=1:
        raise ValueError("canonical function source not exact")
    tail=source.split(prefix,1)[1]
    if tail.count("as $function$")<1 or "$function$;" not in tail:
        raise ValueError("canonical function body unavailable")
    body=tail.split("as $function$",1)[1].split("$function$;",1)[0]
    if not body.strip().startswith("declare") or not body.strip().endswith("end;"):
        raise ValueError("canonical function source unexpected")
    return hashlib.md5(body.encode("utf8")).hexdigest()

def classify(snapshot,body_md5):
    fields=snapshot.split("|")
    if len(fields)!=8:
        return "refused"
    owner,definer,body,is_default,anon,authenticated,postgres,service=fields
    if owner!="postgres" or definer!="t" or body!=body_md5:
        return "refused"
    if any(x not in ("t","f") for x in (is_default,anon,authenticated,postgres,service)):
        return "refused"
    if (anon,authenticated,postgres,service)==("f","f","t","t"):
        return "protected"
    if (is_default,anon,authenticated,postgres,service)==("t","t","t","t","t"):
        return "default_public_execute"
    return "refused"

def guarded_sql(body_md5):
    if not re.fullmatch(r"[0-9a-f]{32}",body_md5):
        raise ValueError("invalid source fingerprint")
    before=(
        "SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('"+RPC+"') "
        "AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef "
        "AND md5(p.prosrc)='"+body_md5+"' AND p.proacl IS NULL "
        "AND has_function_privilege('anon',p.oid,'EXECUTE') "
        "AND has_function_privilege('authenticated',p.oid,'EXECUTE') "
        "AND has_function_privilege('postgres',p.oid,'EXECUTE') "
        "AND has_function_privilege('service_role',p.oid,'EXECUTE')"
    )
    after=(
        "SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('"+RPC+"') "
        "AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef "
        "AND md5(p.prosrc)='"+body_md5+"' "
        "AND NOT has_function_privilege('anon',p.oid,'EXECUTE') "
        "AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') "
        "AND has_function_privilege('postgres',p.oid,'EXECUTE') "
        "AND has_function_privilege('service_role',p.oid,'EXECUTE')"
    )
    # One local transaction. Both guards are inside the transaction; failure
    # rolls back even the function-specific ACL statements.
    return (
        "DO $clone_acl_guard$ BEGIN "
        "IF current_user <> 'postgres' OR current_database() <> 'postgres' "
        "OR pg_is_in_recovery() OR NOT EXISTS ("+before+") "
        "THEN RAISE EXCEPTION 'disposable source ACL precondition refused'; END IF; "
        "END $clone_acl_guard$;\n"
        + REVOKE + "\n" + GRANT + "\n"
        + "DO $clone_acl_guard$ BEGIN IF NOT EXISTS ("+after+") "
        "THEN RAISE EXCEPTION 'disposable source ACL postcondition refused'; END IF; "
        "END $clone_acl_guard$;"
    )

def psql(url,statement,transaction=False):
    command=["psql",url,"-X","-At","-v","ON_ERROR_STOP=1"]
    if transaction:
        command.append("--single-transaction")
    command.extend(["-c",statement])
    result=subprocess.run(command,text=True,capture_output=True,timeout=25,check=False)
    if result.returncode!=0:
        raise ValueError("private local SQL refused")
    return result.stdout.strip()

def reconcile(url,migration):
    if not local_only(url):
        raise ValueError("clone_acl_environment_refused")
    required={
        "CI":"true", "GITHUB_ACTIONS":"true",
        "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
        "ATLAS_NATIVE_NOTEBOOK_FICTIONAL_ONLY":"true",
        "ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED":"true",
    }
    if (any(os.environ.get(k)!=v for k,v in required.items())
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise ValueError("clone_acl_environment_refused")
    try:
        md5=source_fingerprint(migration)
    except (ValueError,OSError,UnicodeError):
        raise ValueError("clone_acl_source_refused") from None
    try:
        who=psql(url,WHO)
    except (ValueError,subprocess.SubprocessError,OSError):
        raise ValueError("clone_acl_probe_refused") from None
    if who!="postgres|postgres|f":
        raise ValueError("clone_acl_principal_refused")
    try:
        snapshot=psql(url,ACL)
    except (ValueError,subprocess.SubprocessError,OSError):
        raise ValueError("clone_acl_probe_refused") from None
    observed=classify(snapshot,md5)
    if observed=="protected":
        return "ALREADY_PROTECTED"
    if observed!="default_public_execute":
        raise ValueError(classify_refusal(snapshot,md5))
    try:
        psql(url,guarded_sql(md5),transaction=True)
    except (ValueError,subprocess.SubprocessError,OSError):
        raise ValueError("clone_acl_transaction_refused") from None
    try:
        post=psql(url,ACL)
    except (ValueError,subprocess.SubprocessError,OSError):
        raise ValueError("clone_acl_probe_refused") from None
    if classify(post,md5)!="protected":
        raise ValueError("clone_acl_postcondition_refused")
    return "EXACT_CANONICAL_FUNCTION_ACL_RESTORED"

def main():
    a=argparse.ArgumentParser()
    a.add_argument("--db-url",required=True)
    a.add_argument("--canonical-migration",required=True)
    args=a.parse_args()
    try:
        outcome=reconcile(args.db_url,args.canonical_migration)
    except Exception as exc:
        # No SQL, role ACL, credentials, exception messages or query bodies.
        stage=str(exc)
        if stage not in REFUSAL_STAGES:
            stage="clone_acl_unknown_refused"
        print("BLOCKED ATLAS_NATIVE_GOVERNOR_CLONE_ACL=NOT_VERIFIED")
        print("ATLAS_NATIVE_GOVERNOR_GRANT_STAGE="+stage)
        raise SystemExit(1)
    print("PASS ATLAS_NATIVE_GOVERNOR_CLONE_ACL="+outcome)
    print("ATLAS_PRODUCTION_CHANGE=NONE")

if __name__=="__main__":
    main()

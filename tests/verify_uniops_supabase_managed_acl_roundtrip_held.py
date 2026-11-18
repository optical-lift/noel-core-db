#!/usr/bin/env python3
"""Entirely fictional Supabase-managed local DB restore observation.

Runs the same checked-out CLI v2.116.0 and an isolated, randomly named
managed local PostgreSQL container. NEVER calls production, never imports
real Atlas data and never modifies any source/grant outside the container.
The synthetic source is the distinct PostgreSQL 17 test service.
"""
import os
import subprocess
from pathlib import Path
import shutil
import tempfile

import reconcile_uniops_native_governor_acl_local_held as acl
import inspect_uniops_acl_readonly_source_clone_held as inspector
import verify_uniops_pg17_cli_role_schema_roundtrip_held as fake

CANONICAL=Path(__file__).resolve().parent.parent/"supabase/migrations"/acl.MIGRATION
ALLOWED=frozenset((
    "acl_parity_canonical_observations_match",
    "acl_parity_clone_differs_from_canonical_source",
))

def fictional_clone_only_rebalance(local,digest):
    """An atomic TEST-ONLY local grant reduction for exactly one function.

    It is NOT callable by production controller or runtime. Requires that
    EVERY extra explicit EXECUTE grantee was inherited from the target's
    existing postgres default-function ACL and that none can delegate.
    Unexpected grantees, grant options, missing source/owner/security/body,
    or failed final rights -> whole one-statement DO transaction rolls back.
    """
    if (not acl.local_only(local) or not os.environ.get(
            "ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")=="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("fictional_managed_rebalance_environment_refused")
    if not isinstance(digest,str) or len(digest)!=32 or any(
            c not in "0123456789abcdef" for c in digest):
        raise RuntimeError("fictional_managed_rebalance_source_refused")
    sql=("""
DO $fictional_acl$ DECLARE g record; BEGIN
IF current_user <> 'postgres' OR current_database() <> 'postgres'
   OR pg_is_in_recovery() THEN
  RAISE EXCEPTION 'fictional local identity refused';
END IF;
IF NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
   AND pg_get_userbyid(p.proowner)='postgres'
   AND p.prosecdef AND md5(p.prosrc)='__MD5__'
   AND p.proacl IS NOT NULL
   AND has_function_privilege('anon',p.oid,'EXECUTE')
   AND has_function_privilege('authenticated',p.oid,'EXECUTE')
   AND has_function_privilege('postgres',p.oid,'EXECUTE')
   AND has_function_privilege('service_role',p.oid,'EXECUTE')
) THEN RAISE EXCEPTION 'fictional source/rights refused'; END IF;
-- Reject any noncanonical explicit grant that is not independently found
-- as a function EXECUTE privilege in the *preexisting managed* defaults.
IF EXISTS (
 SELECT 1 FROM pg_catalog.pg_proc p,
      LATERAL pg_catalog.aclexplode(p.proacl) a
 WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
   AND a.privilege_type='EXECUTE'
   AND (a.grantee NOT IN (p.proowner,'service_role'::regrole)
        AND (a.is_grantable OR NOT EXISTS (
          SELECT 1 FROM pg_catalog.pg_default_acl d,
               LATERAL pg_catalog.aclexplode(d.defaclacl) dacl
          WHERE d.defaclrole='postgres'::regrole
            AND d.defaclobjtype='f'
            AND d.defaclnamespace IN (0,p.pronamespace)
            AND dacl.privilege_type='EXECUTE'
            AND dacl.grantee=a.grantee
            AND NOT dacl.is_grantable))
       OR (a.grantee='service_role'::regrole AND a.is_grantable))
) THEN RAISE EXCEPTION 'fictional unknown grantee refused'; END IF;
FOR g IN
 SELECT DISTINCT a.grantee AS oid
 FROM pg_catalog.pg_proc p,
      LATERAL pg_catalog.aclexplode(p.proacl) a
 WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
   AND a.privilege_type='EXECUTE'
   AND a.grantee NOT IN (p.proowner,'service_role'::regrole)
LOOP
 EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_personal_atlas_access_v1(uuid,text,jsonb) FROM ' ||
   CASE WHEN g.oid=0 THEN 'PUBLIC'
        ELSE pg_catalog.quote_ident(pg_catalog.pg_get_userbyid(g.oid)) END;
END LOOP;
IF NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_proc p
 WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
   AND pg_get_userbyid(p.proowner)='postgres'
   AND p.prosecdef AND md5(p.prosrc)='__MD5__'
   AND NOT (p.proacl IS NULL)
   AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
   AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
   AND has_function_privilege('postgres',p.oid,'EXECUTE')
   AND has_function_privilege('service_role',p.oid,'EXECUTE')
   AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.aclexplode(p.proacl) a
    WHERE a.privilege_type='EXECUTE'
      AND (a.grantee NOT IN (p.proowner,'service_role'::regrole)
           OR (a.grantee='service_role'::regrole AND a.is_grantable)))
) THEN RAISE EXCEPTION 'fictional postcondition refused'; END IF;
END $fictional_acl$;
""").replace("__MD5__",digest)
    # DO is one PostgreSQL statement: any raised failure atomically rolls
    # back all function-specific REVOKEs on this *local* disposable clone.
    attempt=subprocess.run(
        ["psql",local,"-X","-At","-v","ON_ERROR_STOP=1","-c",sql],
        text=True,capture_output=True,stdin=subprocess.DEVNULL,
        check=False,timeout=45)
    if attempt.returncode:
        # The local fictional SQL error is never printed. Only a fixed
        # finite code, safe for public CI, leaves this function.
        categories=(
            ("fictional local identity refused","local_identity_refused"),
            ("fictional source/rights refused","source_rights_refused"),
            ("fictional unknown grantee refused","unknown_grantee_refused"),
            ("fictional postcondition refused","postcondition_refused"),
            ("syntax error","syntax_refused"),
            ("does not exist","missing_object_refused"),
        )
        category=next((name for fragment,name in categories
                       if fragment in attempt.stderr),"other_local_refusal")
        raise RuntimeError("fictional_rebalance_"+category)

def run():
    if (os.environ.get("CI")!="true"
        or os.environ.get("GITHUB_ACTIONS")!="true"
        or os.environ.get("GITHUB_REPOSITORY")!="optical-lift/noel-core-db"
        or os.environ.get("ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")!="true"
        or os.environ.get("NOEL_CORE_DATABASE_URL")
        or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")):
        raise RuntimeError("fictional_managed_environment_refused")
    if fake.command(["supabase","--version"]).splitlines()[-1]!="2.116.0":
        raise RuntimeError("fictional_managed_cli_version_refused")
    digest=acl.source_fingerprint(CANONICAL)
    source=fake.sql(fake.SOURCE,acl.ACL)
    if acl.classify(source,digest)!="protected":
        raise RuntimeError("fictional_managed_canonical_source_refused")

    with tempfile.TemporaryDirectory(prefix="uniops-managed-solely-fictional-") as d:
        root=Path(d)
        roles=root/"roles.sql"
        schema=root/"schema.sql"
        clean=root/"schema-restorable.sql"
        project=root/"local"
        project.mkdir(mode=0o700)
        # Mirror the precise role-only then schema-only source export used
        # by the protected inspector; there are no source data rows.
        fake.command(["supabase","init","--force"],cwd=root,timeout=60)
        fake.command(["supabase","db","dump","--db-url",fake.SOURCE,
                      "--role-only","--file",str(roles)],cwd=root)
        fake.inspect_roles_file(roles)
        fake.command(["supabase","db","dump","--db-url",fake.SOURCE,
                      "--file",str(schema)],cwd=root)
        fake.inspect_schema_file(schema)
        inspector.sanitize_schema(schema,clean)
        port=inspector.isolated_port()
        local=f"postgresql://postgres:postgres@127.0.0.1:{port}/postgres"
        started=False
        try:
            inspector.setup_local(project,port)
            started=True
            # Only aggregate Boolean info about this entire fictional
            # local target; never report raw ACL/identities.
            defaults=fake.sql(local,
                "SELECT EXISTS (SELECT 1 FROM pg_default_acl "
                "WHERE defaclrole='postgres'::regrole AND defaclobjtype='f')")
            if defaults not in ("t","f"):
                raise RuntimeError("fictional_managed_default_acl_probe_refused")
            if fake.sql(local,"SELECT to_regprocedure('"+acl.RPC+"') IS NULL")!="t":
                raise RuntimeError("fictional_managed_clone_preexisting_function")
            inspector.restore_local(local,roles,clean)
            clone=fake.sql(local,acl.ACL)
            result=acl.compare_readonly_acl_observations(source,clone,digest)
            if result not in ALLOWED:
                raise RuntimeError("fictional_managed_clone_source_unverified")
            # Only immutable named observation indices are emitted from this
            # fictional local database. No raw ACL, principal names beyond
            # the public four canonical role categories, or SQL leaves CI.
            if not acl._verified_acl_observation(clone,digest):
                raise RuntimeError("fictional_managed_clone_identity_refused")
            names=("default_acl","anon_exec","authenticated_exec",
                   "postgres_exec","service_exec","explicit_grantees_confined")
            source_fields=source.split("|")
            clone_fields=clone.split("|")
            if source_fields[:3]!=clone_fields[:3] or len(clone_fields)!=9:
                raise RuntimeError("fictional_managed_core_identity_changed")
            differing=tuple(names[i] for i in range(len(names))
                            if source_fields[i+3]!=clone_fields[i+3])
            if not differing or result!="acl_parity_clone_differs_from_canonical_source":
                raise RuntimeError("fictional_managed_unexpected_parity")
            print("PG17_FICTIONAL_MANAGED_ACL_MISMATCH_FIELDS="+",".join(differing))
            # Aggregate-only fictional provenance check: distinguish
            # postgres GLOBAL defaults, PUBLIC-SCHEMA defaults, and
            # explicit grants not explained by either. These counts are
            # not ACL identities and are never obtained from production.
            origin=fake.sql(local,("""
SELECT count(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM pg_catalog.pg_default_acl d,
         LATERAL pg_catalog.aclexplode(d.defaclacl) da
    WHERE d.defaclrole='postgres'::regrole
      AND d.defaclobjtype='f' AND d.defaclnamespace=0
      AND da.grantee=a.grantee AND da.privilege_type='EXECUTE'
)),
count(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM pg_catalog.pg_default_acl d,
         LATERAL pg_catalog.aclexplode(d.defaclacl) da
    WHERE d.defaclrole='postgres'::regrole
      AND d.defaclobjtype='f' AND d.defaclnamespace=p.pronamespace
      AND da.grantee=a.grantee AND da.privilege_type='EXECUTE'
)),
count(*) FILTER (WHERE NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_default_acl d,
         LATERAL pg_catalog.aclexplode(d.defaclacl) da
    WHERE d.defaclrole='postgres'::regrole
      AND d.defaclobjtype='f'
      AND d.defaclnamespace IN (0,p.pronamespace)
      AND da.grantee=a.grantee AND da.privilege_type='EXECUTE'
)),
count(*)
FROM pg_catalog.pg_proc p,
     LATERAL pg_catalog.aclexplode(p.proacl) a
WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
  AND a.privilege_type='EXECUTE'
  AND a.grantee NOT IN (p.proowner,'service_role'::regrole)
""").strip())
            numbers=origin.split("|")
            if len(numbers)!=4 or any(not n.isdigit() or len(n)>3 for n in numbers):
                raise RuntimeError("fictional_default_origin_probe_refused")
            print("PG17_FICTIONAL_MANAGED_EXTRA_EXECUTE_DEFAULT_ORIGIN_COUNTS="+
                  ",".join(numbers))
            print("PG17_FICTIONAL_MANAGED_BEFORE_RESTORE_POSTGRES_DEFAULT_FUNCTION_ACL="+(
                "PRESENT" if defaults=="t" else "ABSENT"))
            print("PG17_FICTIONAL_MANAGED_CLONE_ACL_OBSERVATION="+result)
            # Construct a deliberate unknown role grant. It MUST be refused
            # by the correction without modifying the ACL, even though the
            # basic nine-field observation still fits the managed mismatch.
            unknown="fictional_unknown_acl_grantee"
            fake.sql(local,"CREATE ROLE "+unknown+" NOLOGIN; "
                           "GRANT EXECUTE ON FUNCTION "+acl.RPC+
                           " TO "+unknown+";")
            poisoned=fake.sql(local,acl.ACL)
            if (acl.compare_readonly_acl_observations(
                source,poisoned,digest)
                    !="acl_parity_clone_differs_from_canonical_source"):
                raise RuntimeError("fictional_unknown_grant_fixture_not_valid")
            try:
                fictional_clone_only_rebalance(local,digest)
            except RuntimeError:
                pass
            else:
                raise RuntimeError("fictional_unknown_grantee_not_refused")
            if fake.sql(local,acl.ACL)!=poisoned:
                raise RuntimeError("fictional_refused_acl_was_modified")
            # Remove only the deliberately inserted fictional poison before
            # testing the managed-default-only case.
            fake.sql(local,"REVOKE EXECUTE ON FUNCTION "+acl.RPC+
                           " FROM "+unknown+";")
            if fake.sql(local,acl.ACL)!=clone:
                raise RuntimeError("fictional_poison_cleanup_not_exact")
            # Independently refuse a delegable managed service_role grant.
            # Do not broaden that grant or mutate its option on refusal.
            fake.sql(local,"GRANT EXECUTE ON FUNCTION "+acl.RPC+
                           " TO service_role WITH GRANT OPTION;")
            delegable=fake.sql(local,acl.ACL)
            try:
                fictional_clone_only_rebalance(local,digest)
            except RuntimeError:
                pass
            else:
                raise RuntimeError("fictional_delegable_service_grant_not_refused")
            if fake.sql(local,acl.ACL)!=delegable:
                raise RuntimeError("fictional_refused_service_grant_was_modified")
            fake.sql(local,"REVOKE GRANT OPTION FOR EXECUTE ON FUNCTION "+
                           acl.RPC+" FROM service_role;")
            if fake.sql(local,acl.ACL)!=clone:
                raise RuntimeError("fictional_service_option_cleanup_not_exact")
            fictional_clone_only_rebalance(local,digest)
            corrected=fake.sql(local,acl.ACL)
            if (acl.compare_readonly_acl_observations(source,corrected,digest)
                    !="acl_parity_canonical_observations_match"):
                raise RuntimeError("fictional_local_correction_not_canonical")
            print("PASS PG17_FICTIONAL_UNKNOWN_GRANTEE_REFUSED_WITHOUT_MUTATION")
            print("PASS PG17_FICTIONAL_SERVICE_GRANT_OPTION_REFUSED_WITHOUT_MUTATION")
            print("PASS PG17_FICTIONAL_DEFAULT_ONLY_FUNCTION_ACL_CORRECTED_IN_LOCAL_CLONE")
            print("LIMIT TEST_ONLY_LOCAL_REBALANCE_NEVER_USED_IN_PROTECTED_CONTROLLER")
        finally:
            # Source/target outputs are TEMP only and never uploaded.
            # Regardless of outcome, remove container and its volume.
            if (project/"supabase").exists():
                stop=inspector.run_silent(["supabase","stop","--no-backup"],
                                           cwd=project,timeout=180)
                if not stop and started:
                    raise RuntimeError("fictional_managed_clone_cleanup_refused")
    print("LIMIT MANAGED_FICTIONAL_ACL_DOES_NOT_IDENTIFY_ACTUAL_2852_MISMATCH")
    print("ATLAS_PRODUCTION_CHANGE=NONE")

if __name__=="__main__":
    run()

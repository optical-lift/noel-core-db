#!/usr/bin/env python3
"""Entirely fictional Supabase-managed local DB restore observation.

Runs the same checked-out CLI v2.116.0 and an isolated, randomly named
managed local PostgreSQL container. NEVER calls production, never imports
real Atlas data and never modifies any source/grant outside the container.
The synthetic source is the distinct PostgreSQL 17 test service.
"""
import os
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
            print("PG17_FICTIONAL_MANAGED_BEFORE_RESTORE_POSTGRES_DEFAULT_FUNCTION_ACL="+(
                "PRESENT" if defaults=="t" else "ABSENT"))
            print("PG17_FICTIONAL_MANAGED_CLONE_ACL_OBSERVATION="+result)
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

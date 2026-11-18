#!/usr/bin/env python3
"""HELD #2859: separately approved, single-use READ-ONLY ACL staged inspection.

This source cannot authorize itself; an independent, reviewed, one-shot
issue-title controller plus protected environment must succeed before any
production credential can reach this process. Never import or run it from
the consumed #2852 workflow. No ACL mutation or signed Work journey exists.
Only a source-owned pg_catalog SELECT and schema/role-only dumps touch the
live database. All restore statements target a disposable localhost clone.
Private outputs are suppressed and deleted, including after a failure.
"""
import os
from pathlib import Path
import re
import shutil
import tempfile
from urllib.parse import urlsplit

import inspect_uniops_acl_readonly_source_clone_held as prior
import inspect_uniops_acl_staged_local_held as local
import reconcile_uniops_native_governor_acl_local_held as acl

PROJECT_REF="zirqkouammpwxlqfbsvf"
GATE="UNI_OPS_STAGED_READONLY_2859_APPROVED"
EXPECTED={"CI":"true","GITHUB_ACTIONS":"true",
          "GITHUB_REPOSITORY":"optical-lift/noel-core-db",
          GATE:"true"}
SUCCESS=frozenset((
    "stage_canonical_match",
    "stage_default_compatible_not_provenance",
    "stage_default_drift_ambiguous",
))
REFUSALS=frozenset((
    "stage_inspect_environment_refused",
    "stage_inspect_source_refused",
    "stage_inspect_live_probe_refused",
    "stage_inspect_source_drift_refused",
    "stage_inspect_snapshot_refused",
    "stage_inspect_local_start_refused",
    "stage_inspect_cleanup_refused",
    "stage_inspect_unknown_refused",
    "stage_local_catalog_refused",
    "stage_local_restore_refused",
    "stage_local_file_refused",
    "stage_local_identity_refused",
    "stage_local_source_refused",
    "stage_local_preexisting_target_refused",
    "stage_local_after_roles_target_refused",
    "stage_source_unverified",
    "stage_preexisting_target_refused",
    "stage_target_missing_refused",
    "stage_metadata_refused",
    "stage_extra_unknown_refused",
    "stage_delegable_refused",
    "stage_other_mismatch_refused",
))

class Refused(Exception):
    pass


def require_environment(env):
    if (any(env.get(k)!=v for k,v in EXPECTED.items())
        or env.get("SUPABASE_SERVICE_ROLE_KEY")
        or env.get("ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED")
        or env.get("ATLAS_GOVERNOR_PG17_SYNTHETIC_ENABLED")
        or env.get("UNI_OPS_READONLY_ACL_2848_APPROVED")):
        raise Refused("stage_inspect_environment_refused")
    temp=env.get("RUNNER_TEMP","")
    if (not isinstance(temp,str) or not os.path.isabs(temp)
        or not Path(temp).is_dir() or Path(temp).is_symlink()):
        raise Refused("stage_inspect_environment_refused")
    raw=env.get("NOEL_CORE_DATABASE_URL","")
    try:
        p=urlsplit(raw)
        allowed_hostname=p.hostname=="db."+PROJECT_REF+".supabase.co"
        allowed_pooler=(p.username or "").endswith("."+PROJECT_REF)
        if (p.scheme not in ("postgres","postgresql") or not p.password
            or not (allowed_hostname or allowed_pooler)
            or not p.hostname or p.hostname in ("localhost","127.0.0.1")):
            raise Refused("stage_inspect_environment_refused")
    except (TypeError,ValueError):
        raise Refused("stage_inspect_environment_refused") from None
    return raw,Path(temp)


def source_snapshot(live):
    # The exact pinned original static SELECT is read-only at the connection
    # layer; this module never accepts a SQL argument from a caller.
    try:
        return prior.catalog_snapshot(live,read_only=True)
    except Exception:
        raise Refused("stage_inspect_live_probe_refused") from None


def source_fingerprint():
    canonical=(Path(__file__).resolve().parent.parent/
               "supabase/migrations"/acl.MIGRATION)
    try:
        return acl.source_fingerprint(canonical)
    except (ValueError,OSError,UnicodeError):
        raise Refused("stage_inspect_source_refused") from None


def private_file(path):
    # The local reader rejects unsafe files before any localhost write.
    try:
        obj=Path(path)
        stat=obj.lstat()
        if (obj.is_symlink() or not obj.is_file() or stat.st_size<=0
            or stat.st_size>100_000_000 or stat.st_mode & 0o077):
            raise Refused("stage_inspect_snapshot_refused")
    except (OSError,ValueError,TypeError):
        raise Refused("stage_inspect_snapshot_refused") from None


def inspect():
    live,temp=require_environment(os.environ)
    digest=source_fingerprint()
    root=None
    project=None
    status="stage_inspect_unknown_refused"
    try:
        root=Path(tempfile.mkdtemp(prefix="uniops-staged-2859-",dir=temp))
        os.chmod(root,0o700)
        project=root/"local"
        project.mkdir(mode=0o700)
        source=source_snapshot(live)
        if not acl._verified_acl_observation(source,digest) or acl.classify(source,digest)!="protected":
            raise Refused("stage_source_unverified")

        roles=root/"roles.sql"
        schema=root/"schema.sql"
        clean=root/"schema-restorable.sql"
        if not prior.run_silent(
            ["supabase","db","dump","--db-url",live,
             "--role-only","--file",str(roles)],timeout=300):
            raise Refused("stage_inspect_snapshot_refused")
        if not prior.run_silent(
            ["supabase","db","dump","--db-url",live,
             "--file",str(schema)],timeout=300):
            raise Refused("stage_inspect_snapshot_refused")
        private_file(roles)
        private_file(schema)
        prior.sanitize_schema(schema,clean)
        private_file(clean)
        # Detect live drift before using any clone metadata.
        if source_snapshot(live)!=source:
            raise Refused("stage_inspect_source_drift_refused")

        port=prior.isolated_port()
        prior.setup_local(project,port)
        clone=f"postgresql://postgres:postgres@127.0.0.1:{port}/postgres"
        decision=local.inspect_staged_local(clone,roles,clean,source,digest)
        if decision.verdict not in SUCCESS:
            raise Refused(decision.verdict)
        status=decision.safe_line()
    except Refused as e:
        status=str(e) if str(e) in REFUSALS else "stage_inspect_unknown_refused"
    except local.StageRefused as e:
        status=str(e) if str(e) in REFUSALS else "stage_inspect_unknown_refused"
    except prior.Refused:
        status="stage_inspect_snapshot_refused"
    except Exception:
        status="stage_inspect_unknown_refused"
    finally:
        cleanup_ok=True
        if project is not None and (project/"supabase").exists():
            if not prior.run_silent(
                ["supabase","stop","--no-backup"],
                cwd=project,timeout=120):
                cleanup_ok=False
        if root is not None:
            try:
                shutil.rmtree(root)
            except OSError:
                cleanup_ok=False
        if not cleanup_ok:
            status="stage_inspect_cleanup_refused"
    return status


def main():
    previous_umask=os.umask(0o077)
    try:
        try:
            status=inspect()
        except Exception:
            status="stage_inspect_unknown_refused"
    finally:
        os.umask(previous_umask)

    # Never print the source query, credential, raw ACL, names, raw exception,
    # or private dump. Only fixed names from the pure classifier are accepted.
    if status.startswith("UNI_OPS_STAGE_VERDICT="):
        code=status.split(";",1)[0].split("=",1)[1]
        if code not in SUCCESS or not re.fullmatch(
            r"UNI_OPS_STAGE_VERDICT=stage_[a-z_]+;DIFF=(?:none|[a-z_,]+);ROLE_DEFAULT_CHANGE=(?:true|false);SCHEMA_DEFAULT_CHANGE=(?:true|false)",
            status):
            status="stage_inspect_unknown_refused"
    elif status not in REFUSALS:
        status="stage_inspect_unknown_refused"
    print("UNI_OPS_2859_READONLY_STAGE="+status,flush=True)
    print("UNI_OPS_PRODUCTION_CHANGE=NONE",flush=True)
    print("UNI_OPS_SIGNED_WORK_JOURNEY=NOT_RUN",flush=True)
    return 0 if status.startswith("UNI_OPS_STAGE_VERDICT=") else 1


if __name__=="__main__":
    raise SystemExit(main())

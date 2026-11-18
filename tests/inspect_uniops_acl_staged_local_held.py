#!/usr/bin/env python3
"""HELD local-only role/schema staged ACL inspection adapter.

This module has NO live source connection, no secrets, no controller, no
authorization trigger, no repair SQL, and no runnable main. A future distinct
owner-approved controller must separately provide a canonical source
observation and private CLI-generated role/schema files. It must clean the
disposable clone even after failures. Never call on production.
"""
import os
from pathlib import Path
import subprocess

import reconcile_uniops_native_governor_acl_local_held as acl
import inspect_uniops_acl_readonly_source_clone_held as prior
import uniops_acl_stage_observations_held as stage

# Errors are finite, nonprivate categories; no subprocess output is exposed.
class StageRefused(Exception):
    pass


def local_catalog(url, query):
    """Only two immutable SELECT forms plus the pinned nine-field ACL SELECT."""
    if (not acl.local_only(url)
        or query not in (acl.ACL,stage.DEFAULTS_SQL,stage.EXTRAS_SQL)
        or not query.startswith("SELECT ") or ";" in query):
        raise StageRefused("stage_local_catalog_refused")
    env=os.environ.copy()
    env["PGOPTIONS"]="-c default_transaction_read_only=on"
    try:
        p=subprocess.run(
            ["psql",url,"-X","-At","-q","-v","ON_ERROR_STOP=1","-c",query],
            env=env,stdin=subprocess.DEVNULL,text=True,capture_output=True,
            timeout=45,check=False)
    except (OSError,subprocess.SubprocessError):
        raise StageRefused("stage_local_catalog_refused") from None
    if p.returncode != 0 or len(p.stdout)>200:
        raise StageRefused("stage_local_catalog_refused")
    return p.stdout.strip()


def restore_one_local(url,file):
    """Use only private, regular preexisting files, and only localhost DB."""
    if not acl.local_only(url):
        raise StageRefused("stage_local_restore_refused")
    try:
        p=Path(file)
        stat=p.lstat()
        if (not p.is_file() or p.is_symlink() or stat.st_size<=0
            or stat.st_size>100_000_000 or stat.st_mode & 0o077):
            raise StageRefused("stage_local_file_refused")
    except (OSError,TypeError,ValueError):
        raise StageRefused("stage_local_file_refused") from None
    if not prior.run_silent(
        ["psql",url,"-X","-v","ON_ERROR_STOP=1","-f",str(p)],
        timeout=300):
        raise StageRefused("stage_local_restore_refused")


def inspect_staged_local(url,roles,schema,source,digest):
    """Inspect exactly one disposable clone. All observations stay in memory.

    No credentials or raw SQL are printed. The caller owns entire private
    temp directory, clone lifecycle and cleanup, and must preserve source
    read-only / CLI-2.116.0 / one-shot owner gate separately.
    """
    if not acl.local_only(url):
        raise StageRefused("stage_local_identity_refused")
    if not acl._verified_acl_observation(source,digest) or acl.classify(source,digest)!="protected":
        raise StageRefused("stage_local_source_refused")
    before_target=local_catalog(url,acl.ACL)
    before_defaults=local_catalog(url,stage.DEFAULTS_SQL)
    if before_target!="":
        raise StageRefused("stage_local_preexisting_target_refused")
    restore_one_local(url,roles)
    after_roles_target=local_catalog(url,acl.ACL)
    after_roles_defaults=local_catalog(url,stage.DEFAULTS_SQL)
    if after_roles_target!="":
        raise StageRefused("stage_local_after_roles_target_refused")
    restore_one_local(url,schema)
    after_schema_target=local_catalog(url,acl.ACL)
    after_schema_defaults=local_catalog(url,stage.DEFAULTS_SQL)
    after_schema_extras=local_catalog(url,stage.EXTRAS_SQL)
    decision=stage.classify_stages(
        source,before_target,after_roles_target,after_schema_target,
        before_defaults,after_roles_defaults,after_schema_defaults,
        after_schema_extras,digest)
    if decision.verdict not in (
        "stage_canonical_match",
        "stage_default_compatible_not_provenance",
        "stage_default_drift_ambiguous"):
        raise StageRefused(decision.verdict)
    return decision


if __name__=="__main__":
    raise SystemExit("HELD: no standalone or protected execution controller")

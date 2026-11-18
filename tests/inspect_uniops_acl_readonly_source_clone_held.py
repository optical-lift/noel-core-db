#!/usr/bin/env python3
"""One protected, explicitly owner-triggered metadata-only ACL comparison.

The only SQL submitted to live production is the single static pg_catalog
SELECT from the previously pinned source-owned ACL verifier. The CLI reads a
schema-only and custom-role-only snapshot, never table rows. Every schema
restore and other write is confined to a disposable localhost database.

No raw ACL result, credentials, snapshot SQL, roles or subprocess errors are
logged; all private files are removed on every normal exit. This tool never
authorizes itself: the distinct owner-approved GitHub issue event and protected
environment must pass before invocation.
"""
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

import reconcile_uniops_native_governor_acl_local_held as acl

PROJECT_REF = "zirqkouammpwxlqfbsvf"
SCHEMA_TOGGLES = re.compile(r"^\s*ALTER TABLE .+ (DISABLE|ENABLE) TRIGGER ALL;\s*$")
ALLOWED = frozenset(acl.PARITY_MARKERS) | {
    "acl_inspect_environment_refused",
    "acl_inspect_source_refused",
    "acl_inspect_live_probe_refused",
    "acl_inspect_live_drift_refused",
    "acl_inspect_snapshot_refused",
    "acl_inspect_local_start_refused",
    "acl_inspect_local_restore_refused",
    "acl_inspect_local_probe_refused",
    "acl_inspect_cleanup_refused",
    "acl_inspect_unknown_refused",
}

class Refused(Exception):
    pass

def fail(code):
    if code not in ALLOWED:
        code = "acl_inspect_unknown_refused"
    raise Refused(code)

def require_environment(env):
    required = {
        "CI": "true",
        "GITHUB_ACTIONS": "true",
        "GITHUB_REPOSITORY": "optical-lift/noel-core-db",
        "UNI_OPS_READONLY_ACL_2848_APPROVED": "true",
    }
    if any(env.get(k) != v for k, v in required.items()):
        fail("acl_inspect_environment_refused")
    if env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("ATLAS_NATIVE_GOVERNOR_CLONE_ACL_RECONCILE_ENABLED"):
        fail("acl_inspect_environment_refused")
    tmp = env.get("RUNNER_TEMP", "")
    if not tmp or not os.path.isabs(tmp) or not Path(tmp).is_dir():
        fail("acl_inspect_environment_refused")
    raw = env.get("NOEL_CORE_DATABASE_URL", "")
    try:
        p = urlsplit(raw)
        if (p.scheme not in ("postgresql", "postgres")
            or p.hostname in (None, "localhost", "127.0.0.1")
            or not p.password
            or not (p.hostname == "db." + PROJECT_REF + ".supabase.co"
                    or (p.username or "").endswith("." + PROJECT_REF))):
            fail("acl_inspect_environment_refused")
    except (ValueError, TypeError):
        fail("acl_inspect_environment_refused")
    return raw, Path(tmp)

def run_silent(cmd, *, cwd=None, env=None, timeout=240):
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=timeout, check=False)
        return p.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False

def catalog_snapshot(db_url, read_only=False):
    # This exact static SELECT is the sole SQL executed against live source.
    # Even accidental future SELECT edits cannot gain database write access.
    if not acl.ACL.startswith("SELECT ") or ";" in acl.ACL:
        fail("acl_inspect_source_refused")
    env = os.environ.copy()
    if read_only:
        env["PGOPTIONS"] = "-c default_transaction_read_only=on"
    try:
        p = subprocess.run(
            ["psql", db_url, "-X", "-At", "-q", "-v", "ON_ERROR_STOP=1",
             "-c", acl.ACL],
            env=env, stdin=subprocess.DEVNULL, capture_output=True,
            text=True, timeout=45, check=False)
    except (OSError, subprocess.SubprocessError):
        fail("acl_inspect_live_probe_refused" if read_only
             else "acl_inspect_local_probe_refused")
    if p.returncode != 0 or len(p.stdout) > 200:
        fail("acl_inspect_live_probe_refused" if read_only
             else "acl_inspect_local_probe_refused")
    return p.stdout.strip()

def isolated_port():
    ports=list(range(38000, 61000))
    secrets.SystemRandom().shuffle(ports)
    for port in ports[:256]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("0.0.0.0", port))
            except OSError:
                continue
            return port
    fail("acl_inspect_local_start_refused")

def sanitize_schema(source, dest):
    # Exact canonical validator behavior for schema-only restore; preserve
    # grants and revoke statements unchanged. No private source is printed.
    try:
        lines=source.read_text(encoding="utf-8").splitlines(keepends=True)
        kept=[]
        disabled=enabled=0
        for line in lines:
            m=SCHEMA_TOGGLES.match(line)
            if not m:
                kept.append(line)
            elif m.group(1)=="DISABLE":
                disabled+=1
            else:
                enabled+=1
        if disabled != enabled:
            fail("acl_inspect_snapshot_refused")
        dest.write_text("".join(kept), encoding="utf-8")
    except (UnicodeError, OSError):
        fail("acl_inspect_snapshot_refused")

def setup_local(path, port):
    if not run_silent(["supabase", "init", "--force"],cwd=path,timeout=60):
        fail("acl_inspect_local_start_refused")
    config=path/"supabase/config.toml"
    try:
        raw=config.read_text(encoding="utf8")
        section=""
        out=[]
        found_project=False
        found_port=False
        for line in raw.splitlines(keepends=True):
            stripped=line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section=stripped
            if section=="" and re.match(r"^project_id\s*=",stripped):
                line='project_id = "uniops_acl_2848_'+secrets.token_hex(4)+'"\n'
                found_project=True
            elif section=="[db]" and re.match(r"^port\s*=",stripped):
                line=f"port = {port}\n"
                found_port=True
            out.append(line)
        if not (found_project and found_port):
            fail("acl_inspect_local_start_refused")
        config.write_text("".join(out),encoding="utf8")
    except (OSError,UnicodeError):
        fail("acl_inspect_local_start_refused")
    # Only postgres is required: no GoTrue, PostgREST or application engine.
    if not run_silent(["supabase","db","start"],cwd=path,timeout=300):
        fail("acl_inspect_local_start_refused")

def restore_local(url, role_file, schema_file):
    for file in (role_file,schema_file):
        if not run_silent(
            ["psql",url,"-X","-v","ON_ERROR_STOP=1","-f",str(file)],
            timeout=300):
            fail("acl_inspect_local_restore_refused")

def inspect():
    live,tmp=require_environment(os.environ)
    try:
        fingerprint=acl.source_fingerprint(
            Path(__file__).parent.parent / "supabase/migrations" / acl.MIGRATION)
    except (ValueError, OSError, UnicodeError):
        fail("acl_inspect_source_refused")
    root=None
    project=None
    status="acl_inspect_unknown_refused"
    try:
        root=Path(tempfile.mkdtemp(prefix="uniops-acl-2848-",dir=tmp))
        os.chmod(root,0o700)
        project=root/"local"
        project.mkdir(mode=0o700)
        # Source read is metadata-only and guarded by a read-only transaction.
        source=catalog_snapshot(live,read_only=True)
        if not acl._verified_acl_observation(source,fingerprint):
            fail("acl_parity_source_unverified")
        roles=root/"roles.sql"
        schema=root/"schema.sql"
        sanitized=root/"schema-restorable.sql"
        if not run_silent(["supabase","db","dump","--db-url",live,
                           "--role-only","--file",str(roles)],timeout=300):
            fail("acl_inspect_snapshot_refused")
        if not run_silent(["supabase","db","dump","--db-url",live,
                           "--file",str(schema)],timeout=300):
            fail("acl_inspect_snapshot_refused")
        if not roles.is_file() or not schema.is_file():
            fail("acl_inspect_snapshot_refused")
        sanitize_schema(schema,sanitized)
        # Prevent changing-source ambiguity from being misclassified as
        # a restore defect: repeat only the exact metadata SELECT.
        if catalog_snapshot(live,read_only=True)!=source:
            fail("acl_inspect_live_drift_refused")
        port=isolated_port()
        setup_local(project,port)
        local=f"postgresql://postgres:postgres@127.0.0.1:{port}/postgres"
        restore_local(local,roles,sanitized)
        clone=catalog_snapshot(local)
        status=acl.compare_readonly_acl_observations(source,clone,fingerprint)
        if status not in acl.PARITY_MARKERS:
            fail("acl_inspect_unknown_refused")
    except Refused as e:
        status=str(e)
    except Exception:
        status="acl_inspect_unknown_refused"
    finally:
        if project is not None and (project/"supabase").exists():
            if not run_silent(["supabase","stop","--no-backup"],cwd=project,
                              timeout=120):
                status="acl_inspect_cleanup_refused"
        if root is not None:
            try:
                shutil.rmtree(root)
            except OSError:
                status="acl_inspect_cleanup_refused"
    return status if status in ALLOWED else "acl_inspect_unknown_refused"

def main():
    old_umask=os.umask(0o077)
    try:
        status=inspect()
    except Refused as e:
        status=str(e)
    except Exception:
        status="acl_inspect_unknown_refused"
    finally:
        os.umask(old_umask)
    if status not in ALLOWED:
        status="acl_inspect_unknown_refused"
    print("UNI_OPS_ACL_READONLY_RESULT="+status,flush=True)
    print("UNI_OPS_PRODUCTION_CHANGE=NONE",flush=True)
    # Valid red findings still complete the diagnostic without claiming PASS.
    return 0 if status in acl.PARITY_MARKERS else 1

if __name__=="__main__":
    raise SystemExit(main())

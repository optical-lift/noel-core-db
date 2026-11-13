#!/usr/bin/env python3
"""E05 disposable, synthetic-only schema/roles restore probe.

Called solely after the hosted Supabase local DB volume, actual SQL endpoint,
PG17, empty managed Auth, and job-unique project have been attested.
This is NOT the Noel Production schema, not the Work fixture, and not signed E05.
The two generated SQL inputs mirror the two separate protected read-only
Supabase db dump modes, without ever fetching or retaining Production content.
"""
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

ROLE_SQL = "CREATE ROLE e05_restore_probe_role NOLOGIN;\n"
SCHEMA_SQL = """CREATE SCHEMA e05_restore_probe;
REVOKE ALL ON SCHEMA e05_restore_probe FROM PUBLIC;
GRANT USAGE ON SCHEMA e05_restore_probe TO authenticated;
CREATE TABLE e05_restore_probe.items (id uuid PRIMARY KEY, owner_id uuid NOT NULL);
ALTER TABLE e05_restore_probe.items ENABLE ROW LEVEL SECURITY;
CREATE POLICY e05_restore_probe_owner ON e05_restore_probe.items
  FOR SELECT TO authenticated USING (owner_id = auth.uid());
REVOKE ALL ON e05_restore_probe.items FROM PUBLIC;
GRANT SELECT ON e05_restore_probe.items TO authenticated;
CREATE FUNCTION e05_restore_probe.owned_count()
RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $e05$ SELECT count(*)::integer FROM e05_restore_probe.items $e05$;
REVOKE EXECUTE ON FUNCTION e05_restore_probe.owned_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION e05_restore_probe.owned_count() TO authenticated;
"""
OWNER = "e5200000-0000-4000-8000-000000000001"
OUTSIDER = "e5200000-0000-4000-8000-000000000003"

class Refused(RuntimeError): pass

def require(ok, why):
    if not ok:
        raise Refused(why)

def local_url(url):
    try:
        value = urlsplit(url)
        p = value.port
    except ValueError:
        raise Refused("Invalid local Supabase test URL") from None
    require(value.scheme == "postgresql" and value.hostname == "127.0.0.1"
            and p is not None and 1 <= p <= 65535 and p != 55432
            and value.username == "postgres" and value.password is None
            and value.path == "/postgres" and not value.query
            and not value.fragment,
            "Only loopback job-owned Supabase postgres database permitted")
    return url

def job_root(root):
    raw = os.environ.get("RUNNER_TEMP", "")
    require(raw and not Path(raw).is_symlink(),
            "Job-owned RUNNER_TEMP required")
    temp = Path(raw).resolve(strict=True)
    path = Path(root).resolve(strict=True)
    require(path.is_dir() and not Path(root).is_symlink()
            and temp in path.parents
            and path.name.startswith("e05-supported-stack."),
            "Synthetic restore directory must be exact current job scratch")
    return path

def write_private(root, filename, sql):
    require(filename in ("roles-only.sql", "schema-only.sql"),
            "Unrecognized synthetic snapshot filename")
    output = root / filename
    require(not output.exists() and not output.is_symlink(),
            "Synthetic snapshot already exists")
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(sql)
    require(output.stat().st_mode & 0o077 == 0 and output.stat().st_size > 0,
            "Local synthetic file privacy failed")
    return output

def psql(url, env, sql=None, script=None, sqlstate=False, expect_error=False):
    local_url(url)
    require(sql is None or script is None, "Only one local SQL input permitted")
    require(env.get("PGPASSWORD") == "postgres",
            "Unexpected local password scope for synthetic-only test")
    require(not env.get("NOEL_CORE_DATABASE_URL")
            and not env.get("SUPABASE_DB_URL"),
            "Production connection environment must not enter this probe")
    args = ["psql", url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
            "-v", "VERBOSITY=sqlstate" if sqlstate else "VERBOSITY=terse"]
    input_sql = None
    if script is not None:
        require(Path(script).is_file() and not Path(script).is_symlink(),
                "SQL file unavailable or symlinked")
        args += ["-f", str(script)]
    else:
        require(isinstance(sql, str) and sql.strip() != "",
                "Missing fixed local query")
        # stdin runs each statement independently in one psql connection,
        # retaining SET LOCAL identity for the subsequent SELECT result.
        input_sql = sql + "\n"
    try:
        result = subprocess.run(args, env=env, input=input_sql,
                                capture_output=True, text=True,
                                check=False, timeout=45)
    except (OSError, subprocess.SubprocessError):
        raise Refused("Disposable psql command unavailable") from None
    if expect_error:
        require(result.returncode != 0
                and re.search(r"\b42501\b", result.stderr) is not None,
                "Anonymous relation read was not SQLSTATE 42501-denied")
        return ""
    require(result.returncode == 0,
            "Disposable roles/schema restoration or access probe failed")
    return result.stdout.strip()

def run_synthetic_restore(url, env, root):
    """Exercise actual psql -f restore and real RLS as two synthetic actors."""
    local_url(url)
    root = job_root(root)
    # The caller already proved the real Docker container+network/volume
    # identity. Recheck this isolated database is empty before writing.
    require(psql(url, env, sql="SELECT count(*) FROM auth.users;") == "0",
            "Not an empty local managed Auth baseline")
    roles = write_private(root, "roles-only.sql", ROLE_SQL)
    schema = write_private(root, "schema-only.sql", SCHEMA_SQL)
    # Roles-only then schema-only follows existing Noel clone validation.
    psql(url, env, script=roles)
    psql(url, env, script=schema)
    proof = psql(url, env, sql="""SELECT
       to_regrole('e05_restore_probe_role') IS NOT NULL,
       to_regclass('e05_restore_probe.items') IS NOT NULL,
       to_regprocedure('e05_restore_probe.owned_count()') IS NOT NULL,
       (SELECT relrowsecurity FROM pg_class
         WHERE oid='e05_restore_probe.items'::regclass),
       has_schema_privilege('authenticated','e05_restore_probe','USAGE'),
       has_table_privilege('authenticated','e05_restore_probe.items','SELECT'),
       has_function_privilege('authenticated','e05_restore_probe.owned_count()','EXECUTE'),
       NOT has_schema_privilege('anon','e05_restore_probe','USAGE'),
       NOT has_table_privilege('anon','e05_restore_probe.items','SELECT'),
       NOT has_function_privilege('anon','e05_restore_probe.owned_count()','EXECUTE'),
       (SELECT count(*)=0 FROM auth.users);""")
    require(proof == "|".join(["t"]*11),
            "Synthetic restore schema, role, ACL or RLS catalog postconditions failed")
    psql(url, env, sql=("INSERT INTO e05_restore_probe.items(id,owner_id)"
                        f" VALUES ('e5200000-0000-4000-8000-000000000901', '{OWNER}');"))
    def signed_role_count(uid):
        response=psql(url,env,sql=(
            "BEGIN; SET LOCAL ROLE authenticated;"
            f" SET LOCAL request.jwt.claim.sub = '{uid}';"
            " SELECT count(*) FROM e05_restore_probe.items; ROLLBACK;"))
        lines=[line.strip() for line in response.splitlines() if line.strip()]
        require(len(lines)>=2 and lines[-1]=="ROLLBACK"
                and lines[-2] in ("0","1"),
                "Authenticated local RLS response malformed")
        return lines[-2]
    require(signed_role_count(OWNER)=="1" and signed_role_count(OUTSIDER)=="0",
            "Restored synthetic RLS failed identity isolation")
    psql(url,env,sql=("BEGIN; SET LOCAL ROLE anon;"
                      " SELECT count(*) FROM e05_restore_probe.items;"),
         sqlstate=True, expect_error=True)
    require(psql(url,env,sql="SELECT count(*) FROM auth.users;")=="0",
            "Synthetic roles/schema fixture changed managed Auth user count")
    print("E05_HOSTED_SYNTHETIC_RESTORE=PASS; ROLES=RESTORED; SCHEMA=RESTORED; "
          "ACL_DENIAL=42501; RLS_OWNER=1; RLS_OUTSIDER=0; "
          "PRODUCTION_SCHEMA=NOT_READ; E05_SIGNED=NOT_RUN")

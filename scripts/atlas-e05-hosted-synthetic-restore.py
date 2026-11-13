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


def local_api_key(status, api_port):
    """Accept only this job's localhost Supabase anon key, never a remote key."""
    require(isinstance(status,dict),"Unrecognized local CLI status")
    require(status.get("API_URL")=="http://127.0.0.1:"+str(api_port),
            "Local Auth/REST URL differs from attested project")
    key=status.get("ANON_KEY")
    require(isinstance(key,str) and len(key)>32
            and (key.startswith("eyJ") or key.startswith("sb_publishable_")),
            "Local anonymous API key absent or malformed")
    return key


def jwt_claims(token):
    """Read (never forge) the session from GoTrue's real signed token."""
    import base64
    import json
    import uuid
    require(isinstance(token,str) and token.count(".")==2,
            "Real GoTrue access token absent")
    try:
        body=token.split(".")[1]
        payload=json.loads(base64.urlsafe_b64decode(body+"="*(-len(body)%4)))
        require(isinstance(payload,dict) and payload.get("role")=="authenticated",
                "GoTrue signed authenticated role absent")
        return str(uuid.UUID(payload["sub"])),str(uuid.UUID(payload["session_id"]))
    except (ValueError,TypeError,KeyError,UnicodeDecodeError,AttributeError):
        raise Refused("GoTrue signed subject/session unreadable") from None


def run_signed_synthetic_auth_probe(db,env,root,api_port,project):
    """Three real local GoTrue logins with genuine PostgREST RLS, no Work."""
    import json
    import secrets
    import subprocess
    import urllib.request
    import urllib.error
    import time
    local_url(db)
    job_root(root)
    require(isinstance(api_port,int) and 1<=api_port<=65535,
            "Invalid signed test API port")
    require(Path(project).resolve(strict=True)==root/"project",
            "Only the attested job-owned Supabase project may supply API keys")
    require(psql(db,env,sql="SELECT count(*) FROM auth.users;")=="0",
            "Signed synthetic test requires empty local Auth")
    try:
        result=subprocess.run(["supabase","status","-o","json"],
            cwd=project,env=env,capture_output=True,text=True,timeout=35,
            check=False)
    except (OSError,subprocess.SubprocessError):
        raise Refused("Local Supabase status unavailable") from None
    require(result.returncode==0,"Local Supabase status refused; output withheld")
    try:
        status=json.loads(result.stdout)
    except (ValueError,TypeError):
        raise Refused("Local CLI status JSON malformed") from None
    key=local_api_key(status,api_port)
    base="http://127.0.0.1:"+str(api_port)
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def request(route,data,bearer):
        require(route.startswith("/") and not route.startswith("//"),
                "Only project-local API paths are permitted")
        headers={"apikey":key,"Content-Type":"application/json",
                 "Authorization":"Bearer "+bearer}
        req=urllib.request.Request(base+route,data=json.dumps(data).encode(),
                                   headers=headers,method="POST")
        try:
            with opener.open(req,timeout=12) as res:
                return res.status,res.read(400000)
        except urllib.error.HTTPError as error:
            error.close()
            return error.code,b""
        except (OSError,urllib.error.URLError):
            raise Refused("Local Auth/PostgREST unavailable") from None

    actors={}
    for role in ("governor","recipient","outsider"):
        email="e05-"+role+"-"+secrets.token_hex(8)+"@example.invalid"
        password=secrets.token_urlsafe(35)
        code,_=request("/auth/v1/signup",
                       {"email":email,"password":password},key)
        require(code in (200,201),"Local GoTrue signup failed")
        code,body=request("/auth/v1/token?grant_type=password",
                          {"email":email,"password":password},key)
        require(code==200,"Local GoTrue password session failed")
        try:
            signed=json.loads(body)
            uid,sid=jwt_claims(signed.get("access_token"))
            require(signed["user"]["id"]==uid,
                    "GoTrue user and signed subject mismatch")
        except (ValueError,TypeError,KeyError):
            raise Refused("Local GoTrue session response invalid") from None
        actors[role]={"uid":uid,"sid":sid,"token":signed["access_token"]}
    require(len({v["uid"] for v in actors.values()})==3
            and len({v["sid"] for v in actors.values()})==3
            and len({v["token"] for v in actors.values()})==3,
            "Independent real GoTrue sessions required")
    sessions=",".join("'"+v["sid"]+"'::uuid" for v in actors.values())
    require(psql(db,env,sql="SELECT count(*),count(DISTINCT user_id) "
        "FROM auth.sessions WHERE id IN ("+sessions+");")=="3|3",
        "GoTrue sessions not independently recorded in Auth")
    psql(db,env,sql="""BEGIN;
CREATE FUNCTION public.e05_probe_owned_count()
RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path = ''
AS $e05$ SELECT count(*)::integer FROM e05_restore_probe.items $e05$;
REVOKE EXECUTE ON FUNCTION public.e05_probe_owned_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.e05_probe_owned_count() TO authenticated;
COMMIT;
NOTIFY pgrst, 'reload schema';""")
    require(psql(db,env,sql="SELECT has_function_privilege('authenticated',"
        "'public.e05_probe_owned_count()','EXECUTE'),"
        "NOT has_function_privilege('anon',"
        "'public.e05_probe_owned_count()','EXECUTE');")=="t|t",
        "Signed-only REST function privilege incorrect")
    uid=actors["governor"]["uid"]
    psql(db,env,sql="INSERT INTO e05_restore_probe.items(id,owner_id) "
        "VALUES ('e5200000-0000-4000-8000-000000000902','"+uid+"'::uuid);")
    for role in ("governor","recipient","outsider"):
        expected=1 if role=="governor" else 0
        passed=False
        for _ in range(8):
            code,body=request("/rest/v1/rpc/e05_probe_owned_count",
                              {},actors[role]["token"])
            if code==200:
                try:value=json.loads(body)
                except (ValueError,TypeError):
                    raise Refused("Signed REST response malformed") from None
                require(type(value) is int and value==expected,
                        "Real signed RLS read violated identity separation")
                passed=True
                break
            require(code==404,"Signed local REST error other than cache absence")
            time.sleep(1)
        require(passed,"Signed local RPC did not become source-visible")
    code,_=request("/rest/v1/rpc/e05_probe_owned_count",{},key)
    require(code in (401,403,404),
            "Anonymous request reached authenticated-only RLS reader")
    print("E05_HOSTED_REAL_SIGNED_SYNTHETIC=PASS; REAL_GOTRUE_SESSIONS=3; "
          "LOCAL_RLS_OWNER=1; LOCAL_RLS_FOREIGN=0; ANON_RPC=DENIED; "
          "NOEL_SCHEMA=NOT_READ; ORIGINAL_WORK=NOT_RUN")

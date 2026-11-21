#!/usr/bin/env python3
"""E05 protected owner-only genuine signed *test*, never a release.

The enclosing GitHub workflow authenticates the OWNER issue, pins each Git
revision and acquires current Production SCHEMA and ROLES READ ONLY. This
program receives only local file paths; it never receives a Production URL.
Its native PostgreSQL PGDATA, three fictional identities, GoTrue, PostgREST
and HTTP proxy all live on loopback and in the current job's RUNNER_TEMP.

One failed dependency is a HELD test, not a reason to change Production,
relax RLS/GRANT, or repurpose the preserved RiverSong schema clone.
"""
import argparse
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import subprocess
import tempfile
import threading
import urllib.parse

PINNED_BLOBS = {
    "scripts/atlas-riversong-e05-signed-acceptance.py":
        "87401240aa913d57e8bc276af1f221ff5ddc9765",
    "scripts/atlas-riversong-signed-transport.py":
        "03a176e71a18065bae73aac805691a99d6d663ab",
    "scripts/atlas-riversong-browser-preflight.py":
        "55da4dfa7b376e83151e5091340c4f83d6d5fdfa",
}
class Held(RuntimeError): pass

def need(ok,why):
    if not ok: raise Held(why)

def git_blob(path):
    data=path.read_bytes()
    return hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()

def source_module(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    need(spec and spec.loader,"Missing reviewed E05 source module")
    value=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def safe_file(path,temp):
    p=Path(path)
    need(p.is_file() and not p.is_symlink(),"Protected local input file unavailable")
    resolved=p.resolve(strict=True)
    need(temp in resolved.parents,"Protected local input must be job temporary")
    need(resolved.stat().st_size>0 and resolved.stat().st_size<100_000_000,
         "Protected snapshot unexpectedly empty or excessive")
    return resolved

def local_query(pg,env,sql):
    try:
        x=subprocess.run([str(pg/"psql"),"-X","-A","-t",
                          "-v","ON_ERROR_STOP=1","-c",sql],env=env,
                         capture_output=True,text=True,timeout=40)
    except (OSError,subprocess.SubprocessError):
        raise Held("Disposable local database query unavailable") from None
    need(x.returncode==0,"Disposable local source query failed; private details withheld")
    return x.stdout.strip()

def private_restore(runtime,file,pg,env,stage):
    try:
        runtime.command([pg/"psql","-X","-v","ON_ERROR_STOP=1","-f",file],
                        env=env,timeout=350)
    except (OSError,subprocess.SubprocessError):
        raise Held("Disposable "+stage+" restoration refused") from None

def initialize(runtime,native,roles_dump,schema_dump,temp):
    pg=native.pg_tools()
    runtime.pg=pg
    root=runtime.root
    pw=secrets.token_urlsafe(40)
    pwfile=root/"local-pg.pw"
    pwfile.write_text(pw)
    pwfile.chmod(0o600)
    runtime.command([pg/"initdb","-D",root/"db","-U","postgres",
                     "--auth-local=scram-sha-256","--auth-host=scram-sha-256",
                     "--pwfile",pwfile,"-E","UTF8","--no-instructions"],timeout=120)
    socket_dir=root/"socket"
    socket_dir.mkdir(mode=0o700)
    runtime.socket_dir=socket_dir
    port=native.free_port()
    runtime.db_started=True
    runtime.command([pg/"pg_ctl","-D",root/"db","-l",root/"postgres.log",
                     "-o",f"-h 127.0.0.1 -p {port} -k {socket_dir}","-w","start"],
                    timeout=90)
    env=dict(runtime.env,PGHOST="127.0.0.1",PGPORT=str(port),
             PGUSER="postgres",PGDATABASE="postgres",PGPASSWORD=pw,
             PGCONNECT_TIMEOUT="5",PSQLRC="/dev/null")
    runtime.db_env=env
    before=local_query(pg,env,"SELECT current_database(),host(inet_server_addr()),current_setting('data_directory')")
    columns=before.split("|")
    need(len(columns)==3 and columns[:2]==["postgres","127.0.0.1"] and
         temp in Path(columns[2]).resolve().parents,
         "Fresh cluster not strictly bound to job temporary PGDATA")
    # Production-role snapshot contains NO application rows and the job holds
    # no Production URL, only schema and role files.
    private_restore(runtime,roles_dump,pg,env,"roles")
    db_name="atlas_e05_"+secrets.token_hex(8)
    runtime.command([pg/"psql","-X","-v","ON_ERROR_STOP=1",
                     "-c",f"CREATE DATABASE {db_name} TEMPLATE template0;"],
                    env=env,timeout=50)
    env["PGDATABASE"]=db_name
    runtime.db_env=env
    private_restore(runtime,schema_dump,pg,env,"schema")
    return pg,env,port,pw,db_name

def start_native_services(runtime,native,pg,env,port,pw,db_name):
    # Authentic GoTrue is compiled from exactly reviewed upstream commit;
    # the PostgREST executable uses its reviewed upstream SHA256 archive.
    binary=native.build(runtime)
    local_secret=secrets.token_urlsafe(48)
    rest_pw=secrets.token_urlsafe(36)
    # This PASSWORD update is only inside the isolated job database cluster,
    # never Production or the preserved private RiverSong clone. Existing
    # snapshot membership, RLS and EXECUTE ACL are kept unchanged.
    local_query(pg,env,"ALTER ROLE authenticator LOGIN PASSWORD '"+
                rest_pw.replace("'","''")+"';")
    auth_port=native.free_port()
    rest_port=native.free_port()
    while rest_port==auth_port:rest_port=native.free_port()
    auth_base=f"http://127.0.0.1:{auth_port}"
    rest_base=f"http://127.0.0.1:{rest_port}"
    auth_env=dict(runtime.env,
        DATABASE_URL=f"postgresql://postgres:{pw}@127.0.0.1:{port}/{db_name}?sslmode=disable",
        GOTRUE_DB_DRIVER="postgres",DB_NAMESPACE="auth",
        GOTRUE_DB_MIGRATIONS_PATH=str(runtime.root/"auth-source/migrations"),
        GOTRUE_API_HOST="127.0.0.1",PORT=str(auth_port),
        API_EXTERNAL_URL=auth_base,GOTRUE_SITE_URL=auth_base,
        GOTRUE_JWT_SECRET=local_secret,GOTRUE_JWT_AUD="authenticated",
        GOTRUE_JWT_DEFAULT_GROUP_NAME="authenticated",
        GOTRUE_EXTERNAL_EMAIL_ENABLED="true",
        GOTRUE_DISABLE_SIGNUP="true",
        GOTRUE_MAILER_AUTOCONFIRM="true",
        GOTRUE_EXTERNAL_PHONE_ENABLED="false",
        GOTRUE_LOG_LEVEL="error")
    auth=runtime.service([runtime.root/"auth"],auth_env,"auth")
    native.wait_health(auth,auth_base,"/health")
    rest_env=dict(runtime.env,
        PGRST_DB_URI=f"postgresql://authenticator:{rest_pw}@127.0.0.1:{port}/{db_name}",
        PGRST_DB_SCHEMAS="public",PGRST_DB_ANON_ROLE="anon",
        PGRST_JWT_SECRET=local_secret,PGRST_SERVER_HOST="127.0.0.1",
        PGRST_SERVER_PORT=str(rest_port),PGRST_DB_CONFIG="false",
        PGRST_DB_CHANNEL_ENABLED="false",PGRST_LOG_LEVEL="error")
    rest=runtime.service([binary],rest_env,"rest")
    native.wait_health(rest,rest_base,"/")
    return auth_port,rest_port

class Proxy(BaseHTTPRequestHandler):
    """Only route requests to real local Auth and PostgREST child processes."""
    def log_message(self,*_args): pass
    def do_GET(self): self.relay()
    def do_POST(self): self.relay()
    def relay(self):
        u=urllib.parse.urlsplit(self.path)
        if (u.fragment or not u.path.startswith(("/auth/v1/","/rest/v1/rpc/"))
            or self.command not in ("GET","POST")):
            self.send_error(404);return
        if u.path.startswith("/auth/v1/"):
            target=self.server.auth_port
            path=u.path[len("/auth/v1"):]
        else:
            target=self.server.rest_port
            path=u.path[len("/rest/v1"):]
        if u.query:path+="?"+u.query
        length=int(self.headers.get("Content-Length","0"))
        if length<0 or length>1_048_576:
            self.send_error(413);return
        body=self.rfile.read(length) if length else None
        headers={"Content-Type":"application/json"}
        for k in ("Authorization","Accept","Prefer"):
            if self.headers.get(k): headers[k]=self.headers[k]
        conn=http.client.HTTPConnection("127.0.0.1",target,timeout=25)
        try:
            conn.request(self.command,path,body=body,headers=headers)
            upstream=conn.getresponse()
            payload=upstream.read(1_048_577)
            if len(payload)>1_048_576:
                self.send_error(502);return
            self.send_response(upstream.status)
            self.send_header("Content-Type",upstream.getheader("Content-Type","application/json"))
            self.send_header("Content-Length",str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (OSError,ValueError,http.client.HTTPException):
            try:self.send_error(502)
            except OSError:pass
        finally:
            conn.close()

def run(noel_root,atlas_root,roles_dump,schema_dump,temp):
    need(platform.system()=="Darwin" and platform.machine()=="x86_64",
         "Only the reviewed Intel RiverSong private test runner is allowed")
    need(temp.is_dir() and not temp.is_symlink(),"Fresh RUNNER_TEMP is required")
    need(noel_root.is_dir() and atlas_root.is_dir() and
         not noel_root.is_symlink() and not atlas_root.is_symlink(),
         "Pinned Noel/Atlas source trees required")
    for rel,sha in PINNED_BLOBS.items():
        path=atlas_root/rel
        need(path.is_file() and not path.is_symlink() and git_blob(path)==sha,
             "Atlas original signed/transport source pin mismatch")
    for rel in ("scripts/check-atlas-e05-current-source.py",
                "scripts/prepare-atlas-e05-nonfarm-clone-fixture.py",
                "scripts/run-atlas-e05-isolated-riversong.py"):
        need((noel_root/rel).is_file(),"Noel source owner E05 module missing")
    roles=safe_file(roles_dump,temp)
    schema=safe_file(schema_dump,temp)
    # Prevent another tool from accidentally emitting a credential in logs.
    os.umask(0o077)
    native=source_module(atlas_root/"scripts/atlas-riversong-signed-transport.py",
                         "e05_verified_native_transport")
    runtime=None
    server=None
    thread=None
    stage="SOURCE_PIN_GUARD"
    try:
        root=Path(tempfile.mkdtemp(prefix="e05-protected-native.",dir=temp))
        runtime=native.Runtime(root)
        runtime.env["DYLD_LIBRARY_PATH"]=str(native.pg_tools().parent/"lib")
        stage="FRESH_PG17_AND_READONLY_SCHEMA_RESTORE"
        pg,db_env,port,pw,db_name=initialize(runtime,native,roles,schema,temp)
        os.environ.update({k:v for k,v in db_env.items() if k.startswith("PG")})
        os.environ["PATH"]=str(pg)+":"+os.environ.get("PATH","")
        local_url=f"postgresql://postgres@127.0.0.1:{port}/{db_name}"
        stage="CURRENT_SOURCE_ELIGIBILITY"
        # Source-only checker is immutable, no grants and no data writes.
        gate=subprocess.run(["python3",str(noel_root/"scripts/check-atlas-e05-current-source.py"),
                             "--db-url",local_url,"--output",str(root/"source-eligibility.json")],
                            capture_output=True,text=True,timeout=70)
        need(gate.returncode==0 and (root/"source-eligibility.json").is_file(),
             "Current schema/roles exact Work source gate refused")
        gate_receipt=json.loads((root/"source-eligibility.json").read_text())
        need(gate_receipt.get("state")=="E05_SOURCE_ELIGIBLE_NOT_FULL_PARITY" and
             gate_receipt.get("productionChanges") is False,
             "Unreviewed current-source eligibility receipt")
        stage="PINNED_REAL_GOTRUE_POSTGREST_START"
        a_port,r_port=start_native_services(runtime,native,pg,db_env,port,pw,db_name)
        server=ThreadingHTTPServer(("127.0.0.1",0),Proxy)
        server.auth_port=a_port;server.rest_port=r_port
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        api_url=f"http://127.0.0.1:{server.server_port}"
        stage="E05_THREE_INDEPENDENT_SIGNED_ACTORS"
        for actor in ("governor","recipient","outsider"):
            os.environ[f"ATLAS_E05_{actor.upper()}_EMAIL"]=(
                "e05-"+actor+"-"+secrets.token_hex(8)+"@example.invalid")
            os.environ[f"ATLAS_E05_{actor.upper()}_PASSWORD"]=secrets.token_urlsafe(36)
        os.environ["ATLAS_E05_LOCAL_ANON_KEY"]=secrets.token_urlsafe(36)
        bridge=subprocess.run(["python3",str(noel_root/"scripts/run-atlas-e05-isolated-riversong.py"),
                               "--db-url",local_url,"--api-url",api_url,"--atlas-runner",
                               str(atlas_root/"scripts/atlas-riversong-e05-signed-acceptance.py")],
                              capture_output=True,text=True,timeout=850)
        need(bridge.returncode==0 and
             "E05_SIGNED_SOURCE_ACCEPTANCE=PASS;" in bridge.stdout,
             "Genuine three-actor signed source proof refused")
        stage="BOUNDED_SIGNED_ACCEPTANCE"
        print("E05_PROTECTED_CURRENT_SCHEMA=PASS; REAL_GOTRUE_SESSIONS=3; "+
              "SIGNED_SOURCE_ACCEPTANCE=PASS; BROWSER=NOT_RUN; RECIPIENT_HISTORY=HELD")
        return 0
    except (Held,native.Blocked,OSError,ValueError,subprocess.SubprocessError) as exc:
        print("E05_PROTECTED_SIGNED=HELD; STAGE="+stage+"; "+
              (str(exc) if isinstance(exc,Held) else "PRIVATE_DIAGNOSTICS_WITHHELD"))
        return 1
    finally:
        if server:
            server.shutdown();server.server_close()
        if thread:thread.join(timeout=6)
        if runtime:
            try:runtime.cleanup()
            except (native.Blocked,OSError,subprocess.SubprocessError):
                print("E05_PROTECTED_CLEANUP=FAILED; OPERATOR_INSPECTION_REQUIRED")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--noel-source",type=Path,required=True)
    p.add_argument("--atlas-source",type=Path,required=True)
    p.add_argument("--roles-dump",type=Path,required=True)
    p.add_argument("--schema-dump",type=Path,required=True)
    args=p.parse_args()
    raw=os.environ.get("RUNNER_TEMP","")
    need(bool(raw) and not Path(raw).is_symlink(),"Job-owned RUNNER_TEMP required")
    temp=Path(raw).resolve(strict=True)
    return run(args.noel_source.resolve(strict=True),
               args.atlas_source.resolve(strict=True),
               args.roles_dump,args.schema_dump,temp)

if __name__=="__main__":
    try:raise SystemExit(main())
    except (Held,OSError,ValueError):
        print("E05_PROTECTED_SIGNED=HELD; PRIVATE_DIAGNOSTICS_WITHHELD")
        raise SystemExit(1) from None

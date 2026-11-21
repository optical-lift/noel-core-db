#!/usr/bin/env python3
"""E05 synthetic-only GitHub-hosted Supabase CLI startup attestation.

No Production URL, roles/schema snapshot, Work fixture, user credentials,
or signed acceptance. This tests supported Supabase local PG17+Auth startup
and a random job-unique Docker database volume, with mandatory cleanup.
"""
import argparse
import importlib.util
import ipaddress
import json
import os
from pathlib import Path,PurePosixPath
import platform
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import urllib.error
import urllib.request

class Held(RuntimeError): pass
def need(ok,reason):
    if not ok: raise Held(reason)

def cmd(args,cwd=None,env=None,timeout=100,log=None):
    try:
        p=subprocess.run([str(x) for x in args],cwd=cwd,env=env,
             capture_output=True,text=True,timeout=timeout,check=False)
    except (OSError,subprocess.SubprocessError):
        raise Held("Local stack command unavailable") from None
    if log:
        Path(log).write_text((p.stdout+p.stderr)[:250000],encoding="utf-8")
        os.chmod(log,0o600)
    need(p.returncode==0,"Isolated local stack command failed; details withheld")
    return p.stdout.strip()

def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1",0))
        return sock.getsockname()[1]

def configure(path,project,dbport,apiport):
    need(re.fullmatch(r'e05host_[0-9a-f]{16}',project)!=None,"Bad job identity")
    section=""
    flags={"project":0,"db":0,"api":0}
    lines=[]
    for line in path.read_text().splitlines(keepends=True):
        stripped=line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):section=stripped
        if section=="" and re.match(r'^project_id\s*=',stripped):
            line=f'project_id = "{project}"\n';flags["project"]+=1
        elif section=="[db]" and re.match(r'^port\s*=',stripped):
            line=f'port = {dbport}\n';flags["db"]+=1
        elif section=="[api]" and re.match(r'^port\s*=',stripped):
            line=f'port = {apiport}\n';flags["api"]+=1
        lines.append(line)
    need(flags=={"project":1,"db":1,"api":1},"Unrecognized local Supabase config")
    path.write_text("".join(lines))

def attested_volume(inspect,project,pgdata,dbport,sql_server_ip):
    need(inspect.get("Name")=="/supabase_db_"+project and
         inspect.get("State",{}).get("Running") is True,
         "Wrong running local DB container")
    need(isinstance(pgdata,str) and pgdata.startswith("/"),
         "Missing local PostgreSQL data-directory identity")
    pg=PurePosixPath(pgdata)
    # A host-to-Docker 127.0.0.1 port forward reaches the PostgreSQL
    # container on its Docker-network IP, NOT the host loopback address.
    # Prove the DB's actual server interface belongs to this exact container.
    try:
        server=ipaddress.ip_address(sql_server_ip)
    except ValueError:
        raise Held("Invalid PostgreSQL server interface") from None
    nets=inspect.get("NetworkSettings",{}).get("Networks",{})
    need(isinstance(nets,dict) and any(
         n.get("IPAddress")==str(server) for n in nets.values()),
         "Connected PostgreSQL server does not match job Docker container network")
    mounts=inspect.get("Mounts",[])
    valid=[m for m in mounts if m.get("Type")=="volume" and
           isinstance(m.get("Name"),str) and m["Name"].endswith("_"+project)
           and isinstance(m.get("Destination"),str)
           and (PurePosixPath(m["Destination"])==pg or
                PurePosixPath(m["Destination"]) in pg.parents)]
    need(len(valid)==1,"Database PGDATA not in isolated project Docker volume")
    bind=inspect.get("NetworkSettings",{}).get("Ports",{}).get("5432/tcp",[])
    need(isinstance(bind,list) and len(bind)==1 and
         bind[0].get("HostIp")=="127.0.0.1" and
         bind[0].get("HostPort")==str(dbport),
         "Database port must have one exact loopback-only mapping")
    return valid[0]["Name"]

def attested_network(info,expected):
    need(info.get("Name")==expected and info.get("Driver")=="bridge"
         and info.get("Options",{}).get(
             "com.docker.network.bridge.host_binding_ipv4")=="127.0.0.1",
         "Docker network is not an exact dedicated loopback bridge")
    return True

def run(synthetic_restore=False,signed_synthetic_auth=False,
        docker_current_source_probe=False):
    need(platform.system()=="Linux" and platform.machine()=="x86_64",
         "Only hosted Ubuntu x64 supports this synthetic test")
    raw=os.environ.get("RUNNER_TEMP","")
    need(raw and not Path(raw).is_symlink(),"Missing job-owned temporary root")
    temp=Path(raw).resolve(strict=True)
    need(temp.is_dir(),"Invalid job-owned temporary root")
    need(cmd(["supabase","--version"]).splitlines()[-1]=="2.116.0",
         "Unexpected Supabase CLI version")
    cmd(["docker","info"],timeout=35)
    need(shutil.which("psql") is not None,"PostgreSQL client missing")
    os.umask(0o077)
    root=Path(tempfile.mkdtemp(prefix="e05-supported-stack.",dir=temp))
    project=root/"project"
    project.mkdir(mode=0o700)
    ident="e05host_"+secrets.token_hex(8)
    dbport,apiport=port(),port()
    need(dbport!=apiport,"Overlapping local ports")
    env=dict(os.environ)
    env.pop("NOEL_CORE_DATABASE_URL",None)
    env.pop("SUPABASE_DB_URL",None)
    started=False
    network=None
    volume=None
    outcome=1
    stage="INITIALIZE"
    try:
        cmd(["supabase","init","--force"],cwd=project,env=env,log=root/"init.log")
        configure(project/"supabase/config.toml",ident,dbport,apiport)
        stage="FRESH_PROJECT_IDENTITY"
        try:cmd(["docker","container","inspect","supabase_db_"+ident],timeout=12)
        except Held:pass
        else:raise Held("Job project container existed before startup")
        stage="LOOPBACK_DOCKER_NETWORK"
        name="e05net_"+secrets.token_hex(8)
        need("--network-id" in cmd(["supabase","start","--help"],cwd=project,
                                     env=env,timeout=35),
             "Pinned Supabase CLI does not support an explicit network")
        cmd(["docker","network","create","--driver","bridge",
             "--opt","com.docker.network.bridge.host_binding_ipv4=127.0.0.1",
             name],timeout=30)
        network=name
        network_info=json.loads(cmd(["docker","network","inspect",network],timeout=20))
        need(isinstance(network_info,list) and len(network_info)==1,
             "Docker network inspect did not return one job bridge")
        attested_network(network_info[0],network)
        stage="SUPPORTED_SUPABASE_START"
        started=True
        cmd(["supabase","start","--network-id",network,"-x",
             "realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor"],
            cwd=project,env=env,timeout=720,log=root/"start.log")
        stage="LOCAL_PG17_MANAGED_AUTH"
        db=f"postgresql://postgres@127.0.0.1:{dbport}/postgres"
        db_env=dict(env,PGPASSWORD="postgres",PGCONNECT_TIMEOUT="5")
        query=("SELECT current_database(),host(inet_server_addr()),"
               "current_setting('data_directory'),current_setting('server_version_num'),"
               "to_regclass('auth.users') IS NOT NULL,"
               "to_regclass('auth.sessions') IS NOT NULL,"
               "to_regclass('auth.identities') IS NOT NULL,"
               "(SELECT count(*) FROM auth.users),(SELECT count(*) FROM auth.sessions);")
        values=cmd(["psql",db,"-X","-A","-t","-v","ON_ERROR_STOP=1","-c",query],
                   env=db_env,timeout=30).split("|")
        need(len(values)==9 and values[0]=="postgres",
             "Current local DB name or catalog response mismatch")
        need(values[3].isdigit() and int(values[3])//10000==17,
             "Local managed database is not PostgreSQL 17")
        need(values[4:]==["t","t","t","0","0"],
             "Local managed Auth missing or nonempty; refuse synthetic baseline")
        stage="DOCKER_PROJECT_VOLUME"
        info=json.loads(cmd(["docker","container","inspect","supabase_db_"+ident],
                             timeout=30))[0]
        volume=attested_volume(info,ident,values[2],dbport,values[1])
        stage="LOCAL_GOTRUE_HEALTH"
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(f"http://127.0.0.1:{apiport}/auth/v1/health",
                             timeout=12) as res:health=res.status
        except (OSError,urllib.error.HTTPError):
            raise Held("Local real Auth health unavailable") from None
        need(health==200,"Local managed Auth not healthy")
        if docker_current_source_probe:
            stage="DOCKER_ATTESTED_E05_CURRENT_SOURCE_GATE"
            bridge=Path(__file__).with_name("check-atlas-e05-docker-current-source.py")
            need(bridge.is_file() and not bridge.is_symlink(),
                 "Reviewed Docker source eligibility gate absent")
            spec=importlib.util.spec_from_file_location("e05_docker_source_gate",bridge)
            need(spec is not None and spec.loader is not None,
                 "Docker source eligibility gate unavailable")
            gate=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gate)
            try:
                proof=gate.check(db,db_env,root,ident,network,volume,dbport)
            except gate.Refused:
                raise Held("Docker source gate refused; private output withheld") from None
            need(proof.get("state")=="HELD_MISSING_CURRENT_SOURCE" and
                 proof.get("dockerCustody")=="PASS" and
                 proof.get("signedSourceAcceptance")=="NOT_RUN" and
                 proof.get("productionChanges") is False,
                 "Synthetic-only test should not have current Noel Source")
            print("E05_DOCKER_CURRENT_SOURCE_CUSTODY=PASS; "+
                  "NOEL_CURRENT_SCHEMA=HELD_MISSING_SURFACES; "+
                  "ORIGINAL_WORK=NOT_RUN")
        if synthetic_restore or signed_synthetic_auth:
            stage="SYNTHETIC_ROLES_AND_SCHEMA_RESTORE"
            helper=Path(__file__).with_name("atlas-e05-hosted-synthetic-restore.py")
            need(helper.is_file() and not helper.is_symlink(),
                 "Exact Noel hosted synthetic restore module unavailable")
            spec=importlib.util.spec_from_file_location("e05_hosted_restore",helper)
            need(spec is not None and spec.loader is not None,
                 "Hosted E05 synthetic restore module cannot load")
            module=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            try:
                module.run_synthetic_restore(db,db_env,root)
                if signed_synthetic_auth:
                    stage="REAL_GOTRUE_THREE_SESSION_SYNTHETIC_RLS"
                    module.run_signed_synthetic_auth_probe(db,db_env,root,apiport,project)
            except module.Refused as exc:
                # Only explicitly whitelisted fixed source messages may enter
                # CI. Never disclose SQL, token, endpoint credential or stderr.
                safe_reasons={
                    "Invalid signed test API port":"API_PORT",
                    "Only the attested job-owned Supabase project may supply API keys":"PROJECT_BOUNDARY",
                    "Signed synthetic test requires empty local Auth":"AUTH_NOT_EMPTY",
                    "Local Supabase status unavailable":"STATUS_UNAVAILABLE",
                    "Local Supabase status refused; output withheld":"STATUS_REFUSED",
                    "Local CLI status JSON malformed":"STATUS_JSON",
                    "Local Auth/REST URL differs from attested project":"STATUS_API_MISMATCH",
                    "Local anonymous API key absent or malformed":"STATUS_ANON_KEY",
                    "Local GoTrue signup failed":"AUTH_SIGNUP",
                    "Local GoTrue password session failed":"AUTH_PASSWORD_SESSION",
                    "Local GoTrue session response invalid":"AUTH_RESPONSE",
                    "GoTrue signed subject/session unreadable":"AUTH_SESSION_CLAIM",
                    "Independent real GoTrue sessions required":"AUTH_NOT_INDEPENDENT",
                    "GoTrue sessions not independently recorded in Auth":"AUTH_SESSION_CUSTODY",
                    "Signed-only REST function privilege incorrect":"REST_PRIVILEGE",
                    "Signed local REST error other than cache absence":"REST_SIGNED_ERROR",
                    "Signed local RPC did not become source-visible":"REST_CACHE",
                    "Signed REST response malformed":"REST_RESPONSE",
                    "Real signed RLS read violated identity separation":"RLS_ISOLATION",
                    "Anonymous request reached authenticated-only RLS reader":"REST_ANON_DENIAL",
                }
                code=safe_reasons.get(str(exc),"UNCLASSIFIED")
                print("E05_HOSTED_SIGNED_DIAGNOSTIC="+code)
                raise Held("Hosted synthetic restore refused; private details withheld") from None
            except (OSError,ValueError,subprocess.SubprocessError):
                raise Held("Hosted synthetic restore refused; private details withheld") from None
        print("E05_SUPPORTED_STACK=PASS; PG17=TRUE; AUTH=REAL_LOCAL; "+
              "UNIQUE_VOLUME=TRUE; PRODUCTION_ROWS=NONE; E05_SIGNED=NOT_RUN")
        outcome=0
    except (Held,KeyError,IndexError,ValueError,subprocess.SubprocessError):
        print("E05_SUPPORTED_STACK=HELD; STAGE="+stage+"; PRIVATE_DIAGNOSTICS_WITHHELD")
    finally:
        if started:
            try:cmd(["supabase","stop","--no-backup"],cwd=project,
                    env=env,timeout=240,log=root/"stop.log")
            except Held:
                print("E05_SUPPORTED_STACK_CLEANUP=HELD");outcome=1
        if network:
            try:
                cmd(["docker","network","rm",network],timeout=35)
            except Held:
                print("E05_SUPPORTED_STACK_NETWORK_CLEANUP=HELD");outcome=1
            try:cmd(["docker","network","inspect",network],timeout=15)
            except Held:pass
            else:
                print("E05_SUPPORTED_STACK_NETWORK_RETAINED=HELD");outcome=1
        if volume:
            try:cmd(["docker","volume","inspect",volume],timeout=20)
            except Held:pass
            else:
                print("E05_SUPPORTED_STACK_VOLUME_RETAINED=HELD");outcome=1
        need(temp in root.resolve().parents and root.name.startswith("e05-supported-stack."),
             "Refuse foreign temporary cleanup")
        shutil.rmtree(root,ignore_errors=True)
        if root.exists():
            print("E05_SUPPORTED_STACK_TEMP_RETAINED=HELD");outcome=1
    return outcome

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--synthetic-restore-probe",action="store_true")
    parser.add_argument("--signed-synthetic-auth-probe",action="store_true")
    parser.add_argument("--docker-current-source-probe",action="store_true")
    flags=parser.parse_args()
    try:raise SystemExit(run(synthetic_restore=flags.synthetic_restore_probe,
                             signed_synthetic_auth=flags.signed_synthetic_auth_probe,
                             docker_current_source_probe=flags.docker_current_source_probe))
    except (Held,OSError,ValueError,subprocess.SubprocessError):
        print("E05_SUPPORTED_STACK=HELD; NO_PRODUCTION_ACCESS")
        raise SystemExit(1) from None

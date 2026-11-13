#!/usr/bin/env python3
"""Read-only E05 CURRENT SOURCE inventory on an attested CLI Docker database.

This is an ADDITIVE Docker-specific custody path, not an exception to the
native named atlas_e05_<nonce> database and RUNNER_TEMP/PGDATA rules.
Run only from the verified job-unique Supabase CLI local PG17 stack. It cannot
restore any schema, prepare a fixture, mint a session or run Atlas original Work.
An owner-approved schema/roles source and separately reviewed Work transport
are still required before original signed E05 acceptance.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
PROJECT=re.compile(r"e05host_[0-9a-f]{16}\Z")
NETWORK=re.compile(r"e05net_[0-9a-f]{16}\Z")

class Refused(RuntimeError): pass
def require(ok,reason):
    if not ok:raise Refused(reason)

def source_module(name,alias):
    source=HERE/name
    require(source.is_file() and not source.is_symlink(),
            "Required reviewed local Noel source module missing")
    spec=importlib.util.spec_from_file_location(alias,source)
    require(spec and spec.loader,"Source module unavailable")
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def catalog_presence_sql(source):
    """Read only existence predicates. Missing tables must not break the SQL."""
    expressions=[]
    for name in source.RELATIONS:
        expressions.append("'"+name+"',to_regclass('"+name+"') IS NOT NULL")
    for name,sig in source.FUNCTIONS.items():
        expressions.append("'"+name+"',to_regprocedure('"+sig+"') IS NOT NULL")
    for role in ("anon","authenticated","authenticator"):
        expressions.append("'role."+role+"',to_regrole('"+role+"') IS NOT NULL")
    return "SELECT jsonb_build_object("+",".join(expressions)+");"

def exact_presence(response,source):
    required=set(source.RELATIONS)|set(source.FUNCTIONS)|{
        "role.anon","role.authenticated","role.authenticator"}
    require(isinstance(response,dict) and set(response)==required,
            "Current source presence inventory response not exact")
    return all(response.get(name) is True for name in required)

def query(url,env,sql):
    # Only fixed queries from source-owned functions are allowed.
    require(isinstance(sql,str) and sql.startswith("SELECT "),
            "Only read-only source-owned SELECT is permitted")
    require(env.get("PGPASSWORD")=="postgres"
            and not env.get("NOEL_CORE_DATABASE_URL")
            and not env.get("SUPABASE_DB_URL"),
            "Production or unknown credentials not allowed in Docker source gate")
    try:
        r=subprocess.run(["psql",url,"-X","-A","-t","-v","ON_ERROR_STOP=1",
                          "-c",sql],env=env,capture_output=True,text=True,
                         timeout=35,check=False)
    except (OSError,subprocess.SubprocessError):
        raise Refused("Read-only Docker catalog query unavailable") from None
    require(r.returncode==0,"Docker source catalog SELECT failed; details withheld")
    return r.stdout.strip()

def docker_inspect(name):
    try:
        r=subprocess.run(["docker","container","inspect",name],
                         capture_output=True,text=True,check=False,timeout=25)
    except (OSError,subprocess.SubprocessError):
        raise Refused("Exact local Docker instance unavailable") from None
    require(r.returncode==0,"Exact Docker instance missing")
    try:data=json.loads(r.stdout)
    except (TypeError,ValueError):
        raise Refused("Docker provenance response malformed") from None
    require(isinstance(data,list) and len(data)==1,
            "Docker instance provenance ambiguous")
    return data[0]

def check(url,env,root,project,network,expected_volume,dbport):
    """Attest same CLI PostgreSQL container before checking native Source facts.

    Never infer permission from 'postgres' as a name; actual local Docker
    container identity, network, port, empty Auth and project-owned volume
    must be established. Current schema presence does not prove parity.
    """
    restore=source_module("atlas-e05-hosted-synthetic-restore.py",
                          "e05_local_restore_custody")
    stack=source_module("check-atlas-e05-supported-stack.py",
                        "e05_supported_docker_attestation")
    current=source_module("check-atlas-e05-current-source.py",
                          "e05_native_source_contract")
    restore.local_url(url)
    root=restore.job_root(root)
    require(PROJECT.fullmatch(project) is not None and
            NETWORK.fullmatch(network) is not None,
            "Unrecognized disposable Docker project/network identity")
    require((root/"project").is_dir() and not (root/"project").is_symlink(),
            "Exact job's CLI project directory missing")
    config=(root/"project"/"supabase"/"config.toml")
    require(config.is_file() and not config.is_symlink(),
            "Exact CLI config not available")
    import tomllib
    settings=tomllib.loads(config.read_text(encoding="utf-8"))
    require(settings.get("project_id")==project and
            settings.get("db",{}).get("port")==dbport,
            "CLI project ID or database port not bound to this job")
    require(isinstance(dbport,int) and 1<=dbport<=65535,
            "Invalid Docker project port")
    import urllib.parse
    parsed=urllib.parse.urlsplit(url)
    require(parsed.port==dbport,"SQL port differs from project config")
    require(expected_volume=="supabase_db_"+project,
            "Docker DB volume not from this exact random project")
    sql=query(url,env,
              "SELECT current_database(),host(inet_server_addr()),"
              "current_setting('data_directory'),"
              "current_setting('server_version_num'),"
              "(SELECT count(*) FROM auth.users),"
              "(SELECT count(*) FROM auth.sessions);")
    fields=sql.split("|")
    require(len(fields)==6 and fields[0]=="postgres" and
            fields[3].isdigit() and int(fields[3])//10000==17 and
            fields[4:] == ["0","0"],
            "Expected fresh PostgreSQL 17 managed Auth baseline absent")
    details=docker_inspect("supabase_db_"+project)
    networks=details.get("NetworkSettings",{}).get("Networks",{})
    require(network in networks and
            networks[network].get("IPAddress")==fields[1],
            "SQL server interface is not attached to exact job bridge")
    volume=stack.attested_volume(details,project,fields[2],dbport,fields[1])
    require(volume==expected_volume,
            "Exact job Docker PGDATA volume mismatch")
    net=stack.cmd(["docker","network","inspect",network],timeout=20)
    try:network_info=json.loads(net)
    except (TypeError,ValueError):
        raise Refused("Docker job network response malformed") from None
    require(isinstance(network_info,list) and len(network_info)==1,
            "Ambiguous Docker job network")
    stack.attested_network(network_info[0],network)
    # Native canonical Source object names are re-used, never re-implemented.
    presence=catalog_presence_sql(current)
    try:inventory=json.loads(query(url,env,presence))
    except (ValueError,TypeError):
        raise Refused("Source presence inventory malformed") from None
    if not exact_presence(inventory,current):
        return {"state":"HELD_MISSING_CURRENT_SOURCE","dockerCustody":"PASS",
                "currentSource":"MISSING_REQUIRED_RELATIONS_OR_FUNCTIONS",
                "signedSourceAcceptance":"NOT_RUN","productionChanges":False}
    try:result=json.loads(query(url,env,current.surface_sql()))
    except (TypeError,ValueError):
        raise Refused("Current source surface response malformed") from None
    require(isinstance(result,dict) and
            set(result)=={"database","server","pgdata","surfaces"}
            and result["database"]==fields[0] and
            result["server"]==fields[1] and
            result["pgdata"]==fields[2],
            "Current source response no longer matches attested Docker instance")
    count=current.require_source_surfaces(result["surfaces"])
    return {"state":"DOCKER_SOURCE_ELIGIBLE_NOT_FULL_PARITY",
            "dockerCustody":"PASS","checkedSurfaces":count,
            "currentSource":"SURFACE_AND_ACL_ELIGIBLE_NOT_PARITY",
            "signedSourceAcceptance":"NOT_RUN","productionChanges":False}

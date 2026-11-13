#!/usr/bin/env python3
"""E05 read-only source eligibility gate: fresh job-owned clone only.

This checks required Source objects, signed public RPC permissions, and an
empty fixture baseline. It neither acquires the Production snapshot nor
establishes full Production schema parity, real signed sessions, or browser
acceptance. It never modifies a database.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit

DB_NAME = re.compile(r"atlas_e05_[0-9a-f]{8,24}\Z")
RELATIONS = (
    "auth.users", "auth.sessions", "auth.identities",
    "atlas.organizations", "atlas.farms", "atlas.work_items",
    "atlas.work_allocations", "atlas.principal_ledger_authorities",
    "atlas.company_work_native_ledger_relevance",
    "atlas.work_result_contract_policies", "ledger.ledgers",
    "ledger.seats", "ledger.booking_requests",
    "ledger.booking_offerings", "reality.entities",
)
FUNCTIONS = {
    "atlas.company_work_native_ledger_exact_source_v1":
       "atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)",
    "public.propose_native_ledger_exact_work_scope_owner_self_api_v1":
       "public.propose_native_ledger_exact_work_scope_owner_self_api_v1(uuid,uuid,uuid,uuid,text,timestamp with time zone)",
    "public.native_ledger_standing_scopes_self_api_v1":
       "public.native_ledger_standing_scopes_self_api_v1()",
    "public.respond_native_ledger_standing_scope_self_api_v1":
       "public.respond_native_ledger_standing_scope_self_api_v1(uuid,text)",
    "public.assign_native_ledger_company_work_under_scope_owner_self_api_v1":
       "public.assign_native_ledger_company_work_under_scope_owner_self_api_v1(uuid,uuid,text)",
    "public.connected_person_my_work_self_api_v1":
       "public.connected_person_my_work_self_api_v1(integer,uuid)",
    "public.company_work_accountability_native_ledger_self_api_v1":
       "public.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)",
    "public.report_connected_person_company_work_self_api_v1":
       "public.report_connected_person_company_work_self_api_v1(uuid,text,text,jsonb)",
}
PUBLIC_CALLS = tuple(k for k in FUNCTIONS if k.startswith("public."))

class Refused(RuntimeError):
    pass

def need(condition, reason):
    if not condition:
        raise Refused(reason)

def guard_url(raw, temp):
    try:
        u=urlsplit(raw)
        port=u.port
    except ValueError:
        raise Refused("Invalid E05 database URL") from None
    need(u.scheme=="postgresql" and u.hostname=="127.0.0.1" and
         isinstance(port,int) and 1<=port<=65535 and port!=55432 and
         u.username=="postgres" and u.password is None and
         u.path.count("/")==1 and DB_NAME.fullmatch(u.path[1:]) and
         u.query in ("","sslmode=disable") and not u.fragment,
         "Only uncredentialed loopback named E05 test database permitted")
    need(temp.is_dir() and not temp.is_symlink(), "RUNNER_TEMP must be a real directory")
    return u.path[1:]

def surface_sql():
    # Every identifier and signature is static reviewed Source, never an input.
    values=[]
    for name in RELATIONS:
        values.append(f"'{name}',to_regclass('{name}') IS NOT NULL")
    for name,sig in FUNCTIONS.items():
        values.append(f"'{name}',to_regprocedure('{sig}') IS NOT NULL")
    for role in ("anon","authenticated","authenticator"):
        values.append(f"'role.{role}',to_regrole('{role}') IS NOT NULL")
    for name in PUBLIC_CALLS:
        sig=FUNCTIONS[name]
        values.append(f"'acl.authenticated.{name}',has_function_privilege('authenticated',to_regprocedure('{sig}'),'EXECUTE')")
        values.append(f"'acl.anon.denied.{name}',NOT has_function_privilege('anon',to_regprocedure('{sig}'),'EXECUTE')")
    values.extend((
        "'role.authenticator.authenticated',pg_has_role('authenticator','authenticated','MEMBER')",
        "'role.authenticator.anon',pg_has_role('authenticator','anon','MEMBER')",
        "'empty.auth.users',(SELECT count(*)=0 FROM auth.users)",
        "'empty.atlas.work_items',(SELECT count(*)=0 FROM atlas.work_items)",
        "'empty.atlas.organizations',(SELECT count(*)=0 FROM atlas.organizations)",
        "'empty.ledger.seats',(SELECT count(*)=0 FROM ledger.seats)",
        "'empty.reality.person',(SELECT count(*)=0 FROM reality.entities WHERE entity_kind='person')",
    ))
    return ("SELECT jsonb_build_object('database',current_database(),"
            "'server',host(inet_server_addr()),'pgdata',current_setting('data_directory'),"
            "'surfaces',jsonb_build_object("+",".join(values)+"));")

def check(result, database, temp):
    need(isinstance(result,dict) and
         set(result)=={"database","server","pgdata","surfaces"},
         "Unrecognized E05 catalog response")
    need(result["database"]==database and result["server"]=="127.0.0.1",
         "E05 local database/server identity mismatch")
    need(isinstance(result["pgdata"],str),"E05 PGDATA absent")
    pgdata=Path(result["pgdata"]).resolve(strict=True)
    need(temp in pgdata.parents and pgdata.is_dir(),
         "PGDATA must belong to the fresh job's RUNNER_TEMP")
    expected=set(RELATIONS)|set(FUNCTIONS)|{"role.anon","role.authenticated",
        "role.authenticator","role.authenticator.authenticated",
        "role.authenticator.anon","empty.auth.users","empty.atlas.work_items",
        "empty.atlas.organizations","empty.ledger.seats","empty.reality.person"}
    for name in PUBLIC_CALLS:
        expected.update(("acl.authenticated."+name,"acl.anon.denied."+name))
    found=result["surfaces"]
    need(isinstance(found,dict) and set(found)==expected,
         "Incomplete E05 source surface inventory")
    missing=sorted(name for name in expected if found[name] is not True)
    need(not missing,"Required E05 source/ACL/empty-state surface HELD: "+", ".join(missing))
    return {"state":"E05_SOURCE_ELIGIBLE_NOT_FULL_PARITY",
            "testDatabase":database,"checkedSurfaces":len(expected),
            "productionSchemaAndRolesSnapshot":"REQUIRED_SEPARATELY",
            "signedSourceAcceptance":"NOT_RUN","browserUserJourney":"NOT_RUN",
            "productionChanges":False,"permissionsChanged":False}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    supplied=os.environ.get("RUNNER_TEMP")
    need(bool(supplied),"RUNNER_TEMP is required")
    need(not Path(supplied).is_symlink(),"RUNNER_TEMP symlink denied")
    temp=Path(supplied).resolve(strict=True)
    database=guard_url(args.db_url,temp)
    output=Path(args.output).resolve()
    need(temp in output.parents and not output.exists() and not Path(args.output).is_symlink(),
         "Receipt must be a new job-local file")
    try:
        call=subprocess.run(
            ["psql",args.db_url,"-X","-A","-t","-v","ON_ERROR_STOP=1",
             "-c",surface_sql()],capture_output=True,text=True,timeout=35)
    except (OSError,subprocess.SubprocessError):
        raise Refused("E05 local read-only catalog query unavailable") from None
    need(call.returncode==0,"E05 local catalog query refused; SQL diagnostics withheld")
    try:
        data=json.loads(call.stdout)
    except (ValueError,TypeError):
        raise Refused("Invalid E05 catalog JSON") from None
    receipt=check(data,database,temp)
    fd=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(receipt,f,indent=2)
        f.write("\n")
    print("E05_REQUIRED_SOURCE=PASS; FULL_SCHEMA_PARITY=NOT_PROVEN; SIGNED=NOT_RUN")

if __name__=="__main__":
    try:
        main()
    except (Refused,OSError,ValueError) as exc:
        print(str(exc) if isinstance(exc,Refused) else
              "E05 readiness unavailable; private diagnostics withheld")
        raise SystemExit(1) from None

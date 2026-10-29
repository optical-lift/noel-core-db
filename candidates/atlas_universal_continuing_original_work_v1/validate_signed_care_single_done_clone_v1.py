#!/usr/bin/env python3
"""Held signed CARE -> one Done proof; FRESH disposable local clone ONLY.

Prerequisites: full native schema, canonical held original Work migration and
fictional fixture, both held Done/care draft sources, and the companion
signed_care_single_done_fictional_fixture_v1.sql. Local GoTrue+PostgREST must
be running. This does not grant the unreleased care writer to a browser:
private source methods are exercised via privileged clone SQL with claims
from real, verified, separately signed GoTrue sessions. Public My Work and
disclosure are tested via bearer HTTP. This is NOT an end-user API release test.

This script creates fictional data only on the validator's disposable clone.
"""
import argparse
import importlib.util
import json
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]/"scripts"
SPEC=importlib.util.spec_from_file_location(
    "signed_care_base",ROOT/"validate-atlas-work-prerequisite-signed-http.py")
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Canonical signed Work test module unavailable")
base=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)
c1=base.c1

ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
BED3="e5200000-0000-4000-8000-000000000b03"
BED4="e5200000-0000-4000-8000-000000000b04"
STATE="ec300000-0000-4000-8000-000000000003"
ACTION="ec300000-0000-4000-8000-000000000010"
PARTIAL="ec300000-0000-4000-8000-000000000011"
FULL="ec300000-0000-4000-8000-000000000012"

def check(test,message):
    if not test: raise AssertionError(message)

def sql(db,q):
    return c1.sql(db,q)

def literal(value):
    return "'"+str(value).replace("'","''")+"'"

def signed_source(db,token,func_sql,expected_error=None):
    # Do not manufacture or accept unsigned JWTs: caller MUST have received
    # this token from local GoTrue sign_in. Verify the recorded local session.
    claims=c1.jwt_payload(token)
    uid=claims.get("sub")
    sid=claims.get("session_id")
    check(claims.get("role")=="authenticated"
          and bool(re.fullmatch(r"[0-9a-f-]{36}",str(uid)))
          and bool(re.fullmatch(r"[0-9a-f-]{36}",str(sid))),
          "Source invocation requires genuine signed JWT identity and session")
    check(sql(db,f"select count(*) from auth.sessions where "
                 f"id={literal(sid)}::uuid and user_id={literal(uid)}::uuid")=="1",
          "Signed session no longer exists on the disposable clone")
    encoded=json.dumps(claims,separators=(",",":"))
    # Privileged clone SQL invokes the unreleased private method. We do NOT
    # claim that the worker can call this method through PostgREST.
    statement=(
      "BEGIN;\n"
      "SELECT set_config('request.jwt.claims',"+literal(encoded)+",true);\n"
      "SELECT set_config('request.jwt.claim.sub',"+literal(uid)+",true);\n"
      "SELECT ("+func_sql+")::text;\n"
      "COMMIT;\n"
    )
    result=subprocess.run(
      ["psql",db,"-X","-A","-t","-v","ON_ERROR_STOP=1",
       "-v","VERBOSITY=verbose","-c",statement],
      capture_output=True,text=True,check=False)
    if expected_error is not None:
        check(result.returncode!=0 and
              re.search(r"\b"+re.escape(expected_error)+r"\b",result.stderr),
              f"Expected source SQLSTATE {expected_error}, got: "
              +result.stderr[-500:])
        return None
    check(result.returncode==0,
          "Signed private clone source rejected: "+result.stderr[-900:])
    candidates=[line.strip() for line in result.stdout.splitlines()
                if line.lstrip().startswith("{")]
    check(bool(candidates),"Private clone source did not return JSON")
    return json.loads(candidates[-1])

def rpc(api,key,token,name,payload):
    return base.rpc(api,key,token,name,payload)

def allow(api,key,token,name,payload):
    status,obj=rpc(api,key,token,name,payload)
    check(status==200 and isinstance(obj,dict) and obj.get("ok") is True,
          f"Signed {name} failed {status}: {str(obj)[:350]}")
    return obj

def deny(api,key,token,name,payload,label):
    status,obj=rpc(api,key,token,name,payload)
    check(status in (401,403) and isinstance(obj,dict)
          and (token is None or obj.get("code")=="42501"),
          f"{label}: expected genuine source 42501, NOT missing RPC: "
          f"{status} {str(obj)[:350]}")
    print("PASS",label)

def care_call(work,action,kind,condition):
    return ("atlas.record_continuing_care_actual_self_api_v1("
            f"{literal(work)}::uuid,{literal(action)}::uuid,"
            f"{literal(kind)}::text,{literal(condition)}::text,"
            "12::integer,'Fictional physically observed care in Bed 3'::text,"
            "NULL::date)")

def work_reader(work,bed):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
       p_work_item_id=work,p_subject_domain="spatial",
       p_subject_kind="growing_object",p_subject_id=bed)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--db-url",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()
    check(bool(re.fullmatch(
      r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:54322/postgres",args.db_url)),
      "Only fresh disposable Supabase local database 127.0.0.1:54322 admitted")
    check(sql(args.db_url,"select current_database()")=="postgres",
          "Expected disposable clone")
    check(sql(args.db_url,
       "select count(*) from atlas.rhythm_state where "
       f"id={literal(STATE)}::uuid and state='due'")=="1",
       "Exact fictional Bed 3 care state missing")
    check(sql(args.db_url,
       "select count(*) from atlas.work_items where "
       f"source_object_id={literal(STATE)}::uuid")=="0",
       "Fictional care proof must start without an existing Work")
    for signature in (
      "atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)",
      "atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)",
      "atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)"
    ):
        check(sql(args.db_url,
            "select count(*) from pg_proc where oid=to_regprocedure("
            +literal(signature)+")")=="1","Missing combined private source "+signature)
        check(sql(args.db_url,
            "select has_function_privilege('authenticated',"
            "to_regprocedure("+literal(signature)+"),'EXECUTE')")=="f",
            "Unreleased private source was exposed to authenticated")

    api,key=c1.local_status()
    tokens={}
    for name,uid in base.setup_auth(args.db_url):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),
              "Failed genuine GoTrue signed identity "+name)
        check(sql(args.db_url,
             "select count(*) from auth.sessions where id="
             +literal(claims["session_id"])+"::uuid and user_id="
             +literal(uid)+"::uuid")=="1",
             "GoTrue session not stored for "+name)
        tokens[name]=token
    check(len(set(tokens.values()))==4,
          "Expected four separate signed sessions")
    owner,worker,outsider=tokens["owner"],tokens["worker"],tokens["outsider"]
    print("PASS four genuine, independent local GoTrue sessions")

    proposal=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_worker_person_id="e5200000-0000-4000-8000-000000000102",
      p_organization_unit_id=None,p_coverage_mode="ledger_all_work",
      p_operation_class=None,
      p_terms="Clone-only accepted physical care responsibility, exact Ledger.",
      p_valid_until=None)
    deny(api,key,worker,"propose_native_ledger_standing_scope_owner_self_api_v1",
         proposal,"Worker cannot govern a care scope")
    scope=allow(api,key,owner,
       "propose_native_ledger_standing_scope_owner_self_api_v1",proposal).get("scopeId")
    check(scope and re.fullmatch(r"[0-9a-f-]{36}",scope),
          "Governed scope not created")
    deny(api,key,outsider,"respond_native_ledger_standing_scope_self_api_v1",
      {"p_scope_id":scope,"p_decision":"accept"},
      "Unconnected outsider cannot accept worker responsibility")
    allow(api,key,worker,"respond_native_ledger_standing_scope_self_api_v1",
       {"p_scope_id":scope,"p_decision":"accept"})

    create=("atlas.owner_establish_observed_continuing_care_work_self_api_v1("
       f"{literal(ORG)}::uuid,{literal(LEDGER)}::uuid,"
       f"{literal(STATE)}::uuid,{literal(scope)}::uuid,'heavy'::text,"
       "'Fictional heavy weeds visually observed today'::text,"
       "clock_timestamp(),(now() AT TIME ZONE 'America/Chicago')::date,"
       f"{literal(ACTION)}::uuid)")
    signed_source(args.db_url,owner,create,"42501")
    for field,suffix in (("identity","001"),("condition","002")):
        disclosure=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
          p_target_person_id="e5200000-0000-4000-8000-000000000102",
          p_subject_domain="spatial",p_subject_kind="growing_object",
          p_subject_id=BED3,p_disclosure_class=field,
          p_decision_kind="grant",
          p_source_action_id="ec300000-0000-4000-8000-000000000"+suffix,
          p_reason="Exact fictional Bed 3 information is necessary for assigned care.")
        allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",disclosure)
    made=signed_source(args.db_url,owner,create)
    check(made.get("ok") is True and made.get("newOriginalWorkCreated") is True,
          "Governor failed to establish governed original care Work")
    work=made["workItemId"]
    print("PASS governor source observation and one bounded original Work")

    allow(api,key,worker,"connected_person_original_work_subject_self_api_v1",
          work_reader(work,BED3))
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
          work_reader(work,BED4),
          "Withheld Bed 4 is not inferred from Bed 3 care")
    deny(api,key,outsider,"connected_person_original_work_subject_self_api_v1",
          work_reader(work,BED3),
          "Outsider cannot find Bed 3 physical Work subject")
    signed_source(args.db_url,outsider,care_call(work,FULL,"weeded_full","clear"),
                  "42501")
    signed_source(args.db_url,owner,care_call(work,FULL,"weeded_full","clear"),
                  "42501")
    signed_source(args.db_url,worker,care_call(work,FULL,"weeded_full","heavy"),
                  "22023")
    partial=signed_source(args.db_url,worker,
       care_call(work,PARTIAL,"weeded_partial","row_readable"))
    check(partial.get("workState")=="open" and
          partial.get("noNewWorkCreated") is True,
          "Partial care manufactured a Done or next Work")
    check(sql(args.db_url,
       "select count(*) from atlas.work_lifecycle_events_v1 where "
       f"work_item_id={literal(work)}::uuid and event_kind='work_transition_applied'")=="0",
       "Partial care illegally completed universal Work")
    print("PASS signed partial Actual retains original open Work")
    full=signed_source(args.db_url,worker,
       care_call(work,FULL,"weeded_full","clear"))
    check(full.get("workState")=="completed" and
          full.get("contractVersion")=="universal_work_lifecycle_transition_v1"
          and full.get("physicalActualContractVersion")=="continuing_care_actual_v1",
          "Signed physical care did not use common Done")
    replay=signed_source(args.db_url,worker,
       care_call(work,FULL,"weeded_full","clear"))
    check(replay.get("idempotent") is True and
          replay.get("eventId")==full.get("eventId"),
          "Signed replay changed the immutable Work transition")
    check(sql(args.db_url,
       "select count(*) from atlas.work_lifecycle_events_v1 where "
       f"work_item_id={literal(work)}::uuid and event_kind='work_transition_applied'")=="1",
       "Source produced duplicate Done events")
    check(sql(args.db_url,
       "select count(*) from atlas.rhythm_satisfactions where "
       f"rhythm_state_id={literal(STATE)}::uuid and satisfaction_kind='full'")=="1",
       "Physical Actual did not satisfy exact rhythm")
    check(sql(args.db_url,
       "select count(*) from atlas.work_items where "
       f"source_object_id={literal(STATE)}::uuid")=="1",
       "Physical completion manufactured another original Work")
    print("PASS physical Result -> exactly one immutable Done -> rhythm satisfaction")
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS local GoTrue independent sessions, disclosure, signed-claim private "
      "source invocation, partial/full Actual, single lifecycle Done and replay.\n"
      "NOT PROVEN: browser HTTP access to private functions; standing "
      "care release; successor Work/Today.\n",encoding="utf-8")

if __name__=="__main__":
    main()

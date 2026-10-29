#!/usr/bin/env python3
"""Held signed CARE -> one Done proof; FRESH disposable local clone ONLY.

Prerequisites: full native schema, canonical held original Work migration and
fictional fixture, both held Done/care draft sources, and the companion
signed_care_single_done_fictional_fixture_v1.sql. Local GoTrue+PostgREST must
be running. The owner-only observed-Need source remains a private privileged test
invocation using claims from a verified GoTrue session. The *physical Actual*
must run through the real authenticated public PostgREST RPC with the
worker's actual bearer token; no fabricated claims or elevated SQL substitute
for this end-user reporting test. This is a protected clone, NOT a release.

This script creates fictional data only on the validator's disposable clone.
"""
import argparse
import importlib.util
import json
import re
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
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
CARE_RPC="record_continuing_care_actual_self_api_v1"
CARE_SIG="public.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)"

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

def care_args(work,action,kind,condition):
    return dict(p_work_item_id=work,p_action_id=action,
                p_actual_kind=kind,p_condition_after=condition,
                p_minutes=12,
                p_note="Fictional physically observed care in Bed 3",
                p_recheck_on=None)

def refused_care(api,key,token,payload,label,expected="42501",code=403):
    status,obj=rpc(api,key,token,CARE_RPC,payload)
    check(status==code and isinstance(obj,dict)
          and obj.get("code")==expected,
          f"{label}: expected real signed source denial {code}/{expected}, "
          f"got {status} / {str(obj)[:350]}")
    print("PASS",label)

def source_policy(scope,method,governor="full_eligibility",worker="assigned_work_only",action="021"):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_rhythm_state_id=STATE,p_scope_id=scope,
      p_authorization_method=method,p_governor_visibility=governor,
      p_worker_visibility=worker,p_eligibility_window="due",
      p_observation_max_age_seconds=259200,
      p_reason="Fictional exact Bed 3 steward rhythm and current physical source only.",
      p_action_id="ec300000-0000-4000-8000-000000000"+action)

def eligibility_args():
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                p_rhythm_state_id=STATE)

def disclosed_rhythms(api,key,token,limit=30,after=None):
    obj=allow(api,key,token,"connected_person_disclosed_standing_rhythms_self_api_v1",
      dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_limit=limit,
           p_after_state_id=after))
    check(obj.get("contractVersion")=="connected_person_disclosed_standing_rhythms_v1"
          and obj.get("organizationId")==ORG and obj.get("ledgerId")==LEDGER
          and obj.get("coverage")=="admitted_person_only"
          and obj.get("noWorkCreated") is True
          and obj.get("notAnExecutionPlan") is True
          and obj.get("notAnAutomaticOverdueBacklog") is True
          and obj.get("noUndisclosedCounts") is True
          and isinstance(obj.get("items"),list)
          and isinstance(obj.get("hasMore"),bool),
          "Signed care list lacks bounded admission contract")
    return obj

def physical_observation(action,condition):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                p_rhythm_state_id=STATE,p_condition=condition,
                p_note="Fictional on-site signed physical observation in Bed 3.",
                p_action_id="ec300000-0000-4000-8000-000000000"+action)

def standing_admission(action,service_day):
    return dict(p_organization_id=ORG,p_ledger_id=LEDGER,
       p_rhythm_state_id=STATE,
       p_action_id="ec300000-0000-4000-8000-000000000"+action,
       p_service_date=service_day)

def reject_admission(api,key,token,payload,label,sqlstate="42501"):
    status,obj=rpc(api,key,token,"admit_standing_continuing_source_work_self_api_v1",payload)
    check(status in (400,403) and isinstance(obj,dict) and
          obj.get("code")==sqlstate,
          f"{label}: expected source SQLSTATE {sqlstate}, not missing RPC: "
          f"{status} {str(obj)[:400]}")
    print("PASS",label)

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
      r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
      "Only disposable local Supabase postgres at 127.0.0.1 admitted")
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
    check(sql(args.db_url,
       "select has_function_privilege('authenticated',"
       "to_regprocedure("+literal(CARE_SIG)+"),'EXECUTE')")=="t",
       "Signed care reporting RPC must be allowed for authenticated")
    check(sql(args.db_url,
       "select has_function_privilege('anon',"
       "to_regprocedure("+literal(CARE_SIG)+"),'EXECUTE')")=="f",
       "Anonymous browser was given executable care reporting RPC")
    check(sql(args.db_url,
       "select count(*) from pg_proc where oid=to_regprocedure("
       +literal(CARE_SIG)+") and prosecdef and "
       "'search_path=\"\"'=any(proconfig)")=="1",
       "Bounded signed care RPC must use a fixed empty search_path")
    print("PASS private writers denied, public care reporter authenticated-only")
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

    check(disclosed_rhythms(api,key,worker)["items"]==[],
          "Native standing scope alone leaked undisclosed care")
    deny(api,key,outsider,"connected_person_disclosed_standing_rhythms_self_api_v1",
         dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_limit=30,p_after_state_id=None),
         "Outsider cannot enumerate standing care")
    deny(api,key,worker,"connected_person_disclosed_standing_rhythms_self_api_v1",
         dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_limit=0,p_after_state_id=None),
         "Zero limit is rejected by signed source")

    # A current accepted connection by itself does not expose governing
    # source eligibility. Every policy/method/visibility is owner-chosen.
    deny(api,key,worker,"owner_decide_continuing_source_governance_self_api_v1",
         source_policy(scope,"owner_each_cycle"),"Worker cannot establish its own standing authority")
    allow(api,key,owner,"owner_decide_continuing_source_governance_self_api_v1",
          source_policy(scope,"owner_each_cycle"))
    deny(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
         eligibility_args(),"Assigned-only visibility cannot enumerate eligible sources")
    # The test fixture's civil due boundaries are made past ONLY on the
    # disposable synthetic clone; no manual Work or actual is created.
    sql(args.db_url,
        "update atlas.rhythm_state set warning_at=now()-interval '2 hours',"
        "due_at=now()-interval '1 hour' where id="+literal(STATE)+"::uuid")
    print("PASS governor's per-cycle authority and worker assigned-only source privacy")

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
    # The governor may later establish standing approval by an append-only
    # change of authority. Worker eligibility still needs exact field grants
    # AND fresh physical evidence after any qualifying satisfaction.
    allow(api,key,owner,"owner_decide_continuing_source_governance_self_api_v1",
        source_policy(scope,"standing_source_observed",worker="eligible_disclosed",action="022"))
    listed=disclosed_rhythms(api,key,worker,limit=1)
    check(len(listed["items"])==1
          and listed["items"][0].get("rhythmStateId")==STATE
          and listed["items"][0].get("rhythmKind")=="weed_stewardship"
          and listed["items"][0].get("isWork") is False
          and listed["items"][0].get("isAssignment") is False
          and listed.get("hasMore") is False,
          "Exact authorized Bed 3 source was not exposed once")
    check(disclosed_rhythms(api,key,worker,limit=1,after=STATE)["items"]==[],
          "Pagination repeated or leaked an undisclosed care item")
    check(sql(args.db_url,"select count(*) from atlas.work_items where source_object_id="
          +literal(STATE)+"::uuid")=="0",
          "Read-only standing list created original Work")
    disclosure_change=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_target_person_id="e5200000-0000-4000-8000-000000000102",
      p_subject_domain="spatial",p_subject_kind="growing_object",
      p_subject_id=BED3,p_disclosure_class="condition",
      p_decision_kind="withhold",
      p_source_action_id="ec300000-0000-4000-8000-000000000028",
      p_reason="Fictional owner pauses the physical Bed 3 condition disclosure.")
    allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",disclosure_change)
    check(disclosed_rhythms(api,key,worker)["items"]==[],
          "Withheld Subject condition remained discoverable")
    disclosure_change["p_decision_kind"]="grant"
    disclosure_change["p_source_action_id"]="ec300000-0000-4000-8000-000000000029"
    disclosure_change["p_reason"]="Fictional owner restores exact Bed 3 condition disclosure."
    allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",disclosure_change)
    check(len(disclosed_rhythms(api,key,worker)["items"])==1,
          "Restored Subject grant did not restore exact standing row")
    print("PASS signed worker identity, field withhold, pagination and no-clock Work")

    no_evidence=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                      eligibility_args())
    check(no_evidence.get("eligible") is False and
          no_evidence.get("reasonCode")=="fresh_physical_observation_required",
          "A due clock was promoted without fresh physical evidence")
    refused_care(api,key,outsider,
       care_args("00000000-0000-4000-8000-000000000090",FULL,"weeded_full","clear"),
       "Unknown outsider cannot report care",expected="42501")
    deny(api,key,outsider,"continuing_work_source_eligibility_self_api_v1",
         eligibility_args(),"Outsider cannot enumerate eligible Bed 3")
    seen=allow(api,key,worker,"record_standing_care_observation_self_api_v1",
               physical_observation("023","clear"))
    check(seen.get("noWorkCreated") is True,"Observation invented Work")
    not_needed=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                     eligibility_args())
    check(not_needed.get("eligible") is False
          and not_needed.get("reasonCode")=="physical_condition_or_strategy_not_eligible",
          "A clear physical observation was misread as Work demand")
    fresh=allow(api,key,worker,"record_standing_care_observation_self_api_v1",
                physical_observation("024","heavy"))
    check(fresh.get("noWorkCreated") is True,"Standing approval secretly created Work")
    retry=allow(api,key,worker,"record_standing_care_observation_self_api_v1",
                physical_observation("024","heavy"))
    check(retry.get("idempotent") is True and
          retry.get("sourceObservationId")==fresh.get("sourceObservationId"),
          "Signed observation replay was not idempotent")
    eligible=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                   eligibility_args())
    check(eligible.get("eligible") is True
          and eligible.get("notOnToday") is True
          and eligible.get("noWorkCreated") is True,
          "Fresh physical source must be eligible but must not silently schedule Work")
    check(sql(args.db_url,"select count(*) from atlas.work_items where source_object_id="
              +literal(STATE)+"::uuid")=="0",
          "Policy or observation silently minted an original Work")
    allow(api,key,owner,"owner_decide_continuing_source_governance_self_api_v1",
        source_policy(scope,"standing_source_observed",governor="exceptions_only",
                      worker="eligible_disclosed",action="025"))
    owner_projection=allow(api,key,owner,"continuing_work_source_eligibility_self_api_v1",
                           eligibility_args())
    check(owner_projection.get("visible") is False,
          "Governor exception-only visibility ignored")
    print("PASS owner-selected standing method, real signed worker observations and source-enforced views")

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
    refused_care(api,key,outsider,
      care_args(work,FULL,"weeded_full","clear"),
      "Outsider signed browser cannot report Bed 3 physical care")
    refused_care(api,key,owner,
      care_args(work,FULL,"weeded_full","clear"),
      "Governor signed browser cannot report unassigned worker care")
    refused_care(api,key,worker,
      care_args(work,FULL,"weeded_full","heavy"),
      "Invalid full-care condition is source-rejected",expected="22023",code=400)
    partial=allow(api,key,worker,CARE_RPC,
       care_args(work,PARTIAL,"weeded_partial","row_readable"))
    check(partial.get("workState")=="open" and
          partial.get("noNewWorkCreated") is True,
          "Partial care manufactured a Done or next Work")
    check(sql(args.db_url,
       "select count(*) from atlas.work_lifecycle_events_v1 where "
       f"work_item_id={literal(work)}::uuid and event_kind='work_transition_applied'")=="0",
       "Partial care illegally completed universal Work")
    print("PASS signed partial Actual retains original open Work")
    full=allow(api,key,worker,CARE_RPC,
       care_args(work,FULL,"weeded_full","clear"))
    check(full.get("workState")=="completed" and
          full.get("contractVersion")=="universal_work_lifecycle_transition_v1"
          and full.get("physicalActualContractVersion")=="continuing_care_actual_v1",
          "Signed physical care did not use common Done")
    replay=allow(api,key,worker,CARE_RPC,
       care_args(work,FULL,"weeded_full","clear"))
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
    print("PASS real bearer HTTP: physical Result -> single Done -> rhythm satisfaction")
    # An unrelated Person cannot retrieve the completed Work receipt by
    # replaying the worker's known action ID.
    refused_care(api,key,outsider,
      care_args(work,FULL,"weeded_full","clear"),
      "Outsider HTTP retry of another Person's completed action denied")
    # Direct private function privilege remains denied, not merely a missing
    # PostgREST cache entry masquerading as a 404 success.
    check(sql(args.db_url,
       "select has_function_privilege('authenticated',"
       "to_regprocedure('atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)'),"
       "'EXECUTE')")=="f","Private care writer leaked direct EXECUTE")
    print("PASS authenticated-only public care RPC and private writer membrane")
    # A completed physical cycle resets rhythm timing. The next observation
    # cannot be eligible merely because the previous one reported need.
    after_full=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                     eligibility_args())
    check(after_full.get("eligible") is False and
          after_full.get("reasonCode")=="rhythm_window_not_reached",
          "Completed care incorrectly admitted immediate next Work")
    # The next cycle may be admitted ONLY after its own fresh observation
    # and a new due window. The worker deliberately selects the service day;
    # the clock alone cannot create Work or a Today item.
    from datetime import datetime
    from zoneinfo import ZoneInfo
    day=datetime.now(ZoneInfo("America/Chicago")).date().isoformat()
    reject_admission(api,key,worker,standing_admission("030",day),
      "New Work is not admitted before the next rhythm window",
      sqlstate="23514")
    sql(args.db_url,
      "update atlas.rhythm_state set warning_at=now()-interval '2 hours',"
      "due_at=now()-interval '1 hour' where id="+literal(STATE)+"::uuid")
    still_missing=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                      eligibility_args())
    check(still_missing.get("eligible") is False and
       still_missing.get("reasonCode")=="fresh_physical_observation_required",
       "Next due window without new physical observation created eligibility")
    latest=allow(api,key,worker,"record_standing_care_observation_self_api_v1",
            physical_observation("028","heavy"))
    check(latest.get("noWorkCreated") is True,
          "Renewed worker physical observation manufactured a Work")
    next_eligible=allow(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
                   eligibility_args())
    check(next_eligible.get("eligible") is True,
          "Signed fresh physical observation did not qualify due Need")
    reject_admission(api,key,outsider,standing_admission("030",day),
       "Outsider cannot admit standing Work")
    reject_admission(api,key,owner,standing_admission("030",day),
       "Unassigned governor cannot impersonate delegated standing worker")
    admitted=allow(api,key,worker,"admit_standing_continuing_source_work_self_api_v1",
                 standing_admission("030",day))
    nextwork=admitted.get("workItemId")
    check(admitted.get("newOriginalWorkCreated") is True and nextwork
          and nextwork!=work and admitted.get("serviceDate")==day,
       "Exact native successor Work and deliberate worker day not created")
    repeat=allow(api,key,worker,"admit_standing_continuing_source_work_self_api_v1",
                 standing_admission("030",day))
    check(repeat.get("idempotent") is True
          and repeat.get("workItemId")==nextwork,
          "Standing source action replay duplicated the original Work")
    reject_admission(api,key,worker,standing_admission("031",day),
       "Another action cannot duplicate open standing Need",sqlstate="23514")
    check(sql(args.db_url,
      "select count(*) from atlas.work_items where source_object_id="
      +literal(STATE)+"::uuid")=="2",
      "Completed original plus one new open serving must be exactly two")
    check(sql(args.db_url,
      "select count(*) from atlas.company_work_native_ledger_relevance "
      "where work_item_id="+literal(nextwork)+"::uuid "
      "and source_schema='atlas' "
      "and source_table='continuing_work_source_governance_events_v1' "
      "and evidence_kind='source_verified'")=="1",
      "Standing worker falsely claimed a new owner attestation instead of source verified")
    my_work=allow(api,key,worker,"connected_person_my_work_self_api_v1",
          {"p_limit":50,"p_after_allocation_id":None})
    displayed=[item for item in my_work.get("items",[])
              if item.get("workItemId")==nextwork]
    check(len(displayed)==1
          and displayed[0].get("workOn")==day
          and displayed[0].get("scheduleState")=="scheduled"
          and displayed[0].get("workRelevanceVerified") is True,
          "Native Person My Work failed to show one disclosure-verified scheduled Work")
    invisible=allow(api,key,outsider,"connected_person_my_work_self_api_v1",
          {"p_limit":50,"p_after_allocation_id":None})
    check(all(item.get("workItemId")!=nextwork for item in invisible.get("items",[])),
      "New original Work leaked into outsider's My Work")
    deny(api,key,worker,"connected_person_original_work_subject_self_api_v1",
         work_reader(nextwork,BED4),
         "New standing Bed 3 Work cannot disclose the withheld Bed 4")
    print("PASS owner-standing source -> one native Work + verified Person-day Today, no duplicate")
    allow(api,key,owner,"owner_decide_continuing_source_governance_self_api_v1",
          source_policy(scope,"hold",governor="full_eligibility",
                        worker="assigned_work_only",action="026"))
    deny(api,key,worker,"continuing_work_source_eligibility_self_api_v1",
         eligibility_args(),"Governor hold immediately revokes upcoming source visibility")
    check(disclosed_rhythms(api,key,worker)["items"]==[],
          "Governor hold failed to remove standing rhythm source")
    deny(api,key,worker,"record_standing_care_observation_self_api_v1",
         physical_observation("027","heavy"),
         "Governor hold revokes worker new observation authority")
    reject_admission(api,key,worker,standing_admission("032",day),
      "Owner hold also revokes further standing Work admission")
    print("PASS complete->resting; new source-qualified Work/Today; owner hold immediately revokes")
    # The original care source also runs against older held candidates.
    # Require this *additional* signed matrix when an exact historical
    # review API exists; otherwise explicitly log the omitted scope.
    historical_summary=""
    history_sig=("public.governor_link_historical_self_adoption_self_api_v1"
                 "(uuid,uuid,uuid,uuid,uuid,uuid)")
    if sql(args.db_url,"select to_regprocedure("+literal(history_sig)+") is not null")=="t":
        import sys
        hist_spec=importlib.util.spec_from_file_location(
          "signed_historical_source",ROOT/"validate-atlas-historical-self-adoption-signed-http.py")
        check(hist_spec is not None and hist_spec.loader is not None,
              "Historical signed proof module unavailable")
        hist=importlib.util.module_from_spec(hist_spec)
        hist_spec.loader.exec_module(hist)
        historical_summary=hist.proof(args.db_url,api,key,tokens,sys.modules[__name__])
    else:
        historical_summary="NOT TESTED: historical review source not present in this candidate.\n"
    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
      "PASS local GoTrue independent sessions, disclosure, private governor "
      "source, real signed bearer HTTP physical Actual partial/full/invalid/denied, "
      "one lifecycle Done, replay and rhythm satisfaction.\n"
      "PASS immutable owner-selected source methods, exact worker visibility, "
      "clock plus physical evidence, genuine signed observation, hold/revoke, "
      "no Work or Today without explicit source-qualified admission.\n"
      "PASS delegated native Work admission via real signed worker and explicit date, "
      "one scheduled Today row, replay, outsider denial, and no second open serving.\n"
      historical_summary+
      "NOT PROVEN: production rollout, standing care release, next-bed Today.\n",
      encoding="utf-8")

if __name__=="__main__":
    main()

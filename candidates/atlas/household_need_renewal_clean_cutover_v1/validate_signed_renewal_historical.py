#!/usr/bin/env python3
"""Separate, fictional historical-load setup and genuine signed due HTTP proof.

Never modifies the initial signed proof's observations or timestamps. Setup
inserts NEW synthetic historical rows into a fresh localhost disposable clone.
The setup is DML test data, NOT a claim of historical signed RPC execution.
All actual due reads, decisions and subsequent observations use real
independent GoTrue JWTs over HTTP, with the unmodified production functions.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path
from uuid import UUID

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location("original_work_prerequisite",
    ROOT/"scripts/validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
due_spec=importlib.util.spec_from_file_location("renewal_due",
    Path(__file__).resolve().with_name("validate_signed_renewal_due.py"))
due=importlib.util.module_from_spec(due_spec)
due_spec.loader.exec_module(due)
H=due.HOUSEHOLD
I=due.INSTANCE
U="e5200000-0000-4000-8000-000000000001"
P="e5200000-0000-4000-8000-000000000101"

def ident(suffix):
    return str(UUID("e5200000-0000-4000-8000-00000000"+suffix))

def historical_fixture(claims):
    # The SQL context is supplied from the actual verified synthetic local
    # session solely for fixture guards. This setup is not signed HTTP proof.
    # No triggers, permissions, existing rows or clock functions are changed.
    who=str(UUID(claims["sub"]))
    sid=str(UUID(claims["session_id"]))
    base.check(who==U and claims["role"]=="authenticated","Exact fixture owner session")
    ctx=json.dumps({"sub":who,"session_id":sid,"role":"authenticated","aud":"authenticated"})
    statements=["begin",f"select set_config('request.jwt.claims','{ctx}',true)",
        f"select atlas.require_household_governor_self_v1('{H}')"]
    steps=[
      ("begin_cycle","ready_for_cycle","washing","wash_started","intervene","observe",0,10),
      ("begin_drying","wet_ready_for_drying","drying","drying_started","intervene","observe",70,75),
      ("return_to_use","dry_ready_for_return","returned_to_use","returned_to_use","intervene","observe",135,140),
    ]
    for index,(need_key,before,after,step,disposition,after_disposition,start,end) in enumerate(steps,1):
        def key(n): return ident(f"{index:02x}{n:02x}")
        opened,need,work,result,obs,execution,acceptance,action=[key(n) for n in range(1,9)]
        contract={"begin_cycle":"household_laundry_begin_cycle_v1",
                  "begin_drying":"household_laundry_begin_drying_v1",
                  "return_to_use":"household_laundry_return_to_use_v1"}[need_key]
        t0=f"(transaction_timestamp()-interval '3 days'+interval '{start} minutes')"
        t1=f"(transaction_timestamp()-interval '3 days'+interval '{end} minutes')"
        source=f"clone-historical-laundry:{work}"
        statements += [
          f"""insert into atlas.care_observation_events(id,subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,condition_state,disposition,observed_by_user_id,source_kind,source_key,note,inferred_from_clock,metadata)
          values('{opened}','household','household_kernel_instance','{I}','household','{H}',{t0},'{before}','{disposition}','{U}','clone_historical_laundry_fixture','{source}:before','Fictional historical condition.',false,'{{"cloneFixture":true}}')""",
          f"""insert into atlas.household_need_occurrences_v1(id,household_id,instance_id,need_key,state,opened_by_observation_id,source_action_id,created_at,updated_at)
          values('{need}','{H}','{I}','{need_key}','open','{opened}','{action}',{t0},{t0})""",
          f"""insert into atlas.work_items(id,household_id,source_object_type,source_object_id,work_state,title,instructions,stable_key,result_contract_key,created_by_user_id,metadata,created_at,updated_at)
          values('{work}','{H}','household_need_occurrence','{need}','open','Fictional historical Laundry step','Synthetic fixture only','{source}','{contract}','{U}',jsonb_build_object('needOccurrenceId','{need}','cloneFixture',true),{t0},{t0})""",
          f"update atlas.household_need_occurrences_v1 set current_work_item_id='{work}' where id='{need}' and household_id='{H}'",
          f"""insert into atlas.work_item_context_links(household_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind,provenance,metadata)
          values('{H}','{work}','household','kernel_instance','{I}','acts_on','{{"cloneFixture":true}}','{{}}')""",
          f"""insert into atlas.care_result_events(id,subject_domain,subject_kind,subject_id,scope_kind,scope_id,result_kind,condition_before,condition_after,actor_user_id,source_kind,source_key,note,metadata,occurred_at)
          values('{result}','household','household_kernel_instance','{I}','household','{H}','improved_more_remains','{before}','{after}','{U}','household_laundry_physical_actual','{source}:result','Synthetic historical seed, not signed RPC.',jsonb_build_object('workItemId','{work}','needOccurrenceId','{need}','completedStep','{step}','wholeLaundryDone',false,'cloneFixture',true),{t1})""",
          f"""insert into atlas.care_observation_events(id,subject_domain,subject_kind,subject_id,scope_kind,scope_id,observed_at,condition_state,disposition,observed_by_user_id,source_kind,source_key,note,inferred_from_clock,metadata)
          values('{obs}','household','household_kernel_instance','{I}','household','{H}',{t1},'{after}','{after_disposition}','{U}','household_laundry_actual_state','{source}:observation','Synthetic historical seed.',false,jsonb_build_object('careResultId','{result}','cloneFixture',true))""",
          f"""insert into atlas.work_execution_results(id,household_id,work_item_id,reported_by_user_id,result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at)
          values('{execution}','{H}','{work}','{U}','completed','{contract}','{source}:result',jsonb_build_object('careResultId','{result}','careObservationId','{obs}','step','{step}','isWholeLaundryDone',false),jsonb_build_object('needOccurrenceId','{need}','cloneFixture',true),{t1})""",
          f"""insert into atlas.work_result_acceptances(id,household_id,work_item_id,execution_result_id,decision,acceptance_kind,accepted_by_domain,evidence)
          values('{acceptance}','{H}','{work}','{execution}','accepted','source_qualified_physical_actual','household_laundry_actual',jsonb_build_object('careResultId','{result}','step','{step}','cloneFixture',true))""",
          f"update atlas.work_items set work_state='completed',completed_at={t1},updated_at={t1} where household_id='{H}' and id='{work}'",
          f"update atlas.household_need_occurrences_v1 set state='satisfied',satisfied_at={t1},satisfied_by_care_result_id='{result}',updated_at={t1} where household_id='{H}' and id='{need}'",
        ]
    return ";\n".join(statements+["commit"])+";"

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    base.check(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),"Only disposable localhost")
    api,key=c1.local_status()
    def sql(stmt): return base.sql(args.db_url,stmt)
    base.check(sql(f"select count(*) from atlas.household_kernel_instances where id='{I}' and household_id='{H}' and metadata->>'cloneFixture'='true'")=="1","Exact fictional instance")
    for table,col in (("work_items","household_id"),("household_need_occurrences_v1","household_id"),("care_observation_events","scope_id"),("care_result_events","scope_id"),("household_need_renewal_decisions_v1","household_id")):
        base.check(sql(f"select count(*) from atlas.{table} where {col}='{H}'")=="0","Fresh fixture only; never rewrite prior observations")
    tokens={}; claims={}
    for name,uid in base.setup_auth(args.db_url):
        token,payload=c1.sign_in(api,key,name)
        sid=str(UUID(payload["session_id"]))
        base.check(payload["sub"]==uid and sql(f"select count(*) from auth.sessions where id='{sid}' and user_id='{uid}'")=="1","Independently verified local session")
        tokens[name]=token;claims[name]=payload
    def ok(name,body=None): return base.allow(api,key,tokens["owner"],name,body or {})
    def deny(actor,name,body): base.deny(api,key,tokens.get(actor),name,body,"due-renewal actor boundary")
    def owner_rpc(name,body): return base.rpc(api,key,tokens["owner"],name,body)
    base.check(sql(f"select count(*) from atlas.household_rhythms where household_id='{H}' and stable_key='kernel:household.laundry:general'")=="0","Obsolete row actually absent before signed proof")
    base.check(sql("select count(*) from atlas.household_rhythms where id='e5200000-0000-4000-8000-000000000ea2'")=="1","Independent rhythm remains")
    base.check(ok("household_laundry_current_self_api_v1")["instanceId"]==I,"Actual signed fixture owner")
    sql(historical_fixture(claims["owner"]))
    cur=ok("household_laundry_current_self_api_v1")
    base.check(cur["currentCondition"]=="returned_to_use" and cur["workItemId"] is None and cur["needOccurrenceId"] is None,"Source recognizes independent historical load fixture")
    base.check(sql(f"select count(*) from atlas.household_need_occurrences_v1 where household_id='{H}' and state='satisfied'")=="3","Full synthetic closed-load chain, no rewritten rows")
    calibration=ok("calibrate_personal_laundry_kernel_self_api_v1",{"p_input":{"laundryLocation":"home","usualPattern":"little_most_days","expectedMinutes":45}})
    base.check(calibration["instance"]["id"]==I,"Same original instance")
    proposal=ok("household_laundry_renewal_attention_self_api_v1")
    base.check(proposal["state"]=="proposal" and proposal["decisionId"] is None,"Old load does not invent consent")
    accepted=ok("household_need_renewal_decide_self_api_v1",{
      "p_kernel_instance_id":I,"p_action_id":ident("0e01"),"p_decision_kind":"establish",
      "p_renew_after_days":1,"p_decision_reason":"Fictional owner accepts the proposed daily condition check."})
    base.check(accepted["currentlyEstablished"] is True and accepted["workCreated"] is False and accepted["needCreated"] is False and accepted["clockAdmitted"] is False,"Genuine signed interval acceptance")
    result=due.check_due_renewal(ok=ok,deny=deny,owner_rpc=owner_rpc,sql=sql,check=base.check,household=H,instance=I)
    sid=str(UUID(claims["owner"]["session_id"]))
    sql(f"delete from auth.sessions where id='{sid}' and user_id='{U}'")
    deny("owner","household_laundry_renewal_attention_self_api_v1",{})
    base.check(sql(f"select count(*) from atlas.household_rhythms where household_id='{H}' and stable_key='kernel:household.laundry:general'")=="0","Full signed behavior never re-creates legacy record")
    base.check(sql(f"select count(*) from atlas.rhythm_satisfactions where household_id='{H}'")=="0","No legacy satisfaction writes")
    Path(args.output).write_text(result+" Historical input rows were fictional setup, not previously signed HTTP history. Genuine signed due read, response, replay and revocation tested.\n")
if __name__=="__main__": main()

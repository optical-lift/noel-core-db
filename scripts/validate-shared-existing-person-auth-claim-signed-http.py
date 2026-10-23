#!/usr/bin/env python3
"""Genuine LOCAL GoTrue+PostgREST claim test; never touches production users."""
import argparse,importlib.util,re,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("work_test",HERE/"validate-atlas-work-prerequisite-signed-http.py")
w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
c1=w.c1
ORG=c1.ORG
PERSON="e5200000-0000-4000-8000-000000000105"
DECLINE="e5200000-0000-4000-8000-000000000106"
OLD="e5200000-0000-4000-8000-000000000005"
API={
 "prepare":"prepare_existing_person_auth_claim_self_api_v1",
 "accept":"accept_existing_person_auth_claim_self_api_v1",
 "approve":"approve_existing_person_auth_claim_self_api_v1",
 "finish":"finish_existing_person_auth_claim_self_api_v1",
 "inspect":"inspect_existing_person_auth_claim_self_api_v1",
 "reject":"reject_existing_person_auth_claim_self_api_v1",
 "list":"list_existing_person_auth_claims_self_api_v1",
}
def check(ok,why):c1.check(ok,why)
def sql(db,q):return c1.sql(db,q)
def call(api,key,token,action,data):return w.rpc(api,key,token,API[action],data)
def yes(api,key,token,action,data):
 status,out=call(api,key,token,action,data)
 check(status==200 and isinstance(out,dict) and out.get("ok") is True,
       f"{action} failed: {status} {str(out)[:180]}")
 return out
def no(api,key,token,action,data,why):
 status,out=call(api,key,token,action,data)
 check(status in (401,403) and isinstance(out,dict),
       f"{why}: expected 401/403, observed {status} {str(out)[:180]}")
 if token:check(out.get("code")=="42501",f"{why}: unexpected error: {str(out)[:180]}")
 print("PASS",why)
def prepare(person,email):return dict(
 p_organization_id=ORG,p_person_id=person,p_email=email,
 p_basis="Known existing human independently witnessed through an original native Ledger relationship.")
def count(db,t):return sql(db,"select count(*) from "+t)
def main():
 p=argparse.ArgumentParser();p.add_argument("--db-url",required=True);p.add_argument("--output",required=True)
 a=p.parse_args()
 check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
       "Refuse nonlocal DB")
 api,key=c1.local_status()
 users=w.setup_auth(a.db_url)
 signed={}
 for name,uid in users:
  token,claims=c1.sign_in(api,key,name)
  check(claims.get("sub")==uid and claims.get("session_id"),"Genuine signed session missing")
  check(sql(a.db_url,f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
        "Signed session not registered")
  signed[name]=(token,claims)
 owner=signed["owner"][0];recipient=signed["worker"][0];wrong=signed["outsider"][0]
 check(sql(a.db_url,f"select count(*) from reality.auth_person_bindings where auth_user_id='{c1.WORKER}'::uuid")=="0",
       "New Auth claimant already has Person")
 check(sql(a.db_url,f"select count(*) from atlas.person_auth_credentials where person_id='{PERSON}'::uuid and auth_user_id='{OLD}'::uuid and status='retired'")=="1",
       "Retired historical Auth credential missing")
 baseline={t:count(a.db_url,t) for t in (
 "reality.entities","atlas.people","ledger.seats","atlas.principals",
 "atlas.organization_memberships","atlas.work_items")}
 check(yes(api,key,owner,"list",{"p_organization_id":ORG}).get("cases")==[],
       "Empty authorized queue must be empty")
 no(api,key,wrong,"list",{"p_organization_id":ORG},"Wrong steward cannot enumerate")
 no(api,key,recipient,"prepare",prepare(PERSON,"atlas-c1-worker@example.invalid"),"Recipient not identity steward")
 original=prepare(PERSON,"atlas-c1-worker@example.invalid")
 case=yes(api,key,owner,"prepare",original)
 case_id=case.get("caseId")
 check(case_id and case.get("caseState")=="prepared","Case not prepared")
 replay=yes(api,key,owner,"prepare",original)
 check(replay.get("caseId")==case_id and replay.get("idempotentReplay") is True,"Preparation not idempotent")
 args={"p_case_id":case_id,"p_explicit_acceptance":True}
 no(api,key,owner,"accept",args,"Operator cannot accept")
 no(api,key,wrong,"accept",args,"Wrong email cannot accept")
 no(api,key,None,"accept",args,"Anonymous cannot accept")
 view=yes(api,key,recipient,"inspect",{"p_case_id":case_id})
 check(view.get("intendedPersonName")=="Claim Validation Human","Wrong recipient-safe Person")
 no(api,key,wrong,"inspect",{"p_case_id":case_id},"Wrong email cannot inspect")
 rejected=yes(api,key,owner,"prepare",prepare(DECLINE,"atlas-c1-outsider@example.invalid"))
 yes(api,key,wrong,"reject",{"p_case_id":rejected["caseId"],"p_reason":"This is not my real identity."})
 check(sql(a.db_url,f"select count(*) from reality.auth_person_bindings where person_entity_id='{DECLINE}'::uuid")=="0",
       "Rejecting person unexpectedly bound")
 print("PASS identity preparation, wrong mailbox, rejection, source role checks")
 yes(api,key,recipient,"accept",args)
 review={"p_case_id":case_id,"p_method":"verified_video_call",
         "p_basis":"I recognized the real human on a separately established video call, not by email."}
 no(api,key,recipient,"approve",review,"Claimant cannot approve")
 approve=yes(api,key,owner,"approve",review)
 check(approve.get("state")=="approved","Independent review missing")
 result=yes(api,key,recipient,"finish",{"p_case_id":case_id})
 check(result.get("personId")==PERSON and result.get("state")=="completed","Wrong canonical binding")
 check(yes(api,key,recipient,"finish",{"p_case_id":case_id}).get("idempotentReplay") is True,
       "Finish retry created duplicate")
 for table,field in (("reality.auth_person_bindings","person_entity_id"),
                     ("atlas.person_auth_credentials","person_id")):
  check(sql(a.db_url,f"select count(*) from {table} where {field}='{PERSON}'::uuid and auth_user_id='{c1.WORKER}'::uuid and "+("binding_state" if table.startswith("reality.") else "status")+"='active'")=="1",
        "Active new Auth not the original Person")
 check(sql(a.db_url,f"select count(*) from atlas.person_sign_in_emails where person_id='{PERSON}'::uuid and auth_user_id='{c1.WORKER}'::uuid and verification_state='verified' and preferred")=="1",
       "Primary verified email binding absent")
 check(sql(a.db_url,f"select count(*) from atlas.person_auth_credentials where person_id='{PERSON}'::uuid and auth_user_id='{OLD}'::uuid and status='retired'")=="1",
       "Old credential history damaged")
 for table,n in baseline.items():check(count(a.db_url,table)==n,"Identity transition mutated "+table)
 print("PASS canonical original Person, Ledger/work continuity, no inferred role/seat")
 # Competing database writer must fail unique active-Person restriction, not
 # merely the existing one-Auth-user restriction.
 attempt=subprocess.run(["psql",a.db_url,"-X","-v","ON_ERROR_STOP=1","-c",
   "insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values ("+
   "'"+OLD+"'::uuid,'"+PERSON+"'::uuid,'active','{}'::jsonb)"],
   capture_output=True,text=True)
 check(attempt.returncode!=0 and "reality_auth_one_active_person_shared_v1" in attempt.stderr,
       "Concurrent/competing active-Person Auth index did not reject second writer")
 print("PASS canonical active Auth Person uniqueness enforced independently")
 fresh,claims=c1.sign_in(api,key,"worker")
 check(claims.get("session_id")!=signed["worker"][1]["session_id"],"No distinct later signed session")
 check(yes(api,key,fresh,"inspect",{"p_case_id":case_id}).get("caseState")=="completed",
       "Re-sign-in did not resolve original Person")
 sql(a.db_url,f"delete from auth.sessions where id='{claims['session_id']}'::uuid")
 no(api,key,fresh,"inspect",{"p_case_id":case_id},"Revoked signed session denied")
 Path(a.output).parent.mkdir(parents=True,exist_ok=True)
 Path(a.output).write_text("PASS genuine signed users; native canonical Person; recipient approval/denial; historical custody; unique binding; revoked session.\n",encoding="utf-8")
 print("PASS genuine LOCAL signed Person claim test")
if __name__=="__main__":main()

#!/usr/bin/env python3
"""Real signed LOCAL GoTrue two-human Foundry source-scope review proof.

Run only after Gate 2 Foundry signed preparation proof in disposable
production-schema clone. No real source files, people, or mailboxes.
"""
import argparse
import importlib.util
import re
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("base",HERE/"validate-shared-foundry-workspace-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

OUTSIDER="f1900000-0000-4000-8000-000000000004"
OUTSIDER_P="f1900000-0000-4000-8000-000000000204"
REQUEST="request_foundry_source_custody_review_self_api_v1"
INSPECT="inspect_foundry_source_custody_review_self_api_v1"
DECIDE="decide_foundry_source_custody_review_self_api_v1"
REVOKE="revoke_foundry_source_custody_review_self_api_v1"

def expect(flag,text):c1.check(flag,text)
def local_sql(db,q):return c1.sql(db,q)
def allowed(api,key,token,fn,values,label):
    status,out=c1.rpc(api,key,fn,values,token)
    expect(status==200 and isinstance(out,dict) and out.get("ok") is True,
      f"{label}: expected signed success got {status} {str(out)[:300]}")
    print("PASS",label)
    return out
def denied(api,key,token,fn,values,label):
    status,out=c1.rpc(api,key,fn,values,token)
    expect(status in (401,403) and isinstance(out,dict),
      f"{label}: expected access denial got {status} {str(out)[:300]}")
    if token is not None:
        expect(out.get("code")=="42501",
          f"{label}: expected 42501 permission denial, got {out}")
    print("PASS",label)

def setup_outsider(db):
    email="atlas-c1-foundry-review-outsider@example.invalid"
    local_sql(db,f"""update auth.users set
       instance_id='00000000-0000-0000-0000-000000000000'::uuid,
       email='{email}',
       encrypted_password=extensions.crypt('{c1.PASSWORD}',extensions.gen_salt('bf')),
       email_confirmed_at=now(),confirmation_token='',recovery_token='',
       email_change='',email_change_token_new='',email_change_token_current='',
       phone_change='',phone_change_token='',reauthentication_token='',
       raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
       raw_user_meta_data='{{"is_owner":true,"principal_id":"{base.OWNER_P}"}}'::jsonb
     where id='{OUTSIDER}'::uuid""")
    local_sql(db,f"""insert into auth.identities(
       id,provider_id,user_id,identity_data,provider,created_at,updated_at
      ) values(gen_random_uuid(),'{email}','{OUTSIDER}'::uuid,
        jsonb_build_object('sub','{OUTSIDER}','email','{email}'),'email',now(),now())""")
    local_sql(db,"notify pgrst,'reload schema'")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    expect(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
      "Source-review proof refuses production DB")
    api,key=c1.local_status()
    expect(local_sql(a.db_url,
      f"select count(*) from auth.users where id in ('{base.OWNER}','{base.OTHER}','{base.NO_PRINCIPAL}','{OUTSIDER}')")=="4",
      "Four fictional GoTrue users missing")
    setup_outsider(a.db_url)
    signed={}
    for label,uid in (("foundry-owner",base.OWNER),("foundry-other",base.OTHER),
                      ("foundry-noprincipal",base.NO_PRINCIPAL),
                      ("foundry-review-outsider",OUTSIDER)):
        token,claims=c1.sign_in(api,key,label)
        expect(claims.get("sub")==uid and claims.get("session_id"),
               "Real independently signed GoTrue session required")
        expect(local_sql(a.db_url,
          f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
          "Signed session is not real DB session")
        signed[label]=(token,claims)
    owner=signed["foundry-owner"][0]
    reviewer=signed["foundry-other"][0]
    outsider=signed["foundry-review-outsider"][0]
    unbound=signed["foundry-noprincipal"][0]
    expect(signed["foundry-review-outsider"][1].get("user_metadata",{}).get("is_owner") is True,
           "Deliberately forged editable user metadata fixture absent")

    base_counts={table:int(local_sql(a.db_url,"select count(*) from "+table)) for table in (
       "atlas.people","reality.entities","ledger.seats","atlas.work_items","foundry.snapshots")}
    workspace=allowed(api,key,owner,base.PREP,dict(
       p_request_id="f1900000-0000-4000-8000-000000000320",
       p_subject_label="Fictional external research subject",
       p_provisional_field="Historical source custody, with independent human check",
       p_custody_scope_kind="documented_external"),"review owner prepares pending workspace")["workspaceId"]
    # Only the source-specific connected-People selector candidate exercises
    # this extra assertion. Prior immutable signed custody candidates stay valid.
    if local_sql(a.db_url,
      "select to_regprocedure('public.list_foundry_source_custody_reviewers_self_api_v1(text)') is not null")=="t":
        selected=allowed(api,key,owner,
          "list_foundry_source_custody_reviewers_self_api_v1",
          {"p_workspace_id":workspace},"owner sees connected reviewer people")
        expect(selected["aiCarrierAccess"] is False,"Reviewer list granted AI access")
        reviewer_ids=[item["principalId"] for item in selected.get("reviewers",[])]
        expect(reviewer_ids==[base.OTHER_P],
          f"Connected directory must contain only other active shared Principal: {reviewer_ids}")
        denied(api,key,reviewer,"list_foundry_source_custody_reviewers_self_api_v1",
          {"p_workspace_id":workspace},"unrelated signed person cannot see private owner reviewer list")
        denied(api,key,outsider,"list_foundry_source_custody_reviewers_self_api_v1",
          {"p_workspace_id":workspace},"outsider cannot enumerate eligible reviewers")
        denied(api,key,None,"list_foundry_source_custody_reviewers_self_api_v1",
          {"p_workspace_id":workspace},"anonymous reviewer directory is closed")
    request=dict(
      p_workspace_id=workspace,
      p_request_id="f1900000-0000-4000-8000-000000000321",
      p_reviewer_principal_id=base.OTHER_P,
      p_claim_basis_kind="public_source",
      p_source_refs=["synthetic-doc-source-001","synthetic-doc-source-002"],
      p_permitted_human_actions=["catalog","transcribe"],
      p_scope_description="Two specified fictional historical documents, metadata and faithful transcription only.",
      p_claimed_authority_basis="Owner claims these two synthetic sources are public. This is an unverified claim until independent review.")
    denied(api,key,None,REQUEST,request,"anonymous source custody request")
    denied(api,key,reviewer,REQUEST,request,"reviewer cannot impersonate workspace owner")
    denied(api,key,unbound,REQUEST,request,"no-Principal caller cannot initiate custody case")
    first=allowed(api,key,owner,REQUEST,request,"owner submits exact source scope")
    case=first["caseId"]
    expect(first["reviewState"]=="pending" and first["aiCarrierAccess"] is False,
      "Submitted custody case was incorrectly promoted to approved AI authority")
    again=allowed(api,key,owner,REQUEST,request,"exact request retry is stable")
    expect(again["caseId"]==case and again["replayed"] is True,
      "Request replay did not preserve case identity")
    status,bad=c1.rpc(api,key,REQUEST,{**request,"p_scope_description":"Different source scope on reused request"},owner)
    expect(status>=400 and bad.get("code")=="22023",
      "Reused request ID with changed source scope must be rejected")
    claim=allowed(api,key,reviewer,INSPECT,{"p_case_id":case},"designated reviewer inspects claimed source and scope")
    expect(claim["sourceRefs"]==request["p_source_refs"]
      and claim["humanActions"]==request["p_permitted_human_actions"]
      and claim["claimedAuthorityBasis"]==request["p_claimed_authority_basis"],
      "Exact proposed source/reference/authority evidence did not survive")
    denied(api,key,outsider,INSPECT,{"p_case_id":case},"foreign signed Principal cannot inspect a review")
    denied(api,key,unbound,INSPECT,{"p_case_id":case},"no-Principal caller cannot inspect review")
    denied(api,key,outsider,INSPECT,{"p_case_id":"f1900000-0000-4000-8000-000000000999"},
      "nonexistent and foreign review are equally inaccessible")
    decision=dict(p_case_id=case,p_decision="approve",
      p_review_basis="I independently examined these fictional original-source references and approve only the stated human catalog/transcription scope.")
    denied(api,key,owner,DECIDE,decision,"owner cannot self-approve source custody")
    denied(api,key,outsider,DECIDE,decision,"unassigned Principal cannot approve custody")
    result=allowed(api,key,reviewer,DECIDE,decision,"distinct signed reviewer approves bounded human review")
    expect(result["reviewState"]=="approved" and result["workspaceCustodyState"]=="pending"
      and result["aiCarrierAccess"] is False,"Human review improperly admitted AI authority")
    again=allowed(api,key,owner,INSPECT,{"p_case_id":case},"owner reads separately reviewed case")
    expect(again["reviewState"]=="approved" and again["reviewBasis"]==decision["p_review_basis"],
      "Reviewer source basis not preserved verbatim")
    expect(local_sql(a.db_url,
      f"select custody_review_state from foundry.workspace_authority_registry_v1 where workspace_id='{workspace}'")=="pending",
      "Human review changed delegated agent workspace custody authorization")
    expect(local_sql(a.db_url,
      "select count(*) from atlas.agent_command_definitions where scope_kind='foundry_workspace'")=="0",
      "Human approval silently enabled an AI command")
    revoked=allowed(api,key,owner,REVOKE,dict(p_case_id=case,
      p_reason="Owner revokes this source-scope review before any further handling."),
      "owner revokes prior human source review")
    expect(revoked["reviewState"]=="revoked" and revoked["aiCarrierAccess"] is False,
      "Revocation failed")
    replay=allowed(api,key,owner,REVOKE,dict(p_case_id=case,
      p_reason="Owner revokes this source-scope review before any further handling."),
      "revocation retry is idempotent")
    expect(replay.get("replayed") is True,"Repeated revoke should not append again")
    for table,orig in base_counts.items():
        expect(int(local_sql(a.db_url,"select count(*) from "+table))==orig,
          f"Source case silently modified canonical Atlas or snapshot {table}")
    # Revoking an actual signed session immediately blocks review, not merely JWT expiry.
    local_sql(a.db_url,
      f"delete from auth.sessions where id='{signed['foundry-other'][1]['session_id']}'::uuid")
    denied(api,key,reviewer,INSPECT,{"p_case_id":case},
      "removed GoTrue reviewer session immediately loses access")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text(
      "PASS independent genuinely signed reviewers; source-reference custody; "
      "scope idempotency; cross-Principal denial; AI-state pending; human revocation; "
      "rejected owner self-approval; revoked signed session; no canonical writes\n",
      encoding="utf-8")
    print("PASS real signed Foundry independent human source custody review")

if __name__=="__main__": main()

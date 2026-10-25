#!/usr/bin/env python3
"""Signed LOCAL GoTrue -> PostgREST proof of pre-Ledger Foundry preparation.

This is part of the immutable shared_ candidate's protected local-clone validation.
The only permitted DB endpoint is 127.0.0.1. No outside mailbox or production
subject/testimony is involved.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
mod = importlib.util.spec_from_file_location("local_c1", HERE/"validate-atlas-c1-signed-http.py")
c1 = importlib.util.module_from_spec(mod)
mod.loader.exec_module(c1)

OWNER = "f1900000-0000-4000-8000-000000000001"
OTHER = "f1900000-0000-4000-8000-000000000002"
NO_PRINCIPAL = "f1900000-0000-4000-8000-000000000003"
OWNER_P = "f1900000-0000-4000-8000-000000000201"
OTHER_P = "f1900000-0000-4000-8000-000000000202"
PREP = "prepare_foundry_workspace_self_api_v1"
READ = "get_foundry_workspace_preparation_self_api_v1"

def need(ok, message):
    c1.check(ok, message)

def db(db_url, statement):
    return c1.sql(db_url, statement)

def check_rpc(api, key, token, func, args):
    return c1.rpc(api, key, func, args, token)

def approved(api, key, token, func, args, label):
    status, result = check_rpc(api, key, token, func, args)
    need(status == 200 and isinstance(result, dict) and result.get("ok") is True,
         f"{label}: expected successful signed RPC, got {status}: {str(result)[:350]}")
    return result

def forbidden(api, key, token, func, args, label):
    status, result = check_rpc(api, key, token, func, args)
    need(status in (401,403) and isinstance(result, dict),
         f"{label}: expected 401/403, got {status}: {str(result)[:350]}")
    if token is not None:
        need(result.get("code") == "42501",
             f"{label}: expected permission denial 42501, got: {str(result)[:350]}")
    print("PASS", label)

def setup_auth(db_url):
    for label,uid in (("foundry-owner",OWNER),("foundry-other",OTHER),
                      ("foundry-noprincipal",NO_PRINCIPAL)):
        email=f"atlas-c1-{label}@example.invalid"
        metadata = '{"is_owner":true,"principal_id":"'+OWNER_P+'"}' if label=="foundry-other" else "{}"
        db(db_url, f"""
          update auth.users set
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{email}',
            encrypted_password=extensions.crypt('{c1.PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),
            confirmation_token='',recovery_token='',email_change='',
            email_change_token_new='',email_change_token_current='',
            phone_change='',phone_change_token='',reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{metadata}'::jsonb
          where id='{uid}'::uuid
        """)
        db(db_url, f"""
          insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          values(gen_random_uuid(),'{email}','{uid}'::uuid,
            jsonb_build_object('sub','{uid}','email','{email}'),'email',now(),now())
        """)
    db(db_url, "notify pgrst, 'reload schema'")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    need(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
         "Foundry signed probe refuses remote database URI")
    need(db(a.db_url,
      f"select count(*) from auth.users where id in ('{OWNER}','{OTHER}','{NO_PRINCIPAL}')")=="3",
      "Three fictional users required")
    api,key=c1.local_status()
    setup_auth(a.db_url)
    signed={}
    for label,uid in (("foundry-owner",OWNER),("foundry-other",OTHER),
                      ("foundry-noprincipal",NO_PRINCIPAL)):
        token,claims=c1.sign_in(api,key,label)
        need(claims.get("sub")==uid and bool(claims.get("session_id")),
             "Real local signed JWT identity/session missing")
        need(db(a.db_url,
          f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
             "GoTrue session did not persist")
        signed[label]=(token,claims)
    owner=signed["foundry-owner"][0]
    other=signed["foundry-other"][0]
    unbound=signed["foundry-noprincipal"][0]
    need(signed["foundry-other"][1].get("user_metadata",{}).get("is_owner") is True,
         "Misleading user-editable principal metadata fixture absent")
    baseline={table:int(db(a.db_url, "select count(*) from "+table)) for table in
              ("atlas.people","reality.entities","ledger.seats",
               "atlas.work_items","foundry.snapshots")}
    count_start=int(db(a.db_url,"select count(*) from foundry.events"))
    args=dict(p_request_id="f1900000-0000-4000-8000-000000000301",
              p_subject_label="Fictional external subject",
              p_provisional_field="Fictional program commitments and historical documents",
              p_custody_scope_kind="documented_external")
    forbidden(api,key,None,PREP,args,"anonymous creation")
    forbidden(api,key,unbound,PREP,args,"signed user without Principal")
    first=approved(api,key,owner,PREP,args,"owner creates pending workspace")
    wid=first.get("workspaceId")
    need(bool(wid) and first.get("custodyReviewState")=="pending"
         and first.get("subjectIdentityState")=="unresolved"
         and first.get("replayed") is False,"Creation improperly established subject authority")
    again=approved(api,key,owner,PREP,args,"stable retry")
    need(again.get("workspaceId")==wid and again.get("replayed") is True,
         "Idempotent retry created another workspace")
    changed={**args,"p_subject_label":"Changed subject"}
    status,invalid=check_rpc(api,key,owner,PREP,changed)
    need(status>=400 and isinstance(invalid,dict) and invalid.get("code")=="P0001",
         "Changing payload with same operation ID must be rejected")
    view=approved(api,key,owner,READ,{"p_workspace_id":wid},"owner reads pending workspace")
    need(view.get("workspaceId")==wid and view.get("custodyReviewState")=="pending"
         and view.get("subjectIdentityState")=="unresolved",
         "Read promoted proposed external subject to verified reality")
    forbidden(api,key,None,READ,{"p_workspace_id":wid},"anonymous workspace read")
    forbidden(api,key,other,READ,{"p_workspace_id":wid},
              "separate signed Principal cannot inspect foreign workspace")
    forbidden(api,key,unbound,READ,{"p_workspace_id":wid},
              "signed user without Principal cannot inspect workspace")
    forbidden(api,key,other,READ,{"p_workspace_id":"does-not-exist"},
              "foreign and nonexistent target both denied")
    foreign={**args,"p_request_id":"f1900000-0000-4000-8000-000000000302",
             "p_subject_label":"Fictional second subject"}
    other_result=approved(api,key,other,PREP,foreign,"other Principal creates own pending workspace")
    other_wid=other_result["workspaceId"]
    need(other_wid!=wid,"Principals must create independent workspace IDs")
    forbidden(api,key,owner,READ,{"p_workspace_id":other_wid},
              "first Principal cannot inspect other's workspace")
    need(approved(api,key,other,READ,{"p_workspace_id":other_wid},
                  "other Principal own read").get("workspaceId")==other_wid,
         "Other Principal own read mismatch")
    if db(a.db_url,
      "select to_regprocedure('public.list_foundry_owned_workspaces_self_api_v1()') is not null")=="t":
        owner_index=approved(api,key,owner,"list_foundry_owned_workspaces_self_api_v1",
          {},"signed owner reads only own Foundry Index")
        other_index=approved(api,key,other,"list_foundry_owned_workspaces_self_api_v1",
          {},"signed second Principal reads only own Foundry Index")
        need(any(item["workspaceId"]==wid for item in owner_index["items"]) and
             all(item["workspaceId"]!=other_wid for item in owner_index["items"]),
             "Foundry owner Index contains foreign workspace or loses owned one")
        need(any(item["workspaceId"]==other_wid for item in other_index["items"]) and
             all(item["workspaceId"]!=wid for item in other_index["items"]),
             "Second Principal Foundry Index contains foreign workspace")
        forbidden(api,key,None,"list_foundry_owned_workspaces_self_api_v1",
               {},"anonymous cannot enumerate a Foundry Index")
        forbidden(api,key,unbound,"list_foundry_owned_workspaces_self_api_v1",
               {},"unbound signed caller cannot read Foundry Index")
    need(db(a.db_url,
      f"select count(*) from foundry.workspace_authority_registry_v1 where workspace_id='{wid}' and owner_principal_id='{OWNER_P}'::uuid and custody_review_state='pending' and cardinality(custody_basis_refs)=0")=="1",
         "Initial source-custody authority must remain absent")
    need(db(a.db_url,
      f"select count(*) from foundry.workspace_authority_registry_v1 where workspace_id='{other_wid}' and owner_principal_id='{OTHER_P}'::uuid and custody_review_state='pending'")=="1",
         "Other owner custody binding mismatch")
    need(int(db(a.db_url,"select count(*) from foundry.events"))==count_start+2,
         "Prepared workspace must append exactly one event per distinct request")
    for table,n in baseline.items():
        need(int(db(a.db_url,"select count(*) from "+table))==n,
             f"Pre-Ledger preparation unexpectedly mutated {table}")
    # Optional exact-version typed reality evidence proof. Only candidate
    # packages that contain the new API exercise these extra signed checks.
    intake_enabled = db(a.db_url,
      "select to_regprocedure('public.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)') is not null")=="t"
    if intake_enabled:
        writer="capture_foundry_reality_input_self_api_v1"
        reader="list_foundry_reality_inputs_self_api_v1"
        original="The north garden has three beds. Thursday events recur. Set the mower blade to 3 inches."
        segments=[
          {"text":"The north garden has three beds.","kind":"place"},
          {"text":"Thursday events recur.","kind":"recurrence"},
          {"text":"Set the mower blade to 3 inches.","kind":"operating_instruction"}
        ]
        capture=dict(p_workspace_id=wid,p_request_id="f1900000-0000-4000-8000-000000000311",
            p_original_text=original,p_segments=segments,p_source_kind="operator_statement",
            p_observed_at=None)
        forbidden(api,key,None,writer,capture,"anonymous cannot record new evidence")
        forbidden(api,key,other,writer,capture,"other Principal cannot write owner's evidence")
        forbidden(api,key,unbound,writer,capture,"no-Principal signed caller cannot append")
        first_evidence=approved(api,key,owner,writer,capture,"owner captures typed original")
        need(first_evidence.get("canonicalMutation") is False and
             first_evidence.get("aiCarrierAccess") is False and
             first_evidence.get("replayed") is False,
             "Evidence capture improperly promoted source or granted AI access")
        retry=approved(api,key,owner,writer,capture,"idempotent evidence retry")
        need(retry.get("replayed") is True and
             retry.get("entryId")==first_evidence.get("entryId"),
             "Duplicate source evidence produced on retry")
        status,invalid=check_rpc(api,key,owner,writer,{**capture,
          "p_original_text":"Changed without changing request ID"})
        need(status>=400,"Reused request ID with different original must fail")
        status,invalid=check_rpc(api,key,owner,writer,{**capture,
          "p_request_id":"f1900000-0000-4000-8000-000000000312",
          "p_segments":[{"text":"Fabricated segment","kind":"place"}]})
        need(status>=400,"Evidence segment not in original must be rejected")
        status,invalid=check_rpc(api,key,owner,writer,{**capture,
          "p_request_id":"f1900000-0000-4000-8000-000000000313",
          "p_segments":[{"text":"Thursday events recur.","kind":"canonical_price"}]})
        need(status>=400,"Unapproved semantic class must be rejected")
        owned=approved(api,key,owner,reader,{"p_workspace_id":wid},
                       "owner reads original evidence")
        need(owned.get("aiCarrierAccess") is False and owned.get("canonicalMutation") is False,
             "Readback incorrectly claims canonical or AI grant")
        rows=[row for row in owned.get("items",[])
              if row.get("entryId")==first_evidence["entryId"]]
        need(len(rows)==1 and rows[0].get("originalText")==original and
             rows[0].get("segments")==segments and
             rows[0].get("segmentStatus")=="unresolved" and
             rows[0].get("authorPrincipalId")==OWNER_P,
             "Original typed evidence or signed author did not round-trip")
        need(db(a.db_url,f"select count(*) from foundry.events where workspace_id='{wid}' and event_type='foundry_reality_input_v1'")=="1",
             "Repeated evidence request duplicated append-only event")
        forbidden(api,key,None,reader,{"p_workspace_id":wid},
                  "anonymous cannot inspect source evidence")
        forbidden(api,key,other,reader,{"p_workspace_id":wid},
                  "foreign human cannot inspect source evidence")
        forbidden(api,key,unbound,reader,{"p_workspace_id":wid},
                  "unbound signed caller cannot inspect source evidence")
        independent=approved(api,key,other,writer,
            {**capture,"p_workspace_id":other_wid,
             "p_request_id":"f1900000-0000-4000-8000-000000000314"},
            "second human appends only to own workspace")
        need(independent.get("entryId")!=first_evidence.get("entryId"),
             "Distinct signed sources share evidence ID")
        forbidden(api,key,owner,reader,{"p_workspace_id":other_wid},
                  "owner cannot inspect second person's source")
        for table,n in baseline.items():
            need(int(db(a.db_url,"select count(*) from "+table))==n,
                 f"Source intake must not establish canonical {table}")
    bridge_enabled = db(a.db_url,
      "select to_regprocedure('public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)') is not null")=="t"
    if bridge_enabled:
        need(intake_enabled,"Recurrence bridge requires owner-scoped evidence")
        bridge="establish_foundry_weekly_recurrence_self_api_v1"
        ledger_id="f1900000-0000-4000-8000-000000000490"
        call=dict(p_workspace_id=wid,p_entry_id=first_evidence["entryId"],
          p_segment_index=1,p_ledger_id=ledger_id,
          p_title="Fictional Thursday recurring gathering",
          p_weekday=4,p_timezone_name="America/Chicago",
          p_effective_start_date="2026-10-29",
          p_all_day=True,p_local_start_time=None,p_local_end_time=None)
        forbidden(api,key,None,bridge,call,"anonymous cannot establish source")
        forbidden(api,key,other,bridge,call,"other signed principal cannot establish owner's source")
        forbidden(api,key,unbound,bridge,call,"unbound caller cannot establish source")
        status,missing=check_rpc(api,key,owner,bridge,
            {**call,"p_entry_id":"foundry-reality-intake-does-not-exist"})
        need(status in (401,403),"Missing evidence must be denied")
        status,not_recurrence=check_rpc(api,key,owner,bridge,
            {**call,"p_segment_index":2})
        need(status>=400,"An operating instruction cannot be a recurrence")
        status,bad_zone=check_rpc(api,key,owner,bridge,
            {**call,"p_timezone_name":"Made/Up"})
        need(status>=400,"Made-up time zone must be rejected")
        status,bad_time=check_rpc(api,key,owner,bridge,
            {**call,"p_all_day":False})
        need(status>=400,"Unknown time cannot be made into a timed event")
        forbidden(api,key,other,bridge,
                  {**call,"p_workspace_id":other_wid,
                   "p_entry_id":independent["entryId"]},
                  "connected person with no schedule responsibility cannot establish")
        original_count=int(db(a.db_url,"select count(*) from ledger.recurrence_series"))
        created=approved(api,key,owner,bridge,call,
                         "authorized human establishes sourced weekly event")
        need(created.get("replayed") is False
             and created.get("canonicalConsequenceKind")=="ledger_recurrence_series"
             and created.get("weekdays")==[4]
             and created.get("sourceEntryId")==first_evidence["entryId"]
             and created.get("aiCarrierAccess") is False,
             "Sourced recurrence receipt wrong")
        need(int(db(a.db_url,"select count(*) from ledger.recurrence_series"))==original_count+1,
             "Actual recurrence was not established once")
        series_id=created["seriesId"]
        need(db(a.db_url,
              f"select count(*) from ledger.recurrence_series where id='{series_id}'::uuid "
              "and frequency='weekly' and occurrence_type='event' "
              "and weekdays=array[4]::smallint[] and all_day=true "
              "and local_start_time is null and local_end_time is null "
              "and metadata->'foundrySource'->>'literal'='Thursday events recur.'")=="1",
             "Existing canonical domain record did not preserve exact source")
        retry=approved(api,key,owner,bridge,call,"repeat source establishment")
        need(retry.get("replayed") is True and retry.get("seriesId")==series_id,
             "Retry updated or duplicated canonical recurrence")
        need(int(db(a.db_url,"select count(*) from ledger.recurrence_series"))==original_count+1,
             "Retry created duplicate recurrence")
        status,changed=check_rpc(api,key,owner,bridge,{**call,
              "p_title":"Different scheduling instruction"})
        need(status>=400,"Source retry must not overwrite original calendar rule")
        need(int(db(a.db_url,"select count(*) from atlas.work_items"))==baseline["atlas.work_items"],
             "Source-based schedule cannot invent Work tasks")
    # Deleting an actual local GoTrue session must immediately revoke access.
    db(a.db_url,
      f"delete from auth.sessions where id='{signed['foundry-owner'][1]['session_id']}'::uuid")
    forbidden(api,key,owner,READ,{"p_workspace_id":wid},
              "deleted GoTrue session cannot read despite unexpired JWT")
    forbidden(api,key,owner,PREP,{**args,"p_request_id":"f1900000-0000-4000-8000-000000000303"},
              "deleted GoTrue session cannot create")
    if intake_enabled:
        forbidden(api,key,owner,reader,{"p_workspace_id":wid},
                  "revoked GoTrue session cannot read original evidence")
        forbidden(api,key,owner,writer,{**capture,
          "p_request_id":"f1900000-0000-4000-8000-000000000315"},
                  "revoked GoTrue session cannot append original evidence")
    if bridge_enabled:
        forbidden(api,key,owner,bridge,call,
                  "revoked GoTrue session cannot re-establish or inspect source")
    # Only a schema containing the additional independent-human custody API
    # activates the extra signed proof. The original Gate 2 probe is unchanged
    # for earlier immutable candidates that do not have these functions.
    if db(a.db_url,
      "select to_regprocedure('public.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)') is not null")=="t":
        import subprocess,sys
        subprocess.run([
          sys.executable,str(Path(__file__).resolve().parent/
                             "validate-shared-foundry-custody-signed-http.py"),
          "--db-url",a.db_url,
          "--output",str(Path(a.output).with_name("signed-foundry-human-custody-summary.txt"))
        ],check=True)

    path=Path(a.output)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(
      "PASS signed GoTrue owner/outsider/unbound, opaque workspace scope, "
      "unverified external subject, idempotence, original-event custody, "
      "cross-Principal denial, revoked real session, no canonical Atlas mutations\n",
      encoding="utf-8")
    print("PASS signed local Foundry pre-Ledger workspace isolation and session revocation")

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""Only disposable local GoTrue signed proof: one Event identity is not a Ledger-wide permission."""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
def import_module(path,alias):
    spec=importlib.util.spec_from_file_location(alias,HERE/path)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
ev=import_module("validate-atlas-one-event-schedule-writer-signed-http.py","signed_event_base")
base=import_module("validate-atlas-work-prerequisite-signed-http.py","signed_worker_base")
c1=base.c1
LEDGER=ev.LEDGER
ORG=ev.ORG
EVENT_A=ev.CANONICAL_A
EVENT_B=ev.CANONICAL_B
PERSON=ev.MEMBER_PERSON
WORK="e5200000-0000-4000-8000-000000000901"
WORK_LEDGER="e5200000-0000-4000-8000-000000000401"
WORK_ORG="e5200000-0000-4000-8000-000000000801"
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"

def check(x,msg):
    if not x: raise AssertionError(msg)

def rpc(api,key,token,name,params):
    return ev.request(api,key,"/rest/v1/rpc/"+name,params,token)

def ok(api,key,token,name,params):
    status,packet=rpc(api,key,token,name,params)
    check(status==200 and isinstance(packet,dict) and packet.get("ok") is True,
          f"{name} was not a signed success: {status} {str(packet)[:250]}")
    return packet

def deny(api,key,token,name,params,case):
    status,packet=rpc(api,key,token,name,params)
    check(status in (401,403) and isinstance(packet,dict) and
          (token is None or packet.get("code")=="42501"),
          f"{case}: real source denial required, not 404/missing RPC: {status} {str(packet)[:250]}")
    print("PASS",case)

def events(api,key,bearer):
    p=ok(api,key,bearer,"ledger_occurrence_shared_index_self_api_v1",
         {"p_ledger_id":LEDGER})
    return p

def evidence(api,key,bearer):
    return rpc(api,key,bearer,"ledger_occurrence_date_evidence_self_api_v1",
       {"p_ledger_id":LEDGER,"p_start_date":"2030-10-29",
        "p_end_date":"2030-11-03","p_timezone_name":"America/Chicago","p_limit":150})

def changed(api,key,bearer,kind,action):
    return ok(api,key,bearer,"governor_set_subject_disclosure_self_api_v1",dict(
        p_organization_id=ORG,p_ledger_id=LEDGER,p_target_person_id=PERSON,
        p_subject_domain="event",p_subject_kind="occurrence",
        p_subject_id=EVENT_A,p_disclosure_class="identity",
        p_decision_kind=kind,p_source_action_id=action,
        p_reason="One exact synthetic Event identity to one native Ledger Person."))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",args.db_url)),
          "Signed probe refuses a nonlocal database URL")
    api,key=ev.local_endpoint()
    # Existing original Work and Event fixtures are synthetic and wholly local.
    check(ev.sql(args.db_url,
      f"select count(*) from local_intel.occurrences where id in ('{EVENT_A}','{EVENT_B}')")=="2",
      "Two separate fictional Events missing")
    for uid,suffix in ((ev.MEMBER,"member"),(ev.OUTSIDER,"outsider"),(ev.ROOT,"root")):
        address=f"atlas-write-{suffix}@example.invalid"
        ev.sql(args.db_url,f"""
          UPDATE auth.users SET
            instance_id='00000000-0000-0000-0000-000000000000'::uuid,
            email='{address}',
            encrypted_password=extensions.crypt('{ev.PASSWORD}',extensions.gen_salt('bf')),
            email_confirmed_at=now(),confirmation_token='',recovery_token='',
            email_change='',email_change_token_new='',
            email_change_token_current='',phone_change='',phone_change_token='',
            reauthentication_token='',
            raw_app_meta_data='{{"provider":"email","providers":["email"]}}'::jsonb,
            raw_user_meta_data='{{"is_owner":true,"role":"root_governing"}}'::jsonb
          WHERE id='{uid}'::uuid
        """)
        ev.sql(args.db_url,f"""INSERT INTO auth.identities
          (id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES(gen_random_uuid(),'{address}','{uid}'::uuid,
                 jsonb_build_object('sub','{uid}','email','{address}'),
                 'email',now(),now())""")
    ev.sql(args.db_url,"notify pgrst, 'reload schema'")
    sessions={}
    for suffix,uid in (("member",ev.MEMBER),("outsider",ev.OUTSIDER),("root",ev.ROOT)):
        token,claims=ev.signed_session(api,key,f"atlas-write-{suffix}@example.invalid")
        check(claims.get("sub")==uid and bool(claims.get("session_id")),
              "No verified independent signed "+suffix)
        check(ev.sql(args.db_url,"select count(*) from auth.sessions where "+
             f"id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
             "Local signed "+suffix+" session not stored")
        sessions[suffix]=token
    member=sessions["member"]; outsider=sessions["outsider"]; root=sessions["root"]
    check(not events(api,key,member)["events"],"Ledger membership leaked private Event index")
    check(events(api,key,member)["unresolvedOrganizationBindings"]==0,
          "Hidden Event binding count leaked")
    check({x["id"] for x in events(api,key,root)["events"]}>={EVENT_A,EVENT_B},
          "Original governor lost planned Event oversight")
    status,detail=evidence(api,key,member)
    check(status==200 and detail.get("occurrences")==[] and
          detail.get("coverage",{}).get("eligibleOccurrenceCount")==0,
          f"Date evidence leaked private planned Events: {status} {str(detail)[:240]}")
    deny(api,key,member,"ledger_occurrence_shared_work_self_api_v1",
         dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A),
         "Connected Person cannot enumerate hidden Event details")
    deny(api,key,member,"ledger_occurrence_work_extension_self_api_v1",
         dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A),
         "Connected Person cannot enumerate hidden Event work/history")
    deny(api,key,outsider,"ledger_occurrence_shared_index_self_api_v1",
         {"p_ledger_id":LEDGER},"Outsider cannot read the governed Ledger index")
    deny(api,key,member,"governor_set_subject_disclosure_self_api_v1",dict(
         p_organization_id=ORG,p_ledger_id=LEDGER,p_target_person_id=PERSON,
         p_subject_domain="event",p_subject_kind="occurrence",p_subject_id=EVENT_A,
         p_disclosure_class="identity",p_decision_kind="grant",
         p_source_action_id="f5210000-0000-4000-8000-000000000701",
         p_reason="Forged ordinary connected Person identity grant must fail."),
         "Non-governor cannot disclose their own private Event")
    assert changed(api,key,root,"grant","f5210000-0000-4000-8000-000000000702").get("currentlyGranted") is True
    admitted=events(api,key,member)
    check([x["id"] for x in admitted["events"]]==[EVENT_A],
          "Identity grant leaked adjacent Event or failed its own exact grant")
    status,date=evidence(api,key,member)
    check(status==200 and {x["sourceRef"]["id"] for x in date["occurrences"]}=={EVENT_A},
          "Exact Event date reader failed individual grant or leaked other occurrence")
    governing=ok(api,key,root,"ledger_occurrence_shared_work_self_api_v1",
                 dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A))
    check(len(governing["work"])==1 and
          governing["work"][0]["title"]=="Hidden synthetic vendor payment review",
          "Synthetic governor private Work fixture not independently readable")
    root_history=ok(api,key,root,"ledger_occurrence_work_extension_self_api_v1",
                    dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A))
    check(len(root_history["work"])==1 and len(root_history["history"])>=1,
          "Governor did not preserve original private Work and history")
    disclosed=ok(api,key,member,"ledger_occurrence_shared_work_self_api_v1",
                 dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A))
    check(disclosed["work"]==[] and not disclosed["permissions"]["ordinaryWorkCreate"],
          "Identity grant permitted unrelated task discovery or task creation")
    ext=ok(api,key,member,"ledger_occurrence_work_extension_self_api_v1",
           dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A))
    check(ext["work"]==[] and ext["history"]==[],
          "Identity grant exposed undisclosed Work or history")
    deny(api,key,member,"ledger_occurrence_schedule_correction_preflight_self_api_v1",
         dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_occurrence_id=EVENT_A),
         "An identity grant is not source schedule/resource authority")
    assert changed(api,key,root,"withhold","f5210000-0000-4000-8000-000000000703").get("currentlyGranted") is False
    check(not events(api,key,member)["events"],"Revoked Event title still visible")
    print("PASS signed Event withheld → exact grant → hidden again, including alternate readers")

    # Separate legitimate original Company Work fixture: real Person allocation,
    # native Ledger connection and Work relevance. No fake browser grant.
    base.setup_auth(args.db_url)
    worker,c=base.c1.sign_in(api,key,"worker")
    check(c.get("sub")==base.c1.WORKER and bool(c.get("session_id")),
          "No genuine independently signed Work recipient")
    check(ev.sql(args.db_url,f"select count(*) from auth.sessions where id='{c['session_id']}'::uuid")=="1",
          "Worker signed session not persisted")
    # Use real signed native Ledger authority, not a direct allocation insert.
    owner,claims=base.c1.sign_in(api,key,"owner")
    check(claims.get("sub")==base.c1.OWNER and bool(claims.get("session_id")),
          "No genuine independently signed Work governor")
    check(ev.sql(args.db_url,f"select count(*) from auth.sessions where "
          f"id='{claims['session_id']}'::uuid and user_id='{base.c1.OWNER}'::uuid")=="1",
          "Original Work governor signed session not persisted")
    check(ev.sql(args.db_url,f"select count(*) from atlas.work_items where "
          f"id='{WORK}'::uuid and source_object_type is null "
          "and result_contract_key is null")=="1",
          "Original fixture has an unexpected source contract")
    original_count=ev.sql(args.db_url,"select count(*) from atlas.work_items")
    ev.sql(args.db_url,f"update atlas.work_items set source_object_type='legacy_task' "
          f"where id='{WORK}'::uuid and source_object_type is null")
    scope=ok(api,key,owner,"propose_native_ledger_exact_work_scope_owner_self_api_v1",
             dict(p_organization_id=WORK_ORG,p_ledger_id=WORK_LEDGER,
                  p_worker_person_id=WORKER_PERSON,p_work_item_id=WORK,
                  p_terms="Synthetic one-work agreement for signed authority validation.",
                  p_valid_until=None))
    check(scope.get("coverageMode")=="exact_work" and
          scope.get("coveredWorkItemId")==WORK and
          scope.get("workerConsentRecorded") is False and scope.get("scopeId"),
          "Exact scope not source-bounded")
    sid=scope["scopeId"]
    pending=ok(api,key,worker,"native_ledger_standing_scopes_self_api_v1",{})
    check(any(s.get("scopeId")==sid and s.get("state")=="proposed"
              and s.get("coveredWorkItemId")==WORK
              for s in pending.get("incoming",[])),
          "Worker cannot see the exact proposed scope")
    acceptance=ok(api,key,worker,"respond_native_ledger_standing_scope_self_api_v1",
                  dict(p_scope_id=sid,p_decision="accept"))
    check(acceptance.get("state")=="active" and
          acceptance.get("assignmentCreated") is False,
          "Scope acceptance incorrectly created a Work allocation")
    assigned=ok(api,key,owner,
                "assign_native_ledger_company_work_under_scope_owner_self_api_v1",
                dict(p_work_item_id=WORK,p_scope_id=sid,
                     p_reason="Assign existing synthetic Company Work without a day."))
    allocation=assigned.get("allocationId")
    check(assigned.get("workItemId")==WORK and
          assigned.get("responsiblePersonId")==WORKER_PERSON and
          assigned.get("coveredWorkItemId")==WORK and
          assigned.get("newWorkCreated") is False and bool(allocation),
          "Signed assignment did not preserve original Work")
    check(ev.sql(args.db_url,"select count(*) from atlas.work_items")==original_count,
          "Signed assignment created duplicate original Work")
    check(ev.sql(args.db_url,f"select count(*) from atlas.work_execution_plans "
          f"where work_item_id='{WORK}'::uuid")=="0",
          "Signed assignment silently created a schedule")
    mine=ok(api,key,worker,"connected_person_my_work_self_api_v1",
            {"p_limit":50,"p_after_allocation_id":None})
    current=[x for x in mine.get("items",[]) if x.get("workItemId")==WORK]
    check(len(current)==1 and current[0].get("allocationId")==allocation and
          current[0].get("scheduleState")=="unscheduled" and
          current[0].get("planId") is None,
          "Signed worker My Work did not show one original unscheduled allocation")
    before=ev.sql(args.db_url,f"select count(*) from atlas.work_execution_plans where work_item_id='{WORK}'::uuid")
    deny(api,key,worker,"connected_person_place_work_self_api_v1",
         dict(p_work_item_id=WORK,p_service_date="2030-10-31",
              p_reason="Worker chooses a day without independently delegated scheduling authority."),
         "Assigned worker cannot commit Company schedule date")
    deny(api,key,worker,"connected_person_place_work_self_api_v1",
         dict(p_work_item_id=WORK,p_service_date=None,
              p_reason="Worker attempts to withdraw governor-owned scheduled work."),
         "Assigned worker cannot withdraw Company schedule")
    after=ev.sql(args.db_url,f"select count(*) from atlas.work_execution_plans where work_item_id='{WORK}'::uuid")
    check(before==after,"Denied Person schedule request mutated Company plan")
    check(ev.sql(args.db_url,f"select count(*) from atlas.work_allocations where work_item_id='{WORK}'::uuid and state='active'")=="1",
          "Denied date changes destroyed or duplicated genuine Work responsibility")
    print("PASS assigned signed Person cannot place or withdraw original Company Work plan")
    Path(args.output).write_text("PASS signed Event identity, direct reader denial, exact grant/revocation, and worker schedule authority\n")
    print("PASS complete disposable Atlas Today P0 matrix")

if __name__=="__main__": main()

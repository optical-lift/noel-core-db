#!/usr/bin/env python3
"""DISPOSABLE local GoTrue/PostgREST only. Cannot connect to production."""
import argparse,datetime,importlib.util,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("signed_base",
    HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
c1=base.c1
ORG=c1.ORG
ELM=c1.LEDGER_A
ANNA_LEDGER=c1.LEDGER_B
ANNA_ROOT="e5200000-0000-4000-8000-000000000602"
OWNER_PERSON="e5200000-0000-4000-8000-000000000101"
ANNA_PERSON="e5200000-0000-4000-8000-000000000102"
PERSON_CHOICES="connected_ledger_person_choices_self_api_v1"
AGENDA="connected_ledger_person_agenda_self_api_v1"
DIRECT="connected_ledger_direct_assign_self_api_v1"
SEND="connected_ledger_send_dated_self_api_v1"
SUBMIT="submit_ledger_work_self_api_v1"
INBOX="ledger_work_inbox_root_self_api_v1"
STATUS="ledger_work_submission_status_self_api_v1"
DECIDE="decide_ledger_work_intake_root_self_api_v1"

def must(condition,message):
    base.check(condition,message)
def sql(db,statement):
    return base.sql(db,statement)
def rpc(api,key,token,name,args):
    return base.rpc(api,key,token,name,args)
def allow(api,key,token,name,args):
    code,obj=rpc(api,key,token,name,args)
    must(code==200 and isinstance(obj,dict) and obj.get("ok") is True,
         f"Signed allow {name}: {code} {str(obj)[:200]}")
    return obj
def deny(api,key,token,name,args,reason):
    code,obj=rpc(api,key,token,name,args)
    must(code in (401,403) and isinstance(obj,dict) and
         (token is None or obj.get("code")=="42501"),
         f"NOT A DENIAL {reason}: {code} {str(obj)[:220]}")
    print("PASS denied",reason)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    a=parser.parse_args()
    must(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
         "Refuse nonlocal production DB")
    api,key=c1.local_status()
    base.setup_auth(a.db_url)
    tokens={}
    for name,expected in (("owner",c1.OWNER),("worker",c1.WORKER),
                          ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        must(claims.get("sub")==expected and claims.get("session_id"),
             "Signed claims do not match cloned Person")
        tokens[name]=token
    lex=tokens["owner"];anna=tokens["worker"]
    other=tokens["outsider"];unbound=tokens["no-seat"]
    original_people=sql(a.db_url,
        "select count(*) from reality.entities where entity_kind='person'")
    original_principals=sql(a.db_url,
        "select count(*) from atlas.principals")
    must(sql(a.db_url,f"select count(*) from atlas.principals "
         f"where person_id='{ANNA_PERSON}'::uuid and status='active'")=="1",
         "Fixture must bind exactly one Principal to the existing canonical Anna Person")
    must(sql(a.db_url,f"select count(*) from atlas.principal_ledger_authorities "
        f"where ledger_id='{ANNA_LEDGER}'::uuid and status='active' "
        f"and authority_kind='root_governing'")=="1","Anna root not established")
    # Anna is an Elm worker, not its root, even though she roots her own Ledger.
    deny(api,key,anna,PERSON_CHOICES,
         {"p_ledger_id":ELM,"p_limit":50,"p_after_person_id":None},
         "Anna's Elm employee seat cannot enumerate Elm personnel")
    deny(api,key,anna,DIRECT,{"p_ledger_id":ELM,
         "p_recipient_person_id":OWNER_PERSON,"p_sentence":"Forbidden peer assignment",
         "p_execution_date":datetime.date.today().isoformat(),
         "p_source_action_id":"reciprocal-denied-assign"},
         "Anna cannot compulsory-assign an Elm colleague by UUID")
    deny(api,key,anna,SEND,{"p_ledger_id":ELM,"p_recipient_person_id":OWNER_PERSON,
         "p_body":"Forbidden private roster probe","p_kind":"notice",
         "p_source_action_id":"reciprocal-denied-notice",
         "p_proposed_work_on":None},
         "Anna cannot probe an Elm colleague by targeted notice")
    # Lex roots Elm, but only has an ordinary connection in Anna's Ledger.
    deny(api,key,lex,PERSON_CHOICES,{"p_ledger_id":ANNA_LEDGER,"p_limit":100,
         "p_after_person_id":None},"Lex Elm root cannot read Anna's roster")
    deny(api,key,lex,INBOX,{"p_ledger_id":ANNA_LEDGER,"p_limit":100},
         "Lex Elm root cannot read Anna's Ledger-root inbox")
    deny(api,key,other,INBOX,{"p_ledger_id":ANNA_LEDGER,"p_limit":100},
         "Other Person without Anna root cannot read inbox")
    deny(api,key,unbound,PERSON_CHOICES,{"p_ledger_id":ELM,"p_limit":50,
         "p_after_person_id":None},"Unbound Person cannot read roster")
    deny(api,key,None,INBOX,{"p_ledger_id":ELM,"p_limit":50},
         "Anonymous cannot read private root inbox")
    # Negative read oracle: a connected employee must not even be able to
    # test another Person's Ledger seat by requesting an empty date agenda.
    # Self and current exact-root reads are separately admitted.
    today=datetime.date.today().isoformat()
    deny(api,key,anna,AGENDA,{"p_ledger_id":ELM,"p_person_id":OWNER_PERSON,
         "p_date":today,"p_limit":25},
         "Anna worker cannot probe a colleague's Elm agenda or seat")
    deny(api,key,lex,AGENDA,{"p_ledger_id":ANNA_LEDGER,"p_person_id":ANNA_PERSON,
         "p_date":today,"p_limit":25},
         "Lex Elm root cannot probe Anna's separate Ledger agenda")
    allow(api,key,anna,AGENDA,{"p_ledger_id":ELM,"p_person_id":ANNA_PERSON,
         "p_date":today,"p_limit":25})
    allow(api,key,lex,AGENDA,{"p_ledger_id":ELM,"p_person_id":ANNA_PERSON,
         "p_date":today,"p_limit":25})
    allow(api,key,anna,AGENDA,{"p_ledger_id":ANNA_LEDGER,"p_person_id":OWNER_PERSON,
         "p_date":today,"p_limit":25})
    # Prove positive root authority on each Ledger.
    a_roster=allow(api,key,lex,PERSON_CHOICES,{"p_ledger_id":ELM,"p_limit":50,
         "p_after_person_id":None})
    must(a_roster.get("rootAuthorityNotRequired") is False,
         "Elm root roster packet did not indicate restricted authority")
    b_roster=allow(api,key,anna,PERSON_CHOICES,{"p_ledger_id":ANNA_LEDGER,
         "p_limit":50,"p_after_person_id":None})
    must(b_roster.get("ledgerId")==ANNA_LEDGER,
         "Anna's own Ledger root roster incorrect")
    # Employee submits ONE original Work. It does not enter a Person Today.
    payload={"p_ledger_id":ELM,"p_title":"Clone check the Elm parking signs",
       "p_attention_date_proposal":datetime.date.today().isoformat(),
       "p_source_action_id":"daily:synthetic-ledger-request-001"}
    sent=allow(api,key,anna,SUBMIT,payload)
    must(sent.get("contractVersion")=="ledger_work_intake_v1" and
         sent.get("assignedToPerson") is False and
         sent.get("personDayPlacementEstablished") is False and
         sent.get("createdNow") is True,"Employee intake falsely assigned Work")
    replay=allow(api,key,anna,SUBMIT,payload)
    must(replay.get("workItemId")==sent.get("workItemId") and
         replay.get("intakeId")==sent.get("intakeId") and
         replay.get("createdNow") is False,"Idempotent submission cloned original Work")
    work=sent["workItemId"];intake=sent["intakeId"]
    must(sql(a.db_url,f"select count(*) from atlas.work_allocations where work_item_id='{work}'::uuid")=="0",
         "Employee intake assigned an individual")
    must(sql(a.db_url,f"select count(*) from atlas.work_execution_plans where work_item_id='{work}'::uuid")=="0",
         "Employee intake created a Work-on plan")
    must(sql(a.db_url,f"select count(*) from atlas.work_items where id='{work}'::uuid")=="1",
         "Ledger intake did not preserve one original Work")
    status=allow(api,key,anna,STATUS,{"p_intake_id":intake})
    must(status.get("workItemId")==work and status.get("title")==payload["p_title"],
         "Employee source reread could not verify the same original")
    deny(api,key,lex,STATUS,{"p_intake_id":intake},
         "Another Person cannot read employee's private submission receipt")
    inbox=allow(api,key,lex,INBOX,{"p_ledger_id":ELM,"p_limit":100})
    must(any(x.get("workItemId")==work for x in inbox.get("items",[]))
         and inbox.get("isPersonalWorkObligation") is False
         and inbox.get("notificationDeliveryClaimed") is False,
         "Root inbox lost original Work or claimed a Person obligation")
    deny(api,key,anna,INBOX,{"p_ledger_id":ELM,"p_limit":100},
         "Anna worker cannot read confidential root inbox")
    result=allow(api,key,lex,DECIDE,{"p_intake_id":intake,
         "p_decision":"accepted_for_ledger","p_expected_revision":0,
         "p_reason":"Synthetic Ledger governance accepted this original Work"})
    must(result.get("workItemId")==work and
         result.get("personWorkAssignmentCreated") is False,
         "Root review impersonated an individual")
    state=allow(api,key,anna,STATUS,{"p_intake_id":intake})
    must(state.get("reviewState")=="accepted_for_ledger",
         "Employee cannot read bounded review status")
    # Strict reciprocal owner limited on Anna's Ledger; root only on Elm.
    again=allow(api,key,anna,SUBMIT,{"p_ledger_id":ANNA_LEDGER,
       "p_title":"Clone Anna's ledger supply task",
       "p_attention_date_proposal":None,
       "p_source_action_id":"daily:synthetic-anna-ledger-002"})
    anna_inbox=allow(api,key,anna,INBOX,{"p_ledger_id":ANNA_LEDGER,"p_limit":100})
    must(any(x.get("workItemId")==again.get("workItemId") for x in anna_inbox.get("items",[])),
         "Anna root cannot read her own Ledger intake")
    # Revoking Anna's root does not revoke her ordinary Elm worker seat.
    # Native root-custody constraint permits 'active' or 'ended' with
    # ended_at. 'revoked' is not a valid authority status, and an invalid
    # fixture update cannot count as a tested revocation.
    sql(a.db_url,f"update atlas.principal_ledger_authorities "
         f"set status='ended', ended_at=now() "
         f"where id='{ANNA_ROOT}'::uuid and status='active'")
    must(sql(a.db_url,f"select count(*) from atlas.principal_ledger_authorities "
         f"where id='{ANNA_ROOT}'::uuid and status='ended' "
         f"and ended_at is not null")=="1",
         "One original Anna root must have ended before testing revocation")
    deny(api,key,anna,INBOX,{"p_ledger_id":ANNA_LEDGER,"p_limit":100},
         "Revoked Anna root retained access with existing signed JWT")
    deny(api,key,anna,PERSON_CHOICES,{"p_ledger_id":ANNA_LEDGER,"p_limit":100,
         "p_after_person_id":None},"Revoked Anna root retained directory access")
    deny(api,key,anna,AGENDA,{"p_ledger_id":ANNA_LEDGER,"p_person_id":OWNER_PERSON,
         "p_date":today,"p_limit":25},
         "Revoked Anna root cannot see another Person agenda")
    # Ending root authority on Anna's separate Ledger must not silently
    # remove an independently active worker seat on the Elm Ledger.
    allow(api,key,anna,AGENDA,{"p_ledger_id":ELM,"p_person_id":ANNA_PERSON,
         "p_date":today,"p_limit":25})
    must(sql(a.db_url,"select count(*) from reality.entities where entity_kind='person'")
         ==original_people and
         sql(a.db_url,"select count(*) from atlas.principals")==original_principals,
         "Work submission created or duplicated a Person or Principal")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text("PASS signed reciprocal Elm-worker/Anna-root Lex-root/limited "
        "separate auth sessions, confidential intake, denied guessed IDs, "
        "idempotent one-original Work, exact source readback, revocation; "
        "no shadow Person or Principal. LOCAL DISPOSABLE CLONE ONLY.\n")
    print("PASS reciprocal Ledger root, private intake and original Person identity")
if __name__=="__main__":
    main()

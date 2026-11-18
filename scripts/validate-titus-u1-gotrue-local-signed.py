#!/usr/bin/env python3
"""U1 real GoTrue + PostgREST proof. Requires isolated LOCAL Supabase only.

The verified JWTs are minted by a local GoTrue instance, never handwritten.
The database is disposable and contains only fictional schema + People. This
does NOT prove production-schema migration or delegated manager establishment.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import base64
import json
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

MANAGER="11111111-1111-4111-8111-111111111111"
RECIPIENT="22222222-2222-4222-8222-222222222222"
OUTSIDER="33333333-3333-4333-8333-333333333333"
INSTITUTION="44444444-4444-4444-8444-444444444444"
LEDGER="77777777-7777-4777-8777-777777777777"
PASSWORD="Titus-U1-fictional-local-only-2026!"
DB_RE=r"^postgres(?:ql)?://[^@]+@127\.0\.0\.1:54322/postgres$"


def check(p,detail):
    if not p: raise AssertionError("TITUS U1 LOCAL SIGNED: "+detail)


def local_db(url):
    return bool(re.fullmatch(DB_RE,url))


def local_api(url):
    u=urllib.parse.urlparse(url)
    return u.scheme=="http" and u.hostname in ("localhost","127.0.0.1") and u.port==54321


def sql(db,statement):
    check(local_db(db),"SQL database URL must be local :54322")
    cmd=["psql",db,"-X","-A","-t","-v","ON_ERROR_STOP=1","-c",statement]
    return subprocess.run(cmd,capture_output=True,text=True,check=True).stdout.strip()


def get_local_status():
    proc=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=True)
    kv={}
    for line in proc.stdout.splitlines():
        if "=" in line:
            k,v=line.split("=",1)
            kv[k.strip()]=v.strip().strip('"')
    api=kv.get("API_URL","").rstrip("/")
    key=kv.get("ANON_KEY") or kv.get("SUPABASE_ANON_KEY")
    check(local_api(api),"Local API must be http://127.0.0.1:54321")
    check(isinstance(key,str) and len(key)>20,"Missing local-only anon key")
    return api,key


def req(api,key,endpoint,data,token=None):
    check(local_api(api),"Remote API is forbidden")
    body=json.dumps(data).encode("utf-8")
    headers={"apikey":key,"Content-Type":"application/json"}
    if token: headers["Authorization"]="Bearer "+token
    call=urllib.request.Request(api+endpoint,body,headers,method="POST")
    try:
        with urllib.request.urlopen(call,timeout=20) as r:
            return r.status,json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raw=e.read().decode("utf-8")
        try: result=json.loads(raw)
        except ValueError: result={"code":"invalid_json"}
        return e.code,result


def claims(token):
    parts=token.split(".")
    check(len(parts)==3,"Not a three-part signed JWT")
    payload=parts[1]+"="*(-len(parts[1])%4)
    return json.loads(base64.urlsafe_b64decode(payload))


def create_signed_person(api,key,role):
    email="titus-u1-"+role+"@example.invalid"
    # This is local GoTrue sign-up; we do not insert sessions or forge JWTs.
    status,data=req(api,key,"/auth/v1/signup",
       {"email":email,"password":PASSWORD})
    check(status==200 and isinstance(data,dict),
       "Local GoTrue signup must succeed for "+role+" (HTTP "+str(status)+")")
    status,data=req(api,key,"/auth/v1/token?grant_type=password",
       {"email":email,"password":PASSWORD})
    check(status==200 and isinstance(data,dict) and data.get("access_token"),
       "Local GoTrue password sign-in failed for "+role)
    token=data["access_token"]
    jwt=claims(token)
    check(jwt.get("role")=="authenticated" and
       bool(jwt.get("session_id")) and bool(jwt.get("sub")),
       "GoTrue signed token missing session/subject for "+role)
    for field in ("session_id","sub"): uuid.UUID(jwt[field])
    return token,jwt


def deny(api,key,token,name,params,label):
    code,result=req(api,key,"/rest/v1/rpc/"+name,params,token)
    check(code in (401,403) and isinstance(result,dict) and
        result.get("code")=="42501",
        label+" must be SQL identity/authority denial (HTTP "+str(code)+")")
    print("PASS",label)


def allow(api,key,token,name,params,label):
    code,result=req(api,key,"/rest/v1/rpc/"+name,params,token)
    check(code==200 and isinstance(result,dict),
       label+" returned "+str(code)+" "+str(result)[:160])
    print("PASS",label)
    return result


def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(local_db(args.db_url),"Refuse any nonlocal DB")
    api,key=get_local_status()
    signed={}
    for role,person in (("manager",MANAGER),("recipient",RECIPIENT),("outsider",OUTSIDER)):
        token,jwt=create_signed_person(api,key,role)
        uid=jwt["sub"];session=jwt["session_id"]
        check(sql(args.db_url,"select count(*) from auth.sessions "
          f"where id='{session}'::uuid and user_id='{uid}'::uuid")=="1",
          "GoTrue signed session not recorded in auth.sessions")
        check(sql(args.db_url,
          f"select count(*) from auth.users where id='{uid}'::uuid")=="1",
          "GoTrue signed Auth user missing")
        sql(args.db_url,"insert into reality.auth_person_bindings "
          "(auth_user_id,person_entity_id,binding_state) "
          f"values('{uid}'::uuid,'{person}'::uuid,'active')")
        signed[role]=(token,jwt)
    check(sql(args.db_url,"select count(*) from reality.auth_person_bindings "
      "where binding_state='active'")=="3","One binding for each signer")
    manager=signed["manager"][0]
    recipient=signed["recipient"][0]
    outsider=signed["outsider"][0]
    context="titus_account_contexts_self_api_v1"
    inbox="titus_institution_account_self_service_self_api_v1"
    invite="titus_institution_account_invite_self_api_v1"
    accept="titus_institution_account_accept_self_api_v1"
    withdraw="titus_institution_account_withdraw_self_api_v1"
    cancel="titus_institution_account_cancel_invite_self_api_v1"
    select="titus_account_context_check_self_api_v1"
    manage="shared_titus_institution_manager_command_self_api_v1"
    bootstrap="shared_titus_institution_root_bootstrap_self_api_v1"
    organization="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    def governance(action,prior=None,new=None,request=None,ledger=LEDGER):
        return {"p_ledger_id":ledger,"p_action":action,
          "p_prior_manager_person_id":prior,
          "p_new_manager_person_id":new,
          "p_request_id":request or str(uuid.uuid4())}
    assert_private=allow(api,key,recipient,context,{},"signed recipient personal-only")
    check(assert_private.get("institutions")==[] and
      assert_private.get("personal",{}).get("personId")==RECIPIENT,
      "Uninvited recipient must see only personal context")
    check(allow(api,key,manager,context,{},"signed manager also personal-only")
      .get("institutions")==[],"Manager must not self-admit")
    check(allow(api,key,outsider,inbox,{},"outsider inbox empty")
      .get("pending")==[],"Outsider may not see recipient invitations")

    # A live Auth identity, institutional root, or Ledger Seat does NOT
    # automatically create the manager responsibility. A distinct signed
    # root-governed appointment is the only source of that authority.
    initial={"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
      "p_request_id":str(uuid.uuid4())}
    deny(api,key,manager,invite,initial,
      "independent root is not automatically institution account manager")
    deny(api,key,recipient,bootstrap,{"p_ledger_id":LEDGER,
       "p_organization_id":organization,"p_request_id":str(uuid.uuid4())},
       "non-governing Person cannot bootstrap root")
    deny(api,key,manager,bootstrap,{"p_ledger_id":"88888888-8888-4888-8888-888888888888",
       "p_organization_id":organization,"p_request_id":str(uuid.uuid4())},
       "governing principal cannot bootstrap wrong Ledger")
    # Atlas's active governing participation alone is NOT a source for a
    # native Reality Ledger; neither is a compatibility name/identity bridge.
    # This fixture mirrors the unresolved live *shape*, never the customer's data.
    atlas_only_org="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    atlas_only_ledger="66666666-6666-4666-8666-666666666666"
    orphan_request=lambda:{
      "p_ledger_id":atlas_only_ledger,
      "p_organization_id":atlas_only_org,
      "p_request_id":str(uuid.uuid4())}
    deny(api,key,manager,bootstrap,orphan_request(),
      "Atlas-only governing pair without native Ledger cannot bootstrap")
    sql(args.db_url,
      "insert into compatibility.legacy_bindings("
      "legacy_schema,legacy_table,legacy_key,disposition,"
      "new_schema,new_table,new_id) values("
      f"'atlas','organizations','{atlas_only_org}','maps_to',"
      f"'reality','entities','{INSTITUTION}'::uuid)")
    deny(api,key,manager,bootstrap,orphan_request(),
      "adding Reality mapping alone cannot repair missing native Ledger")
    check(sql(args.db_url,
      "select count(*) from titus.institution_account_root_origins_v1")=="0",
      "Orphaned Atlas source minted a Titus root")
    # The REAL Atlas governing source independently verifies both the native
    # Ledger and the Organization's primary governing Ledger under the SAME
    # canonical Principal. The scratch adapter models those two checks but
    # makes no claim to restore the complete protected production schema.
    native_probe="titus_u1_fixture_native_owner_probe_v1"
    operating_ledger="88888888-8888-4888-8888-888888888888"
    native_params={"p_ledger_id":operating_ledger}
    deny(api,key,manager,native_probe,native_params,
      "native operating Ledger without its own root authority denies despite primary root")
    native_authority="f0f0f0f0-0000-4000-8000-000000000001"
    sql(args.db_url,
      "insert into atlas.principal_ledger_authorities("
      "id,principal_id,ledger_id,authority_kind,status) values("
      f"'{native_authority}'::uuid,"
      "'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid,"
      f"'{operating_ledger}'::uuid,'root_governing','active')")
    check(allow(api,key,manager,native_probe,native_params,
      "two distinct root-governed Ledgers admit one signed governing Principal")
      .get("authorized") is True,"Two-Ledger source did not establish identity")
    deny(api,key,recipient,native_probe,native_params,
      "another signed Person cannot borrow principal's native and governing roots")
    sql(args.db_url,
      "update atlas.principal_ledger_authorities set status='ended' "
      "where principal_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid "
      f"and ledger_id='{LEDGER}'::uuid")
    deny(api,key,manager,native_probe,native_params,
      "native root without separate current primary governing root denies")
    sql(args.db_url,
      "update atlas.principal_ledger_authorities set status='active' "
      "where principal_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'::uuid "
      f"and ledger_id='{LEDGER}'::uuid")
    sql(args.db_url,
      "update ledger.seats set seat_state='ended' "
      f"where ledger_id='{operating_ledger}'::uuid "
      f"and person_entity_id='{MANAGER}'::uuid")
    deny(api,key,manager,native_probe,native_params,
      "two root authorities do not replace a current native Ledger Seat")
    sql(args.db_url,
      "update ledger.seats set seat_state='active' "
      f"where ledger_id='{operating_ledger}'::uuid "
      f"and person_entity_id='{MANAGER}'::uuid")
    check(allow(api,key,manager,native_probe,native_params,
      "restored native Seat and both roots allow signed Atlas model")
      .get("authorized") is True,"Restored source did not recover")
    # Titus institutional root is deliberately STRICTER: its root attaches
    # to the uniquely governing PRIMARY institutional Ledger, not an
    # operating Ledger, even when Atlas governs both Ledgers correctly.
    deny(api,key,manager,bootstrap,
      {"p_ledger_id":operating_ledger,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
      "Titus institutional root cannot bootstrap on merely operating Ledger")
    check(sql(args.db_url,
      "select count(*) from titus.institution_account_root_origins_v1")=="0",
      "Operating Ledger issued forbidden Titus root")
    # A governing Principal for an Atlas Organization may not establish a
    # Titus institutional root unless the separate compatibility original
    # maps EXACTLY that organization to the native canonical Reality Entity.
    # These deliberate mutations touch only the fictional disposable DB.
    foreign_institution="55555555-5555-4555-8555-555555555555"
    sql(args.db_url,
      "insert into reality.entities(id,entity_kind,stable_key) "
      f"values('{foreign_institution}'::uuid,'business','fictional-foreign-org')")
    sql(args.db_url,
      "update compatibility.legacy_bindings set new_id="
      f"'{foreign_institution}'::uuid where legacy_key='{organization}'")
    deny(api,key,manager,bootstrap,
      {"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
       "explicit Atlas Organization mapping to wrong Reality institution denies")
    sql(args.db_url,
      "update compatibility.legacy_bindings set new_id="
      f"'{INSTITUTION}'::uuid where legacy_key='{organization}'")
    duplicate_id=str(uuid.uuid4())
    sql(args.db_url,
      "insert into compatibility.legacy_bindings("
      "id,legacy_schema,legacy_table,legacy_key,disposition,"
      "new_schema,new_table,new_id) values("
      f"'{duplicate_id}'::uuid,'atlas','organizations','{organization}','maps_to',"
      f"'reality','entities','{INSTITUTION}'::uuid)")
    deny(api,key,manager,bootstrap,
      {"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
       "two competing Atlas-to-Reality organization originals deny")
    sql(args.db_url,
      f"delete from compatibility.legacy_bindings where id='{duplicate_id}'::uuid")
    sql(args.db_url,
      f"delete from compatibility.legacy_bindings where legacy_key='{organization}'")
    deny(api,key,manager,bootstrap,
      {"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
       "missing organization Reality mapping denies rather than guessing")
    sql(args.db_url,
      "insert into compatibility.legacy_bindings("
      "legacy_schema,legacy_table,legacy_key,disposition,new_schema,new_table,new_id) "
      f"values('atlas','organizations','{organization}','maps_to',"
      f"'reality','entities','{INSTITUTION}'::uuid)")
    first_root={"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())}
    origin=allow(api,key,manager,bootstrap,first_root,
       "signed native and institutional governing Principal establishes root")
    check(origin.get("alreadyExists") is False,"root not established")
    retry=allow(api,key,manager,bootstrap,first_root,
       "same root establishment is idempotent")
    check(retry.get("alreadyExists") is True and
       retry.get("originId")==origin.get("originId"),"root retry changed source")

    deny(api,key,recipient,manage,governance("appoint",new=RECIPIENT),
      "recipient cannot appoint a manager")
    deny(api,key,outsider,manage,governance("appoint",new=OUTSIDER),
      "outsider cannot appoint a manager")
    deny(api,key,manager,manage,governance(
      "appoint",new=MANAGER,ledger="88888888-8888-4888-8888-888888888888"),
      "root cannot appoint across second Ledger of same institution")
    first_management=governance("appoint",new=MANAGER)
    appointed=allow(api,key,manager,manage,first_management,
      "independent signed institution root appoints manager")
    check(appointed.get("alreadyExists") is False and appointed.get("governanceId"),
      "Explicit manager appointment did not record an original")
    retry=allow(api,key,manager,manage,first_management,
      "idempotent source-governed manager appointment")
    check(retry.get("governanceId")==appointed["governanceId"] and
      retry.get("alreadyExists") is True,"Manager appointment replay changed original")
    deny(api,key,manager,manage,governance("appoint",new=MANAGER),
      "current manager cannot be silently appointed twice")
    deny(api,key,manager,
      "shared_titus_institution_root_relinquish_self_api_v1",
      {"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
      "root cannot exit with active institution account manager")
    deny(api,key,outsider,invite,initial,"outsider cannot invite")
    deny(api,key,recipient,invite,initial,"recipient cannot issue own admission")
    deny(api,key,manager,invite,
       {"p_ledger_id":"88888888-8888-4888-8888-888888888888",
        "p_recipient_person_id":RECIPIENT,"p_request_id":str(uuid.uuid4())},
        "manager cannot issue to same institution via wrong Ledger")
    first=allow(api,key,manager,invite,initial,"genuine signed manager invitation")
    check(first.get("alreadyExists") is False,"First issue not an original")
    again=allow(api,key,manager,invite,initial,"idempotent manager invitation")
    check(again.get("invitationId")==first.get("invitationId") and
      again.get("alreadyExists") is True,"Invitation receipt was not idempotent")
    inv=first["invitationId"]
    check(allow(api,key,manager,inbox,{},"manager cannot inspect recipient inbox")
      .get("pending")==[],"Manager acquired recipient invite")
    check(allow(api,key,outsider,inbox,{},"outsider cannot inspect recipient inbox")
      .get("pending")==[],"Outsider acquired recipient invite")
    pending=allow(api,key,recipient,inbox,{},"recipient sees own pending invite")
    check(len(pending.get("pending",[]))==1 and
      pending["pending"][0]["invitationId"]==inv,
      "Recipient inbox did not contain the exact invitation")
    deny(api,key,manager,accept,
      {"p_invitation_id":inv,"p_request_id":str(uuid.uuid4())},
      "manager cannot accept as another Person")
    deny(api,key,outsider,accept,
      {"p_invitation_id":inv,"p_request_id":str(uuid.uuid4())},
      "outsider cannot accept")

    receipt=str(uuid.uuid4())
    accepted=allow(api,key,recipient,accept,
      {"p_invitation_id":inv,"p_request_id":receipt},
      "recipient genuine signed acceptance")
    check(accepted.get("alreadyExists") is False and accepted.get("admissionId"),
       "Acceptance did not issue new admission")
    admission=accepted["admissionId"]
    repeat=allow(api,key,recipient,accept,
      {"p_invitation_id":inv,"p_request_id":receipt},
      "same Person accepted-idempotent replay")
    check(repeat.get("admissionId")==admission and repeat.get("alreadyExists") is True,
      "Accepted replay mutated original")
    context_result=allow(api,key,recipient,context,{},
      "accepted recipient has institution context")
    check(len(context_result.get("institutions",[]))==1 and
      context_result["institutions"][0].get("ledgerId")==LEDGER and
      context_result.get("personal",{}).get("personId")==RECIPIENT,
      "Context selector lost canonical Person or institution")
    deny(api,key,outsider,select,
      {"p_kind":"institution","p_ledger_id":LEDGER},
      "outsider cannot select recipient institution")
    deny(api,key,manager,select,
      {"p_kind":"institution","p_ledger_id":LEDGER},
      "manager invite is not manager admission")
    check(allow(api,key,recipient,inbox,{},"accepted recipient has own exit reference")
      ["active"][0]["admissionId"]==admission,
      "Accepted admission must be recipient-private exit ID")
    # The same Auth user can have a second independently minted REAL session;
    # it sees the same Person and independently sourced account scopes.
    later_status,later_data=req(api,key,"/auth/v1/token?grant_type=password",
      {"email":"titus-u1-recipient@example.invalid","password":PASSWORD})
    check(later_status==200 and later_data.get("access_token"),
      "Second genuine signed session for ONE Auth user missing")
    recipient_later=later_data["access_token"]
    later_claims=claims(recipient_later)
    check(later_claims["sub"]==signed["recipient"][1]["sub"] and
      later_claims["session_id"]!=signed["recipient"][1]["session_id"],
      "Second signed session changed human identity")
    check(len(allow(api,key,recipient_later,context,{},
      "same Person second signed session sees admitted institution")
      ["institutions"])==1,"Separate signed session lost current scope")

    deny(api,key,manager,cancel,
      {"p_invitation_id":inv,"p_request_id":str(uuid.uuid4())},
      "accepted invitation may not be cancelled")

    exit_request=str(uuid.uuid4())
    result=allow(api,key,recipient,withdraw,
      {"p_admission_id":admission,"p_request_id":exit_request},
      "recipient independently withdraws")
    check(result.get("ended") is True and result.get("alreadyExists") is False,
       "Withdrawal source unsuccessful")
    check(allow(api,key,recipient,context,{},"personal scope survives exit")
      .get("institutions")==[],"University access survived withdrawal")
    check(allow(api,key,recipient,inbox,{},"recipient exited inbox")
      .get("active")==[],"Withdrawn admission leaked into inbox")
    deny(api,key,recipient,accept,
      {"p_invitation_id":inv,"p_request_id":receipt},
      "withdrawn historical accepted invitation cannot revive")

    check(allow(api,key,recipient_later,context,{},
      "second signed session also lost withdrawn institution")
      ["institutions"]==[],"Withdrawal not reflected in other live session")

    # A second ORIGINAL invitation is required after leaving, and the manager
    # may withdraw only using current exact institutional responsibility.
    rejoin=allow(api,key,manager,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},"re-invite as new source original")
    rejoined=allow(api,key,recipient,accept,
      {"p_invitation_id":rejoin["invitationId"],
       "p_request_id":str(uuid.uuid4())},"new admission after withdrawal")
    check(rejoined.get("admissionId")!=admission,
      "Rejoining overwrote the withdrawn original")
    allow(api,key,manager,withdraw,
      {"p_admission_id":rejoined["admissionId"],
       "p_request_id":str(uuid.uuid4())},"current exact manager withdrawal")
    check(allow(api,key,recipient,context,{},
      "manager withdrawal leaves signed personal context")
      ["institutions"]==[],"Institution remained after manager withdrawal")

    # A cancelled INVITATION cannot be accepted, distinct from withdrawal.
    cancelled=allow(api,key,manager,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},"issue cancellation probe invite")
    allow(api,key,manager,cancel,
      {"p_invitation_id":cancelled["invitationId"],
       "p_request_id":str(uuid.uuid4())},"manager cancels unused invitation")
    deny(api,key,recipient,accept,
      {"p_invitation_id":cancelled["invitationId"],
       "p_request_id":str(uuid.uuid4())},"cancelled invite cannot be accepted")
    check(allow(api,key,recipient,inbox,{},
      "cancelled invitation absent from signed inbox")
      ["pending"]==[],"Cancelled invite remained pending")

    # Issuer's live Reality authority must exist AT ACCEPTANCE, not merely
    # when the original invitation was created.
    pending_stale=allow(api,key,manager,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},"issue invitation before manager exits")
    deny(api,key,manager,manage,governance("transfer",
       prior=RECIPIENT,new=OUTSIDER),"wrong expected prior manager cannot transfer")
    transferred=allow(api,key,manager,manage,governance("transfer",
       prior=MANAGER,new=OUTSIDER),
       "institution root transfers manager atomically to a distinct Person")
    check(transferred.get("alreadyExists") is False,"Transfer must create original")
    deny(api,key,manager,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},
       "former manager cannot issue after governed transfer")
    outsider_invite=allow(api,key,outsider,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},
       "new manager may issue under transferred responsibility")
    allow(api,key,outsider,cancel,
      {"p_invitation_id":outsider_invite["invitationId"],
       "p_request_id":str(uuid.uuid4())},
       "transferred manager may cancel only their unaccepted invite")
    deny(api,key,outsider,manage,governance("revoke",prior=OUTSIDER),
       "manager without institutional root cannot revoke their own root grant")
    revoked=allow(api,key,manager,manage,governance("revoke",prior=OUTSIDER),
       "independent root revokes transferred manager")
    check(revoked.get("alreadyExists") is False,"Revocation must create original")
    deny(api,key,outsider,invite,
      {"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
       "p_request_id":str(uuid.uuid4())},
       "revoked manager cannot issue an invitation")
    check(sql(args.db_url,
      "select count(*) from titus.institution_account_manager_governance_v1")=="3",
      "Expected exactly one appointment, transfer and revocation original")
    deny(api,key,recipient,accept,
      {"p_invitation_id":pending_stale["invitationId"],
       "p_request_id":str(uuid.uuid4())},
       "recipient cannot accept stale-issued invitation")
    check(allow(api,key,recipient,inbox,{},
      "stale-issued pending invitation hidden")["pending"]==[],
      "Former manager's source invitation leaked as actionable")
    # Root withdrawal is distinct from manager revocation: no stale signed
    # root can append manager changes, even when Person login remains good.
    allow(api,key,manager,
      "shared_titus_institution_root_relinquish_self_api_v1",
      {"p_ledger_id":LEDGER,"p_organization_id":organization,
       "p_request_id":str(uuid.uuid4())},
      "signed institutional root voluntarily ends own source")
    deny(api,key,manager,manage,governance("appoint",new=MANAGER),
      "ended institution root cannot reappoint a manager")

    # New original requires an independent Atlas governing root *again*;
    # a prior Titus manager or mere historical root cannot reappoint itself.
    root_source={"p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_request_id":str(uuid.uuid4())}
    new_root=allow(api,key,manager,bootstrap,root_source,
      "independent Atlas governing root re-establishes after relinquishment")
    check(new_root.get("alreadyExists") is False,"root recovery must be a new original")
    nominate_root="shared_titus_institution_root_nominate_self_api_v1"
    accept_root="shared_titus_institution_root_accept_self_api_v1"
    cancel_root="shared_titus_institution_root_cancel_self_api_v1"
    relinquish_root="shared_titus_institution_root_relinquish_self_api_v1"
    invitation_args=lambda req_id:{
      "p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_recipient_person_id":OUTSIDER,"p_request_id":req_id}
    deny(api,key,recipient,nominate_root,invitation_args(str(uuid.uuid4())),
      "recipient cannot nominate institution root successor")
    deny(api,key,manager,nominate_root,{
      **invitation_args(str(uuid.uuid4())),
      "p_ledger_id":"88888888-8888-4888-8888-888888888888"},
      "institution root cannot nominate successor across second Ledger")
    first_nomination=allow(api,key,manager,nominate_root,
      invitation_args(str(uuid.uuid4())),
      "current root nominates successor without granting rights")
    check(first_nomination.get("alreadyExists") is False,"nomination must issue original")
    allow(api,key,manager,cancel_root,{"p_invitation_id":first_nomination["invitationId"],
      "p_request_id":str(uuid.uuid4())},
      "current root cancels still-unaccepted succession invitation")
    deny(api,key,outsider,accept_root,
      {"p_invitation_id":first_nomination["invitationId"],
       "p_request_id":str(uuid.uuid4())},
      "cancelled root succession invitation is not reusable")
    second_nomination=allow(api,key,manager,nominate_root,
      invitation_args(str(uuid.uuid4())),
      "root issues separate new succession nomination")
    deny(api,key,recipient,accept_root,
      {"p_invitation_id":second_nomination["invitationId"],
       "p_request_id":str(uuid.uuid4())},
      "unrelated Person cannot accept root succession")
    accept_args={"p_invitation_id":second_nomination["invitationId"],
      "p_request_id":str(uuid.uuid4())}
    successor=allow(api,key,outsider,accept_root,accept_args,
      "independently signed nominated successor accepts root transfer")
    check(successor.get("alreadyExists") is False and successor.get("originId"),
      "root succession original missing")
    repeated_successor=allow(api,key,outsider,accept_root,accept_args,
      "signed successor acceptance replay is exact original")
    check(repeated_successor.get("alreadyExists") is True and
      repeated_successor.get("originId")==successor["originId"],
      "successor receipt changed during replay")
    deny(api,key,manager,manage,governance("appoint",new=MANAGER),
      "former Titus root cannot appoint managers after accepted succession")
    deny(api,key,manager,bootstrap,{
      "p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_request_id":str(uuid.uuid4())},
      "independent Atlas root cannot overrule existing successor Tito root")
    allow(api,key,outsider,manage,governance("appoint",new=RECIPIENT),
      "signed successor root can appoint a manager without Atlas owner label")
    deny(api,key,outsider,relinquish_root,{
      "p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_request_id":str(uuid.uuid4())},
      "successor may not relinquish with active institutional manager")
    allow(api,key,outsider,manage,governance("revoke",prior=RECIPIENT),
      "signed successor root may revoke current Titus manager")
    allow(api,key,outsider,relinquish_root,{
      "p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_request_id":str(uuid.uuid4())},
      "successor expressly relinquishes root without appointing new root")
    deny(api,key,outsider,manage,governance("appoint",new=RECIPIENT),
      "former successor root cannot govern after relinquishment")
    restored=allow(api,key,manager,bootstrap,{
      "p_ledger_id":LEDGER,"p_organization_id":organization,
      "p_request_id":str(uuid.uuid4())},
      "independent Atlas governing root can recover after successor ends")
    check(restored.get("alreadyExists") is False,"recovered root must have new original")
    check(sql(args.db_url,"select count(*) from titus.institution_account_root_origins_v1")=="4",
      "Expected initial, rebootstrap, accepted succession, final rebootstrap originals")
    check(sql(args.db_url,"select count(*) from titus.institution_account_root_endings_v1")=="3",
      "Expected first relinquishment, accepted transfer, successor relinquishment")
    check(sql(args.db_url,"select count(*) from reality.responsibility_relations "
      "where responsibility_key='titus_institution_account_root_governance' "
      "and relation_state='active' and ended_at is null")=="1",
      "At most one institution root may remain active")

    # Race a manager appointment against the SAME institution root's
    # relinquishment. The ledger-first source must serialize both commands:
    # one succeeds, the other fails closed, and no orphaned manager remains.
    # Two actual, concurrent GoTrue-authenticated PostgREST requests are made;
    # no psql-injected JWT or fake role is involved.
    concurrent_barrier=Barrier(2)
    def race_signed_rpc(endpoint,body):
        concurrent_barrier.wait(timeout=8)
        return req(api,key,"/rest/v1/rpc/"+endpoint,body,manager)
    with ThreadPoolExecutor(max_workers=2) as executor:
        appoint_future=executor.submit(
            race_signed_rpc,manage,governance("appoint",new=MANAGER))
        relinquish_future=executor.submit(
            race_signed_rpc,relinquish_root,{
                "p_ledger_id":LEDGER,"p_organization_id":organization,
                "p_request_id":str(uuid.uuid4())})
        appoint_result=appoint_future.result(timeout=30)
        relinquish_result=relinquish_future.result(timeout=30)
    statuses=(appoint_result[0],relinquish_result[0])
    check(sorted(statuses)==[200,403],
      "concurrent root relinquish vs manager appointment must serialize "
      f"into exactly one success and one 42501 denial; got {statuses}")
    rejected=appoint_result if appoint_result[0]!=200 else relinquish_result
    check(rejected[1].get("code")=="42501",
      "concurrent losing transaction must fail by the authority guard, not deadlock")
    active_manager=int(sql(args.db_url,
      "select count(*) from reality.responsibility_relations where "
      "responsibility_key='titus_institution_account_management' "
      "and jurisdiction_entity_id='44444444-4444-4444-8444-444444444444'::uuid "
      "and scope->>'ledgerId'='77777777-7777-4777-8777-777777777777' "
      "and relation_state='active' and ended_at is null"))
    active_root=int(sql(args.db_url,
      "select count(*) from reality.responsibility_relations where "
      "responsibility_key='titus_institution_account_root_governance' "
      "and jurisdiction_entity_id='44444444-4444-4444-8444-444444444444'::uuid "
      "and scope->>'ledgerId'='77777777-7777-4777-8777-777777777777' "
      "and relation_state='active' and ended_at is null"))
    check((active_root,active_manager) in ((1,1),(0,0)),
      "simultaneous commands must never leave an active manager without root")
    print("PASS concurrent genuine signed Ledger-first authority serialization "
      "and no-orphan invariant")

    # A GoTrue-issued token can remain signed after its session is removed;
    # source rechecks auth.sessions rather than trusting token validity alone.
    later_id=later_claims["session_id"]
    sql(args.db_url,f"delete from auth.sessions where id='{later_id}'::uuid")
    deny(api,key,recipient_later,context,{},
      "revoked second genuine JWT session cannot read account contexts")
    check(allow(api,key,recipient,context,{},
      "first genuine session remains valid after second session revocation")
      ["personal"]["personId"]==RECIPIENT,
      "Revoking one signed session destroyed another valid session")
    # With one current Auth user, retiring its unique Person binding rejects
    # this remaining good signed session without generating another Person.
    rid=signed["recipient"][1]["session_id"]
    sql(args.db_url,"update reality.auth_person_bindings set "
      "binding_state='retired',retired_at=clock_timestamp() "
      f"where auth_user_id='{signed['recipient'][1]['sub']}'::uuid")
    deny(api,key,recipient,context,{},
      "signed session cannot bypass retired canonical Person binding")
    check(sql(args.db_url,"select count(*) from "
      "titus.institution_account_admissions_v1")=="2",
      "Expected exactly two immutable original admissions after rejoin")
    check(sql(args.db_url,"select count(*) from "
      "titus.institution_account_admission_withdrawals_v1")=="2",
      "Expected exactly two immutable original withdrawals")
    check(sql(args.db_url,"select count(*) from auth.users")=="3",
      "Source minted an extra Auth user")
    Path(args.output).write_text(
      "PASS genuine local GoTrue + PostgREST U1 identity, issuer, consent, "
      "recipient privacy, replay, withdrawal and stale-session checks; "
      "NOT production-shaped or manager-establishment proof.\n",encoding="utf-8")
    print("PASS Titus U1 LOCAL real signed GoTrue verification; no production touched")


if __name__=="__main__":
    main()

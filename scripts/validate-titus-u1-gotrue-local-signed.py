#!/usr/bin/env python3
"""U1 real GoTrue + PostgREST proof. Requires isolated LOCAL Supabase only.

The verified JWTs are minted by a local GoTrue instance, never handwritten.
The database is disposable and contains only fictional schema + People. This
does NOT prove production-schema migration or delegated manager establishment.
"""
import argparse
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
    assert_private=allow(api,key,recipient,context,{},"signed recipient personal-only")
    check(assert_private.get("institutions")==[] and
      assert_private.get("personal",{}).get("personId")==RECIPIENT,
      "Uninvited recipient must see only personal context")
    check(allow(api,key,manager,context,{},"signed manager also personal-only")
      .get("institutions")==[],"Manager must not self-admit")
    check(allow(api,key,outsider,inbox,{},"outsider inbox empty")
      .get("pending")==[],"Outsider may not see recipient invitations")

    initial={"p_ledger_id":LEDGER,"p_recipient_person_id":RECIPIENT,
      "p_request_id":str(uuid.uuid4())}
    deny(api,key,outsider,invite,initial,"outsider cannot invite")
    deny(api,key,recipient,invite,initial,"recipient cannot issue own admission")
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

    # A genuinely signed token's session can be invalidated while JWT remains
    # cryptographically intact; the source must recheck auth.sessions.
    rid=signed["recipient"][1]["session_id"]
    sql(args.db_url,f"delete from auth.sessions where id='{rid}'::uuid")
    deny(api,key,recipient,context,{},"stale genuine JWT after session deletion")
    check(sql(args.db_url,"select count(*) from "
      "titus.institution_account_admissions_v1")=="1",
      "Unexpected additional admission from session or scope switching")
    check(sql(args.db_url,"select count(*) from "
      "titus.institution_account_admission_withdrawals_v1")=="1",
      "Withdrawal did not preserve immutable original")
    check(sql(args.db_url,"select count(*) from auth.users")=="3",
      "Source minted an extra Auth user")
    Path(args.output).write_text(
      "PASS genuine local GoTrue + PostgREST U1 identity, issuer, consent, "
      "recipient privacy, replay, withdrawal and stale-session checks; "
      "NOT production-shaped or manager-establishment proof.\n",encoding="utf-8")
    print("PASS Titus U1 LOCAL real signed GoTrue verification; no production touched")


if __name__=="__main__":
    main()

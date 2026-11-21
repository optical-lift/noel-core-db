#!/usr/bin/env python3
"""Genuine GoTrue-signed bearer / PostgREST proof, on a disposable LOCAL DB only.

All Auth accounts and Course text are synthetic. This is NOT acceptance by the
real customer or an independently consenting second human. Never run remotely.
No tokens, passwords, Course bodies or personal identifiers enter job output.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import re
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request

READ="titus_customer_material_read_self_api_v1"
SAVE="titus_customer_material_save_self_api_v1"
UUID_RE=re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",re.I)
LOOPBACK={"127.0.0.1","localhost"}
OPENER=urllib.request.build_opener(urllib.request.ProxyHandler({}))

def check(ok, reason):
    if not ok: raise AssertionError(reason)

def sql(db, query):
    run=subprocess.run(["psql",db,"-X","-A","-t","-v","ON_ERROR_STOP=1","-c",query],
        capture_output=True,text=True,check=True)
    return run.stdout.strip()

def local_credentials():
    run=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=True)
    env={}
    for line in run.stdout.splitlines():
        if "=" in line:
            name,value=line.split("=",1)
            env[name.strip()]=value.strip().strip('"')
    api=env.get("API_URL","").rstrip("/")
    key=env.get("ANON_KEY") or env.get("SUPABASE_ANON_KEY")
    service=env.get("SERVICE_ROLE_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY")
    parsed=urllib.parse.urlparse(api)
    check(parsed.scheme=="http" and parsed.hostname in LOOPBACK and
          parsed.port is not None and parsed.username is None and
          parsed.password is None and parsed.path=="","Refuse nonlocal Auth API")
    check(bool(key and service),"Missing disposable local Auth keys")
    return api,key,service

def call(api,key,path,body,token=None):
    headers={"apikey":key,"Content-Type":"application/json","Accept":"application/json"}
    if token is not None:headers["Authorization"]="Bearer "+token
    req=urllib.request.Request(api+path,data=json.dumps(body).encode("utf-8"),
                               headers=headers,method="POST")
    try:
        with OPENER.open(req,timeout=25) as resp:
            raw=resp.read().decode("utf-8")
            return resp.status,json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw=exc.read().decode("utf-8")
        try: return exc.code,json.loads(raw) if raw else None
        except json.JSONDecodeError: return exc.code,None

def payload(token):
    try:
        segment=token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(segment+"="*(-len(segment)%4)))
    except Exception as e:raise AssertionError("Malformed locally signed Auth JWT") from e

def positive(api,key,token,name,data,label):
    status,result=call(api,key,"/rest/v1/rpc/"+name,data,token)
    check(status==200 and isinstance(result,dict),f"{label}: signed success failed HTTP {status}")
    return result

def negative(api,key,token,name,data,label,codes=("42501",)):
    status,result=call(api,key,"/rest/v1/rpc/"+name,data,token)
    check(status in (401,403,409,500) and isinstance(result,dict),
          f"{label}: expected source denial, observed HTTP {status}")
    check(result.get("code") in codes,
          f"{label}: wrong denial type {result.get('code')}; never accept missing RPC")
    print("PASS",label)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(re.fullmatch(r"postgres(ql)?://postgres:postgres@127[.]0[.]0[.]1:[0-9]{2,5}/postgres",
                       args.db_url) is not None,"Refuse nonlocal or privileged production database")
    # Docker port forwarding uses a localhost client address even if the
    # server reports its internal bridge IP. The exact db-url regex above,
    # not inet_server_addr(), is the remote-destination prevention boundary.
    check(sql(args.db_url,"SELECT current_database()")=="postgres",
          "Unexpected disposable local database")
    api,key,service=local_credentials()
    suffix=secrets.token_hex(5)
    password=secrets.token_urlsafe(26)
    users={}
    for role in ("owner_a","owner_b","outsider"):
        address=f"titus-signed-{role}-{suffix}@example.invalid"
        status,result=call(api,service,"/auth/v1/admin/users",
            {"email":address,"password":password,"email_confirm":True},service)
        check(status in (200,201) and isinstance(result,dict) and
              UUID_RE.fullmatch(str(result.get("id",""))) is not None,
              f"{role}: local GoTrue test-account creation failed: HTTP {status}")
        uid=result["id"]
        status,login=call(api,key,"/auth/v1/token?grant_type=password",
                          {"email":address,"password":password})
        check(status==200 and isinstance(login,dict) and
              isinstance(login.get("access_token"),str),
              f"{role}: genuine GoTrue login failed: HTTP {status}")
        token=login["access_token"];claims=payload(token)
        sid=claims.get("session_id")
        check(claims.get("role")=="authenticated" and claims.get("sub")==uid and
              isinstance(sid,str) and UUID_RE.fullmatch(sid) is not None,
              f"{role}: invalid signed session claims")
        check(sql(args.db_url,f"SELECT count(*) FROM auth.sessions WHERE id='{sid}'::uuid "
                    f"AND user_id='{uid}'::uuid")=="1",
              f"{role}: GoTrue session not persisted in local Auth")
        users[role]={"id":uid,"token":token,"sid":sid,"email":address}
    print("PASS three independent, genuinely signed local GoTrue sessions")

    a=users["owner_a"];b=users["owner_b"];outsider=users["outsider"]
    for item in (a,b):
        receipt="synthetic-local-test-"+secrets.token_hex(10)
        sql(args.db_url,"INSERT INTO titus.customer_workspace_entitlements_v1 "
            "(owner_auth_user_id,grant_kind,grant_source_receipt) "
            f"VALUES('{item['id']}'::uuid,'private_pilot','{receipt}')")
    negative(api,key,outsider["token"],"titus_customer_catalog_self_api_v1",{},
             "signed unentitled catalog denied")

    def create_course(actor,label):
        catalog=positive(api,key,actor["token"],"titus_customer_start_workspace_self_api_v1",
            {"p_title":"Isolated Signed Manuscript Workspace"},label+" workspace")
        check(catalog.get("courses")==[],label+": workspace must start with zero Courses")
        created=positive(api,key,actor["token"],"titus_customer_create_course_self_api_v1",
            {"p_request_id":secrets_uuid(),"p_title":"Isolated Test Course"},label+" Course")
        courses=created.get("courses")
        check(isinstance(courses,list) and len(courses)==1 and
              UUID_RE.fullmatch(str(courses[0].get("courseId",""))) is not None,
              label+": Course was not source-created")
        return courses[0]["courseId"]

    course_a=create_course(a,"A")
    course_b=create_course(b,"B")
    a_read={"p_course_id":course_a};b_read={"p_course_id":course_b}
    blank=positive(api,key,a["token"],READ,a_read,"A blank owned manuscript")
    check(blank.get("courseId")==course_a and blank.get("material") is None,
          "New original Course must have no seeded material")
    check(positive(api,key,b["token"],READ,b_read,"B own blank read").get("material") is None,
          "Independent owner B must be able to read own Course before revocation")
    for label,token in (("B",b["token"]),("unentitled",outsider["token"])):
        negative(api,key,token,READ,a_read,label+" read A's manuscript denied")
        negative(api,key,token,SAVE,{**a_read,"p_request_id":secrets_uuid(),
                 "p_expected_revision":0,"p_text":"Unauthorised attempt"},
                 label+" save A's manuscript denied")
    negative(api,key,None,READ,a_read,"anonymous manuscript read denied")
    negative(api,key,None,SAVE,{**a_read,"p_request_id":secrets_uuid(),
             "p_expected_revision":0,"p_text":"Unauthorized"},
             "anonymous manuscript save denied")
    print("PASS independent source-entitlement and Course-ownership isolation")

    body="Original synthetic signed local manuscript"
    attempt={"p_course_id":course_a,"p_request_id":secrets_uuid(),
             "p_expected_revision":0,"p_text":body}
    first=positive(api,key,a["token"],SAVE,attempt,"first signed original save")
    check(first.get("material",{}).get("revisionNumber")==1 and
          first["material"].get("text")==body,"First save did not persist")
    retry=positive(api,key,a["token"],SAVE,attempt,"idempotent same-receipt retry")
    check(retry.get("material",{}).get("revisionNumber")==1,"Retry duplicated revision")
    negative(api,key,a["token"],SAVE,{**attempt,"p_text":"Conflicting replay"},
             "changed same-receipt replay denied",("23505",))
    negative(api,key,a["token"],SAVE,{**attempt,"p_request_id":secrets_uuid(),
             "p_text":"Stale revision"},"stale expected revision denied",("40001",))
    check(positive(api,key,a["token"],READ,a_read,"reopen latest source").get("material",{}).get("text")==body,
          "Author failed to reopen exact source-written text")
    print("PASS signed first original, idempotent retry, stale/replay denials")

    status,login2=call(api,key,"/auth/v1/token?grant_type=password",
                       {"email":a["email"],"password":password})
    check(status==200 and isinstance(login2,dict) and login2.get("access_token"),
          "Independent second owner GoTrue login missing")
    token2=login2["access_token"];claims2=payload(token2)
    check(claims2.get("session_id")!=a["sid"] and
          claims2.get("sub")==a["id"],"Second signed session not independent")
    check(positive(api,key,token2,READ,a_read,"reopen on second signed session")
            .get("material",{}).get("text")==body,"Cross-session reopen disagreed")
    raced=[
      {"p_course_id":course_a,"p_request_id":secrets_uuid(),
       "p_expected_revision":1,"p_text":"Concurrent isolated source A"},
      {"p_course_id":course_a,"p_request_id":secrets_uuid(),
       "p_expected_revision":1,"p_text":"Concurrent isolated source B"},
    ]
    with ThreadPoolExecutor(max_workers=2) as ex:
        p1=ex.submit(call,api,key,"/rest/v1/rpc/"+SAVE,raced[0],a["token"])
        p2=ex.submit(call,api,key,"/rest/v1/rpc/"+SAVE,raced[1],token2)
        results=[p1.result(),p2.result()]
    accepted=[(i,v) for i,(status,v) in enumerate(results) if status==200]
    denied=[v for status,v in results if status in (409,500) and
            isinstance(v,dict) and v.get("code")=="40001"]
    check(len(accepted)==1 and len(denied)==1,"Concurrent expected revision must yield exactly one winner")
    latest=positive(api,key,a["token"],READ,a_read,"concurrent exact reopen")
    check(latest.get("material",{}).get("revisionNumber")==2 and
          latest["material"].get("text")==raced[accepted[0][0]]["p_text"],
          "Concurrent outcome was not one exact append-only original")
    count=sql(args.db_url,f"SELECT count(*) FROM titus.customer_course_material_revisions_v1 "
                           f"WHERE course_id='{course_a}'::uuid")
    check(count=="2","Concurrent writes created duplicate Course revisions")
    print("PASS independent signed-session concurrency, exactly one writer")

    bfirst=positive(api,key,b["token"],SAVE,{**b_read,
       "p_request_id":secrets_uuid(),"p_expected_revision":0,
       "p_text":"B independent private synthetic text"},"B owned pre-revocation save")
    check(bfirst.get("material",{}).get("revisionNumber")==1,
          "B's valid pre-revocation own-course save failed")
    sql(args.db_url,f"UPDATE titus.customer_workspace_entitlements_v1 SET state='revoked' "
                    f"WHERE owner_auth_user_id='{b['id']}'::uuid")
    negative(api,key,b["token"],READ,b_read,"revoked B's own Course read denied")
    negative(api,key,b["token"],SAVE,{**b_read,"p_request_id":secrets_uuid(),
       "p_expected_revision":1,"p_text":"Denied after revocation"},
       "revoked B's own Course save denied")
    check(positive(api,key,a["token"],READ,a_read,"A remains authorized")
          .get("material",{}).get("revisionNumber")==2,
          "Revocation incorrectly affected unrelated A")
    print("PASS real local signed entitlement withdrawal, own Course denied")

    sid2=claims2["session_id"]
    check(UUID_RE.fullmatch(sid2) is not None,"Refuse invalid signed session UUID")
    sql(args.db_url,f"UPDATE auth.sessions SET not_after=now()-interval '1 minute' "
                    f"WHERE id='{sid2}'::uuid AND user_id='{a['id']}'::uuid")
    negative(api,key,token2,READ,a_read,"expired A own Course read denied")
    negative(api,key,token2,SAVE,{**a_read,"p_request_id":secrets_uuid(),
       "p_expected_revision":2,"p_text":"Expired session write"},
       "expired A own Course save denied")
    check(positive(api,key,a["token"],READ,a_read,"unexpired A session still valid")
          .get("material",{}).get("revisionNumber")==2,"Expired second session revoked the first")
    check(sql(args.db_url,"SELECT count(*) FROM titus.customer_course_material_revisions_v1")=="3",
          "Failed denials created material revisions")
    with open(args.output,"w",encoding="utf-8") as out:
        out.write(json.dumps({"scope":"disposable-local-only","goTrueSessions":4,
            "signedSource":"PASS","courseCount":2,"revisionCount":3,
            "realUserAcceptance":False,"productionWrites":False},sort_keys=True)+"\n")
    print("PASS local GoTrue and PostgREST manuscript acceptance: no production data or real user claims")

def secrets_uuid():
    import uuid
    return str(uuid.uuid4())

if __name__=="__main__":main()
